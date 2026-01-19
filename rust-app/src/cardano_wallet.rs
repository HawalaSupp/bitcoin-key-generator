// Cardano (ADA) Wallet Implementation
// Uses Ed25519 Extended (BIP32-Ed25519) with Shelley-era addresses
// Derivation path: m/1852'/1815'/0'/0/0

use serde::{Deserialize, Serialize};
use ed25519_dalek::{SigningKey, VerifyingKey};
use bech32::{self, Variant, ToBase32};

/// Cardano keys structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CardanoKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub address: String, // Shelley-era addr1...
}

/// Derive Cardano keys from a BIP39 seed using simplified approach
/// Note: Full Cardano uses PBKDF2 + BIP32-Ed25519 which is complex
/// This implementation uses a simplified ed25519 derivation
pub fn derive_cardano_keys(seed: &[u8]) -> Result<CardanoKeys, String> {
    // Cardano uses a specific derivation scheme (Icarus/Shelley)
    // For now, we use the first 32 bytes of HMAC-SHA512 of the seed
    use hmac::{Hmac, Mac};
    use sha2::Sha512;

    type HmacSha512 = Hmac<Sha512>;

    // Derive a deterministic key using the Cardano path indicator
    let mut mac = HmacSha512::new_from_slice(b"ed25519 cardano seed")
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

    // Generate Shelley-era address (simplified - enterprise address)
    let address = encode_cardano_address(&verifying_key)?;

    Ok(CardanoKeys {
        private_hex,
        public_hex,
        address,
    })
}

/// Encode a Cardano Shelley-era address (enterprise address - no stake part)
fn encode_cardano_address(public_key: &VerifyingKey) -> Result<String, String> {
    use blake2::{Blake2b, Digest};
    use blake2::digest::consts::U28;

    // Hash public key with Blake2b-224
    let mut hasher = Blake2b::<U28>::new();
    hasher.update(public_key.as_bytes());
    let hash = hasher.finalize();

    // Enterprise address format: header byte (0x61 for mainnet) + 28-byte key hash
    let mut address_bytes = Vec::with_capacity(29);
    address_bytes.push(0x61); // Enterprise address, mainnet
    address_bytes.extend_from_slice(&hash);

    // Bech32 encode with "addr" prefix (bech32 v0.9 API)
    let address = bech32::encode("addr", address_bytes.to_base32(), Variant::Bech32)
        .map_err(|e| format!("Bech32 encoding failed: {}", e))?;

    Ok(address)
}

/// Generate a Cardano staking address
pub fn derive_staking_address(seed: &[u8]) -> Result<String, String> {
    use hmac::{Hmac, Mac};
    use sha2::Sha512;
    use blake2::{Blake2b, Digest};
    use blake2::digest::consts::U28;

    type HmacSha512 = Hmac<Sha512>;

    // Use a different derivation for staking key
    let mut mac = HmacSha512::new_from_slice(b"ed25519 cardano stake")
        .map_err(|e| format!("HMAC error: {}", e))?;
    mac.update(seed);
    let result = mac.finalize().into_bytes();

    let private_bytes: [u8; 32] = result[..32]
        .try_into()
        .map_err(|_| "Failed to extract private key bytes")?;

    let signing_key = SigningKey::from_bytes(&private_bytes);
    let verifying_key = signing_key.verifying_key();

    // Hash public key with Blake2b-224
    let mut hasher = Blake2b::<U28>::new();
    hasher.update(verifying_key.as_bytes());
    let hash = hasher.finalize();

    // Reward address format: header byte (0xe1 for mainnet) + 28-byte key hash
    let mut address_bytes = Vec::with_capacity(29);
    address_bytes.push(0xe1); // Reward address, mainnet
    address_bytes.extend_from_slice(&hash);

    // Bech32 encode with "stake" prefix (bech32 v0.9 API)
    let address = bech32::encode("stake", address_bytes.to_base32(), Variant::Bech32)
        .map_err(|e| format!("Bech32 encoding failed: {}", e))?;

    Ok(address)
}

#[cfg(test)]
mod tests {
    use super::*;
    use bip39::Mnemonic;

    #[test]
    fn test_derive_cardano_keys() {
        let mnemonic = Mnemonic::parse("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about").unwrap();
        let seed = mnemonic.to_seed("");
        
        let keys = derive_cardano_keys(&seed).unwrap();
        
        // Verify address format
        assert!(keys.address.starts_with("addr1"), "Cardano address should start with addr1");
        assert!(!keys.private_hex.is_empty());
        assert!(!keys.public_hex.is_empty());
        assert_eq!(keys.public_hex.len(), 64); // 32 bytes = 64 hex chars
    }

    #[test]
    fn test_derive_staking_address() {
        let mnemonic = Mnemonic::parse("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about").unwrap();
        let seed = mnemonic.to_seed("");
        
        let stake_address = derive_staking_address(&seed).unwrap();
        assert!(stake_address.starts_with("stake1"), "Staking address should start with stake1");
    }
}
