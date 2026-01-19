//! Pre-Image Hash Generation
//!
//! Generates the hash that needs to be signed for each chain type.

pub mod bitcoin;
pub mod ethereum;
pub mod cosmos;
pub mod solana;

use serde::{Deserialize, Serialize};

/// A pre-image hash with metadata for signing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PreImageHash {
    /// The hash to sign (32 bytes)
    pub hash: [u8; 32],
    
    /// Public key hash or address that should sign this
    pub signer_id: String,
    
    /// For UTXO chains: which input index this is for
    pub input_index: Option<usize>,
    
    /// Human-readable description
    pub description: String,
    
    /// Signing algorithm to use
    pub algorithm: SigningAlgorithm,
}

impl PreImageHash {
    pub fn new(hash: [u8; 32], signer_id: String, algorithm: SigningAlgorithm) -> Self {
        Self {
            hash,
            signer_id,
            input_index: None,
            description: String::new(),
            algorithm,
        }
    }
    
    pub fn with_input_index(mut self, index: usize) -> Self {
        self.input_index = Some(index);
        self
    }
    
    pub fn with_description(mut self, desc: impl Into<String>) -> Self {
        self.description = desc.into();
        self
    }
    
    /// Get hash as hex string
    pub fn hash_hex(&self) -> String {
        format!("0x{}", hex::encode(self.hash))
    }
}

/// Signing algorithm type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SigningAlgorithm {
    /// secp256k1 ECDSA (Bitcoin, Ethereum)
    Secp256k1Ecdsa,
    /// secp256k1 Schnorr (Bitcoin Taproot)
    Secp256k1Schnorr,
    /// Ed25519 (Solana, Cosmos with certain key types)
    Ed25519,
}

/// External signature (result of signing a pre-image hash)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExternalSignature {
    /// The signature bytes
    pub signature: Vec<u8>,
    
    /// Recovery ID for ECDSA (optional)
    pub recovery_id: Option<u8>,
    
    /// Which input this signature is for (UTXO chains)
    pub input_index: Option<usize>,
    
    /// Public key that created this signature
    pub public_key: Vec<u8>,
}

impl ExternalSignature {
    pub fn new(signature: Vec<u8>, public_key: Vec<u8>) -> Self {
        Self {
            signature,
            recovery_id: None,
            input_index: None,
            public_key,
        }
    }
    
    pub fn with_recovery_id(mut self, v: u8) -> Self {
        self.recovery_id = Some(v);
        self
    }
    
    pub fn with_input_index(mut self, index: usize) -> Self {
        self.input_index = Some(index);
        self
    }
    
    /// Get signature as hex
    pub fn signature_hex(&self) -> String {
        format!("0x{}", hex::encode(&self.signature))
    }
    
    /// Get 65-byte signature (r || s || v) for EVM
    pub fn to_rsv(&self) -> Option<[u8; 65]> {
        if self.signature.len() < 64 {
            return None;
        }
        let mut rsv = [0u8; 65];
        rsv[..64].copy_from_slice(&self.signature[..64]);
        rsv[64] = self.recovery_id.unwrap_or(27);
        Some(rsv)
    }
}

/// Error types for pre-image operations
#[derive(Debug, thiserror::Error)]
pub enum PreImageError {
    #[error("Invalid transaction format: {0}")]
    InvalidTransaction(String),
    
    #[error("Unsupported transaction type: {0}")]
    UnsupportedType(String),
    
    #[error("Missing required field: {0}")]
    MissingField(String),
    
    #[error("Invalid input index: {0}")]
    InvalidInputIndex(usize),
    
    #[error("Encoding error: {0}")]
    EncodingError(String),
    
    #[error("Invalid signature: {0}")]
    InvalidSignature(String),
    
    #[error("Public key mismatch")]
    PublicKeyMismatch,
}

pub type PreImageResult<T> = Result<T, PreImageError>;

// Re-export chain-specific functions
pub use bitcoin::{
    get_bitcoin_sighashes,
    BitcoinSigHashType,
};
pub use ethereum::get_ethereum_signing_hash;
pub use cosmos::get_cosmos_sign_doc_hash;
pub use solana::get_solana_message_hash;
