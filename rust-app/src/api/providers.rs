//! Blockchain API Providers
//!
//! Unified interface for multiple blockchain data providers.

use crate::error::{HawalaError, HawalaResult};
use crate::types::*;
use std::time::Duration;

/// Fetch balances for all requested addresses
pub fn fetch_all_balances(request: &BalanceRequest) -> HawalaResult<Vec<Balance>> {
    let mut balances = Vec::new();
    
    for addr in &request.addresses {
        match fetch_balance(&addr.address, addr.chain) {
            Ok(balance) => balances.push(balance),
            Err(_) => {
                // Return zero balance on error
                balances.push(Balance {
                    chain: addr.chain,
                    address: addr.address.clone(),
                    balance: "0".to_string(),
                    balance_raw: "0".to_string(),
                });
            }
        }
    }
    
    Ok(balances)
}

/// Fetch balance for a single address
pub fn fetch_balance(address: &str, chain: Chain) -> HawalaResult<Balance> {
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(10))
        .build()?;
    
    match chain {
        Chain::Bitcoin | Chain::BitcoinTestnet => {
            fetch_bitcoin_balance(&client, address, chain == Chain::BitcoinTestnet)
        }
        Chain::Litecoin => {
            fetch_litecoin_balance(&client, address)
        }
        Chain::Ethereum | Chain::EthereumSepolia | Chain::Bnb | Chain::Polygon 
        | Chain::Arbitrum | Chain::Optimism | Chain::Base | Chain::Avalanche => {
            fetch_evm_balance(&client, address, chain)
        }
        Chain::Solana | Chain::SolanaDevnet => {
            fetch_solana_balance(&client, address, chain == Chain::SolanaDevnet)
        }
        Chain::Xrp | Chain::XrpTestnet => {
            fetch_xrp_balance(&client, address, chain == Chain::XrpTestnet)
        }
        Chain::Monero => {
            // Monero requires special handling
            Ok(Balance {
                chain,
                address: address.to_string(),
                balance: "0".to_string(),
                balance_raw: "0".to_string(),
            })
        }
    }
}

fn fetch_bitcoin_balance(
    client: &reqwest::blocking::Client,
    address: &str,
    testnet: bool,
) -> HawalaResult<Balance> {
    let base_url = if testnet {
        "https://mempool.space/testnet/api"
    } else {
        "https://mempool.space/api"
    };
    
    let url = format!("{}/address/{}", base_url, address);
    
    #[derive(serde::Deserialize)]
    struct AddressInfo {
        chain_stats: ChainStats,
        mempool_stats: ChainStats,
    }
    
    #[derive(serde::Deserialize)]
    struct ChainStats {
        funded_txo_sum: u64,
        spent_txo_sum: u64,
    }
    
    let info: AddressInfo = client.get(&url).send()?.json()?;
    
    let confirmed = info.chain_stats.funded_txo_sum - info.chain_stats.spent_txo_sum;
    let unconfirmed = info.mempool_stats.funded_txo_sum - info.mempool_stats.spent_txo_sum;
    let total = confirmed + unconfirmed;
    
    let chain = if testnet { Chain::BitcoinTestnet } else { Chain::Bitcoin };
    
    Ok(Balance {
        chain,
        address: address.to_string(),
        balance: format!("{:.8}", total as f64 / 100_000_000.0),
        balance_raw: total.to_string(),
    })
}

fn fetch_litecoin_balance(
    _client: &reqwest::blocking::Client,
    address: &str,
) -> HawalaResult<Balance> {
    // TODO: Phase 6 - integrate Litecoin API
    Ok(Balance {
        chain: Chain::Litecoin,
        address: address.to_string(),
        balance: "0".to_string(),
        balance_raw: "0".to_string(),
    })
}

fn fetch_evm_balance(
    client: &reqwest::blocking::Client,
    address: &str,
    chain: Chain,
) -> HawalaResult<Balance> {
    // Use public RPC endpoints
    let rpc_url = match chain {
        Chain::Ethereum => "https://eth.llamarpc.com",
        Chain::EthereumSepolia => "https://rpc.sepolia.org",
        Chain::Bnb => "https://bsc-dataseed.binance.org",
        Chain::Polygon => "https://polygon-rpc.com",
        Chain::Arbitrum => "https://arb1.arbitrum.io/rpc",
        Chain::Optimism => "https://mainnet.optimism.io",
        Chain::Base => "https://mainnet.base.org",
        Chain::Avalanche => "https://api.avax.network/ext/bc/C/rpc",
        _ => return Err(HawalaError::invalid_input("Invalid EVM chain")),
    };
    
    let payload = serde_json::json!({
        "jsonrpc": "2.0",
        "method": "eth_getBalance",
        "params": [address, "latest"],
        "id": 1
    });
    
    #[derive(serde::Deserialize)]
    struct RpcResponse {
        result: Option<String>,
    }
    
    let response: RpcResponse = client
        .post(rpc_url)
        .json(&payload)
        .send()?
        .json()?;
    
    let balance_hex = response.result.unwrap_or_else(|| "0x0".to_string());
    let balance_wei = u128::from_str_radix(balance_hex.trim_start_matches("0x"), 16)
        .unwrap_or(0);
    
    let balance_eth = balance_wei as f64 / 1e18;
    
    Ok(Balance {
        chain,
        address: address.to_string(),
        balance: format!("{:.6}", balance_eth),
        balance_raw: balance_wei.to_string(),
    })
}

fn fetch_solana_balance(
    client: &reqwest::blocking::Client,
    address: &str,
    devnet: bool,
) -> HawalaResult<Balance> {
    let rpc_url = if devnet {
        "https://api.devnet.solana.com"
    } else {
        "https://api.mainnet-beta.solana.com"
    };
    
    let payload = serde_json::json!({
        "jsonrpc": "2.0",
        "method": "getBalance",
        "params": [address],
        "id": 1
    });
    
    #[derive(serde::Deserialize)]
    struct RpcResponse {
        result: Option<BalanceResult>,
    }
    
    #[derive(serde::Deserialize)]
    struct BalanceResult {
        value: u64,
    }
    
    let response: RpcResponse = client
        .post(rpc_url)
        .json(&payload)
        .send()?
        .json()?;
    
    let lamports = response.result.map(|r| r.value).unwrap_or(0);
    let sol = lamports as f64 / 1e9;
    
    let chain = if devnet { Chain::SolanaDevnet } else { Chain::Solana };
    
    Ok(Balance {
        chain,
        address: address.to_string(),
        balance: format!("{:.9}", sol),
        balance_raw: lamports.to_string(),
    })
}

fn fetch_xrp_balance(
    client: &reqwest::blocking::Client,
    address: &str,
    testnet: bool,
) -> HawalaResult<Balance> {
    let rpc_url = if testnet {
        "https://s.altnet.rippletest.net:51234"
    } else {
        "https://xrplcluster.com"
    };
    
    let payload = serde_json::json!({
        "method": "account_info",
        "params": [{
            "account": address,
            "ledger_index": "validated"
        }]
    });
    
    #[derive(serde::Deserialize)]
    struct RpcResponse {
        result: Option<AccountResult>,
    }
    
    #[derive(serde::Deserialize)]
    struct AccountResult {
        account_data: Option<AccountData>,
    }
    
    #[derive(serde::Deserialize)]
    struct AccountData {
        #[serde(rename = "Balance")]
        balance: String,
    }
    
    let response: RpcResponse = client
        .post(rpc_url)
        .json(&payload)
        .send()?
        .json()?;
    
    let drops: u64 = response.result
        .and_then(|r| r.account_data)
        .and_then(|d| d.balance.parse().ok())
        .unwrap_or(0);
    
    let xrp = drops as f64 / 1e6;
    
    let chain = if testnet { Chain::XrpTestnet } else { Chain::Xrp };
    
    Ok(Balance {
        chain,
        address: address.to_string(),
        balance: format!("{:.6}", xrp),
        balance_raw: drops.to_string(),
    })
}

#[cfg(test)]
mod tests {
    #[allow(unused_imports)]
    use super::*;

    #[test]
    fn test_evm_balance_parsing() {
        // Test hex parsing
        let hex = "0x1234";
        let value = u128::from_str_radix(hex.trim_start_matches("0x"), 16).unwrap();
        assert_eq!(value, 0x1234);
    }
}
