//! Secp256r1 (P-256/NIST) Curve Implementation
//!
//! Used by: NEO, some hardware wallets, WebAuthn/FIDO2
//!
//! Features:
//! - ECDSA signing with SHA-256
//! - Hardware security module compatibility
//! - Standard NIST P-256 curve

use super::{CurveError, EllipticCurve, KeyExchange};
use p256::{
    ecdsa::{
        signature::{Signer, Verifier, DigestSigner, DigestVerifier},
        Signature, SigningKey, VerifyingKey, DerSignature,
    },
    elliptic_curve::{
        sec1::{FromEncodedPoint, ToEncodedPoint},
    },
    EncodedPoint, PublicKey, SecretKey,
};
use sha2::{Sha256, Digest};
use rand::rngs::OsRng;

/// Secp256r1 (P-256) curve implementation
pub struct Secp256r1Curve;

impl EllipticCurve for Secp256r1Curve {
    type PrivateKey = [u8; 32];
    type PublicKey = [u8; 33]; // Compressed public key
    type Signature = [u8; 64];  // Fixed-size signature
    
    fn generate_keypair(seed: &[u8]) -> Result<(Self::PrivateKey, Self::PublicKey), CurveError> {
        if seed.len() < 32 {
            return Err(CurveError::InvalidSeed(
                format!("Seed must be at least 32 bytes, got {}", seed.len())
            ));
        }
        
        let mut private_key_bytes = [0u8; 32];
        private_key_bytes.copy_from_slice(&seed[..32]);
        
        let secret_key = SecretKey::from_bytes((&private_key_bytes).into())
            .map_err(|e| CurveError::InvalidSeed(format!("Invalid seed: {:?}", e)))?;
        
        let public_key = secret_key.public_key();
        let pk_compressed = public_key.to_encoded_point(true);
        
        let mut pk_bytes = [0u8; 33];
        pk_bytes.copy_from_slice(pk_compressed.as_bytes());
        
        Ok((private_key_bytes, pk_bytes))
    }
    
    fn public_key_from_private(private_key: &[u8]) -> Result<Self::PublicKey, CurveError> {
        if private_key.len() != 32 {
            return Err(CurveError::InvalidPrivateKey(
                format!("Private key must be 32 bytes, got {}", private_key.len())
            ));
        }
        
        let secret_key = SecretKey::from_bytes(private_key.into())
            .map_err(|e| CurveError::InvalidPrivateKey(format!("Invalid private key: {:?}", e)))?;
        
        let public_key = secret_key.public_key();
        let pk_compressed = public_key.to_encoded_point(true);
        
        let mut pk_bytes = [0u8; 33];
        pk_bytes.copy_from_slice(pk_compressed.as_bytes());
        
        Ok(pk_bytes)
    }
    
    fn sign(private_key: &[u8], message: &[u8]) -> Result<Self::Signature, CurveError> {
        if private_key.len() != 32 {
            return Err(CurveError::InvalidPrivateKey(
                format!("Private key must be 32 bytes, got {}", private_key.len())
            ));
        }
        
        let signing_key = SigningKey::from_bytes(private_key.into())
            .map_err(|e| CurveError::InvalidPrivateKey(format!("Invalid signing key: {:?}", e)))?;
        
        // Sign message (SigningKey automatically hashes with SHA-256)
        let signature: Signature = signing_key.sign(message);
        
        Ok(signature.to_bytes().into())
    }
    
    fn verify(public_key: &[u8], message: &[u8], signature: &[u8]) -> Result<bool, CurveError> {
        if signature.len() != 64 {
            return Err(CurveError::InvalidSignature(
                format!("Signature must be 64 bytes, got {}", signature.len())
            ));
        }
        
        let verifying_key = Self::parse_public_key(public_key)?;
        
        let sig = Signature::from_bytes(signature.into())
            .map_err(|e| CurveError::InvalidSignature(format!("Invalid signature: {:?}", e)))?;
        
        Ok(verifying_key.verify(message, &sig).is_ok())
    }
}

impl KeyExchange for Secp256r1Curve {
    fn ecdh(private_key: &[u8], peer_public_key: &[u8]) -> Result<[u8; 32], CurveError> {
        if private_key.len() != 32 {
            return Err(CurveError::InvalidPrivateKey(
                format!("Private key must be 32 bytes, got {}", private_key.len())
            ));
        }
        
        let secret_key = SecretKey::from_bytes(private_key.into())
            .map_err(|e| CurveError::InvalidPrivateKey(format!("Invalid private key: {:?}", e)))?;
        
        let peer_pk = Self::parse_p256_public_key(peer_public_key)?;
        
        let shared_secret = p256::ecdh::diffie_hellman(
            secret_key.to_nonzero_scalar(),
            peer_pk.as_affine(),
        );
        
        let mut result = [0u8; 32];
        result.copy_from_slice(shared_secret.raw_secret_bytes());
        
        Ok(result)
    }
}

impl Secp256r1Curve {
    /// Parse public key from various formats (compressed, uncompressed)
    fn parse_public_key(public_key: &[u8]) -> Result<VerifyingKey, CurveError> {
        match public_key.len() {
            33 => {
                // Compressed format
                let point = EncodedPoint::from_bytes(public_key)
                    .map_err(|e| CurveError::InvalidPublicKey(format!("Invalid point: {:?}", e)))?;
                
                VerifyingKey::from_encoded_point(&point)
                    .map_err(|e| CurveError::InvalidPublicKey(format!("Invalid key: {:?}", e)))
            }
            65 => {
                // Uncompressed format
                let point = EncodedPoint::from_bytes(public_key)
                    .map_err(|e| CurveError::InvalidPublicKey(format!("Invalid point: {:?}", e)))?;
                
                VerifyingKey::from_encoded_point(&point)
                    .map_err(|e| CurveError::InvalidPublicKey(format!("Invalid key: {:?}", e)))
            }
            64 => {
                // Raw coordinates (X || Y)
                let mut uncompressed = [0u8; 65];
                uncompressed[0] = 0x04;
                uncompressed[1..].copy_from_slice(public_key);
                
                let point = EncodedPoint::from_bytes(&uncompressed)
                    .map_err(|e| CurveError::InvalidPublicKey(format!("Invalid point: {:?}", e)))?;
                
                VerifyingKey::from_encoded_point(&point)
                    .map_err(|e| CurveError::InvalidPublicKey(format!("Invalid key: {:?}", e)))
            }
            _ => Err(CurveError::InvalidPublicKey(
                format!("Public key must be 33, 64, or 65 bytes, got {}", public_key.len())
            ))
        }
    }
    
    /// Parse P-256 public key
    fn parse_p256_public_key(public_key: &[u8]) -> Result<PublicKey, CurveError> {
        match public_key.len() {
            33 | 65 => {
                let point = EncodedPoint::from_bytes(public_key)
                    .map_err(|e| CurveError::InvalidPublicKey(format!("Invalid point: {:?}", e)))?;
                
                PublicKey::from_encoded_point(&point)
                    .into_option()
                    .ok_or_else(|| CurveError::InvalidPublicKey("Invalid P-256 public key".into()))
            }
            64 => {
                let mut uncompressed = [0u8; 65];
                uncompressed[0] = 0x04;
                uncompressed[1..].copy_from_slice(public_key);
                
                let point = EncodedPoint::from_bytes(&uncompressed)
                    .map_err(|e| CurveError::InvalidPublicKey(format!("Invalid point: {:?}", e)))?;
                
                PublicKey::from_encoded_point(&point)
                    .into_option()
                    .ok_or_else(|| CurveError::InvalidPublicKey("Invalid P-256 public key".into()))
            }
            _ => Err(CurveError::InvalidPublicKey(
                format!("Public key must be 33, 64, or 65 bytes, got {}", public_key.len())
            ))
        }
    }
    
    /// Generate keypair using secure random (for hardware wallet simulation)
    pub fn generate_keypair_random() -> Result<([u8; 32], [u8; 33]), CurveError> {
        let secret_key = SecretKey::random(&mut OsRng);
        let public_key = secret_key.public_key();
        
        let sk_bytes: [u8; 32] = secret_key.to_bytes().into();
        
        let pk_compressed = public_key.to_encoded_point(true);
        let mut pk_bytes = [0u8; 33];
        pk_bytes.copy_from_slice(pk_compressed.as_bytes());
        
        Ok((sk_bytes, pk_bytes))
    }
    
    /// Get uncompressed public key (65 bytes)
    pub fn public_key_uncompressed(private_key: &[u8]) -> Result<[u8; 65], CurveError> {
        if private_key.len() != 32 {
            return Err(CurveError::InvalidPrivateKey(
                format!("Private key must be 32 bytes, got {}", private_key.len())
            ));
        }
        
        let secret_key = SecretKey::from_bytes(private_key.into())
            .map_err(|e| CurveError::InvalidPrivateKey(format!("Invalid private key: {:?}", e)))?;
        
        let public_key = secret_key.public_key();
        let pk_uncompressed = public_key.to_encoded_point(false);
        
        let mut pk_bytes = [0u8; 65];
        pk_bytes.copy_from_slice(pk_uncompressed.as_bytes());
        
        Ok(pk_bytes)
    }
    
    /// Compress a public key
    pub fn compress_public_key(uncompressed: &[u8]) -> Result<[u8; 33], CurveError> {
        let pk = Self::parse_p256_public_key(uncompressed)?;
        let compressed = pk.to_encoded_point(true);
        
        let mut result = [0u8; 33];
        result.copy_from_slice(compressed.as_bytes());
        
        Ok(result)
    }
    
    /// Sign prehashed message (for when hash is computed externally)
    pub fn sign_prehashed(private_key: &[u8], hash: &[u8; 32]) -> Result<[u8; 64], CurveError> {
        if private_key.len() != 32 {
            return Err(CurveError::InvalidPrivateKey(
                format!("Private key must be 32 bytes, got {}", private_key.len())
            ));
        }
        
        let signing_key = SigningKey::from_bytes(private_key.into())
            .map_err(|e| CurveError::InvalidPrivateKey(format!("Invalid signing key: {:?}", e)))?;
        
        // Create a digest from the prehashed value
        let mut digest = Sha256::new();
        digest.update(hash);
        
        let signature: Signature = signing_key.sign_digest(digest);
        
        Ok(signature.to_bytes().into())
    }
    
    /// Verify prehashed message
    pub fn verify_prehashed(
        public_key: &[u8],
        hash: &[u8; 32],
        signature: &[u8],
    ) -> Result<bool, CurveError> {
        if signature.len() != 64 {
            return Err(CurveError::InvalidSignature(
                format!("Signature must be 64 bytes, got {}", signature.len())
            ));
        }
        
        let verifying_key = Self::parse_public_key(public_key)?;
        
        let sig = Signature::from_bytes(signature.into())
            .map_err(|e| CurveError::InvalidSignature(format!("Invalid signature: {:?}", e)))?;
        
        let mut digest = Sha256::new();
        digest.update(hash);
        
        Ok(verifying_key.verify_digest(digest, &sig).is_ok())
    }
    
    /// Sign and return DER-encoded signature (for X.509/TLS compatibility)
    pub fn sign_der(private_key: &[u8], message: &[u8]) -> Result<Vec<u8>, CurveError> {
        if private_key.len() != 32 {
            return Err(CurveError::InvalidPrivateKey(
                format!("Private key must be 32 bytes, got {}", private_key.len())
            ));
        }
        
        let signing_key = SigningKey::from_bytes(private_key.into())
            .map_err(|e| CurveError::InvalidPrivateKey(format!("Invalid signing key: {:?}", e)))?;
        
        let signature: DerSignature = signing_key.sign(message);
        
        Ok(signature.as_bytes().to_vec())
    }
    
    /// Verify DER-encoded signature
    pub fn verify_der(
        public_key: &[u8],
        message: &[u8],
        signature_der: &[u8],
    ) -> Result<bool, CurveError> {
        let verifying_key = Self::parse_public_key(public_key)?;
        
        let sig = DerSignature::from_bytes(signature_der)
            .map_err(|e| CurveError::InvalidSignature(format!("Invalid DER signature: {:?}", e)))?;
        
        Ok(verifying_key.verify(message, &sig).is_ok())
    }
    
    /// Generate WebAuthn/FIDO2 compatible key pair
    /// Returns (private_key, public_key_cose)
    pub fn generate_webauthn_keypair(seed: &[u8]) -> Result<([u8; 32], Vec<u8>), CurveError> {
        let (sk, _) = Self::generate_keypair(seed)?;
        let pk_uncompressed = Self::public_key_uncompressed(&sk)?;
        
        // COSE key format for ES256 (algorithm -7)
        // This is a simplified COSE encoding
        let x = &pk_uncompressed[1..33];
        let y = &pk_uncompressed[33..65];
        
        // COSE_Key structure:
        // {
        //   1: 2,      // kty: EC2
        //   3: -7,     // alg: ES256
        //   -1: 1,     // crv: P-256
        //   -2: x,     // x coordinate
        //   -3: y,     // y coordinate
        // }
        // Encoded as CBOR
        let mut cose_key = Vec::with_capacity(80);
        cose_key.push(0xa5); // Map of 5 items
        
        // kty: 2 (EC2)
        cose_key.push(0x01);
        cose_key.push(0x02);
        
        // alg: -7 (ES256)
        cose_key.push(0x03);
        cose_key.push(0x26); // -7 in CBOR
        
        // crv: 1 (P-256)
        cose_key.push(0x20); // -1 in CBOR
        cose_key.push(0x01);
        
        // x coordinate
        cose_key.push(0x21); // -2 in CBOR
        cose_key.push(0x58); // byte string, 1-byte length
        cose_key.push(0x20); // 32 bytes
        cose_key.extend_from_slice(x);
        
        // y coordinate
        cose_key.push(0x22); // -3 in CBOR
        cose_key.push(0x58); // byte string, 1-byte length
        cose_key.push(0x20); // 32 bytes
        cose_key.extend_from_slice(y);
        
        Ok((sk, cose_key))
    }
}

// MARK: - Tests

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_secp256r1_generate_keypair() {
        let seed = [42u8; 32];
        let (sk, pk) = Secp256r1Curve::generate_keypair(&seed).unwrap();
        
        assert_eq!(sk.len(), 32);
        assert_eq!(pk.len(), 33);
        assert!(pk[0] == 0x02 || pk[0] == 0x03); // Compressed prefix
    }
    
    #[test]
    fn test_secp256r1_sign_verify() {
        let seed = [42u8; 32];
        let (sk, pk) = Secp256r1Curve::generate_keypair(&seed).unwrap();
        
        let message = b"Hello, P-256!";
        let signature = Secp256r1Curve::sign(&sk, message).unwrap();
        
        assert_eq!(signature.len(), 64);
        
        let valid = Secp256r1Curve::verify(&pk, message, &signature).unwrap();
        assert!(valid);
        
        // Wrong message should fail
        let wrong_msg = b"Wrong message";
        let valid = Secp256r1Curve::verify(&pk, wrong_msg, &signature).unwrap();
        assert!(!valid);
    }
    
    #[test]
    fn test_secp256r1_ecdh() {
        let seed_a = [1u8; 32];
        let seed_b = [2u8; 32];
        
        let (sk_a, pk_a) = Secp256r1Curve::generate_keypair(&seed_a).unwrap();
        let (sk_b, pk_b) = Secp256r1Curve::generate_keypair(&seed_b).unwrap();
        
        let shared_a = Secp256r1Curve::ecdh(&sk_a, &pk_b).unwrap();
        let shared_b = Secp256r1Curve::ecdh(&sk_b, &pk_a).unwrap();
        
        assert_eq!(shared_a, shared_b);
    }
    
    #[test]
    fn test_secp256r1_uncompressed() {
        let seed = [42u8; 32];
        let (sk, pk_compressed) = Secp256r1Curve::generate_keypair(&seed).unwrap();
        
        let pk_uncompressed = Secp256r1Curve::public_key_uncompressed(&sk).unwrap();
        assert_eq!(pk_uncompressed.len(), 65);
        assert_eq!(pk_uncompressed[0], 0x04); // Uncompressed prefix
        
        // Verify with uncompressed key
        let message = b"Test message";
        let signature = Secp256r1Curve::sign(&sk, message).unwrap();
        
        let valid = Secp256r1Curve::verify(&pk_uncompressed, message, &signature).unwrap();
        assert!(valid);
    }
    
    #[test]
    fn test_secp256r1_der_signature() {
        let seed = [42u8; 32];
        let (sk, pk) = Secp256r1Curve::generate_keypair(&seed).unwrap();
        
        let message = b"DER signature test";
        let sig_der = Secp256r1Curve::sign_der(&sk, message).unwrap();
        
        // DER signatures are variable length (typically 70-72 bytes)
        assert!(sig_der.len() >= 68 && sig_der.len() <= 72);
        
        let valid = Secp256r1Curve::verify_der(&pk, message, &sig_der).unwrap();
        assert!(valid);
    }
    
    #[test]
    fn test_secp256r1_compress() {
        let seed = [42u8; 32];
        let (sk, pk_compressed) = Secp256r1Curve::generate_keypair(&seed).unwrap();
        
        let pk_uncompressed = Secp256r1Curve::public_key_uncompressed(&sk).unwrap();
        let recompressed = Secp256r1Curve::compress_public_key(&pk_uncompressed).unwrap();
        
        assert_eq!(pk_compressed, recompressed);
    }
    
    #[test]
    fn test_secp256r1_webauthn() {
        let seed = [42u8; 32];
        let (sk, cose_key) = Secp256r1Curve::generate_webauthn_keypair(&seed).unwrap();
        
        assert_eq!(sk.len(), 32);
        assert!(!cose_key.is_empty());
        
        // COSE key should start with 0xa5 (map of 5 items)
        assert_eq!(cose_key[0], 0xa5);
    }
}
