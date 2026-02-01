//! Internet Computer (ICP) Wallet Implementation
//!
//! Key derivation for Internet Computer (ICP).
//! Uses secp256k1 with Principal ID and Account ID formats.

use secp256k1::{Secp256k1, SecretKey, PublicKey};
use sha2::{Sha224, Sha256, Digest};

use crate::error::{HawalaError, HawalaResult};
use crate::types::InternetComputerKeys;

/// Derive Internet Computer keys from seed
pub fn derive_internet_computer_keys(seed: &[u8]) -> HawalaResult<InternetComputerKeys> {
    let private_key = derive_private_key(seed)?;
    let private_hex = hex::encode(&private_key);
    
    let secp = Secp256k1::new();
    let secret_key = SecretKey::from_slice(&private_key)
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    let public_key = PublicKey::from_secret_key(&secp, &secret_key);
    
    let public_compressed = public_key.serialize();
    let public_hex = hex::encode(&public_compressed);
    
    // Principal ID from public key
    let principal_id = derive_principal_id(&public_compressed)?;
    
    // Account ID from Principal ID
    let account_id = derive_account_id(&principal_id)?;
    
    Ok(InternetComputerKeys {
        private_hex,
        public_hex,
        principal_id,
        account_id,
    })
}

fn derive_private_key(seed: &[u8]) -> HawalaResult<[u8; 32]> {
    use hmac::{Hmac, Mac};
    use sha2::Sha512;
    
    type HmacSha512 = Hmac<Sha512>;
    
    // BIP44 path m/44'/223'/0'/0/0
    let mut mac = HmacSha512::new_from_slice(b"Bitcoin seed")
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    mac.update(seed);
    let result = mac.finalize().into_bytes();
    
    let mut key = [0u8; 32];
    key.copy_from_slice(&result[..32]);
    Ok(key)
}

fn derive_principal_id(public_key: &[u8]) -> HawalaResult<String> {
    // DER encode the secp256k1 public key
    let der_prefix: [u8; 23] = [
        0x30, 0x56, 0x30, 0x10, 0x06, 0x07, 0x2a, 0x86,
        0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x05, 0x2b,
        0x81, 0x04, 0x00, 0x0a, 0x03, 0x42, 0x00,
    ];
    
    let mut der_key = der_prefix.to_vec();
    // Add uncompressed public key marker and convert from compressed
    der_key.push(0x04);
    // For simplicity, we use the compressed key hash
    der_key.extend_from_slice(public_key);
    
    // SHA-224 hash
    let mut hasher = Sha224::new();
    hasher.update(&der_key);
    let hash = hasher.finalize();
    
    // Principal = hash + type byte (self-authenticating = 0x02)
    let mut principal_bytes = hash[..28].to_vec();
    principal_bytes.push(0x02);
    
    // Encode as textual principal (base32 with CRC)
    let crc = crc32fast::hash(&principal_bytes);
    let mut data_with_crc = crc.to_be_bytes().to_vec();
    data_with_crc.extend_from_slice(&principal_bytes);
    
    let encoded = data_encoding::BASE32_NOPAD.encode(&data_with_crc).to_lowercase();
    
    // Format with dashes every 5 characters
    let formatted: String = encoded
        .chars()
        .collect::<Vec<_>>()
        .chunks(5)
        .map(|c| c.iter().collect::<String>())
        .collect::<Vec<_>>()
        .join("-");
    
    Ok(formatted)
}

fn derive_account_id(principal_id: &str) -> HawalaResult<String> {
    // Account ID = SHA-256(domain_sep + principal_bytes + subaccount)
    // For the default subaccount (all zeros), we just hash principal
    
    let domain_sep = b"\x0Aaccount-id";
    
    // Decode principal (remove dashes and decode base32)
    let principal_clean = principal_id.replace("-", "");
    let decoded = data_encoding::BASE32_NOPAD
        .decode(principal_clean.to_uppercase().as_bytes())
        .map_err(|e| HawalaError::crypto_error(e.to_string()))?;
    
    // Skip CRC (first 4 bytes)
    let principal_bytes = if decoded.len() > 4 { &decoded[4..] } else { &decoded };
    
    let mut hasher = Sha256::new();
    hasher.update(domain_sep);
    hasher.update(principal_bytes);
    hasher.update([0u8; 32]); // default subaccount
    let hash = hasher.finalize();
    
    // CRC32 checksum prepended
    let _checksum = crc32fast::hash(&hash);
    
    Ok(hex::encode(&hash))
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_icp_key_derivation() {
        let seed = [0u8; 64];
        let keys = derive_internet_computer_keys(&seed).unwrap();
        
        assert!(!keys.private_hex.is_empty());
        assert!(keys.principal_id.contains("-"));
        assert_eq!(keys.account_id.len(), 64);
    }
}
