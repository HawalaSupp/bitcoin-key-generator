//! Transaction Tracker
//!
//! Tracks transaction confirmations across all chains.
//! Polls blockchain APIs to check transaction status and confirmation count.

use crate::error::{HawalaError, HawalaResult, ErrorCode};
use crate::types::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

// =============================================================================
// Types
// =============================================================================

/// Transaction status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TxStatus {
    /// Transaction is in mempool, not yet confirmed
    Pending,
    /// Transaction is in a block but needs more confirmations
    Confirming,
    /// Transaction has enough confirmations
    Confirmed,
    /// Transaction failed (reverted for EVM)
    Failed,
    /// Transaction was dropped from mempool
    Dropped,
}

/// A transaction tracking entry (internal to tracker)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TxTrackingEntry {
    pub txid: String,
    pub chain: Chain,
    pub confirmations: u32,
    pub status: TxStatus,
    pub block_height: Option<u64>,
    pub timestamp: u64, // Unix timestamp when tracking started
    pub last_checked: u64,
}

#[allow(dead_code)]
impl TxTrackingEntry {
    /// Check if transaction is fully confirmed based on chain requirements
    pub fn is_confirmed(&self) -> bool {
        self.confirmations >= required_confirmations(self.chain)
    }
    
    /// Get progress towards full confirmation (0.0 to 1.0)
    pub fn confirmation_progress(&self) -> f64 {
        let required = required_confirmations(self.chain);
        (self.confirmations as f64 / required as f64).min(1.0)
    }
}

/// Result of checking a transaction
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransactionCheckResult {
    pub txid: String,
    pub chain: Chain,
    pub found: bool,
    pub confirmations: u32,
    pub status: TxStatus,
    pub block_height: Option<u64>,
    pub block_hash: Option<String>,
    pub fee_paid: Option<String>,
    pub gas_used: Option<u64>,
}

/// Request to track a transaction
#[derive(Debug, Clone, Deserialize)]
pub struct TrackRequest {
    pub txid: String,
    pub chain: Chain,
}

lazy_static::lazy_static! {
    static ref TRACKED_TXS: Mutex<HashMap<String, TxTrackingEntry>> = Mutex::new(HashMap::new());
}

// =============================================================================
// Required Confirmations per Chain
// =============================================================================

/// Get required confirmations for a chain
pub fn required_confirmations(chain: Chain) -> u32 {
    match chain {
        Chain::Bitcoin | Chain::Litecoin => 6,
        Chain::BitcoinTestnet => 1,
        Chain::Ethereum | Chain::Bnb => 12,
        Chain::EthereumSepolia => 1,
        Chain::Polygon | Chain::Arbitrum | Chain::Optimism | Chain::Base | Chain::Avalanche => 1,
        Chain::Solana | Chain::SolanaDevnet => 1,
        Chain::Xrp | Chain::XrpTestnet => 1,
        Chain::Monero => 10,
        _ => chain.required_confirmations(),
    }
}

// =============================================================================
// Public API
// =============================================================================

/// Start tracking a transaction
pub fn track_transaction(txid: &str, chain: Chain) -> HawalaResult<TxTrackingEntry> {
    let now = current_timestamp();
    
    let tx = TxTrackingEntry {
        txid: txid.to_string(),
        chain,
        confirmations: 0,
        status: TxStatus::Pending,
        block_height: None,
        timestamp: now,
        last_checked: now,
    };
    
    // Store in tracker
    if let Ok(mut tracked) = TRACKED_TXS.lock() {
        tracked.insert(txid.to_string(), tx.clone());
    }
    
    // Immediately check the transaction
    check_transaction(txid, chain)
}

/// Stop tracking a transaction
pub fn stop_tracking(txid: &str) {
    if let Ok(mut tracked) = TRACKED_TXS.lock() {
        tracked.remove(txid);
    }
}

/// Get a tracked transaction
pub fn get_tracked(txid: &str) -> Option<TxTrackingEntry> {
    TRACKED_TXS.lock().ok()?.get(txid).cloned()
}

/// Get all tracked transactions
pub fn get_all_tracked() -> Vec<TxTrackingEntry> {
    TRACKED_TXS.lock()
        .map(|t| t.values().cloned().collect())
        .unwrap_or_default()
}

/// Check transaction status and update tracking
pub fn check_transaction(txid: &str, chain: Chain) -> HawalaResult<TxTrackingEntry> {
    let result = match chain {
        Chain::Bitcoin | Chain::BitcoinTestnet | Chain::Litecoin => {
            check_bitcoin_transaction(txid, chain)?
        }
        Chain::Ethereum | Chain::EthereumSepolia | Chain::Bnb |
        Chain::Polygon | Chain::Arbitrum | Chain::Optimism | Chain::Base | Chain::Avalanche => {
            check_evm_transaction(txid, chain)?
        }
        Chain::Solana | Chain::SolanaDevnet => check_solana_transaction(txid)?,
        Chain::Xrp | Chain::XrpTestnet => check_xrp_transaction(txid)?,
        Chain::Monero => {
            return Err(HawalaError::new(ErrorCode::NotImplemented, "Monero tracking not yet implemented"));
        }
        // EVM-compatible chains
        chain if chain.is_evm() => check_evm_transaction(txid, chain)?,
        // Default fallback
        _ => {
            return Err(HawalaError::new(ErrorCode::NotImplemented, format!("Transaction tracking not yet implemented for {:?}", chain)));
        }
    };
    
    // Update tracked transaction
    let now = current_timestamp();
    let mut tx = TxTrackingEntry {
        txid: txid.to_string(),
        chain,
        confirmations: result.confirmations,
        status: result.status,
        block_height: result.block_height,
        timestamp: now,
        last_checked: now,
    };
    
    // Preserve original timestamp if already tracked
    if let Ok(mut tracked) = TRACKED_TXS.lock() {
        if let Some(existing) = tracked.get(txid) {
            tx.timestamp = existing.timestamp;
        }
        tracked.insert(txid.to_string(), tx.clone());
    }
    
    Ok(tx)
}

/// Get current confirmations for a transaction
pub fn get_confirmations(txid: &str, chain: Chain) -> HawalaResult<u32> {
    let result = check_transaction(txid, chain)?;
    Ok(result.confirmations)
}

/// Get transaction status
pub fn get_transaction_status(txid: &str, chain: Chain) -> HawalaResult<TxStatus> {
    let result = check_transaction(txid, chain)?;
    Ok(result.status)
}

// =============================================================================
// Bitcoin/Litecoin Transaction Checking
// =============================================================================

fn check_bitcoin_transaction(txid: &str, chain: Chain) -> HawalaResult<TransactionCheckResult> {
    let base_url = match chain {
        Chain::BitcoinTestnet => "https://mempool.space/testnet/api",
        Chain::Litecoin => "https://litecoinspace.org/api",
        _ => "https://mempool.space/api",
    };
    
    let url = format!("{}/tx/{}", base_url, txid);
    
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(10))
        .build()
        .map_err(|e| HawalaError::network_error(format!("Failed to create client: {}", e)))?;
    
    let response = client.get(&url).send();
    
    match response {
        Ok(resp) => {
            if resp.status() == reqwest::StatusCode::NOT_FOUND {
                return Ok(TransactionCheckResult {
                    txid: txid.to_string(),
                    chain,
                    found: false,
                    confirmations: 0,
                    status: TxStatus::Pending,
                    block_height: None,
                    block_hash: None,
                    fee_paid: None,
                    gas_used: None,
                });
            }
            
            let json: serde_json::Value = resp.json()
                .map_err(|e| HawalaError::parse_error(format!("Failed to parse response: {}", e)))?;
            
            let status = &json["status"];
            let confirmed = status["confirmed"].as_bool().unwrap_or(false);
            let block_height = status["block_height"].as_u64();
            let block_hash = status["block_hash"].as_str().map(|s| s.to_string());
            
            let fee = json["fee"].as_u64().map(|f| f.to_string());
            
            let (confirmations, tx_status) = if confirmed {
                let height_url = format!("{}/blocks/tip/height", base_url);
                let current_height = client.get(&height_url)
                    .send()
                    .ok()
                    .and_then(|r| r.text().ok())
                    .and_then(|t| t.trim().parse::<u64>().ok())
                    .unwrap_or(0);
                
                let confs = if let Some(tx_height) = block_height {
                    (current_height.saturating_sub(tx_height) + 1) as u32
                } else {
                    1
                };
                
                let status = if confs >= required_confirmations(chain) {
                    TxStatus::Confirmed
                } else {
                    TxStatus::Confirming
                };
                
                (confs, status)
            } else {
                (0, TxStatus::Pending)
            };
            
            Ok(TransactionCheckResult {
                txid: txid.to_string(),
                chain,
                found: true,
                confirmations,
                status: tx_status,
                block_height,
                block_hash,
                fee_paid: fee,
                gas_used: None,
            })
        }
        Err(e) => Err(HawalaError::network_error(format!("Failed to fetch transaction: {}", e))),
    }
}

// =============================================================================
// EVM Transaction Checking
// =============================================================================

fn check_evm_transaction(txid: &str, chain: Chain) -> HawalaResult<TransactionCheckResult> {
    let chain_id = chain.chain_id().unwrap_or(1);
    let endpoints = get_rpc_endpoints(chain_id);
    
    for endpoint in &endpoints {
        if let Ok(result) = check_evm_transaction_single(txid, chain, endpoint) {
            return Ok(result);
        }
    }
    
    Ok(TransactionCheckResult {
        txid: txid.to_string(),
        chain,
        found: false,
        confirmations: 0,
        status: TxStatus::Pending,
        block_height: None,
        block_hash: None,
        fee_paid: None,
        gas_used: None,
    })
}

fn check_evm_transaction_single(txid: &str, chain: Chain, rpc_url: &str) -> HawalaResult<TransactionCheckResult> {
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(10))
        .build()
        .map_err(|e| HawalaError::network_error(format!("Failed to create client: {}", e)))?;
    
    let receipt_payload = serde_json::json!({
        "jsonrpc": "2.0",
        "method": "eth_getTransactionReceipt",
        "params": [txid],
        "id": 1
    });
    
    let receipt_response = client
        .post(rpc_url)
        .json(&receipt_payload)
        .send()
        .map_err(|e| HawalaError::network_error(format!("RPC request failed: {}", e)))?;
    
    let receipt_json: serde_json::Value = receipt_response.json()
        .map_err(|e| HawalaError::parse_error(format!("Failed to parse receipt: {}", e)))?;
    
    if let Some(result) = receipt_json["result"].as_object() {
        let block_number_hex = result.get("blockNumber")
            .and_then(|v| v.as_str())
            .unwrap_or("0x0");
        let block_height = u64::from_str_radix(block_number_hex.trim_start_matches("0x"), 16).unwrap_or(0);
        
        let block_hash = result.get("blockHash")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());
        
        let status_hex = result.get("status")
            .and_then(|v| v.as_str())
            .unwrap_or("0x1");
        let success = status_hex == "0x1";
        
        let gas_used = result.get("gasUsed")
            .and_then(|v| v.as_str())
            .and_then(|s| u64::from_str_radix(s.trim_start_matches("0x"), 16).ok());
        
        let block_payload = serde_json::json!({
            "jsonrpc": "2.0",
            "method": "eth_blockNumber",
            "params": [],
            "id": 1
        });
        
        let current_height = client
            .post(rpc_url)
            .json(&block_payload)
            .send()
            .ok()
            .and_then(|r| r.json::<serde_json::Value>().ok())
            .and_then(|j| j["result"].as_str().map(|s| s.to_string()))
            .and_then(|s| u64::from_str_radix(s.trim_start_matches("0x"), 16).ok())
            .unwrap_or(0);
        
        let confirmations = current_height.saturating_sub(block_height) + 1;
        
        let tx_status = if !success {
            TxStatus::Failed
        } else if confirmations as u32 >= required_confirmations(chain) {
            TxStatus::Confirmed
        } else {
            TxStatus::Confirming
        };
        
        return Ok(TransactionCheckResult {
            txid: txid.to_string(),
            chain,
            found: true,
            confirmations: confirmations as u32,
            status: tx_status,
            block_height: Some(block_height),
            block_hash,
            fee_paid: None,
            gas_used,
        });
    }
    
    let tx_payload = serde_json::json!({
        "jsonrpc": "2.0",
        "method": "eth_getTransactionByHash",
        "params": [txid],
        "id": 1
    });
    
    let tx_response = client
        .post(rpc_url)
        .json(&tx_payload)
        .send()
        .map_err(|e| HawalaError::network_error(format!("RPC request failed: {}", e)))?;
    
    let tx_json: serde_json::Value = tx_response.json()
        .map_err(|e| HawalaError::parse_error(format!("Failed to parse tx: {}", e)))?;
    
    if tx_json["result"].is_object() && !tx_json["result"].is_null() {
        return Ok(TransactionCheckResult {
            txid: txid.to_string(),
            chain,
            found: true,
            confirmations: 0,
            status: TxStatus::Pending,
            block_height: None,
            block_hash: None,
            fee_paid: None,
            gas_used: None,
        });
    }
    
    Ok(TransactionCheckResult {
        txid: txid.to_string(),
        chain,
        found: false,
        confirmations: 0,
        status: TxStatus::Pending,
        block_height: None,
        block_hash: None,
        fee_paid: None,
        gas_used: None,
    })
}

fn get_rpc_endpoints(chain_id: u64) -> Vec<&'static str> {
    match chain_id {
        1 => vec![
            "https://eth.llamarpc.com",
            "https://ethereum.publicnode.com",
            "https://rpc.ankr.com/eth",
        ],
        11155111 => vec![
            "https://ethereum-sepolia-rpc.publicnode.com",
            "https://sepolia.drpc.org",
            "https://1rpc.io/sepolia",
        ],
        56 => vec![
            "https://bsc-dataseed.binance.org",
            "https://bsc-dataseed1.defibit.io",
            "https://bsc.publicnode.com",
        ],
        137 => vec![
            "https://polygon-rpc.com",
            "https://polygon.llamarpc.com",
            "https://polygon.publicnode.com",
        ],
        42161 => vec![
            "https://arb1.arbitrum.io/rpc",
            "https://arbitrum.llamarpc.com",
        ],
        10 => vec![
            "https://mainnet.optimism.io",
            "https://optimism.llamarpc.com",
        ],
        8453 => vec![
            "https://mainnet.base.org",
            "https://base.llamarpc.com",
        ],
        43114 => vec![
            "https://api.avax.network/ext/bc/C/rpc",
            "https://avalanche.publicnode.com",
        ],
        _ => vec!["https://eth.llamarpc.com"],
    }
}

// =============================================================================
// Solana Transaction Checking
// =============================================================================

fn check_solana_transaction(txid: &str) -> HawalaResult<TransactionCheckResult> {
    let endpoints = vec![
        "https://api.mainnet-beta.solana.com",
        "https://solana-mainnet.g.alchemy.com/v2/demo",
    ];
    
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(10))
        .build()
        .map_err(|e| HawalaError::network_error(format!("Failed to create client: {}", e)))?;
    
    for endpoint in &endpoints {
        let payload = serde_json::json!({
            "jsonrpc": "2.0",
            "method": "getTransaction",
            "params": [
                txid,
                { "encoding": "json", "commitment": "confirmed" }
            ],
            "id": 1
        });
        
        if let Ok(response) = client.post(*endpoint).json(&payload).send() {
            if let Ok(json) = response.json::<serde_json::Value>() {
                if let Some(result) = json["result"].as_object() {
                    let slot = result.get("slot").and_then(|v| v.as_u64());
                    let meta = result.get("meta").and_then(|v| v.as_object());
                    let err = meta.and_then(|m| m.get("err"));
                    
                    let status = if err.is_some() && !err.unwrap().is_null() {
                        TxStatus::Failed
                    } else {
                        TxStatus::Confirmed
                    };
                    
                    return Ok(TransactionCheckResult {
                        txid: txid.to_string(),
                        chain: Chain::Solana,
                        found: true,
                        confirmations: 1,
                        status,
                        block_height: slot,
                        block_hash: None,
                        fee_paid: meta.and_then(|m| m.get("fee")).and_then(|f| f.as_u64()).map(|f| f.to_string()),
                        gas_used: None,
                    });
                }
            }
        }
    }
    
    Ok(TransactionCheckResult {
        txid: txid.to_string(),
        chain: Chain::Solana,
        found: false,
        confirmations: 0,
        status: TxStatus::Pending,
        block_height: None,
        block_hash: None,
        fee_paid: None,
        gas_used: None,
    })
}

// =============================================================================
// XRP Transaction Checking
// =============================================================================

fn check_xrp_transaction(txid: &str) -> HawalaResult<TransactionCheckResult> {
    let endpoints = vec![
        "https://s1.ripple.com:51234",
        "https://xrplcluster.com",
    ];
    
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(10))
        .build()
        .map_err(|e| HawalaError::network_error(format!("Failed to create client: {}", e)))?;
    
    for endpoint in &endpoints {
        let payload = serde_json::json!({
            "method": "tx",
            "params": [{
                "transaction": txid,
                "binary": false
            }]
        });
        
        if let Ok(response) = client.post(*endpoint).json(&payload).send() {
            if let Ok(json) = response.json::<serde_json::Value>() {
                if let Some(result) = json["result"].as_object() {
                    let validated = result.get("validated").and_then(|v| v.as_bool()).unwrap_or(false);
                    let meta = result.get("meta").and_then(|v| v.as_object());
                    let tx_result = meta.and_then(|m| m.get("TransactionResult")).and_then(|t| t.as_str());
                    
                    let status = if validated {
                        if tx_result == Some("tesSUCCESS") {
                            TxStatus::Confirmed
                        } else {
                            TxStatus::Failed
                        }
                    } else {
                        TxStatus::Pending
                    };
                    
                    let ledger_index = result.get("ledger_index").and_then(|v| v.as_u64());
                    let fee = result.get("Fee").and_then(|v| v.as_str()).map(|s| s.to_string());
                    
                    return Ok(TransactionCheckResult {
                        txid: txid.to_string(),
                        chain: Chain::Xrp,
                        found: true,
                        confirmations: if validated { 1 } else { 0 },
                        status,
                        block_height: ledger_index,
                        block_hash: None,
                        fee_paid: fee,
                        gas_used: None,
                    });
                }
            }
        }
    }
    
    Ok(TransactionCheckResult {
        txid: txid.to_string(),
        chain: Chain::Xrp,
        found: false,
        confirmations: 0,
        status: TxStatus::Pending,
        block_height: None,
        block_hash: None,
        fee_paid: None,
        gas_used: None,
    })
}

// =============================================================================
// Helper Functions
// =============================================================================

fn current_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or(Duration::ZERO)
        .as_secs()
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_required_confirmations() {
        assert_eq!(required_confirmations(Chain::Bitcoin), 6);
        assert_eq!(required_confirmations(Chain::BitcoinTestnet), 1);
        assert_eq!(required_confirmations(Chain::Ethereum), 12);
        assert_eq!(required_confirmations(Chain::EthereumSepolia), 1);
        assert_eq!(required_confirmations(Chain::Solana), 1);
    }
    
    #[test]
    fn test_confirmation_progress() {
        let tx = TxTrackingEntry {
            txid: "test".to_string(),
            chain: Chain::Bitcoin,
            confirmations: 3,
            status: TxStatus::Confirming,
            block_height: Some(100),
            timestamp: 0,
            last_checked: 0,
        };
        
        assert_eq!(tx.confirmation_progress(), 0.5);
        assert!(!tx.is_confirmed());
    }
}
