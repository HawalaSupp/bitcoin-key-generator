//! Address Whitelisting
//!
//! Provides address whitelisting functionality:
//! - Whitelist addresses for safe sending
//! - Require whitelist for high-value transactions
//! - Time-locked whitelist additions
//!
//! Inspired by exchange withdrawal whitelists

use crate::error::{HawalaError, HawalaResult, ErrorCode};
use crate::types::Chain;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::RwLock;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

// =============================================================================
// Types
// =============================================================================

/// A whitelisted address
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WhitelistEntry {
    /// The whitelisted address
    pub address: String,
    /// Optional label/name
    pub label: Option<String>,
    /// Chain(s) this whitelist applies to
    pub chains: Vec<Chain>,
    /// When this entry was added
    pub added_at: u64,
    /// When this entry becomes active (for time-lock)
    pub active_at: u64,
    /// Whether this entry is currently active
    pub is_active: bool,
    /// Optional notes
    pub notes: Option<String>,
}

/// Whitelist configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WhitelistConfig {
    /// Require whitelist for all transactions
    pub require_for_all: bool,
    /// Require whitelist for transactions above this USD value
    pub require_above_usd: Option<f64>,
    /// Time delay for new whitelist entries (seconds)
    pub time_lock_seconds: u64,
    /// Maximum entries allowed
    pub max_entries: usize,
    /// Allow sending to non-whitelisted with warning
    pub allow_with_warning: bool,
}

impl Default for WhitelistConfig {
    fn default() -> Self {
        Self {
            require_for_all: false,
            require_above_usd: Some(1000.0),
            time_lock_seconds: 24 * 60 * 60, // 24 hours
            max_entries: 100,
            allow_with_warning: true,
        }
    }
}

/// Result of checking an address against whitelist
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WhitelistCheckResult {
    /// Whether the address is whitelisted
    pub is_whitelisted: bool,
    /// The whitelist entry if found
    pub entry: Option<WhitelistEntry>,
    /// Whether transaction is allowed
    pub allowed: bool,
    /// Warning message if not whitelisted but allowed
    pub warning: Option<String>,
    /// Block reason if not allowed
    pub block_reason: Option<String>,
    /// Remaining time until entry becomes active (if pending)
    pub pending_seconds: Option<u64>,
}

/// Request to add to whitelist
#[derive(Debug, Clone, Deserialize)]
pub struct AddWhitelistRequest {
    /// Address to whitelist
    pub address: String,
    /// Optional label
    pub label: Option<String>,
    /// Chains to whitelist for (empty = all chains)
    pub chains: Vec<Chain>,
    /// Optional notes
    pub notes: Option<String>,
    /// Skip time lock (requires additional auth)
    pub skip_time_lock: bool,
}

// =============================================================================
// Whitelist Manager
// =============================================================================

/// Manages address whitelists
pub struct WhitelistManager {
    /// Whitelisted addresses by wallet ID
    entries: RwLock<HashMap<String, Vec<WhitelistEntry>>>,
    /// Configuration
    config: RwLock<WhitelistConfig>,
}

impl WhitelistManager {
    /// Create a new whitelist manager with default config
    pub fn new() -> Self {
        Self {
            entries: RwLock::new(HashMap::new()),
            config: RwLock::new(WhitelistConfig::default()),
        }
    }

    /// Create with custom configuration
    pub fn with_config(config: WhitelistConfig) -> Self {
        Self {
            entries: RwLock::new(HashMap::new()),
            config: RwLock::new(config),
        }
    }

    /// Get current configuration
    pub fn get_config(&self) -> WhitelistConfig {
        self.config.read()
            .map(|c| c.clone())
            .unwrap_or_default()
    }

    /// Update configuration
    pub fn set_config(&self, config: WhitelistConfig) {
        if let Ok(mut c) = self.config.write() {
            *c = config;
        }
    }

    /// Check if an address is whitelisted
    pub fn check_address(
        &self,
        wallet_id: &str,
        address: &str,
        chain: Chain,
        transaction_usd: Option<f64>,
    ) -> WhitelistCheckResult {
        let config = self.get_config();
        let address_lower = address.to_lowercase();
        let now = Self::current_timestamp();
        
        // Check whitelist
        let entry = self.get_entry(wallet_id, &address_lower, chain);
        
        if let Some(entry) = &entry {
            if entry.is_active && entry.active_at <= now {
                // Whitelisted and active
                return WhitelistCheckResult {
                    is_whitelisted: true,
                    entry: Some(entry.clone()),
                    allowed: true,
                    warning: None,
                    block_reason: None,
                    pending_seconds: None,
                };
            } else if !entry.is_active {
                // Pending time lock
                let remaining = entry.active_at.saturating_sub(now);
                return WhitelistCheckResult {
                    is_whitelisted: false,
                    entry: Some(entry.clone()),
                    allowed: config.allow_with_warning,
                    warning: Some(format!("Address is whitelisted but pending. Active in {} hours.", remaining / 3600)),
                    block_reason: if config.allow_with_warning { None } else { Some("Address whitelist pending".to_string()) },
                    pending_seconds: Some(remaining),
                };
            }
        }
        
        // Not whitelisted - check if allowed
        let (allowed, warning, block_reason) = self.evaluate_non_whitelisted(&config, transaction_usd);
        
        WhitelistCheckResult {
            is_whitelisted: false,
            entry: None,
            allowed,
            warning,
            block_reason,
            pending_seconds: None,
        }
    }

    /// Add an address to the whitelist
    pub fn add_address(
        &self,
        wallet_id: &str,
        request: AddWhitelistRequest,
    ) -> HawalaResult<WhitelistEntry> {
        let config = self.get_config();
        let address_lower = request.address.to_lowercase();
        let now = Self::current_timestamp();
        
        // Validate address format
        if !Self::is_valid_address(&address_lower) {
            return Err(HawalaError::new(ErrorCode::InvalidInput, "Invalid address format"));
        }
        
        // Check max entries
        if let Ok(entries) = self.entries.read() {
            if let Some(wallet_entries) = entries.get(wallet_id) {
                if wallet_entries.len() >= config.max_entries {
                    return Err(HawalaError::new(
                        ErrorCode::InvalidInput,
                        format!("Maximum {} whitelist entries reached", config.max_entries),
                    ));
                }
                
                // Check if already exists
                if wallet_entries.iter().any(|e| e.address.to_lowercase() == address_lower) {
                    return Err(HawalaError::new(ErrorCode::InvalidInput, "Address already whitelisted"));
                }
            }
        }
        
        // Calculate active time
        let active_at = if request.skip_time_lock {
            now // Immediate (requires additional auth in real implementation)
        } else {
            now + config.time_lock_seconds
        };
        
        let entry = WhitelistEntry {
            address: address_lower,
            label: request.label,
            chains: if request.chains.is_empty() {
                vec![Chain::Ethereum, Chain::Bitcoin, Chain::Solana] // Default to major chains
            } else {
                request.chains
            },
            added_at: now,
            active_at,
            is_active: request.skip_time_lock,
            notes: request.notes,
        };
        
        // Add to storage
        if let Ok(mut entries) = self.entries.write() {
            entries.entry(wallet_id.to_string())
                .or_insert_with(Vec::new)
                .push(entry.clone());
        }
        
        Ok(entry)
    }

    /// Remove an address from the whitelist
    pub fn remove_address(&self, wallet_id: &str, address: &str) -> HawalaResult<()> {
        let address_lower = address.to_lowercase();
        
        if let Ok(mut entries) = self.entries.write() {
            if let Some(wallet_entries) = entries.get_mut(wallet_id) {
                let original_len = wallet_entries.len();
                wallet_entries.retain(|e| e.address.to_lowercase() != address_lower);
                
                if wallet_entries.len() == original_len {
                    return Err(HawalaError::new(ErrorCode::InvalidInput, "Address not found in whitelist"));
                }
            } else {
                return Err(HawalaError::new(ErrorCode::InvalidInput, "Wallet has no whitelist entries"));
            }
        }
        
        Ok(())
    }

    /// Get all whitelist entries for a wallet
    pub fn get_all_entries(&self, wallet_id: &str) -> Vec<WhitelistEntry> {
        let now = Self::current_timestamp();
        
        if let Ok(entries) = self.entries.read() {
            if let Some(wallet_entries) = entries.get(wallet_id) {
                // Update active status based on time
                return wallet_entries.iter()
                    .map(|e| {
                        let mut entry = e.clone();
                        entry.is_active = entry.active_at <= now;
                        entry
                    })
                    .collect();
            }
        }
        
        Vec::new()
    }

    /// Update the label for a whitelisted address
    pub fn update_label(&self, wallet_id: &str, address: &str, label: Option<String>) -> HawalaResult<()> {
        let address_lower = address.to_lowercase();
        
        if let Ok(mut entries) = self.entries.write() {
            if let Some(wallet_entries) = entries.get_mut(wallet_id) {
                for entry in wallet_entries.iter_mut() {
                    if entry.address.to_lowercase() == address_lower {
                        entry.label = label;
                        return Ok(());
                    }
                }
            }
        }
        
        Err(HawalaError::new(ErrorCode::InvalidInput, "Address not found in whitelist"))
    }

    /// Activate a pending whitelist entry (skip time lock with auth)
    pub fn activate_immediately(&self, wallet_id: &str, address: &str) -> HawalaResult<()> {
        let address_lower = address.to_lowercase();
        let now = Self::current_timestamp();
        
        if let Ok(mut entries) = self.entries.write() {
            if let Some(wallet_entries) = entries.get_mut(wallet_id) {
                for entry in wallet_entries.iter_mut() {
                    if entry.address.to_lowercase() == address_lower {
                        entry.active_at = now;
                        entry.is_active = true;
                        return Ok(());
                    }
                }
            }
        }
        
        Err(HawalaError::new(ErrorCode::InvalidInput, "Address not found in whitelist"))
    }

    /// Clear all whitelist entries for a wallet
    pub fn clear_all(&self, wallet_id: &str) {
        if let Ok(mut entries) = self.entries.write() {
            entries.remove(wallet_id);
        }
    }

    // =========================================================================
    // Private Methods
    // =========================================================================

    fn get_entry(&self, wallet_id: &str, address: &str, chain: Chain) -> Option<WhitelistEntry> {
        if let Ok(entries) = self.entries.read() {
            if let Some(wallet_entries) = entries.get(wallet_id) {
                return wallet_entries.iter()
                    .find(|e| {
                        e.address.to_lowercase() == address &&
                        (e.chains.is_empty() || e.chains.contains(&chain))
                    })
                    .cloned();
            }
        }
        None
    }

    fn evaluate_non_whitelisted(
        &self,
        config: &WhitelistConfig,
        transaction_usd: Option<f64>,
    ) -> (bool, Option<String>, Option<String>) {
        // If whitelist required for all
        if config.require_for_all {
            if config.allow_with_warning {
                return (true, Some("Address not whitelisted. Consider adding to whitelist.".to_string()), None);
            } else {
                return (false, None, Some("Address must be whitelisted before sending.".to_string()));
            }
        }
        
        // If whitelist required above threshold
        if let (Some(threshold), Some(amount)) = (config.require_above_usd, transaction_usd) {
            if amount > threshold {
                if config.allow_with_warning {
                    return (
                        true,
                        Some(format!(
                            "Sending ${:.2} to non-whitelisted address. Consider adding to whitelist for amounts over ${:.0}.",
                            amount, threshold
                        )),
                        None,
                    );
                } else {
                    return (
                        false,
                        None,
                        Some(format!(
                            "Transactions over ${:.0} require whitelisted addresses.",
                            threshold
                        )),
                    );
                }
            }
        }
        
        // Allowed without warning
        (true, None, None)
    }

    fn is_valid_address(address: &str) -> bool {
        // Basic validation
        if address.starts_with("0x") {
            // EVM address
            address.len() == 42 && address[2..].chars().all(|c| c.is_ascii_hexdigit())
        } else if address.starts_with("bc1") || address.starts_with("tb1") {
            // Bitcoin bech32
            address.len() >= 14 && address.len() <= 90
        } else if address.starts_with("1") || address.starts_with("3") || address.starts_with("m") || address.starts_with("n") {
            // Bitcoin legacy/P2SH
            address.len() >= 26 && address.len() <= 35
        } else {
            // Allow other formats (Solana, etc.)
            address.len() >= 20 && address.len() <= 100
        }
    }

    fn current_timestamp() -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or(Duration::ZERO)
            .as_secs()
    }
}

impl Default for WhitelistManager {
    fn default() -> Self {
        Self::new()
    }
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_manager() {
        let manager = WhitelistManager::new();
        let config = manager.get_config();
        assert!(!config.require_for_all);
        assert!(config.require_above_usd.is_some());
    }

    #[test]
    fn test_add_address() {
        let manager = WhitelistManager::new();
        
        let request = AddWhitelistRequest {
            address: "0x1234567890123456789012345678901234567890".to_string(),
            label: Some("My Exchange".to_string()),
            chains: vec![Chain::Ethereum],
            notes: None,
            skip_time_lock: true,
        };
        
        let result = manager.add_address("wallet1", request);
        assert!(result.is_ok());
        
        let entry = result.unwrap();
        assert_eq!(entry.label, Some("My Exchange".to_string()));
        assert!(entry.is_active);
    }

    #[test]
    fn test_check_whitelisted() {
        let manager = WhitelistManager::new();
        
        let request = AddWhitelistRequest {
            address: "0x1234567890123456789012345678901234567890".to_string(),
            label: None,
            chains: vec![],
            notes: None,
            skip_time_lock: true,
        };
        
        manager.add_address("wallet1", request).unwrap();
        
        let result = manager.check_address(
            "wallet1",
            "0x1234567890123456789012345678901234567890",
            Chain::Ethereum,
            Some(5000.0),
        );
        
        assert!(result.is_whitelisted);
        assert!(result.allowed);
        assert!(result.warning.is_none());
    }

    #[test]
    fn test_check_not_whitelisted() {
        let manager = WhitelistManager::new();
        
        let result = manager.check_address(
            "wallet1",
            "0x0000000000000000000000000000000000000000",
            Chain::Ethereum,
            Some(5000.0),
        );
        
        assert!(!result.is_whitelisted);
        assert!(result.allowed); // Default allows with warning
        assert!(result.warning.is_some());
    }

    #[test]
    fn test_time_lock() {
        let manager = WhitelistManager::new();
        
        let request = AddWhitelistRequest {
            address: "0x1234567890123456789012345678901234567890".to_string(),
            label: None,
            chains: vec![],
            notes: None,
            skip_time_lock: false, // Enforce time lock
        };
        
        let entry = manager.add_address("wallet1", request).unwrap();
        assert!(!entry.is_active); // Should not be active yet
        assert!(entry.active_at > entry.added_at);
    }

    #[test]
    fn test_remove_address() {
        let manager = WhitelistManager::new();
        
        let request = AddWhitelistRequest {
            address: "0x1234567890123456789012345678901234567890".to_string(),
            label: None,
            chains: vec![],
            notes: None,
            skip_time_lock: true,
        };
        
        manager.add_address("wallet1", request).unwrap();
        
        let result = manager.remove_address("wallet1", "0x1234567890123456789012345678901234567890");
        assert!(result.is_ok());
        
        let entries = manager.get_all_entries("wallet1");
        assert!(entries.is_empty());
    }

    #[test]
    fn test_duplicate_prevention() {
        let manager = WhitelistManager::new();
        
        let request = AddWhitelistRequest {
            address: "0x1234567890123456789012345678901234567890".to_string(),
            label: None,
            chains: vec![],
            notes: None,
            skip_time_lock: true,
        };
        
        manager.add_address("wallet1", request.clone()).unwrap();
        
        // Try to add same address again
        let result = manager.add_address("wallet1", request);
        assert!(result.is_err());
    }

    #[test]
    fn test_case_insensitive() {
        let manager = WhitelistManager::new();
        
        let request = AddWhitelistRequest {
            address: "0xABCDEF1234567890123456789012345678901234".to_string(),
            label: None,
            chains: vec![],
            notes: None,
            skip_time_lock: true,
        };
        
        manager.add_address("wallet1", request).unwrap();
        
        // Check with lowercase
        let result = manager.check_address(
            "wallet1",
            "0xabcdef1234567890123456789012345678901234",
            Chain::Ethereum,
            None,
        );
        
        assert!(result.is_whitelisted);
    }
}
