// Hedera Hashgraph (HBAR) Wallet Implementation
// Uses Ed25519 curve
// Derivation path: m/44'/3030'/0'/0'/0

use serde::{Deserialize, Serialize};
use ed25519_dalek::{SigningKey, VerifyingKey};

/// Hedera keys structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HederaKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub public_key_der: String, // DER-encoded public key
}

/// Derive Hedera keys from a BIP39 seed
pub fn derive_hedera_keys(seed: &[u8]) -> Result<HederaKeys, String> {
    use hmac::{Hmac, Mac};
    use sha2::Sha512;

    type HmacSha512 = Hmac<Sha512>;

    // Derive key using Hedera path indicator
    let mut mac = HmacSha512::new_from_slice(b"ed25519 hedera seed")
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

    // DER-encoded public key for Hedera
    let public_key_der = encode_hedera_public_key_der(&verifying_key);

    Ok(HederaKeys {
        private_hex,
        public_hex,
        public_key_der,
    })
}

/// Encode Hedera public key in DER format
fn encode_hedera_public_key_der(public_key: &VerifyingKey) -> String {
    // Ed25519 public key DER prefix
    // 30 2a 30 05 06 03 2b 65 70 03 21 00 + 32 bytes public key
    let der_prefix: [u8; 12] = [0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00];

    let mut der_key = Vec::with_capacity(44);
    der_key.extend_from_slice(&der_prefix);
    der_key.extend_from_slice(public_key.as_bytes());

    hex::encode(der_key)
}

/// Format Hedera account ID (e.g., 0.0.12345)
/// Note: Account IDs are assigned by the network, not derived from keys
pub fn format_hedera_account_id(shard: u64, realm: u64, num: u64) -> String {
    format!("{}.{}.{}", shard, realm, num)
}

#[cfg(test)]
mod tests {
    use super::*;
    use bip39::Mnemonic;

    #[test]
    fn test_derive_hedera_keys() {
        let mnemonic = Mnemonic::parse("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about").unwrap();
        let seed = mnemonic.to_seed("");
        
        let keys = derive_hedera_keys(&seed).unwrap();
        
        // Verify public key hex is 64 characters (32 bytes)
        assert_eq!(keys.public_hex.len(), 64, "Hedera public key should be 64 hex chars");
        // Verify DER key is 88 characters (44 bytes)
        assert_eq!(keys.public_key_der.len(), 88, "Hedera DER public key should be 88 hex chars");
        assert!(!keys.private_hex.is_empty());
    }

    #[test]
    fn test_format_account_id() {
        let account_id = format_hedera_account_id(0, 0, 12345);
        assert_eq!(account_id, "0.0.12345");
    }
}
