//! QR Code Types and Data Structures
//!
//! Common types used across the QR module.

use serde::{Deserialize, Serialize};

/// A single QR code frame
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QrFrame {
    /// Frame index (0-based)
    pub index: usize,
    /// Total number of frames
    pub total: usize,
    /// Frame data (base64 or hex encoded)
    pub data: String,
    /// Checksum of this frame
    pub checksum: u32,
}

impl QrFrame {
    /// Create a new QR frame
    pub fn new(index: usize, total: usize, data: String) -> Self {
        let checksum = crc32fast::hash(data.as_bytes());
        Self {
            index,
            total,
            data,
            checksum,
        }
    }
    
    /// Verify frame checksum
    pub fn verify_checksum(&self) -> bool {
        crc32fast::hash(self.data.as_bytes()) == self.checksum
    }
}

/// Multi-part message header
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MultiPartHeader {
    /// Message UUID
    pub message_id: String,
    /// Total parts
    pub total_parts: usize,
    /// Total payload size
    pub total_size: usize,
    /// Content type
    pub content_type: ContentType,
    /// Checksum of complete payload
    pub checksum: u32,
}

/// Content types for QR payloads
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ContentType {
    /// Raw bytes
    RawBytes,
    /// JSON data
    Json,
    /// CBOR data
    Cbor,
    /// Bitcoin PSBT
    Psbt,
    /// Ethereum transaction
    EthTransaction,
    /// Signed transaction
    SignedTransaction,
    /// Signature only
    Signature,
    /// Public key
    PublicKey,
    /// Account info
    AccountInfo,
}

impl ContentType {
    /// Get MIME-like string for content type
    pub fn as_str(&self) -> &'static str {
        match self {
            ContentType::RawBytes => "application/octet-stream",
            ContentType::Json => "application/json",
            ContentType::Cbor => "application/cbor",
            ContentType::Psbt => "application/x-psbt",
            ContentType::EthTransaction => "application/x-eth-tx",
            ContentType::SignedTransaction => "application/x-signed-tx",
            ContentType::Signature => "application/x-signature",
            ContentType::PublicKey => "application/x-public-key",
            ContentType::AccountInfo => "application/x-account-info",
        }
    }
}

/// Animated QR display settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnimationSettings {
    /// Frames per second
    pub fps: u32,
    /// Fragment size in bytes
    pub fragment_size: usize,
    /// Number of extra fountain code frames
    pub redundancy_frames: usize,
    /// Loop animation
    pub loop_animation: bool,
}

impl Default for AnimationSettings {
    fn default() -> Self {
        Self {
            fps: 8,
            fragment_size: 100,
            redundancy_frames: 10,
            loop_animation: true,
        }
    }
}

/// QR code generation options
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QrOptions {
    /// Error correction level
    pub error_correction: super::ErrorCorrectionLevel,
    /// Animation settings (for multi-part)
    pub animation: AnimationSettings,
    /// Use uppercase for alphanumeric mode
    pub uppercase: bool,
    /// Minimum QR version (1-40)
    pub min_version: u8,
}

impl Default for QrOptions {
    fn default() -> Self {
        Self {
            error_correction: super::ErrorCorrectionLevel::M,
            animation: AnimationSettings::default(),
            uppercase: true,
            min_version: 1,
        }
    }
}

/// Scan result from QR decoder
#[derive(Debug, Clone)]
pub enum ScanResult {
    /// Complete single-frame result
    Complete(Vec<u8>),
    /// Partial multi-frame result
    Partial {
        /// Number of frames received
        received: usize,
        /// Total frames expected
        total: usize,
        /// Estimated completion percentage
        progress: f32,
    },
    /// Fountain code progress
    Fountain {
        /// Estimated completion percentage
        progress: f32,
        /// Whether decoding is possible
        can_decode: bool,
    },
}

/// Bytewords encoding style
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BytewordsStyle {
    /// Standard format: "able acid also..."
    Standard,
    /// Minimal format: "aeadao..."
    Minimal,
    /// URI format: "able-acid-also-..."
    Uri,
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_qr_frame() {
        let frame = QrFrame::new(0, 3, "test data".to_string());
        
        assert_eq!(frame.index, 0);
        assert_eq!(frame.total, 3);
        assert!(frame.verify_checksum());
    }
    
    #[test]
    fn test_content_type() {
        assert_eq!(ContentType::Psbt.as_str(), "application/x-psbt");
        assert_eq!(ContentType::Json.as_str(), "application/json");
    }
    
    #[test]
    fn test_animation_defaults() {
        let settings = AnimationSettings::default();
        
        assert_eq!(settings.fps, 8);
        assert_eq!(settings.fragment_size, 100);
        assert!(settings.loop_animation);
    }
}
