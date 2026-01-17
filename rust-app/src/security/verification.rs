//! Cryptographic Verification Module
//!
//! Message signing and verification for:
//! - Transaction authentication
//! - Message signing (EIP-191/EIP-712 style)
//! - Challenge-response authentication
//! - Signature verification

use crate::error::{HawalaError, HawalaResult};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::RwLock;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// Verification manager
pub struct VerificationManager {
    /// Pending challenges
    pending_challenges: RwLock<HashMap<String, Challenge>>,
    /// Verification history
    history: RwLock<Vec<VerificationRecord>>,
    /// Configuration
    config: RwLock<VerificationConfig>,
}

/// Challenge for authentication
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Challenge {
    /// Challenge ID
    pub id: String,
    /// Challenge nonce (random bytes as hex)
    pub nonce: String,
    /// Expected address/signer
    pub expected_signer: String,
    /// Creation timestamp
    pub created_at: u64,
    /// Expiration timestamp
    pub expires_at: u64,
    /// Challenge message
    pub message: String,
    /// Whether this challenge has been used
    pub used: bool,
}

/// Verification configuration
#[derive(Debug, Clone)]
pub struct VerificationConfig {
    /// Challenge expiration time
    pub challenge_ttl: Duration,
    /// Maximum pending challenges per address
    pub max_pending_per_address: usize,
    /// Require domain binding
    pub require_domain: bool,
    /// Allowed domains
    pub allowed_domains: Vec<String>,
}

impl Default for VerificationConfig {
    fn default() -> Self {
        Self {
            challenge_ttl: Duration::from_secs(300), // 5 minutes
            max_pending_per_address: 5,
            require_domain: false,
            allowed_domains: Vec::new(),
        }
    }
}

/// Verification record
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerificationRecord {
    pub challenge_id: String,
    pub signer: String,
    pub success: bool,
    pub timestamp: u64,
    pub error: Option<String>,
}

/// Message to sign (EIP-191 style)
#[derive(Debug, Clone)]
pub struct SignableMessage {
    /// Message content
    pub message: String,
    /// Domain (optional, for EIP-712 style)
    pub domain: Option<MessageDomain>,
    /// Timestamp
    pub timestamp: u64,
    /// Nonce
    pub nonce: String,
}

/// Message domain (EIP-712 inspired)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageDomain {
    /// Application name
    pub name: String,
    /// Version
    pub version: String,
    /// Chain ID
    pub chain_id: Option<u64>,
    /// Verifying contract (optional)
    pub verifying_contract: Option<String>,
}

/// Signature verification result
#[derive(Debug)]
pub struct VerificationResult {
    pub valid: bool,
    pub signer: Option<String>,
    pub error: Option<String>,
    pub verified_at: u64,
}

impl VerificationManager {
    /// Create a new verification manager
    pub fn new() -> Self {
        Self {
            pending_challenges: RwLock::new(HashMap::new()),
            history: RwLock::new(Vec::new()),
            config: RwLock::new(VerificationConfig::default()),
        }
    }

    /// Create a new verification manager with config
    pub fn with_config(config: VerificationConfig) -> Self {
        Self {
            pending_challenges: RwLock::new(HashMap::new()),
            history: RwLock::new(Vec::new()),
            config: RwLock::new(config),
        }
    }

    /// Update configuration
    pub fn set_config(&self, config: VerificationConfig) {
        let mut cfg = self.config.write().unwrap();
        *cfg = config;
    }

    /// Create a challenge for an address
    pub fn create_challenge(&self, expected_signer: &str, domain: Option<&str>) -> HawalaResult<Challenge> {
        let config = self.config.read().unwrap();
        
        // Check domain if required
        if config.require_domain {
            let domain = domain.ok_or_else(|| 
                HawalaError::invalid_input("Domain is required for verification")
            )?;
            
            if !config.allowed_domains.is_empty() && 
               !config.allowed_domains.contains(&domain.to_string()) {
                return Err(HawalaError::invalid_input("Domain not allowed"));
            }
        }

        let mut pending = self.pending_challenges.write().unwrap();
        
        // Check pending limit
        let count = pending.values()
            .filter(|c| c.expected_signer == expected_signer && !c.used)
            .count();
        
        if count >= config.max_pending_per_address {
            // Clean up expired challenges first
            let now = current_timestamp();
            pending.retain(|_, c| c.expires_at > now || c.used);
            
            // Recheck after cleanup
            let count = pending.values()
                .filter(|c| c.expected_signer == expected_signer && !c.used)
                .count();
            
            if count >= config.max_pending_per_address {
                return Err(HawalaError::rate_limited(
                    "Too many pending challenges for this address"
                ));
            }
        }

        let now = current_timestamp();
        let nonce = generate_nonce();
        let id = format!("chal_{}", &nonce[..16]);
        
        let domain_str = domain.unwrap_or("hawala");
        let message = format!(
            "{} Authentication\n\nNonce: {}\nTimestamp: {}\nAddress: {}",
            domain_str, nonce, now, expected_signer
        );

        let challenge = Challenge {
            id: id.clone(),
            nonce,
            expected_signer: expected_signer.to_string(),
            created_at: now,
            expires_at: now + config.challenge_ttl.as_secs(),
            message,
            used: false,
        };

        pending.insert(id, challenge.clone());
        Ok(challenge)
    }

    /// Verify a challenge response
    /// 
    /// Note: This is a simplified verification that checks the signature format
    /// and challenge validity. In production, you'd integrate with actual
    /// crypto libraries for signature verification.
    pub fn verify_challenge(
        &self,
        challenge_id: &str,
        signature: &str,
        claimed_signer: &str,
    ) -> HawalaResult<VerificationResult> {
        let mut pending = self.pending_challenges.write().unwrap();
        
        let challenge = pending.get_mut(challenge_id)
            .ok_or_else(|| HawalaError::auth_error("Challenge not found"))?;

        let now = current_timestamp();

        // Check if expired
        if now > challenge.expires_at {
            challenge.used = true;
            return Ok(VerificationResult {
                valid: false,
                signer: None,
                error: Some("Challenge expired".to_string()),
                verified_at: now,
            });
        }

        // Check if already used
        if challenge.used {
            return Ok(VerificationResult {
                valid: false,
                signer: None,
                error: Some("Challenge already used".to_string()),
                verified_at: now,
            });
        }

        // Check signer matches expected
        if !addresses_match(&challenge.expected_signer, claimed_signer) {
            challenge.used = true;
            return Ok(VerificationResult {
                valid: false,
                signer: Some(claimed_signer.to_string()),
                error: Some("Signer does not match expected address".to_string()),
                verified_at: now,
            });
        }

        // Verify signature format (basic validation)
        let sig_valid = validate_signature_format(signature);
        
        challenge.used = true;

        let result = VerificationResult {
            valid: sig_valid,
            signer: Some(claimed_signer.to_string()),
            error: if sig_valid { None } else { Some("Invalid signature format".to_string()) },
            verified_at: now,
        };

        // Record verification
        let mut history = self.history.write().unwrap();
        history.push(VerificationRecord {
            challenge_id: challenge_id.to_string(),
            signer: claimed_signer.to_string(),
            success: result.valid,
            timestamp: now,
            error: result.error.clone(),
        });

        Ok(result)
    }

    /// Get a pending challenge
    pub fn get_challenge(&self, challenge_id: &str) -> Option<Challenge> {
        let pending = self.pending_challenges.read().unwrap();
        pending.get(challenge_id).cloned()
    }

    /// Cancel a challenge
    pub fn cancel_challenge(&self, challenge_id: &str) -> HawalaResult<()> {
        let mut pending = self.pending_challenges.write().unwrap();
        
        if let Some(challenge) = pending.get_mut(challenge_id) {
            challenge.used = true;
            Ok(())
        } else {
            Err(HawalaError::invalid_input("Challenge not found"))
        }
    }

    /// Clean up expired challenges
    pub fn cleanup_expired(&self) -> usize {
        let mut pending = self.pending_challenges.write().unwrap();
        let now = current_timestamp();
        let before = pending.len();
        
        pending.retain(|_, c| {
            // Keep if not expired and not used
            c.expires_at > now && !c.used
        });
        
        before - pending.len()
    }

    /// Get verification history for an address
    pub fn get_history(&self, signer: &str, limit: usize) -> Vec<VerificationRecord> {
        let history = self.history.read().unwrap();
        
        history.iter()
            .filter(|r| addresses_match(&r.signer, signer))
            .rev()
            .take(limit)
            .cloned()
            .collect()
    }

    /// Get recent failed verifications (for anomaly detection)
    pub fn get_recent_failures(&self, since: Duration) -> Vec<VerificationRecord> {
        let history = self.history.read().unwrap();
        let cutoff = current_timestamp().saturating_sub(since.as_secs());
        
        history.iter()
            .filter(|r| !r.success && r.timestamp >= cutoff)
            .cloned()
            .collect()
    }
}

impl Default for VerificationManager {
    fn default() -> Self {
        Self::new()
    }
}

/// Create a signable message
pub fn create_signable_message(
    content: &str,
    domain: Option<MessageDomain>,
) -> SignableMessage {
    SignableMessage {
        message: content.to_string(),
        domain,
        timestamp: current_timestamp(),
        nonce: generate_nonce(),
    }
}

/// Format message for signing (EIP-191 style prefix)
pub fn format_message_for_signing(message: &SignableMessage) -> String {
    let domain_prefix = message.domain.as_ref()
        .map(|d| format!("{} v{}", d.name, d.version))
        .unwrap_or_else(|| "Hawala".to_string());
    
    format!(
        "\x19{} Signed Message:\n{}\n\nNonce: {}\nTimestamp: {}",
        domain_prefix,
        message.message,
        message.nonce,
        message.timestamp
    )
}

/// Hash a message for signing (returns hex-encoded hash)
pub fn hash_message(message: &str) -> String {
    use sha2::{Sha256, Digest};
    
    let mut hasher = Sha256::new();
    hasher.update(message.as_bytes());
    hex::encode(hasher.finalize())
}

/// Validate signature format (basic check)
fn validate_signature_format(signature: &str) -> bool {
    // Remove 0x prefix if present
    let sig = signature.strip_prefix("0x").unwrap_or(signature);
    
    // Check if it's valid hex
    if hex::decode(sig).is_err() {
        return false;
    }
    
    // Ethereum signatures are 65 bytes (130 hex chars)
    // Bitcoin signatures vary but are typically 64-73 bytes
    let len = sig.len();
    len >= 128 && len <= 146
}

/// Compare addresses (case-insensitive for Ethereum)
fn addresses_match(a: &str, b: &str) -> bool {
    let a = a.strip_prefix("0x").unwrap_or(a);
    let b = b.strip_prefix("0x").unwrap_or(b);
    a.eq_ignore_ascii_case(b)
}

/// Generate a random nonce
fn generate_nonce() -> String {
    use std::time::Instant;
    
    // Simple nonce generation using timestamp and a pseudo-random component
    // In production, use a proper CSPRNG
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    
    // Add some entropy from Instant for additional randomness
    let instant_nanos = Instant::now().elapsed().as_nanos();
    
    // Combine and hash
    let data = format!("{}{}{}", now, instant_nanos, std::process::id());
    hash_message(&data)
}

/// Get current timestamp
fn current_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// Personal sign helper (EIP-191)
pub fn personal_sign_message(message: &str) -> String {
    let prefix = format!("\x19Ethereum Signed Message:\n{}", message.len());
    let full_message = format!("{}{}", prefix, message);
    hash_message(&full_message)
}

/// Typed data hash helper (EIP-712 simplified)
pub fn typed_data_hash(domain: &MessageDomain, message: &str) -> String {
    let domain_separator = format!(
        "{}:{}:{}",
        domain.name,
        domain.version,
        domain.chain_id.unwrap_or(1)
    );
    
    let type_hash = hash_message(&domain_separator);
    let message_hash = hash_message(message);
    
    hash_message(&format!("\x19\x01{}{}", type_hash, message_hash))
}

/// Global verification manager
static VERIFICATION_MANAGER: std::sync::OnceLock<VerificationManager> = std::sync::OnceLock::new();

/// Get the global verification manager
pub fn get_verification_manager() -> &'static VerificationManager {
    VERIFICATION_MANAGER.get_or_init(VerificationManager::new)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_challenge() {
        let manager = VerificationManager::new();
        
        let challenge = manager.create_challenge(
            "0x1234567890abcdef1234567890abcdef12345678",
            None
        ).unwrap();

        assert!(!challenge.id.is_empty());
        assert!(!challenge.nonce.is_empty());
        assert!(challenge.message.contains("Nonce:"));
        assert!(!challenge.used);
    }

    #[test]
    fn test_challenge_expiration() {
        let config = VerificationConfig {
            challenge_ttl: Duration::from_secs(1),
            ..Default::default()
        };
        let manager = VerificationManager::with_config(config);
        
        let challenge = manager.create_challenge(
            "0x1234567890abcdef1234567890abcdef12345678",
            None
        ).unwrap();

        // Wait for expiration
        std::thread::sleep(Duration::from_secs(2));

        // Try to verify - should fail due to expiration
        let fake_sig = "0x".to_string() + &"ab".repeat(65);
        let result = manager.verify_challenge(
            &challenge.id,
            &fake_sig,
            "0x1234567890abcdef1234567890abcdef12345678"
        ).unwrap();

        assert!(!result.valid);
        assert!(result.error.as_ref().map(|e| e.contains("expired")).unwrap_or(false));
    }

    #[test]
    fn test_challenge_single_use() {
        let manager = VerificationManager::new();
        
        let challenge = manager.create_challenge(
            "0x1234567890abcdef1234567890abcdef12345678",
            None
        ).unwrap();

        // Valid-looking signature (65 bytes = 130 hex chars)
        let fake_sig = "0x".to_string() + &"ab".repeat(65);

        // First verification
        let result1 = manager.verify_challenge(
            &challenge.id,
            &fake_sig,
            "0x1234567890abcdef1234567890abcdef12345678"
        ).unwrap();

        // Second attempt should fail
        let result2 = manager.verify_challenge(
            &challenge.id,
            &fake_sig,
            "0x1234567890abcdef1234567890abcdef12345678"
        ).unwrap();

        assert!(result1.valid);
        assert!(!result2.valid);
        assert!(result2.error.as_ref().map(|e| e.contains("already used")).unwrap_or(false));
    }

    #[test]
    fn test_signer_mismatch() {
        let manager = VerificationManager::new();
        
        let challenge = manager.create_challenge(
            "0x1111111111111111111111111111111111111111",
            None
        ).unwrap();

        let fake_sig = "0x".to_string() + &"ab".repeat(65);

        let result = manager.verify_challenge(
            &challenge.id,
            &fake_sig,
            "0x2222222222222222222222222222222222222222"
        ).unwrap();

        assert!(!result.valid);
        assert!(result.error.as_ref().map(|e| e.contains("does not match")).unwrap_or(false));
    }

    #[test]
    fn test_addresses_match() {
        // Case insensitive
        assert!(addresses_match(
            "0xAbCdEf1234567890AbCdEf1234567890AbCdEf12",
            "0xabcdef1234567890abcdef1234567890abcdef12"
        ));

        // With/without prefix
        assert!(addresses_match(
            "AbCdEf1234567890AbCdEf1234567890AbCdEf12",
            "0xabcdef1234567890abcdef1234567890abcdef12"
        ));
    }

    #[test]
    fn test_validate_signature_format() {
        // Valid Ethereum signature (65 bytes)
        let valid_sig = "ab".repeat(65);
        assert!(validate_signature_format(&valid_sig));

        // With 0x prefix
        let with_prefix = format!("0x{}", "ab".repeat(65));
        assert!(validate_signature_format(&with_prefix));

        // Too short
        assert!(!validate_signature_format("abcd"));

        // Invalid hex
        assert!(!validate_signature_format("xyz"));
    }

    #[test]
    fn test_personal_sign_message() {
        let message = "Hello, World!";
        let hash = personal_sign_message(message);
        
        // Should be a valid hex hash
        assert_eq!(hash.len(), 64);
        assert!(hex::decode(&hash).is_ok());
    }

    #[test]
    fn test_typed_data_hash() {
        let domain = MessageDomain {
            name: "Hawala".to_string(),
            version: "1".to_string(),
            chain_id: Some(1),
            verifying_contract: None,
        };

        let hash = typed_data_hash(&domain, "test message");
        
        assert_eq!(hash.len(), 64);
        assert!(hex::decode(&hash).is_ok());
    }

    #[test]
    fn test_cleanup_expired() {
        let config = VerificationConfig {
            challenge_ttl: Duration::from_millis(50),
            ..Default::default()
        };
        let manager = VerificationManager::with_config(config);
        
        // Create challenges
        manager.create_challenge("0x1111111111111111111111111111111111111111", None).unwrap();
        manager.create_challenge("0x2222222222222222222222222222222222222222", None).unwrap();

        // Wait for expiration
        std::thread::sleep(Duration::from_millis(100));

        // Cleanup
        let cleaned = manager.cleanup_expired();
        assert_eq!(cleaned, 2);
    }

    #[test]
    fn test_domain_requirement() {
        let config = VerificationConfig {
            require_domain: true,
            allowed_domains: vec!["hawala.app".to_string()],
            ..Default::default()
        };
        let manager = VerificationManager::with_config(config);

        // Without domain should fail
        let result = manager.create_challenge(
            "0x1234567890abcdef1234567890abcdef12345678",
            None
        );
        assert!(result.is_err());

        // With wrong domain should fail
        let result = manager.create_challenge(
            "0x1234567890abcdef1234567890abcdef12345678",
            Some("other.app")
        );
        assert!(result.is_err());

        // With correct domain should succeed
        let result = manager.create_challenge(
            "0x1234567890abcdef1234567890abcdef12345678",
            Some("hawala.app")
        );
        assert!(result.is_ok());
    }
}
