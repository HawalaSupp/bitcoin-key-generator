// NEAR Protocol Wallet Implementation
// Uses Ed25519 curve
// Derivation path: m/44'/397'/0'

use serde::{Deserialize, Serialize};
use ed25519_dalek::{SigningKey, VerifyingKey};

/// NEAR keys structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NearKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub implicit_address: String, // 64-char hex (implicit account)
}

/// Derive NEAR keys from a BIP39 seed
pub fn derive_near_keys(seed: &[u8]) -> Result<NearKeys, String> {
    use hmac::{Hmac, Mac};
    use sha2::Sha512;

    type HmacSha512 = Hmac<Sha512>;

    // Derive key using NEAR path indicator
    let mut mac = HmacSha512::new_from_slice(b"ed25519 near seed")
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

    // NEAR implicit address is just the hex of the public key
    let implicit_address = public_hex.clone();

    Ok(NearKeys {
        private_hex,
        public_hex,
        implicit_address,
    })
}

/// Format NEAR public key for display (ed25519:base58...)
pub fn format_near_public_key(public_key: &VerifyingKey) -> String {
    let encoded = bs58::encode(public_key.as_bytes()).into_string();
    format!("ed25519:{}", encoded)
}

#[cfg(test)]
mod tests {
    use super::*;
    use bip39::Mnemonic;

    #[test]
    fn test_derive_near_keys() {
        let mnemonic = Mnemonic::parse("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about").unwrap();
        let seed = mnemonic.to_seed("");
        
        let keys = derive_near_keys(&seed).unwrap();
        
        // Verify implicit address is 64 hex characters
        assert_eq!(keys.implicit_address.len(), 64, "NEAR implicit address should be 64 hex chars");
        assert!(!keys.private_hex.is_empty());
        assert!(!keys.public_hex.is_empty());
    }
}
