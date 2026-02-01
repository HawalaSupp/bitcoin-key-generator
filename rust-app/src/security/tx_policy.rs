//! Transaction Policies
//!
//! Configurable transaction policies for:
//! - Spending limits (daily, weekly, per-tx)
//! - Address whitelisting requirements
//! - Time-based restrictions
//! - Chain-specific rules
//! - Approval workflows

use crate::error::{read_lock, write_lock, HawalaError, HawalaResult};
use crate::types::Chain;
use chrono::{Datelike, Timelike};
use std::collections::{HashMap, HashSet};
use std::sync::RwLock;
use std::time::{Duration, Instant, SystemTime};

/// Transaction policy manager
pub struct PolicyManager {
    /// Policies per wallet
    policies: RwLock<HashMap<String, WalletPolicy>>,
    /// Spending history for limit tracking
    spending_history: RwLock<HashMap<String, Vec<SpendRecord>>>,
    /// Global policies (apply to all wallets)
    global_policy: RwLock<GlobalPolicy>,
}

/// Wallet-specific policy
#[derive(Debug, Clone)]
pub struct WalletPolicy {
    pub wallet_id: String,
    pub enabled: bool,
    
    // Spending limits
    pub daily_limit: Option<u128>,
    pub weekly_limit: Option<u128>,
    pub monthly_limit: Option<u128>,
    pub per_tx_limit: Option<u128>,
    
    // Address restrictions
    pub require_whitelist: bool,
    pub whitelisted_addresses: HashSet<String>,
    pub blocked_addresses: HashSet<String>,
    
    // Time restrictions
    pub allowed_hours: Option<(u8, u8)>, // Start and end hour (0-23)
    pub allowed_days: Option<Vec<u8>>,   // Days of week (0=Sunday, 6=Saturday)
    
    // Chain restrictions
    pub allowed_chains: Option<HashSet<Chain>>,
    
    // Approval requirements
    pub require_approval_above: Option<u128>,
    pub cooldown_period: Option<Duration>,
}

/// Global policy (applies to all wallets)
#[derive(Debug, Clone)]
pub struct GlobalPolicy {
    /// Global daily limit
    pub global_daily_limit: Option<u128>,
    /// Emergency lockdown
    pub lockdown_enabled: bool,
    /// Maintenance mode
    pub maintenance_mode: bool,
    /// Blocked chains
    pub blocked_chains: HashSet<Chain>,
}

impl Default for GlobalPolicy {
    fn default() -> Self {
        Self {
            global_daily_limit: None,
            lockdown_enabled: false,
            maintenance_mode: false,
            blocked_chains: HashSet::new(),
        }
    }
}

/// Spending record
#[derive(Debug, Clone)]
#[allow(dead_code)]
struct SpendRecord {
    amount: u128,
    chain: Chain,
    recipient: String,
    timestamp: Instant,
    system_time: SystemTime,
}

/// Policy check result
#[derive(Debug, Clone)]
pub struct PolicyCheckResult {
    pub allowed: bool,
    pub violations: Vec<PolicyViolation>,
    pub warnings: Vec<String>,
    pub requires_approval: bool,
    pub remaining_daily_limit: Option<u128>,
    pub remaining_weekly_limit: Option<u128>,
}

/// Policy violation
#[derive(Debug, Clone)]
pub struct PolicyViolation {
    pub violation_type: ViolationType,
    pub message: String,
    pub limit: Option<u128>,
    pub actual: Option<u128>,
}

/// Types of policy violations
#[derive(Debug, Clone, PartialEq)]
pub enum ViolationType {
    DailyLimitExceeded,
    WeeklyLimitExceeded,
    MonthlyLimitExceeded,
    PerTxLimitExceeded,
    AddressNotWhitelisted,
    AddressBlocked,
    TimeRestriction,
    ChainNotAllowed,
    CooldownActive,
    GlobalLimitExceeded,
    SystemLockdown,
    MaintenanceMode,
}

impl Default for WalletPolicy {
    fn default() -> Self {
        Self {
            wallet_id: String::new(),
            enabled: false,
            daily_limit: None,
            weekly_limit: None,
            monthly_limit: None,
            per_tx_limit: None,
            require_whitelist: false,
            whitelisted_addresses: HashSet::new(),
            blocked_addresses: HashSet::new(),
            allowed_hours: None,
            allowed_days: None,
            allowed_chains: None,
            require_approval_above: None,
            cooldown_period: None,
        }
    }
}

impl PolicyManager {
    /// Create a new policy manager
    pub fn new() -> Self {
        Self {
            policies: RwLock::new(HashMap::new()),
            spending_history: RwLock::new(HashMap::new()),
            global_policy: RwLock::new(GlobalPolicy::default()),
        }
    }

    /// Check if a transaction is allowed by policies
    pub fn check_transaction(
        &self,
        wallet_id: &str,
        recipient: &str,
        amount: u128,
        chain: Chain,
    ) -> PolicyCheckResult {
        let mut violations = Vec::new();
        let mut warnings = Vec::new();
        let mut requires_approval = false;

        // Check global policy
        if let Ok(global) = read_lock(&self.global_policy) {
            
            if global.lockdown_enabled {
                violations.push(PolicyViolation {
                    violation_type: ViolationType::SystemLockdown,
                    message: "System is in emergency lockdown".to_string(),
                    limit: None,
                    actual: None,
                });
            }

            if global.maintenance_mode {
                violations.push(PolicyViolation {
                    violation_type: ViolationType::MaintenanceMode,
                    message: "System is in maintenance mode".to_string(),
                    limit: None,
                    actual: None,
                });
            }

            if global.blocked_chains.contains(&chain) {
                violations.push(PolicyViolation {
                    violation_type: ViolationType::ChainNotAllowed,
                    message: format!("{} transactions are currently blocked", chain.symbol()),
                    limit: None,
                    actual: None,
                });
            }

            if let Some(global_limit) = global.global_daily_limit {
                let today_total = self.get_daily_spending(wallet_id);
                if today_total + amount > global_limit {
                    violations.push(PolicyViolation {
                        violation_type: ViolationType::GlobalLimitExceeded,
                        message: "Global daily spending limit exceeded".to_string(),
                        limit: Some(global_limit),
                        actual: Some(today_total + amount),
                    });
                }
            }
        }

        // Check wallet-specific policy
        let policies = match read_lock(&self.policies) {
            Ok(p) => p,
            Err(_) => return PolicyCheckResult {
                allowed: false,
                violations: vec![PolicyViolation {
                    violation_type: ViolationType::SystemLockdown,
                    message: "Unable to read policies".to_string(),
                    limit: None,
                    actual: None,
                }],
                warnings: vec![],
                requires_approval: false,
                remaining_daily_limit: None,
                remaining_weekly_limit: None,
            },
        };
        if let Some(policy) = policies.get(wallet_id) {
            if policy.enabled {
                // Per-transaction limit
                if let Some(limit) = policy.per_tx_limit {
                    if amount > limit {
                        violations.push(PolicyViolation {
                            violation_type: ViolationType::PerTxLimitExceeded,
                            message: "Transaction exceeds per-transaction limit".to_string(),
                            limit: Some(limit),
                            actual: Some(amount),
                        });
                    }
                }

                // Daily limit
                if let Some(limit) = policy.daily_limit {
                    let today_total = self.get_daily_spending(wallet_id);
                    if today_total + amount > limit {
                        violations.push(PolicyViolation {
                            violation_type: ViolationType::DailyLimitExceeded,
                            message: "Daily spending limit exceeded".to_string(),
                            limit: Some(limit),
                            actual: Some(today_total + amount),
                        });
                    }
                }

                // Weekly limit
                if let Some(limit) = policy.weekly_limit {
                    let week_total = self.get_weekly_spending(wallet_id);
                    if week_total + amount > limit {
                        violations.push(PolicyViolation {
                            violation_type: ViolationType::WeeklyLimitExceeded,
                            message: "Weekly spending limit exceeded".to_string(),
                            limit: Some(limit),
                            actual: Some(week_total + amount),
                        });
                    }
                }

                // Monthly limit
                if let Some(limit) = policy.monthly_limit {
                    let month_total = self.get_monthly_spending(wallet_id);
                    if month_total + amount > limit {
                        violations.push(PolicyViolation {
                            violation_type: ViolationType::MonthlyLimitExceeded,
                            message: "Monthly spending limit exceeded".to_string(),
                            limit: Some(limit),
                            actual: Some(month_total + amount),
                        });
                    }
                }

                // Address whitelist
                let normalized_recipient = recipient.to_lowercase();
                if policy.require_whitelist {
                    if !policy.whitelisted_addresses.contains(&normalized_recipient) {
                        violations.push(PolicyViolation {
                            violation_type: ViolationType::AddressNotWhitelisted,
                            message: "Recipient address is not whitelisted".to_string(),
                            limit: None,
                            actual: None,
                        });
                    }
                }

                // Address blocklist
                if policy.blocked_addresses.contains(&normalized_recipient) {
                    violations.push(PolicyViolation {
                        violation_type: ViolationType::AddressBlocked,
                        message: "Recipient address is blocked".to_string(),
                        limit: None,
                        actual: None,
                    });
                }

                // Time restrictions
                if let Some((start, end)) = policy.allowed_hours {
                    let hour = chrono::Local::now().hour() as u8;
                    let allowed = if start <= end {
                        hour >= start && hour < end
                    } else {
                        hour >= start || hour < end
                    };
                    
                    if !allowed {
                        violations.push(PolicyViolation {
                            violation_type: ViolationType::TimeRestriction,
                            message: format!(
                                "Transactions only allowed between {}:00 and {}:00",
                                start, end
                            ),
                            limit: None,
                            actual: None,
                        });
                    }
                }

                // Day restrictions
                if let Some(ref days) = policy.allowed_days {
                    let today = chrono::Local::now().weekday().num_days_from_sunday() as u8;
                    if !days.contains(&today) {
                        violations.push(PolicyViolation {
                            violation_type: ViolationType::TimeRestriction,
                            message: "Transactions not allowed on this day".to_string(),
                            limit: None,
                            actual: None,
                        });
                    }
                }

                // Chain restrictions
                if let Some(ref allowed) = policy.allowed_chains {
                    if !allowed.contains(&chain) {
                        violations.push(PolicyViolation {
                            violation_type: ViolationType::ChainNotAllowed,
                            message: format!("{} transactions are not allowed", chain.symbol()),
                            limit: None,
                            actual: None,
                        });
                    }
                }

                // Cooldown check
                if let Some(cooldown) = policy.cooldown_period {
                    if let Some(last_tx) = self.get_last_transaction_time(wallet_id) {
                        if last_tx.elapsed() < cooldown {
                            let remaining = cooldown - last_tx.elapsed();
                            violations.push(PolicyViolation {
                                violation_type: ViolationType::CooldownActive,
                                message: format!(
                                    "Cooldown active. Wait {} seconds.",
                                    remaining.as_secs()
                                ),
                                limit: None,
                                actual: None,
                            });
                        }
                    }
                }

                // Approval threshold
                if let Some(threshold) = policy.require_approval_above {
                    if amount >= threshold {
                        requires_approval = true;
                        warnings.push(format!(
                            "Transaction of {} requires approval (threshold: {})",
                            amount, threshold
                        ));
                    }
                }
            }
        }

        // Calculate remaining limits
        let policies = match read_lock(&self.policies) {
            Ok(p) => p,
            Err(_) => return PolicyCheckResult {
                allowed: violations.is_empty(),
                violations,
                warnings,
                requires_approval,
                remaining_daily_limit: None,
                remaining_weekly_limit: None,
            },
        };
        let remaining_daily = policies.get(wallet_id)
            .and_then(|p| p.daily_limit)
            .map(|limit| limit.saturating_sub(self.get_daily_spending(wallet_id)));

        let remaining_weekly = policies.get(wallet_id)
            .and_then(|p| p.weekly_limit)
            .map(|limit| limit.saturating_sub(self.get_weekly_spending(wallet_id)));

        PolicyCheckResult {
            allowed: violations.is_empty(),
            violations,
            warnings,
            requires_approval,
            remaining_daily_limit: remaining_daily,
            remaining_weekly_limit: remaining_weekly,
        }
    }

    /// Record a completed transaction
    pub fn record_transaction(
        &self,
        wallet_id: &str,
        recipient: &str,
        amount: u128,
        chain: Chain,
    ) {
        let record = SpendRecord {
            amount,
            chain,
            recipient: recipient.to_lowercase(),
            timestamp: Instant::now(),
            system_time: SystemTime::now(),
        };

        if let Ok(mut history) = write_lock(&self.spending_history) {
            history
                .entry(wallet_id.to_string())
                .or_insert_with(Vec::new)
                .push(record);

            // Clean up old records (older than 31 days)
            if let Some(records) = history.get_mut(wallet_id) {
                let cutoff = SystemTime::now() - Duration::from_secs(31 * 24 * 60 * 60);
                records.retain(|r| r.system_time > cutoff);
            }
        }
    }

    /// Set policy for a wallet
    pub fn set_policy(&self, wallet_id: &str, policy: WalletPolicy) {
        if let Ok(mut policies) = write_lock(&self.policies) {
            let mut policy = policy;
            policy.wallet_id = wallet_id.to_string();
            policies.insert(wallet_id.to_string(), policy);
        }
    }

    /// Get policy for a wallet
    pub fn get_policy(&self, wallet_id: &str) -> Option<WalletPolicy> {
        read_lock(&self.policies)
            .ok()
            .and_then(|policies| policies.get(wallet_id).cloned())
    }

    /// Enable/disable policy for a wallet
    pub fn set_policy_enabled(&self, wallet_id: &str, enabled: bool) -> HawalaResult<()> {
        let mut policies = write_lock(&self.policies)?;
        if let Some(policy) = policies.get_mut(wallet_id) {
            policy.enabled = enabled;
            Ok(())
        } else {
            Err(HawalaError::invalid_input("Policy not found for wallet"))
        }
    }

    /// Set global lockdown
    pub fn set_lockdown(&self, enabled: bool) {
        if let Ok(mut global) = write_lock(&self.global_policy) {
            global.lockdown_enabled = enabled;
        }
    }

    /// Set maintenance mode
    pub fn set_maintenance_mode(&self, enabled: bool) {
        if let Ok(mut global) = write_lock(&self.global_policy) {
            global.maintenance_mode = enabled;
        }
    }

    /// Add address to wallet whitelist
    pub fn whitelist_address(&self, wallet_id: &str, address: &str) -> HawalaResult<()> {
        let mut policies = write_lock(&self.policies)?;
        let policy = policies.entry(wallet_id.to_string())
            .or_insert_with(|| {
                let mut p = WalletPolicy::default();
                p.wallet_id = wallet_id.to_string();
                p
            });
        
        policy.whitelisted_addresses.insert(address.to_lowercase());
        Ok(())
    }

    /// Remove address from wallet whitelist
    pub fn remove_whitelist_address(&self, wallet_id: &str, address: &str) -> HawalaResult<()> {
        if let Ok(mut policies) = write_lock(&self.policies) {
            if let Some(policy) = policies.get_mut(wallet_id) {
                policy.whitelisted_addresses.remove(&address.to_lowercase());
            }
        }
        Ok(())
    }

    /// Block an address
    pub fn block_address(&self, wallet_id: &str, address: &str) -> HawalaResult<()> {
        let mut policies = write_lock(&self.policies)?;
        let policy = policies.entry(wallet_id.to_string())
            .or_insert_with(|| {
                let mut p = WalletPolicy::default();
                p.wallet_id = wallet_id.to_string();
                p
            });
        
        policy.blocked_addresses.insert(address.to_lowercase());
        Ok(())
    }

    /// Get daily spending for a wallet
    fn get_daily_spending(&self, wallet_id: &str) -> u128 {
        let history = match read_lock(&self.spending_history) {
            Ok(h) => h,
            Err(_) => return 0,
        };
        let one_day_ago = SystemTime::now() - Duration::from_secs(24 * 60 * 60);
        
        history.get(wallet_id)
            .map(|records| {
                records.iter()
                    .filter(|r| r.system_time > one_day_ago)
                    .map(|r| r.amount)
                    .sum()
            })
            .unwrap_or(0)
    }

    /// Get weekly spending for a wallet
    fn get_weekly_spending(&self, wallet_id: &str) -> u128 {
        let history = match read_lock(&self.spending_history) {
            Ok(h) => h,
            Err(_) => return 0,
        };
        let one_week_ago = SystemTime::now() - Duration::from_secs(7 * 24 * 60 * 60);
        
        history.get(wallet_id)
            .map(|records| {
                records.iter()
                    .filter(|r| r.system_time > one_week_ago)
                    .map(|r| r.amount)
                    .sum()
            })
            .unwrap_or(0)
    }

    /// Get monthly spending for a wallet
    fn get_monthly_spending(&self, wallet_id: &str) -> u128 {
        let history = match read_lock(&self.spending_history) {
            Ok(h) => h,
            Err(_) => return 0,
        };
        let one_month_ago = SystemTime::now() - Duration::from_secs(30 * 24 * 60 * 60);
        
        history.get(wallet_id)
            .map(|records| {
                records.iter()
                    .filter(|r| r.system_time > one_month_ago)
                    .map(|r| r.amount)
                    .sum()
            })
            .unwrap_or(0)
    }

    /// Get last transaction time
    fn get_last_transaction_time(&self, wallet_id: &str) -> Option<Instant> {
        read_lock(&self.spending_history)
            .ok()
            .and_then(|history| {
                history.get(wallet_id)
                    .and_then(|records| records.last())
                    .map(|r| r.timestamp)
            })
    }
}

impl Default for PolicyManager {
    fn default() -> Self {
        Self::new()
    }
}

/// Global policy manager instance
static POLICY_MANAGER: std::sync::OnceLock<PolicyManager> = std::sync::OnceLock::new();

/// Get the global policy manager
pub fn get_policy_manager() -> &'static PolicyManager {
    POLICY_MANAGER.get_or_init(PolicyManager::new)
}

/// Check if a transaction is allowed (convenience function)
pub fn check_transaction_policy(
    wallet_id: &str,
    recipient: &str,
    amount: u128,
    chain: Chain,
) -> PolicyCheckResult {
    get_policy_manager().check_transaction(wallet_id, recipient, amount, chain)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_per_tx_limit() {
        let manager = PolicyManager::new();
        
        let mut policy = WalletPolicy::default();
        policy.enabled = true;
        policy.per_tx_limit = Some(1000);
        manager.set_policy("wallet1", policy);

        // Under limit - allowed
        let result = manager.check_transaction("wallet1", "recipient", 500, Chain::Ethereum);
        assert!(result.allowed);

        // Over limit - blocked
        let result = manager.check_transaction("wallet1", "recipient", 2000, Chain::Ethereum);
        assert!(!result.allowed);
        assert!(result.violations.iter().any(|v| v.violation_type == ViolationType::PerTxLimitExceeded));
    }

    #[test]
    fn test_daily_limit() {
        let manager = PolicyManager::new();
        
        let mut policy = WalletPolicy::default();
        policy.enabled = true;
        policy.daily_limit = Some(1000);
        manager.set_policy("wallet1", policy);

        // Record some spending
        manager.record_transaction("wallet1", "recipient", 600, Chain::Ethereum);

        // Check remaining
        let result = manager.check_transaction("wallet1", "recipient", 300, Chain::Ethereum);
        assert!(result.allowed);

        // Would exceed
        let result = manager.check_transaction("wallet1", "recipient", 500, Chain::Ethereum);
        assert!(!result.allowed);
        assert!(result.violations.iter().any(|v| v.violation_type == ViolationType::DailyLimitExceeded));
    }

    #[test]
    fn test_whitelist_required() {
        let manager = PolicyManager::new();
        
        let mut policy = WalletPolicy::default();
        policy.enabled = true;
        policy.require_whitelist = true;
        policy.whitelisted_addresses.insert("0xallowed".to_string());
        manager.set_policy("wallet1", policy);

        // Whitelisted - allowed
        let result = manager.check_transaction("wallet1", "0xallowed", 100, Chain::Ethereum);
        assert!(result.allowed);

        // Not whitelisted - blocked
        let result = manager.check_transaction("wallet1", "0xnotallowed", 100, Chain::Ethereum);
        assert!(!result.allowed);
        assert!(result.violations.iter().any(|v| v.violation_type == ViolationType::AddressNotWhitelisted));
    }

    #[test]
    fn test_address_blocked() {
        let manager = PolicyManager::new();
        
        manager.block_address("wallet1", "0xbad").unwrap();
        
        let mut policy = WalletPolicy::default();
        policy.enabled = true;
        manager.set_policy("wallet1", policy);
        
        // Get policy and enable it with blocked address
        let mut updated = manager.get_policy("wallet1").unwrap();
        updated.blocked_addresses.insert("0xbad".to_string());
        updated.enabled = true;
        manager.set_policy("wallet1", updated);

        let result = manager.check_transaction("wallet1", "0xbad", 100, Chain::Ethereum);
        assert!(!result.allowed);
        assert!(result.violations.iter().any(|v| v.violation_type == ViolationType::AddressBlocked));
    }

    #[test]
    fn test_global_lockdown() {
        let manager = PolicyManager::new();
        
        // Enable lockdown
        manager.set_lockdown(true);

        let result = manager.check_transaction("wallet1", "recipient", 100, Chain::Ethereum);
        assert!(!result.allowed);
        assert!(result.violations.iter().any(|v| v.violation_type == ViolationType::SystemLockdown));

        // Disable lockdown
        manager.set_lockdown(false);
        let result = manager.check_transaction("wallet1", "recipient", 100, Chain::Ethereum);
        assert!(result.allowed);
    }

    #[test]
    fn test_remaining_limits() {
        let manager = PolicyManager::new();
        
        let mut policy = WalletPolicy::default();
        policy.enabled = true;
        policy.daily_limit = Some(1000);
        policy.weekly_limit = Some(5000);
        manager.set_policy("wallet1", policy);

        manager.record_transaction("wallet1", "recipient", 300, Chain::Ethereum);

        let result = manager.check_transaction("wallet1", "recipient", 100, Chain::Ethereum);
        assert_eq!(result.remaining_daily_limit, Some(700));
        assert_eq!(result.remaining_weekly_limit, Some(4700));
    }
}
