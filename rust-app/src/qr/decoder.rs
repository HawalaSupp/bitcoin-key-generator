//! QR Code Decoder
//!
//! Decodes QR code data, supporting both single and multi-part decoding.

use super::{
    types::{ContentType, ScanResult},
    QrError, QrResult,
};
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// QR Code Decoder
pub struct QrDecoder {
    /// Pending multi-part messages
    pending: HashMap<String, PendingMessage>,
    /// Fountain decoder (if active)
    fountain_decoder: Option<super::fountain::FountainDecoder>,
    /// Current message ID for fountain decoding
    fountain_message_id: Option<String>,
}

impl QrDecoder {
    /// Create a new decoder
    pub fn new() -> Self {
        Self {
            pending: HashMap::new(),
            fountain_decoder: None,
            fountain_message_id: None,
        }
    }
    
    /// Reset decoder state
    pub fn reset(&mut self) {
        self.pending.clear();
        self.fountain_decoder = None;
        self.fountain_message_id = None;
    }
    
    /// Decode a scanned QR code string
    /// Returns the complete data if all parts received, or progress info
    pub fn decode(&mut self, qr_data: &str) -> QrResult<ScanResult> {
        // Try to parse as JSON
        let value: serde_json::Value = serde_json::from_str(qr_data)
            .map_err(|e| QrError::InvalidData(format!("Invalid JSON: {}", e)))?;
        
        // Determine frame type
        if value.get("indexes").is_some() {
            // Fountain code frame
            self.decode_fountain_frame(qr_data)
        } else if value.get("message_id").is_some() && value.get("part").is_some() {
            // Multi-part frame
            self.decode_multipart_frame(qr_data)
        } else if value.get("data").is_some() {
            // Single frame
            self.decode_single_frame(qr_data)
        } else {
            Err(QrError::InvalidData("Unknown frame format".to_string()))
        }
    }
    
    /// Decode a single frame
    fn decode_single_frame(&self, qr_data: &str) -> QrResult<ScanResult> {
        let frame: SingleFrame = serde_json::from_str(qr_data)
            .map_err(|e| QrError::InvalidData(e.to_string()))?;
        
        let data = BASE64.decode(&frame.data)
            .map_err(|e| QrError::InvalidData(format!("Base64 decode error: {}", e)))?;
        
        // Verify checksum
        let checksum = crc32fast::hash(&data);
        if checksum != frame.checksum {
            return Err(QrError::ChecksumMismatch);
        }
        
        Ok(ScanResult::Complete(data))
    }
    
    /// Decode a multi-part frame
    fn decode_multipart_frame(&mut self, qr_data: &str) -> QrResult<ScanResult> {
        let frame: MultiPartFrame = serde_json::from_str(qr_data)
            .map_err(|e| QrError::InvalidData(e.to_string()))?;
        
        let data = BASE64.decode(&frame.data)
            .map_err(|e| QrError::InvalidData(format!("Base64 decode error: {}", e)))?;
        
        // Get or create pending message
        let pending = self.pending
            .entry(frame.message_id.clone())
            .or_insert_with(|| PendingMessage {
                total_parts: frame.total,
                total_size: frame.total_size,
                content_type: frame.content_type.clone(),
                parts: HashMap::new(),
                expected_checksum: None,
            });
        
        // Store this part
        pending.parts.insert(frame.part, data);
        
        // Update checksum if this is the last part
        if let Some(checksum) = frame.checksum {
            pending.expected_checksum = Some(checksum);
        }
        
        // Check if complete
        if pending.parts.len() == pending.total_parts {
            let message = self.assemble_multipart(&frame.message_id)?;
            self.pending.remove(&frame.message_id);
            Ok(ScanResult::Complete(message))
        } else {
            Ok(ScanResult::Partial {
                received: pending.parts.len(),
                total: pending.total_parts,
                progress: pending.parts.len() as f32 / pending.total_parts as f32,
            })
        }
    }
    
    /// Assemble multi-part message
    fn assemble_multipart(&self, message_id: &str) -> QrResult<Vec<u8>> {
        let pending = self.pending.get(message_id)
            .ok_or_else(|| QrError::InvalidData("Message not found".to_string()))?;
        
        let mut result = Vec::with_capacity(pending.total_size);
        
        for i in 0..pending.total_parts {
            let part = pending.parts.get(&i)
                .ok_or_else(|| QrError::IncompleteMessage(pending.parts.len(), pending.total_parts))?;
            result.extend_from_slice(part);
        }
        
        // Verify checksum if present
        if let Some(expected) = pending.expected_checksum {
            let actual = crc32fast::hash(&result);
            if actual != expected {
                return Err(QrError::ChecksumMismatch);
            }
        }
        
        Ok(result)
    }
    
    /// Decode a fountain code frame
    fn decode_fountain_frame(&mut self, qr_data: &str) -> QrResult<ScanResult> {
        let frame: FountainFrame = serde_json::from_str(qr_data)
            .map_err(|e| QrError::InvalidData(e.to_string()))?;
        
        // Initialize decoder if needed
        if self.fountain_decoder.is_none() || 
           self.fountain_message_id.as_ref() != Some(&frame.message_id) {
            self.fountain_decoder = Some(super::fountain::FountainDecoder::new(
                frame.fragment_count,
                frame.message_len,
            ));
            self.fountain_message_id = Some(frame.message_id.clone());
        }
        
        let decoder = self.fountain_decoder.as_mut().unwrap();
        
        let data = BASE64.decode(&frame.data)
            .map_err(|e| QrError::InvalidData(format!("Base64 decode error: {}", e)))?;
        
        let part = super::fountain::FountainPart {
            indexes: frame.indexes,
            data,
        };
        
        decoder.receive_part(part)?;
        
        if decoder.is_complete() {
            let result = decoder.result()?;
            
            // Verify checksum
            let checksum = crc32fast::hash(&result);
            if checksum != frame.checksum {
                return Err(QrError::ChecksumMismatch);
            }
            
            // Reset decoder
            self.fountain_decoder = None;
            self.fountain_message_id = None;
            
            Ok(ScanResult::Complete(result))
        } else {
            Ok(ScanResult::Fountain {
                progress: decoder.progress(),
                can_decode: decoder.can_decode(),
            })
        }
    }
    
    /// Get the content type of a pending message
    pub fn pending_content_type(&self, message_id: &str) -> Option<&str> {
        self.pending.get(message_id).map(|p| p.content_type.as_str())
    }
    
    /// Get progress for a specific message
    pub fn message_progress(&self, message_id: &str) -> Option<f32> {
        self.pending.get(message_id).map(|p| {
            p.parts.len() as f32 / p.total_parts as f32
        })
    }
    
    /// Get all pending message IDs
    pub fn pending_messages(&self) -> Vec<&String> {
        self.pending.keys().collect()
    }
}

impl Default for QrDecoder {
    fn default() -> Self {
        Self::new()
    }
}

/// Single frame format (matching encoder)
#[derive(Debug, Clone, Serialize, Deserialize)]
struct SingleFrame {
    content_type: String,
    data: String,
    checksum: u32,
}

/// Multi-part frame format (matching encoder)
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

/// Fountain code frame format (matching encoder)
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

/// Pending multi-part message
struct PendingMessage {
    total_parts: usize,
    total_size: usize,
    content_type: String,
    parts: HashMap<usize, Vec<u8>>,
    expected_checksum: Option<u32>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::qr::encoder::QrEncoder;
    use crate::qr::types::{ContentType, AnimationSettings, QrOptions};
    
    #[test]
    fn test_decode_single_frame() {
        let encoder = QrEncoder::new();
        let original = b"Hello, World!";
        
        let frames = encoder.encode(original, ContentType::RawBytes).unwrap();
        assert_eq!(frames.len(), 1);
        
        let mut decoder = QrDecoder::new();
        let result = decoder.decode(&frames[0]).unwrap();
        
        match result {
            ScanResult::Complete(data) => {
                assert_eq!(data, original.to_vec());
            }
            _ => panic!("Expected complete result"),
        }
    }
    
    #[test]
    fn test_decode_multipart() {
        let encoder = QrEncoder::with_options(QrOptions {
            animation: AnimationSettings {
                fragment_size: 10,
                ..Default::default()
            },
            error_correction: super::super::ErrorCorrectionLevel::M,
            ..Default::default()
        });
        
        // Use larger data to force multipart encoding
        let original: Vec<u8> = (0..2500).map(|i| (i % 256) as u8).collect();
        let frames = encoder.encode(&original, ContentType::RawBytes).unwrap();
        
        assert!(frames.len() > 1, "Expected multiple frames, got {}", frames.len());
        
        let mut decoder = QrDecoder::new();
        let mut final_result = None;
        
        for frame in &frames {
            let result = decoder.decode(frame).unwrap();
            match result {
                ScanResult::Complete(data) => {
                    final_result = Some(data);
                    break;
                }
                ScanResult::Partial { received, total, .. } => {
                    assert!(received <= total);
                }
                _ => {}
            }
        }
        
        assert!(final_result.is_some());
        assert_eq!(final_result.unwrap(), original);
    }
    
    #[test]
    fn test_decode_out_of_order() {
        let encoder = QrEncoder::with_options(QrOptions {
            animation: AnimationSettings {
                fragment_size: 10,
                ..Default::default()
            },
            error_correction: super::super::ErrorCorrectionLevel::M,
            ..Default::default()
        });
        
        // Use larger data to force multipart encoding
        let original: Vec<u8> = (0..2500).map(|i| (i % 256) as u8).collect();
        let frames = encoder.encode(&original, ContentType::RawBytes).unwrap();
        
        // Shuffle frames
        let mut shuffled = frames.clone();
        shuffled.reverse();
        
        let mut decoder = QrDecoder::new();
        let mut final_result = None;
        
        for frame in &shuffled {
            let result = decoder.decode(frame).unwrap();
            if let ScanResult::Complete(data) = result {
                final_result = Some(data);
                break;
            }
        }
        
        assert!(final_result.is_some());
        assert_eq!(final_result.unwrap(), original);
    }
    
    #[test]
    fn test_checksum_verification() {
        let json = r#"{"content_type":"application/octet-stream","data":"SGVsbG8=","checksum":0}"#;
        
        let mut decoder = QrDecoder::new();
        let result = decoder.decode(json);
        
        assert!(matches!(result, Err(QrError::ChecksumMismatch)));
    }
}
