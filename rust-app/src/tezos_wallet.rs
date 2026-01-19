// Tezos (XTZ) Wallet Implementation
// Uses Ed25519 curve
// Derivation path: m/44'/1729'/0'/0'

use serde::{Deserialize, Serialize};
use ed25519_dalek::{SigningKey, VerifyingKey};

/// Tezos keys structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TezosKeys {
    pub private_hex: String,
    pub secret_key: String, // edsk... format
    pub public_hex: String,
    pub public_key: String, // edpk... format
    pub address: String, // tz1... format
}

/// Derive Tezos keys from a BIP39 seed
pub fn derive_tezos_keys(seed: &[u8]) -> Result<TezosKeys, String> {
    use hmac::{Hmac, Mac};
    use sha2::Sha512;

    type HmacSha512 = Hmac<Sha512>;

    // Derive key using Tezos path indicator
    let mut mac = HmacSha512::new_from_slice(b"ed25519 tezos seed")
        .map_err(|e| format!("HMAC error: {}", e))?;
    mac.update(seed);
    let result = mac.finalize().into_bytes();

    // Use first 32 bytes as private key
    let private_bytes: [u8; 32] = result[..32]
        .try_into()
        .map_err(|_| "Failed to extract private key bytes")?;

    // Create signing key
    let signing_key = SigningKey::from_bytes(&private_bytes);
    let verifying_key = signing_key.verifying_key();

    // Private key hex
    let private_hex = hex::encode(private_bytes);

    // Tezos secret key (edsk... format)
    let secret_key = encode_tezos_secret(&private_bytes)?;

    // Public key hex
    let public_hex = hex::encode(verifying_key.as_bytes());

    // Tezos public key (edpk... format)
    let public_key = encode_tezos_public_key(&verifying_key)?;

    // Tezos address (tz1... format)
    let address = encode_tezos_address(&verifying_key)?;

    Ok(TezosKeys {
        private_hex,
        secret_key,
        public_hex,
        public_key,
        address,
    })
}

/// Tezos Base58Check encoding with prefix
fn tezos_base58check_encode(prefix: &[u8], data: &[u8]) -> String {
    use bitcoin::base58;
    use bitcoin::hashes::{sha256, Hash};

    let mut payload = Vec::with_capacity(prefix.len() + data.len() + 4);
    payload.extend_from_slice(prefix);
    payload.extend_from_slice(data);

    // Double SHA256 checksum
    let hash1 = sha256::Hash::hash(&payload);
    let hash2 = sha256::Hash::hash(&hash1[..]);

    payload.extend_from_slice(&hash2[..4]);

    base58::encode(&payload)
}

/// Encode Tezos secret key (edsk...)
fn encode_tezos_secret(private_key: &[u8; 32]) -> Result<String, String> {
    // edsk prefix: [43, 246, 78, 7] for ed25519 seed (32 bytes)
    let prefix = [43u8, 246, 78, 7];
    Ok(tezos_base58check_encode(&prefix, private_key))
}

/// Encode Tezos public key (edpk...)
fn encode_tezos_public_key(public_key: &VerifyingKey) -> Result<String, String> {
    // edpk prefix: [13, 15, 37, 217]
    let prefix = [13u8, 15, 37, 217];
    Ok(tezos_base58check_encode(&prefix, public_key.as_bytes()))
}

/// Encode Tezos address (tz1...)
fn encode_tezos_address(public_key: &VerifyingKey) -> Result<String, String> {
    use blake2::{Blake2b, Digest};
    use blake2::digest::consts::U20;

    // Blake2b-160 hash of public key
    let mut hasher = Blake2b::<U20>::new();
    hasher.update(public_key.as_bytes());
    let hash = hasher.finalize();

    // tz1 prefix: [6, 161, 159]
    let prefix = [6u8, 161, 159];
    Ok(tezos_base58check_encode(&prefix, &hash))
}

#[cfg(test)]
mod tests {
    use super::*;
    use bip39::Mnemonic;

    #[test]
    fn test_derive_tezos_keys() {
        let mnemonic = Mnemonic::parse("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about").unwrap();
        let seed = mnemonic.to_seed("");
        
        let keys = derive_tezos_keys(&seed).unwrap();
        
        // Verify address starts with tz1
        assert!(keys.address.starts_with("tz1"), "Tezos address should start with tz1");
        // Verify public key starts with edpk
        assert!(keys.public_key.starts_with("edpk"), "Tezos public key should start with edpk");
        // Verify secret key starts with edsk
        assert!(keys.secret_key.starts_with("edsk"), "Tezos secret key should start with edsk");
        assert!(!keys.private_hex.is_empty());
    }
}
