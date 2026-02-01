//! DEX Types and Data Structures

use serde::{Deserialize, Serialize};
use crate::types::Chain;

/// Supported DEX aggregator providers
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum DEXProvider {
    /// 1inch Fusion aggregator
    OneInch,
    /// 0x Protocol aggregator
    ZeroX,
    /// THORChain cross-chain swaps
    THORChain,
    /// Osmosis DEX (Cosmos)
    Osmosis,
    /// Uniswap direct
    Uniswap,
    /// Paraswap aggregator
    Paraswap,
}

impl DEXProvider {
    pub fn display_name(&self) -> &'static str {
        match self {
            DEXProvider::OneInch => "1inch",
            DEXProvider::ZeroX => "0x",
            DEXProvider::THORChain => "THORChain",
            DEXProvider::Osmosis => "Osmosis",
            DEXProvider::Uniswap => "Uniswap",
            DEXProvider::Paraswap => "Paraswap",
        }
    }

    pub fn supported_chains(&self) -> Vec<Chain> {
        match self {
            DEXProvider::OneInch => vec![
                Chain::Ethereum,
                Chain::Bnb,
                Chain::Polygon,
                Chain::Arbitrum,
                Chain::Optimism,
                Chain::Avalanche,
                Chain::Base,
                Chain::Fantom,
            ],
            DEXProvider::ZeroX => vec![
                Chain::Ethereum,
                Chain::Bnb,
                Chain::Polygon,
                Chain::Arbitrum,
                Chain::Optimism,
                Chain::Avalanche,
                Chain::Base,
            ],
            DEXProvider::THORChain => vec![
                Chain::Bitcoin,
                Chain::Ethereum,
                Chain::Bnb,
                Chain::Avalanche,
                Chain::Cosmos,
                Chain::Litecoin,
                Chain::BitcoinCash,
                Chain::Dogecoin,
            ],
            DEXProvider::Osmosis => vec![
                Chain::Osmosis,
                Chain::Cosmos,
            ],
            DEXProvider::Uniswap => vec![
                Chain::Ethereum,
                Chain::Polygon,
                Chain::Arbitrum,
                Chain::Optimism,
                Chain::Base,
            ],
            DEXProvider::Paraswap => vec![
                Chain::Ethereum,
                Chain::Bnb,
                Chain::Polygon,
                Chain::Arbitrum,
                Chain::Optimism,
                Chain::Avalanche,
            ],
        }
    }
}

/// Request for a swap quote
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SwapQuoteRequest {
    /// Blockchain network
    pub chain: Chain,
    /// Source token address (use native token placeholder for ETH/BNB/etc)
    pub from_token: String,
    /// Destination token address
    pub to_token: String,
    /// Amount to swap (in smallest unit, e.g., wei)
    pub amount: String,
    /// Slippage tolerance (0.5 = 0.5%)
    pub slippage: f64,
    /// Sender address
    pub from_address: String,
    /// Optional: specific provider to use
    pub provider: Option<DEXProvider>,
    /// Optional: custom deadline in seconds (default: 1200 = 20 minutes)
    pub deadline_seconds: Option<u64>,
    /// Optional: referrer address for fee sharing
    pub referrer: Option<String>,
    /// Optional: gas price in gwei (for gas estimation)
    pub gas_price_gwei: Option<f64>,
}

impl SwapQuoteRequest {
    /// Native token placeholder addresses
    pub const NATIVE_ETH: &'static str = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
    pub const NATIVE_BNB: &'static str = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
    pub const NATIVE_MATIC: &'static str = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
    pub const NATIVE_AVAX: &'static str = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

    pub fn chain_id(&self) -> u64 {
        self.chain.chain_id().unwrap_or(1)
    }
}

/// A single swap route/hop
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SwapRoute {
    /// Protocol name (e.g., "Uniswap V3", "Curve")
    pub protocol: String,
    /// Percentage of the swap going through this route
    pub percentage: f64,
    /// Token path for this route
    pub path: Vec<RouteToken>,
}

/// Token in a swap route
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RouteToken {
    pub address: String,
    pub symbol: String,
    pub decimals: u8,
}

/// Swap quote response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SwapQuote {
    /// Provider that generated this quote
    pub provider: DEXProvider,
    /// Chain for the swap
    pub chain: Chain,
    /// Source token address
    pub from_token: String,
    /// Source token symbol
    pub from_token_symbol: String,
    /// Source token decimals
    pub from_token_decimals: u8,
    /// Destination token address
    pub to_token: String,
    /// Destination token symbol
    pub to_token_symbol: String,
    /// Destination token decimals
    pub to_token_decimals: u8,
    /// Input amount (in smallest unit)
    pub from_amount: String,
    /// Expected output amount (in smallest unit)
    pub to_amount: String,
    /// Minimum output amount after slippage
    pub to_amount_min: String,
    /// Estimated gas cost (in native token units)
    pub estimated_gas: String,
    /// Gas price used for estimate (in gwei)
    pub gas_price_gwei: f64,
    /// Estimated gas cost in USD
    pub gas_cost_usd: Option<f64>,
    /// Price impact percentage (negative = worse price)
    pub price_impact: f64,
    /// Swap routes/paths
    pub routes: Vec<SwapRoute>,
    /// Quote expiry timestamp (Unix seconds)
    pub expires_at: u64,
    /// Ready-to-sign transaction data
    pub tx: Option<SwapTransaction>,
}

impl SwapQuote {
    /// Human-readable from amount
    pub fn from_amount_display(&self) -> String {
        format_token_amount(&self.from_amount, self.from_token_decimals)
    }

    /// Human-readable to amount
    pub fn to_amount_display(&self) -> String {
        format_token_amount(&self.to_amount, self.to_token_decimals)
    }

    /// Human-readable minimum to amount
    pub fn to_amount_min_display(&self) -> String {
        format_token_amount(&self.to_amount_min, self.to_token_decimals)
    }

    /// Exchange rate (to_amount / from_amount)
    pub fn exchange_rate(&self) -> f64 {
        let from = parse_token_amount(&self.from_amount, self.from_token_decimals);
        let to = parse_token_amount(&self.to_amount, self.to_token_decimals);
        if from > 0.0 { to / from } else { 0.0 }
    }

    /// Is this quote still valid?
    pub fn is_expired(&self) -> bool {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        now > self.expires_at
    }
}

/// Transaction data for executing a swap
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SwapTransaction {
    /// Contract address to call
    pub to: String,
    /// Calldata
    pub data: String,
    /// Value to send (for native token swaps)
    pub value: String,
    /// Gas limit
    pub gas_limit: String,
    /// Gas price in wei (optional, use for legacy tx)
    pub gas_price: Option<String>,
    /// Max fee per gas in wei (optional, use for EIP-1559)
    pub max_fee_per_gas: Option<String>,
    /// Max priority fee per gas in wei (optional, use for EIP-1559)
    pub max_priority_fee_per_gas: Option<String>,
}

/// Aggregated quotes from multiple providers
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AggregatedQuotes {
    /// All quotes received
    pub quotes: Vec<SwapQuote>,
    /// Best quote (highest output)
    pub best_quote: Option<SwapQuote>,
    /// Request that generated these quotes
    pub request: SwapQuoteRequest,
    /// Timestamp when quotes were fetched
    pub fetched_at: u64,
}

impl AggregatedQuotes {
    /// Get quote from a specific provider
    pub fn get_by_provider(&self, provider: DEXProvider) -> Option<&SwapQuote> {
        self.quotes.iter().find(|q| q.provider == provider)
    }

    /// Get quotes sorted by output amount (best first)
    pub fn sorted_by_output(&self) -> Vec<&SwapQuote> {
        let mut sorted: Vec<_> = self.quotes.iter().collect();
        sorted.sort_by(|a, b| {
            let a_amount = a.to_amount.parse::<u128>().unwrap_or(0);
            let b_amount = b.to_amount.parse::<u128>().unwrap_or(0);
            b_amount.cmp(&a_amount) // Descending
        });
        sorted
    }

    /// Get quotes sorted by gas cost (cheapest first)
    pub fn sorted_by_gas(&self) -> Vec<&SwapQuote> {
        let mut sorted: Vec<_> = self.quotes.iter().collect();
        sorted.sort_by(|a, b| {
            let a_gas = a.gas_cost_usd.unwrap_or(f64::MAX);
            let b_gas = b.gas_cost_usd.unwrap_or(f64::MAX);
            a_gas.partial_cmp(&b_gas).unwrap_or(std::cmp::Ordering::Equal)
        });
        sorted
    }
}

/// Token approval status
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TokenApproval {
    /// Token address
    pub token: String,
    /// Spender address (DEX router)
    pub spender: String,
    /// Current allowance
    pub current_allowance: String,
    /// Required allowance for swap
    pub required_allowance: String,
    /// Whether approval is needed
    pub needs_approval: bool,
    /// Approval transaction data (if needed)
    pub approval_tx: Option<SwapTransaction>,
}

/// Error types for DEX operations
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum DEXError {
    /// Provider returned an error
    ProviderError { provider: DEXProvider, message: String },
    /// No liquidity for this pair
    InsufficientLiquidity,
    /// Quote expired
    QuoteExpired,
    /// Unsupported chain for provider
    UnsupportedChain { chain: Chain, provider: DEXProvider },
    /// Unsupported token
    UnsupportedToken { token: String },
    /// Slippage too high
    SlippageTooHigh { requested: f64, max_allowed: f64 },
    /// Rate limit exceeded
    RateLimited { retry_after_seconds: u64 },
    /// Network error
    NetworkError(String),
    /// Invalid request
    InvalidRequest(String),
}

impl std::fmt::Display for DEXError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            DEXError::ProviderError { provider, message } => {
                write!(f, "{} error: {}", provider.display_name(), message)
            }
            DEXError::InsufficientLiquidity => write!(f, "Insufficient liquidity for this swap"),
            DEXError::QuoteExpired => write!(f, "Quote has expired"),
            DEXError::UnsupportedChain { chain, provider } => {
                write!(f, "{:?} not supported by {}", chain, provider.display_name())
            }
            DEXError::UnsupportedToken { token } => write!(f, "Unsupported token: {}", token),
            DEXError::SlippageTooHigh { requested, max_allowed } => {
                write!(f, "Slippage {}% exceeds max allowed {}%", requested, max_allowed)
            }
            DEXError::RateLimited { retry_after_seconds } => {
                write!(f, "Rate limited. Retry after {} seconds", retry_after_seconds)
            }
            DEXError::NetworkError(msg) => write!(f, "Network error: {}", msg),
            DEXError::InvalidRequest(msg) => write!(f, "Invalid request: {}", msg),
        }
    }
}

impl std::error::Error for DEXError {}

// Helper functions

fn format_token_amount(amount: &str, decimals: u8) -> String {
    let amount_u128: u128 = amount.parse().unwrap_or(0);
    let divisor = 10u128.pow(decimals as u32);
    let whole = amount_u128 / divisor;
    let frac = amount_u128 % divisor;
    
    if frac == 0 {
        whole.to_string()
    } else {
        let frac_str = format!("{:0>width$}", frac, width = decimals as usize);
        let trimmed = frac_str.trim_end_matches('0');
        format!("{}.{}", whole, trimmed)
    }
}

fn parse_token_amount(amount: &str, decimals: u8) -> f64 {
    let amount_u128: u128 = amount.parse().unwrap_or(0);
    let divisor = 10u128.pow(decimals as u32) as f64;
    amount_u128 as f64 / divisor
}

#[cfg(test)]
mod type_tests {
    use super::*;

    #[test]
    fn test_format_token_amount() {
        assert_eq!(format_token_amount("1000000000000000000", 18), "1");
        assert_eq!(format_token_amount("1500000000000000000", 18), "1.5");
        assert_eq!(format_token_amount("1000000", 6), "1");
        assert_eq!(format_token_amount("1500000", 6), "1.5");
        assert_eq!(format_token_amount("100000000", 8), "1");
    }

    #[test]
    fn test_parse_token_amount() {
        assert!((parse_token_amount("1000000000000000000", 18) - 1.0).abs() < 0.0001);
        assert!((parse_token_amount("1500000000000000000", 18) - 1.5).abs() < 0.0001);
        assert!((parse_token_amount("1000000", 6) - 1.0).abs() < 0.0001);
    }

    #[test]
    fn test_provider_supported_chains() {
        let oneinch_chains = DEXProvider::OneInch.supported_chains();
        assert!(oneinch_chains.contains(&Chain::Ethereum));
        assert!(oneinch_chains.contains(&Chain::Polygon));
        assert!(!oneinch_chains.contains(&Chain::Bitcoin));

        let thorchain_chains = DEXProvider::THORChain.supported_chains();
        assert!(thorchain_chains.contains(&Chain::Bitcoin));
        assert!(thorchain_chains.contains(&Chain::Ethereum));
    }

    #[test]
    fn test_swap_quote_exchange_rate() {
        let quote = SwapQuote {
            provider: DEXProvider::OneInch,
            chain: Chain::Ethereum,
            from_token: "ETH".to_string(),
            from_token_symbol: "ETH".to_string(),
            from_token_decimals: 18,
            to_token: "USDC".to_string(),
            to_token_symbol: "USDC".to_string(),
            to_token_decimals: 6,
            from_amount: "1000000000000000000".to_string(), // 1 ETH
            to_amount: "3000000000".to_string(),            // 3000 USDC
            to_amount_min: "2970000000".to_string(),        // 2970 USDC (1% slippage)
            estimated_gas: "150000".to_string(),
            gas_price_gwei: 30.0,
            gas_cost_usd: Some(5.0),
            price_impact: -0.1,
            routes: vec![],
            expires_at: 9999999999,
            tx: None,
        };

        assert!((quote.exchange_rate() - 3000.0).abs() < 0.01);
        assert_eq!(quote.from_amount_display(), "1");
        assert_eq!(quote.to_amount_display(), "3000");
    }
}
