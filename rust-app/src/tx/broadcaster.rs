//! Transaction Broadcaster
//!
//! Broadcasts signed transactions to blockchain networks with multi-provider fallback.
//! Migrated from Swift TransactionBroadcaster.swift

use crate::error::{HawalaError, HawalaResult, ErrorCode};
use crate::types::*;
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;

/// Broadcast configuration
pub struct BroadcastConfig {
    pub timeout_secs: u64,
    pub retries: u32,
}

impl Default for BroadcastConfig {
    fn default() -> Self {
        Self {
            timeout_secs: 15,
            retries: 3,
        }
    }
}

// =============================================================================
// Bitcoin Broadcasting
// =============================================================================

/// Broadcast Bitcoin transaction to mempool.space
pub fn broadcast_bitcoin(raw_tx: &str, testnet: bool) -> HawalaResult<BroadcastResult> {
    let client = create_client()?;
    
    let base_url = if testnet {
        "https://mempool.space/testnet/api"
    } else {
        "https://mempool.space/api"
    };
    
    let url = format!("{}/tx", base_url);
    
    let response = client
        .post(&url)
        .header("Content-Type", "text/plain")
        .header("User-Agent", "HawalaApp/1.0")
        .body(raw_tx.to_string())
        .send()
        .map_err(|e| HawalaError::network_error(format!("Failed to send request: {}", e)))?;
    
    let status = response.status();
    let body = response.text().unwrap_or_default();
    
    if status.is_success() {
        let txid = body.trim().to_string();
        let explorer_base = if testnet {
            "https://mempool.space/testnet/tx/"
        } else {
            "https://mempool.space/tx/"
        };
        
        Ok(BroadcastResult {
            chain: if testnet { Chain::BitcoinTestnet } else { Chain::Bitcoin },
            txid: txid.clone(),
            success: true,
            error_message: None,
            explorer_url: Some(format!("{}{}", explorer_base, txid)),
        })
    } else {
        Err(HawalaError::new(
            ErrorCode::BroadcastFailed,
            format!("Bitcoin broadcast failed: {}", body),
        ))
    }
}

// =============================================================================
// Litecoin Broadcasting
// =============================================================================

/// Broadcast Litecoin transaction with fallback providers
pub fn broadcast_litecoin(raw_tx: &str) -> HawalaResult<BroadcastResult> {
    // Try Blockchair first
    if let Ok(result) = broadcast_litecoin_blockchair(raw_tx) {
        return Ok(result);
    }
    
    // Fallback to Blockcypher
    broadcast_litecoin_blockcypher(raw_tx)
}

fn broadcast_litecoin_blockchair(raw_tx: &str) -> HawalaResult<BroadcastResult> {
    let client = create_client()?;
    
    #[derive(Serialize)]
    struct BlockchairRequest {
        data: String,
    }
    
    #[derive(Deserialize)]
    struct BlockchairResponse {
        data: Option<BlockchairData>,
    }
    
    #[derive(Deserialize)]
    struct BlockchairData {
        transaction_hash: String,
    }
    
    let response = client
        .post("https://api.blockchair.com/litecoin/push/transaction")
        .header("Content-Type", "application/json")
        .header("User-Agent", "HawalaApp/1.0")
        .json(&BlockchairRequest { data: raw_tx.to_string() })
        .send()
        .map_err(|e| HawalaError::network_error(format!("Blockchair request failed: {}", e)))?;
    
    if !response.status().is_success() {
        return Err(HawalaError::broadcast_failed("Blockchair returned error status"));
    }
    
    let result: BlockchairResponse = response.json()
        .map_err(|e| HawalaError::parse_error(format!("Failed to parse Blockchair response: {}", e)))?;
    
    let txid = result.data
        .ok_or_else(|| HawalaError::broadcast_failed("No transaction hash in response"))?
        .transaction_hash;
    
    Ok(BroadcastResult {
        chain: Chain::Litecoin,
        txid: txid.clone(),
        success: true,
        error_message: None,
        explorer_url: Some(format!("https://blockchair.com/litecoin/transaction/{}", txid)),
    })
}

fn broadcast_litecoin_blockcypher(raw_tx: &str) -> HawalaResult<BroadcastResult> {
    let client = create_client()?;
    
    #[derive(Serialize)]
    struct BlockcypherRequest {
        tx: String,
    }
    
    #[derive(Deserialize)]
    struct BlockcypherResponse {
        tx: Option<BlockcypherTx>,
    }
    
    #[derive(Deserialize)]
    struct BlockcypherTx {
        hash: String,
    }
    
    let response = client
        .post("https://api.blockcypher.com/v1/ltc/main/txs/push")
        .header("Content-Type", "application/json")
        .json(&BlockcypherRequest { tx: raw_tx.to_string() })
        .send()
        .map_err(|e| HawalaError::network_error(format!("Blockcypher request failed: {}", e)))?;
    
    if !response.status().is_success() {
        let error_body = response.text().unwrap_or_default();
        return Err(HawalaError::broadcast_failed(format!("Blockcypher error: {}", error_body)));
    }
    
    let result: BlockcypherResponse = response.json()
        .map_err(|e| HawalaError::parse_error(format!("Failed to parse Blockcypher response: {}", e)))?;
    
    let txid = result.tx
        .ok_or_else(|| HawalaError::broadcast_failed("No transaction in response"))?
        .hash;
    
    Ok(BroadcastResult {
        chain: Chain::Litecoin,
        txid: txid.clone(),
        success: true,
        error_message: None,
        explorer_url: Some(format!("https://blockchair.com/litecoin/transaction/{}", txid)),
    })
}

// =============================================================================
// Ethereum/EVM Broadcasting
// =============================================================================

/// Broadcast Ethereum transaction with multi-RPC fallback
pub fn broadcast_ethereum(raw_tx: &str, testnet: bool) -> HawalaResult<BroadcastResult> {
    let chain_id = if testnet { 11155111u64 } else { 1u64 };
    broadcast_evm(raw_tx, chain_id)
}

/// Broadcast to any EVM chain by chain ID
pub fn broadcast_evm(raw_tx: &str, chain_id: u64) -> HawalaResult<BroadcastResult> {
    let endpoints = get_rpc_endpoints(chain_id);
    let mut last_error = HawalaError::broadcast_failed("All endpoints failed");
    
    for endpoint in &endpoints {
        match broadcast_evm_single(raw_tx, endpoint) {
            Ok(txid) => {
                let chain = chain_from_id(chain_id);
                let (explorer_base, _) = get_explorer_info(chain_id);
                
                return Ok(BroadcastResult {
                    chain,
                    txid: txid.clone(),
                    success: true,
                    error_message: None,
                    explorer_url: Some(format!("{}{}", explorer_base, txid)),
                });
            }
            Err(e) => {
                eprintln!("[EVM Broadcast] Failed on {}: {}", endpoint, e);
                last_error = e;
            }
        }
    }
    
    Err(last_error)
}

fn broadcast_evm_single(raw_tx: &str, rpc_url: &str) -> HawalaResult<String> {
    let client = create_client()?;
    
    // Ensure 0x prefix
    let tx_with_prefix = if raw_tx.starts_with("0x") {
        raw_tx.to_string()
    } else {
        format!("0x{}", raw_tx)
    };
    
    #[derive(Serialize)]
    struct RpcRequest {
        jsonrpc: &'static str,
        method: &'static str,
        params: Vec<String>,
        id: u32,
    }
    
    #[derive(Deserialize)]
    struct RpcResponse {
        result: Option<String>,
        error: Option<RpcError>,
    }
    
    #[derive(Deserialize)]
    struct RpcError {
        message: String,
    }
    
    let response = client
        .post(rpc_url)
        .header("Content-Type", "application/json")
        .json(&RpcRequest {
            jsonrpc: "2.0",
            method: "eth_sendRawTransaction",
            params: vec![tx_with_prefix],
            id: 1,
        })
        .send()
        .map_err(|e| HawalaError::network_error(format!("RPC request failed: {}", e)))?;
    
    if !response.status().is_success() {
        return Err(HawalaError::network_error("RPC returned error status"));
    }
    
    let result: RpcResponse = response.json()
        .map_err(|e| HawalaError::parse_error(format!("Failed to parse RPC response: {}", e)))?;
    
    if let Some(error) = result.error {
        return Err(HawalaError::broadcast_failed(error.message));
    }
    
    result.result.ok_or_else(|| HawalaError::broadcast_failed("No txid in response"))
}

/// Get nonce for an EVM address
pub fn get_evm_nonce(address: &str, chain_id: u64) -> HawalaResult<u64> {
    let endpoints = get_rpc_endpoints(chain_id);
    
    for endpoint in &endpoints {
        if let Ok(nonce) = get_evm_nonce_single(address, endpoint) {
            return Ok(nonce);
        }
    }
    
    Err(HawalaError::network_error("Failed to fetch nonce from all endpoints"))
}

fn get_evm_nonce_single(address: &str, rpc_url: &str) -> HawalaResult<u64> {
    let client = create_client()?;
    
    #[derive(Serialize)]
    struct RpcRequest<'a> {
        jsonrpc: &'static str,
        method: &'static str,
        params: Vec<&'a str>,
        id: u32,
    }
    
    #[derive(Deserialize)]
    struct RpcResponse {
        result: Option<String>,
    }
    
    let response = client
        .post(rpc_url)
        .header("Content-Type", "application/json")
        .json(&RpcRequest {
            jsonrpc: "2.0",
            method: "eth_getTransactionCount",
            params: vec![address, "pending"],
            id: 1,
        })
        .send()
        .map_err(|e| HawalaError::network_error(e.to_string()))?;
    
    let result: RpcResponse = response.json()
        .map_err(|e| HawalaError::parse_error(e.to_string()))?;
    
    let hex_nonce = result.result
        .ok_or_else(|| HawalaError::network_error("No nonce in response"))?;
    
    let nonce = u64::from_str_radix(hex_nonce.trim_start_matches("0x"), 16)
        .map_err(|e| HawalaError::parse_error(format!("Invalid nonce format: {}", e)))?;
    
    Ok(nonce)
}

// =============================================================================
// Solana Broadcasting
// =============================================================================

/// Broadcast Solana transaction
pub fn broadcast_solana(raw_tx_base64: &str, devnet: bool) -> HawalaResult<BroadcastResult> {
    let client = create_client()?;
    
    let rpc_url = if devnet {
        "https://api.devnet.solana.com"
    } else {
        "https://api.mainnet-beta.solana.com"
    };
    
    #[derive(Serialize)]
    struct RpcRequest {
        jsonrpc: &'static str,
        id: u32,
        method: &'static str,
        params: (String, SolanaOptions),
    }
    
    #[derive(Serialize)]
    struct SolanaOptions {
        encoding: &'static str,
        #[serde(rename = "preflightCommitment")]
        preflight_commitment: &'static str,
    }
    
    #[derive(Deserialize)]
    struct RpcResponse {
        result: Option<String>,
        error: Option<RpcError>,
    }
    
    #[derive(Deserialize)]
    struct RpcError {
        message: String,
    }
    
    let response = client
        .post(rpc_url)
        .header("Content-Type", "application/json")
        .json(&RpcRequest {
            jsonrpc: "2.0",
            id: 1,
            method: "sendTransaction",
            params: (
                raw_tx_base64.to_string(),
                SolanaOptions {
                    encoding: "base64",
                    preflight_commitment: "confirmed",
                },
            ),
        })
        .send()
        .map_err(|e| HawalaError::network_error(format!("Solana RPC failed: {}", e)))?;
    
    let result: RpcResponse = response.json()
        .map_err(|e| HawalaError::parse_error(format!("Failed to parse Solana response: {}", e)))?;
    
    if let Some(error) = result.error {
        return Err(HawalaError::broadcast_failed(error.message));
    }
    
    let signature = result.result
        .ok_or_else(|| HawalaError::broadcast_failed("No signature in response"))?;
    
    let explorer_url = if devnet {
        format!("https://explorer.solana.com/tx/{}?cluster=devnet", signature)
    } else {
        format!("https://explorer.solana.com/tx/{}", signature)
    };
    
    Ok(BroadcastResult {
        chain: if devnet { Chain::SolanaDevnet } else { Chain::Solana },
        txid: signature,
        success: true,
        error_message: None,
        explorer_url: Some(explorer_url),
    })
}

// =============================================================================
// XRP Broadcasting
// =============================================================================

/// Broadcast XRP transaction
pub fn broadcast_xrp(raw_tx_hex: &str, testnet: bool) -> HawalaResult<BroadcastResult> {
    let client = create_client()?;
    
    let rpc_url = if testnet {
        "https://s.altnet.rippletest.net:51234"
    } else {
        "https://s1.ripple.com:51234"
    };
    
    #[derive(Serialize)]
    struct RpcRequest {
        method: &'static str,
        params: Vec<TxBlobParam>,
    }
    
    #[derive(Serialize)]
    struct TxBlobParam {
        tx_blob: String,
    }
    
    #[derive(Deserialize)]
    struct RpcResponse {
        result: XrpResult,
    }
    
    #[derive(Deserialize)]
    struct XrpResult {
        engine_result: Option<String>,
        engine_result_message: Option<String>,
        tx_json: Option<XrpTxJson>,
    }
    
    #[derive(Deserialize)]
    struct XrpTxJson {
        hash: String,
    }
    
    let response = client
        .post(rpc_url)
        .header("Content-Type", "application/json")
        .json(&RpcRequest {
            method: "submit",
            params: vec![TxBlobParam { tx_blob: raw_tx_hex.to_string() }],
        })
        .send()
        .map_err(|e| HawalaError::network_error(format!("XRP RPC failed: {}", e)))?;
    
    let result: RpcResponse = response.json()
        .map_err(|e| HawalaError::parse_error(format!("Failed to parse XRP response: {}", e)))?;
    
    // Check engine_result
    if let Some(engine_result) = &result.result.engine_result {
        if engine_result != "tesSUCCESS" {
            let message = result.result.engine_result_message
                .unwrap_or_else(|| engine_result.clone());
            return Err(HawalaError::broadcast_failed(message));
        }
    }
    
    let hash = result.result.tx_json
        .ok_or_else(|| HawalaError::broadcast_failed("No tx_json in response"))?
        .hash;
    
    let explorer_base = if testnet {
        "https://testnet.xrpl.org/transactions/"
    } else {
        "https://livenet.xrpl.org/transactions/"
    };
    
    Ok(BroadcastResult {
        chain: if testnet { Chain::XrpTestnet } else { Chain::Xrp },
        txid: hash.clone(),
        success: true,
        error_message: None,
        explorer_url: Some(format!("{}{}", explorer_base, hash)),
    })
}

// =============================================================================
// Unified Broadcast Function
// =============================================================================

/// Broadcast a transaction to the appropriate network based on chain
pub fn broadcast_transaction(chain: Chain, raw_tx: &str) -> HawalaResult<BroadcastResult> {
    match chain {
        Chain::Bitcoin => broadcast_bitcoin(raw_tx, false),
        Chain::BitcoinTestnet => broadcast_bitcoin(raw_tx, true),
        Chain::Litecoin => broadcast_litecoin(raw_tx),
        Chain::Ethereum => broadcast_ethereum(raw_tx, false),
        Chain::EthereumSepolia => broadcast_ethereum(raw_tx, true),
        Chain::Bnb => broadcast_evm(raw_tx, 56),
        Chain::Polygon => broadcast_evm(raw_tx, 137),
        Chain::Arbitrum => broadcast_evm(raw_tx, 42161),
        Chain::Optimism => broadcast_evm(raw_tx, 10),
        Chain::Base => broadcast_evm(raw_tx, 8453),
        Chain::Avalanche => broadcast_evm(raw_tx, 43114),
        Chain::Solana => broadcast_solana(raw_tx, false),
        Chain::SolanaDevnet => broadcast_solana(raw_tx, true),
        Chain::Xrp => broadcast_xrp(raw_tx, false),
        Chain::XrpTestnet => broadcast_xrp(raw_tx, true),
        Chain::Monero => Err(HawalaError::new(
            ErrorCode::NotImplemented,
            "Monero broadcasting requires specialized handling",
        )),
    }
}

// =============================================================================
// Helper Functions
// =============================================================================

fn create_client() -> HawalaResult<Client> {
    Client::builder()
        .timeout(Duration::from_secs(15))
        .connect_timeout(Duration::from_secs(10))
        .build()
        .map_err(|e| HawalaError::internal(format!("Failed to create HTTP client: {}", e)))
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
            "https://bsc-dataseed1.ninicoin.io",
        ],
        137 => vec![
            "https://polygon-rpc.com",
            "https://rpc.ankr.com/polygon",
            "https://polygon.llamarpc.com",
        ],
        42161 => vec![
            "https://arb1.arbitrum.io/rpc",
            "https://arbitrum.llamarpc.com",
            "https://rpc.ankr.com/arbitrum",
        ],
        10 => vec![
            "https://mainnet.optimism.io",
            "https://optimism.llamarpc.com",
            "https://rpc.ankr.com/optimism",
        ],
        8453 => vec![
            "https://mainnet.base.org",
            "https://base.llamarpc.com",
            "https://base.publicnode.com",
        ],
        43114 => vec![
            "https://api.avax.network/ext/bc/C/rpc",
            "https://avalanche.llamarpc.com",
            "https://rpc.ankr.com/avalanche",
        ],
        _ => vec!["https://eth.llamarpc.com"],
    }
}

fn chain_from_id(chain_id: u64) -> Chain {
    match chain_id {
        1 => Chain::Ethereum,
        11155111 => Chain::EthereumSepolia,
        56 => Chain::Bnb,
        137 => Chain::Polygon,
        42161 => Chain::Arbitrum,
        10 => Chain::Optimism,
        8453 => Chain::Base,
        43114 => Chain::Avalanche,
        _ => Chain::Ethereum,
    }
}

fn get_explorer_info(chain_id: u64) -> (&'static str, &'static str) {
    match chain_id {
        1 => ("https://etherscan.io/tx/", "ethereum"),
        11155111 => ("https://sepolia.etherscan.io/tx/", "ethereum-sepolia"),
        56 => ("https://bscscan.com/tx/", "bnb"),
        137 => ("https://polygonscan.com/tx/", "polygon"),
        42161 => ("https://arbiscan.io/tx/", "arbitrum"),
        10 => ("https://optimistic.etherscan.io/tx/", "optimism"),
        8453 => ("https://basescan.org/tx/", "base"),
        43114 => ("https://snowtrace.io/tx/", "avalanche"),
        _ => ("https://etherscan.io/tx/", "ethereum"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_get_rpc_endpoints() {
        let endpoints = get_rpc_endpoints(1);
        assert!(!endpoints.is_empty());
        assert!(endpoints[0].contains("eth"));
    }
    
    #[test]
    fn test_chain_from_id() {
        assert!(matches!(chain_from_id(1), Chain::Ethereum));
        assert!(matches!(chain_from_id(56), Chain::Bnb));
        assert!(matches!(chain_from_id(137), Chain::Polygon));
    }
}
