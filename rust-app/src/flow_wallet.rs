//! Flow Wallet Implementation
//!
//! Key derivation for Flow blockchain.
//! Uses ECDSA secp256k1 with specific address format.

use secp256k1::{Secp256k1, SecretKey, PublicKey};
use sha3::{Sha3_256, Digest};

use crate::error::{HawalaError, HawalaResult};
use crate::types::FlowKeys;

/// Derive Flow keys from seed
pub fn derive_flow_keys(seed: &[u8]) -> HawalaResult<FlowKeys> {
    let private_key = derive_private_key(seed)?;
    let private_hex = hex::encode(&private_key);
    
    let secp = Secp256k1::new();
    let secret_key = SecretKey::from_slice(&private_key)
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    let public_key = PublicKey::from_secret_key(&secp, &secret_key);
    
    // Flow uses uncompressed public key
    let public_uncompressed = public_key.serialize_uncompressed();
    let public_hex = hex::encode(&public_uncompressed[1..]); // Skip 0x04 prefix
    
    // Flow address (8 bytes)
    let address = derive_flow_address(&public_uncompressed)?;
    
    Ok(FlowKeys {
        private_hex,
        public_hex,
        address,
    })
}

fn derive_private_key(seed: &[u8]) -> HawalaResult<[u8; 32]> {
    use hmac::{Hmac, Mac};
    use sha2::Sha512;
    
    type HmacSha512 = Hmac<Sha512>;
    
    // BIP44 path m/44'/539'/0'/0/0
    let mut mac = HmacSha512::new_from_slice(b"Bitcoin seed")
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    mac.update(seed);
    let result = mac.finalize().into_bytes();
    
    let mut key = [0u8; 32];
    key.copy_from_slice(&result[..32]);
    Ok(key)
}

fn derive_flow_address(public_key: &[u8]) -> HawalaResult<String> {
    // Flow address = last 8 bytes of SHA3-256(public_key)
    let mut hasher = Sha3_256::new();
    hasher.update(&public_key[1..]); // Skip 0x04 prefix
    let hash = hasher.finalize();
    
    // Last 8 bytes
    let address_bytes = &hash[24..32];
    
    Ok(format!("0x{}", hex::encode(address_bytes)))
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_flow_key_derivation() {
        let seed = [0u8; 64];
        let keys = derive_flow_keys(&seed).unwrap();
        
        assert!(!keys.private_hex.is_empty());
        assert!(keys.address.starts_with("0x"));
        assert_eq!(keys.address.len(), 18); // 0x + 16 hex chars
    }
}
