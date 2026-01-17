//! EVM Nonce Manager
//!
//! Manages nonces for EVM transactions to prevent conflicts
//! and enable proper transaction replacement (RBF/cancel).

use crate::error::{HawalaError, HawalaResult};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::sync::Mutex;
use std::time::Duration;

// =============================================================================
// Types
// =============================================================================

/// Nonce state for an address on a chain
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct NonceState {
    /// Last confirmed nonce (on-chain)
    pub confirmed_nonce: u64,
    /// Nonces currently pending in mempool
    pub pending_nonces: HashSet<u64>,
    /// Locally reserved nonces (not yet broadcast)
    pub reserved_nonces: HashSet<u64>,
}

/// Result of nonce fetch operation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NonceResult {
    pub address: String,
    pub chain_id: u64,
    pub nonce: u64,
    pub source: NonceSource,
}

/// Source of the nonce value
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NonceSource {
    /// From blockchain RPC
    Network,
    /// Calculated from local state
    Local,
    /// Reserved for pending transaction
    Reserved,
}

/// Nonce gap detection result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NonceGap {
    pub start: u64,
    pub end: u64,
    pub count: u64,
}

lazy_static::lazy_static! {
    /// Global nonce cache: chain_id -> address -> NonceState
    static ref NONCE_CACHE: Mutex<HashMap<u64, HashMap<String, NonceState>>> = 
        Mutex::new(HashMap::new());
}

// =============================================================================
// Public API
// =============================================================================

/// Get the next available nonce for an address
pub fn get_next_nonce(address: &str, chain_id: u64) -> HawalaResult<NonceResult> {
    // Fetch current nonce from network
    let network_nonce = fetch_network_nonce(address, chain_id)?;
    
    // Check local state for pending/reserved nonces
    let mut cache = NONCE_CACHE.lock().map_err(|_| HawalaError::internal("Lock failed"))?;
    let chain_cache = cache.entry(chain_id).or_default();
    let state = chain_cache.entry(address.to_lowercase()).or_default();
    
    // Update confirmed nonce if network is ahead
    if network_nonce > state.confirmed_nonce {
        state.confirmed_nonce = network_nonce;
        // Clear pending nonces that are now confirmed
        state.pending_nonces.retain(|&n| n >= network_nonce);
    }
    
    // Find next available nonce
    let mut next_nonce = network_nonce;
    while state.pending_nonces.contains(&next_nonce) || state.reserved_nonces.contains(&next_nonce) {
        next_nonce += 1;
    }
    
    let source = if next_nonce == network_nonce {
        NonceSource::Network
    } else {
        NonceSource::Local
    };
    
    Ok(NonceResult {
        address: address.to_string(),
        chain_id,
        nonce: next_nonce,
        source,
    })
}

/// Reserve a nonce for a pending transaction
pub fn reserve_nonce(address: &str, chain_id: u64, nonce: u64) -> HawalaResult<()> {
    let mut cache = NONCE_CACHE.lock().map_err(|_| HawalaError::internal("Lock failed"))?;
    let chain_cache = cache.entry(chain_id).or_default();
    let state = chain_cache.entry(address.to_lowercase()).or_default();
    
    state.reserved_nonces.insert(nonce);
    Ok(())
}

/// Mark a nonce as pending (transaction broadcast)
pub fn mark_nonce_pending(address: &str, chain_id: u64, nonce: u64) -> HawalaResult<()> {
    let mut cache = NONCE_CACHE.lock().map_err(|_| HawalaError::internal("Lock failed"))?;
    let chain_cache = cache.entry(chain_id).or_default();
    let state = chain_cache.entry(address.to_lowercase()).or_default();
    
    // Move from reserved to pending
    state.reserved_nonces.remove(&nonce);
    state.pending_nonces.insert(nonce);
    Ok(())
}

/// Confirm a nonce (transaction included in block)
pub fn confirm_nonce(address: &str, chain_id: u64, nonce: u64) -> HawalaResult<()> {
    let mut cache = NONCE_CACHE.lock().map_err(|_| HawalaError::internal("Lock failed"))?;
    let chain_cache = cache.entry(chain_id).or_default();
    let state = chain_cache.entry(address.to_lowercase()).or_default();
    
    state.pending_nonces.remove(&nonce);
    state.reserved_nonces.remove(&nonce);
    
    // Update confirmed nonce if this is higher
    if nonce >= state.confirmed_nonce {
        state.confirmed_nonce = nonce + 1;
    }
    
    Ok(())
}

/// Release a reserved/pending nonce (transaction failed/cancelled)
pub fn release_nonce(address: &str, chain_id: u64, nonce: u64) -> HawalaResult<()> {
    let mut cache = NONCE_CACHE.lock().map_err(|_| HawalaError::internal("Lock failed"))?;
    let chain_cache = cache.entry(chain_id).or_default();
    let state = chain_cache.entry(address.to_lowercase()).or_default();
    
    state.reserved_nonces.remove(&nonce);
    state.pending_nonces.remove(&nonce);
    Ok(())
}

/// Get nonce for replacement transaction (uses same nonce)
pub fn get_replacement_nonce(original_nonce: u64) -> u64 {
    original_nonce
}

/// Detect nonce gaps in pending transactions
pub fn detect_nonce_gaps(address: &str, chain_id: u64) -> HawalaResult<Vec<NonceGap>> {
    let cache = NONCE_CACHE.lock().map_err(|_| HawalaError::internal("Lock failed"))?;
    
    let state = cache
        .get(&chain_id)
        .and_then(|c| c.get(&address.to_lowercase()));
    
    let state = match state {
        Some(s) => s,
        None => return Ok(Vec::new()),
    };
    
    if state.pending_nonces.is_empty() {
        return Ok(Vec::new());
    }
    
    let mut sorted: Vec<_> = state.pending_nonces.iter().copied().collect();
    sorted.sort();
    
    let mut gaps = Vec::new();
    let mut expected = state.confirmed_nonce;
    
    for &nonce in &sorted {
        if nonce > expected {
            gaps.push(NonceGap {
                start: expected,
                end: nonce - 1,
                count: nonce - expected,
            });
        }
        expected = nonce + 1;
    }
    
    Ok(gaps)
}

/// Clear all cached state for an address
pub fn clear_nonce_cache(address: &str, chain_id: u64) -> HawalaResult<()> {
    let mut cache = NONCE_CACHE.lock().map_err(|_| HawalaError::internal("Lock failed"))?;
    
    if let Some(chain_cache) = cache.get_mut(&chain_id) {
        chain_cache.remove(&address.to_lowercase());
    }
    
    Ok(())
}

/// Sync nonce state with network
pub fn sync_nonce(address: &str, chain_id: u64) -> HawalaResult<u64> {
    let network_nonce = fetch_network_nonce(address, chain_id)?;
    
    let mut cache = NONCE_CACHE.lock().map_err(|_| HawalaError::internal("Lock failed"))?;
    let chain_cache = cache.entry(chain_id).or_default();
    let state = chain_cache.entry(address.to_lowercase()).or_default();
    
    state.confirmed_nonce = network_nonce;
    // Clear old pending nonces
    state.pending_nonces.retain(|&n| n >= network_nonce);
    state.reserved_nonces.retain(|&n| n >= network_nonce);
    
    Ok(network_nonce)
}

/// Get current nonce state for an address
pub fn get_nonce_state(address: &str, chain_id: u64) -> Option<NonceState> {
    NONCE_CACHE.lock().ok()?
        .get(&chain_id)?
        .get(&address.to_lowercase())
        .cloned()
}

// =============================================================================
// Network Functions
// =============================================================================

/// Fetch nonce from RPC endpoint
fn fetch_network_nonce(address: &str, chain_id: u64) -> HawalaResult<u64> {
    let endpoints = get_rpc_endpoints(chain_id);
    
    for endpoint in &endpoints {
        if let Ok(nonce) = fetch_nonce_from_rpc(address, endpoint) {
            return Ok(nonce);
        }
    }
    
    Err(HawalaError::network_error("All RPC endpoints failed"))
}

fn fetch_nonce_from_rpc(address: &str, rpc_url: &str) -> HawalaResult<u64> {
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(10))
        .build()
        .map_err(|e| HawalaError::network_error(format!("Client error: {}", e)))?;
    
    // Use "pending" to include mempool transactions
    let payload = serde_json::json!({
        "jsonrpc": "2.0",
        "method": "eth_getTransactionCount",
        "params": [address, "pending"],
        "id": 1
    });
    
    let response: serde_json::Value = client.post(rpc_url)
        .json(&payload)
        .send()
        .map_err(|e| HawalaError::network_error(format!("Request failed: {}", e)))?
        .json()
        .map_err(|e| HawalaError::parse_error(format!("Parse failed: {}", e)))?;
    
    let hex_nonce = response["result"]
        .as_str()
        .ok_or_else(|| HawalaError::parse_error("Missing result"))?;
    
    let nonce = u64::from_str_radix(hex_nonce.trim_start_matches("0x"), 16)
        .map_err(|_| HawalaError::parse_error("Invalid hex nonce"))?;
    
    Ok(nonce)
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
        ],
        56 => vec![
            "https://bsc-dataseed.binance.org",
            "https://bsc.publicnode.com",
        ],
        137 => vec![
            "https://polygon-rpc.com",
            "https://polygon.llamarpc.com",
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
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_nonce_gap_detection() {
        let mut state = NonceState::default();
        state.confirmed_nonce = 5;
        state.pending_nonces.insert(5);
        state.pending_nonces.insert(7); // Gap at 6
        state.pending_nonces.insert(8);
        state.pending_nonces.insert(10); // Gap at 9
        
        // Manually test gap detection logic
        let mut sorted: Vec<_> = state.pending_nonces.iter().copied().collect();
        sorted.sort();
        
        let mut gaps = Vec::new();
        let mut expected = state.confirmed_nonce;
        
        for &nonce in &sorted {
            if nonce > expected {
                gaps.push((expected, nonce - 1));
            }
            expected = nonce + 1;
        }
        
        assert_eq!(gaps.len(), 2);
        assert_eq!(gaps[0], (6, 6)); // Gap at 6
        assert_eq!(gaps[1], (9, 9)); // Gap at 9
    }
    
    #[test]
    fn test_replacement_nonce() {
        assert_eq!(get_replacement_nonce(42), 42);
    }
    
    #[test]
    fn test_rpc_endpoints() {
        let endpoints = get_rpc_endpoints(1);
        assert!(!endpoints.is_empty());
        
        let endpoints = get_rpc_endpoints(137);
        assert!(endpoints.iter().any(|e| e.contains("polygon")));
    }
}
