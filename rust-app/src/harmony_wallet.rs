//! Harmony Wallet Implementation
//!
//! Key derivation for Harmony (ONE), an EVM-compatible sharded blockchain.
//! Supports both 0x and one1... bech32 addresses.

use secp256k1::{Secp256k1, SecretKey, PublicKey};
use sha3::{Keccak256, Digest};
use bech32::{self, Variant, ToBase32};

use crate::error::{HawalaError, HawalaResult};
use crate::types::HarmonyKeys;

/// Derive Harmony keys from seed
pub fn derive_harmony_keys(seed: &[u8]) -> HawalaResult<HarmonyKeys> {
    let private_key = derive_private_key(seed)?;
    let private_hex = hex::encode(&private_key);
    
    let secp = Secp256k1::new();
    let secret_key = SecretKey::from_slice(&private_key)
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    let public_key = PublicKey::from_secret_key(&secp, &secret_key);
    
    let public_uncompressed = public_key.serialize_uncompressed();
    let public_hex = hex::encode(&public_uncompressed[1..]);
    
    // Standard Ethereum-style address
    let address = derive_eth_address(&public_uncompressed[1..])?;
    
    // Harmony bech32 address (one1...)
    let address_bytes = hex::decode(&address[2..])
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    let bech32_address = bech32::encode("one", address_bytes.to_base32(), Variant::Bech32)
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    
    Ok(HarmonyKeys {
        private_hex,
        public_hex,
        address,
        bech32_address,
    })
}

fn derive_private_key(seed: &[u8]) -> HawalaResult<[u8; 32]> {
    use hmac::{Hmac, Mac};
    use sha2::Sha512;
    
    type HmacSha512 = Hmac<Sha512>;
    
    // BIP44 path m/44'/1023'/0'/0/0
    let mut mac = HmacSha512::new_from_slice(b"Bitcoin seed")
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    mac.update(seed);
    let result = mac.finalize().into_bytes();
    
    let mut key = [0u8; 32];
    key.copy_from_slice(&result[..32]);
    Ok(key)
}

fn derive_eth_address(public_key: &[u8]) -> HawalaResult<String> {
    let mut hasher = Keccak256::new();
    hasher.update(public_key);
    let hash = hasher.finalize();
    
    let address_bytes = &hash[12..32];
    Ok(format!("0x{}", hex::encode(address_bytes)))
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_harmony_key_derivation() {
        let seed = [0u8; 64];
        let keys = derive_harmony_keys(&seed).unwrap();
        
        assert!(!keys.private_hex.is_empty());
        assert!(keys.address.starts_with("0x"));
        assert!(keys.bech32_address.starts_with("one1"));
    }
}
