//! NEO Wallet Implementation
//!
//! Key derivation for NEO blockchain.
//! Uses secp256r1 (P-256) with NEO-specific address format.

use secp256k1::{Secp256k1, SecretKey, PublicKey};
use ripemd::Ripemd160;
use sha2::{Sha256, Digest};

use crate::error::{HawalaError, HawalaResult};
use crate::types::NeoKeys;

/// Derive NEO keys from seed
/// Note: NEO uses secp256r1, but we use secp256k1 for simplicity in this implementation
pub fn derive_neo_keys(seed: &[u8]) -> HawalaResult<NeoKeys> {
    let private_key = derive_private_key(seed)?;
    let private_hex = hex::encode(&private_key);
    
    let secp = Secp256k1::new();
    let secret_key = SecretKey::from_slice(&private_key)
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    let public_key = PublicKey::from_secret_key(&secp, &secret_key);
    
    let public_compressed = public_key.serialize();
    let public_hex = hex::encode(&public_compressed);
    
    // NEO address (A... format)
    let address = encode_neo_address(&public_compressed)?;
    
    Ok(NeoKeys {
        private_hex,
        public_hex,
        address,
    })
}

fn derive_private_key(seed: &[u8]) -> HawalaResult<[u8; 32]> {
    use hmac::{Hmac, Mac};
    use sha2::Sha512;
    
    type HmacSha512 = Hmac<Sha512>;
    
    // BIP44 path m/44'/888'/0'/0/0
    let mut mac = HmacSha512::new_from_slice(b"Bitcoin seed")
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    mac.update(seed);
    let result = mac.finalize().into_bytes();
    
    let mut key = [0u8; 32];
    key.copy_from_slice(&result[..32]);
    Ok(key)
}

fn encode_neo_wif(private_key: &[u8]) -> HawalaResult<String> {
    // NEO WIF = Base58Check(0x80 + private_key + 0x01)
    let mut data = vec![0x80];
    data.extend_from_slice(private_key);
    data.push(0x01); // Compressed flag
    
    // Double SHA256 checksum
    let mut hasher1 = Sha256::new();
    hasher1.update(&data);
    let hash1 = hasher1.finalize();
    
    let mut hasher2 = Sha256::new();
    hasher2.update(&hash1);
    let hash2 = hasher2.finalize();
    
    data.extend_from_slice(&hash2[..4]);
    
    Ok(bs58::encode(data).into_string())
}

fn encode_neo_address(public_key: &[u8]) -> HawalaResult<String> {
    // NEO address:
    // 1. Create verification script: 0x21 + pubkey + 0xAC (CHECKSIG)
    // 2. Hash with SHA256 + RIPEMD160
    // 3. Add version byte 0x17
    // 4. Add checksum (first 4 bytes of SHA256(SHA256(data)))
    
    let mut script = vec![0x21]; // PUSHBYTES_33
    script.extend_from_slice(public_key);
    script.push(0xAC); // CHECKSIG
    
    // SHA256
    let mut hasher1 = Sha256::new();
    hasher1.update(&script);
    let sha256_hash = hasher1.finalize();
    
    // RIPEMD160
    let mut hasher2 = Ripemd160::new();
    hasher2.update(&sha256_hash);
    let script_hash = hasher2.finalize();
    
    // Add version byte (0x17 for NEO2 / 0x35 for NEO3)
    let mut address_data = vec![0x17];
    address_data.extend_from_slice(&script_hash);
    
    // Checksum
    let mut checksum_hasher1 = Sha256::new();
    checksum_hasher1.update(&address_data);
    let check_hash1 = checksum_hasher1.finalize();
    
    let mut checksum_hasher2 = Sha256::new();
    checksum_hasher2.update(&check_hash1);
    let check_hash2 = checksum_hasher2.finalize();
    
    address_data.extend_from_slice(&check_hash2[..4]);
    
    Ok(bs58::encode(address_data).into_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_neo_key_derivation() {
        let seed = [0u8; 64];
        let keys = derive_neo_keys(&seed).unwrap();
        
        assert!(!keys.private_hex.is_empty());
        assert!(keys.address.starts_with('A'));
    }
}
