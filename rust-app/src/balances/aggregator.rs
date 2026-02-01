//! L2 Balance Aggregation
//!
//! Aggregates token balances across L1 and all L2 chains.
//! Provides unified view of assets and smart chain suggestions.
//!
//! Inspired by Rabby, Rainbow

use crate::error::{HawalaError, HawalaResult, ErrorCode};
use crate::types::Chain;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::Duration;

// =============================================================================
// Types
// =============================================================================

/// Balance on a single chain
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChainBalance {
    /// Chain identifier
    pub chain: Chain,
    /// Balance amount (in token's native decimals)
    pub amount: String,
    /// Balance as decimal string
    pub amount_decimal: String,
    /// USD value of this balance
    pub usd_value: f64,
    /// Whether this chain is an L2
    pub is_l2: bool,
    /// Last update timestamp
    pub last_updated: u64,
}

/// Aggregated balance across all chains
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AggregatedBalance {
    /// Token symbol
    pub token: String,
    /// Token name
    pub token_name: String,
    /// Total amount across all chains
    pub total_amount: String,
    /// Total USD value
    pub total_usd: f64,
    /// Per-chain breakdown
    pub chains: Vec<ChainBalance>,
    /// Number of chains with balance
    pub chain_count: usize,
}

/// Request to aggregate balances
#[derive(Debug, Clone, Deserialize)]
pub struct AggregationRequest {
    /// Wallet address (or addresses per chain)
    pub address: String,
    /// Token to aggregate (native or contract address)
    pub token: String,
    /// Chains to include (empty = all supported)
    pub chains: Vec<Chain>,
}

/// Chain suggestion for a transaction
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChainSuggestion {
    /// Recommended chain
    pub chain: Chain,
    /// Reason for recommendation
    pub reason: String,
    /// Estimated gas fee in USD
    pub estimated_fee_usd: f64,
    /// Available balance on this chain
    pub available_balance: String,
    /// Sufficient balance for transaction
    pub has_sufficient_balance: bool,
}

/// Result of chain suggestion
#[derive(Debug, Clone, Serialize)]
pub struct SuggestionResult {
    /// Best chain for this transaction
    pub recommended: ChainSuggestion,
    /// All chains ranked by preference
    pub alternatives: Vec<ChainSuggestion>,
}

// =============================================================================
// L2 Chain Configuration
// =============================================================================

/// Get all supported L2 chains
pub fn get_l2_chains() -> Vec<Chain> {
    vec![
        Chain::Arbitrum,
        Chain::Optimism,
        Chain::Base,
        Chain::Polygon,
        Chain::Avalanche,
    ]
}

/// Get all EVM chains (L1 + L2)
pub fn get_all_evm_chains() -> Vec<Chain> {
    vec![
        Chain::Ethereum,
        Chain::Arbitrum,
        Chain::Optimism,
        Chain::Base,
        Chain::Polygon,
        Chain::Bnb,
        Chain::Avalanche,
    ]
}

/// Check if chain is an L2
pub fn is_l2(chain: Chain) -> bool {
    matches!(
        chain,
        Chain::Arbitrum | Chain::Optimism | Chain::Base | Chain::Polygon
    )
}

/// Estimate gas fee in USD for a chain
fn estimate_gas_fee_usd(chain: Chain) -> f64 {
    // Approximate gas fees (updated periodically)
    match chain {
        Chain::Ethereum => 5.0,      // L1 expensive
        Chain::Arbitrum => 0.10,     // L2 cheap
        Chain::Optimism => 0.05,     // L2 very cheap
        Chain::Base => 0.02,         // L2 very cheap
        Chain::Polygon => 0.01,      // Sidechain cheapest
        Chain::Bnb => 0.10,          // BSC
        Chain::Avalanche => 0.20,    // C-Chain
        _ => 1.0,                    // Default
    }
}

// =============================================================================
// Balance Aggregator
// =============================================================================

/// Aggregates balances across multiple chains
pub struct BalanceAggregator {
    /// Cached balances (reserved for future caching)
    #[allow(dead_code)]
    cache: HashMap<String, Vec<ChainBalance>>,
}

impl BalanceAggregator {
    /// Create a new balance aggregator
    pub fn new() -> Self {
        Self {
            cache: HashMap::new(),
        }
    }

    /// Aggregate native token balances across all EVM chains
    pub fn aggregate_native_balance(&self, request: &AggregationRequest) -> HawalaResult<AggregatedBalance> {
        let chains = if request.chains.is_empty() {
            get_all_evm_chains()
        } else {
            request.chains.clone()
        };

        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(10))
            .build()
            .map_err(|e| HawalaError::network_error(format!("Failed to create client: {}", e)))?;

        let mut chain_balances = Vec::new();
        let mut total_wei: u128 = 0;

        for chain in &chains {
            match self.fetch_native_balance(&client, *chain, &request.address) {
                Ok(balance) => {
                    let wei = parse_balance(&balance.amount).unwrap_or(0);
                    total_wei += wei;
                    chain_balances.push(balance);
                }
                Err(_) => {
                    // Continue with other chains if one fails
                    chain_balances.push(ChainBalance {
                        chain: *chain,
                        amount: "0".to_string(),
                        amount_decimal: "0".to_string(),
                        usd_value: 0.0,
                        is_l2: is_l2(*chain),
                        last_updated: current_timestamp(),
                    });
                }
            }
        }

        // Calculate totals
        let total_decimal = format_wei(total_wei, 18);
        let _eth_price = self.get_eth_price().unwrap_or(2500.0);
        let total_usd: f64 = chain_balances.iter().map(|b| b.usd_value).sum();

        let token_symbol = self.get_native_symbol(chains.first().copied().unwrap_or(Chain::Ethereum));

        Ok(AggregatedBalance {
            token: token_symbol.clone(),
            token_name: self.get_native_name(chains.first().copied().unwrap_or(Chain::Ethereum)),
            total_amount: total_decimal,
            total_usd,
            chain_count: chain_balances.iter().filter(|b| parse_balance(&b.amount).unwrap_or(0) > 0).count(),
            chains: chain_balances,
        })
    }

    /// Aggregate ERC-20 token balance across chains
    pub fn aggregate_token_balance(
        &self,
        address: &str,
        token_address: &str,
        chains: &[Chain],
    ) -> HawalaResult<AggregatedBalance> {
        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(10))
            .build()
            .map_err(|e| HawalaError::network_error(format!("Failed to create client: {}", e)))?;

        let chains_to_check = if chains.is_empty() {
            get_all_evm_chains()
        } else {
            chains.to_vec()
        };

        let mut chain_balances = Vec::new();
        let mut total_raw: u128 = 0;

        for chain in &chains_to_check {
            match self.fetch_token_balance(&client, *chain, address, token_address) {
                Ok(balance) => {
                    let raw = parse_balance(&balance.amount).unwrap_or(0);
                    total_raw += raw;
                    chain_balances.push(balance);
                }
                Err(_) => {
                    chain_balances.push(ChainBalance {
                        chain: *chain,
                        amount: "0".to_string(),
                        amount_decimal: "0".to_string(),
                        usd_value: 0.0,
                        is_l2: is_l2(*chain),
                        last_updated: current_timestamp(),
                    });
                }
            }
        }

        // Assume 18 decimals for now (should be fetched per token)
        let decimals = 18;
        let total_decimal = format_wei(total_raw, decimals);
        let total_usd: f64 = chain_balances.iter().map(|b| b.usd_value).sum();

        Ok(AggregatedBalance {
            token: token_address.to_string(),
            token_name: "Token".to_string(),
            total_amount: total_decimal,
            total_usd,
            chain_count: chain_balances.iter().filter(|b| parse_balance(&b.amount).unwrap_or(0) > 0).count(),
            chains: chain_balances,
        })
    }

    /// Suggest the best chain for a transaction
    pub fn suggest_chain(
        &self,
        address: &str,
        token: &str,
        amount: &str,
    ) -> HawalaResult<SuggestionResult> {
        // Get balances across chains
        let request = AggregationRequest {
            address: address.to_string(),
            token: token.to_string(),
            chains: vec![],
        };

        let aggregated = if token.to_lowercase() == "eth" || token.starts_with("0x") && token.len() < 10 {
            self.aggregate_native_balance(&request)?
        } else {
            self.aggregate_token_balance(address, token, &[])?
        };

        let required_amount = parse_decimal_to_wei(amount, 18).unwrap_or(0);

        // Build suggestions for each chain with sufficient balance
        let mut suggestions: Vec<ChainSuggestion> = aggregated.chains
            .iter()
            .filter_map(|cb| {
                let balance = parse_balance(&cb.amount).unwrap_or(0);
                let has_sufficient = balance >= required_amount;
                let fee_usd = estimate_gas_fee_usd(cb.chain);

                Some(ChainSuggestion {
                    chain: cb.chain,
                    reason: if has_sufficient {
                        format!("Available: {} | Fee: ~${:.2}", cb.amount_decimal, fee_usd)
                    } else {
                        "Insufficient balance".to_string()
                    },
                    estimated_fee_usd: fee_usd,
                    available_balance: cb.amount_decimal.clone(),
                    has_sufficient_balance: has_sufficient,
                })
            })
            .collect();

        // Sort by: has balance first, then by lowest fee
        suggestions.sort_by(|a, b| {
            match (a.has_sufficient_balance, b.has_sufficient_balance) {
                (true, false) => std::cmp::Ordering::Less,
                (false, true) => std::cmp::Ordering::Greater,
                _ => a.estimated_fee_usd.partial_cmp(&b.estimated_fee_usd).unwrap_or(std::cmp::Ordering::Equal),
            }
        });

        let recommended = suggestions.first().cloned().ok_or_else(|| {
            HawalaError::new(ErrorCode::InvalidInput, "No chains available for transaction")
        })?;

        let alternatives = suggestions.into_iter().skip(1).collect();

        Ok(SuggestionResult {
            recommended,
            alternatives,
        })
    }

    // =========================================================================
    // Private Methods
    // =========================================================================

    fn fetch_native_balance(
        &self,
        client: &reqwest::blocking::Client,
        chain: Chain,
        address: &str,
    ) -> HawalaResult<ChainBalance> {
        let rpc_url = get_rpc_url(chain);

        let payload = serde_json::json!({
            "jsonrpc": "2.0",
            "method": "eth_getBalance",
            "params": [address, "latest"],
            "id": 1
        });

        let response = client
            .post(&rpc_url)
            .json(&payload)
            .send()
            .map_err(|e| HawalaError::network_error(e.to_string()))?;

        let json: serde_json::Value = response.json()
            .map_err(|e| HawalaError::parse_error(e.to_string()))?;

        let balance_hex = json["result"].as_str().unwrap_or("0x0");
        let balance_wei = u128::from_str_radix(balance_hex.trim_start_matches("0x"), 16).unwrap_or(0);
        let balance_decimal = format_wei(balance_wei, 18);

        let eth_price = self.get_eth_price().unwrap_or(2500.0);
        let usd_value = balance_decimal.parse::<f64>().unwrap_or(0.0) * eth_price;

        Ok(ChainBalance {
            chain,
            amount: balance_wei.to_string(),
            amount_decimal: balance_decimal,
            usd_value,
            is_l2: is_l2(chain),
            last_updated: current_timestamp(),
        })
    }

    fn fetch_token_balance(
        &self,
        client: &reqwest::blocking::Client,
        chain: Chain,
        address: &str,
        token_address: &str,
    ) -> HawalaResult<ChainBalance> {
        let rpc_url = get_rpc_url(chain);

        // balanceOf(address) selector + padded address
        let data = format!(
            "0x70a08231000000000000000000000000{}",
            address.trim_start_matches("0x")
        );

        let payload = serde_json::json!({
            "jsonrpc": "2.0",
            "method": "eth_call",
            "params": [{
                "to": token_address,
                "data": data
            }, "latest"],
            "id": 1
        });

        let response = client
            .post(&rpc_url)
            .json(&payload)
            .send()
            .map_err(|e| HawalaError::network_error(e.to_string()))?;

        let json: serde_json::Value = response.json()
            .map_err(|e| HawalaError::parse_error(e.to_string()))?;

        let balance_hex = json["result"].as_str().unwrap_or("0x0");
        let balance_raw = u128::from_str_radix(balance_hex.trim_start_matches("0x"), 16).unwrap_or(0);
        let balance_decimal = format_wei(balance_raw, 18); // Assume 18 decimals

        Ok(ChainBalance {
            chain,
            amount: balance_raw.to_string(),
            amount_decimal: balance_decimal,
            usd_value: 0.0, // Would need price oracle
            is_l2: is_l2(chain),
            last_updated: current_timestamp(),
        })
    }

    fn get_eth_price(&self) -> Option<f64> {
        // Simple price fetch - in production would use price oracle
        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(5))
            .build()
            .ok()?;

        let response = client
            .get("https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd")
            .send()
            .ok()?;

        let json: serde_json::Value = response.json().ok()?;
        json["ethereum"]["usd"].as_f64()
    }

    fn get_native_symbol(&self, chain: Chain) -> String {
        match chain {
            Chain::Ethereum | Chain::EthereumSepolia | Chain::Arbitrum | Chain::Optimism | Chain::Base => "ETH".to_string(),
            Chain::Polygon => "MATIC".to_string(),
            Chain::Bnb => "BNB".to_string(),
            Chain::Avalanche => "AVAX".to_string(),
            _ => "ETH".to_string(),
        }
    }

    fn get_native_name(&self, chain: Chain) -> String {
        match chain {
            Chain::Ethereum | Chain::EthereumSepolia | Chain::Arbitrum | Chain::Optimism | Chain::Base => "Ethereum".to_string(),
            Chain::Polygon => "Polygon".to_string(),
            Chain::Bnb => "BNB".to_string(),
            Chain::Avalanche => "Avalanche".to_string(),
            _ => "Ethereum".to_string(),
        }
    }
}

impl Default for BalanceAggregator {
    fn default() -> Self {
        Self::new()
    }
}

// =============================================================================
// Helper Functions
// =============================================================================

fn get_rpc_url(chain: Chain) -> String {
    match chain {
        Chain::Ethereum => "https://eth.llamarpc.com".to_string(),
        Chain::Arbitrum => "https://arb1.arbitrum.io/rpc".to_string(),
        Chain::Optimism => "https://mainnet.optimism.io".to_string(),
        Chain::Base => "https://mainnet.base.org".to_string(),
        Chain::Polygon => "https://polygon-rpc.com".to_string(),
        Chain::Bnb => "https://bsc-dataseed.binance.org".to_string(),
        Chain::Avalanche => "https://api.avax.network/ext/bc/C/rpc".to_string(),
        _ => "https://eth.llamarpc.com".to_string(),
    }
}

fn parse_balance(balance_str: &str) -> Option<u128> {
    balance_str.parse().ok()
}

fn parse_decimal_to_wei(amount: &str, decimals: u8) -> Option<u128> {
    let parts: Vec<&str> = amount.split('.').collect();
    let integer_part: u128 = parts.first()?.parse().ok()?;
    
    let decimal_part: u128 = if parts.len() > 1 {
        let dec_str = format!("{:0<width$}", parts[1], width = decimals as usize);
        dec_str[..decimals as usize].parse().unwrap_or(0)
    } else {
        0
    };
    
    let multiplier = 10u128.pow(decimals as u32);
    Some(integer_part * multiplier + decimal_part)
}

fn format_wei(wei: u128, decimals: u8) -> String {
    let divisor = 10u128.pow(decimals as u32);
    let integer = wei / divisor;
    let fraction = wei % divisor;
    
    if fraction == 0 {
        integer.to_string()
    } else {
        let fraction_str = format!("{:0>width$}", fraction, width = decimals as usize);
        let trimmed = fraction_str.trim_end_matches('0');
        format!("{}.{}", integer, trimmed)
    }
}

fn current_timestamp() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_wei() {
        assert_eq!(format_wei(1_000_000_000_000_000_000, 18), "1");
        assert_eq!(format_wei(1_500_000_000_000_000_000, 18), "1.5");
        assert_eq!(format_wei(100_000_000_000_000_000, 18), "0.1");
    }

    #[test]
    fn test_parse_decimal_to_wei() {
        assert_eq!(parse_decimal_to_wei("1", 18), Some(1_000_000_000_000_000_000));
        assert_eq!(parse_decimal_to_wei("1.5", 18), Some(1_500_000_000_000_000_000));
    }

    #[test]
    fn test_is_l2() {
        assert!(is_l2(Chain::Arbitrum));
        assert!(is_l2(Chain::Optimism));
        assert!(is_l2(Chain::Base));
        assert!(!is_l2(Chain::Ethereum));
    }

    #[test]
    fn test_get_l2_chains() {
        let l2s = get_l2_chains();
        assert!(l2s.contains(&Chain::Arbitrum));
        assert!(l2s.contains(&Chain::Optimism));
        assert!(!l2s.contains(&Chain::Ethereum));
    }

    #[test]
    fn test_gas_estimates() {
        assert!(estimate_gas_fee_usd(Chain::Ethereum) > estimate_gas_fee_usd(Chain::Base));
        assert!(estimate_gas_fee_usd(Chain::Base) < estimate_gas_fee_usd(Chain::Arbitrum));
    }

    #[test]
    fn test_new_aggregator() {
        let aggregator = BalanceAggregator::new();
        assert!(aggregator.cache.is_empty());
    }
}
