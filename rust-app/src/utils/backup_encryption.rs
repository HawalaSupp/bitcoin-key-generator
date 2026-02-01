//! Backup Encryption with Authenticated Encryption
//!
//! Provides secure backup encryption using:
//! - AES-256-GCM for authenticated encryption
//! - Argon2id for key derivation from password
//! - Random nonces to prevent nonce reuse

#![allow(deprecated)] // GenericArray::from_slice deprecated in generic-array 1.x

use aes_gcm::{
    aead::{Aead, KeyInit, OsRng},
    Aes256Gcm, Nonce,
};
use rand::RngCore;
use crate::error::{HawalaError, HawalaResult};

/// Encrypted backup structure
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct EncryptedBackup {
    /// Version for future compatibility
    pub version: u8,
    /// Salt used for key derivation (32 bytes, base64)
    pub salt: String,
    /// Nonce used for encryption (12 bytes, base64)
    pub nonce: String,
    /// Encrypted data (ciphertext + auth tag, base64)
    pub ciphertext: String,
    /// Key derivation parameters
    pub kdf_params: KdfParams,
}

/// Key derivation parameters
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct KdfParams {
    /// Memory cost in KiB
    pub memory_cost: u32,
    /// Time cost (iterations)
    pub time_cost: u32,
    /// Parallelism
    pub parallelism: u32,
}

impl Default for KdfParams {
    fn default() -> Self {
        Self {
            // Secure defaults for password hashing
            // 64 MiB memory, 3 iterations, 4 parallel lanes
            memory_cost: 65536,
            time_cost: 3,
            parallelism: 4,
        }
    }
}

/// Encrypt wallet backup data with password
pub fn encrypt_backup(plaintext: &[u8], password: &str) -> HawalaResult<EncryptedBackup> {
    if password.len() < 8 {
        return Err(HawalaError::invalid_input(
            "Password must be at least 8 characters"
        ));
    }
    
    // Generate random salt for key derivation
    let mut salt = [0u8; 32];
    OsRng.fill_bytes(&mut salt);
    
    // Generate random nonce for encryption
    let mut nonce_bytes = [0u8; 12];
    OsRng.fill_bytes(&mut nonce_bytes);
    
    // Derive encryption key from password using Argon2id
    let kdf_params = KdfParams::default();
    let key = derive_key(password, &salt, &kdf_params)?;
    
    // Encrypt with AES-256-GCM
    let cipher = Aes256Gcm::new_from_slice(&key)
        .map_err(|e| HawalaError::crypto_error(format!("Failed to create cipher: {}", e)))?;
    
    let nonce = Nonce::from_slice(&nonce_bytes);
    
    let ciphertext = cipher.encrypt(nonce, plaintext)
        .map_err(|e| HawalaError::crypto_error(format!("Encryption failed: {}", e)))?;
    
    Ok(EncryptedBackup {
        version: 1,
        salt: base64_encode(&salt),
        nonce: base64_encode(&nonce_bytes),
        ciphertext: base64_encode(&ciphertext),
        kdf_params,
    })
}

/// Decrypt wallet backup data with password
pub fn decrypt_backup(backup: &EncryptedBackup, password: &str) -> HawalaResult<Vec<u8>> {
    if backup.version != 1 {
        return Err(HawalaError::invalid_input(format!(
            "Unsupported backup version: {}",
            backup.version
        )));
    }
    
    // Decode components
    let salt = base64_decode(&backup.salt)?;
    let nonce_bytes = base64_decode(&backup.nonce)?;
    let ciphertext = base64_decode(&backup.ciphertext)?;
    
    if salt.len() != 32 {
        return Err(HawalaError::invalid_input("Invalid salt length"));
    }
    
    if nonce_bytes.len() != 12 {
        return Err(HawalaError::invalid_input("Invalid nonce length"));
    }
    
    // Derive encryption key from password
    let key = derive_key(password, &salt, &backup.kdf_params)?;
    
    // Decrypt with AES-256-GCM
    let cipher = Aes256Gcm::new_from_slice(&key)
        .map_err(|e| HawalaError::crypto_error(format!("Failed to create cipher: {}", e)))?;
    
    let nonce = Nonce::from_slice(&nonce_bytes);
    
    let plaintext = cipher.decrypt(nonce, ciphertext.as_ref())
        .map_err(|_| HawalaError::crypto_error(
            "Decryption failed - incorrect password or corrupted data"
        ))?;
    
    Ok(plaintext)
}

/// Derive encryption key from password using Argon2id
fn derive_key(password: &str, salt: &[u8], params: &KdfParams) -> HawalaResult<[u8; 32]> {
    use argon2::{Argon2, Algorithm, Version, Params};
    
    let argon2_params = Params::new(
        params.memory_cost,
        params.time_cost,
        params.parallelism,
        Some(32), // Output length
    ).map_err(|e| HawalaError::crypto_error(format!("Invalid KDF params: {}", e)))?;
    
    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, argon2_params);
    
    let mut key = [0u8; 32];
    argon2.hash_password_into(password.as_bytes(), salt, &mut key)
        .map_err(|e| HawalaError::crypto_error(format!("Key derivation failed: {}", e)))?;
    
    Ok(key)
}

/// Base64 encode bytes
fn base64_encode(data: &[u8]) -> String {
    use base64::Engine;
    base64::engine::general_purpose::STANDARD.encode(data)
}

/// Base64 decode string
fn base64_decode(s: &str) -> HawalaResult<Vec<u8>> {
    use base64::Engine;
    base64::engine::general_purpose::STANDARD.decode(s)
        .map_err(|e| HawalaError::parse_error(format!("Invalid base64: {}", e)))
}

/// Encrypt backup and serialize to JSON string
pub fn encrypt_backup_to_json(plaintext: &[u8], password: &str) -> HawalaResult<String> {
    let backup = encrypt_backup(plaintext, password)?;
    serde_json::to_string_pretty(&backup)
        .map_err(|e| HawalaError::internal(format!("JSON serialization failed: {}", e)))
}

/// Decrypt backup from JSON string
pub fn decrypt_backup_from_json(json: &str, password: &str) -> HawalaResult<Vec<u8>> {
    let backup: EncryptedBackup = serde_json::from_str(json)
        .map_err(|e| HawalaError::parse_error(format!("Invalid backup JSON: {}", e)))?;
    decrypt_backup(&backup, password)
}

/// Verify that a password can decrypt a backup without returning the plaintext
pub fn verify_backup_password(backup: &EncryptedBackup, password: &str) -> bool {
    decrypt_backup(backup, password).is_ok()
}

/// Estimate memory required for decryption
pub fn estimate_memory_usage(backup: &EncryptedBackup) -> usize {
    // KiB to bytes
    (backup.kdf_params.memory_cost as usize) * 1024
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encrypt_decrypt_roundtrip() {
        let plaintext = b"abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let password = "test_password_123";
        
        let encrypted = encrypt_backup(plaintext, password).unwrap();
        let decrypted = decrypt_backup(&encrypted, password).unwrap();
        
        assert_eq!(plaintext.as_slice(), decrypted.as_slice());
    }

    #[test]
    fn test_wrong_password_fails() {
        let plaintext = b"secret data";
        let password = "correct_password";
        let wrong_password = "wrong_password";
        
        let encrypted = encrypt_backup(plaintext, password).unwrap();
        let result = decrypt_backup(&encrypted, wrong_password);
        
        assert!(result.is_err());
    }

    #[test]
    fn test_short_password_rejected() {
        let plaintext = b"secret data";
        let password = "short";
        
        let result = encrypt_backup(plaintext, password);
        assert!(result.is_err());
    }

    #[test]
    fn test_json_roundtrip() {
        let plaintext = b"wallet backup data";
        let password = "secure_password_123";
        
        let json = encrypt_backup_to_json(plaintext, password).unwrap();
        let decrypted = decrypt_backup_from_json(&json, password).unwrap();
        
        assert_eq!(plaintext.as_slice(), decrypted.as_slice());
    }

    #[test]
    fn test_different_encryptions_produce_different_output() {
        let plaintext = b"same data";
        let password = "same_password";
        
        let encrypted1 = encrypt_backup(plaintext, password).unwrap();
        let encrypted2 = encrypt_backup(plaintext, password).unwrap();
        
        // Salt and nonce should be different
        assert_ne!(encrypted1.salt, encrypted2.salt);
        assert_ne!(encrypted1.nonce, encrypted2.nonce);
        assert_ne!(encrypted1.ciphertext, encrypted2.ciphertext);
    }

    #[test]
    fn test_verify_password() {
        let plaintext = b"test data";
        let password = "correct_password";
        
        let encrypted = encrypt_backup(plaintext, password).unwrap();
        
        assert!(verify_backup_password(&encrypted, password));
        assert!(!verify_backup_password(&encrypted, "wrong"));
    }
}
