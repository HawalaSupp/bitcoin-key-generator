//! Ed25519 Curve Implementation
//!
//! Used by: Solana, Stellar, Cardano, TON, Near, Aptos, Sui, Algorand, etc.
//!
//! Features:
//! - EdDSA signing and verification (RFC 8032)
//! - Ed25519-SHA512 variant (Cardano)
//! - SLIP-0010 key derivation
//! - X25519 key exchange (via Curve25519)

use super::{CurveError, EllipticCurve, KeyDerivation};
use ed25519_dalek::{SigningKey, VerifyingKey, Signature, Signer, Verifier};
use sha2::{Sha512, Digest};
use hmac::{Hmac, Mac};

type HmacSha512 = Hmac<sha2::Sha512>;

/// Ed25519 curve implementation
pub struct Ed25519Curve;

impl EllipticCurve for Ed25519Curve {
    type PrivateKey = [u8; 32];
    type PublicKey = [u8; 32];
    type Signature = [u8; 64];
    
    fn generate_keypair(seed: &[u8]) -> Result<(Self::PrivateKey, Self::PublicKey), CurveError> {
        if seed.len() < 32 {
            return Err(CurveError::InvalidSeed(
                format!("Seed must be at least 32 bytes, got {}", seed.len())
            ));
        }
        
        let mut sk_bytes = [0u8; 32];
        sk_bytes.copy_from_slice(&seed[..32]);
        
        let signing_key = SigningKey::from_bytes(&sk_bytes);
        let verifying_key = signing_key.verifying_key();
        
        Ok((sk_bytes, verifying_key.to_bytes()))
    }
    
    fn public_key_from_private(private_key: &[u8]) -> Result<Self::PublicKey, CurveError> {
        if private_key.len() != 32 {
            return Err(CurveError::InvalidPrivateKey(
                format!("Private key must be 32 bytes, got {}", private_key.len())
            ));
        }
        
        let mut sk_bytes = [0u8; 32];
        sk_bytes.copy_from_slice(private_key);
        
        let signing_key = SigningKey::from_bytes(&sk_bytes);
        let verifying_key = signing_key.verifying_key();
        
        Ok(verifying_key.to_bytes())
    }
    
    fn sign(private_key: &[u8], message: &[u8]) -> Result<Self::Signature, CurveError> {
        if private_key.len() != 32 {
            return Err(CurveError::InvalidPrivateKey(
                format!("Private key must be 32 bytes, got {}", private_key.len())
            ));
        }
        
        let mut sk_bytes = [0u8; 32];
        sk_bytes.copy_from_slice(private_key);
        
        let signing_key = SigningKey::from_bytes(&sk_bytes);
        let signature = signing_key.sign(message);
        
        Ok(signature.to_bytes())
    }
    
    fn verify(public_key: &[u8], message: &[u8], signature: &[u8]) -> Result<bool, CurveError> {
        if public_key.len() != 32 {
            return Err(CurveError::InvalidPublicKey(
                format!("Public key must be 32 bytes, got {}", public_key.len())
            ));
        }
        if signature.len() != 64 {
            return Err(CurveError::InvalidSignature(
                format!("Signature must be 64 bytes, got {}", signature.len())
            ));
        }
        
        let mut pk_bytes = [0u8; 32];
        pk_bytes.copy_from_slice(public_key);
        
        let verifying_key = VerifyingKey::from_bytes(&pk_bytes)
            .map_err(|e| CurveError::InvalidPublicKey(e.to_string()))?;
        
        let mut sig_bytes = [0u8; 64];
        sig_bytes.copy_from_slice(signature);
        
        let sig = Signature::from_bytes(&sig_bytes);
        
        Ok(verifying_key.verify(message, &sig).is_ok())
    }
}

impl KeyDerivation for Ed25519Curve {
    fn derive_child(
        parent_private: &[u8],
        parent_chain_code: &[u8],
        index: u32,
        hardened: bool,
    ) -> Result<([u8; 32], [u8; 32]), CurveError> {
        // Ed25519 only supports hardened derivation (SLIP-0010)
        if !hardened {
            return Err(CurveError::DerivationFailed(
                "Ed25519 only supports hardened derivation".into()
            ));
        }
        
        if parent_private.len() != 32 {
            return Err(CurveError::InvalidPrivateKey("Parent key must be 32 bytes".into()));
        }
        if parent_chain_code.len() != 32 {
            return Err(CurveError::DerivationFailed("Chain code must be 32 bytes".into()));
        }
        
        let actual_index = index | 0x80000000; // Always hardened
        
        let mut mac = HmacSha512::new_from_slice(parent_chain_code)
            .map_err(|e| CurveError::DerivationFailed(e.to_string()))?;
        
        // SLIP-0010: 0x00 || private_key || index
        mac.update(&[0x00]);
        mac.update(parent_private);
        mac.update(&actual_index.to_be_bytes());
        
        let result = mac.finalize().into_bytes();
        
        let (child_key, child_chain) = result.split_at(32);
        
        let mut child_key_arr = [0u8; 32];
        child_key_arr.copy_from_slice(child_key);
        let mut child_chain_arr = [0u8; 32];
        child_chain_arr.copy_from_slice(child_chain);
        
        Ok((child_key_arr, child_chain_arr))
    }
    
    fn derive_path(seed: &[u8], path: &str) -> Result<(Vec<u8>, Vec<u8>), CurveError> {
        // Parse path like "m/44'/501'/0'/0'"
        let parts: Vec<&str> = path.split('/').collect();
        
        if parts.is_empty() || parts[0] != "m" {
            return Err(CurveError::DerivationFailed("Path must start with 'm'".into()));
        }
        
        // Derive master key from seed using SLIP-0010
        let mut mac = HmacSha512::new_from_slice(b"ed25519 seed")
            .map_err(|e| CurveError::DerivationFailed(e.to_string()))?;
        mac.update(seed);
        let result = mac.finalize().into_bytes();
        
        let (master_key, master_chain_code) = result.split_at(32);
        let mut current_key = [0u8; 32];
        current_key.copy_from_slice(master_key);
        let mut current_chain_code = [0u8; 32];
        current_chain_code.copy_from_slice(master_chain_code);
        
        // Derive each level (all hardened for ed25519)
        for part in parts.iter().skip(1) {
            let index_str = part.trim_end_matches('\'').trim_end_matches('h');
            let index: u32 = index_str.parse()
                .map_err(|_| CurveError::DerivationFailed(format!("Invalid index: {}", part)))?;
            
            // Ed25519 always uses hardened derivation
            let (new_key, new_chain) = Self::derive_child(
                &current_key,
                &current_chain_code,
                index,
                true,
            )?;
            
            current_key = new_key;
            current_chain_code = new_chain;
        }
        
        // Get public key
        let public_key = Self::public_key_from_private(&current_key)?;
        
        Ok((current_key.to_vec(), public_key.to_vec()))
    }
}

// MARK: - Helper Functions

impl Ed25519Curve {
    /// Get the expanded secret key (64 bytes) for advanced use cases
    pub fn expand_secret_key(private_key: &[u8]) -> Result<[u8; 64], CurveError> {
        if private_key.len() != 32 {
            return Err(CurveError::InvalidPrivateKey(
                format!("Private key must be 32 bytes, got {}", private_key.len())
            ));
        }
        
        let mut hasher = Sha512::new();
        hasher.update(private_key);
        let hash: [u8; 64] = hasher.finalize().into();
        
        // Clamp the lower 32 bytes (as per Ed25519 spec)
        let mut expanded = hash;
        expanded[0] &= 248;
        expanded[31] &= 127;
        expanded[31] |= 64;
        
        Ok(expanded)
    }
    
    /// Sign with pre-hashed message (for Cardano-style signing)
    pub fn sign_prehashed(private_key: &[u8], message_hash: &[u8; 32]) -> Result<[u8; 64], CurveError> {
        // For standard Ed25519, we just sign the hash as a message
        Self::sign(private_key, message_hash)
    }
    
    /// Derive Solana address from public key (Base58)
    pub fn to_solana_address(public_key: &[u8; 32]) -> String {
        bs58::encode(public_key).into_string()
    }
    
    /// Derive keypair from Solana-style derivation
    /// Solana uses simple seed -> keypair without BIP-32/SLIP-0010
    pub fn solana_keypair(seed: &[u8]) -> Result<([u8; 32], [u8; 32]), CurveError> {
        if seed.len() < 32 {
            return Err(CurveError::InvalidSeed(
                format!("Seed must be at least 32 bytes, got {}", seed.len())
            ));
        }
        
        // For Solana, the seed is used directly as the private key
        let mut private_key = [0u8; 32];
        private_key.copy_from_slice(&seed[..32]);
        
        let public_key = Self::public_key_from_private(&private_key)?;
        
        Ok((private_key, public_key))
    }
    
    /// Convert private key to Solana keypair format (64 bytes = secret + public)
    pub fn to_solana_keypair(private_key: &[u8; 32]) -> Result<[u8; 64], CurveError> {
        let public_key = Self::public_key_from_private(private_key)?;
        
        let mut keypair = [0u8; 64];
        keypair[..32].copy_from_slice(private_key);
        keypair[32..].copy_from_slice(&public_key);
        
        Ok(keypair)
    }
    
    /// Derive Stellar address (with version byte and checksum)
    pub fn to_stellar_address(public_key: &[u8; 32]) -> String {
        // Stellar uses a custom base32 encoding with CRC16 checksum
        // Version byte 0x30 (48) for public keys -> 'G' prefix
        let version_byte = 0x30u8; // Account ID
        
        let mut payload = [0u8; 33];
        payload[0] = version_byte;
        payload[1..].copy_from_slice(public_key);
        
        // Calculate CRC16-XModem checksum
        let checksum = crc16_xmodem(&payload);
        
        let mut full_payload = [0u8; 35];
        full_payload[..33].copy_from_slice(&payload);
        full_payload[33..].copy_from_slice(&checksum.to_le_bytes());
        
        // Stellar uses RFC 4648 base32
        base32::encode(base32::Alphabet::Rfc4648 { padding: false }, &full_payload)
    }
}

/// CRC16-XModem for Stellar addresses
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

// MARK: - Tests

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_ed25519_generate_keypair() {
        let seed = [42u8; 32];
        let (sk, pk) = Ed25519Curve::generate_keypair(&seed).unwrap();
        
        assert_eq!(sk.len(), 32);
        assert_eq!(pk.len(), 32);
    }
    
    #[test]
    fn test_ed25519_sign_verify() {
        let seed = [42u8; 32];
        let (sk, pk) = Ed25519Curve::generate_keypair(&seed).unwrap();
        
        let message = b"Hello, Ed25519!";
        let signature = Ed25519Curve::sign(&sk, message).unwrap();
        
        assert_eq!(signature.len(), 64);
        
        let valid = Ed25519Curve::verify(&pk, message, &signature).unwrap();
        assert!(valid);
        
        // Wrong message should fail
        let wrong_msg = b"Wrong message";
        let valid = Ed25519Curve::verify(&pk, wrong_msg, &signature).unwrap();
        assert!(!valid);
    }
    
    #[test]
    fn test_ed25519_derive_path() {
        let seed = hex::decode(
            "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        ).unwrap();
        
        // Solana derivation path
        let (private_key, public_key) = Ed25519Curve::derive_path(&seed, "m/44'/501'/0'/0'").unwrap();
        
        assert_eq!(private_key.len(), 32);
        assert_eq!(public_key.len(), 32);
    }
    
    #[test]
    fn test_ed25519_solana_address() {
        let seed = [42u8; 32];
        let (_, pk) = Ed25519Curve::generate_keypair(&seed).unwrap();
        
        let address = Ed25519Curve::to_solana_address(&pk);
        
        // Should be a valid Base58 string
        assert!(!address.is_empty());
        assert!(bs58::decode(&address).into_vec().is_ok());
    }
    
    #[test]
    fn test_ed25519_solana_keypair_format() {
        let seed = [42u8; 32];
        let (sk, pk) = Ed25519Curve::generate_keypair(&seed).unwrap();
        
        let keypair = Ed25519Curve::to_solana_keypair(&sk).unwrap();
        
        assert_eq!(keypair.len(), 64);
        assert_eq!(&keypair[..32], &sk);
        assert_eq!(&keypair[32..], &pk);
    }
    
    #[test]
    fn test_ed25519_stellar_address() {
        let seed = [42u8; 32];
        let (_, pk) = Ed25519Curve::generate_keypair(&seed).unwrap();
        
        let address = Ed25519Curve::to_stellar_address(&pk);
        
        // Should start with 'G' for account IDs
        assert!(address.starts_with('G'));
        assert_eq!(address.len(), 56);
    }
    
    #[test]
    fn test_ed25519_consistency() {
        // Same seed should produce same keys
        let seed = [1u8; 32];
        
        let (sk1, pk1) = Ed25519Curve::generate_keypair(&seed).unwrap();
        let (sk2, pk2) = Ed25519Curve::generate_keypair(&seed).unwrap();
        
        assert_eq!(sk1, sk2);
        assert_eq!(pk1, pk2);
    }
}
