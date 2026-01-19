//! Multi-Curve Cryptography Support
//!
//! This module provides a unified abstraction for multiple elliptic curves
//! used across different blockchain networks:
//!
//! - `secp256k1`: Bitcoin, Ethereum, BNB Chain, etc.
//! - `ed25519`: Solana, Stellar, Cardano, TON, Near, Aptos, Sui
//! - `sr25519`: Polkadot, Kusama (Substrate-based chains)
//! - `secp256r1` (P-256/NIST): NEO, some hardware wallets
//!
//! # Architecture
//!
//! All curves implement the `EllipticCurve` trait which provides:
//! - Key generation from seed
//! - Public key derivation
//! - Message signing
//! - Signature verification
//!
//! # Example
//!
//! ```rust,ignore
//! use rust_app::crypto::curves::{CurveType, sign, verify};
//!
//! let seed = [0u8; 32];
//! let message = b"hello world";
//!
//! // Sign with secp256k1
//! let (sig, pubkey) = sign(CurveType::Secp256k1, &seed, message)?;
//!
//! // Verify
//! let valid = verify(CurveType::Secp256k1, &pubkey, message, &sig)?;
//! ```

pub mod secp256k1;
pub mod ed25519;
pub mod sr25519;
pub mod secp256r1;
pub mod traits;

pub use traits::*;
pub use secp256k1::Secp256k1Curve;
pub use ed25519::Ed25519Curve;
pub use sr25519::Sr25519Curve;
pub use secp256r1::Secp256r1Curve;

use serde::{Deserialize, Serialize};

// MARK: - Curve Type Enum

/// Supported elliptic curve types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CurveType {
    /// secp256k1 - Bitcoin, Ethereum, BNB, etc.
    Secp256k1,
    /// Ed25519 - Solana, Stellar, Cardano, TON, Near, Aptos, Sui
    Ed25519,
    /// Sr25519 (Schnorr on Ristretto) - Polkadot, Kusama
    Sr25519,
    /// secp256r1 (P-256/NIST) - NEO, some hardware wallets
    Secp256r1,
}

impl CurveType {
    /// Get the curve name as a string
    pub fn name(&self) -> &'static str {
        match self {
            Self::Secp256k1 => "secp256k1",
            Self::Ed25519 => "ed25519",
            Self::Sr25519 => "sr25519",
            Self::Secp256r1 => "secp256r1",
        }
    }
    
    /// Get the private key size in bytes
    pub fn private_key_size(&self) -> usize {
        match self {
            Self::Secp256k1 => 32,
            Self::Ed25519 => 32,
            Self::Sr25519 => 64, // MiniSecretKey is 32, but full SecretKey is 64
            Self::Secp256r1 => 32,
        }
    }
    
    /// Get the public key size in bytes (compressed for applicable curves)
    pub fn public_key_size(&self) -> usize {
        match self {
            Self::Secp256k1 => 33, // Compressed
            Self::Ed25519 => 32,
            Self::Sr25519 => 32,
            Self::Secp256r1 => 33, // Compressed
        }
    }
    
    /// Get the signature size in bytes
    pub fn signature_size(&self) -> usize {
        match self {
            Self::Secp256k1 => 64, // r,s without recovery byte
            Self::Ed25519 => 64,
            Self::Sr25519 => 64,
            Self::Secp256r1 => 64,
        }
    }
    
    /// Parse curve type from string
    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "secp256k1" => Some(Self::Secp256k1),
            "ed25519" => Some(Self::Ed25519),
            "sr25519" => Some(Self::Sr25519),
            "secp256r1" | "p256" | "nist256p1" => Some(Self::Secp256r1),
            _ => None,
        }
    }
    
    /// Get chains that use this curve
    pub fn chains(&self) -> &'static [&'static str] {
        match self {
            Self::Secp256k1 => &["bitcoin", "ethereum", "bnb", "litecoin", "dogecoin", "tron"],
            Self::Ed25519 => &["solana", "stellar", "cardano", "ton", "near", "aptos", "sui", "algorand"],
            Self::Sr25519 => &["polkadot", "kusama"],
            Self::Secp256r1 => &["neo"],
        }
    }
}

impl std::fmt::Display for CurveType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.name())
    }
}

// MARK: - Curve Errors

/// Errors that can occur during curve operations
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum CurveError {
    InvalidPrivateKey(String),
    InvalidPublicKey(String),
    InvalidSignature(String),
    InvalidSeed(String),
    SigningFailed(String),
    VerificationFailed(String),
    UnsupportedCurve(String),
    DerivationFailed(String),
}

impl std::fmt::Display for CurveError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidPrivateKey(s) => write!(f, "Invalid private key: {}", s),
            Self::InvalidPublicKey(s) => write!(f, "Invalid public key: {}", s),
            Self::InvalidSignature(s) => write!(f, "Invalid signature: {}", s),
            Self::InvalidSeed(s) => write!(f, "Invalid seed: {}", s),
            Self::SigningFailed(s) => write!(f, "Signing failed: {}", s),
            Self::VerificationFailed(s) => write!(f, "Verification failed: {}", s),
            Self::UnsupportedCurve(s) => write!(f, "Unsupported curve: {}", s),
            Self::DerivationFailed(s) => write!(f, "Key derivation failed: {}", s),
        }
    }
}

impl std::error::Error for CurveError {}

// MARK: - Unified Interface

/// Generate a keypair for the specified curve
pub fn generate_keypair(curve: CurveType, seed: &[u8]) -> Result<(Vec<u8>, Vec<u8>), CurveError> {
    match curve {
        CurveType::Secp256k1 => {
            let (sk, pk) = Secp256k1Curve::generate_keypair(seed)?;
            Ok((sk.to_vec(), pk.to_vec()))
        }
        CurveType::Ed25519 => {
            let (sk, pk) = Ed25519Curve::generate_keypair(seed)?;
            Ok((sk.to_vec(), pk.to_vec()))
        }
        CurveType::Sr25519 => {
            let (sk, pk) = Sr25519Curve::generate_keypair(seed)?;
            Ok((sk.to_vec(), pk.to_vec()))
        }
        CurveType::Secp256r1 => {
            let (sk, pk) = Secp256r1Curve::generate_keypair(seed)?;
            Ok((sk.to_vec(), pk.to_vec()))
        }
    }
}

/// Derive public key from private key
pub fn public_key_from_private(curve: CurveType, private_key: &[u8]) -> Result<Vec<u8>, CurveError> {
    match curve {
        CurveType::Secp256k1 => {
            let pk = Secp256k1Curve::public_key_from_private(private_key)?;
            Ok(pk.to_vec())
        }
        CurveType::Ed25519 => {
            let pk = Ed25519Curve::public_key_from_private(private_key)?;
            Ok(pk.to_vec())
        }
        CurveType::Sr25519 => {
            let pk = Sr25519Curve::public_key_from_private(private_key)?;
            Ok(pk.to_vec())
        }
        CurveType::Secp256r1 => {
            let pk = Secp256r1Curve::public_key_from_private(private_key)?;
            Ok(pk.to_vec())
        }
    }
}

/// Sign a message with the specified curve
pub fn sign(curve: CurveType, private_key: &[u8], message: &[u8]) -> Result<Vec<u8>, CurveError> {
    match curve {
        CurveType::Secp256k1 => {
            let sig = Secp256k1Curve::sign(private_key, message)?;
            Ok(sig.to_vec())
        }
        CurveType::Ed25519 => {
            let sig = Ed25519Curve::sign(private_key, message)?;
            Ok(sig.to_vec())
        }
        CurveType::Sr25519 => {
            let sig = Sr25519Curve::sign(private_key, message)?;
            Ok(sig.to_vec())
        }
        CurveType::Secp256r1 => {
            let sig = Secp256r1Curve::sign(private_key, message)?;
            Ok(sig.to_vec())
        }
    }
}

/// Verify a signature with the specified curve
pub fn verify(curve: CurveType, public_key: &[u8], message: &[u8], signature: &[u8]) -> Result<bool, CurveError> {
    match curve {
        CurveType::Secp256k1 => Secp256k1Curve::verify(public_key, message, signature),
        CurveType::Ed25519 => Ed25519Curve::verify(public_key, message, signature),
        CurveType::Sr25519 => Sr25519Curve::verify(public_key, message, signature),
        CurveType::Secp256r1 => Secp256r1Curve::verify(public_key, message, signature),
    }
}

/// Sign a message and return both signature and public key
pub fn sign_with_pubkey(
    curve: CurveType,
    private_key: &[u8],
    message: &[u8],
) -> Result<(Vec<u8>, Vec<u8>), CurveError> {
    let signature = sign(curve, private_key, message)?;
    let public_key = public_key_from_private(curve, private_key)?;
    Ok((signature, public_key))
}

// MARK: - Tests

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_curve_type_properties() {
        assert_eq!(CurveType::Secp256k1.name(), "secp256k1");
        assert_eq!(CurveType::Ed25519.name(), "ed25519");
        assert_eq!(CurveType::Sr25519.name(), "sr25519");
        assert_eq!(CurveType::Secp256r1.name(), "secp256r1");
        
        assert_eq!(CurveType::Secp256k1.private_key_size(), 32);
        assert_eq!(CurveType::Ed25519.public_key_size(), 32);
    }
    
    #[test]
    fn test_curve_type_from_str() {
        assert_eq!(CurveType::from_str("secp256k1"), Some(CurveType::Secp256k1));
        assert_eq!(CurveType::from_str("Ed25519"), Some(CurveType::Ed25519));
        assert_eq!(CurveType::from_str("P256"), Some(CurveType::Secp256r1));
        assert_eq!(CurveType::from_str("invalid"), None);
    }
}
