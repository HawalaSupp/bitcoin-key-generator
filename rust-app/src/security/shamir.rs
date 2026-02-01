//! Shamir's Secret Sharing Implementation
//!
//! Splits a seed phrase into N shares where M shares are required to recover.
//! Uses the sharks crate for cryptographically secure SSS.

use crate::error::{HawalaError, HawalaResult, ErrorCode};
use sharks::{Share, Sharks};
use serde::{Deserialize, Serialize};

// =============================================================================
// Types
// =============================================================================

/// A single recovery share from Shamir's Secret Sharing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecoveryShare {
    /// Share identifier (1-255)
    pub id: u8,
    /// The share data (base64 encoded)
    pub data: String,
    /// Minimum shares needed to recover (M in M-of-N)
    pub threshold: u8,
    /// Total shares created (N in M-of-N)
    pub total: u8,
    /// Unix timestamp when created
    pub created_at: u64,
    /// Human-readable label ("Mom", "Bank", etc.)
    pub label: String,
    /// Checksum for integrity verification
    pub checksum: String,
}

/// Request to create shares
#[derive(Debug, Clone, Deserialize)]
pub struct CreateSharesRequest {
    /// The seed phrase to split (12 or 24 words)
    pub seed_phrase: String,
    /// Total number of shares to create (N)
    pub total_shares: u8,
    /// Minimum shares needed to recover (M)
    pub threshold: u8,
    /// Optional labels for each share
    pub labels: Option<Vec<String>>,
}

/// Request to recover from shares
#[derive(Debug, Clone, Deserialize)]
pub struct RecoverRequest {
    /// The shares to use for recovery
    pub shares: Vec<RecoveryShare>,
}

/// Result of share validation
#[derive(Debug, Clone, Serialize)]
pub struct ShareValidation {
    pub valid: bool,
    pub share_id: u8,
    pub threshold: u8,
    pub total: u8,
    pub error: Option<String>,
}

// =============================================================================
// Public API
// =============================================================================

/// Create M-of-N Shamir shares from a seed phrase
/// 
/// # Arguments
/// * `seed_phrase` - The BIP-39 seed phrase (12 or 24 words)
/// * `total_shares` - Total number of shares to create (N, 2-255)
/// * `threshold` - Minimum shares needed to recover (M, 2-N)
/// * `labels` - Optional labels for each share
/// 
/// # Returns
/// Vector of RecoveryShare structs, each containing one share
pub fn create_shares(
    seed_phrase: &str,
    total_shares: u8,
    threshold: u8,
    labels: Option<Vec<String>>,
) -> HawalaResult<Vec<RecoveryShare>> {
    // Validate inputs
    if threshold < 2 {
        return Err(HawalaError::invalid_input("Threshold must be at least 2"));
    }
    if total_shares < threshold {
        return Err(HawalaError::invalid_input("Total shares must be >= threshold"));
    }
    // Note: u8 max is 255, so no need to check upper bound
    
    // Validate seed phrase
    let words: Vec<&str> = seed_phrase.trim().split_whitespace().collect();
    if words.len() != 12 && words.len() != 24 {
        return Err(HawalaError::invalid_input(
            "Seed phrase must be 12 or 24 words"
        ));
    }
    
    // Convert seed phrase to bytes
    let secret_bytes = seed_phrase.as_bytes();
    
    // Create Sharks instance with threshold
    let sharks = Sharks(threshold);
    
    // Generate shares (this uses a cryptographically secure RNG internally)
    let dealer = sharks.dealer(secret_bytes);
    let shares: Vec<Share> = dealer.take(total_shares as usize).collect();
    
    // Get current timestamp
    let created_at = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    
    // Convert to RecoveryShare format
    let mut result = Vec::with_capacity(shares.len());
    
    for (i, share) in shares.iter().enumerate() {
        let share_bytes: Vec<u8> = share.into();
        let share_base64 = base64_encode(&share_bytes);
        
        // Create checksum (first 8 chars of hex SHA256)
        let checksum = calculate_checksum(&share_bytes);
        
        // Get label
        let label = labels
            .as_ref()
            .and_then(|l| l.get(i).cloned())
            .unwrap_or_else(|| format!("Share {}", i + 1));
        
        result.push(RecoveryShare {
            id: (i + 1) as u8,
            data: share_base64,
            threshold,
            total: total_shares,
            created_at,
            label,
            checksum,
        });
    }
    
    Ok(result)
}

/// Recover a seed phrase from M shares
/// 
/// # Arguments
/// * `shares` - At least M RecoveryShare structs
/// 
/// # Returns
/// The recovered seed phrase
pub fn recover_seed(shares: &[RecoveryShare]) -> HawalaResult<String> {
    if shares.is_empty() {
        return Err(HawalaError::invalid_input("No shares provided"));
    }
    
    // Verify we have enough shares
    let threshold = shares[0].threshold;
    if shares.len() < threshold as usize {
        return Err(HawalaError::invalid_input(format!(
            "Need at least {} shares for recovery, got {}",
            threshold,
            shares.len()
        )));
    }
    
    // Verify all shares have same threshold (from same split)
    for share in shares {
        if share.threshold != threshold {
            return Err(HawalaError::invalid_input(
                "Shares have different thresholds - may be from different splits"
            ));
        }
    }
    
    // Convert shares to sharks format
    let sharks = Sharks(threshold);
    let mut shark_shares = Vec::new();
    
    for share in shares {
        // Validate checksum
        let share_bytes = base64_decode(&share.data)?;
        let expected_checksum = calculate_checksum(&share_bytes);
        
        if share.checksum != expected_checksum {
            return Err(HawalaError::invalid_input(format!(
                "Share {} has invalid checksum - may be corrupted",
                share.id
            )));
        }
        
        // Parse share
        let shark_share = Share::try_from(share_bytes.as_slice())
            .map_err(|_| HawalaError::invalid_input(format!(
                "Share {} has invalid format",
                share.id
            )))?;
        
        shark_shares.push(shark_share);
    }
    
    // Recover secret
    let secret_bytes = sharks.recover(&shark_shares)
        .map_err(|_| HawalaError::new(
            ErrorCode::CryptoError,
            "Failed to recover secret - shares may be invalid or from different splits"
        ))?;
    
    // Convert back to string
    let seed_phrase = String::from_utf8(secret_bytes)
        .map_err(|_| HawalaError::new(
            ErrorCode::CryptoError,
            "Recovered data is not valid UTF-8"
        ))?;
    
    // Validate recovered seed phrase
    let words: Vec<&str> = seed_phrase.trim().split_whitespace().collect();
    if words.len() != 12 && words.len() != 24 {
        return Err(HawalaError::new(
            ErrorCode::CryptoError,
            "Recovered secret is not a valid seed phrase"
        ));
    }
    
    Ok(seed_phrase)
}

/// Validate a share without revealing the secret
/// 
/// Checks that the share is well-formed and has a valid checksum
pub fn validate_share(share: &RecoveryShare) -> ShareValidation {
    // Check basic structure
    if share.data.is_empty() {
        return ShareValidation {
            valid: false,
            share_id: share.id,
            threshold: share.threshold,
            total: share.total,
            error: Some("Share data is empty".to_string()),
        };
    }
    
    // Decode and verify checksum
    match base64_decode(&share.data) {
        Ok(bytes) => {
            let expected_checksum = calculate_checksum(&bytes);
            if share.checksum != expected_checksum {
                ShareValidation {
                    valid: false,
                    share_id: share.id,
                    threshold: share.threshold,
                    total: share.total,
                    error: Some("Checksum mismatch - share may be corrupted".to_string()),
                }
            } else {
                // Try to parse as a valid share
                match Share::try_from(bytes.as_slice()) {
                    Ok(_) => ShareValidation {
                        valid: true,
                        share_id: share.id,
                        threshold: share.threshold,
                        total: share.total,
                        error: None,
                    },
                    Err(_) => ShareValidation {
                        valid: false,
                        share_id: share.id,
                        threshold: share.threshold,
                        total: share.total,
                        error: Some("Invalid share format".to_string()),
                    },
                }
            }
        }
        Err(e) => ShareValidation {
            valid: false,
            share_id: share.id,
            threshold: share.threshold,
            total: share.total,
            error: Some(format!("Failed to decode share: {}", e)),
        },
    }
}

// =============================================================================
// Helper Functions
// =============================================================================

fn base64_encode(data: &[u8]) -> String {
    use base64::{Engine as _, engine::general_purpose::STANDARD};
    STANDARD.encode(data)
}

fn base64_decode(data: &str) -> HawalaResult<Vec<u8>> {
    use base64::{Engine as _, engine::general_purpose::STANDARD};
    STANDARD.decode(data)
        .map_err(|e| HawalaError::invalid_input(format!("Invalid base64: {}", e)))
}

fn calculate_checksum(data: &[u8]) -> String {
    use sha2::{Sha256, Digest};
    let mut hasher = Sha256::new();
    hasher.update(data);
    let hash = hasher.finalize();
    hex::encode(&hash[..4])
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    
    const TEST_SEED: &str = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
    
    #[test]
    fn test_create_shares_2_of_3() {
        let shares = create_shares(TEST_SEED, 3, 2, None).unwrap();
        
        assert_eq!(shares.len(), 3);
        for (i, share) in shares.iter().enumerate() {
            assert_eq!(share.id, (i + 1) as u8);
            assert_eq!(share.threshold, 2);
            assert_eq!(share.total, 3);
            assert!(!share.data.is_empty());
            assert!(!share.checksum.is_empty());
        }
    }
    
    #[test]
    fn test_recover_2_of_3() {
        let shares = create_shares(TEST_SEED, 3, 2, None).unwrap();
        
        // Recover with first 2 shares
        let recovered = recover_seed(&shares[..2]).unwrap();
        assert_eq!(recovered, TEST_SEED);
        
        // Recover with last 2 shares
        let recovered = recover_seed(&shares[1..]).unwrap();
        assert_eq!(recovered, TEST_SEED);
        
        // Recover with first and last shares
        let recovered = recover_seed(&[shares[0].clone(), shares[2].clone()]).unwrap();
        assert_eq!(recovered, TEST_SEED);
    }
    
    #[test]
    fn test_recover_3_of_5() {
        let shares = create_shares(TEST_SEED, 5, 3, None).unwrap();
        
        // Need at least 3 shares
        assert!(recover_seed(&shares[..2]).is_err());
        
        // 3 shares should work
        let recovered = recover_seed(&shares[..3]).unwrap();
        assert_eq!(recovered, TEST_SEED);
    }
    
    #[test]
    fn test_validate_share() {
        let shares = create_shares(TEST_SEED, 3, 2, None).unwrap();
        
        let validation = validate_share(&shares[0]);
        assert!(validation.valid);
        assert!(validation.error.is_none());
        
        // Corrupt a share
        let mut corrupted = shares[0].clone();
        corrupted.data = "invalid_base64!!!".to_string();
        
        let validation = validate_share(&corrupted);
        assert!(!validation.valid);
        assert!(validation.error.is_some());
    }
    
    #[test]
    fn test_labels() {
        let labels = vec![
            "Mom".to_string(),
            "Bank Safe".to_string(),
            "Lawyer".to_string(),
        ];
        
        let shares = create_shares(TEST_SEED, 3, 2, Some(labels.clone())).unwrap();
        
        assert_eq!(shares[0].label, "Mom");
        assert_eq!(shares[1].label, "Bank Safe");
        assert_eq!(shares[2].label, "Lawyer");
    }
    
    #[test]
    fn test_24_word_seed() {
        let seed_24 = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art";
        
        let shares = create_shares(seed_24, 3, 2, None).unwrap();
        let recovered = recover_seed(&shares[..2]).unwrap();
        assert_eq!(recovered, seed_24);
    }
    
    #[test]
    fn test_invalid_inputs() {
        // Threshold too low
        assert!(create_shares(TEST_SEED, 3, 1, None).is_err());
        
        // Total < threshold
        assert!(create_shares(TEST_SEED, 2, 3, None).is_err());
        
        // Invalid seed (wrong word count)
        assert!(create_shares("one two three", 3, 2, None).is_err());
    }
}
