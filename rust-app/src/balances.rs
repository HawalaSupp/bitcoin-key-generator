//! Balance Fetcher
//!
//! Fetches balances from various blockchain APIs.
//! Supports: Bitcoin, Litecoin, Ethereum/EVM, Solana, XRP

use crate::error::{HawalaError, HawalaResult};
use crate::types::*;
use std::time::Duration;

// =============================================================================
// Public API
// =============================================================================

/// Fetch balances for all requested addresses
pub fn fetch_all_balances(request: &BalanceRequest) -> HawalaResult<Vec<Balance>> {
    let mut balances = Vec::new();
    let mut errors = Vec::new();
    
    for addr in &request.addresses {
        match fetch_balance(&addr.address, addr.chain) {
            Ok(balance) => balances.push(balance),
            Err(e) => errors.push(format!("{:?}: {}", addr.chain, e)),
        }
    }
    
    // If all requests failed, return error
    if balances.is_empty() && !errors.is_empty() {
        return Err(HawalaError::network_error(errors.join("; ")));
    }
    
    Ok(balances)
}

/// Fetch balance for a single address
pub fn fetch_balance(address: &str, chain: Chain) -> HawalaResult<Balance> {
    match chain {
        Chain::Bitcoin | Chain::BitcoinTestnet => fetch_bitcoin_balance(address, chain),
        Chain::Litecoin => fetch_litecoin_balance(address),
        Chain::Ethereum | Chain::EthereumSepolia | Chain::Bnb |
        Chain::Polygon | Chain::Arbitrum | Chain::Optimism |
        Chain::Base | Chain::Avalanche => fetch_evm_balance(address, chain),
        Chain::Solana | Chain::SolanaDevnet => fetch_solana_balance(address, chain),
        Chain::Xrp | Chain::XrpTestnet => fetch_xrp_balance(address, chain),
        Chain::Monero => {
            // Monero balance requires view key
            Err(HawalaError::not_implemented("Monero balance requires view key"))
        }
        // EVM-compatible chains
        chain if chain.is_evm() => fetch_evm_balance(address, chain),
        // Default fallback
        _ => Err(HawalaError::not_implemented(format!("Balance fetching not yet supported for {:?}", chain))),
    }
}

// =============================================================================
// Bitcoin Balance
// =============================================================================

/// Fetch Bitcoin balance from mempool.space/blockstream
pub fn fetch_bitcoin_balance(address: &str, chain: Chain) -> HawalaResult<Balance> {
    let base_url = match chain {
        Chain::BitcoinTestnet => "https://mempool.space/testnet/api",
        _ => "https://mempool.space/api",
    };
    
    let url = format!("{}/address/{}", base_url, address);
    let client = create_http_client()?;
    
    let resp: serde_json::Value = client.get(&url)
        .send()
        .map_err(|e| HawalaError::network_error(format!("Failed to fetch BTC balance: {}", e)))?
        .json()
        .map_err(|e| HawalaError::parse_error(format!("Failed to parse BTC balance: {}", e)))?;
    
    // Calculate balance from chain_stats and mempool_stats
    let chain_funded = resp["chain_stats"]["funded_txo_sum"].as_i64().unwrap_or(0);
    let chain_spent = resp["chain_stats"]["spent_txo_sum"].as_i64().unwrap_or(0);
    let mempool_funded = resp["mempool_stats"]["funded_txo_sum"].as_i64().unwrap_or(0);
    let mempool_spent = resp["mempool_stats"]["spent_txo_sum"].as_i64().unwrap_or(0);
    
    let balance_sats = (chain_funded - chain_spent) + (mempool_funded - mempool_spent);
    let balance_btc = balance_sats as f64 / 100_000_000.0;
    
    Ok(Balance {
        chain,
        address: address.to_string(),
        balance: format!("{:.8}", balance_btc),
        balance_raw: balance_sats.to_string(),
    })
}

// =============================================================================
// Litecoin Balance
// =============================================================================

/// Fetch Litecoin balance from litecoinspace.org
pub fn fetch_litecoin_balance(address: &str) -> HawalaResult<Balance> {
    let url = format!("https://litecoinspace.org/api/address/{}", address);
    let client = create_http_client()?;
    
    let resp: serde_json::Value = client.get(&url)
        .send()
        .map_err(|e| HawalaError::network_error(format!("Failed to fetch LTC balance: {}", e)))?
        .json()
        .map_err(|e| HawalaError::parse_error(format!("Failed to parse LTC balance: {}", e)))?;
    
    let chain_funded = resp["chain_stats"]["funded_txo_sum"].as_i64().unwrap_or(0);
    let chain_spent = resp["chain_stats"]["spent_txo_sum"].as_i64().unwrap_or(0);
    let mempool_funded = resp["mempool_stats"]["funded_txo_sum"].as_i64().unwrap_or(0);
    let mempool_spent = resp["mempool_stats"]["spent_txo_sum"].as_i64().unwrap_or(0);
    
    let balance_litoshi = (chain_funded - chain_spent) + (mempool_funded - mempool_spent);
    let balance_ltc = balance_litoshi as f64 / 100_000_000.0;
    
    Ok(Balance {
        chain: Chain::Litecoin,
        address: address.to_string(),
        balance: format!("{:.8}", balance_ltc),
        balance_raw: balance_litoshi.to_string(),
    })
}

// =============================================================================
// EVM Balance (Ethereum, BSC, Polygon, etc.)
// =============================================================================

/// Fetch EVM balance using JSON-RPC
pub fn fetch_evm_balance(address: &str, chain: Chain) -> HawalaResult<Balance> {
    let rpc_endpoints = get_rpc_endpoints(chain);
    
    for endpoint in &rpc_endpoints {
        if let Ok(balance) = fetch_evm_balance_from_rpc(address, chain, endpoint) {
            return Ok(balance);
        }
    }
    
    Err(HawalaError::network_error(format!("All RPC endpoints failed for {:?}", chain)))
}

fn fetch_evm_balance_from_rpc(address: &str, chain: Chain, rpc_url: &str) -> HawalaResult<Balance> {
    let client = create_http_client()?;
    
    let payload = serde_json::json!({
        "jsonrpc": "2.0",
        "method": "eth_getBalance",
        "params": [address, "latest"],
        "id": 1
    });
    
    let resp: serde_json::Value = client.post(rpc_url)
        .json(&payload)
        .send()
        .map_err(|e| HawalaError::network_error(format!("RPC request failed: {}", e)))?
        .json()
        .map_err(|e| HawalaError::parse_error(format!("Failed to parse RPC response: {}", e)))?;
    
    if let Some(hex_bal) = resp["result"].as_str() {
        let balance_wei = u128::from_str_radix(hex_bal.trim_start_matches("0x"), 16)
            .map_err(|_| HawalaError::parse_error("Invalid hex balance"))?;
        
        let balance_eth = balance_wei as f64 / 1e18;
        
        Ok(Balance {
            chain,
            address: address.to_string(),
            balance: format!("{:.12}", balance_eth),
            balance_raw: balance_wei.to_string(),
        })
    } else if let Some(error) = resp["error"].as_object() {
        let message = error.get("message")
            .and_then(|m| m.as_str())
            .unwrap_or("Unknown RPC error");
        Err(HawalaError::network_error(message.to_string()))
    } else {
        Err(HawalaError::parse_error("Missing result in RPC response"))
    }
}

fn get_rpc_endpoints(chain: Chain) -> Vec<&'static str> {
    match chain {
        Chain::Ethereum => vec![
            "https://eth.llamarpc.com",
            "https://ethereum.publicnode.com",
            "https://rpc.ankr.com/eth",
            "https://cloudflare-eth.com",
        ],
        Chain::EthereumSepolia => vec![
            "https://ethereum-sepolia-rpc.publicnode.com",
            "https://sepolia.drpc.org",
            "https://1rpc.io/sepolia",
        ],
        Chain::Bnb => vec![
            "https://bsc-dataseed.binance.org",
            "https://bsc-dataseed1.defibit.io",
            "https://bsc.publicnode.com",
        ],
        Chain::Polygon => vec![
            "https://polygon-rpc.com",
            "https://polygon.llamarpc.com",
            "https://polygon.publicnode.com",
        ],
        Chain::Arbitrum => vec![
            "https://arb1.arbitrum.io/rpc",
            "https://arbitrum.llamarpc.com",
        ],
        Chain::Optimism => vec![
            "https://mainnet.optimism.io",
            "https://optimism.llamarpc.com",
        ],
        Chain::Base => vec![
            "https://mainnet.base.org",
            "https://base.llamarpc.com",
        ],
        Chain::Avalanche => vec![
            "https://api.avax.network/ext/bc/C/rpc",
            "https://avalanche.publicnode.com",
        ],
        _ => vec!["https://eth.llamarpc.com"],
    }
}

// =============================================================================
// Solana Balance
// =============================================================================

/// Fetch Solana balance using JSON-RPC
pub fn fetch_solana_balance(address: &str, chain: Chain) -> HawalaResult<Balance> {
    let rpc_url = match chain {
        Chain::SolanaDevnet => "https://api.devnet.solana.com",
        _ => "https://api.mainnet-beta.solana.com",
    };
    
    let client = create_http_client()?;
    
    let payload = serde_json::json!({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "getBalance",
        "params": [address]
    });
    
    let resp: serde_json::Value = client.post(rpc_url)
        .json(&payload)
        .send()
        .map_err(|e| HawalaError::network_error(format!("Failed to fetch SOL balance: {}", e)))?
        .json()
        .map_err(|e| HawalaError::parse_error(format!("Failed to parse SOL balance: {}", e)))?;
    
    if let Some(result) = resp["result"].as_object() {
        let lamports = result.get("value")
            .and_then(|v| v.as_u64())
            .unwrap_or(0);
        
        let balance_sol = lamports as f64 / 1_000_000_000.0;
        
        Ok(Balance {
            chain,
            address: address.to_string(),
            balance: format!("{:.9}", balance_sol),
            balance_raw: lamports.to_string(),
        })
    } else if let Some(error) = resp["error"].as_object() {
        let message = error.get("message")
            .and_then(|m| m.as_str())
            .unwrap_or("Unknown RPC error");
        Err(HawalaError::network_error(message.to_string()))
    } else {
        Err(HawalaError::parse_error("Missing result in RPC response"))
    }
}

// =============================================================================
// XRP Balance
// =============================================================================

/// Fetch XRP balance using XRPL RPC
pub fn fetch_xrp_balance(address: &str, chain: Chain) -> HawalaResult<Balance> {
    let rpc_urls = match chain {
        Chain::XrpTestnet => vec!["https://s.altnet.rippletest.net:51234"],
        _ => vec!["https://s1.ripple.com:51234", "https://xrplcluster.com"],
    };
    
    let client = create_http_client()?;
    
    for rpc_url in &rpc_urls {
        let payload = serde_json::json!({
            "method": "account_info",
            "params": [{
                "account": address,
                "ledger_index": "current"
            }]
        });
        
        if let Ok(resp) = client.post(*rpc_url)
            .json(&payload)
            .send()
        {
            if let Ok(json) = resp.json::<serde_json::Value>() {
                if let Some(result) = json["result"].as_object() {
                    if let Some(account_data) = result.get("account_data") {
                        // Balance is in drops (1 XRP = 1,000,000 drops)
                        let balance_drops = account_data["Balance"]
                            .as_str()
                            .and_then(|s| s.parse::<i64>().ok())
                            .unwrap_or(0);
                        
                        let balance_xrp = balance_drops as f64 / 1_000_000.0;
                        
                        return Ok(Balance {
                            chain,
                            address: address.to_string(),
                            balance: format!("{:.6}", balance_xrp),
                            balance_raw: balance_drops.to_string(),
                        });
                    }
                }
                
                // Check for error (account not found = 0 balance)
                if let Some(error) = json["result"]["error"].as_str() {
                    if error == "actNotFound" {
                        return Ok(Balance {
                            chain,
                            address: address.to_string(),
                            balance: "0.000000".to_string(),
                            balance_raw: "0".to_string(),
                        });
                    }
                }
            }
        }
    }
    
    Err(HawalaError::network_error("All XRP RPC endpoints failed"))
}

// =============================================================================
// Token Balances (ERC-20, SPL, etc.)
// =============================================================================

/// Fetch ERC-20 token balance
pub fn fetch_erc20_balance(address: &str, token_contract: &str, chain: Chain) -> HawalaResult<TokenBalance> {
    let rpc_endpoints = get_rpc_endpoints(chain);
    let client = create_http_client()?;
    
    // balanceOf(address) selector = 0x70a08231
    let padded_address = format!("000000000000000000000000{}", address.trim_start_matches("0x"));
    let data = format!("0x70a08231{}", padded_address);
    
    for endpoint in &rpc_endpoints {
        let payload = serde_json::json!({
            "jsonrpc": "2.0",
            "method": "eth_call",
            "params": [{
                "to": token_contract,
                "data": data
            }, "latest"],
            "id": 1
        });
        
        if let Ok(resp) = client.post(*endpoint).json(&payload).send() {
            if let Ok(json) = resp.json::<serde_json::Value>() {
                if let Some(hex_balance) = json["result"].as_str() {
                    let balance = u128::from_str_radix(hex_balance.trim_start_matches("0x"), 16)
                        .unwrap_or(0);
                    
                    return Ok(TokenBalance {
                        chain,
                        address: address.to_string(),
                        token_contract: token_contract.to_string(),
                        balance_raw: balance.to_string(),
                        decimals: 18, // Would need to query decimals() for accuracy
                    });
                }
            }
        }
    }
    
    Err(HawalaError::network_error("Failed to fetch token balance"))
}

/// Fetch SPL token balance (Solana)
pub fn fetch_spl_balance(address: &str, mint: &str, chain: Chain) -> HawalaResult<TokenBalance> {
    let rpc_url = match chain {
        Chain::SolanaDevnet => "https://api.devnet.solana.com",
        _ => "https://api.mainnet-beta.solana.com",
    };
    
    let client = create_http_client()?;
    
    let payload = serde_json::json!({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "getTokenAccountsByOwner",
        "params": [
            address,
            { "mint": mint },
            { "encoding": "jsonParsed" }
        ]
    });
    
    let resp: serde_json::Value = client.post(rpc_url)
        .json(&payload)
        .send()
        .map_err(|e| HawalaError::network_error(format!("Failed to fetch SPL balance: {}", e)))?
        .json()
        .map_err(|e| HawalaError::parse_error(format!("Failed to parse SPL balance: {}", e)))?;
    
    if let Some(accounts) = resp["result"]["value"].as_array() {
        let mut total_balance: u64 = 0;
        let mut decimals = 0u8;
        
        for account in accounts {
            if let Some(info) = account["account"]["data"]["parsed"]["info"].as_object() {
                if let Some(amount) = info.get("tokenAmount").and_then(|t| t.as_object()) {
                    let balance: u64 = amount.get("amount")
                        .and_then(|a| a.as_str())
                        .and_then(|s| s.parse().ok())
                        .unwrap_or(0);
                    total_balance += balance;
                    
                    decimals = amount.get("decimals")
                        .and_then(|d| d.as_u64())
                        .unwrap_or(0) as u8;
                }
            }
        }
        
        return Ok(TokenBalance {
            chain,
            address: address.to_string(),
            token_contract: mint.to_string(),
            balance_raw: total_balance.to_string(),
            decimals,
        });
    }
    
    Ok(TokenBalance {
        chain,
        address: address.to_string(),
        token_contract: mint.to_string(),
        balance_raw: "0".to_string(),
        decimals: 0,
    })
}

// =============================================================================
// Helper Functions
// =============================================================================

fn create_http_client() -> HawalaResult<reqwest::blocking::Client> {
    reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(15))
        .build()
        .map_err(|e| HawalaError::network_error(format!("Failed to create HTTP client: {}", e)))
}

// =============================================================================
// Token Balance Type
// =============================================================================

/// Token balance for ERC-20, SPL, etc.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TokenBalance {
    pub chain: Chain,
    pub address: String,
    pub token_contract: String,
    pub balance_raw: String,
    pub decimals: u8,
}

impl TokenBalance {
    /// Get formatted balance with correct decimal places
    pub fn formatted_balance(&self) -> String {
        if self.decimals == 0 {
            return self.balance_raw.clone();
        }
        
        let raw: u128 = self.balance_raw.parse().unwrap_or(0);
        let divisor = 10u128.pow(self.decimals as u32);
        let balance = raw as f64 / divisor as f64;
        
        format!("{:.precision$}", balance, precision = self.decimals as usize)
    }
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_token_balance_formatting() {
        let balance = TokenBalance {
            chain: Chain::Ethereum,
            address: "0x123".to_string(),
            token_contract: "0xtoken".to_string(),
            balance_raw: "1000000000000000000".to_string(), // 1e18
            decimals: 18,
        };
        
        assert!(balance.formatted_balance().starts_with("1.0"));
    }
    
    #[test]
    fn test_rpc_endpoints() {
        let endpoints = get_rpc_endpoints(Chain::Ethereum);
        assert!(!endpoints.is_empty());
        
        let endpoints = get_rpc_endpoints(Chain::Bnb);
        assert!(endpoints.iter().any(|e| e.contains("binance")));
    }
}
