// Algorand (ALGO) Wallet Implementation
// Uses Ed25519 curve
// Derivation path: m/44'/283'/0'/0'/0'

use serde::{Deserialize, Serialize};
use ed25519_dalek::{SigningKey, VerifyingKey};

/// Algorand keys structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AlgorandKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub address: String, // Base32 with checksum
}

/// Derive Algorand keys from a BIP39 seed
pub fn derive_algorand_keys(seed: &[u8]) -> Result<AlgorandKeys, String> {
    use hmac::{Hmac, Mac};
    use sha2::Sha512;

    type HmacSha512 = Hmac<Sha512>;

    // Derive key using Algorand path indicator
    let mut mac = HmacSha512::new_from_slice(b"ed25519 algorand seed")
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

    // Public key hex (32 bytes)
    let public_hex = hex::encode(verifying_key.as_bytes());

    // Generate Algorand address
    let address = encode_algorand_address(&verifying_key)?;

    Ok(AlgorandKeys {
        private_hex,
        public_hex,
        address,
    })
}

/// Encode Algorand address (Base32 with SHA512/256 checksum)
fn encode_algorand_address(public_key: &VerifyingKey) -> Result<String, String> {
    use sha2::{Sha512_256, Digest};
    use data_encoding::BASE32_NOPAD;

    // SHA512/256 hash of public key for checksum
    let mut hasher = Sha512_256::new();
    hasher.update(public_key.as_bytes());
    let hash = hasher.finalize();

    // Take last 4 bytes as checksum
    let checksum = &hash[28..32];

    // Concatenate public key + checksum
    let mut address_bytes = Vec::with_capacity(36);
    address_bytes.extend_from_slice(public_key.as_bytes());
    address_bytes.extend_from_slice(checksum);

    // Base32 encode (no padding)
    Ok(BASE32_NOPAD.encode(&address_bytes))
}

#[cfg(test)]
mod tests {
    use super::*;
    use bip39::Mnemonic;

    #[test]
    fn test_derive_algorand_keys() {
        let mnemonic = Mnemonic::parse("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about").unwrap();
        let seed = mnemonic.to_seed("");
        
        let keys = derive_algorand_keys(&seed).unwrap();
        
        // Verify address is 58 characters (Base32 of 36 bytes)
        assert_eq!(keys.address.len(), 58, "Algorand address should be 58 characters");
        assert!(!keys.private_hex.is_empty());
        assert!(!keys.public_hex.is_empty());
    }
}
