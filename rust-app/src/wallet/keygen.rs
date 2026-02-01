//! Key Generation
//!
//! Creates wallets from entropy or mnemonic phrases.
//! 
//! SECURITY: All sensitive data (entropy, seeds) is zeroized on drop.

use bip39::Mnemonic;
use rand::rngs::OsRng;
use rand::RngCore;
use zeroize::Zeroizing;

use crate::error::{HawalaError, HawalaResult};
use crate::types::*;

use super::derivation;

/// Create a new wallet from random entropy
/// 
/// SECURITY: Entropy is securely zeroized after mnemonic generation
pub fn create_wallet_from_entropy() -> HawalaResult<(String, AllKeys)> {
    // Use Zeroizing wrapper to ensure entropy is cleared on drop
    let mut entropy = Zeroizing::new([0u8; 16]); // 128 bits = 12 words
    OsRng.fill_bytes(entropy.as_mut());
    
    let mnemonic = Mnemonic::from_entropy(entropy.as_ref())
        .map_err(|e| HawalaError::crypto_error(format!("Failed to create mnemonic: {}", e)))?;
    
    let phrase = mnemonic.to_string();
    
    // Seed is 64 bytes - wrap in Zeroizing for automatic cleanup
    let seed = Zeroizing::new(mnemonic.to_seed(""));
    
    let keys = derivation::derive_all_keys(seed.as_ref())?;
    
    // entropy is automatically zeroized when dropped here
    Ok((phrase, keys))
}

/// Restore wallet from mnemonic phrase
/// 
/// SECURITY: Seed is securely zeroized after key derivation
pub fn restore_wallet(mnemonic_phrase: &str) -> HawalaResult<AllKeys> {
    restore_wallet_with_passphrase(mnemonic_phrase, "")
}

/// Restore wallet from mnemonic phrase with optional passphrase (BIP-39)
/// 
/// SECURITY: Seed is securely zeroized after key derivation
pub fn restore_wallet_with_passphrase(mnemonic_phrase: &str, passphrase: &str) -> HawalaResult<AllKeys> {
    let mnemonic = Mnemonic::parse(mnemonic_phrase)
        .map_err(|e| HawalaError::new(crate::error::ErrorCode::InvalidMnemonic, format!("Invalid mnemonic: {}", e)))?;
    
    // Wrap seed in Zeroizing for automatic cleanup
    let seed = Zeroizing::new(mnemonic.to_seed(passphrase));
    derivation::derive_all_keys(seed.as_ref())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_wallet() {
        let result = create_wallet_from_entropy();
        assert!(result.is_ok());
        
        let (mnemonic, keys) = result.unwrap();
        assert_eq!(mnemonic.split_whitespace().count(), 12);
        assert!(!keys.bitcoin.address.is_empty());
        assert!(!keys.ethereum.address.is_empty());
    }

    #[test]
    fn test_restore_wallet() {
        // Test vector mnemonic
        let mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let result = restore_wallet(mnemonic);
        assert!(result.is_ok());
    }
}
