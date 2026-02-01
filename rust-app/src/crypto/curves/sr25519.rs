//! Sr25519 Curve Implementation (Schnorr on Ristretto255)
//!
//! Used by: Polkadot, Kusama, and other Substrate-based chains
//!
//! Features:
//! - Schnorr signatures on Ristretto255
//! - VRF (Verifiable Random Function) support
//! - Hard and soft key derivation
//! - Hierarchical deterministic derivation (Substrate style)

use super::{CurveError, EllipticCurve};
use schnorrkel::{
    Keypair, MiniSecretKey, PublicKey, SecretKey, Signature,
    derive::{ChainCode, Derivation},
    signing_context,
};
use hmac::{Hmac, Mac};

type HmacSha512 = Hmac<sha2::Sha512>;

/// Substrate signing context
const SUBSTRATE_SIGNING_CONTEXT: &[u8] = b"substrate";

/// Sr25519 curve implementation
pub struct Sr25519Curve;

impl EllipticCurve for Sr25519Curve {
    type PrivateKey = [u8; 64]; // SecretKey is 64 bytes
    type PublicKey = [u8; 32];
    type Signature = [u8; 64];
    
    fn generate_keypair(seed: &[u8]) -> Result<(Self::PrivateKey, Self::PublicKey), CurveError> {
        if seed.len() < 32 {
            return Err(CurveError::InvalidSeed(
                format!("Seed must be at least 32 bytes, got {}", seed.len())
            ));
        }
        
        let mut mini_secret_bytes = [0u8; 32];
        mini_secret_bytes.copy_from_slice(&seed[..32]);
        
        let mini_secret = MiniSecretKey::from_bytes(&mini_secret_bytes)
            .map_err(|e| CurveError::InvalidSeed(format!("Invalid seed: {:?}", e)))?;
        
        let keypair = mini_secret.expand_to_keypair(schnorrkel::ExpansionMode::Ed25519);
        
        Ok((keypair.secret.to_bytes(), keypair.public.to_bytes()))
    }
    
    fn public_key_from_private(private_key: &[u8]) -> Result<Self::PublicKey, CurveError> {
        if private_key.len() == 32 {
            // MiniSecretKey (32 bytes)
            let mut mini_bytes = [0u8; 32];
            mini_bytes.copy_from_slice(private_key);
            
            let mini_secret = MiniSecretKey::from_bytes(&mini_bytes)
                .map_err(|e| CurveError::InvalidPrivateKey(format!("Invalid mini secret: {:?}", e)))?;
            
            let keypair = mini_secret.expand_to_keypair(schnorrkel::ExpansionMode::Ed25519);
            Ok(keypair.public.to_bytes())
        } else if private_key.len() == 64 {
            // Full SecretKey (64 bytes)
            let secret = SecretKey::from_bytes(private_key)
                .map_err(|e| CurveError::InvalidPrivateKey(format!("Invalid secret key: {:?}", e)))?;
            
            Ok(secret.to_public().to_bytes())
        } else {
            Err(CurveError::InvalidPrivateKey(
                format!("Private key must be 32 or 64 bytes, got {}", private_key.len())
            ))
        }
    }
    
    fn sign(private_key: &[u8], message: &[u8]) -> Result<Self::Signature, CurveError> {
        let keypair = Self::keypair_from_bytes(private_key)?;
        
        let context = signing_context(SUBSTRATE_SIGNING_CONTEXT);
        let signature = keypair.sign(context.bytes(message));
        
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
        
        let pk = PublicKey::from_bytes(&pk_bytes)
            .map_err(|e| CurveError::InvalidPublicKey(format!("Invalid public key: {:?}", e)))?;
        
        let mut sig_bytes = [0u8; 64];
        sig_bytes.copy_from_slice(signature);
        
        let sig = Signature::from_bytes(&sig_bytes)
            .map_err(|e| CurveError::InvalidSignature(format!("Invalid signature: {:?}", e)))?;
        
        let context = signing_context(SUBSTRATE_SIGNING_CONTEXT);
        
        Ok(pk.verify(context.bytes(message), &sig).is_ok())
    }
}

impl Sr25519Curve {
    /// Create keypair from bytes (handles both 32 and 64 byte formats)
    fn keypair_from_bytes(private_key: &[u8]) -> Result<Keypair, CurveError> {
        if private_key.len() == 32 {
            // MiniSecretKey (32 bytes)
            let mut mini_bytes = [0u8; 32];
            mini_bytes.copy_from_slice(private_key);
            
            let mini_secret = MiniSecretKey::from_bytes(&mini_bytes)
                .map_err(|e| CurveError::InvalidPrivateKey(format!("Invalid mini secret: {:?}", e)))?;
            
            Ok(mini_secret.expand_to_keypair(schnorrkel::ExpansionMode::Ed25519))
        } else if private_key.len() == 64 {
            // Full SecretKey (64 bytes)
            let secret = SecretKey::from_bytes(private_key)
                .map_err(|e| CurveError::InvalidPrivateKey(format!("Invalid secret key: {:?}", e)))?;
            
            Ok(secret.to_keypair())
        } else {
            Err(CurveError::InvalidPrivateKey(
                format!("Private key must be 32 or 64 bytes, got {}", private_key.len())
            ))
        }
    }
    
    /// Derive master keypair from seed (Substrate style)
    pub fn from_seed(seed: &[u8]) -> Result<([u8; 64], [u8; 32], [u8; 32]), CurveError> {
        if seed.len() < 32 {
            return Err(CurveError::InvalidSeed(
                format!("Seed must be at least 32 bytes, got {}", seed.len())
            ));
        }
        
        let mut mini_secret_bytes = [0u8; 32];
        mini_secret_bytes.copy_from_slice(&seed[..32]);
        
        let mini_secret = MiniSecretKey::from_bytes(&mini_secret_bytes)
            .map_err(|e| CurveError::InvalidSeed(format!("Invalid seed: {:?}", e)))?;
        
        let keypair = mini_secret.expand_to_keypair(schnorrkel::ExpansionMode::Ed25519);
        
        // Initial chain code is derived from seed
        let mut mac = HmacSha512::new_from_slice(b"sr25519 seed")
            .map_err(|e| CurveError::DerivationFailed(e.to_string()))?;
        mac.update(seed);
        let result = mac.finalize().into_bytes();
        
        let mut chain_code = [0u8; 32];
        chain_code.copy_from_slice(&result[32..]);
        
        Ok((keypair.secret.to_bytes(), keypair.public.to_bytes(), chain_code))
    }
    
    /// Hard derivation (changes both public and secret key unpredictably)
    pub fn derive_hard(
        secret_key: &[u8],
        chain_code: &[u8; 32],
        junction: &[u8],
    ) -> Result<([u8; 64], [u8; 32], [u8; 32]), CurveError> {
        let keypair = Self::keypair_from_bytes(secret_key)?;
        
        let cc = ChainCode(*chain_code);
        
        // Create junction data
        let (derived_keypair, new_cc) = keypair.hard_derive_mini_secret_key(
            Some(cc),
            junction,
        );
        
        let derived = derived_keypair.expand_to_keypair(schnorrkel::ExpansionMode::Ed25519);
        
        Ok((
            derived.secret.to_bytes(),
            derived.public.to_bytes(),
            new_cc.0,
        ))
    }
    
    /// Soft derivation (public key derivable from parent public key)
    pub fn derive_soft(
        secret_key: &[u8],
        chain_code: &[u8; 32],
        junction: &[u8],
    ) -> Result<([u8; 64], [u8; 32], [u8; 32]), CurveError> {
        let keypair = Self::keypair_from_bytes(secret_key)?;
        
        let cc = ChainCode(*chain_code);
        
        let (derived, new_cc) = keypair.derived_key_simple(cc, junction);
        
        Ok((
            derived.secret.to_bytes(),
            derived.public.to_bytes(),
            new_cc.0,
        ))
    }
    
    /// Derive public key only (soft derivation)
    pub fn derive_public_soft(
        public_key: &[u8; 32],
        chain_code: &[u8; 32],
        junction: &[u8],
    ) -> Result<([u8; 32], [u8; 32]), CurveError> {
        let pk = PublicKey::from_bytes(public_key)
            .map_err(|e| CurveError::InvalidPublicKey(format!("Invalid public key: {:?}", e)))?;
        
        let cc = ChainCode(*chain_code);
        
        let (derived_pk, new_cc) = pk.derived_key_simple(cc, junction);
        
        Ok((derived_pk.to_bytes(), new_cc.0))
    }
    
    /// Derive from Substrate-style path (e.g., "//polkadot/0" or "/soft")
    /// "//" = hard derivation, "/" = soft derivation
    pub fn derive_path(seed: &[u8], path: &str) -> Result<([u8; 64], [u8; 32]), CurveError> {
        let (mut sk, mut pk, mut cc) = Self::from_seed(seed)?;
        
        // Parse path
        let mut remaining = path;
        while !remaining.is_empty() {
            if remaining.starts_with("//") {
                // Hard derivation
                remaining = &remaining[2..];
                let (junction, rest) = Self::parse_junction(remaining);
                remaining = rest;
                
                (sk, pk, cc) = Self::derive_hard(&sk, &cc, junction.as_bytes())?;
            } else if remaining.starts_with('/') {
                // Soft derivation
                remaining = &remaining[1..];
                let (junction, rest) = Self::parse_junction(remaining);
                remaining = rest;
                
                (sk, pk, cc) = Self::derive_soft(&sk, &cc, junction.as_bytes())?;
            } else {
                return Err(CurveError::DerivationFailed(
                    format!("Invalid path syntax at: {}", remaining)
                ));
            }
        }
        
        Ok((sk, pk))
    }
    
    /// Parse a junction from path string
    fn parse_junction(path: &str) -> (&str, &str) {
        // Find next '/' or end of string
        if let Some(pos) = path.find('/') {
            (&path[..pos], &path[pos..])
        } else {
            (path, "")
        }
    }
    
    /// Sign with custom context (not Substrate default)
    pub fn sign_with_context(
        private_key: &[u8],
        context: &[u8],
        message: &[u8],
    ) -> Result<[u8; 64], CurveError> {
        let keypair = Self::keypair_from_bytes(private_key)?;
        
        let ctx = signing_context(context);
        let signature = keypair.sign(ctx.bytes(message));
        
        Ok(signature.to_bytes())
    }
    
    /// Verify with custom context
    pub fn verify_with_context(
        public_key: &[u8],
        context: &[u8],
        message: &[u8],
        signature: &[u8],
    ) -> Result<bool, CurveError> {
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
        
        let pk = PublicKey::from_bytes(&pk_bytes)
            .map_err(|e| CurveError::InvalidPublicKey(format!("Invalid public key: {:?}", e)))?;
        
        let mut sig_bytes = [0u8; 64];
        sig_bytes.copy_from_slice(signature);
        
        let sig = Signature::from_bytes(&sig_bytes)
            .map_err(|e| CurveError::InvalidSignature(format!("Invalid signature: {:?}", e)))?;
        
        let ctx = signing_context(context);
        
        Ok(pk.verify(ctx.bytes(message), &sig).is_ok())
    }
    
    /// Generate VRF output
    pub fn vrf_sign(
        private_key: &[u8],
        transcript_data: &[u8],
    ) -> Result<([u8; 32], [u8; 64]), CurveError> {
        let keypair = Self::keypair_from_bytes(private_key)?;
        
        let ctx = signing_context(b"substrate");
        let (inout, proof, _) = keypair.vrf_sign(ctx.bytes(transcript_data));
        
        let output: [u8; 32] = inout.to_preout().to_bytes();
        let proof_bytes: [u8; 64] = proof.to_bytes();
        
        Ok((output, proof_bytes))
    }
    
    /// Convert to SS58 address (Substrate format)
    pub fn to_ss58_address(public_key: &[u8; 32], network_id: u16) -> String {
        // SS58 format: prefix || pubkey || checksum
        let mut payload = Vec::new();
        
        if network_id < 64 {
            payload.push(network_id as u8);
        } else if network_id < 16384 {
            // Two-byte prefix
            let first = ((network_id & 0xFC) >> 2) | 0x40;
            let second = (network_id >> 8) | ((network_id & 0x03) << 6);
            payload.push(first as u8);
            payload.push(second as u8);
        } else {
            // Larger network IDs not supported here
            payload.push(42); // Generic Substrate
        }
        
        payload.extend_from_slice(public_key);
        
        // SS58 checksum
        let mut hasher = blake2_rfc::blake2b::Blake2b::new(64);
        hasher.update(b"SS58PRE");
        hasher.update(&payload);
        let hash = hasher.finalize();
        
        payload.extend_from_slice(&hash.as_bytes()[..2]);
        
        bs58::encode(payload).into_string()
    }
}

// MARK: - Tests

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_sr25519_generate_keypair() {
        let seed = [42u8; 32];
        let (sk, pk) = Sr25519Curve::generate_keypair(&seed).unwrap();
        
        assert_eq!(sk.len(), 64);
        assert_eq!(pk.len(), 32);
    }
    
    #[test]
    fn test_sr25519_sign_verify() {
        let seed = [42u8; 32];
        let (sk, pk) = Sr25519Curve::generate_keypair(&seed).unwrap();
        
        let message = b"Hello, Sr25519!";
        let signature = Sr25519Curve::sign(&sk, message).unwrap();
        
        assert_eq!(signature.len(), 64);
        
        let valid = Sr25519Curve::verify(&pk, message, &signature).unwrap();
        assert!(valid);
        
        // Wrong message should fail
        let wrong_msg = b"Wrong message";
        let valid = Sr25519Curve::verify(&pk, wrong_msg, &signature).unwrap();
        assert!(!valid);
    }
    
    #[test]
    fn test_sr25519_derive_path() {
        let seed = [42u8; 32];
        
        // Hard derivation path
        let (sk, pk) = Sr25519Curve::derive_path(&seed, "//polkadot//0").unwrap();
        
        assert_eq!(sk.len(), 64);
        assert_eq!(pk.len(), 32);
    }
    
    #[test]
    fn test_sr25519_soft_derivation() {
        let seed = [42u8; 32];
        
        let (sk, pk, cc) = Sr25519Curve::from_seed(&seed).unwrap();
        
        // Soft derive from secret
        let (_, pk_from_secret, _) = Sr25519Curve::derive_soft(&sk, &cc, b"soft").unwrap();
        
        // Soft derive from public
        let mut pk_arr = [0u8; 32];
        pk_arr.copy_from_slice(&pk);
        let (pk_from_public, _) = Sr25519Curve::derive_public_soft(&pk_arr, &cc, b"soft").unwrap();
        
        // Should produce same public key
        assert_eq!(pk_from_secret, pk_from_public);
    }
    
    #[test]
    fn test_sr25519_ss58_address() {
        let seed = [42u8; 32];
        let (_, pk) = Sr25519Curve::generate_keypair(&seed).unwrap();
        
        let mut pk_arr = [0u8; 32];
        pk_arr.copy_from_slice(&pk);
        
        // Polkadot network ID = 0
        let polkadot_addr = Sr25519Curve::to_ss58_address(&pk_arr, 0);
        assert!(polkadot_addr.starts_with('1')); // Polkadot addresses start with 1
        
        // Kusama network ID = 2
        let _kusama_addr = Sr25519Curve::to_ss58_address(&pk_arr, 2);
        // Kusama addresses have different prefix
        
        // Generic Substrate = 42
        let generic_addr = Sr25519Curve::to_ss58_address(&pk_arr, 42);
        assert!(generic_addr.starts_with('5')); // Generic starts with 5
    }
    
    #[test]
    fn test_sr25519_vrf() {
        let seed = [42u8; 32];
        let (sk, _) = Sr25519Curve::generate_keypair(&seed).unwrap();
        
        let (output, proof) = Sr25519Curve::vrf_sign(&sk, b"randomness seed").unwrap();
        
        assert_eq!(output.len(), 32);
        assert_eq!(proof.len(), 64);
    }
}
