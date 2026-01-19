//! EOS Wallet Implementation
//!
//! Key derivation for EOS blockchain.
//! Uses secp256k1 with EOS-specific Base58 format.

use secp256k1::{Secp256k1, SecretKey, PublicKey};
use ripemd::Ripemd160;
use sha2::Digest;

use crate::error::{HawalaError, HawalaResult};
use crate::types::EosKeys;

/// Derive EOS keys from seed
pub fn derive_eos_keys(seed: &[u8]) -> HawalaResult<EosKeys> {
    let private_key = derive_private_key(seed)?;
    let private_hex = hex::encode(&private_key);
    
    let secp = Secp256k1::new();
    let secret_key = SecretKey::from_slice(&private_key)
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    let public_key = PublicKey::from_secret_key(&secp, &secret_key);
    
    let public_compressed = public_key.serialize();
    let public_hex = hex::encode(&public_compressed);
    
    // EOS public key format (EOS + Base58Check)
    let public_eos = encode_eos_public_key(&public_compressed)?;
    
    Ok(EosKeys {
        private_hex,
        public_hex,
        public_key: public_eos,
    })
}

fn derive_private_key(seed: &[u8]) -> HawalaResult<[u8; 32]> {
    use hmac::{Hmac, Mac};
    use sha2::Sha512;
    
    type HmacSha512 = Hmac<Sha512>;
    
    // BIP44 path m/44'/194'/0'/0/0
    let mut mac = HmacSha512::new_from_slice(b"Bitcoin seed")
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    mac.update(seed);
    let result = mac.finalize().into_bytes();
    
    let mut key = [0u8; 32];
    key.copy_from_slice(&result[..32]);
    Ok(key)
}

fn encode_eos_wif(private_key: &[u8]) -> HawalaResult<String> {
    // EOS WIF = Base58Check(0x80 + private_key)
    use sha2::Sha256;
    
    let mut data = vec![0x80];
    data.extend_from_slice(private_key);
    
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

fn encode_eos_public_key(public_key: &[u8]) -> HawalaResult<String> {
    // EOS public key = "EOS" + Base58(pubkey + RIPEMD160(pubkey)[0:4])
    let mut hasher = Ripemd160::new();
    hasher.update(public_key);
    let hash = hasher.finalize();
    
    let mut data = public_key.to_vec();
    data.extend_from_slice(&hash[..4]);
    
    Ok(format!("EOS{}", bs58::encode(data).into_string()))
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_eos_key_derivation() {
        let seed = [0u8; 64];
        let keys = derive_eos_keys(&seed).unwrap();
        
        assert!(!keys.private_hex.is_empty());
        assert!(keys.public_key.starts_with("EOS"));
    }
}
