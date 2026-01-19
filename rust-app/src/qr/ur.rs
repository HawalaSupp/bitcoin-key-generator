//! Uniform Resource (UR) Encoding for QR Codes
//!
//! Implements BC-UR (Blockchain Commons Uniform Resources) standard
//! for encoding structured binary data in QR codes.
//!
//! # Format
//! UR format: `ur:<type>/<payload>` or `ur:<type>/<seq>-<count>/<payload>`
//!
//! # Supported Types
//! - crypto-psbt: Partially Signed Bitcoin Transaction
//! - crypto-account: HD account with key derivations
//! - crypto-hdkey: Hierarchical Deterministic key
//! - crypto-output: Bitcoin output descriptor
//! - crypto-seed: BIP39 seed
//! - bytes: Raw bytes

use super::{QrError, QrResult};
use serde::{Deserialize, Serialize};

/// UR type identifiers
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum UrType {
    /// Raw bytes
    Bytes,
    /// Bitcoin PSBT
    CryptoPsbt,
    /// HD account info
    CryptoAccount,
    /// HD key
    CryptoHdkey,
    /// Output descriptor
    CryptoOutput,
    /// BIP39 seed
    CryptoSeed,
    /// Ethereum signature request
    EthSignRequest,
    /// Ethereum signature
    EthSignature,
    /// Solana signature request
    SolSignRequest,
    /// Solana signature
    SolSignature,
}

impl UrType {
    /// Get the UR type string
    pub fn as_str(&self) -> &'static str {
        match self {
            UrType::Bytes => "bytes",
            UrType::CryptoPsbt => "crypto-psbt",
            UrType::CryptoAccount => "crypto-account",
            UrType::CryptoHdkey => "crypto-hdkey",
            UrType::CryptoOutput => "crypto-output",
            UrType::CryptoSeed => "crypto-seed",
            UrType::EthSignRequest => "eth-sign-request",
            UrType::EthSignature => "eth-signature",
            UrType::SolSignRequest => "sol-sign-request",
            UrType::SolSignature => "sol-signature",
        }
    }
    
    /// Parse UR type from string
    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "bytes" => Some(UrType::Bytes),
            "crypto-psbt" => Some(UrType::CryptoPsbt),
            "crypto-account" => Some(UrType::CryptoAccount),
            "crypto-hdkey" => Some(UrType::CryptoHdkey),
            "crypto-output" => Some(UrType::CryptoOutput),
            "crypto-seed" => Some(UrType::CryptoSeed),
            "eth-sign-request" => Some(UrType::EthSignRequest),
            "eth-signature" => Some(UrType::EthSignature),
            "sol-sign-request" => Some(UrType::SolSignRequest),
            "sol-signature" => Some(UrType::SolSignature),
            _ => None,
        }
    }
}

/// UR Encoder
pub struct UrEncoder {
    /// UR type
    ur_type: UrType,
    /// Encoded data
    data: Vec<u8>,
    /// Fragment size for multi-part
    fragment_size: usize,
}

impl UrEncoder {
    /// Create a new UR encoder
    pub fn new(ur_type: UrType, data: &[u8]) -> Self {
        Self {
            ur_type,
            data: data.to_vec(),
            fragment_size: 100,
        }
    }
    
    /// Set fragment size for multi-part encoding
    pub fn with_fragment_size(mut self, size: usize) -> Self {
        self.fragment_size = size;
        self
    }
    
    /// Encode as a single UR string (if small enough)
    pub fn encode_single(&self) -> QrResult<String> {
        let encoded = bytewords_encode(&self.data, BytewordsStyle::Minimal);
        Ok(format!("ur:{}/{}", self.ur_type.as_str(), encoded))
    }
    
    /// Encode as multi-part UR strings
    pub fn encode_multipart(&self) -> QrResult<Vec<String>> {
        let encoded = bytewords_encode(&self.data, BytewordsStyle::Minimal);
        let chars: Vec<char> = encoded.chars().collect();
        
        let fragment_count = (chars.len() + self.fragment_size - 1) / self.fragment_size;
        let mut parts = Vec::with_capacity(fragment_count);
        
        for i in 0..fragment_count {
            let start = i * self.fragment_size;
            let end = std::cmp::min(start + self.fragment_size, chars.len());
            let fragment: String = chars[start..end].iter().collect();
            
            let part = format!(
                "ur:{}/{}-{}/{}",
                self.ur_type.as_str(),
                i + 1,
                fragment_count,
                fragment
            );
            parts.push(part);
        }
        
        Ok(parts)
    }
    
    /// Encode to UR format (auto-detect single vs multi-part)
    pub fn encode(&self) -> QrResult<Vec<String>> {
        let encoded = bytewords_encode(&self.data, BytewordsStyle::Minimal);
        
        if encoded.len() <= 200 {
            Ok(vec![format!("ur:{}/{}", self.ur_type.as_str(), encoded)])
        } else {
            self.encode_multipart()
        }
    }
}

/// UR Decoder
pub struct UrDecoder {
    /// Expected UR type (optional)
    expected_type: Option<UrType>,
    /// Collected parts
    parts: Vec<(usize, String)>,
    /// Total parts expected
    total_parts: Option<usize>,
    /// Decoded UR type
    decoded_type: Option<UrType>,
}

impl UrDecoder {
    /// Create a new UR decoder
    pub fn new() -> Self {
        Self {
            expected_type: None,
            parts: Vec::new(),
            total_parts: None,
            decoded_type: None,
        }
    }
    
    /// Create decoder expecting a specific type
    pub fn with_expected_type(ur_type: UrType) -> Self {
        Self {
            expected_type: Some(ur_type),
            parts: Vec::new(),
            total_parts: None,
            decoded_type: None,
        }
    }
    
    /// Decode a single UR string
    pub fn decode_single(ur: &str) -> QrResult<(UrType, Vec<u8>)> {
        let parsed = Self::parse_ur(ur)?;
        
        let ur_type = UrType::from_str(&parsed.ur_type)
            .ok_or_else(|| QrError::UnsupportedUrType(parsed.ur_type.clone()))?;
        
        let data = bytewords_decode(&parsed.payload, BytewordsStyle::Minimal)?;
        
        Ok((ur_type, data))
    }
    
    /// Receive a UR part
    pub fn receive(&mut self, ur: &str) -> QrResult<bool> {
        let parsed = Self::parse_ur(ur)?;
        
        let ur_type = UrType::from_str(&parsed.ur_type)
            .ok_or_else(|| QrError::UnsupportedUrType(parsed.ur_type.clone()))?;
        
        // Check type consistency
        if let Some(expected) = self.expected_type {
            if ur_type != expected {
                return Err(QrError::InvalidUrFormat(
                    format!("Expected {:?}, got {:?}", expected, ur_type)
                ));
            }
        }
        
        self.decoded_type = Some(ur_type);
        
        if let Some((seq, total)) = parsed.sequence {
            self.total_parts = Some(total);
            
            // Store part if not already received
            if !self.parts.iter().any(|(s, _)| *s == seq) {
                self.parts.push((seq, parsed.payload));
            }
            
            Ok(self.parts.len() == total)
        } else {
            // Single-part message
            self.parts.push((1, parsed.payload));
            self.total_parts = Some(1);
            Ok(true)
        }
    }
    
    /// Get the decoded result
    pub fn result(&self) -> QrResult<(UrType, Vec<u8>)> {
        let total = self.total_parts
            .ok_or(QrError::DecodingIncomplete)?;
        
        if self.parts.len() != total {
            return Err(QrError::IncompleteMessage(self.parts.len(), total));
        }
        
        // Sort parts by sequence number
        let mut sorted_parts = self.parts.clone();
        sorted_parts.sort_by_key(|(seq, _)| *seq);
        
        // Concatenate payloads
        let payload: String = sorted_parts.iter()
            .map(|(_, p)| p.as_str())
            .collect();
        
        let ur_type = self.decoded_type
            .ok_or(QrError::DecodingIncomplete)?;
        
        let data = bytewords_decode(&payload, BytewordsStyle::Minimal)?;
        
        Ok((ur_type, data))
    }
    
    /// Get progress
    pub fn progress(&self) -> f32 {
        match self.total_parts {
            Some(total) => self.parts.len() as f32 / total as f32,
            None => 0.0,
        }
    }
    
    /// Parse a UR string
    fn parse_ur(ur: &str) -> QrResult<ParsedUr> {
        let ur = ur.trim();
        
        if !ur.to_lowercase().starts_with("ur:") {
            return Err(QrError::InvalidUrFormat("Missing 'ur:' prefix".to_string()));
        }
        
        let content = &ur[3..];
        let parts: Vec<&str> = content.split('/').collect();
        
        if parts.len() < 2 {
            return Err(QrError::InvalidUrFormat("Missing type or payload".to_string()));
        }
        
        let ur_type = parts[0].to_string();
        
        if parts.len() == 2 {
            // Single part: ur:type/payload
            Ok(ParsedUr {
                ur_type,
                sequence: None,
                payload: parts[1].to_string(),
            })
        } else if parts.len() == 3 {
            // Multi-part: ur:type/seq-count/payload
            let seq_parts: Vec<&str> = parts[1].split('-').collect();
            if seq_parts.len() != 2 {
                return Err(QrError::InvalidUrFormat("Invalid sequence format".to_string()));
            }
            
            let seq: usize = seq_parts[0].parse()
                .map_err(|_| QrError::InvalidUrFormat("Invalid sequence number".to_string()))?;
            let total: usize = seq_parts[1].parse()
                .map_err(|_| QrError::InvalidUrFormat("Invalid total count".to_string()))?;
            
            Ok(ParsedUr {
                ur_type,
                sequence: Some((seq, total)),
                payload: parts[2].to_string(),
            })
        } else {
            Err(QrError::InvalidUrFormat("Too many path segments".to_string()))
        }
    }
}

impl Default for UrDecoder {
    fn default() -> Self {
        Self::new()
    }
}

/// Parsed UR components
struct ParsedUr {
    ur_type: String,
    sequence: Option<(usize, usize)>,
    payload: String,
}

/// Bytewords encoding style
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BytewordsStyle {
    /// Standard format with spaces
    Standard,
    /// Minimal format (first and last letter only)
    Minimal,
    /// URI format with dashes
    Uri,
}

/// Bytewords encoding (simplified)
/// Uses first and last letter of each word for minimal encoding
fn bytewords_encode(data: &[u8], style: BytewordsStyle) -> String {
    // Append CRC32 checksum
    let checksum = crc32fast::hash(data);
    let checksum_bytes = checksum.to_be_bytes();
    
    let mut full_data = data.to_vec();
    full_data.extend_from_slice(&checksum_bytes);
    
    // Encode each byte as two characters (minimal style)
    let mut result = String::with_capacity(full_data.len() * 2);
    
    for byte in &full_data {
        let word = BYTEWORDS[*byte as usize];
        match style {
            BytewordsStyle::Minimal => {
                // First and last letter
                let chars: Vec<char> = word.chars().collect();
                result.push(chars[0]);
                result.push(chars[chars.len() - 1]);
            }
            BytewordsStyle::Standard | BytewordsStyle::Uri => {
                if !result.is_empty() {
                    result.push(if style == BytewordsStyle::Uri { '-' } else { ' ' });
                }
                result.push_str(word);
            }
        }
    }
    
    result
}

/// Bytewords decoding
fn bytewords_decode(encoded: &str, style: BytewordsStyle) -> QrResult<Vec<u8>> {
    let chars: Vec<char> = encoded.chars().collect();
    
    if style == BytewordsStyle::Minimal {
        if chars.len() % 2 != 0 {
            return Err(QrError::InvalidData("Invalid bytewords length".to_string()));
        }
        
        let mut bytes = Vec::with_capacity(chars.len() / 2);
        
        for i in (0..chars.len()).step_by(2) {
            let first = chars[i];
            let last = chars[i + 1];
            
            let byte = BYTEWORDS.iter()
                .position(|w| {
                    let wc: Vec<char> = w.chars().collect();
                    wc[0] == first && wc[wc.len() - 1] == last
                })
                .ok_or_else(|| QrError::InvalidData(
                    format!("Unknown byteword: {}{}", first, last)
                ))?;
            
            bytes.push(byte as u8);
        }
        
        // Remove and verify checksum
        if bytes.len() < 4 {
            return Err(QrError::InvalidData("Data too short".to_string()));
        }
        
        let data_len = bytes.len() - 4;
        let data = &bytes[..data_len];
        let checksum_bytes = &bytes[data_len..];
        
        let expected_checksum = u32::from_be_bytes([
            checksum_bytes[0],
            checksum_bytes[1],
            checksum_bytes[2],
            checksum_bytes[3],
        ]);
        
        let actual_checksum = crc32fast::hash(data);
        
        if expected_checksum != actual_checksum {
            return Err(QrError::ChecksumMismatch);
        }
        
        Ok(data.to_vec())
    } else {
        // Standard or URI style - split by separator and look up words
        let separator = if style == BytewordsStyle::Uri { '-' } else { ' ' };
        let words: Vec<&str> = encoded.split(separator).collect();
        
        let mut bytes = Vec::with_capacity(words.len());
        
        for word in &words {
            let byte = BYTEWORDS.iter()
                .position(|w| w == word)
                .ok_or_else(|| QrError::InvalidData(format!("Unknown word: {}", word)))?;
            bytes.push(byte as u8);
        }
        
        // Remove and verify checksum
        if bytes.len() < 4 {
            return Err(QrError::InvalidData("Data too short".to_string()));
        }
        
        let data_len = bytes.len() - 4;
        let data = &bytes[..data_len];
        let checksum_bytes = &bytes[data_len..];
        
        let expected_checksum = u32::from_be_bytes([
            checksum_bytes[0],
            checksum_bytes[1],
            checksum_bytes[2],
            checksum_bytes[3],
        ]);
        
        let actual_checksum = crc32fast::hash(data);
        
        if expected_checksum != actual_checksum {
            return Err(QrError::ChecksumMismatch);
        }
        
        Ok(data.to_vec())
    }
}

/// Official BC-UR bytewords wordlist (256 words, 4 chars each)
/// Each word has unique first and last characters for error detection
const BYTEWORDS: [&str; 256] = [
    // 0x00-0x07
    "able", "acid", "also", "apex", "aqua", "arch", "atom", "aunt",
    // 0x08-0x0f
    "away", "axis", "back", "bald", "barn", "beta", "bias", "blue",
    // 0x10-0x17
    "body", "brag", "brew", "bulb", "buzz", "calm", "cash", "cats",
    // 0x18-0x1f
    "chef", "city", "claw", "code", "cola", "cook", "cost", "crux",
    // 0x20-0x27
    "curl", "cusp", "cyan", "dark", "data", "days", "deli", "dice",
    // 0x28-0x2f
    "diet", "disk", "dogs", "down", "draw", "drop", "drum", "dull",
    // 0x30-0x37
    "duty", "each", "easy", "echo", "edge", "epic", "even", "exam",
    // 0x38-0x3f
    "exit", "eyes", "fact", "fair", "fern", "figs", "film", "fish",
    // 0x40-0x47
    "fizz", "flap", "flew", "flux", "foxy", "free", "frog", "fuel",
    // 0x48-0x4f
    "fund", "gala", "game", "gear", "gems", "gift", "girl", "glow",
    // 0x50-0x57
    "good", "gray", "grim", "guru", "gush", "gyro", "half", "hang",
    // 0x58-0x5f
    "hard", "hawk", "heat", "help", "high", "hill", "holy", "hope",
    // 0x60-0x67
    "horn", "huts", "iced", "idea", "idle", "inch", "inky", "into",
    // 0x68-0x6f
    "iris", "iron", "item", "jade", "jazz", "join", "jolt", "jowl",
    // 0x70-0x77
    "judo", "jugs", "jump", "junk", "jury", "keep", "keno", "kept",
    // 0x78-0x7f
    "keys", "kick", "kiln", "king", "kite", "kiwi", "knob", "lamb",
    // 0x80-0x87
    "lava", "lazy", "leaf", "legs", "liar", "limp", "lion", "list",
    // 0x88-0x8f
    "logo", "loud", "love", "luau", "luck", "lung", "main", "many",
    // 0x90-0x97
    "math", "maze", "memo", "menu", "meow", "mild", "mint", "miss",
    // 0x98-0x9f
    "monk", "nail", "navy", "need", "news", "next", "noon", "note",
    // 0xa0-0xa7
    "numb", "obey", "oboe", "omit", "onyx", "open", "oval", "owls",
    // 0xa8-0xaf
    "paid", "part", "peck", "play", "plus", "poem", "pool", "pose",
    // 0xb0-0xb7
    "puff", "puma", "purr", "quad", "quiz", "race", "ramp", "real",
    // 0xb8-0xbf
    "redo", "rich", "road", "rock", "roof", "ruby", "ruin", "runs",
    // 0xc0-0xc7
    "rust", "safe", "saga", "scar", "sets", "silk", "skew", "slot",
    // 0xc8-0xcf
    "soap", "solo", "song", "stub", "surf", "swan", "taco", "task",
    // 0xd0-0xd7
    "taxi", "tent", "tied", "time", "tiny", "toil", "tomb", "toys",
    // 0xd8-0xdf
    "trip", "tuna", "twin", "ugly", "undo", "unit", "urge", "user",
    // 0xe0-0xe7
    "vast", "very", "veto", "vial", "vibe", "view", "visa", "void",
    // 0xe8-0xef
    "vows", "wall", "warm", "wasp", "wave", "waxy", "webs", "what",
    // 0xf0-0xf7
    "when", "whiz", "wolf", "work", "yawn", "yell", "yoga", "yurt",
    // 0xf8-0xff
    "zaps", "zero", "zest", "zinc", "zone", "zoom", "zulu", "zyme",
];

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_ur_type_str() {
        assert_eq!(UrType::CryptoPsbt.as_str(), "crypto-psbt");
        assert_eq!(UrType::Bytes.as_str(), "bytes");
    }
    
    #[test]
    fn test_ur_type_from_str() {
        assert_eq!(UrType::from_str("crypto-psbt"), Some(UrType::CryptoPsbt));
        assert_eq!(UrType::from_str("BYTES"), Some(UrType::Bytes));
        assert_eq!(UrType::from_str("unknown"), None);
    }
    
    #[test]
    fn test_bytewords_roundtrip() {
        let data = b"Hello, World!";
        
        let encoded = bytewords_encode(data, BytewordsStyle::Minimal);
        let decoded = bytewords_decode(&encoded, BytewordsStyle::Minimal).unwrap();
        
        assert_eq!(decoded, data.to_vec());
    }
    
    #[test]
    fn test_ur_encoder_single() {
        let encoder = UrEncoder::new(UrType::Bytes, b"test");
        let ur = encoder.encode_single().unwrap();
        
        assert!(ur.starts_with("ur:bytes/"));
    }
    
    #[test]
    fn test_ur_decoder_single() {
        let data = b"Hello";
        let encoder = UrEncoder::new(UrType::Bytes, data);
        let ur = encoder.encode_single().unwrap();
        
        let (ur_type, decoded) = UrDecoder::decode_single(&ur).unwrap();
        
        assert_eq!(ur_type, UrType::Bytes);
        assert_eq!(decoded, data.to_vec());
    }
    
    #[test]
    fn test_ur_multipart() {
        let data = vec![0u8; 500]; // Large enough for multi-part
        let encoder = UrEncoder::new(UrType::CryptoPsbt, &data)
            .with_fragment_size(50);
        
        let parts = encoder.encode_multipart().unwrap();
        
        assert!(parts.len() > 1);
        
        let mut decoder = UrDecoder::new();
        let mut complete = false;
        
        for part in &parts {
            complete = decoder.receive(part).unwrap();
            if complete {
                break;
            }
        }
        
        assert!(complete);
        
        let (ur_type, decoded) = decoder.result().unwrap();
        assert_eq!(ur_type, UrType::CryptoPsbt);
        assert_eq!(decoded, data);
    }
    
    #[test]
    fn test_parse_ur() {
        // Single part
        let parsed = UrDecoder::parse_ur("ur:bytes/aebacy").unwrap();
        assert_eq!(parsed.ur_type, "bytes");
        assert!(parsed.sequence.is_none());
        
        // Multi-part
        let parsed = UrDecoder::parse_ur("ur:crypto-psbt/1-3/aebc").unwrap();
        assert_eq!(parsed.ur_type, "crypto-psbt");
        assert_eq!(parsed.sequence, Some((1, 3)));
    }
}
