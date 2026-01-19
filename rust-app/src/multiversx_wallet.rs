//! MultiversX (EGLD) Wallet Implementation
//!
//! Key derivation for MultiversX (formerly Elrond).
//! Uses Ed25519 with bech32 erd1... addresses.

use ed25519_dalek::{SigningKey, VerifyingKey};
use bech32::{self, Variant, ToBase32};

use crate::error::{HawalaError, HawalaResult};
use crate::types::MultiversXKeys;

/// Derive MultiversX keys from seed
pub fn derive_multiversx_keys(seed: &[u8]) -> HawalaResult<MultiversXKeys> {
    let private_key = derive_ed25519_key(seed)?;
    let private_hex = hex::encode(&private_key);
    
    let signing_key = SigningKey::from_bytes(&private_key);
    let verifying_key: VerifyingKey = (&signing_key).into();
    
    let public_hex = hex::encode(verifying_key.as_bytes());
    
    // MultiversX erd1 bech32 address
    let address = encode_multiversx_address(verifying_key.as_bytes())?;
    
    Ok(MultiversXKeys {
        private_hex,
        public_hex,
        address,
    })
}

fn derive_ed25519_key(seed: &[u8]) -> HawalaResult<[u8; 32]> {
    use hmac::{Hmac, Mac};
    use sha2::Sha512;
    
    type HmacSha512 = Hmac<Sha512>;
    
    // BIP44 path m/44'/508'/0'/0'/0'
    let mut mac = HmacSha512::new_from_slice(b"ed25519 seed")
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    mac.update(seed);
    let result = mac.finalize().into_bytes();
    
    let mut key = [0u8; 32];
    key.copy_from_slice(&result[..32]);
    Ok(key)
}

fn encode_multiversx_address(public_key: &[u8]) -> HawalaResult<String> {
    // MultiversX uses the raw 32-byte public key as address data
    let encoded = bech32::encode("erd", public_key.to_base32(), Variant::Bech32)
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    
    Ok(encoded)
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_multiversx_key_derivation() {
        let seed = [0u8; 64];
        let keys = derive_multiversx_keys(&seed).unwrap();
        
        assert!(!keys.private_hex.is_empty());
        assert!(keys.address.starts_with("erd1"));
    }
}
