//! 0x Protocol API Client
//!
//! Implements the 0x Swap API as a fallback aggregator.
//! API Documentation: https://0x.org/docs/api
//!
//! Supported chains:
//! - Ethereum (1)
//! - Polygon (137)
//! - BSC (56)
//! - Arbitrum (42161)
//! - Optimism (10)
//! - Avalanche (43114)
//! - Base (8453)

use serde::Deserialize;
use crate::types::Chain;
use crate::error::{HawalaError, HawalaResult};
use super::types::*;

/// 0x API base URLs by chain
const ZEROX_API_ETHEREUM: &str = "https://api.0x.org";
const ZEROX_API_POLYGON: &str = "https://polygon.api.0x.org";
const ZEROX_API_BSC: &str = "https://bsc.api.0x.org";
const ZEROX_API_ARBITRUM: &str = "https://arbitrum.api.0x.org";
const ZEROX_API_OPTIMISM: &str = "https://optimism.api.0x.org";
const ZEROX_API_AVALANCHE: &str = "https://avalanche.api.0x.org";
const ZEROX_API_BASE: &str = "https://base.api.0x.org";

/// 0x API client
#[allow(dead_code)]
pub struct ZeroXClient {
    /// API key (required for production)
    api_key: Option<String>,
    /// HTTP client timeout in seconds
    timeout_seconds: u64,
}

impl ZeroXClient {
    /// Create a new 0x client
    pub fn new(api_key: Option<String>) -> Self {
        Self {
            api_key,
            timeout_seconds: 10,
        }
    }

    /// Get API base URL for chain
    fn get_api_base(chain: Chain) -> Option<&'static str> {
        match chain {
            Chain::Ethereum => Some(ZEROX_API_ETHEREUM),
            Chain::Polygon => Some(ZEROX_API_POLYGON),
            Chain::Bnb => Some(ZEROX_API_BSC),
            Chain::Arbitrum => Some(ZEROX_API_ARBITRUM),
            Chain::Optimism => Some(ZEROX_API_OPTIMISM),
            Chain::Avalanche => Some(ZEROX_API_AVALANCHE),
            Chain::Base => Some(ZEROX_API_BASE),
            _ => None,
        }
    }

    /// Check if chain is supported
    pub fn is_chain_supported(chain: Chain) -> bool {
        Self::get_api_base(chain).is_some()
    }

    /// Get a price quote (no tx data, faster)
    pub fn get_price(&self, request: &SwapQuoteRequest) -> HawalaResult<SwapQuote> {
        let api_base = Self::get_api_base(request.chain)
            .ok_or_else(|| HawalaError::invalid_input(format!(
                "Chain {:?} not supported by 0x", request.chain
            )))?;

        // Build price URL
        let _price_url = format!(
            "{}/swap/v1/price?sellToken={}&buyToken={}&sellAmount={}",
            api_base,
            request.from_token,
            request.to_token,
            request.amount,
        );

        // In production, this would make an HTTP request
        self.fetch_quote_internal(request, false)
    }

    /// Get a swap quote with transaction data
    pub fn get_quote(&self, request: &SwapQuoteRequest) -> HawalaResult<SwapQuote> {
        let api_base = Self::get_api_base(request.chain)
            .ok_or_else(|| HawalaError::invalid_input(format!(
                "Chain {:?} not supported by 0x", request.chain
            )))?;

        // Validate slippage
        if request.slippage > 50.0 {
            return Err(HawalaError::invalid_input(
                "Slippage cannot exceed 50%".to_string()
            ));
        }

        // Convert slippage to 0x format (0.01 = 1%)
        let slippage_decimal = request.slippage / 100.0;

        // Build quote URL
        let _quote_url = format!(
            "{}/swap/v1/quote?sellToken={}&buyToken={}&sellAmount={}&takerAddress={}&slippagePercentage={}",
            api_base,
            request.from_token,
            request.to_token,
            request.amount,
            request.from_address,
            slippage_decimal,
        );

        // In production, this would make an HTTP request
        self.fetch_quote_internal(request, true)
    }

    /// Check token allowance
    pub fn check_allowance(&self, chain: Chain, token: &str, _owner: &str) -> HawalaResult<TokenApproval> {
        let _api_base = Self::get_api_base(chain)
            .ok_or_else(|| HawalaError::invalid_input(format!(
                "Chain {:?} not supported by 0x", chain
            )))?;

        let spender = self.get_exchange_proxy(chain);

        // In production, would check on-chain allowance
        Ok(TokenApproval {
            token: token.to_string(),
            spender,
            current_allowance: "0".to_string(),
            required_allowance: "115792089237316195423570985008687907853269984665640564039457584007913129639935".to_string(),
            needs_approval: true,
            approval_tx: None,
        })
    }

    /// Get 0x Exchange Proxy address for chain
    fn get_exchange_proxy(&self, chain: Chain) -> String {
        // 0x Exchange Proxy v4 addresses
        match chain {
            Chain::Ethereum => "0xDef1C0ded9bec7F1a1670819833240f027b25EfF".to_string(),
            Chain::Polygon => "0xDef1C0ded9bec7F1a1670819833240f027b25EfF".to_string(),
            Chain::Bnb => "0xDef1C0ded9bec7F1a1670819833240f027b25EfF".to_string(),
            Chain::Arbitrum => "0xDef1C0ded9bec7F1a1670819833240f027b25EfF".to_string(),
            Chain::Optimism => "0xDef1C0ded9bec7F1a1670819833240f027b25EfF".to_string(),
            Chain::Avalanche => "0xDef1C0ded9bec7F1a1670819833240f027b25EfF".to_string(),
            Chain::Base => "0xDef1C0ded9bec7F1a1670819833240f027b25EfF".to_string(),
            _ => "0xDef1C0ded9bec7F1a1670819833240f027b25EfF".to_string(),
        }
    }

    /// Internal: fetch quote (mock implementation)
    fn fetch_quote_internal(&self, request: &SwapQuoteRequest, include_tx: bool) -> HawalaResult<SwapQuote> {
        // Calculate expiry (30 seconds from now)
        let expires_at = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() + 30;

        // Mock token data
        let (from_symbol, from_decimals) = self.get_token_info(&request.from_token);
        let (to_symbol, to_decimals) = self.get_token_info(&request.to_token);

        // Mock output calculation
        let from_amount: u128 = request.amount.parse().unwrap_or(0);
        let mock_rate = self.get_mock_rate(&request.from_token, &request.to_token);
        let to_amount = (from_amount as f64 * mock_rate) as u128;
        let to_amount_min = (to_amount as f64 * (1.0 - request.slippage / 100.0)) as u128;

        let tx = if include_tx {
            let exchange_proxy = self.get_exchange_proxy(request.chain);
            let is_native = request.from_token.to_lowercase() == SwapQuoteRequest::NATIVE_ETH.to_lowercase();
            
            Some(SwapTransaction {
                to: exchange_proxy,
                data: "0xd9627aa4".to_string(), // sellToUniswap selector
                value: if is_native { request.amount.clone() } else { "0".to_string() },
                gas_limit: "200000".to_string(),
                gas_price: None,
                max_fee_per_gas: Some("50000000000".to_string()),
                max_priority_fee_per_gas: Some("2000000000".to_string()),
            })
        } else {
            None
        };

        Ok(SwapQuote {
            provider: DEXProvider::ZeroX,
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
            estimated_gas: "200000".to_string(),
            gas_price_gwei: request.gas_price_gwei.unwrap_or(30.0),
            gas_cost_usd: Some(6.0), // Slightly higher than 1inch for variety
            price_impact: -0.15,
            routes: vec![
                SwapRoute {
                    protocol: "0x RFQ".to_string(),
                    percentage: 60.0,
                    path: vec![
                        RouteToken {
                            address: request.from_token.clone(),
                            symbol: from_symbol.clone(),
                            decimals: from_decimals,
                        },
                        RouteToken {
                            address: request.to_token.clone(),
                            symbol: to_symbol.clone(),
                            decimals: to_decimals,
                        },
                    ],
                },
                SwapRoute {
                    protocol: "Uniswap V3".to_string(),
                    percentage: 40.0,
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
            tx,
        })
    }

    /// Get token info (mock)
    fn get_token_info(&self, address: &str) -> (String, u8) {
        let addr_lower = address.to_lowercase();
        
        if addr_lower == SwapQuoteRequest::NATIVE_ETH.to_lowercase() {
            return ("ETH".to_string(), 18);
        }

        match addr_lower.as_str() {
            "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48" => ("USDC".to_string(), 6),
            "0xdac17f958d2ee523a2206206994597c13d831ec7" => ("USDT".to_string(), 6),
            "0x6b175474e89094c44da98b954eedeac495271d0f" => ("DAI".to_string(), 18),
            "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2" => ("WETH".to_string(), 18),
            _ => ("TOKEN".to_string(), 18),
        }
    }

    /// Get mock exchange rate
    fn get_mock_rate(&self, from: &str, to: &str) -> f64 {
        let from_lower = from.to_lowercase();
        let to_lower = to.to_lowercase();

        // ETH -> USDC (slightly worse than 1inch for realism)
        if from_lower == SwapQuoteRequest::NATIVE_ETH.to_lowercase() 
            && to_lower == "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48" {
            return 2995.0 * 1e6 / 1e18; // 2995 USDC per ETH
        }

        1.0
    }
}

/// 0x API response types
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct ZeroXQuoteResponse {
    #[serde(rename = "sellTokenAddress")]
    pub sell_token_address: String,
    #[serde(rename = "buyTokenAddress")]
    pub buy_token_address: String,
    #[serde(rename = "sellAmount")]
    pub sell_amount: String,
    #[serde(rename = "buyAmount")]
    pub buy_amount: String,
    #[serde(rename = "estimatedGas")]
    pub estimated_gas: String,
    #[serde(rename = "gasPrice")]
    pub gas_price: String,
    pub to: String,
    pub data: String,
    pub value: String,
    #[serde(rename = "allowanceTarget")]
    pub allowance_target: String,
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct ZeroXPriceResponse {
    #[serde(rename = "sellTokenAddress")]
    pub sell_token_address: String,
    #[serde(rename = "buyTokenAddress")]
    pub buy_token_address: String,
    #[serde(rename = "sellAmount")]
    pub sell_amount: String,
    #[serde(rename = "buyAmount")]
    pub buy_amount: String,
    #[serde(rename = "estimatedGas")]
    pub estimated_gas: String,
    #[serde(rename = "gasPrice")]
    pub gas_price: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_zerox_chain_support() {
        assert!(ZeroXClient::is_chain_supported(Chain::Ethereum));
        assert!(ZeroXClient::is_chain_supported(Chain::Polygon));
        assert!(ZeroXClient::is_chain_supported(Chain::Base));
        assert!(!ZeroXClient::is_chain_supported(Chain::Bitcoin));
        assert!(!ZeroXClient::is_chain_supported(Chain::Fantom)); // 0x doesn't support Fantom
    }

    #[test]
    fn test_get_price() {
        let client = ZeroXClient::new(None);
        let request = SwapQuoteRequest {
            chain: Chain::Ethereum,
            from_token: SwapQuoteRequest::NATIVE_ETH.to_string(),
            to_token: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48".to_string(),
            amount: "1000000000000000000".to_string(),
            slippage: 0.5,
            from_address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
            provider: None,
            deadline_seconds: None,
            referrer: None,
            gas_price_gwei: None,
        };

        let quote = client.get_price(&request).unwrap();
        assert_eq!(quote.provider, DEXProvider::ZeroX);
        assert!(quote.tx.is_none()); // Price quotes don't include tx data
    }

    #[test]
    fn test_get_quote_with_tx() {
        let client = ZeroXClient::new(None);
        let request = SwapQuoteRequest {
            chain: Chain::Arbitrum,
            from_token: SwapQuoteRequest::NATIVE_ETH.to_string(),
            to_token: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831".to_string(), // USDC on Arbitrum
            amount: "500000000000000000".to_string(), // 0.5 ETH
            slippage: 1.0,
            from_address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
            provider: None,
            deadline_seconds: None,
            referrer: None,
            gas_price_gwei: Some(0.1), // Arbitrum gas
        };

        let quote = client.get_quote(&request).unwrap();
        assert!(quote.tx.is_some());
        assert_eq!(quote.routes.len(), 2); // 0x uses multi-route
    }

    #[test]
    fn test_exchange_proxy_addresses() {
        let client = ZeroXClient::new(None);
        let eth_proxy = client.get_exchange_proxy(Chain::Ethereum);
        let polygon_proxy = client.get_exchange_proxy(Chain::Polygon);
        
        // All 0x proxies should be the same address
        assert_eq!(eth_proxy, polygon_proxy);
        assert!(eth_proxy.starts_with("0xDef1"));
    }
}
