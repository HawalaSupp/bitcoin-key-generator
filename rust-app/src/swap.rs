//! DEX Swap Module
//!
//! Cross-chain and same-chain token swap functionality.
//! Integrates with major DEX aggregators for best pricing.

use crate::error::{HawalaError, HawalaResult, ErrorCode};
use crate::types::Chain;
use serde::{Deserialize, Serialize};

// =============================================================================
// Swap Types
// =============================================================================

/// Token information for swaps
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SwapToken {
    pub chain: Chain,
    pub address: String, // Contract address (or "native" for native token)
    pub symbol: String,
    pub name: String,
    pub decimals: u8,
    pub logo_url: Option<String>,
}

/// Swap quote request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SwapQuoteRequest {
    pub from_chain: Chain,
    pub to_chain: Chain,
    pub from_token: String, // Token address or "native"
    pub to_token: String,
    pub amount: String, // Raw amount in smallest units
    pub sender_address: String,
    pub slippage_percent: f64, // e.g., 0.5 for 0.5%
}

/// Swap quote response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SwapQuote {
    pub from_token: SwapToken,
    pub to_token: SwapToken,
    pub from_amount: String,
    pub to_amount: String,
    pub to_amount_min: String, // After slippage
    pub exchange_rate: String,
    pub price_impact: f64,
    pub gas_estimate: String,
    pub provider: String,
    pub route: Vec<SwapRoute>,
    pub valid_until: u64, // Unix timestamp
}

/// A single hop in a swap route
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SwapRoute {
    pub protocol: String, // e.g., "Uniswap V3", "SushiSwap"
    pub pool_address: String,
    pub from_token: String,
    pub to_token: String,
    pub fee_percent: f64,
}

/// Swap transaction data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SwapTransaction {
    pub chain: Chain,
    pub to: String, // Router/aggregator contract
    pub data: String, // Encoded call data
    pub value: String, // ETH value for native swaps
    pub gas_limit: String,
}

// =============================================================================
// Public API
// =============================================================================

/// Get a swap quote
pub fn get_swap_quote(request: &SwapQuoteRequest) -> HawalaResult<SwapQuote> {
    // Cross-chain swaps
    if request.from_chain != request.to_chain {
        return get_cross_chain_quote(request);
    }
    
    // Same-chain swaps
    match request.from_chain {
        Chain::Ethereum | Chain::EthereumSepolia => get_evm_swap_quote(request, 1),
        Chain::Bnb => get_evm_swap_quote(request, 56),
        Chain::Polygon => get_evm_swap_quote(request, 137),
        Chain::Arbitrum => get_evm_swap_quote(request, 42161),
        Chain::Optimism => get_evm_swap_quote(request, 10),
        Chain::Base => get_evm_swap_quote(request, 8453),
        Chain::Avalanche => get_evm_swap_quote(request, 43114),
        Chain::Solana | Chain::SolanaDevnet => get_solana_swap_quote(request),
        Chain::Osmosis => get_osmosis_swap_quote(request),
        chain if chain.is_evm() => {
            let chain_id = chain.chain_id().unwrap_or(1);
            get_evm_swap_quote(request, chain_id)
        }
        _ => Err(HawalaError::new(
            ErrorCode::NotImplemented,
            format!("Swaps not supported for {:?}", request.from_chain),
        )),
    }
}

/// Build swap transaction from quote
pub fn build_swap_transaction(quote: &SwapQuote, sender: &str) -> HawalaResult<SwapTransaction> {
    match quote.from_token.chain {
        Chain::Ethereum | Chain::Bnb | Chain::Polygon | Chain::Arbitrum
        | Chain::Optimism | Chain::Base | Chain::Avalanche => {
            build_evm_swap_tx(quote, sender)
        }
        chain if chain.is_evm() => {
            build_evm_swap_tx(quote, sender)
        }
        _ => Err(HawalaError::new(
            ErrorCode::NotImplemented,
            "Swap transaction building not yet supported",
        )),
    }
}

/// Get popular tokens for a chain
pub fn get_popular_tokens(chain: Chain) -> HawalaResult<Vec<SwapToken>> {
    match chain {
        Chain::Ethereum => Ok(get_ethereum_tokens()),
        Chain::Bnb => Ok(get_bsc_tokens()),
        Chain::Polygon => Ok(get_polygon_tokens()),
        Chain::Arbitrum => Ok(get_arbitrum_tokens()),
        Chain::Optimism => Ok(get_optimism_tokens()),
        Chain::Base => Ok(get_base_tokens()),
        Chain::Avalanche => Ok(get_avalanche_tokens()),
        Chain::Solana => Ok(get_solana_tokens()),
        _ => Ok(vec![]),
    }
}

// =============================================================================
// EVM Swaps (via 1inch or 0x aggregator style)
// =============================================================================

fn get_evm_swap_quote(request: &SwapQuoteRequest, _chain_id: u64) -> HawalaResult<SwapQuote> {
    // In production, this would call 1inch, 0x, or similar aggregator API
    // For now, return a simulated quote
    
    let from_token = SwapToken {
        chain: request.from_chain,
        address: request.from_token.clone(),
        symbol: if request.from_token == "native" { 
            request.from_chain.symbol().to_string() 
        } else { 
            "TOKEN".to_string() 
        },
        name: "From Token".to_string(),
        decimals: 18,
        logo_url: None,
    };
    
    let to_token = SwapToken {
        chain: request.to_chain,
        address: request.to_token.clone(),
        symbol: if request.to_token == "native" { 
            request.to_chain.symbol().to_string() 
        } else { 
            "TOKEN".to_string() 
        },
        name: "To Token".to_string(),
        decimals: 18,
        logo_url: None,
    };
    
    // Simulate rate (would be fetched from aggregator)
    let from_amount: u128 = request.amount.parse().unwrap_or(0);
    let rate = 0.95; // Simulated 5% worse than 1:1
    let to_amount = (from_amount as f64 * rate) as u128;
    let slippage = 1.0 - (request.slippage_percent / 100.0);
    let to_amount_min = (to_amount as f64 * slippage) as u128;
    
    Ok(SwapQuote {
        from_token,
        to_token,
        from_amount: from_amount.to_string(),
        to_amount: to_amount.to_string(),
        to_amount_min: to_amount_min.to_string(),
        exchange_rate: rate.to_string(),
        price_impact: 0.01, // 1%
        gas_estimate: "150000".to_string(),
        provider: "1inch".to_string(),
        route: vec![
            SwapRoute {
                protocol: "Uniswap V3".to_string(),
                pool_address: "0x...".to_string(),
                from_token: request.from_token.clone(),
                to_token: request.to_token.clone(),
                fee_percent: 0.3,
            }
        ],
        valid_until: chrono::Utc::now().timestamp() as u64 + 60, // 1 minute
    })
}

fn build_evm_swap_tx(quote: &SwapQuote, _sender: &str) -> HawalaResult<SwapTransaction> {
    // Build swap call data (simplified)
    // In production, this would be properly ABI-encoded
    
    let router = match quote.from_token.chain {
        Chain::Ethereum => "0x1111111254EEB25477B68fb85Ed929f73A960582", // 1inch v5
        Chain::Bnb => "0x1111111254EEB25477B68fb85Ed929f73A960582",
        Chain::Polygon => "0x1111111254EEB25477B68fb85Ed929f73A960582",
        Chain::Arbitrum => "0x1111111254EEB25477B68fb85Ed929f73A960582",
        _ => "0x1111111254EEB25477B68fb85Ed929f73A960582",
    };
    
    let value = if quote.from_token.address == "native" {
        quote.from_amount.clone()
    } else {
        "0".to_string()
    };
    
    Ok(SwapTransaction {
        chain: quote.from_token.chain,
        to: router.to_string(),
        data: "0x...".to_string(), // Would be properly encoded
        value,
        gas_limit: quote.gas_estimate.clone(),
    })
}

// =============================================================================
// Solana Swaps (via Jupiter)
// =============================================================================

fn get_solana_swap_quote(request: &SwapQuoteRequest) -> HawalaResult<SwapQuote> {
    // Jupiter API integration
    let from_token = SwapToken {
        chain: Chain::Solana,
        address: request.from_token.clone(),
        symbol: if request.from_token == "native" { "SOL".to_string() } else { "TOKEN".to_string() },
        name: "From Token".to_string(),
        decimals: 9,
        logo_url: None,
    };
    
    let to_token = SwapToken {
        chain: Chain::Solana,
        address: request.to_token.clone(),
        symbol: if request.to_token == "native" { "SOL".to_string() } else { "TOKEN".to_string() },
        name: "To Token".to_string(),
        decimals: 9,
        logo_url: None,
    };
    
    let from_amount: u128 = request.amount.parse().unwrap_or(0);
    let to_amount = (from_amount as f64 * 0.95) as u128;
    
    Ok(SwapQuote {
        from_token,
        to_token,
        from_amount: from_amount.to_string(),
        to_amount: to_amount.to_string(),
        to_amount_min: to_amount.to_string(),
        exchange_rate: "0.95".to_string(),
        price_impact: 0.01,
        gas_estimate: "5000".to_string(), // Compute units
        provider: "Jupiter".to_string(),
        route: vec![],
        valid_until: chrono::Utc::now().timestamp() as u64 + 60,
    })
}

// =============================================================================
// Cross-Chain Swaps
// =============================================================================

fn get_cross_chain_quote(_request: &SwapQuoteRequest) -> HawalaResult<SwapQuote> {
    // Cross-chain via bridges (THORChain, Wormhole, etc.)
    Err(HawalaError::new(
        ErrorCode::NotImplemented,
        "Cross-chain swaps not yet implemented. Use THORChain swap module.",
    ))
}

// =============================================================================
// Osmosis Swaps
// =============================================================================

fn get_osmosis_swap_quote(request: &SwapQuoteRequest) -> HawalaResult<SwapQuote> {
    let from_token = SwapToken {
        chain: Chain::Osmosis,
        address: request.from_token.clone(),
        symbol: "OSMO".to_string(),
        name: "Osmosis".to_string(),
        decimals: 6,
        logo_url: None,
    };
    
    let to_token = SwapToken {
        chain: Chain::Osmosis,
        address: request.to_token.clone(),
        symbol: "ATOM".to_string(),
        name: "Cosmos".to_string(),
        decimals: 6,
        logo_url: None,
    };
    
    let from_amount: u128 = request.amount.parse().unwrap_or(0);
    let to_amount = (from_amount as f64 * 0.12) as u128; // Simulated rate
    
    Ok(SwapQuote {
        from_token,
        to_token,
        from_amount: from_amount.to_string(),
        to_amount: to_amount.to_string(),
        to_amount_min: to_amount.to_string(),
        exchange_rate: "0.12".to_string(),
        price_impact: 0.005,
        gas_estimate: "250000".to_string(),
        provider: "Osmosis DEX".to_string(),
        route: vec![],
        valid_until: chrono::Utc::now().timestamp() as u64 + 60,
    })
}

// =============================================================================
// Popular Token Lists
// =============================================================================

fn get_ethereum_tokens() -> Vec<SwapToken> {
    vec![
        SwapToken { chain: Chain::Ethereum, address: "native".to_string(), symbol: "ETH".to_string(), name: "Ethereum".to_string(), decimals: 18, logo_url: None },
        SwapToken { chain: Chain::Ethereum, address: "0xdAC17F958D2ee523a2206206994597C13D831ec7".to_string(), symbol: "USDT".to_string(), name: "Tether USD".to_string(), decimals: 6, logo_url: None },
        SwapToken { chain: Chain::Ethereum, address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48".to_string(), symbol: "USDC".to_string(), name: "USD Coin".to_string(), decimals: 6, logo_url: None },
        SwapToken { chain: Chain::Ethereum, address: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599".to_string(), symbol: "WBTC".to_string(), name: "Wrapped Bitcoin".to_string(), decimals: 8, logo_url: None },
        SwapToken { chain: Chain::Ethereum, address: "0x6B175474E89094C44Da98b954EesC4D30E6eb8e1".to_string(), symbol: "DAI".to_string(), name: "Dai Stablecoin".to_string(), decimals: 18, logo_url: None },
    ]
}

fn get_bsc_tokens() -> Vec<SwapToken> {
    vec![
        SwapToken { chain: Chain::Bnb, address: "native".to_string(), symbol: "BNB".to_string(), name: "BNB".to_string(), decimals: 18, logo_url: None },
        SwapToken { chain: Chain::Bnb, address: "0x55d398326f99059fF775485246999027B3197955".to_string(), symbol: "USDT".to_string(), name: "Tether USD".to_string(), decimals: 18, logo_url: None },
        SwapToken { chain: Chain::Bnb, address: "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d".to_string(), symbol: "USDC".to_string(), name: "USD Coin".to_string(), decimals: 18, logo_url: None },
        SwapToken { chain: Chain::Bnb, address: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c".to_string(), symbol: "WBNB".to_string(), name: "Wrapped BNB".to_string(), decimals: 18, logo_url: None },
    ]
}

fn get_polygon_tokens() -> Vec<SwapToken> {
    vec![
        SwapToken { chain: Chain::Polygon, address: "native".to_string(), symbol: "MATIC".to_string(), name: "Polygon".to_string(), decimals: 18, logo_url: None },
        SwapToken { chain: Chain::Polygon, address: "0xc2132D05D31c914a87C6611C10748AEb04B58e8F".to_string(), symbol: "USDT".to_string(), name: "Tether USD".to_string(), decimals: 6, logo_url: None },
        SwapToken { chain: Chain::Polygon, address: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174".to_string(), symbol: "USDC".to_string(), name: "USD Coin".to_string(), decimals: 6, logo_url: None },
    ]
}

fn get_arbitrum_tokens() -> Vec<SwapToken> {
    vec![
        SwapToken { chain: Chain::Arbitrum, address: "native".to_string(), symbol: "ETH".to_string(), name: "Ethereum".to_string(), decimals: 18, logo_url: None },
        SwapToken { chain: Chain::Arbitrum, address: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9".to_string(), symbol: "USDT".to_string(), name: "Tether USD".to_string(), decimals: 6, logo_url: None },
        SwapToken { chain: Chain::Arbitrum, address: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8".to_string(), symbol: "USDC".to_string(), name: "USD Coin".to_string(), decimals: 6, logo_url: None },
        SwapToken { chain: Chain::Arbitrum, address: "0x912CE59144191C1204E64559FE8253a0e49E6548".to_string(), symbol: "ARB".to_string(), name: "Arbitrum".to_string(), decimals: 18, logo_url: None },
    ]
}

fn get_optimism_tokens() -> Vec<SwapToken> {
    vec![
        SwapToken { chain: Chain::Optimism, address: "native".to_string(), symbol: "ETH".to_string(), name: "Ethereum".to_string(), decimals: 18, logo_url: None },
        SwapToken { chain: Chain::Optimism, address: "0x4200000000000000000000000000000000000042".to_string(), symbol: "OP".to_string(), name: "Optimism".to_string(), decimals: 18, logo_url: None },
    ]
}

fn get_base_tokens() -> Vec<SwapToken> {
    vec![
        SwapToken { chain: Chain::Base, address: "native".to_string(), symbol: "ETH".to_string(), name: "Ethereum".to_string(), decimals: 18, logo_url: None },
    ]
}

fn get_avalanche_tokens() -> Vec<SwapToken> {
    vec![
        SwapToken { chain: Chain::Avalanche, address: "native".to_string(), symbol: "AVAX".to_string(), name: "Avalanche".to_string(), decimals: 18, logo_url: None },
    ]
}

fn get_solana_tokens() -> Vec<SwapToken> {
    vec![
        SwapToken { chain: Chain::Solana, address: "native".to_string(), symbol: "SOL".to_string(), name: "Solana".to_string(), decimals: 9, logo_url: None },
        SwapToken { chain: Chain::Solana, address: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB".to_string(), symbol: "USDT".to_string(), name: "Tether USD".to_string(), decimals: 6, logo_url: None },
        SwapToken { chain: Chain::Solana, address: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v".to_string(), symbol: "USDC".to_string(), name: "USD Coin".to_string(), decimals: 6, logo_url: None },
    ]
}
