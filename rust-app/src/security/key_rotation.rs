//! Key Rotation Infrastructure
//!
//! Support for key versioning and rotation:
//! - Key version tracking
//! - Rotation scheduling
//! - Key derivation versioning
//! - Migration utilities
//! - Key deprecation

use crate::error::{HawalaError, HawalaResult};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::RwLock;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// Key rotation manager
pub struct KeyRotationManager {
    /// Key versions per wallet
    versions: RwLock<HashMap<String, Vec<KeyVersion>>>,
    /// Rotation policies
    policies: RwLock<HashMap<String, RotationPolicy>>,
    /// Pending rotations
    pending: RwLock<Vec<PendingRotation>>,
}

/// Key version information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyVersion {
    /// Version number (starts at 1)
    pub version: u32,
    /// Creation timestamp
    pub created_at: u64,
    /// Key type
    pub key_type: KeyType,
    /// Status
    pub status: KeyStatus,
    /// Derivation path (if HD)
    pub derivation_path: Option<String>,
    /// Algorithm used
    pub algorithm: String,
    /// Deprecation timestamp (if deprecated)
    pub deprecated_at: Option<u64>,
    /// Rotation reason (if rotated)
    pub rotation_reason: Option<String>,
}

/// Key types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum KeyType {
    /// Master seed
    MasterSeed,
    /// Chain-specific key
    ChainKey,
    /// Address key
    AddressKey,
    /// Encryption key (for backups)
    EncryptionKey,
    /// Signing key
    SigningKey,
}

/// Key status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum KeyStatus {
    /// Currently active
    Active,
    /// Can be used for verification but not signing
    VerifyOnly,
    /// Deprecated - should not be used
    Deprecated,
    /// Compromised - must not be used
    Compromised,
    /// Pending rotation
    PendingRotation,
}

/// Rotation policy
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RotationPolicy {
    /// Enable automatic rotation
    pub auto_rotate: bool,
    /// Maximum key age before rotation
    pub max_age: Duration,
    /// Grace period after rotation before old key expires
    pub grace_period: Duration,
    /// Require notification before rotation
    pub require_notification: bool,
    /// Key types subject to this policy
    pub key_types: Vec<KeyType>,
}

impl Default for RotationPolicy {
    fn default() -> Self {
        Self {
            auto_rotate: false,
            max_age: Duration::from_secs(365 * 24 * 60 * 60), // 1 year
            grace_period: Duration::from_secs(30 * 24 * 60 * 60), // 30 days
            require_notification: true,
            key_types: vec![KeyType::EncryptionKey], // Only rotate encryption keys by default
        }
    }
}

/// Pending rotation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PendingRotation {
    pub wallet_id: String,
    pub key_type: KeyType,
    pub current_version: u32,
    pub scheduled_at: u64,
    pub reason: String,
    pub notified: bool,
}

/// Rotation check result
#[derive(Debug, Clone)]
pub struct RotationCheckResult {
    pub needs_rotation: bool,
    pub keys_to_rotate: Vec<KeyRotationInfo>,
    pub warnings: Vec<String>,
}

/// Information about a key that needs rotation
#[derive(Debug, Clone)]
pub struct KeyRotationInfo {
    pub wallet_id: String,
    pub key_type: KeyType,
    pub current_version: u32,
    pub age_days: u64,
    pub reason: RotationReason,
}

/// Reasons for rotation
#[derive(Debug, Clone, PartialEq)]
pub enum RotationReason {
    /// Key has exceeded maximum age
    MaxAgeExceeded,
    /// Key may have been exposed
    PossibleExposure,
    /// User requested rotation
    UserRequested,
    /// Security policy requires rotation
    PolicyRequired,
    /// Key algorithm deprecated
    AlgorithmDeprecated,
}

impl KeyRotationManager {
    /// Create a new key rotation manager
    pub fn new() -> Self {
        Self {
            versions: RwLock::new(HashMap::new()),
            policies: RwLock::new(HashMap::new()),
            pending: RwLock::new(Vec::new()),
        }
    }

    /// Register a new key version
    pub fn register_key_version(
        &self,
        wallet_id: &str,
        key_type: KeyType,
        derivation_path: Option<&str>,
        algorithm: &str,
    ) -> HawalaResult<KeyVersion> {
        let mut versions = self.versions.write().unwrap();
        
        let wallet_versions = versions
            .entry(wallet_id.to_string())
            .or_insert_with(Vec::new);

        // Calculate new version number
        let new_version = wallet_versions
            .iter()
            .filter(|v| v.key_type == key_type)
            .map(|v| v.version)
            .max()
            .unwrap_or(0) + 1;

        let version = KeyVersion {
            version: new_version,
            created_at: current_timestamp(),
            key_type,
            status: KeyStatus::Active,
            derivation_path: derivation_path.map(String::from),
            algorithm: algorithm.to_string(),
            deprecated_at: None,
            rotation_reason: None,
        };

        wallet_versions.push(version.clone());
        Ok(version)
    }

    /// Get current active version for a key type
    pub fn get_active_version(&self, wallet_id: &str, key_type: KeyType) -> Option<KeyVersion> {
        let versions = self.versions.read().unwrap();
        
        versions.get(wallet_id)
            .and_then(|wallet_versions| {
                wallet_versions.iter()
                    .filter(|v| v.key_type == key_type && v.status == KeyStatus::Active)
                    .max_by_key(|v| v.version)
                    .cloned()
            })
    }

    /// Get all versions for a wallet
    pub fn get_all_versions(&self, wallet_id: &str) -> Vec<KeyVersion> {
        let versions = self.versions.read().unwrap();
        versions.get(wallet_id).cloned().unwrap_or_default()
    }

    /// Deprecate a key version
    pub fn deprecate_version(
        &self,
        wallet_id: &str,
        key_type: KeyType,
        version: u32,
        reason: &str,
    ) -> HawalaResult<()> {
        let mut versions = self.versions.write().unwrap();
        
        let wallet_versions = versions.get_mut(wallet_id)
            .ok_or_else(|| HawalaError::invalid_input("Wallet not found"))?;

        let key = wallet_versions.iter_mut()
            .find(|v| v.key_type == key_type && v.version == version)
            .ok_or_else(|| HawalaError::invalid_input("Key version not found"))?;

        if key.status == KeyStatus::Compromised {
            return Err(HawalaError::invalid_input("Cannot deprecate compromised key"));
        }

        key.status = KeyStatus::Deprecated;
        key.deprecated_at = Some(current_timestamp());
        key.rotation_reason = Some(reason.to_string());

        Ok(())
    }

    /// Mark a key as compromised (emergency)
    pub fn mark_compromised(
        &self,
        wallet_id: &str,
        key_type: KeyType,
        version: u32,
    ) -> HawalaResult<()> {
        let mut versions = self.versions.write().unwrap();
        
        let wallet_versions = versions.get_mut(wallet_id)
            .ok_or_else(|| HawalaError::invalid_input("Wallet not found"))?;

        let key = wallet_versions.iter_mut()
            .find(|v| v.key_type == key_type && v.version == version)
            .ok_or_else(|| HawalaError::invalid_input("Key version not found"))?;

        key.status = KeyStatus::Compromised;
        key.deprecated_at = Some(current_timestamp());

        Ok(())
    }

    /// Set rotation policy for a wallet
    pub fn set_rotation_policy(&self, wallet_id: &str, policy: RotationPolicy) {
        let mut policies = self.policies.write().unwrap();
        policies.insert(wallet_id.to_string(), policy);
    }

    /// Get rotation policy
    pub fn get_rotation_policy(&self, wallet_id: &str) -> Option<RotationPolicy> {
        let policies = self.policies.read().unwrap();
        policies.get(wallet_id).cloned()
    }

    /// Check if rotation is needed
    pub fn check_rotation_needed(&self, wallet_id: &str) -> RotationCheckResult {
        let mut keys_to_rotate = Vec::new();
        let mut warnings = Vec::new();

        let versions = self.versions.read().unwrap();
        let policies = self.policies.read().unwrap();

        let Some(wallet_versions) = versions.get(wallet_id) else {
            return RotationCheckResult {
                needs_rotation: false,
                keys_to_rotate,
                warnings,
            };
        };

        let policy = policies.get(wallet_id)
            .cloned()
            .unwrap_or_default();

        let now = current_timestamp();

        for version in wallet_versions.iter() {
            if version.status != KeyStatus::Active {
                continue;
            }

            if !policy.key_types.contains(&version.key_type) {
                continue;
            }

            let age_secs = now.saturating_sub(version.created_at);
            let age_days = age_secs / (24 * 60 * 60);

            if age_secs > policy.max_age.as_secs() {
                keys_to_rotate.push(KeyRotationInfo {
                    wallet_id: wallet_id.to_string(),
                    key_type: version.key_type,
                    current_version: version.version,
                    age_days,
                    reason: RotationReason::MaxAgeExceeded,
                });
            } else if age_secs > policy.max_age.as_secs() * 3 / 4 {
                warnings.push(format!(
                    "{:?} key v{} is {}% of max age",
                    version.key_type,
                    version.version,
                    (age_secs * 100) / policy.max_age.as_secs()
                ));
            }
        }

        RotationCheckResult {
            needs_rotation: !keys_to_rotate.is_empty(),
            keys_to_rotate,
            warnings,
        }
    }

    /// Schedule a rotation
    pub fn schedule_rotation(
        &self,
        wallet_id: &str,
        key_type: KeyType,
        delay: Duration,
        reason: &str,
    ) -> HawalaResult<()> {
        let current = self.get_active_version(wallet_id, key_type)
            .ok_or_else(|| HawalaError::invalid_input("No active key to rotate"))?;

        let mut pending = self.pending.write().unwrap();
        
        // Check for existing pending rotation
        if pending.iter().any(|p| 
            p.wallet_id == wallet_id && 
            p.key_type == key_type &&
            p.current_version == current.version
        ) {
            return Err(HawalaError::invalid_input("Rotation already scheduled"));
        }

        pending.push(PendingRotation {
            wallet_id: wallet_id.to_string(),
            key_type,
            current_version: current.version,
            scheduled_at: current_timestamp() + delay.as_secs(),
            reason: reason.to_string(),
            notified: false,
        });

        // Mark current key as pending rotation
        let mut versions = self.versions.write().unwrap();
        if let Some(wallet_versions) = versions.get_mut(wallet_id) {
            if let Some(key) = wallet_versions.iter_mut()
                .find(|v| v.key_type == key_type && v.version == current.version) {
                key.status = KeyStatus::PendingRotation;
            }
        }

        Ok(())
    }

    /// Get pending rotations
    pub fn get_pending_rotations(&self, wallet_id: Option<&str>) -> Vec<PendingRotation> {
        let pending = self.pending.read().unwrap();
        
        match wallet_id {
            Some(id) => pending.iter()
                .filter(|p| p.wallet_id == id)
                .cloned()
                .collect(),
            None => pending.clone(),
        }
    }

    /// Complete a rotation
    pub fn complete_rotation(
        &self,
        wallet_id: &str,
        key_type: KeyType,
        old_version: u32,
        new_derivation_path: Option<&str>,
        new_algorithm: &str,
    ) -> HawalaResult<KeyVersion> {
        // Deprecate old version
        self.deprecate_version(wallet_id, key_type, old_version, "Rotated to new version")?;

        // Create new version
        let new_version = self.register_key_version(
            wallet_id,
            key_type,
            new_derivation_path,
            new_algorithm,
        )?;

        // Remove from pending
        let mut pending = self.pending.write().unwrap();
        pending.retain(|p| 
            !(p.wallet_id == wallet_id && 
              p.key_type == key_type && 
              p.current_version == old_version)
        );

        Ok(new_version)
    }

    /// Cancel a scheduled rotation
    pub fn cancel_rotation(&self, wallet_id: &str, key_type: KeyType) -> HawalaResult<()> {
        let mut pending = self.pending.write().unwrap();
        let initial_len = pending.len();
        
        pending.retain(|p| !(p.wallet_id == wallet_id && p.key_type == key_type));

        if pending.len() == initial_len {
            return Err(HawalaError::invalid_input("No pending rotation found"));
        }

        // Restore key status
        let mut versions = self.versions.write().unwrap();
        if let Some(wallet_versions) = versions.get_mut(wallet_id) {
            for v in wallet_versions.iter_mut() {
                if v.key_type == key_type && v.status == KeyStatus::PendingRotation {
                    v.status = KeyStatus::Active;
                }
            }
        }

        Ok(())
    }

    /// Validate that a key version is usable
    pub fn validate_key_usable(
        &self,
        wallet_id: &str,
        key_type: KeyType,
        version: u32,
        for_signing: bool,
    ) -> HawalaResult<()> {
        let versions = self.versions.read().unwrap();
        
        let wallet_versions = versions.get(wallet_id)
            .ok_or_else(|| HawalaError::auth_error("Wallet not found"))?;

        let key = wallet_versions.iter()
            .find(|v| v.key_type == key_type && v.version == version)
            .ok_or_else(|| HawalaError::auth_error("Key version not found"))?;

        match key.status {
            KeyStatus::Active => Ok(()),
            KeyStatus::VerifyOnly if !for_signing => Ok(()),
            KeyStatus::VerifyOnly => Err(HawalaError::auth_error(
                "Key is verify-only, cannot be used for signing"
            )),
            KeyStatus::Deprecated => Err(HawalaError::auth_error(
                "Key has been deprecated"
            )),
            KeyStatus::Compromised => Err(HawalaError::auth_error(
                "Key has been marked as compromised"
            )),
            KeyStatus::PendingRotation => {
                if for_signing {
                    Err(HawalaError::auth_error(
                        "Key is pending rotation, signing not recommended"
                    ))
                } else {
                    Ok(())
                }
            }
        }
    }
}

impl Default for KeyRotationManager {
    fn default() -> Self {
        Self::new()
    }
}

/// Get current timestamp in seconds
fn current_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// Global key rotation manager
static KEY_ROTATION_MANAGER: std::sync::OnceLock<KeyRotationManager> = std::sync::OnceLock::new();

/// Get the global key rotation manager
pub fn get_key_rotation_manager() -> &'static KeyRotationManager {
    KEY_ROTATION_MANAGER.get_or_init(KeyRotationManager::new)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_register_key_version() {
        let manager = KeyRotationManager::new();
        
        let v1 = manager.register_key_version(
            "wallet1",
            KeyType::EncryptionKey,
            None,
            "AES-256-GCM"
        ).unwrap();

        assert_eq!(v1.version, 1);
        assert_eq!(v1.status, KeyStatus::Active);

        let v2 = manager.register_key_version(
            "wallet1",
            KeyType::EncryptionKey,
            None,
            "AES-256-GCM"
        ).unwrap();

        assert_eq!(v2.version, 2);
    }

    #[test]
    fn test_deprecate_version() {
        let manager = KeyRotationManager::new();
        
        manager.register_key_version(
            "wallet1",
            KeyType::SigningKey,
            Some("m/44'/60'/0'/0/0"),
            "secp256k1"
        ).unwrap();

        manager.deprecate_version("wallet1", KeyType::SigningKey, 1, "Rotated").unwrap();

        let version = manager.get_all_versions("wallet1");
        assert_eq!(version[0].status, KeyStatus::Deprecated);
    }

    #[test]
    fn test_mark_compromised() {
        let manager = KeyRotationManager::new();
        
        manager.register_key_version(
            "wallet1",
            KeyType::MasterSeed,
            None,
            "BIP39"
        ).unwrap();

        manager.mark_compromised("wallet1", KeyType::MasterSeed, 1).unwrap();

        let version = manager.get_all_versions("wallet1");
        assert_eq!(version[0].status, KeyStatus::Compromised);
    }

    #[test]
    fn test_validate_key_usable() {
        let manager = KeyRotationManager::new();
        
        manager.register_key_version(
            "wallet1",
            KeyType::SigningKey,
            None,
            "ed25519"
        ).unwrap();

        // Active key should be usable
        assert!(manager.validate_key_usable("wallet1", KeyType::SigningKey, 1, true).is_ok());

        // Deprecate and check
        manager.deprecate_version("wallet1", KeyType::SigningKey, 1, "Old").unwrap();
        assert!(manager.validate_key_usable("wallet1", KeyType::SigningKey, 1, true).is_err());
    }

    #[test]
    fn test_schedule_rotation() {
        let manager = KeyRotationManager::new();
        
        manager.register_key_version(
            "wallet1",
            KeyType::EncryptionKey,
            None,
            "AES-256-GCM"
        ).unwrap();

        manager.schedule_rotation(
            "wallet1",
            KeyType::EncryptionKey,
            Duration::from_secs(86400),
            "Annual rotation"
        ).unwrap();

        let pending = manager.get_pending_rotations(Some("wallet1"));
        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0].reason, "Annual rotation");
    }

    #[test]
    fn test_complete_rotation() {
        let manager = KeyRotationManager::new();
        
        let v1 = manager.register_key_version(
            "wallet1",
            KeyType::EncryptionKey,
            None,
            "AES-256-GCM"
        ).unwrap();

        let v2 = manager.complete_rotation(
            "wallet1",
            KeyType::EncryptionKey,
            v1.version,
            None,
            "AES-256-GCM"
        ).unwrap();

        assert_eq!(v2.version, 2);
        
        let versions = manager.get_all_versions("wallet1");
        assert_eq!(versions[0].status, KeyStatus::Deprecated);
        assert_eq!(versions[1].status, KeyStatus::Active);
    }
}
