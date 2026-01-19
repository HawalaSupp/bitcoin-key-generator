//! Elliptic Curve Traits
//!
//! Defines the common interface for all elliptic curve implementations.

use super::CurveError;

/// Core trait for elliptic curve operations
pub trait EllipticCurve {
    /// The private key type
    type PrivateKey: AsRef<[u8]>;
    /// The public key type
    type PublicKey: AsRef<[u8]>;
    /// The signature type
    type Signature: AsRef<[u8]>;
    
    /// Generate a keypair from a 32-byte seed
    fn generate_keypair(seed: &[u8]) -> Result<(Self::PrivateKey, Self::PublicKey), CurveError>;
    
    /// Derive the public key from a private key
    fn public_key_from_private(private_key: &[u8]) -> Result<Self::PublicKey, CurveError>;
    
    /// Sign a message with a private key
    fn sign(private_key: &[u8], message: &[u8]) -> Result<Self::Signature, CurveError>;
    
    /// Verify a signature
    fn verify(public_key: &[u8], message: &[u8], signature: &[u8]) -> Result<bool, CurveError>;
}

/// Extended trait for curves that support recoverable signatures
pub trait RecoverableSignature: EllipticCurve {
    /// Sign with recovery ID (v, r, s format)
    fn sign_recoverable(private_key: &[u8], message: &[u8]) -> Result<(Self::Signature, u8), CurveError>;
    
    /// Recover public key from signature and message
    fn recover_public_key(message: &[u8], signature: &[u8], recovery_id: u8) -> Result<Self::PublicKey, CurveError>;
}

/// Extended trait for curves that support ECDH key exchange
pub trait KeyExchange: EllipticCurve {
    /// Perform ECDH to derive shared secret
    fn ecdh(private_key: &[u8], other_public_key: &[u8]) -> Result<[u8; 32], CurveError>;
}

/// Extended trait for curves that support key derivation
pub trait KeyDerivation: EllipticCurve {
    /// Derive a child key from parent using BIP-32 or similar
    fn derive_child(
        parent_private: &[u8],
        parent_chain_code: &[u8],
        index: u32,
        hardened: bool,
    ) -> Result<([u8; 32], [u8; 32]), CurveError>;
    
    /// Derive from path string (e.g., "m/44'/0'/0'/0/0")
    fn derive_path(seed: &[u8], path: &str) -> Result<(Vec<u8>, Vec<u8>), CurveError>;
}

/// Signature encoding formats
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SignatureFormat {
    /// Raw r,s (64 bytes)
    Raw,
    /// DER encoded
    Der,
    /// Recoverable with v byte (65 bytes)
    Recoverable,
    /// Compact (64 bytes with recovery embedded)
    Compact,
}

/// Public key encoding formats
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PublicKeyFormat {
    /// Compressed (33 bytes for secp256k1/r1)
    Compressed,
    /// Uncompressed (65 bytes for secp256k1/r1)
    Uncompressed,
    /// Raw (32 bytes for ed25519/sr25519)
    Raw,
}
