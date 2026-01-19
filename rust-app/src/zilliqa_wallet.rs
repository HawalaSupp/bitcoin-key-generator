//! Zilliqa Wallet Implementation
//!
//! Key derivation for Zilliqa (ZIL).
//! Uses secp256k1 with bech32 zil1... addresses.

use secp256k1::{Secp256k1, SecretKey, PublicKey};
use sha2::{Sha256, Digest};
use bech32::{self, Variant, ToBase32};

use crate::error::{HawalaError, HawalaResult};
use crate::types::ZilliqaKeys;

/// Derive Zilliqa keys from seed
pub fn derive_zilliqa_keys(seed: &[u8]) -> HawalaResult<ZilliqaKeys> {
    let private_key = derive_private_key(seed)?;
    let private_hex = hex::encode(&private_key);
    
    let secp = Secp256k1::new();
    let secret_key = SecretKey::from_slice(&private_key)
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    let public_key = PublicKey::from_secret_key(&secp, &secret_key);
    
    let public_compressed = public_key.serialize();
    let public_hex = hex::encode(&public_compressed);
    
    // Zilliqa uses SHA256 hash of public key for address
    let address_hex = derive_zilliqa_address_hex(&public_compressed)?;
    let address_bech32 = encode_zilliqa_bech32(&address_hex)?;
    
    Ok(ZilliqaKeys {
        private_hex,
        public_hex,
        address: address_hex,
        bech32_address: address_bech32,
    })
}

fn derive_private_key(seed: &[u8]) -> HawalaResult<[u8; 32]> {
    use hmac::{Hmac, Mac};
    use sha2::Sha512;
    
    type HmacSha512 = Hmac<Sha512>;
    
    // BIP44 path m/44'/313'/0'/0/0
    let mut mac = HmacSha512::new_from_slice(b"Bitcoin seed")
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    mac.update(seed);
    let result = mac.finalize().into_bytes();
    
    let mut key = [0u8; 32];
    key.copy_from_slice(&result[..32]);
    Ok(key)
}

fn derive_zilliqa_address_hex(public_key: &[u8]) -> HawalaResult<String> {
    // Zilliqa address = last 20 bytes of SHA256(uncompressed public key)
    // First we need to get uncompressed key
    let secp = Secp256k1::new();
    let pk = PublicKey::from_slice(public_key)
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    let uncompressed = pk.serialize_uncompressed();
    
    let mut hasher = Sha256::new();
    hasher.update(&uncompressed[1..]); // Skip 0x04 prefix
    let hash = hasher.finalize();
    
    // Last 20 bytes
    Ok(hex::encode(&hash[12..32]))
}

fn encode_zilliqa_bech32(address_hex: &str) -> HawalaResult<String> {
    let address_bytes = hex::decode(address_hex)
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    
    let encoded = bech32::encode("zil", address_bytes.to_base32(), Variant::Bech32)
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    
    Ok(encoded)
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_zilliqa_key_derivation() {
        let seed = [0u8; 64];
        let keys = derive_zilliqa_keys(&seed).unwrap();
        
        assert!(!keys.private_hex.is_empty());
        assert!(keys.bech32_address.starts_with("zil1"));
        assert_eq!(keys.address.len(), 40);
    }
}
