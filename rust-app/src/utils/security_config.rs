//! Security Configuration Manager
//!
//! Centralized security configuration with:
//! - Security level presets (standard, high, paranoid)
//! - Runtime configuration updates
//! - Feature flags for security options
//! - Validation of security settings

use crate::error::{HawalaError, HawalaResult};
use std::sync::RwLock;
use std::time::Duration;

/// Global security configuration manager
pub struct SecurityConfig {
    /// Current configuration
    config: RwLock<SecuritySettings>,
}

/// Security settings
#[derive(Debug, Clone)]
pub struct SecuritySettings {
    /// Security level preset
    pub level: SecurityLevel,
    
    // Session settings
    /// Session timeout (inactivity)
    pub session_timeout: Duration,
    /// Maximum session duration
    pub max_session_duration: Duration,
    /// Require re-auth for sensitive operations
    pub require_reauth_for_send: bool,
    /// Re-auth timeout
    pub sensitive_op_timeout: Duration,
    
    // Network settings
    /// Require HTTPS for all endpoints
    pub require_https: bool,
    /// Allow custom RPC endpoints
    pub allow_custom_endpoints: bool,
    /// Validate endpoint TLS certificates
    pub validate_certificates: bool,
    
    // Transaction settings
    /// Maximum transaction value without extra confirmation
    pub high_value_threshold: u64,
    /// Require confirmation for new addresses
    pub confirm_new_addresses: bool,
    /// Enable address whitelisting
    pub enable_address_whitelist: bool,
    
    // Privacy settings
    /// Redact sensitive data in logs
    pub redact_logs: bool,
    /// Enable audit logging
    pub enable_audit_log: bool,
    /// Collect analytics
    pub collect_analytics: bool,
    
    // Backup settings
    /// Require encrypted backups
    pub require_encrypted_backups: bool,
    /// Minimum backup password strength
    pub min_backup_password_entropy: u32,
    
    // Rate limiting
    /// Enable API rate limiting
    pub enable_rate_limiting: bool,
    /// Default requests per second
    pub default_rate_limit: u32,
    
    // Memory security
    /// Clear sensitive memory after use
    pub zeroize_sensitive_memory: bool,
    /// Use secure memory allocations
    pub use_secure_memory: bool,
}

/// Security level presets
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SecurityLevel {
    /// Standard security - suitable for most users
    Standard,
    /// High security - for users with significant holdings
    High,
    /// Paranoid - maximum security, some convenience trade-offs
    Paranoid,
    /// Custom - user-defined settings
    Custom,
}

impl Default for SecuritySettings {
    fn default() -> Self {
        Self::standard()
    }
}

impl SecuritySettings {
    /// Standard security preset
    pub fn standard() -> Self {
        Self {
            level: SecurityLevel::Standard,
            
            session_timeout: Duration::from_secs(30 * 60),      // 30 minutes
            max_session_duration: Duration::from_secs(24 * 60 * 60), // 24 hours
            require_reauth_for_send: false,
            sensitive_op_timeout: Duration::from_secs(15 * 60), // 15 minutes
            
            require_https: true,
            allow_custom_endpoints: true,
            validate_certificates: true,
            
            high_value_threshold: 100_000_000, // 1 BTC in satoshis
            confirm_new_addresses: true,
            enable_address_whitelist: false,
            
            redact_logs: true,
            enable_audit_log: true,
            collect_analytics: false,
            
            require_encrypted_backups: true,
            min_backup_password_entropy: 40, // ~40 bits of entropy
            
            enable_rate_limiting: true,
            default_rate_limit: 10,
            
            zeroize_sensitive_memory: true,
            use_secure_memory: false, // Platform dependent
        }
    }

    /// High security preset
    pub fn high() -> Self {
        Self {
            level: SecurityLevel::High,
            
            session_timeout: Duration::from_secs(15 * 60),      // 15 minutes
            max_session_duration: Duration::from_secs(8 * 60 * 60), // 8 hours
            require_reauth_for_send: true,
            sensitive_op_timeout: Duration::from_secs(5 * 60),  // 5 minutes
            
            require_https: true,
            allow_custom_endpoints: true,
            validate_certificates: true,
            
            high_value_threshold: 10_000_000, // 0.1 BTC in satoshis
            confirm_new_addresses: true,
            enable_address_whitelist: true,
            
            redact_logs: true,
            enable_audit_log: true,
            collect_analytics: false,
            
            require_encrypted_backups: true,
            min_backup_password_entropy: 60, // ~60 bits of entropy
            
            enable_rate_limiting: true,
            default_rate_limit: 5,
            
            zeroize_sensitive_memory: true,
            use_secure_memory: true,
        }
    }

    /// Paranoid security preset
    pub fn paranoid() -> Self {
        Self {
            level: SecurityLevel::Paranoid,
            
            session_timeout: Duration::from_secs(5 * 60),       // 5 minutes
            max_session_duration: Duration::from_secs(2 * 60 * 60), // 2 hours
            require_reauth_for_send: true,
            sensitive_op_timeout: Duration::from_secs(2 * 60),  // 2 minutes
            
            require_https: true,
            allow_custom_endpoints: false, // Only trusted providers
            validate_certificates: true,
            
            high_value_threshold: 1_000_000, // 0.01 BTC in satoshis
            confirm_new_addresses: true,
            enable_address_whitelist: true,
            
            redact_logs: true,
            enable_audit_log: true,
            collect_analytics: false,
            
            require_encrypted_backups: true,
            min_backup_password_entropy: 80, // ~80 bits of entropy
            
            enable_rate_limiting: true,
            default_rate_limit: 3,
            
            zeroize_sensitive_memory: true,
            use_secure_memory: true,
        }
    }

    /// Validate settings consistency
    pub fn validate(&self) -> Vec<String> {
        let mut warnings = Vec::new();

        // Check for insecure combinations
        if !self.require_https && self.allow_custom_endpoints {
            warnings.push(
                "Warning: Custom endpoints allowed without HTTPS requirement".to_string()
            );
        }

        if !self.require_reauth_for_send && self.high_value_threshold == 0 {
            warnings.push(
                "Warning: No transaction confirmation required for any amount".to_string()
            );
        }

        if !self.redact_logs && self.enable_audit_log {
            warnings.push(
                "Warning: Audit logging enabled without log redaction".to_string()
            );
        }

        if self.session_timeout > self.max_session_duration {
            warnings.push(
                "Warning: Session timeout exceeds maximum duration".to_string()
            );
        }

        if self.min_backup_password_entropy < 32 {
            warnings.push(
                "Warning: Backup password entropy requirement is very low".to_string()
            );
        }

        warnings
    }
}

impl SecurityConfig {
    /// Create a new security configuration with default settings
    pub fn new() -> Self {
        Self {
            config: RwLock::new(SecuritySettings::default()),
        }
    }

    /// Create with specific security level
    pub fn with_level(level: SecurityLevel) -> Self {
        let settings = match level {
            SecurityLevel::Standard => SecuritySettings::standard(),
            SecurityLevel::High => SecuritySettings::high(),
            SecurityLevel::Paranoid => SecuritySettings::paranoid(),
            SecurityLevel::Custom => SecuritySettings::standard(),
        };
        Self {
            config: RwLock::new(settings),
        }
    }

    /// Get current settings
    pub fn settings(&self) -> SecuritySettings {
        self.config.read()
            .map(|c| c.clone())
            .unwrap_or_else(|_| SecuritySettings::standard())
    }

    /// Get security level
    pub fn level(&self) -> SecurityLevel {
        self.config.read()
            .map(|c| c.level)
            .unwrap_or(SecurityLevel::Standard)
    }

    /// Set security level (applies preset)
    pub fn set_level(&self, level: SecurityLevel) {
        let Ok(mut config) = self.config.write() else { return };
        *config = match level {
            SecurityLevel::Standard => SecuritySettings::standard(),
            SecurityLevel::High => SecuritySettings::high(),
            SecurityLevel::Paranoid => SecuritySettings::paranoid(),
            SecurityLevel::Custom => {
                let mut current = config.clone();
                current.level = SecurityLevel::Custom;
                current
            }
        };
    }

    /// Update a specific setting
    pub fn update<F>(&self, updater: F) -> Vec<String> 
    where
        F: FnOnce(&mut SecuritySettings),
    {
        let Ok(mut config) = self.config.write() else { 
            return vec!["Failed to acquire config lock".to_string()]; 
        };
        config.level = SecurityLevel::Custom; // Any manual change makes it custom
        updater(&mut config);
        config.validate()
    }

    /// Check if a transaction amount is high-value
    pub fn is_high_value(&self, amount_satoshis: u64) -> bool {
        self.config.read()
            .map(|c| amount_satoshis >= c.high_value_threshold)
            .unwrap_or(true) // Default to treating as high-value for safety
    }

    /// Check if re-authentication is required for send
    pub fn requires_reauth_for_send(&self) -> bool {
        self.config.read()
            .map(|c| c.require_reauth_for_send)
            .unwrap_or(true) // Default to requiring reauth for safety
    }

    /// Get session timeout
    pub fn session_timeout(&self) -> Duration {
        self.config.read()
            .map(|c| c.session_timeout)
            .unwrap_or(Duration::from_secs(300)) // Default 5 min timeout
    }

    /// Check if custom endpoints are allowed
    pub fn allows_custom_endpoints(&self) -> bool {
        self.config.read()
            .map(|c| c.allow_custom_endpoints)
            .unwrap_or(false) // Default to disallowing for safety
    }

    /// Get minimum backup password entropy
    pub fn min_backup_entropy(&self) -> u32 {
        self.config.read()
            .map(|c| c.min_backup_password_entropy)
            .unwrap_or(60) // Default to standard entropy requirement
    }

    /// Check if audit logging is enabled
    pub fn audit_enabled(&self) -> bool {
        self.config.read()
            .map(|c| c.enable_audit_log)
            .unwrap_or(true) // Default to enabling audit for safety
    }
}

impl Default for SecurityConfig {
    fn default() -> Self {
        Self::new()
    }
}

/// Estimate password entropy (in bits)
pub fn estimate_password_entropy(password: &str) -> u32 {
    if password.is_empty() {
        return 0;
    }

    let mut charset_size: u32 = 0;
    let mut has_lower = false;
    let mut has_upper = false;
    let mut has_digit = false;
    let mut has_special = false;
    let mut has_unicode = false;

    for c in password.chars() {
        if c.is_ascii_lowercase() {
            has_lower = true;
        } else if c.is_ascii_uppercase() {
            has_upper = true;
        } else if c.is_ascii_digit() {
            has_digit = true;
        } else if c.is_ascii_punctuation() || c == ' ' {
            has_special = true;
        } else {
            has_unicode = true;
        }
    }

    if has_lower { charset_size += 26; }
    if has_upper { charset_size += 26; }
    if has_digit { charset_size += 10; }
    if has_special { charset_size += 33; } // Common special chars
    if has_unicode { charset_size += 100; } // Rough estimate

    // Entropy = length * log2(charset_size)
    let entropy_per_char = (charset_size as f64).log2();
    (password.len() as f64 * entropy_per_char) as u32
}

/// Check if password meets minimum entropy requirement
pub fn check_password_strength(password: &str, min_entropy: u32) -> HawalaResult<()> {
    let entropy = estimate_password_entropy(password);
    
    if entropy < min_entropy {
        return Err(HawalaError::invalid_input(format!(
            "Password is too weak (entropy: {} bits, minimum: {} bits). \
            Use a longer password with mixed characters.",
            entropy, min_entropy
        )));
    }
    
    Ok(())
}

/// Global security configuration instance
static SECURITY_CONFIG: std::sync::OnceLock<SecurityConfig> = std::sync::OnceLock::new();

/// Get the global security configuration
pub fn get_security_config() -> &'static SecurityConfig {
    SECURITY_CONFIG.get_or_init(SecurityConfig::new)
}

/// Convenience functions
pub fn security_level() -> SecurityLevel {
    get_security_config().level()
}

pub fn is_high_value_transaction(amount_satoshis: u64) -> bool {
    get_security_config().is_high_value(amount_satoshis)
}

pub fn requires_send_reauth() -> bool {
    get_security_config().requires_reauth_for_send()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_security_levels() {
        let standard = SecuritySettings::standard();
        let high = SecuritySettings::high();
        let paranoid = SecuritySettings::paranoid();
        
        // Paranoid should have shorter timeouts
        assert!(paranoid.session_timeout < high.session_timeout);
        assert!(high.session_timeout < standard.session_timeout);
        
        // Paranoid should have higher entropy requirement
        assert!(paranoid.min_backup_password_entropy > high.min_backup_password_entropy);
        assert!(high.min_backup_password_entropy > standard.min_backup_password_entropy);
    }

    #[test]
    fn test_password_entropy() {
        // Simple password
        let simple = estimate_password_entropy("password");
        assert!(simple < 40);
        
        // Complex password
        let complex = estimate_password_entropy("MyP@ssw0rd!2024");
        assert!(complex > 60);
        
        // Empty password
        assert_eq!(estimate_password_entropy(""), 0);
    }

    #[test]
    fn test_high_value_threshold() {
        let config = SecurityConfig::new();
        
        // Below threshold
        assert!(!config.is_high_value(1_000_000)); // 0.01 BTC
        
        // Above threshold (1 BTC = 100M satoshis)
        assert!(config.is_high_value(200_000_000)); // 2 BTC
    }

    #[test]
    fn test_settings_validation() {
        let mut settings = SecuritySettings::standard();
        settings.require_https = false;
        settings.allow_custom_endpoints = true;
        
        let warnings = settings.validate();
        assert!(!warnings.is_empty());
    }

    #[test]
    fn test_update_settings() {
        let config = SecurityConfig::new();
        
        let _warnings = config.update(|s| {
            s.session_timeout = Duration::from_secs(60);
        });
        
        assert_eq!(config.level(), SecurityLevel::Custom);
        assert_eq!(config.session_timeout(), Duration::from_secs(60));
    }

    #[test]
    fn test_password_strength_check() {
        // Weak password should fail
        assert!(check_password_strength("123456", 40).is_err());
        
        // Strong password should pass
        assert!(check_password_strength("MyV3ryStr0ng!P@ssword", 40).is_ok());
    }
}
