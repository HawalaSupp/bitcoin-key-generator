//! Message Signing Module
//!
//! Implements personal message signing for multiple blockchain networks.
//! Each chain has its own signing format and prefix requirements.
//!
//! Supported chains:
//! - Ethereum (EIP-191 personal_sign)
//! - Tezos (Micheline format)
//! - Solana (Ed25519 direct)
//! - Cosmos (ADR-036)

pub mod ethereum;
pub mod tezos;
pub mod solana;
pub mod cosmos;

// Note: Using qualified exports to avoid ambiguous function names
// Each module has different naming conventions for their signing functions
pub use ethereum::{personal_sign as sign_ethereum_message, verify_personal_sign as verify_ethereum_message, recover_address as recover_ethereum_address};
pub use tezos::{sign_message as sign_tezos_message, verify_message as verify_tezos_message};
pub use solana::{sign_message as sign_solana_message, verify_message as verify_solana_message, get_public_key as get_solana_public_key};
pub use cosmos::{sign_arbitrary as sign_cosmos_message, verify_arbitrary as verify_cosmos_message, get_public_key as get_cosmos_public_key};

use serde::{Deserialize, Serialize};

/// Unified message signature result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageSignature {
    /// The signature bytes as hex string
    pub signature: String,
    /// Recovery ID (v value) for ECDSA, None for Ed25519
    pub recovery_id: Option<u8>,
    /// R component (for ECDSA)
    pub r: Option<String>,
    /// S component (for ECDSA)
    pub s: Option<String>,
    /// V value with EIP-155 chain ID (for Ethereum)
    pub v: Option<u8>,
}

impl MessageSignature {
    /// Create a new ECDSA signature
    pub fn ecdsa(r: [u8; 32], s: [u8; 32], v: u8) -> Self {
        let mut sig = [0u8; 65];
        sig[..32].copy_from_slice(&r);
        sig[32..64].copy_from_slice(&s);
        sig[64] = v;
        
        Self {
            signature: format!("0x{}", hex::encode(sig)),
            recovery_id: Some(v - 27),
            r: Some(format!("0x{}", hex::encode(r))),
            s: Some(format!("0x{}", hex::encode(s))),
            v: Some(v),
        }
    }
    
    /// Create a new Ed25519 signature
    pub fn ed25519(sig: [u8; 64]) -> Self {
        Self {
            signature: format!("0x{}", hex::encode(sig)),
            recovery_id: None,
            r: None,
            s: None,
            v: None,
        }
    }
    
    /// Create from raw bytes with recovery id
    pub fn from_bytes(sig: &[u8], recovery_id: u8) -> Self {
        if sig.len() == 64 {
            let mut r = [0u8; 32];
            let mut s = [0u8; 32];
            r.copy_from_slice(&sig[..32]);
            s.copy_from_slice(&sig[32..]);
            Self::ecdsa(r, s, recovery_id + 27)
        } else {
            Self {
                signature: format!("0x{}", hex::encode(sig)),
                recovery_id: Some(recovery_id),
                r: None,
                s: None,
                v: Some(recovery_id + 27),
            }
        }
    }
}

/// Error types for message signing
#[derive(Debug, thiserror::Error)]
pub enum MessageSignError {
    #[error("Invalid private key: {0}")]
    InvalidPrivateKey(String),
    
    #[error("Invalid signature: {0}")]
    InvalidSignature(String),
    
    #[error("Invalid message: {0}")]
    InvalidMessage(String),
    
    #[error("Signature verification failed")]
    VerificationFailed,
    
    #[error("Address recovery failed: {0}")]
    RecoveryFailed(String),
    
    #[error("Unsupported chain: {0}")]
    UnsupportedChain(String),
    
    #[error("Encoding error: {0}")]
    EncodingError(String),
}

pub type MessageSignResult<T> = Result<T, MessageSignError>;
