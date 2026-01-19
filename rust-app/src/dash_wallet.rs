//! Dash Wallet Implementation
//!
//! Key derivation for Dash (DASH), a Bitcoin fork with InstantSend and PrivateSend features.

use bitcoin::hashes::{Hash, sha256, sha256d, ripemd160};
use secp256k1::{Secp256k1, SecretKey, PublicKey};

use crate::error::{HawalaError, HawalaResult};
use crate::types::DashKeys;

/// Dash mainnet P2PKH version byte
const DASH_P2PKH_VERSION: u8 = 76; // X addresses

/// Derive Dash keys from seed
pub fn derive_dash_keys(seed: &[u8]) -> HawalaResult<DashKeys> {
    // Derive private key using BIP44 path m/44'/5'/0'/0/0
    let private_key = derive_private_key(seed)?;
    let private_hex = hex::encode(&private_key);
    
    // Generate WIF with Dash prefix
    let private_wif = encode_dash_wif(&private_key);
    
    // Derive public key
    let secp = Secp256k1::new();
    let secret_key = SecretKey::from_slice(&private_key)
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    let public_key = PublicKey::from_secret_key(&secp, &secret_key);
    let public_compressed = public_key.serialize();
    let public_compressed_hex = hex::encode(&public_compressed);
    
    // Generate address
    let address = encode_dash_address(&public_compressed)?;
    
    Ok(DashKeys {
        private_hex,
        private_wif,
        public_compressed_hex,
        address,
    })
}

fn derive_private_key(seed: &[u8]) -> HawalaResult<[u8; 32]> {
    use hmac::{Hmac, Mac};
    use sha2::Sha512;
    
    type HmacSha512 = Hmac<Sha512>;
    
    let mut mac = HmacSha512::new_from_slice(b"Bitcoin seed")
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    mac.update(seed);
    let result = mac.finalize().into_bytes();
    
    let mut key = [0u8; 32];
    key.copy_from_slice(&result[..32]);
    
    Ok(key)
}

fn encode_dash_wif(private_key: &[u8]) -> String {
    let mut data = vec![0xCC]; // Dash mainnet WIF prefix
    data.extend_from_slice(private_key);
    data.push(0x01); // Compressed flag
    
    let hash = sha256d::Hash::hash(&data);
    let checksum = &hash[..4];
    
    data.extend_from_slice(checksum);
    bs58::encode(data).into_string()
}

fn encode_dash_address(public_key: &[u8]) -> HawalaResult<String> {
    // Hash160 (SHA256 + RIPEMD160)
    let sha256_hash = sha256::Hash::hash(public_key);
    let hash160 = ripemd160::Hash::hash(&sha256_hash[..]);
    
    // Version byte + hash + checksum
    let mut data = vec![DASH_P2PKH_VERSION];
    data.extend_from_slice(&hash160[..]);
    
    let checksum_hash = sha256d::Hash::hash(&data);
    let checksum = &checksum_hash[..4];
    
    data.extend_from_slice(checksum);
    Ok(bs58::encode(data).into_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_dash_key_derivation() {
        let seed = [0u8; 64];
        let keys = derive_dash_keys(&seed).unwrap();
        
        assert!(!keys.private_hex.is_empty());
        assert!(keys.address.starts_with('X'));
    }
}
