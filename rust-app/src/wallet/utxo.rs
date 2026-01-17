//! UTXO Management
//!
//! Advanced UTXO handling for Bitcoin, Litecoin, and other UTXO-based chains.
//! Includes coin selection, privacy scoring, and manual coin control.

use crate::error::{HawalaError, HawalaResult};
use crate::types::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Duration;

// =============================================================================
// Types
// =============================================================================

/// Raw UTXO from blockchain API
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UTXO {
    pub txid: String,
    pub vout: u32,
    pub value: u64,
    pub confirmations: u32,
    #[serde(default)]
    pub script_pubkey: String,
}

impl UTXO {
    /// Create UTXO key for indexing
    pub fn key(&self) -> String {
        format!("{}:{}", self.txid, self.vout)
    }
    
    /// Get value in BTC/LTC
    pub fn value_btc(&self) -> f64 {
        self.value as f64 / 100_000_000.0
    }
}

/// UTXO with management metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ManagedUTXO {
    pub txid: String,
    pub vout: u32,
    pub value: u64,
    pub confirmations: u32,
    pub script_pubkey: String,
    pub address: String,
    pub metadata: UTXOMetadata,
    pub privacy_score: u8,
}

impl ManagedUTXO {
    pub fn key(&self) -> String {
        format!("{}:{}", self.txid, self.vout)
    }
    
    pub fn value_btc(&self) -> f64 {
        self.value as f64 / 100_000_000.0
    }
    
    pub fn short_txid(&self) -> String {
        if self.txid.len() >= 16 {
            format!("{}...{}", &self.txid[..8], &self.txid[self.txid.len()-8..])
        } else {
            self.txid.clone()
        }
    }
}

/// Metadata for UTXO management
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct UTXOMetadata {
    pub label: String,
    pub source: UTXOSource,
    pub is_frozen: bool,
    pub note: String,
}

/// Source category of a UTXO
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum UTXOSource {
    #[default]
    Unknown,
    Mining,
    Exchange,
    P2P,
    Salary,
    Gift,
    Change,
    SelfTransfer,
    CoinJoin,
    Lightning,
}

/// UTXO selection strategy
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum UTXOSelectionStrategy {
    LargestFirst,
    SmallestFirst,
    OldestFirst,
    NewestFirst,
    PrivacyOptimized,
    #[default]
    Optimal,
}

/// Result of UTXO selection
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UTXOSelection {
    pub selected: Vec<ManagedUTXO>,
    pub total_value: u64,
    pub input_count: usize,
    pub average_privacy_score: u8,
}

lazy_static::lazy_static! {
    static ref UTXO_METADATA: Mutex<HashMap<String, UTXOMetadata>> = Mutex::new(HashMap::new());
}

// =============================================================================
// Public API
// =============================================================================

/// Fetch UTXOs for an address
pub fn fetch_utxos(address: &str, chain: Chain) -> HawalaResult<Vec<UTXO>> {
    let base_url = match chain {
        Chain::Bitcoin => "https://mempool.space/api",
        Chain::BitcoinTestnet => "https://mempool.space/testnet/api",
        Chain::Litecoin => "https://litecoinspace.org/api",
        _ => return Err(HawalaError::invalid_input("UTXO fetch only supported for Bitcoin/Litecoin")),
    };
    
    let url = format!("{}/address/{}/utxo", base_url, address);
    
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(15))
        .build()
        .map_err(|e| HawalaError::network_error(format!("Failed to create client: {}", e)))?;
    
    let response: Vec<RawUTXOResponse> = client.get(&url)
        .send()
        .map_err(|e| HawalaError::network_error(format!("Failed to fetch UTXOs: {}", e)))?
        .json()
        .map_err(|e| HawalaError::parse_error(format!("Failed to parse UTXOs: {}", e)))?;
    
    let utxos = response.into_iter().map(|r| UTXO {
        txid: r.txid,
        vout: r.vout,
        value: r.value,
        confirmations: if r.status.confirmed {
            r.status.block_height.map(|_| 6).unwrap_or(1) // Simplified
        } else {
            0
        },
        script_pubkey: String::new(),
    }).collect();
    
    Ok(utxos)
}

/// Fetch and enrich UTXOs with metadata
pub fn fetch_managed_utxos(address: &str, chain: Chain) -> HawalaResult<Vec<ManagedUTXO>> {
    let utxos = fetch_utxos(address, chain)?;
    let metadata_map = UTXO_METADATA.lock()
        .map_err(|_| HawalaError::internal("UTXO metadata lock poisoned"))?;
    
    let managed = utxos.into_iter().map(|utxo| {
        let key = utxo.key();
        let metadata = metadata_map.get(&key).cloned().unwrap_or_default();
        let privacy_score = calculate_privacy_score(&utxo, &metadata);
        
        ManagedUTXO {
            txid: utxo.txid,
            vout: utxo.vout,
            value: utxo.value,
            confirmations: utxo.confirmations,
            script_pubkey: utxo.script_pubkey,
            address: address.to_string(),
            metadata,
            privacy_score,
        }
    }).collect();
    
    Ok(managed)
}

/// Select UTXOs for a target amount
pub fn select_utxos(
    utxos: &[ManagedUTXO],
    target_amount: u64,
    fee_rate: u64,
    strategy: UTXOSelectionStrategy,
) -> HawalaResult<UTXOSelection> {
    // Filter out frozen UTXOs
    let mut available: Vec<_> = utxos.iter()
        .filter(|u| !u.metadata.is_frozen)
        .cloned()
        .collect();
    
    // Sort by strategy
    sort_utxos(&mut available, strategy);
    
    // Estimate fee based on input count
    let estimate_fee = |count: usize| -> u64 {
        // Approximate: 148 bytes per input + 34 bytes per output + 10 bytes overhead
        let vsize = (count * 148 + 2 * 34 + 10) as u64;
        vsize * fee_rate
    };
    
    let mut selected = Vec::new();
    let mut total: u64 = 0;
    
    for utxo in available {
        let needed = target_amount + estimate_fee(selected.len() + 1);
        if total >= needed {
            break;
        }
        total += utxo.value;
        selected.push(utxo);
    }
    
    let needed_with_fee = target_amount + estimate_fee(selected.len());
    if total < needed_with_fee {
        return Err(HawalaError::insufficient_funds(format!(
            "Need {} sats, have {} sats",
            needed_with_fee, total
        )));
    }
    
    let avg_privacy = if selected.is_empty() {
        0
    } else {
        (selected.iter().map(|u| u.privacy_score as u32).sum::<u32>() / selected.len() as u32) as u8
    };
    
    Ok(UTXOSelection {
        total_value: total,
        input_count: selected.len(),
        average_privacy_score: avg_privacy,
        selected,
    })
}

/// Manual coin control - select specific UTXOs
pub fn coin_control(
    utxos: &[ManagedUTXO],
    selected_keys: &[String],
) -> Vec<ManagedUTXO> {
    utxos.iter()
        .filter(|u| selected_keys.contains(&u.key()) && !u.metadata.is_frozen)
        .cloned()
        .collect()
}

/// Set UTXO metadata
pub fn set_utxo_metadata(key: &str, metadata: UTXOMetadata) {
    if let Ok(mut map) = UTXO_METADATA.lock() {
        map.insert(key.to_string(), metadata);
    }
}

/// Get UTXO metadata
pub fn get_utxo_metadata(key: &str) -> Option<UTXOMetadata> {
    UTXO_METADATA.lock().ok()?.get(key).cloned()
}

/// Freeze/unfreeze a UTXO
pub fn set_utxo_frozen(key: &str, frozen: bool) {
    if let Ok(mut map) = UTXO_METADATA.lock() {
        let entry = map.entry(key.to_string()).or_default();
        entry.is_frozen = frozen;
    }
}

/// Set UTXO label
pub fn set_utxo_label(key: &str, label: &str) {
    if let Ok(mut map) = UTXO_METADATA.lock() {
        let entry = map.entry(key.to_string()).or_default();
        entry.label = label.to_string();
    }
}

/// Set UTXO source
pub fn set_utxo_source(key: &str, source: UTXOSource) {
    if let Ok(mut map) = UTXO_METADATA.lock() {
        let entry = map.entry(key.to_string()).or_default();
        entry.source = source;
    }
}

/// Get total balance from UTXOs
pub fn get_total_balance(utxos: &[ManagedUTXO]) -> u64 {
    utxos.iter().map(|u| u.value).sum()
}

/// Get spendable balance (excluding frozen)
pub fn get_spendable_balance(utxos: &[ManagedUTXO]) -> u64 {
    utxos.iter()
        .filter(|u| !u.metadata.is_frozen)
        .map(|u| u.value)
        .sum()
}

/// Get frozen balance
pub fn get_frozen_balance(utxos: &[ManagedUTXO]) -> u64 {
    utxos.iter()
        .filter(|u| u.metadata.is_frozen)
        .map(|u| u.value)
        .sum()
}

// =============================================================================
// Privacy Scoring
// =============================================================================

fn calculate_privacy_score(utxo: &UTXO, metadata: &UTXOMetadata) -> u8 {
    let mut score: i32 = 100;
    
    // Penalize low confirmation count
    if utxo.confirmations < 6 {
        score -= 10;
    }
    
    // Penalize round amounts (more obvious)
    let btc_value = utxo.value as f64 / 100_000_000.0;
    if (btc_value * 100.0).fract() < 0.001 { // Round to 2 decimal places
        score -= 15;
    }
    
    // Penalize known exchange sources
    if metadata.source == UTXOSource::Exchange {
        score -= 20;
    }
    
    // Penalize recent transactions
    if utxo.confirmations < 100 {
        score -= 5;
    }
    
    // Bonus for old coins
    if utxo.confirmations > 1000 {
        score += 10;
    }
    
    // Bonus for labeled coins
    if !metadata.label.is_empty() {
        score += 5;
    }
    
    // Bonus for CoinJoin
    if metadata.source == UTXOSource::CoinJoin {
        score += 20;
    }
    
    score.clamp(0, 100) as u8
}

// =============================================================================
// UTXO Sorting
// =============================================================================

fn sort_utxos(utxos: &mut [ManagedUTXO], strategy: UTXOSelectionStrategy) {
    match strategy {
        UTXOSelectionStrategy::LargestFirst => {
            utxos.sort_by(|a, b| b.value.cmp(&a.value));
        }
        UTXOSelectionStrategy::SmallestFirst => {
            utxos.sort_by(|a, b| a.value.cmp(&b.value));
        }
        UTXOSelectionStrategy::OldestFirst => {
            utxos.sort_by(|a, b| b.confirmations.cmp(&a.confirmations));
        }
        UTXOSelectionStrategy::NewestFirst => {
            utxos.sort_by(|a, b| a.confirmations.cmp(&b.confirmations));
        }
        UTXOSelectionStrategy::PrivacyOptimized => {
            utxos.sort_by(|a, b| b.privacy_score.cmp(&a.privacy_score));
        }
        UTXOSelectionStrategy::Optimal => {
            // Balance value and privacy
            utxos.sort_by(|a, b| {
                let a_score = (a.value / 100_000) + (a.privacy_score as u64 * 1000);
                let b_score = (b.value / 100_000) + (b.privacy_score as u64 * 1000);
                b_score.cmp(&a_score)
            });
        }
    }
}

// =============================================================================
// API Response Types
// =============================================================================

#[derive(Deserialize)]
struct RawUTXOResponse {
    txid: String,
    vout: u32,
    value: u64,
    status: UTXOStatus,
}

#[derive(Deserialize)]
struct UTXOStatus {
    confirmed: bool,
    block_height: Option<u64>,
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_utxo_key() {
        let utxo = UTXO {
            txid: "abc123".to_string(),
            vout: 0,
            value: 100000,
            confirmations: 6,
            script_pubkey: String::new(),
        };
        assert_eq!(utxo.key(), "abc123:0");
    }
    
    #[test]
    fn test_privacy_score() {
        let utxo = UTXO {
            txid: "test".to_string(),
            vout: 0,
            value: 100_000_000, // 1 BTC (round amount)
            confirmations: 1000,
            script_pubkey: String::new(),
        };
        
        let metadata = UTXOMetadata::default();
        let score = calculate_privacy_score(&utxo, &metadata);
        
        // Should have penalty for round amount, bonus for old
        assert!(score < 100);
        assert!(score > 50);
    }
    
    #[test]
    fn test_selection_strategy_sorting() {
        let mut utxos = vec![
            ManagedUTXO {
                txid: "a".to_string(), vout: 0, value: 1000,
                confirmations: 100, script_pubkey: String::new(),
                address: "addr".to_string(), metadata: Default::default(),
                privacy_score: 80,
            },
            ManagedUTXO {
                txid: "b".to_string(), vout: 0, value: 5000,
                confirmations: 10, script_pubkey: String::new(),
                address: "addr".to_string(), metadata: Default::default(),
                privacy_score: 60,
            },
        ];
        
        sort_utxos(&mut utxos, UTXOSelectionStrategy::LargestFirst);
        assert_eq!(utxos[0].value, 5000);
        
        sort_utxos(&mut utxos, UTXOSelectionStrategy::SmallestFirst);
        assert_eq!(utxos[0].value, 1000);
    }
}
