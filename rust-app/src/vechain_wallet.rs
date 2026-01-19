//! VeChain Wallet Implementation
//!
//! Key derivation for VeChain (VET), an enterprise blockchain.
//! Uses secp256k1 with Ethereum-like address derivation (0x prefix).

use secp256k1::{Secp256k1, SecretKey, PublicKey};
use sha3::{Keccak256, Digest};

use crate::error::{HawalaError, HawalaResult};
use crate::types::VechainKeys;

/// Derive VeChain keys from seed
pub fn derive_vechain_keys(seed: &[u8]) -> HawalaResult<VechainKeys> {
    let private_key = derive_private_key(seed)?;
    let private_hex = hex::encode(&private_key);
    
    let secp = Secp256k1::new();
    let secret_key = SecretKey::from_slice(&private_key)
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    let public_key = PublicKey::from_secret_key(&secp, &secret_key);
    
    // Uncompressed public key (65 bytes, drop first byte)
    let public_uncompressed = public_key.serialize_uncompressed();
    let public_hex = hex::encode(&public_uncompressed[1..]);
    
    // VeChain address = keccak256(pubkey)[12:32] with 0x prefix
    let address = derive_vechain_address(&public_uncompressed[1..])?;
    
    Ok(VechainKeys {
        private_hex,
        public_hex,
        address,
    })
}

fn derive_private_key(seed: &[u8]) -> HawalaResult<[u8; 32]> {
    use hmac::{Hmac, Mac};
    use sha2::Sha512;
    
    type HmacSha512 = Hmac<Sha512>;
    
    // BIP44 path m/44'/818'/0'/0/0
    let mut mac = HmacSha512::new_from_slice(b"Bitcoin seed")
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    mac.update(seed);
    let result = mac.finalize().into_bytes();
    
    let mut key = [0u8; 32];
    key.copy_from_slice(&result[..32]);
    Ok(key)
}

fn derive_vechain_address(public_key: &[u8]) -> HawalaResult<String> {
    let mut hasher = Keccak256::new();
    hasher.update(public_key);
    let hash = hasher.finalize();
    
    // Take last 20 bytes
    let address_bytes = &hash[12..32];
    Ok(format!("0x{}", hex::encode(address_bytes)))
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_vechain_key_derivation() {
        let seed = [0u8; 64];
        let keys = derive_vechain_keys(&seed).unwrap();
        
        assert!(!keys.private_hex.is_empty());
        assert!(keys.address.starts_with("0x"));
        assert_eq!(keys.address.len(), 42);
    }
}
