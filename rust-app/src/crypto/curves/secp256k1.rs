//! secp256k1 Curve Implementation
//!
//! Used by: Bitcoin, Ethereum, BNB Chain, Litecoin, Dogecoin, Tron, etc.
//!
//! Features:
//! - ECDSA signing and verification
//! - Recoverable signatures (for Ethereum)
//! - Compressed and uncompressed public keys
//! - ECDH key exchange
//! - BIP-32 key derivation

use super::{CurveError, EllipticCurve, RecoverableSignature, KeyExchange, KeyDerivation};
use bitcoin::secp256k1::{Secp256k1, SecretKey, PublicKey, Message, All};
use bitcoin::secp256k1::ecdsa::{Signature, RecoverableSignature as RecovSig, RecoveryId};
use sha2::{Sha256, Digest};
use hmac::{Hmac, Mac};

type HmacSha512 = Hmac<sha2::Sha512>;

/// secp256k1 curve implementation
pub struct Secp256k1Curve;

impl EllipticCurve for Secp256k1Curve {
    type PrivateKey = [u8; 32];
    type PublicKey = [u8; 33]; // Compressed
    type Signature = [u8; 64]; // r,s
    
    fn generate_keypair(seed: &[u8]) -> Result<(Self::PrivateKey, Self::PublicKey), CurveError> {
        if seed.len() < 32 {
            return Err(CurveError::InvalidSeed(
                format!("Seed must be at least 32 bytes, got {}", seed.len())
            ));
        }
        
        let secp = Secp256k1::new();
        
        // Use first 32 bytes as private key
        let mut sk_bytes = [0u8; 32];
        sk_bytes.copy_from_slice(&seed[..32]);
        
        let sk = SecretKey::from_slice(&sk_bytes)
            .map_err(|e| CurveError::InvalidPrivateKey(e.to_string()))?;
        
        let pk = PublicKey::from_secret_key(&secp, &sk);
        let pk_bytes = pk.serialize(); // Compressed
        
        Ok((sk_bytes, pk_bytes))
    }
    
    fn public_key_from_private(private_key: &[u8]) -> Result<Self::PublicKey, CurveError> {
        if private_key.len() != 32 {
            return Err(CurveError::InvalidPrivateKey(
                format!("Private key must be 32 bytes, got {}", private_key.len())
            ));
        }
        
        let secp = Secp256k1::new();
        let sk = SecretKey::from_slice(private_key)
            .map_err(|e| CurveError::InvalidPrivateKey(e.to_string()))?;
        
        let pk = PublicKey::from_secret_key(&secp, &sk);
        Ok(pk.serialize())
    }
    
    fn sign(private_key: &[u8], message: &[u8]) -> Result<Self::Signature, CurveError> {
        if private_key.len() != 32 {
            return Err(CurveError::InvalidPrivateKey(
                format!("Private key must be 32 bytes, got {}", private_key.len())
            ));
        }
        
        let secp = Secp256k1::new();
        let sk = SecretKey::from_slice(private_key)
            .map_err(|e| CurveError::InvalidPrivateKey(e.to_string()))?;
        
        // Hash message if not already 32 bytes
        let msg_hash = if message.len() == 32 {
            let mut arr = [0u8; 32];
            arr.copy_from_slice(message);
            arr
        } else {
            let mut hasher = Sha256::new();
            hasher.update(message);
            hasher.finalize().into()
        };
        
        let msg = Message::from_digest(msg_hash);
        let sig = secp.sign_ecdsa(&msg, &sk);
        
        let serialized = sig.serialize_compact();
        Ok(serialized)
    }
    
    fn verify(public_key: &[u8], message: &[u8], signature: &[u8]) -> Result<bool, CurveError> {
        if signature.len() != 64 {
            return Err(CurveError::InvalidSignature(
                format!("Signature must be 64 bytes, got {}", signature.len())
            ));
        }
        
        let secp = Secp256k1::new();
        
        let pk = PublicKey::from_slice(public_key)
            .map_err(|e| CurveError::InvalidPublicKey(e.to_string()))?;
        
        let sig = Signature::from_compact(signature)
            .map_err(|e| CurveError::InvalidSignature(e.to_string()))?;
        
        // Hash message if not already 32 bytes
        let msg_hash = if message.len() == 32 {
            let mut arr = [0u8; 32];
            arr.copy_from_slice(message);
            arr
        } else {
            let mut hasher = Sha256::new();
            hasher.update(message);
            hasher.finalize().into()
        };
        
        let msg = Message::from_digest(msg_hash);
        
        Ok(secp.verify_ecdsa(&msg, &sig, &pk).is_ok())
    }
}

impl RecoverableSignature for Secp256k1Curve {
    fn sign_recoverable(private_key: &[u8], message: &[u8]) -> Result<(Self::Signature, u8), CurveError> {
        if private_key.len() != 32 {
            return Err(CurveError::InvalidPrivateKey(
                format!("Private key must be 32 bytes, got {}", private_key.len())
            ));
        }
        
        let secp = Secp256k1::new();
        let sk = SecretKey::from_slice(private_key)
            .map_err(|e| CurveError::InvalidPrivateKey(e.to_string()))?;
        
        // Hash message if not already 32 bytes
        let msg_hash = if message.len() == 32 {
            let mut arr = [0u8; 32];
            arr.copy_from_slice(message);
            arr
        } else {
            let mut hasher = Sha256::new();
            hasher.update(message);
            hasher.finalize().into()
        };
        
        let msg = Message::from_digest(msg_hash);
        let sig = secp.sign_ecdsa_recoverable(&msg, &sk);
        
        let (recovery_id, serialized) = sig.serialize_compact();
        
        Ok((serialized, recovery_id.to_i32() as u8))
    }
    
    fn recover_public_key(message: &[u8], signature: &[u8], recovery_id: u8) -> Result<Self::PublicKey, CurveError> {
        if signature.len() != 64 {
            return Err(CurveError::InvalidSignature(
                format!("Signature must be 64 bytes, got {}", signature.len())
            ));
        }
        
        let secp = Secp256k1::new();
        
        let rec_id = RecoveryId::from_i32(recovery_id as i32)
            .map_err(|e| CurveError::InvalidSignature(format!("Invalid recovery ID: {}", e)))?;
        
        let sig = RecovSig::from_compact(signature, rec_id)
            .map_err(|e| CurveError::InvalidSignature(e.to_string()))?;
        
        // Hash message if not already 32 bytes
        let msg_hash = if message.len() == 32 {
            let mut arr = [0u8; 32];
            arr.copy_from_slice(message);
            arr
        } else {
            let mut hasher = Sha256::new();
            hasher.update(message);
            hasher.finalize().into()
        };
        
        let msg = Message::from_digest(msg_hash);
        
        let pk = secp.recover_ecdsa(&msg, &sig)
            .map_err(|e| CurveError::VerificationFailed(format!("Recovery failed: {}", e)))?;
        
        Ok(pk.serialize())
    }
}

impl KeyExchange for Secp256k1Curve {
    fn ecdh(private_key: &[u8], other_public_key: &[u8]) -> Result<[u8; 32], CurveError> {
        if private_key.len() != 32 {
            return Err(CurveError::InvalidPrivateKey(
                format!("Private key must be 32 bytes, got {}", private_key.len())
            ));
        }
        
        let sk = SecretKey::from_slice(private_key)
            .map_err(|e| CurveError::InvalidPrivateKey(e.to_string()))?;
        
        let pk = PublicKey::from_slice(other_public_key)
            .map_err(|e| CurveError::InvalidPublicKey(e.to_string()))?;
        
        // Perform ECDH: shared_secret = pk * sk
        let shared_point = bitcoin::secp256k1::ecdh::shared_secret_point(&pk, &sk);
        
        // Hash the x-coordinate
        let mut hasher = Sha256::new();
        hasher.update(&shared_point[..32]); // x-coordinate
        let result: [u8; 32] = hasher.finalize().into();
        
        Ok(result)
    }
}

impl KeyDerivation for Secp256k1Curve {
    fn derive_child(
        parent_private: &[u8],
        parent_chain_code: &[u8],
        index: u32,
        hardened: bool,
    ) -> Result<([u8; 32], [u8; 32]), CurveError> {
        if parent_private.len() != 32 {
            return Err(CurveError::InvalidPrivateKey("Parent key must be 32 bytes".into()));
        }
        if parent_chain_code.len() != 32 {
            return Err(CurveError::DerivationFailed("Chain code must be 32 bytes".into()));
        }
        
        let secp = Secp256k1::new();
        let parent_sk = SecretKey::from_slice(parent_private)
            .map_err(|e| CurveError::InvalidPrivateKey(e.to_string()))?;
        
        // Build HMAC input
        let mut mac = HmacSha512::new_from_slice(parent_chain_code)
            .map_err(|e| CurveError::DerivationFailed(e.to_string()))?;
        
        let actual_index = if hardened { index | 0x80000000 } else { index };
        
        if hardened {
            // Hardened: 0x00 || private_key || index
            mac.update(&[0x00]);
            mac.update(parent_private);
        } else {
            // Normal: public_key || index
            let parent_pk = PublicKey::from_secret_key(&secp, &parent_sk);
            mac.update(&parent_pk.serialize());
        }
        mac.update(&actual_index.to_be_bytes());
        
        let result = mac.finalize().into_bytes();
        
        // Split into key material and chain code
        let (il, ir) = result.split_at(32);
        
        // child_key = parse256(IL) + parent_key (mod n)
        let tweak = SecretKey::from_slice(il)
            .map_err(|e| CurveError::DerivationFailed(format!("Invalid tweak: {}", e)))?;
        
        let child_sk = parent_sk.add_tweak(&tweak.into())
            .map_err(|e| CurveError::DerivationFailed(format!("Tweak failed: {}", e)))?;
        
        let mut child_chain_code = [0u8; 32];
        child_chain_code.copy_from_slice(ir);
        
        Ok((child_sk.secret_bytes(), child_chain_code))
    }
    
    fn derive_path(seed: &[u8], path: &str) -> Result<(Vec<u8>, Vec<u8>), CurveError> {
        // Parse path like "m/44'/0'/0'/0/0"
        let parts: Vec<&str> = path.split('/').collect();
        
        if parts.is_empty() || parts[0] != "m" {
            return Err(CurveError::DerivationFailed("Path must start with 'm'".into()));
        }
        
        // Derive master key from seed
        let mut mac = HmacSha512::new_from_slice(b"Bitcoin seed")
            .map_err(|e| CurveError::DerivationFailed(e.to_string()))?;
        mac.update(seed);
        let result = mac.finalize().into_bytes();
        
        let (master_key, master_chain_code) = result.split_at(32);
        let mut current_key = [0u8; 32];
        current_key.copy_from_slice(master_key);
        let mut current_chain_code = [0u8; 32];
        current_chain_code.copy_from_slice(master_chain_code);
        
        // Derive each level
        for part in parts.iter().skip(1) {
            let (index, hardened) = if part.ends_with('\'') || part.ends_with('h') {
                let index_str = &part[..part.len() - 1];
                let index: u32 = index_str.parse()
                    .map_err(|_| CurveError::DerivationFailed(format!("Invalid index: {}", part)))?;
                (index, true)
            } else {
                let index: u32 = part.parse()
                    .map_err(|_| CurveError::DerivationFailed(format!("Invalid index: {}", part)))?;
                (index, false)
            };
            
            let (new_key, new_chain) = Self::derive_child(
                &current_key,
                &current_chain_code,
                index,
                hardened,
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

impl Secp256k1Curve {
    /// Get uncompressed public key (65 bytes)
    pub fn public_key_uncompressed(private_key: &[u8]) -> Result<[u8; 65], CurveError> {
        if private_key.len() != 32 {
            return Err(CurveError::InvalidPrivateKey(
                format!("Private key must be 32 bytes, got {}", private_key.len())
            ));
        }
        
        let secp = Secp256k1::new();
        let sk = SecretKey::from_slice(private_key)
            .map_err(|e| CurveError::InvalidPrivateKey(e.to_string()))?;
        
        let pk = PublicKey::from_secret_key(&secp, &sk);
        Ok(pk.serialize_uncompressed())
    }
    
    /// Sign for Ethereum (returns 65-byte signature with v)
    pub fn sign_ethereum(private_key: &[u8], message_hash: &[u8; 32]) -> Result<[u8; 65], CurveError> {
        let (sig, rec_id) = Self::sign_recoverable(private_key, message_hash)?;
        
        let mut result = [0u8; 65];
        result[..64].copy_from_slice(&sig);
        result[64] = rec_id + 27; // Ethereum v = recovery_id + 27
        
        Ok(result)
    }
    
    /// Sign for Ethereum with EIP-155 chain ID
    pub fn sign_ethereum_eip155(
        private_key: &[u8],
        message_hash: &[u8; 32],
        chain_id: u64,
    ) -> Result<[u8; 65], CurveError> {
        let (sig, rec_id) = Self::sign_recoverable(private_key, message_hash)?;
        
        let mut result = [0u8; 65];
        result[..64].copy_from_slice(&sig);
        // EIP-155: v = chain_id * 2 + 35 + recovery_id
        result[64] = ((chain_id * 2 + 35 + rec_id as u64) & 0xFF) as u8;
        
        Ok(result)
    }
    
    /// Encode signature in DER format
    pub fn signature_to_der(signature: &[u8; 64]) -> Result<Vec<u8>, CurveError> {
        let sig = Signature::from_compact(signature)
            .map_err(|e| CurveError::InvalidSignature(e.to_string()))?;
        Ok(sig.serialize_der().to_vec())
    }
    
    /// Decode signature from DER format
    pub fn signature_from_der(der: &[u8]) -> Result<[u8; 64], CurveError> {
        let sig = Signature::from_der(der)
            .map_err(|e| CurveError::InvalidSignature(e.to_string()))?;
        Ok(sig.serialize_compact())
    }
}

// MARK: - Tests

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_secp256k1_generate_keypair() {
        let seed = [42u8; 32];
        let (sk, pk) = Secp256k1Curve::generate_keypair(&seed).unwrap();
        
        assert_eq!(sk.len(), 32);
        assert_eq!(pk.len(), 33); // Compressed
        assert!(pk[0] == 0x02 || pk[0] == 0x03); // Compressed prefix
    }
    
    #[test]
    fn test_secp256k1_sign_verify() {
        let seed = [42u8; 32];
        let (sk, pk) = Secp256k1Curve::generate_keypair(&seed).unwrap();
        
        let message = b"Hello, secp256k1!";
        let signature = Secp256k1Curve::sign(&sk, message).unwrap();
        
        assert_eq!(signature.len(), 64);
        
        let valid = Secp256k1Curve::verify(&pk, message, &signature).unwrap();
        assert!(valid);
        
        // Wrong message should fail
        let wrong_msg = b"Wrong message";
        let valid = Secp256k1Curve::verify(&pk, wrong_msg, &signature).unwrap();
        assert!(!valid);
    }
    
    #[test]
    fn test_secp256k1_recoverable_signature() {
        let seed = [42u8; 32];
        let (sk, pk) = Secp256k1Curve::generate_keypair(&seed).unwrap();
        
        let message = [0xABu8; 32];
        let (signature, recovery_id) = Secp256k1Curve::sign_recoverable(&sk, &message).unwrap();
        
        assert!(recovery_id < 4);
        
        let recovered_pk = Secp256k1Curve::recover_public_key(&message, &signature, recovery_id).unwrap();
        assert_eq!(pk, recovered_pk);
    }
    
    #[test]
    fn test_secp256k1_ecdh() {
        let seed1 = [1u8; 32];
        let seed2 = [2u8; 32];
        
        let (sk1, pk1) = Secp256k1Curve::generate_keypair(&seed1).unwrap();
        let (sk2, pk2) = Secp256k1Curve::generate_keypair(&seed2).unwrap();
        
        // Both parties should derive the same shared secret
        let shared1 = Secp256k1Curve::ecdh(&sk1, &pk2).unwrap();
        let shared2 = Secp256k1Curve::ecdh(&sk2, &pk1).unwrap();
        
        assert_eq!(shared1, shared2);
    }
    
    #[test]
    fn test_secp256k1_derive_path() {
        let seed = hex::decode(
            "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        ).unwrap();
        
        let (private_key, public_key) = Secp256k1Curve::derive_path(&seed, "m/44'/0'/0'/0/0").unwrap();
        
        assert_eq!(private_key.len(), 32);
        assert_eq!(public_key.len(), 33);
    }
    
    #[test]
    fn test_secp256k1_ethereum_signature() {
        let seed = [42u8; 32];
        let (sk, _) = Secp256k1Curve::generate_keypair(&seed).unwrap();
        
        let message_hash = [0xABu8; 32];
        let sig = Secp256k1Curve::sign_ethereum(&sk, &message_hash).unwrap();
        
        assert_eq!(sig.len(), 65);
        assert!(sig[64] == 27 || sig[64] == 28); // v = 27 or 28
    }
    
    #[test]
    fn test_secp256k1_der_encoding() {
        let seed = [42u8; 32];
        let (sk, _) = Secp256k1Curve::generate_keypair(&seed).unwrap();
        
        let message = b"test";
        let signature = Secp256k1Curve::sign(&sk, message).unwrap();
        
        let der = Secp256k1Curve::signature_to_der(&signature).unwrap();
        let decoded = Secp256k1Curve::signature_from_der(&der).unwrap();
        
        assert_eq!(signature, decoded);
    }
}
