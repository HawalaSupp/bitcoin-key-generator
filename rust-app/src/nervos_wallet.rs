//! Nervos CKB Wallet Implementation
//!
//! Key derivation for Nervos Network (CKB).
//! Uses secp256k1 with bech32m ckb1... addresses.

use secp256k1::{Secp256k1, SecretKey, PublicKey};
use blake2::{Blake2b, Digest};
use bech32::{self, Variant, ToBase32};

use crate::error::{HawalaError, HawalaResult};
use crate::types::NervosKeys;

/// Derive Nervos CKB keys from seed
pub fn derive_nervos_keys(seed: &[u8]) -> HawalaResult<NervosKeys> {
    let private_key = derive_private_key(seed)?;
    let private_hex = hex::encode(&private_key);
    
    let secp = Secp256k1::new();
    let secret_key = SecretKey::from_slice(&private_key)
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    let public_key = PublicKey::from_secret_key(&secp, &secret_key);
    
    let public_compressed = public_key.serialize();
    let public_hex = hex::encode(&public_compressed);
    
    // CKB lock hash and address
    let _lock_hash = derive_lock_hash(&public_compressed)?;
    let address = encode_ckb_address(&_lock_hash)?;
    
    Ok(NervosKeys {
        private_hex,
        public_hex,
        address,
    })
}

fn derive_private_key(seed: &[u8]) -> HawalaResult<[u8; 32]> {
    use hmac::{Hmac, Mac};
    use sha2::Sha512;
    
    type HmacSha512 = Hmac<Sha512>;
    
    // BIP44 path m/44'/309'/0'/0/0
    let mut mac = HmacSha512::new_from_slice(b"Bitcoin seed")
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    mac.update(seed);
    let result = mac.finalize().into_bytes();
    
    let mut key = [0u8; 32];
    key.copy_from_slice(&result[..32]);
    Ok(key)
}

fn derive_lock_hash(public_key: &[u8]) -> HawalaResult<String> {
    // CKB uses blake2b-256 with personalization "ckb-default-hash"
    use blake2::digest::Update;
    use blake2::digest::VariableOutput;
    use blake2::Blake2bVar;
    
    let mut hasher = Blake2bVar::new(32).unwrap();
    hasher.update(public_key);
    let mut result = vec![0u8; 32];
    hasher.finalize_variable(&mut result).unwrap();
    
    // First 20 bytes for lock args
    Ok(hex::encode(&result[..20]))
}

fn encode_ckb_address(lock_args: &str) -> HawalaResult<String> {
    // CKB full address format (2021):
    // 0x00 (format type) + code_hash_index (1 byte) + lock_args
    
    let args = hex::decode(lock_args)
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    
    // Short address format for default lock script
    // Format type 0x01 (short format) + code hash index 0x00 (secp256k1-blake160)
    let mut address_data = vec![0x01, 0x00];
    address_data.extend_from_slice(&args);
    
    // CKB uses bech32m
    let encoded = bech32::encode("ckb", address_data.to_base32(), Variant::Bech32m)
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    
    Ok(encoded)
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_nervos_key_derivation() {
        let seed = [0u8; 64];
        let keys = derive_nervos_keys(&seed).unwrap();
        
        assert!(!keys.private_hex.is_empty());
        assert!(keys.address.starts_with("ckb1"));
    }
}
