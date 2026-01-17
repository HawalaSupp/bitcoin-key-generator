//! Structured Logging with Sensitive Data Redaction
//!
//! Provides safe logging that automatically redacts:
//! - Private keys
//! - Mnemonics/seed phrases
//! - Passwords
//! - Full addresses (partial redaction)

use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};

/// Global flag to enable/disable debug logging
static DEBUG_ENABLED: AtomicBool = AtomicBool::new(false);

/// Enable debug logging
pub fn enable_debug() {
    DEBUG_ENABLED.store(true, Ordering::SeqCst);
}

/// Disable debug logging
pub fn disable_debug() {
    DEBUG_ENABLED.store(false, Ordering::SeqCst);
}

/// Check if debug logging is enabled
pub fn is_debug_enabled() -> bool {
    DEBUG_ENABLED.load(Ordering::SeqCst)
}

/// Log levels
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum LogLevel {
    Debug,
    Info,
    Warn,
    Error,
}

impl fmt::Display for LogLevel {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            LogLevel::Debug => write!(f, "DEBUG"),
            LogLevel::Info => write!(f, "INFO"),
            LogLevel::Warn => write!(f, "WARN"),
            LogLevel::Error => write!(f, "ERROR"),
        }
    }
}

/// Structured log entry
#[derive(Debug)]
pub struct LogEntry {
    pub level: LogLevel,
    pub module: &'static str,
    pub message: String,
    pub fields: Vec<(&'static str, String)>,
}

impl LogEntry {
    pub fn new(level: LogLevel, module: &'static str, message: impl Into<String>) -> Self {
        Self {
            level,
            module,
            message: message.into(),
            fields: Vec::new(),
        }
    }

    /// Add a field to the log entry (auto-redacts sensitive data)
    pub fn field(mut self, key: &'static str, value: impl fmt::Display) -> Self {
        let value_str = value.to_string();
        let redacted = redact_if_sensitive(key, &value_str);
        self.fields.push((key, redacted));
        self
    }

    /// Add a field with explicit redaction
    pub fn redacted_field(mut self, key: &'static str, value: impl fmt::Display) -> Self {
        let redacted = redact_value(&value.to_string());
        self.fields.push((key, redacted));
        self
    }

    /// Add an address field (partial redaction)
    pub fn address_field(mut self, key: &'static str, address: &str) -> Self {
        let redacted = redact_address(address);
        self.fields.push((key, redacted));
        self
    }

    /// Log the entry
    pub fn log(self) {
        // Skip debug logs if not enabled
        if self.level == LogLevel::Debug && !is_debug_enabled() {
            return;
        }

        let fields_str = self.fields
            .iter()
            .map(|(k, v)| format!("{}={}", k, v))
            .collect::<Vec<_>>()
            .join(" ");

        let timestamp = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S%.3fZ");
        
        if fields_str.is_empty() {
            eprintln!("[{}] {} [{}] {}", timestamp, self.level, self.module, self.message);
        } else {
            eprintln!("[{}] {} [{}] {} | {}", timestamp, self.level, self.module, self.message, fields_str);
        }
    }
}

/// Redact a value if the key suggests it's sensitive
fn redact_if_sensitive(key: &str, value: &str) -> String {
    let key_lower = key.to_lowercase();
    
    // Keys that should always be fully redacted
    let fully_redacted_keys = [
        "private_key", "privatekey", "secret", "seed", "mnemonic",
        "password", "passphrase", "wif", "private", "key_hex",
        "sender_key", "senderkey", "signing_key",
    ];
    
    for sensitive_key in &fully_redacted_keys {
        if key_lower.contains(sensitive_key) {
            return redact_value(value);
        }
    }
    
    // Keys that should be partially redacted (addresses)
    let address_keys = ["address", "recipient", "sender", "from", "to"];
    for addr_key in &address_keys {
        if key_lower.contains(addr_key) {
            return redact_address(value);
        }
    }
    
    // Keys with transaction hashes - show partial
    let hash_keys = ["txid", "tx_hash", "hash", "txhash"];
    for hash_key in &hash_keys {
        if key_lower.contains(hash_key) {
            return redact_hash(value);
        }
    }
    
    value.to_string()
}

/// Fully redact a sensitive value
fn redact_value(value: &str) -> String {
    if value.is_empty() {
        return "[EMPTY]".to_string();
    }
    
    let len = value.len();
    if len <= 4 {
        "[REDACTED]".to_string()
    } else {
        format!("[REDACTED:{}chars]", len)
    }
}

/// Partially redact an address (show first 6 and last 4 chars)
fn redact_address(address: &str) -> String {
    let trimmed = address.trim();
    
    if trimmed.is_empty() {
        return "[EMPTY]".to_string();
    }
    
    // For very short strings, just redact
    if trimmed.len() <= 10 {
        return redact_value(trimmed);
    }
    
    // Show prefix and suffix
    let prefix_len = if trimmed.starts_with("0x") { 8 } else { 6 };
    let suffix_len = 4;
    
    if trimmed.len() <= prefix_len + suffix_len + 3 {
        return redact_value(trimmed);
    }
    
    let prefix = &trimmed[..prefix_len];
    let suffix = &trimmed[trimmed.len() - suffix_len..];
    
    format!("{}...{}", prefix, suffix)
}

/// Partially redact a hash (show first 10 and last 6 chars)
fn redact_hash(hash: &str) -> String {
    let trimmed = hash.trim();
    
    if trimmed.is_empty() {
        return "[EMPTY]".to_string();
    }
    
    if trimmed.len() <= 20 {
        return trimmed.to_string(); // Short hashes shown fully
    }
    
    let prefix_len = if trimmed.starts_with("0x") { 12 } else { 10 };
    let suffix_len = 6;
    
    let prefix = &trimmed[..prefix_len];
    let suffix = &trimmed[trimmed.len() - suffix_len..];
    
    format!("{}...{}", prefix, suffix)
}

/// Convenience macro for debug logging
#[macro_export]
macro_rules! log_debug {
    ($module:expr, $msg:expr) => {
        $crate::utils::logging::LogEntry::new(
            $crate::utils::logging::LogLevel::Debug,
            $module,
            $msg
        ).log()
    };
    ($module:expr, $msg:expr, $($key:ident = $value:expr),* $(,)?) => {
        $crate::utils::logging::LogEntry::new(
            $crate::utils::logging::LogLevel::Debug,
            $module,
            $msg
        )
        $(.field(stringify!($key), &$value))*
        .log()
    };
}

/// Convenience macro for info logging
#[macro_export]
macro_rules! log_info {
    ($module:expr, $msg:expr) => {
        $crate::utils::logging::LogEntry::new(
            $crate::utils::logging::LogLevel::Info,
            $module,
            $msg
        ).log()
    };
    ($module:expr, $msg:expr, $($key:ident = $value:expr),* $(,)?) => {
        $crate::utils::logging::LogEntry::new(
            $crate::utils::logging::LogLevel::Info,
            $module,
            $msg
        )
        $(.field(stringify!($key), &$value))*
        .log()
    };
}

/// Convenience macro for warning logging
#[macro_export]
macro_rules! log_warn {
    ($module:expr, $msg:expr) => {
        $crate::utils::logging::LogEntry::new(
            $crate::utils::logging::LogLevel::Warn,
            $module,
            $msg
        ).log()
    };
    ($module:expr, $msg:expr, $($key:ident = $value:expr),* $(,)?) => {
        $crate::utils::logging::LogEntry::new(
            $crate::utils::logging::LogLevel::Warn,
            $module,
            $msg
        )
        $(.field(stringify!($key), &$value))*
        .log()
    };
}

/// Convenience macro for error logging
#[macro_export]
macro_rules! log_error {
    ($module:expr, $msg:expr) => {
        $crate::utils::logging::LogEntry::new(
            $crate::utils::logging::LogLevel::Error,
            $module,
            $msg
        ).log()
    };
    ($module:expr, $msg:expr, $($key:ident = $value:expr),* $(,)?) => {
        $crate::utils::logging::LogEntry::new(
            $crate::utils::logging::LogLevel::Error,
            $module,
            $msg
        )
        $(.field(stringify!($key), &$value))*
        .log()
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_redact_value() {
        assert_eq!(redact_value(""), "[EMPTY]");
        assert_eq!(redact_value("abc"), "[REDACTED]");
        assert_eq!(redact_value("secret_key_12345"), "[REDACTED:16chars]");
    }

    #[test]
    fn test_redact_address() {
        // Ethereum address
        let addr = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045";
        let redacted = redact_address(addr);
        assert!(redacted.starts_with("0xd8dA6B"));
        assert!(redacted.ends_with("6045"));
        assert!(redacted.contains("..."));
        
        // Bitcoin address
        let btc = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq";
        let redacted = redact_address(btc);
        assert!(redacted.starts_with("bc1qar"));
        assert!(redacted.ends_with("5mdq"));
    }

    #[test]
    fn test_redact_hash() {
        let hash = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
        let redacted = redact_hash(hash);
        assert!(redacted.starts_with("0x1234567890"));
        assert!(redacted.ends_with("abcdef"));
    }

    #[test]
    fn test_redact_if_sensitive() {
        // Private key - fully redacted
        assert!(redact_if_sensitive("private_key", "secret123").contains("REDACTED"));
        
        // Address - partially redacted
        let addr_redacted = redact_if_sensitive("address", "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045");
        assert!(addr_redacted.contains("..."));
        
        // Normal field - not redacted
        assert_eq!(redact_if_sensitive("amount", "100"), "100");
    }

    #[test]
    fn test_log_entry() {
        let entry = LogEntry::new(LogLevel::Info, "test", "Test message")
            .field("amount", "100")
            .field("private_key", "secret")
            .address_field("recipient", "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045");
        
        // Check that private_key was redacted
        let pk_field = entry.fields.iter().find(|(k, _)| *k == "private_key");
        assert!(pk_field.is_some());
        assert!(pk_field.unwrap().1.contains("REDACTED"));
        
        // Check that recipient was partially redacted
        let addr_field = entry.fields.iter().find(|(k, _)| *k == "recipient");
        assert!(addr_field.is_some());
        assert!(addr_field.unwrap().1.contains("..."));
    }
}
