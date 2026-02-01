//! QR Code Encoder
//!
//! Encodes data into QR code format, supporting both single and multi-part encoding.

#![allow(unused_imports)]

use super::{
    types::{QrFrame, MultiPartHeader, ContentType, QrOptions, AnimationSettings},
    ErrorCorrectionLevel, QrError, QrResult, RECOMMENDED_FRAGMENT_SIZE,
};
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use serde::{Deserialize, Serialize};

/// QR Code Encoder
pub struct QrEncoder {
    options: QrOptions,
}

impl QrEncoder {
    /// Create a new encoder with default options
    pub fn new() -> Self {
        Self {
            options: QrOptions::default(),
        }
    }
    
    /// Create encoder with custom options
    pub fn with_options(options: QrOptions) -> Self {
        Self { options }
    }
    
    /// Encode data for QR display
    /// Returns a list of frame strings to display
    pub fn encode(&self, data: &[u8], content_type: ContentType) -> QrResult<Vec<String>> {
        let max_bytes = self.options.error_correction.max_bytes();
        
        // Calculate base64 overhead
        let encoded_size = (data.len() * 4 + 2) / 3;
        
        if encoded_size <= max_bytes - 50 { // Reserve space for header
            // Single frame
            self.encode_single(data, content_type)
        } else {
            // Multi-part
            self.encode_multipart(data, content_type)
        }
    }
    
    /// Encode as a single QR code
    fn encode_single(&self, data: &[u8], content_type: ContentType) -> QrResult<Vec<String>> {
        let encoded = BASE64.encode(data);
        
        let frame = SingleFrame {
            content_type: content_type.as_str().to_string(),
            data: encoded,
            checksum: crc32fast::hash(data),
        };
        
        let json = serde_json::to_string(&frame)
            .map_err(|e| QrError::InvalidData(e.to_string()))?;
        
        Ok(vec![json])
    }
    
    /// Encode as multi-part QR codes
    fn encode_multipart(&self, data: &[u8], content_type: ContentType) -> QrResult<Vec<String>> {
        let fragment_size = self.options.animation.fragment_size;
        let total_parts = (data.len() + fragment_size - 1) / fragment_size;
        
        let message_id = generate_message_id();
        let checksum = crc32fast::hash(data);
        
        let mut frames = Vec::with_capacity(total_parts);
        
        for i in 0..total_parts {
            let start = i * fragment_size;
            let end = std::cmp::min(start + fragment_size, data.len());
            let chunk = &data[start..end];
            
            let frame = MultiPartFrame {
                message_id: message_id.clone(),
                part: i,
                total: total_parts,
                total_size: data.len(),
                content_type: content_type.as_str().to_string(),
                data: BASE64.encode(chunk),
                checksum: if i == total_parts - 1 { Some(checksum) } else { None },
            };
            
            let json = serde_json::to_string(&frame)
                .map_err(|e| QrError::InvalidData(e.to_string()))?;
            
            frames.push(json);
        }
        
        Ok(frames)
    }
    
    /// Encode with fountain codes for better reliability
    pub fn encode_fountain(&self, data: &[u8], content_type: ContentType) -> QrResult<Vec<String>> {
        let encoder = super::fountain::FountainEncoder::new(
            data,
            self.options.animation.fragment_size,
        );
        
        let total_frames = encoder.fragment_count() + self.options.animation.redundancy_frames;
        let mut frames = Vec::with_capacity(total_frames);
        
        let message_id = generate_message_id();
        let checksum = crc32fast::hash(data);
        
        for seq in 0..total_frames {
            let part = encoder.next_part(seq);
            
            let frame = FountainFrame {
                message_id: message_id.clone(),
                seq,
                fragment_count: encoder.fragment_count(),
                message_len: data.len(),
                content_type: content_type.as_str().to_string(),
                indexes: part.indexes.clone(),
                data: BASE64.encode(&part.data),
                checksum,
            };
            
            let json = serde_json::to_string(&frame)
                .map_err(|e| QrError::InvalidData(e.to_string()))?;
            
            frames.push(json);
        }
        
        Ok(frames)
    }
    
    /// Encode a PSBT for air-gapped signing
    pub fn encode_psbt(&self, psbt_bytes: &[u8]) -> QrResult<Vec<String>> {
        self.encode_fountain(psbt_bytes, ContentType::Psbt)
    }
    
    /// Encode an Ethereum transaction
    pub fn encode_eth_transaction(&self, tx_bytes: &[u8]) -> QrResult<Vec<String>> {
        self.encode(tx_bytes, ContentType::EthTransaction)
    }
    
    /// Encode a signature response
    pub fn encode_signature(&self, signature: &[u8]) -> QrResult<Vec<String>> {
        self.encode(signature, ContentType::Signature)
    }
    
    /// Encode account info
    pub fn encode_account_info(&self, info: &AccountInfo) -> QrResult<Vec<String>> {
        let json = serde_json::to_vec(info)
            .map_err(|e| QrError::InvalidData(e.to_string()))?;
        self.encode(&json, ContentType::AccountInfo)
    }
}

impl Default for QrEncoder {
    fn default() -> Self {
        Self::new()
    }
}

/// Single frame format
#[derive(Debug, Clone, Serialize, Deserialize)]
struct SingleFrame {
    content_type: String,
    data: String,
    checksum: u32,
}

/// Multi-part frame format
#[derive(Debug, Clone, Serialize, Deserialize)]
struct MultiPartFrame {
    message_id: String,
    part: usize,
    total: usize,
    total_size: usize,
    content_type: String,
    data: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    checksum: Option<u32>,
}

/// Fountain code frame format
#[derive(Debug, Clone, Serialize, Deserialize)]
struct FountainFrame {
    message_id: String,
    seq: usize,
    fragment_count: usize,
    message_len: usize,
    content_type: String,
    indexes: Vec<usize>,
    data: String,
    checksum: u32,
}

/// Account information for QR export
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccountInfo {
    /// Account name
    pub name: String,
    /// Chain type
    pub chain: String,
    /// Public key (hex)
    pub public_key: String,
    /// Address
    pub address: String,
    /// Derivation path
    pub derivation_path: String,
    /// Master fingerprint (for PSBT)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub master_fingerprint: Option<String>,
}

/// Generate a unique message ID
fn generate_message_id() -> String {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    let id: u64 = rng.gen();
    format!("{:016x}", id)
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_encode_small_data() {
        let encoder = QrEncoder::new();
        let data = b"Hello, World!";
        
        let frames = encoder.encode(data, ContentType::RawBytes).unwrap();
        
        assert_eq!(frames.len(), 1);
        // Content is base64 encoded, check for JSON structure
        assert!(frames[0].contains("content_type"));
        assert!(frames[0].contains("data"));
    }
    
    #[test]
    fn test_encode_multipart() {
        let encoder = QrEncoder::with_options(QrOptions {
            animation: AnimationSettings {
                fragment_size: 10,
                ..Default::default()
            },
            error_correction: super::super::ErrorCorrectionLevel::M,
            ..Default::default()
        });
        
        // Use much larger data to force multipart (base64 expands, so need larger raw data)
        let data: Vec<u8> = (0..2500).map(|i| (i % 256) as u8).collect();
        let frames = encoder.encode(&data, ContentType::RawBytes).unwrap();
        
        assert!(frames.len() > 1, "Expected multiple frames, got {}", frames.len());
        
        // Verify all parts are present
        for (i, frame) in frames.iter().enumerate() {
            let parsed: MultiPartFrame = serde_json::from_str(frame).unwrap();
            assert_eq!(parsed.part, i);
            assert_eq!(parsed.total, frames.len());
        }
    }
    
    #[test]
    fn test_encode_psbt() {
        let encoder = QrEncoder::with_options(QrOptions {
            animation: AnimationSettings {
                fragment_size: 50,
                redundancy_frames: 5,
                ..Default::default()
            },
            ..Default::default()
        });
        
        // Mock PSBT data
        let psbt = vec![0x70, 0x73, 0x62, 0x74, 0xff]; // "psbt" magic + separator
        let frames = encoder.encode_psbt(&psbt).unwrap();
        
        assert!(!frames.is_empty());
    }
    
    #[test]
    fn test_encode_account_info() {
        let encoder = QrEncoder::new();
        
        let info = AccountInfo {
            name: "Bitcoin Account".to_string(),
            chain: "bitcoin".to_string(),
            public_key: "02...".to_string(),
            address: "bc1q...".to_string(),
            derivation_path: "m/84'/0'/0'".to_string(),
            master_fingerprint: Some("12345678".to_string()),
        };
        
        let frames = encoder.encode_account_info(&info).unwrap();
        
        assert_eq!(frames.len(), 1);
        // Content is base64 encoded inside JSON
        assert!(frames[0].contains("content_type"));
    }
}
