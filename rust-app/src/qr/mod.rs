//! QR Code Support for Air-Gapped Signing
//!
//! This module provides QR code encoding/decoding for air-gapped wallet operations.
//! Supports both static QR codes and animated fountain codes for large payloads.
//!
//! # Features
//! - Static QR encoding for small payloads (< 2KB)
//! - Animated QR fountain codes (BC-UR) for large payloads
//! - CBOR encoding for efficient binary data
//! - CRC32 checksums for data integrity
//! - Multi-part message assembly
//!
//! # Standards
//! - BC-UR: Blockchain Commons Uniform Resources
//! - UR Types: crypto-psbt, crypto-account, crypto-hdkey, crypto-output
//!
//! # Usage
//! ```rust,ignore
//! use rust_app::qr::{QrEncoder, QrDecoder, UrType};
//!
//! // Encode a PSBT for air-gapped signing
//! let psbt_bytes = vec![...];
//! let ur_frames = QrEncoder::encode_ur(UrType::CryptoPsbt, &psbt_bytes);
//!
//! // Decode received frames
//! let mut decoder = QrDecoder::new();
//! for frame in received_frames {
//!     if decoder.receive_part(&frame)? {
//!         let data = decoder.result()?;
//!         break;
//!     }
//! }
//! ```

pub mod encoder;
pub mod decoder;
pub mod fountain;
pub mod ur;
pub mod types;

pub use encoder::QrEncoder;
pub use decoder::QrDecoder;
pub use fountain::{FountainEncoder, FountainDecoder};
pub use ur::{UrEncoder, UrDecoder, UrType};
pub use types::*;

use serde::{Deserialize, Serialize};
use thiserror::Error;

/// QR module errors
#[derive(Error, Debug)]
pub enum QrError {
    #[error("Payload too large for single QR code: {0} bytes (max {1})")]
    PayloadTooLarge(usize, usize),
    
    #[error("Invalid QR data: {0}")]
    InvalidData(String),
    
    #[error("Checksum mismatch")]
    ChecksumMismatch,
    
    #[error("Incomplete message: received {0}/{1} parts")]
    IncompleteMessage(usize, usize),
    
    #[error("Invalid UR format: {0}")]
    InvalidUrFormat(String),
    
    #[error("CBOR encoding error: {0}")]
    CborError(String),
    
    #[error("Unsupported UR type: {0}")]
    UnsupportedUrType(String),
    
    #[error("Fountain code error: {0}")]
    FountainError(String),
    
    #[error("Decoding incomplete")]
    DecodingIncomplete,
}

/// Result type for QR operations
pub type QrResult<T> = Result<T, QrError>;

/// Maximum bytes for a single QR code at error correction level L
pub const MAX_QR_BYTES_L: usize = 2953;
/// Maximum bytes for a single QR code at error correction level M  
pub const MAX_QR_BYTES_M: usize = 2331;
/// Maximum bytes for a single QR code at error correction level Q
pub const MAX_QR_BYTES_Q: usize = 1663;
/// Maximum bytes for a single QR code at error correction level H
pub const MAX_QR_BYTES_H: usize = 1273;

/// Recommended fragment size for animated QR codes
pub const RECOMMENDED_FRAGMENT_SIZE: usize = 100;

/// QR code error correction level
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ErrorCorrectionLevel {
    /// Low (~7% recovery)
    L,
    /// Medium (~15% recovery)
    M,
    /// Quartile (~25% recovery)
    Q,
    /// High (~30% recovery)
    H,
}

impl ErrorCorrectionLevel {
    /// Maximum bytes for this error correction level
    pub fn max_bytes(&self) -> usize {
        match self {
            ErrorCorrectionLevel::L => MAX_QR_BYTES_L,
            ErrorCorrectionLevel::M => MAX_QR_BYTES_M,
            ErrorCorrectionLevel::Q => MAX_QR_BYTES_Q,
            ErrorCorrectionLevel::H => MAX_QR_BYTES_H,
        }
    }
}

impl Default for ErrorCorrectionLevel {
    fn default() -> Self {
        ErrorCorrectionLevel::M
    }
}

/// Air-gapped signing request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AirGapRequest {
    /// Request type
    pub request_type: AirGapRequestType,
    /// Chain identifier
    pub chain: String,
    /// Request ID for matching response
    pub request_id: String,
    /// Payload data (transaction, message, etc.)
    pub payload: Vec<u8>,
    /// Optional metadata
    pub metadata: Option<serde_json::Value>,
}

/// Air-gapped signing response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AirGapResponse {
    /// Request ID this responds to
    pub request_id: String,
    /// Signature(s)
    pub signatures: Vec<Vec<u8>>,
    /// Optional public key
    pub public_key: Option<Vec<u8>>,
    /// Optional metadata
    pub metadata: Option<serde_json::Value>,
}

/// Types of air-gapped requests
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum AirGapRequestType {
    /// Sign a raw transaction
    SignTransaction,
    /// Sign a PSBT (Bitcoin)
    SignPsbt,
    /// Sign a message
    SignMessage,
    /// Sign typed data (EIP-712)
    SignTypedData,
    /// Request account info
    GetAccount,
    /// Request public key
    GetPublicKey,
}

impl AirGapRequest {
    /// Create a new sign transaction request
    pub fn sign_transaction(chain: &str, tx_bytes: Vec<u8>) -> Self {
        Self {
            request_type: AirGapRequestType::SignTransaction,
            chain: chain.to_string(),
            request_id: generate_request_id(),
            payload: tx_bytes,
            metadata: None,
        }
    }
    
    /// Create a new sign PSBT request
    pub fn sign_psbt(psbt_bytes: Vec<u8>) -> Self {
        Self {
            request_type: AirGapRequestType::SignPsbt,
            chain: "bitcoin".to_string(),
            request_id: generate_request_id(),
            payload: psbt_bytes,
            metadata: None,
        }
    }
    
    /// Create a new sign message request
    pub fn sign_message(chain: &str, message: &[u8]) -> Self {
        Self {
            request_type: AirGapRequestType::SignMessage,
            chain: chain.to_string(),
            request_id: generate_request_id(),
            payload: message.to_vec(),
            metadata: None,
        }
    }
    
    /// Create a new sign typed data request
    pub fn sign_typed_data(chain: &str, typed_data: &[u8]) -> Self {
        Self {
            request_type: AirGapRequestType::SignTypedData,
            chain: chain.to_string(),
            request_id: generate_request_id(),
            payload: typed_data.to_vec(),
            metadata: None,
        }
    }
}

/// Generate a unique request ID
fn generate_request_id() -> String {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    let id: u64 = rng.gen();
    format!("{:016x}", id)
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_error_correction_max_bytes() {
        assert_eq!(ErrorCorrectionLevel::L.max_bytes(), 2953);
        assert_eq!(ErrorCorrectionLevel::M.max_bytes(), 2331);
        assert_eq!(ErrorCorrectionLevel::Q.max_bytes(), 1663);
        assert_eq!(ErrorCorrectionLevel::H.max_bytes(), 1273);
    }
    
    #[test]
    fn test_air_gap_request_creation() {
        let request = AirGapRequest::sign_transaction("ethereum", vec![1, 2, 3]);
        
        assert_eq!(request.request_type, AirGapRequestType::SignTransaction);
        assert_eq!(request.chain, "ethereum");
        assert_eq!(request.payload, vec![1, 2, 3]);
        assert!(!request.request_id.is_empty());
    }
    
    #[test]
    fn test_air_gap_psbt_request() {
        let psbt = vec![0x70, 0x73, 0x62, 0x74]; // "psbt" magic
        let request = AirGapRequest::sign_psbt(psbt.clone());
        
        assert_eq!(request.request_type, AirGapRequestType::SignPsbt);
        assert_eq!(request.chain, "bitcoin");
        assert_eq!(request.payload, psbt);
    }
}
