//! 1inch Fusion API Client
//!
//! Implements the 1inch Fusion API for swap quotes and transactions.
//! API Documentation: https://portal.1inch.dev/documentation/swap/swagger
//!
//! Supported chains:
//! - Ethereum (1)
//! - BNB Chain (56)
//! - Polygon (137)
//! - Arbitrum (42161)
//! - Optimism (10)
//! - Avalanche (43114)
//! - Base (8453)
//! - Fantom (250)

use serde::Deserialize;
use crate::types::Chain;
use crate::error::{HawalaError, HawalaResult};
use super::types::*;

/// 1inch API base URL
const ONEINCH_API_BASE: &str = "https://api.1inch.dev/swap/v6.0";

/// 1inch API client
#[allow(dead_code)]
pub struct OneInchClient {
    /// API key (optional but recommended for higher rate limits)
    api_key: Option<String>,
    /// HTTP client timeout in seconds
    timeout_seconds: u64,
}

impl OneInchClient {
    /// Create a new 1inch client
    pub fn new(api_key: Option<String>) -> Self {
        Self {
            api_key,
            timeout_seconds: 10,
        }
    }

    /// Get chain ID for 1inch API
    fn get_chain_id(chain: Chain) -> Option<u64> {
        match chain {
            Chain::Ethereum => Some(1),
            Chain::Bnb => Some(56),
            Chain::Polygon => Some(137),
            Chain::Arbitrum => Some(42161),
            Chain::Optimism => Some(10),
            Chain::Avalanche => Some(43114),
            Chain::Base => Some(8453),
            Chain::Fantom => Some(250),
            _ => None,
        }
    }

    /// Check if chain is supported
    pub fn is_chain_supported(chain: Chain) -> bool {
        Self::get_chain_id(chain).is_some()
    }

    /// Get a swap quote from 1inch
    pub fn get_quote(&self, request: &SwapQuoteRequest) -> HawalaResult<SwapQuote> {
        let chain_id = Self::get_chain_id(request.chain)
            .ok_or_else(|| HawalaError::invalid_input(format!(
                "Chain {:?} not supported by 1inch", request.chain
            )))?;

        // Build quote URL
        let _quote_url = format!(
            "{}/{}/quote?src={}&dst={}&amount={}&includeGas=true",
            ONEINCH_API_BASE,
            chain_id,
            request.from_token,
            request.to_token,
            request.amount,
        );

        // In production, this would make an HTTP request
        // For now, return a mock quote structure
        let quote = self.fetch_quote_internal(chain_id, request)?;
        Ok(quote)
    }

    /// Get a swap quote with transaction data
    pub fn get_swap(&self, request: &SwapQuoteRequest) -> HawalaResult<SwapQuote> {
        let chain_id = Self::get_chain_id(request.chain)
            .ok_or_else(|| HawalaError::invalid_input(format!(
                "Chain {:?} not supported by 1inch", request.chain
            )))?;

        // Validate slippage
        if request.slippage > 50.0 {
            return Err(HawalaError::invalid_input(
                "Slippage cannot exceed 50%".to_string()
            ));
        }

        // Build swap URL
        let _swap_url = format!(
            "{}/{}/swap?src={}&dst={}&amount={}&from={}&slippage={}&includeGas=true",
            ONEINCH_API_BASE,
            chain_id,
            request.from_token,
            request.to_token,
            request.amount,
            request.from_address,
            request.slippage,
        );

        // In production, this would make an HTTP request
        let quote = self.fetch_swap_internal(chain_id, request)?;
        Ok(quote)
    }

    /// Check token approval status
    pub fn check_approval(&self, chain: Chain, token: &str, _wallet: &str) -> HawalaResult<TokenApproval> {
        let chain_id = Self::get_chain_id(chain)
            .ok_or_else(|| HawalaError::invalid_input(format!(
                "Chain {:?} not supported by 1inch", chain
            )))?;

        // 1inch router addresses by chain
        let spender = self.get_router_address(chain_id);

        // In production, would check on-chain allowance
        Ok(TokenApproval {
            token: token.to_string(),
            spender,
            current_allowance: "0".to_string(),
            required_allowance: "115792089237316195423570985008687907853269984665640564039457584007913129639935".to_string(), // uint256 max
            needs_approval: true,
            approval_tx: None,
        })
    }

    /// Get approval transaction
    pub fn get_approval_tx(&self, chain: Chain, token: &str, amount: Option<&str>) -> HawalaResult<SwapTransaction> {
        let chain_id = Self::get_chain_id(chain)
            .ok_or_else(|| HawalaError::invalid_input(format!(
                "Chain {:?} not supported by 1inch", chain
            )))?;

        let spender = self.get_router_address(chain_id);
        let approval_amount = amount.unwrap_or(
            "115792089237316195423570985008687907853269984665640564039457584007913129639935"
        );

        // Build approve calldata: approve(address spender, uint256 amount)
        let calldata = format!(
            "0x095ea7b3{:0>64}{:0>64}",
            &spender[2..], // Remove 0x prefix, pad to 32 bytes
            format!("{:x}", approval_amount.parse::<u128>().unwrap_or(u128::MAX))
        );

        Ok(SwapTransaction {
            to: token.to_string(),
            data: calldata,
            value: "0".to_string(),
            gas_limit: "50000".to_string(),
            gas_price: None,
            max_fee_per_gas: None,
            max_priority_fee_per_gas: None,
        })
    }

    /// Get 1inch router address for chain
    fn get_router_address(&self, chain_id: u64) -> String {
        // 1inch v6 Aggregation Router addresses
        match chain_id {
            1 => "0x111111125421cA6dc452d289314280a0f8842A65".to_string(),      // Ethereum
            56 => "0x111111125421cA6dc452d289314280a0f8842A65".to_string(),     // BSC
            137 => "0x111111125421cA6dc452d289314280a0f8842A65".to_string(),    // Polygon
            42161 => "0x111111125421cA6dc452d289314280a0f8842A65".to_string(),  // Arbitrum
            10 => "0x111111125421cA6dc452d289314280a0f8842A65".to_string(),     // Optimism
            43114 => "0x111111125421cA6dc452d289314280a0f8842A65".to_string(),  // Avalanche
            8453 => "0x111111125421cA6dc452d289314280a0f8842A65".to_string(),   // Base
            250 => "0x111111125421cA6dc452d289314280a0f8842A65".to_string(),    // Fantom
            _ => "0x111111125421cA6dc452d289314280a0f8842A65".to_string(),
        }
    }

    /// Internal: fetch quote (mock implementation)
    fn fetch_quote_internal(&self, chain_id: u64, request: &SwapQuoteRequest) -> HawalaResult<SwapQuote> {
        // Calculate expiry (30 seconds from now)
        let expires_at = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() + 30;

        // Mock token data - in production, this comes from the API
        let (from_symbol, from_decimals) = self.get_token_info(&request.from_token, chain_id);
        let (to_symbol, to_decimals) = self.get_token_info(&request.to_token, chain_id);

        // Mock output calculation (in production, this is from DEX routing)
        let from_amount: u128 = request.amount.parse().unwrap_or(0);
        let mock_rate = self.get_mock_rate(&request.from_token, &request.to_token);
        let to_amount = (from_amount as f64 * mock_rate) as u128;
        let to_amount_min = (to_amount as f64 * (1.0 - request.slippage / 100.0)) as u128;

        Ok(SwapQuote {
            provider: DEXProvider::OneInch,
            chain: request.chain,
            from_token: request.from_token.clone(),
            from_token_symbol: from_symbol.clone(),
            from_token_decimals: from_decimals,
            to_token: request.to_token.clone(),
            to_token_symbol: to_symbol.clone(),
            to_token_decimals: to_decimals,
            from_amount: request.amount.clone(),
            to_amount: to_amount.to_string(),
            to_amount_min: to_amount_min.to_string(),
            estimated_gas: "150000".to_string(),
            gas_price_gwei: request.gas_price_gwei.unwrap_or(30.0),
            gas_cost_usd: Some(5.0), // Mock gas cost
            price_impact: -0.1,      // Mock price impact
            routes: vec![
                SwapRoute {
                    protocol: "Uniswap V3".to_string(),
                    percentage: 100.0,
                    path: vec![
                        RouteToken {
                            address: request.from_token.clone(),
                            symbol: from_symbol,
                            decimals: from_decimals,
                        },
                        RouteToken {
                            address: request.to_token.clone(),
                            symbol: to_symbol,
                            decimals: to_decimals,
                        },
                    ],
                },
            ],
            expires_at,
            tx: None,
        })
    }

    /// Internal: fetch swap with tx data (mock implementation)
    fn fetch_swap_internal(&self, chain_id: u64, request: &SwapQuoteRequest) -> HawalaResult<SwapQuote> {
        let mut quote = self.fetch_quote_internal(chain_id, request)?;
        
        // Add transaction data
        let router = self.get_router_address(chain_id);
        let is_native = request.from_token.to_lowercase() == SwapQuoteRequest::NATIVE_ETH.to_lowercase();
        
        quote.tx = Some(SwapTransaction {
            to: router,
            data: "0x12345678".to_string(), // Mock calldata
            value: if is_native { request.amount.clone() } else { "0".to_string() },
            gas_limit: "250000".to_string(),
            gas_price: None,
            max_fee_per_gas: Some("50000000000".to_string()), // 50 gwei
            max_priority_fee_per_gas: Some("2000000000".to_string()), // 2 gwei
        });

        Ok(quote)
    }

    /// Get token info (mock - in production, use token list or API)
    fn get_token_info(&self, address: &str, _chain_id: u64) -> (String, u8) {
        let addr_lower = address.to_lowercase();
        
        // Native token
        if addr_lower == SwapQuoteRequest::NATIVE_ETH.to_lowercase() {
            return ("ETH".to_string(), 18);
        }

        // Common tokens
        match addr_lower.as_str() {
            "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48" => ("USDC".to_string(), 6),
            "0xdac17f958d2ee523a2206206994597c13d831ec7" => ("USDT".to_string(), 6),
            "0x6b175474e89094c44da98b954eedeac495271d0f" => ("DAI".to_string(), 18),
            "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2" => ("WETH".to_string(), 18),
            "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599" => ("WBTC".to_string(), 8),
            _ => ("TOKEN".to_string(), 18),
        }
    }

    /// Get mock exchange rate (for development)
    fn get_mock_rate(&self, from: &str, to: &str) -> f64 {
        let from_lower = from.to_lowercase();
        let to_lower = to.to_lowercase();

        // ETH -> USDC
        if from_lower == SwapQuoteRequest::NATIVE_ETH.to_lowercase() 
            && to_lower == "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48" {
            return 3000.0 * 1e6 / 1e18; // 3000 USDC per ETH (adjusting for decimals)
        }

        // USDC -> ETH
        if from_lower == "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
            && to_lower == SwapQuoteRequest::NATIVE_ETH.to_lowercase() {
            return 1e18 / (3000.0 * 1e6); // 1/3000 ETH per USDC
        }

        // Default 1:1 for unknown pairs
        1.0
    }
}

/// 1inch API response types
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct OneInchQuoteResponse {
    #[serde(rename = "srcToken")]
    pub src_token: OneInchToken,
    #[serde(rename = "dstToken")]
    pub dst_token: OneInchToken,
    #[serde(rename = "srcAmount")]
    pub src_amount: String,
    #[serde(rename = "dstAmount")]
    pub dst_amount: String,
    pub gas: Option<u64>,
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct OneInchToken {
    pub address: String,
    pub symbol: String,
    pub name: String,
    pub decimals: u8,
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct OneInchSwapResponse {
    #[serde(rename = "srcToken")]
    pub src_token: OneInchToken,
    #[serde(rename = "dstToken")]
    pub dst_token: OneInchToken,
    #[serde(rename = "srcAmount")]
    pub src_amount: String,
    #[serde(rename = "dstAmount")]
    pub dst_amount: String,
    pub tx: OneInchTx,
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct OneInchTx {
    pub from: String,
    pub to: String,
    pub data: String,
    pub value: String,
    pub gas: u64,
    #[serde(rename = "gasPrice")]
    pub gas_price: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_oneinch_chain_support() {
        assert!(OneInchClient::is_chain_supported(Chain::Ethereum));
        assert!(OneInchClient::is_chain_supported(Chain::Polygon));
        assert!(OneInchClient::is_chain_supported(Chain::Arbitrum));
        assert!(!OneInchClient::is_chain_supported(Chain::Bitcoin));
        assert!(!OneInchClient::is_chain_supported(Chain::Solana));
    }

    #[test]
    fn test_get_quote() {
        let client = OneInchClient::new(None);
        let request = SwapQuoteRequest {
            chain: Chain::Ethereum,
            from_token: SwapQuoteRequest::NATIVE_ETH.to_string(),
            to_token: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48".to_string(),
            amount: "1000000000000000000".to_string(), // 1 ETH
            slippage: 0.5,
            from_address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
            provider: None,
            deadline_seconds: None,
            referrer: None,
            gas_price_gwei: None,
        };

        let quote = client.get_quote(&request).unwrap();
        assert_eq!(quote.provider, DEXProvider::OneInch);
        assert_eq!(quote.chain, Chain::Ethereum);
        assert_eq!(quote.from_token_symbol, "ETH");
        assert_eq!(quote.to_token_symbol, "USDC");
        assert!(!quote.to_amount.is_empty());
    }

    #[test]
    fn test_get_swap_with_tx() {
        let client = OneInchClient::new(None);
        let request = SwapQuoteRequest {
            chain: Chain::Polygon,
            from_token: SwapQuoteRequest::NATIVE_ETH.to_string(),
            to_token: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174".to_string(), // USDC on Polygon
            amount: "1000000000000000000".to_string(),
            slippage: 1.0,
            from_address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
            provider: None,
            deadline_seconds: None,
            referrer: None,
            gas_price_gwei: Some(50.0),
        };

        let quote = client.get_swap(&request).unwrap();
        assert!(quote.tx.is_some());
        let tx = quote.tx.unwrap();
        assert!(!tx.to.is_empty());
        assert!(!tx.data.is_empty());
    }

    #[test]
    fn test_router_addresses() {
        let client = OneInchClient::new(None);
        let eth_router = client.get_router_address(1);
        let polygon_router = client.get_router_address(137);
        
        // All v6 routers should be the same address
        assert_eq!(eth_router, polygon_router);
        assert!(eth_router.starts_with("0x111111"));
    }
}
