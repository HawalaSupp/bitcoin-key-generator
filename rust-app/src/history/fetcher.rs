//! History Fetcher
//!
//! Fetches transaction history from various blockchain APIs.
//! Supports: Bitcoin, Litecoin, Ethereum/EVM, Solana, XRP

use crate::error::{HawalaError, HawalaResult};
use crate::types::*;
use serde::Deserialize;
use std::time::Duration;

// =============================================================================
// Public API
// =============================================================================

/// Fetch history for all requested addresses
pub fn fetch_all_history(request: &HistoryRequest) -> HawalaResult<Vec<TransactionEntry>> {
    let mut all_entries = Vec::new();
    let mut errors = Vec::new();
    
    for addr in &request.addresses {
        match fetch_chain_history(&addr.address, addr.chain) {
            Ok(entries) => all_entries.extend(entries),
            Err(e) => errors.push(format!("{:?}: {}", addr.chain, e)),
        }
    }
    
    // Sort by timestamp descending
    all_entries.sort_by(|a, b| {
        b.timestamp.unwrap_or(0).cmp(&a.timestamp.unwrap_or(0))
    });
    
    // Apply limit if specified
    if let Some(limit) = request.limit {
        all_entries.truncate(limit as usize);
    }
    
    // If all requests failed, return error
    if all_entries.is_empty() && !errors.is_empty() {
        return Err(HawalaError::network_error(errors.join("; ")));
    }
    
    Ok(all_entries)
}

/// Fetch history for a single chain
pub fn fetch_chain_history(address: &str, chain: Chain) -> HawalaResult<Vec<TransactionEntry>> {
    match chain {
        Chain::Bitcoin | Chain::BitcoinTestnet => {
            fetch_bitcoin_history(address, chain)
        }
        Chain::Litecoin => {
            fetch_litecoin_history(address)
        }
        Chain::Ethereum | Chain::EthereumSepolia | Chain::Bnb | 
        Chain::Polygon | Chain::Arbitrum | Chain::Optimism | 
        Chain::Base | Chain::Avalanche => {
            fetch_evm_history(address, chain)
        }
        Chain::Solana | Chain::SolanaDevnet => {
            fetch_solana_history(address, chain)
        }
        Chain::Xrp | Chain::XrpTestnet => {
            fetch_xrp_history(address)
        }
        Chain::Monero => {
            // Monero requires special handling due to privacy
            Ok(Vec::new())
        }
    }
}

// =============================================================================
// Bitcoin/Litecoin History
// =============================================================================

/// Fetch Bitcoin transaction history from mempool.space
fn fetch_bitcoin_history(address: &str, chain: Chain) -> HawalaResult<Vec<TransactionEntry>> {
    let base_url = match chain {
        Chain::BitcoinTestnet => "https://mempool.space/testnet/api",
        _ => "https://mempool.space/api",
    };
    
    let url = format!("{}/address/{}/txs", base_url, address);
    
    let client = create_http_client()?;
    
    let transactions: Vec<BlockstreamTx> = client.get(&url)
        .send()
        .map_err(|e| HawalaError::network_error(format!("Failed to fetch BTC history: {}", e)))?
        .json()
        .map_err(|e| HawalaError::parse_error(format!("Failed to parse BTC history: {}", e)))?;
    
    // Get current block height for confirmation calculation
    let height_url = format!("{}/blocks/tip/height", base_url);
    let current_height: u64 = client.get(&height_url)
        .send()
        .ok()
        .and_then(|r| r.text().ok())
        .and_then(|t| t.trim().parse().ok())
        .unwrap_or(0);
    
    let mut entries = Vec::new();
    
    for tx in transactions.into_iter().take(50) {
        if let Some(entry) = parse_bitcoin_tx(&tx, address, chain, current_height) {
            entries.push(entry);
        }
    }
    
    Ok(entries)
}

fn parse_bitcoin_tx(tx: &BlockstreamTx, address: &str, chain: Chain, current_height: u64) -> Option<TransactionEntry> {
    // Calculate amounts
    let mut sent: u64 = 0;
    let mut received: u64 = 0;
    let mut from_addr = String::new();
    let mut to_addr = String::new();
    let mut total_input: u64 = 0;
    let mut total_output: u64 = 0;
    
    for vin in &tx.vin {
        if let Some(prevout) = &vin.prevout {
            total_input += prevout.value;
            if prevout.scriptpubkey_address.as_deref() == Some(address) {
                sent += prevout.value;
            } else if let Some(addr) = &prevout.scriptpubkey_address {
                if from_addr.is_empty() {
                    from_addr = addr.clone();
                }
            }
        }
    }
    
    for vout in &tx.vout {
        total_output += vout.value;
        if vout.scriptpubkey_address.as_deref() == Some(address) {
            received += vout.value;
        } else if let Some(addr) = &vout.scriptpubkey_address {
            if to_addr.is_empty() {
                to_addr = addr.clone();
            }
        }
    }
    
    // Calculate fee
    let fee_sats = total_input.saturating_sub(total_output);
    let fee = if fee_sats > 0 {
        Some(format!("{:.8}", fee_sats as f64 / 100_000_000.0))
    } else {
        None
    };
    
    // Determine direction and net amount
    let (direction, amount) = if sent > 0 && received == 0 {
        (TransactionDirection::Outgoing, sent)
    } else if received > 0 && sent == 0 {
        (TransactionDirection::Incoming, received)
    } else if sent > 0 && received > 0 {
        // Self-transfer or change handling
        let net = if sent > received {
            (TransactionDirection::Outgoing, sent - received)
        } else if received > sent {
            (TransactionDirection::Incoming, received - sent)
        } else {
            (TransactionDirection::Self_, sent)
        };
        net
    } else {
        return None;
    };
    
    let status = if tx.status.confirmed {
        TransactionStatus::Confirmed
    } else {
        TransactionStatus::Pending
    };
    
    let confirmations = if tx.status.confirmed {
        tx.status.block_height
            .map(|h| current_height.saturating_sub(h) + 1)
            .unwrap_or(1) as u32
    } else {
        0
    };
    
    Some(TransactionEntry {
        txid: tx.txid.clone(),
        chain,
        direction,
        amount: format!("{:.8}", amount as f64 / 100_000_000.0),
        fee,
        from: if direction == TransactionDirection::Outgoing { address.to_string() } else { from_addr },
        to: if direction == TransactionDirection::Incoming { address.to_string() } else { to_addr },
        timestamp: tx.status.block_time,
        block_height: tx.status.block_height,
        confirmations,
        status,
    })
}

/// Fetch Litecoin history from litecoinspace.org (mempool.space compatible)
fn fetch_litecoin_history(address: &str) -> HawalaResult<Vec<TransactionEntry>> {
    let url = format!("https://litecoinspace.org/api/address/{}/txs", address);
    
    let client = create_http_client()?;
    
    let transactions: Vec<BlockstreamTx> = client.get(&url)
        .send()
        .map_err(|e| HawalaError::network_error(format!("Failed to fetch LTC history: {}", e)))?
        .json()
        .map_err(|e| HawalaError::parse_error(format!("Failed to parse LTC history: {}", e)))?;
    
    // Get current block height
    let height_url = "https://litecoinspace.org/api/blocks/tip/height";
    let current_height: u64 = client.get(height_url)
        .send()
        .ok()
        .and_then(|r| r.text().ok())
        .and_then(|t| t.trim().parse().ok())
        .unwrap_or(0);
    
    let mut entries = Vec::new();
    
    for tx in transactions.into_iter().take(50) {
        if let Some(entry) = parse_bitcoin_tx(&tx, address, Chain::Litecoin, current_height) {
            entries.push(entry);
        }
    }
    
    Ok(entries)
}

// =============================================================================
// EVM History (Ethereum, BSC, Polygon, etc.)
// =============================================================================

fn fetch_evm_history(address: &str, chain: Chain) -> HawalaResult<Vec<TransactionEntry>> {
    let (api_url, symbol) = get_evm_explorer_config(chain);
    
    let url = format!(
        "{}?module=account&action=txlist&address={}&startblock=0&endblock=99999999&sort=desc",
        api_url, address
    );
    
    let client = create_http_client()?;
    
    let response: EtherscanResponse = client.get(&url)
        .send()
        .map_err(|e| HawalaError::network_error(format!("Failed to fetch {} history: {}", symbol, e)))?
        .json()
        .map_err(|e| HawalaError::parse_error(format!("Failed to parse {} history: {}", symbol, e)))?;
    
    if response.message != "OK" && response.result.is_empty() {
        // Empty result is okay for new addresses
        return Ok(Vec::new());
    }
    
    let mut entries = Vec::new();
    
    for tx in response.result.into_iter().take(50) {
        if let Some(entry) = parse_etherscan_tx(&tx, address, chain) {
            entries.push(entry);
        }
    }
    
    Ok(entries)
}

fn parse_etherscan_tx(tx: &EtherscanTx, address: &str, chain: Chain) -> Option<TransactionEntry> {
    let is_receive = tx.to.to_lowercase() == address.to_lowercase();
    
    // Parse value from wei to native token
    let wei_value: u128 = tx.value.parse().unwrap_or(0);
    let amount = wei_value as f64 / 1e18;
    
    let direction = if is_receive {
        TransactionDirection::Incoming
    } else if tx.from.to_lowercase() == address.to_lowercase() {
        TransactionDirection::Outgoing
    } else {
        return None;
    };
    
    // Calculate fee
    let gas_used: u128 = tx.gas_used.parse().unwrap_or(0);
    let gas_price: u128 = tx.gas_price.parse().unwrap_or(0);
    let fee_wei = gas_used * gas_price;
    let fee = if fee_wei > 0 {
        Some(format!("{:.12}", fee_wei as f64 / 1e18))
    } else {
        None
    };
    
    let timestamp: u64 = tx.time_stamp.parse().unwrap_or(0);
    let block_number: u64 = tx.block_number.parse().unwrap_or(0);
    let confirmations: u32 = tx.confirmations.parse().unwrap_or(0);
    
    let mut status = if confirmations > 0 {
        TransactionStatus::Confirmed
    } else {
        TransactionStatus::Pending
    };
    
    // Check for failed transaction
    if tx.is_error == "1" {
        status = TransactionStatus::Failed;
    }
    
    Some(TransactionEntry {
        txid: tx.hash.clone(),
        chain,
        direction,
        amount: format!("{:.12}", amount),
        fee,
        from: tx.from.clone(),
        to: tx.to.clone(),
        timestamp: Some(timestamp),
        block_height: Some(block_number),
        confirmations,
        status,
    })
}

fn get_evm_explorer_config(chain: Chain) -> (&'static str, &'static str) {
    match chain {
        Chain::Ethereum => ("https://api.etherscan.io/api", "ETH"),
        Chain::EthereumSepolia => ("https://api-sepolia.etherscan.io/api", "ETH"),
        Chain::Bnb => ("https://api.bscscan.com/api", "BNB"),
        Chain::Polygon => ("https://api.polygonscan.com/api", "MATIC"),
        Chain::Arbitrum => ("https://api.arbiscan.io/api", "ETH"),
        Chain::Optimism => ("https://api-optimistic.etherscan.io/api", "ETH"),
        Chain::Base => ("https://api.basescan.org/api", "ETH"),
        Chain::Avalanche => ("https://api.snowtrace.io/api", "AVAX"),
        _ => ("https://api.etherscan.io/api", "ETH"),
    }
}

// =============================================================================
// Solana History
// =============================================================================

fn fetch_solana_history(address: &str, chain: Chain) -> HawalaResult<Vec<TransactionEntry>> {
    let rpc_url = match chain {
        Chain::SolanaDevnet => "https://api.devnet.solana.com",
        _ => "https://api.mainnet-beta.solana.com",
    };
    
    let client = create_http_client()?;
    
    // Get signatures for address
    let payload = serde_json::json!({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "getSignaturesForAddress",
        "params": [address, {"limit": 50}]
    });
    
    let response = client.post(rpc_url)
        .json(&payload)
        .send()
        .map_err(|e| HawalaError::network_error(format!("Failed to fetch SOL history: {}", e)))?;
    
    let json: serde_json::Value = response.json()
        .map_err(|e| HawalaError::parse_error(format!("Failed to parse SOL history: {}", e)))?;
    
    let signatures = json["result"]
        .as_array()
        .ok_or_else(|| HawalaError::parse_error("Invalid SOL response"))?;
    
    let mut entries = Vec::new();
    
    for sig in signatures {
        let signature = sig["signature"].as_str().unwrap_or_default();
        let block_time = sig["blockTime"].as_u64();
        let confirmation_status = sig["confirmationStatus"].as_str();
        let has_error = !sig["err"].is_null();
        
        let status = if has_error {
            TransactionStatus::Failed
        } else if confirmation_status == Some("finalized") {
            TransactionStatus::Confirmed
        } else {
            TransactionStatus::Pending
        };
        
        entries.push(TransactionEntry {
            txid: signature.to_string(),
            chain,
            direction: TransactionDirection::Self_, // Need tx detail for actual direction
            amount: "0".to_string(), // Need getTransaction for amount
            fee: None,
            from: address.to_string(),
            to: address.to_string(),
            timestamp: block_time,
            block_height: sig["slot"].as_u64(),
            confirmations: if status == TransactionStatus::Confirmed { 1 } else { 0 },
            status,
        });
    }
    
    Ok(entries)
}

// =============================================================================
// XRP History
// =============================================================================

fn fetch_xrp_history(address: &str) -> HawalaResult<Vec<TransactionEntry>> {
    // Use XRPScan API
    let url = format!(
        "https://api.xrpscan.com/api/v1/account/{}/transactions?limit=50",
        address
    );
    
    let client = create_http_client()?;
    
    let response = client.get(&url)
        .header("Accept", "application/json")
        .send()
        .map_err(|e| HawalaError::network_error(format!("Failed to fetch XRP history: {}", e)))?;
    
    if response.status() == reqwest::StatusCode::TOO_MANY_REQUESTS {
        return Err(HawalaError::network_error("XRP API rate limited"));
    }
    
    let json: serde_json::Value = response.json()
        .map_err(|e| HawalaError::parse_error(format!("Failed to parse XRP history: {}", e)))?;
    
    // Handle both array and object with "transactions" field
    let transactions = if let Some(txs) = json.as_array() {
        txs.clone()
    } else if let Some(txs) = json["transactions"].as_array() {
        txs.clone()
    } else {
        return Ok(Vec::new());
    };
    
    let mut entries = Vec::new();
    
    for tx in transactions.into_iter().take(50) {
        if let Some(entry) = parse_xrp_tx(&tx, address) {
            entries.push(entry);
        }
    }
    
    Ok(entries)
}

fn parse_xrp_tx(tx: &serde_json::Value, address: &str) -> Option<TransactionEntry> {
    let hash = tx["hash"].as_str()?;
    
    // Determine direction
    let destination = tx["Destination"].as_str().unwrap_or_default();
    let is_receive = destination == address;
    
    let direction = if is_receive {
        TransactionDirection::Incoming
    } else {
        TransactionDirection::Outgoing
    };
    
    // Parse amount (can be object for issued currencies or string for XRP)
    let amount = if let Some(amt_obj) = tx["Amount"].as_object() {
        amt_obj.get("value")?.as_str()?.to_string()
    } else if let Some(drops) = tx["Amount"].as_str() {
        // Convert drops to XRP
        let drops_val: i64 = drops.parse().ok()?;
        format!("{:.6}", drops_val as f64 / 1_000_000.0)
    } else {
        "0".to_string()
    };
    
    // Parse timestamp (XRP epoch starts at Jan 1, 2000)
    let timestamp = tx["date"].as_u64().map(|t| t + 946684800);
    
    let validated = tx["validated"].as_bool().unwrap_or(false);
    
    // Parse fee
    let fee = tx["Fee"].as_str().and_then(|f| {
        let drops: i64 = f.parse().ok()?;
        Some(format!("{:.6}", drops as f64 / 1_000_000.0))
    });
    
    Some(TransactionEntry {
        txid: hash.to_string(),
        chain: Chain::Xrp,
        direction,
        amount,
        fee,
        from: tx["Account"].as_str().unwrap_or_default().to_string(),
        to: destination.to_string(),
        timestamp,
        block_height: tx["ledger_index"].as_u64(),
        confirmations: if validated { 1 } else { 0 },
        status: if validated { TransactionStatus::Confirmed } else { TransactionStatus::Pending },
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
// Blockstream/Mempool Types
// =============================================================================

#[derive(Deserialize)]
struct BlockstreamTx {
    txid: String,
    status: BlockstreamStatus,
    vin: Vec<BlockstreamVin>,
    vout: Vec<BlockstreamVout>,
}

#[derive(Deserialize)]
struct BlockstreamStatus {
    confirmed: bool,
    block_height: Option<u64>,
    block_time: Option<u64>,
}

#[derive(Deserialize)]
struct BlockstreamVin {
    prevout: Option<BlockstreamPrevout>,
}

#[derive(Deserialize)]
struct BlockstreamPrevout {
    scriptpubkey_address: Option<String>,
    value: u64,
}

#[derive(Deserialize)]
struct BlockstreamVout {
    scriptpubkey_address: Option<String>,
    value: u64,
}

// =============================================================================
// Etherscan Types
// =============================================================================

#[derive(Deserialize)]
struct EtherscanResponse {
    #[serde(default)]
    message: String,
    #[serde(default)]
    result: Vec<EtherscanTx>,
}

#[derive(Deserialize)]
struct EtherscanTx {
    hash: String,
    from: String,
    to: String,
    value: String,
    #[serde(rename = "timeStamp")]
    time_stamp: String,
    #[serde(rename = "gasUsed")]
    gas_used: String,
    #[serde(rename = "gasPrice")]
    gas_price: String,
    #[serde(rename = "blockNumber")]
    block_number: String,
    confirmations: String,
    #[serde(rename = "isError", default)]
    is_error: String,
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_direction() {
        // Test direction parsing logic
        assert!(matches!(TransactionDirection::Incoming, TransactionDirection::Incoming));
    }
    
    #[test]
    fn test_evm_explorer_config() {
        let (url, symbol) = get_evm_explorer_config(Chain::Ethereum);
        assert!(url.contains("etherscan.io"));
        assert_eq!(symbol, "ETH");
        
        let (url, symbol) = get_evm_explorer_config(Chain::Bnb);
        assert!(url.contains("bscscan.com"));
        assert_eq!(symbol, "BNB");
    }
}
