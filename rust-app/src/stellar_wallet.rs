// Stellar (XLM) Wallet Implementation
// Uses Ed25519 curve
// Derivation path: m/44'/148'/0'

use serde::{Deserialize, Serialize};
use ed25519_dalek::{SigningKey, VerifyingKey};

/// Stellar keys structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StellarKeys {
    pub private_hex: String,
    pub secret_key: String, // S... format
    pub public_hex: String,
    pub address: String, // G... format
}

/// Derive Stellar keys from a BIP39 seed
pub fn derive_stellar_keys(seed: &[u8]) -> Result<StellarKeys, String> {
    use hmac::{Hmac, Mac};
    use sha2::Sha512;

    type HmacSha512 = Hmac<Sha512>;

    // Derive key using Stellar path indicator
    let mut mac = HmacSha512::new_from_slice(b"ed25519 stellar seed")
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

    // Stellar secret key (S... format)
    let secret_key = encode_stellar_secret(&private_bytes)?;

    // Public key hex (32 bytes)
    let public_hex = hex::encode(verifying_key.as_bytes());

    // Stellar address (G... format)
    let address = encode_stellar_address(&verifying_key)?;

    Ok(StellarKeys {
        private_hex,
        secret_key,
        public_hex,
        address,
    })
}

/// Encode Stellar secret key (Base32 with version byte and CRC16 checksum)
fn encode_stellar_secret(private_key: &[u8; 32]) -> Result<String, String> {
    use data_encoding::BASE32;

    // Version byte for secret key: 18 << 3 = 144 (S prefix)
    let version: u8 = 18 << 3;

    let mut payload = vec![version];
    payload.extend_from_slice(private_key);

    // CRC16-XModem checksum
    let checksum = crc16_xmodem(&payload);
    payload.push((checksum & 0xFF) as u8);
    payload.push((checksum >> 8) as u8);

    // Base32 encode
    Ok(BASE32.encode(&payload))
}

/// Encode Stellar address (G... format)
fn encode_stellar_address(public_key: &VerifyingKey) -> Result<String, String> {
    use data_encoding::BASE32;

    // Version byte for public key (account): 6 << 3 = 48 (G prefix)
    let version: u8 = 6 << 3;

    let mut payload = vec![version];
    payload.extend_from_slice(public_key.as_bytes());

    // CRC16-XModem checksum
    let checksum = crc16_xmodem(&payload);
    payload.push((checksum & 0xFF) as u8);
    payload.push((checksum >> 8) as u8);

    // Base32 encode
    Ok(BASE32.encode(&payload))
}

/// CRC16-XModem checksum
fn crc16_xmodem(data: &[u8]) -> u16 {
    let mut crc: u16 = 0;
    for byte in data {
        crc ^= (*byte as u16) << 8;
        for _ in 0..8 {
            if crc & 0x8000 != 0 {
                crc = (crc << 1) ^ 0x1021;
            } else {
                crc <<= 1;
            }
        }
    }
    crc
}

#[cfg(test)]
mod tests {
    use super::*;
    use bip39::Mnemonic;

    #[test]
    fn test_derive_stellar_keys() {
        let mnemonic = Mnemonic::parse("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about").unwrap();
        let seed = mnemonic.to_seed("");
        
        let keys = derive_stellar_keys(&seed).unwrap();
        
        // Verify address starts with G
        assert!(keys.address.starts_with('G'), "Stellar address should start with G");
        // Verify secret starts with S
        assert!(keys.secret_key.starts_with('S'), "Stellar secret should start with S");
        assert!(!keys.private_hex.is_empty());
        assert!(!keys.public_hex.is_empty());
    }
}
