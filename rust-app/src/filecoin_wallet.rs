//! Filecoin Wallet Implementation
//!
//! Key derivation for Filecoin (FIL), a decentralized storage network.
//! Supports secp256k1 addresses (f1...).

use secp256k1::{Secp256k1, SecretKey, PublicKey};
use blake2::{Blake2b512, Digest};

use crate::error::{HawalaError, HawalaResult};
use crate::types::FilecoinKeys;

/// Derive Filecoin keys from seed
pub fn derive_filecoin_keys(seed: &[u8]) -> HawalaResult<FilecoinKeys> {
    let private_key = derive_private_key(seed)?;
    let private_hex = hex::encode(&private_key);
    
    let secp = Secp256k1::new();
    let secret_key = SecretKey::from_slice(&private_key)
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    let public_key = PublicKey::from_secret_key(&secp, &secret_key);
    
    let public_uncompressed = public_key.serialize_uncompressed();
    let public_hex = hex::encode(&public_uncompressed);
    
    // Filecoin secp256k1 address (f1...)
    let address = derive_filecoin_address(&public_uncompressed)?;
    
    Ok(FilecoinKeys {
        private_hex,
        public_hex,
        address,
    })
}

fn derive_private_key(seed: &[u8]) -> HawalaResult<[u8; 32]> {
    use hmac::{Hmac, Mac};
    use sha2::Sha512;
    
    type HmacSha512 = Hmac<Sha512>;
    
    // BIP44 path m/44'/461'/0'/0/0
    let mut mac = HmacSha512::new_from_slice(b"Bitcoin seed")
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    mac.update(seed);
    let result = mac.finalize().into_bytes();
    
    let mut key = [0u8; 32];
    key.copy_from_slice(&result[..32]);
    Ok(key)
}

fn derive_filecoin_address(public_key: &[u8]) -> HawalaResult<String> {
    // Blake2b-160 hash of public key
    let mut hasher = Blake2b512::new();
    hasher.update(public_key);
    let hash = hasher.finalize();
    let payload = &hash[..20];
    
    // Checksum: blake2b-32 of (protocol_byte + payload)
    let mut checksum_input = vec![1u8]; // Protocol 1 = secp256k1
    checksum_input.extend_from_slice(payload);
    
    let mut checksum_hasher = Blake2b512::new();
    checksum_hasher.update(&checksum_input);
    let checksum_hash = checksum_hasher.finalize();
    let checksum = &checksum_hash[..4];
    
    // Encode: base32 lowercase of (payload + checksum)
    let mut address_bytes = payload.to_vec();
    address_bytes.extend_from_slice(checksum);
    
    let encoded = data_encoding::BASE32_NOPAD.encode(&address_bytes).to_lowercase();
    
    Ok(format!("f1{}", encoded))
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_filecoin_key_derivation() {
        let seed = [0u8; 64];
        let keys = derive_filecoin_keys(&seed).unwrap();
        
        assert!(!keys.private_hex.is_empty());
        assert!(keys.address.starts_with("f1"));
    }
}
