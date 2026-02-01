//! Waves Wallet Implementation
//!
//! Key derivation for Waves blockchain.
//! Uses Curve25519 for signing.

use ed25519_dalek::{SigningKey, VerifyingKey};
use sha2::{Sha256, Digest};
use blake2::Blake2b512;

use crate::error::HawalaResult;
use crate::types::WavesKeys;

/// Waves mainnet chain ID
const WAVES_CHAIN_ID: u8 = b'W';

/// Derive Waves keys from seed
pub fn derive_waves_keys(seed: &[u8]) -> HawalaResult<WavesKeys> {
    // Waves uses a specific derivation from seed phrase
    let private_key = derive_waves_private_key(seed)?;
    let private_hex = hex::encode(&private_key);
    
    let signing_key = SigningKey::from_bytes(&private_key);
    let verifying_key: VerifyingKey = (&signing_key).into();
    let public_hex = hex::encode(verifying_key.as_bytes());
    
    // Waves address
    let address = encode_waves_address(verifying_key.as_bytes())?;
    
    Ok(WavesKeys {
        private_hex,
        public_hex,
        address,
    })
}

fn derive_waves_private_key(seed: &[u8]) -> HawalaResult<[u8; 32]> {
    // Waves-specific key derivation
    // account_seed = sha256(sha256(seed) + nonce[4 bytes])
    let mut hasher = Sha256::new();
    hasher.update(seed);
    let first_hash = hasher.finalize();
    
    let mut second_hasher = Sha256::new();
    second_hasher.update(&first_hash);
    second_hasher.update([0u8, 0u8, 0u8, 0u8]); // nonce = 0
    let account_seed = second_hasher.finalize();
    
    // Hash again to get 32-byte private key
    let mut key_hasher = Sha256::new();
    key_hasher.update(&account_seed);
    let key = key_hasher.finalize();
    
    let mut private_key = [0u8; 32];
    private_key.copy_from_slice(&key);
    
    Ok(private_key)
}

fn encode_waves_address(public_key: &[u8]) -> HawalaResult<String> {
    // Waves address format:
    // Version (1 byte) + ChainId (1 byte) + hash(hash(publicKey))[0:20] + checksum[0:4]
    
    let mut hasher = Blake2b512::new();
    hasher.update(public_key);
    let hash1 = hasher.finalize();
    
    // Keccak256 of Blake2b hash (first 32 bytes)
    use sha3::{Keccak256, Digest as Sha3Digest};
    let mut keccak = Keccak256::new();
    keccak.update(&hash1[..32]);
    let hash2 = keccak.finalize();
    
    // Build address
    let mut address_data = Vec::new();
    address_data.push(0x01); // version
    address_data.push(WAVES_CHAIN_ID); // chain ID
    address_data.extend_from_slice(&hash2[..20]); // first 20 bytes of hash
    
    // Checksum: keccak256(address_data)[0:4]
    let mut checksum_hasher = Keccak256::new();
    checksum_hasher.update(&address_data);
    let checksum = checksum_hasher.finalize();
    address_data.extend_from_slice(&checksum[..4]);
    
    Ok(bs58::encode(address_data).into_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_waves_key_derivation() {
        let seed = [0u8; 64];
        let keys = derive_waves_keys(&seed).unwrap();
        
        assert!(!keys.private_hex.is_empty());
        assert!(keys.address.starts_with('3')); // Waves mainnet addresses start with 3
    }
}
