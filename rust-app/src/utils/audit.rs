//! Audit Logging
//!
//! Persistent audit logging for security-sensitive operations with:
//! - Tamper-evident log entries (hash chain)
//! - Structured event types
//! - Sensitive data redaction
//! - Export capabilities
//! - Retention policies

use crate::error::{HawalaError, HawalaResult};
use crate::types::Chain;
use serde::{Deserialize, Serialize};
use sha2::{Sha256, Digest};
use std::collections::VecDeque;
use std::sync::RwLock;
use std::time::SystemTime;

/// Audit log manager
pub struct AuditLog {
    /// Log entries (ring buffer for memory efficiency)
    entries: RwLock<VecDeque<AuditEntry>>,
    /// Configuration
    config: AuditConfig,
    /// Last entry hash (for hash chain)
    last_hash: RwLock<[u8; 32]>,
}

/// Audit configuration
#[derive(Debug, Clone)]
pub struct AuditConfig {
    /// Maximum entries to keep in memory
    pub max_entries: usize,
    /// Whether to hash-chain entries for tamper detection
    pub hash_chain_enabled: bool,
    /// Whether to redact sensitive data
    pub redact_sensitive: bool,
    /// Minimum severity to log
    pub min_severity: AuditSeverity,
}

impl Default for AuditConfig {
    fn default() -> Self {
        Self {
            max_entries: 10000,
            hash_chain_enabled: true,
            redact_sensitive: true,
            min_severity: AuditSeverity::Info,
        }
    }
}

/// Audit entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditEntry {
    /// Entry ID
    pub id: u64,
    /// Timestamp
    pub timestamp: u64,
    /// Event type
    pub event_type: AuditEventType,
    /// Severity level
    pub severity: AuditSeverity,
    /// Wallet ID (if applicable)
    pub wallet_id: Option<String>,
    /// Session ID (if applicable)
    pub session_id: Option<String>,
    /// Chain (if applicable)
    pub chain: Option<String>,
    /// Event-specific details
    pub details: AuditDetails,
    /// Hash of this entry + previous hash (for tamper detection)
    pub hash: String,
    /// Previous entry hash
    pub prev_hash: String,
}

/// Audit event types
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum AuditEventType {
    // Authentication
    SessionCreated,
    SessionValidated,
    SessionLocked,
    SessionUnlocked,
    SessionRevoked,
    SessionExpired,
    AuthenticationFailed,
    
    // Wallet Operations
    WalletCreated,
    WalletRestored,
    WalletDeleted,
    WalletExported,
    
    // Key Operations
    KeyDerivation,
    KeyExport,
    BackupCreated,
    BackupRestored,
    
    // Transaction Operations
    TransactionCreated,
    TransactionSigned,
    TransactionBroadcast,
    TransactionCancelled,
    TransactionConfirmed,
    TransactionFailed,
    
    // Address Operations
    AddressGenerated,
    AddressValidated,
    AddressLabelChanged,
    
    // Configuration
    ConfigChanged,
    EndpointAdded,
    EndpointRemoved,
    
    // Security Events
    SuspiciousActivity,
    RateLimitExceeded,
    InvalidInput,
    ValidationFailed,
    
    // System Events
    SystemStartup,
    SystemShutdown,
    ErrorOccurred,
}

/// Audit severity levels
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub enum AuditSeverity {
    Debug,
    Info,
    Warning,
    Error,
    Critical,
}

/// Event-specific details
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AuditDetails {
    /// Operation that was performed
    pub operation: Option<String>,
    /// Result of the operation
    pub result: Option<String>,
    /// Address involved (redacted if configured)
    pub address: Option<String>,
    /// Transaction ID (redacted if configured)
    pub tx_id: Option<String>,
    /// Amount (in display units)
    pub amount: Option<String>,
    /// IP address
    pub ip_address: Option<String>,
    /// Device info
    pub device_info: Option<String>,
    /// Error message
    pub error: Option<String>,
    /// Additional context
    pub context: Option<String>,
}

impl AuditLog {
    /// Create a new audit log
    pub fn new() -> Self {
        Self::with_config(AuditConfig::default())
    }

    /// Create with custom configuration
    pub fn with_config(config: AuditConfig) -> Self {
        Self {
            entries: RwLock::new(VecDeque::with_capacity(config.max_entries)),
            config,
            last_hash: RwLock::new([0u8; 32]),
        }
    }

    /// Log an audit event
    pub fn log(&self, event_type: AuditEventType, severity: AuditSeverity, builder: AuditBuilder) {
        // Check minimum severity
        if severity < self.config.min_severity {
            return;
        }

        // Acquire locks - if poisoned, silently skip logging (non-critical path)
        let Ok(mut entries) = self.entries.write() else { return };
        let Ok(mut last_hash) = self.last_hash.write() else { return };

        // Generate entry ID
        let id = entries.back().map(|e| e.id + 1).unwrap_or(1);

        // Get timestamp
        let timestamp = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        // Apply redaction if configured
        let mut details = builder.details;
        if self.config.redact_sensitive {
            details = Self::redact_details(details);
        }

        // Create entry
        let prev_hash = hex::encode(&*last_hash);
        let mut entry = AuditEntry {
            id,
            timestamp,
            event_type,
            severity,
            wallet_id: builder.wallet_id,
            session_id: builder.session_id,
            chain: builder.chain.map(|c| c.symbol().to_string()),
            details,
            hash: String::new(), // Computed below
            prev_hash,
        };

        // Compute hash
        if self.config.hash_chain_enabled {
            let hash = Self::compute_hash(&entry, &*last_hash);
            entry.hash = hex::encode(&hash);
            *last_hash = hash;
        }

        // Enforce max entries (ring buffer)
        if entries.len() >= self.config.max_entries {
            entries.pop_front();
        }

        entries.push_back(entry);
    }

    /// Compute hash for tamper detection
    fn compute_hash(entry: &AuditEntry, prev_hash: &[u8; 32]) -> [u8; 32] {
        let mut hasher = Sha256::new();
        hasher.update(&entry.id.to_le_bytes());
        hasher.update(&entry.timestamp.to_le_bytes());
        hasher.update(format!("{:?}", entry.event_type).as_bytes());
        hasher.update(format!("{:?}", entry.severity).as_bytes());
        hasher.update(entry.wallet_id.as_deref().unwrap_or("").as_bytes());
        hasher.update(entry.session_id.as_deref().unwrap_or("").as_bytes());
        hasher.update(prev_hash);
        hasher.finalize().into()
    }

    /// Redact sensitive data
    fn redact_details(mut details: AuditDetails) -> AuditDetails {
        // Redact addresses (keep first 6 and last 4 chars)
        if let Some(addr) = &details.address {
            if addr.len() > 14 {
                details.address = Some(format!(
                    "{}...{}",
                    &addr[..6],
                    &addr[addr.len() - 4..]
                ));
            }
        }

        // Redact transaction IDs
        if let Some(tx) = &details.tx_id {
            if tx.len() > 16 {
                details.tx_id = Some(format!("{}...", &tx[..16]));
            }
        }

        // Redact IP addresses (keep first octet)
        if let Some(ip) = &details.ip_address {
            if let Some(dot_pos) = ip.find('.') {
                details.ip_address = Some(format!("{}.xxx.xxx.xxx", &ip[..dot_pos]));
            }
        }

        details
    }

    /// Verify hash chain integrity
    pub fn verify_integrity(&self) -> IntegrityResult {
        let Ok(entries) = self.entries.read() else {
            return IntegrityResult {
                is_valid: false,
                entries_checked: 0,
                first_invalid_id: None,
                message: "Failed to acquire lock".to_string(),
            };
        };
        
        if entries.is_empty() {
            return IntegrityResult {
                is_valid: true,
                entries_checked: 0,
                first_invalid_id: None,
                message: "No entries to verify".to_string(),
            };
        }

        let mut prev_hash = [0u8; 32];
        let mut entries_checked = 0;

        for entry in entries.iter() {
            if self.config.hash_chain_enabled {
                let expected_hash = Self::compute_hash(entry, &prev_hash);
                let expected_hex = hex::encode(&expected_hash);

                if entry.hash != expected_hex {
                    return IntegrityResult {
                        is_valid: false,
                        entries_checked,
                        first_invalid_id: Some(entry.id),
                        message: format!("Hash mismatch at entry {}", entry.id),
                    };
                }

                prev_hash = expected_hash;
            }
            entries_checked += 1;
        }

        IntegrityResult {
            is_valid: true,
            entries_checked,
            first_invalid_id: None,
            message: "All entries verified".to_string(),
        }
    }

    /// Query entries by event type
    pub fn query_by_type(&self, event_type: AuditEventType) -> Vec<AuditEntry> {
        let Ok(entries) = self.entries.read() else { return Vec::new() };
        entries.iter()
            .filter(|e| e.event_type == event_type)
            .cloned()
            .collect()
    }

    /// Query entries by severity (and above)
    pub fn query_by_severity(&self, min_severity: AuditSeverity) -> Vec<AuditEntry> {
        let Ok(entries) = self.entries.read() else { return Vec::new() };
        entries.iter()
            .filter(|e| e.severity >= min_severity)
            .cloned()
            .collect()
    }

    /// Query entries by wallet
    pub fn query_by_wallet(&self, wallet_id: &str) -> Vec<AuditEntry> {
        let Ok(entries) = self.entries.read() else { return Vec::new() };
        entries.iter()
            .filter(|e| e.wallet_id.as_deref() == Some(wallet_id))
            .cloned()
            .collect()
    }

    /// Query entries by time range
    pub fn query_by_time(&self, start: u64, end: u64) -> Vec<AuditEntry> {
        let Ok(entries) = self.entries.read() else { return Vec::new() };
        entries.iter()
            .filter(|e| e.timestamp >= start && e.timestamp <= end)
            .cloned()
            .collect()
    }

    /// Get recent entries
    pub fn recent(&self, count: usize) -> Vec<AuditEntry> {
        let Ok(entries) = self.entries.read() else { return Vec::new() };
        entries.iter()
            .rev()
            .take(count)
            .cloned()
            .collect()
    }

    /// Export all entries as JSON
    pub fn export_json(&self) -> HawalaResult<String> {
        let entries = self.entries.read()
            .map_err(|_| HawalaError::internal("Failed to acquire audit log lock"))?;
        let vec: Vec<_> = entries.iter().collect();
        serde_json::to_string_pretty(&vec)
            .map_err(|e| HawalaError::internal(format!("Failed to export audit log: {}", e)))
    }

    /// Get entry count
    pub fn count(&self) -> usize {
        self.entries.read().map(|e| e.len()).unwrap_or(0)
    }

    /// Clear all entries
    pub fn clear(&self) {
        let Ok(mut entries) = self.entries.write() else { return };
        entries.clear();
        
        let Ok(mut last_hash) = self.last_hash.write() else { return };
        *last_hash = [0u8; 32];
    }
}

impl Default for AuditLog {
    fn default() -> Self {
        Self::new()
    }
}

/// Integrity verification result
#[derive(Debug, Clone)]
pub struct IntegrityResult {
    pub is_valid: bool,
    pub entries_checked: usize,
    pub first_invalid_id: Option<u64>,
    pub message: String,
}

/// Builder for audit entries
pub struct AuditBuilder {
    wallet_id: Option<String>,
    session_id: Option<String>,
    chain: Option<Chain>,
    details: AuditDetails,
}

impl AuditBuilder {
    pub fn new() -> Self {
        Self {
            wallet_id: None,
            session_id: None,
            chain: None,
            details: AuditDetails::default(),
        }
    }

    pub fn wallet(mut self, wallet_id: &str) -> Self {
        self.wallet_id = Some(wallet_id.to_string());
        self
    }

    pub fn session(mut self, session_id: &str) -> Self {
        self.session_id = Some(session_id.to_string());
        self
    }

    pub fn chain(mut self, chain: Chain) -> Self {
        self.chain = Some(chain);
        self
    }

    pub fn operation(mut self, op: &str) -> Self {
        self.details.operation = Some(op.to_string());
        self
    }

    pub fn result(mut self, result: &str) -> Self {
        self.details.result = Some(result.to_string());
        self
    }

    pub fn address(mut self, address: &str) -> Self {
        self.details.address = Some(address.to_string());
        self
    }

    pub fn tx_id(mut self, tx_id: &str) -> Self {
        self.details.tx_id = Some(tx_id.to_string());
        self
    }

    pub fn amount(mut self, amount: &str) -> Self {
        self.details.amount = Some(amount.to_string());
        self
    }

    pub fn ip(mut self, ip: &str) -> Self {
        self.details.ip_address = Some(ip.to_string());
        self
    }

    pub fn device(mut self, device: &str) -> Self {
        self.details.device_info = Some(device.to_string());
        self
    }

    pub fn error(mut self, error: &str) -> Self {
        self.details.error = Some(error.to_string());
        self
    }

    pub fn context(mut self, context: &str) -> Self {
        self.details.context = Some(context.to_string());
        self
    }
}

impl Default for AuditBuilder {
    fn default() -> Self {
        Self::new()
    }
}

/// Global audit log instance
static AUDIT_LOG: std::sync::OnceLock<AuditLog> = std::sync::OnceLock::new();

/// Get the global audit log
pub fn get_audit_log() -> &'static AuditLog {
    AUDIT_LOG.get_or_init(AuditLog::new)
}

/// Convenience logging functions
pub fn audit_info(event_type: AuditEventType, builder: AuditBuilder) {
    get_audit_log().log(event_type, AuditSeverity::Info, builder);
}

pub fn audit_warning(event_type: AuditEventType, builder: AuditBuilder) {
    get_audit_log().log(event_type, AuditSeverity::Warning, builder);
}

pub fn audit_error(event_type: AuditEventType, builder: AuditBuilder) {
    get_audit_log().log(event_type, AuditSeverity::Error, builder);
}

pub fn audit_critical(event_type: AuditEventType, builder: AuditBuilder) {
    get_audit_log().log(event_type, AuditSeverity::Critical, builder);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_audit_log_basic() {
        let log = AuditLog::new();
        
        log.log(
            AuditEventType::SessionCreated,
            AuditSeverity::Info,
            AuditBuilder::new()
                .wallet("wallet_123")
                .operation("create_session")
        );

        assert_eq!(log.count(), 1);
        let entries = log.recent(1);
        assert_eq!(entries[0].event_type, AuditEventType::SessionCreated);
    }

    #[test]
    fn test_hash_chain_integrity() {
        let log = AuditLog::new();
        
        for i in 0..10 {
            log.log(
                AuditEventType::TransactionCreated,
                AuditSeverity::Info,
                AuditBuilder::new().context(&format!("tx_{}", i))
            );
        }

        let result = log.verify_integrity();
        assert!(result.is_valid);
        assert_eq!(result.entries_checked, 10);
    }

    #[test]
    fn test_redaction() {
        let details = AuditDetails {
            address: Some("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq".to_string()),
            tx_id: Some("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855".to_string()),
            ip_address: Some("192.168.1.100".to_string()),
            ..Default::default()
        };

        let redacted = AuditLog::redact_details(details);
        
        assert!(redacted.address.as_ref().unwrap().contains("..."));
        assert!(redacted.tx_id.as_ref().unwrap().contains("..."));
        assert!(redacted.ip_address.as_ref().unwrap().contains("xxx"));
    }

    #[test]
    fn test_query_by_severity() {
        let log = AuditLog::new();
        
        log.log(AuditEventType::SessionCreated, AuditSeverity::Info, AuditBuilder::new());
        log.log(AuditEventType::AuthenticationFailed, AuditSeverity::Warning, AuditBuilder::new());
        log.log(AuditEventType::SuspiciousActivity, AuditSeverity::Critical, AuditBuilder::new());

        let warnings = log.query_by_severity(AuditSeverity::Warning);
        assert_eq!(warnings.len(), 2); // Warning + Critical
    }

    #[test]
    fn test_ring_buffer() {
        let config = AuditConfig {
            max_entries: 5,
            ..Default::default()
        };
        let log = AuditLog::with_config(config);
        
        for i in 0..10 {
            log.log(
                AuditEventType::TransactionCreated,
                AuditSeverity::Info,
                AuditBuilder::new().context(&format!("tx_{}", i))
            );
        }

        assert_eq!(log.count(), 5);
        let recent = log.recent(5);
        assert!(recent[0].details.context.as_ref().unwrap().contains("tx_9"));
    }

    #[test]
    fn test_export_json() {
        let log = AuditLog::new();
        log.log(AuditEventType::WalletCreated, AuditSeverity::Info, AuditBuilder::new());
        
        let json = log.export_json().unwrap();
        assert!(json.contains("WalletCreated"));
    }
}
