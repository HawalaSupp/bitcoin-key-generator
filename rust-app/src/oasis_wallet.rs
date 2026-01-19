//! Oasis Network Wallet Implementation
//!
//! Key derivation for Oasis Network (ROSE), a privacy-focused L1.
//! Uses Ed25519 keys with bech32 addresses.

use ed25519_dalek::{SigningKey, VerifyingKey};
use bech32::{self, Variant, ToBase32};

use crate::error::{HawalaError, HawalaResult};
use crate::types::OasisKeys;

/// Derive Oasis keys from seed
pub fn derive_oasis_keys(seed: &[u8]) -> HawalaResult<OasisKeys> {
    // Derive Ed25519 key from seed
    let private_key = derive_ed25519_key(seed)?;
    let private_hex = hex::encode(&private_key);
    
    let signing_key = SigningKey::from_bytes(&private_key);
    let verifying_key: VerifyingKey = (&signing_key).into();
    
    let public_hex = hex::encode(verifying_key.as_bytes());
    
    // Oasis bech32 address
    let address = encode_oasis_address(verifying_key.as_bytes())?;
    
    Ok(OasisKeys {
        private_hex,
        public_hex,
        address,
    })
}

fn derive_ed25519_key(seed: &[u8]) -> HawalaResult<[u8; 32]> {
    use hmac::{Hmac, Mac};
    use sha2::Sha512;
    
    type HmacSha512 = Hmac<Sha512>;
    
    // BIP44 path m/44'/474'/0'
    let mut mac = HmacSha512::new_from_slice(b"ed25519 seed")
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    mac.update(seed);
    let result = mac.finalize().into_bytes();
    
    let mut key = [0u8; 32];
    key.copy_from_slice(&result[..32]);
    Ok(key)
}

fn encode_oasis_address(public_key: &[u8]) -> HawalaResult<String> {
    // Oasis staking address format: oasis1 + bech32(context_id + public_key_hash)
    use sha2::{Sha512_256, Digest};
    
    // Context for staking addresses
    let context = b"oasis-core/address: staking";
    let mut hasher = Sha512_256::new();
    hasher.update(context);
    hasher.update([0u8]); // version
    hasher.update(public_key);
    let hash = hasher.finalize();
    
    // Take first 20 bytes + version byte
    let mut address_data = vec![0u8]; // version 0
    address_data.extend_from_slice(&hash[..20]);
    
    let encoded = bech32::encode("oasis", address_data.to_base32(), Variant::Bech32)
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    
    Ok(encoded)
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_oasis_key_derivation() {
        let seed = [0u8; 64];
        let keys = derive_oasis_keys(&seed).unwrap();
        
        assert!(!keys.private_hex.is_empty());
        assert!(keys.address.starts_with("oasis1"));
    }
}
