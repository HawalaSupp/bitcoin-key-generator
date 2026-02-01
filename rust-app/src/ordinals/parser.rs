//! Ordinals and BRC-20 content parsing

use super::types::*;

/// Inscription content parser
pub struct InscriptionParser;

impl InscriptionParser {
    /// Parse inscription ID format (txid:index or txidi0)
    pub fn parse_inscription_id(id: &str) -> Result<(String, u32), OrdinalsError> {
        // Format: txid:index or txidiN
        if id.contains(':') {
            let parts: Vec<&str> = id.split(':').collect();
            if parts.len() != 2 {
                return Err(OrdinalsError::InvalidInscriptionId(id.to_string()));
            }
            let txid = parts[0].to_string();
            let index = parts[1]
                .parse()
                .map_err(|_| OrdinalsError::InvalidInscriptionId(id.to_string()))?;
            Ok((txid, index))
        } else if id.contains('i') {
            // Format: txidiN
            let parts: Vec<&str> = id.split('i').collect();
            if parts.len() != 2 {
                return Err(OrdinalsError::InvalidInscriptionId(id.to_string()));
            }
            let txid = parts[0].to_string();
            let index = parts[1]
                .parse()
                .map_err(|_| OrdinalsError::InvalidInscriptionId(id.to_string()))?;
            Ok((txid, index))
        } else {
            Err(OrdinalsError::InvalidInscriptionId(id.to_string()))
        }
    }

    /// Format inscription ID as txidi0 format
    pub fn format_inscription_id(txid: &str, index: u32) -> String {
        format!("{}i{}", txid, index)
    }

    /// Validate inscription ID format
    pub fn is_valid_inscription_id(id: &str) -> bool {
        Self::parse_inscription_id(id).is_ok()
    }

    /// Check if content is likely BRC-20
    pub fn is_likely_brc20(content_type: &str, content: &[u8]) -> bool {
        if content_type != "text/plain" && content_type != "application/json" {
            return false;
        }

        // Try to parse as JSON and check for BRC-20 fields
        if let Ok(text) = std::str::from_utf8(content) {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(text) {
                return json.get("p").and_then(|v| v.as_str()) == Some("brc-20")
                    && json.get("op").is_some()
                    && json.get("tick").is_some();
            }
        }

        false
    }

    /// Parse BRC-20 content
    pub fn parse_brc20(content: &[u8]) -> Result<Brc20Inscription, OrdinalsError> {
        let text = std::str::from_utf8(content)
            .map_err(|_| OrdinalsError::ParseError("Invalid UTF-8".to_string()))?;

        let brc20: Brc20Inscription = serde_json::from_str(text)
            .map_err(|e| OrdinalsError::InvalidBrc20(e.to_string()))?;

        if !brc20.is_valid() {
            return Err(OrdinalsError::InvalidBrc20("Validation failed".to_string()));
        }

        Ok(brc20)
    }

    /// Detect content type from bytes (magic bytes)
    pub fn detect_content_type(data: &[u8]) -> &'static str {
        if data.len() < 4 {
            return "application/octet-stream";
        }

        // PNG
        if data.starts_with(&[0x89, 0x50, 0x4E, 0x47]) {
            return "image/png";
        }

        // JPEG
        if data.starts_with(&[0xFF, 0xD8, 0xFF]) {
            return "image/jpeg";
        }

        // GIF
        if data.starts_with(b"GIF87a") || data.starts_with(b"GIF89a") {
            return "image/gif";
        }

        // WebP
        if data.len() >= 12 && &data[0..4] == b"RIFF" && &data[8..12] == b"WEBP" {
            return "image/webp";
        }

        // SVG (check for XML/SVG start)
        if data.starts_with(b"<?xml") || data.starts_with(b"<svg") {
            return "image/svg+xml";
        }

        // HTML
        if data.starts_with(b"<!DOCTYPE") || data.starts_with(b"<html") || data.starts_with(b"<HTML") {
            return "text/html";
        }

        // JSON
        if data.starts_with(b"{") || data.starts_with(b"[") {
            return "application/json";
        }

        // MP4
        if data.len() >= 8 && &data[4..8] == b"ftyp" {
            return "video/mp4";
        }

        // WebM
        if data.starts_with(&[0x1A, 0x45, 0xDF, 0xA3]) {
            return "video/webm";
        }

        // MP3
        if data.starts_with(&[0xFF, 0xFB]) || data.starts_with(&[0xFF, 0xFA]) || data.starts_with(b"ID3") {
            return "audio/mpeg";
        }

        // GLTF binary
        if data.starts_with(b"glTF") {
            return "model/gltf-binary";
        }

        // Text (check if printable ASCII)
        if data.iter().all(|&b| b.is_ascii_graphic() || b.is_ascii_whitespace()) {
            return "text/plain";
        }

        "application/octet-stream"
    }

    /// Extract text preview from inscription content
    pub fn extract_text_preview(content: &[u8], max_len: usize) -> Option<String> {
        let text = std::str::from_utf8(content).ok()?;
        let preview: String = text.chars().take(max_len).collect();
        if text.len() > max_len {
            Some(format!("{}...", preview))
        } else {
            Some(preview)
        }
    }
}

/// Satoshi ordinal utilities
pub struct SatoshiUtils;

impl SatoshiUtils {
    /// Total number of satoshis that will ever exist
    pub const TOTAL_SUPPLY: u64 = 2_100_000_000_000_000;

    /// Satoshis per Bitcoin
    pub const SATS_PER_BTC: u64 = 100_000_000;

    /// Calculate which block a satoshi was mined in
    pub fn block_of_sat(sat: u64) -> u64 {
        // Simplified calculation - real calculation is more complex
        // Based on halving schedule
        let subsidy_halving_interval: u64 = 210_000;
        let initial_subsidy: u64 = 50 * Self::SATS_PER_BTC;

        let mut remaining = sat;
        let mut block: u64 = 0;
        let mut subsidy = initial_subsidy;

        while remaining >= subsidy * subsidy_halving_interval {
            remaining -= subsidy * subsidy_halving_interval;
            subsidy /= 2;
            block += subsidy_halving_interval;

            if subsidy == 0 {
                break;
            }
        }

        if subsidy > 0 {
            block += remaining / subsidy;
        }

        block
    }

    /// Calculate satoshi position within its block
    pub fn offset_in_block(sat: u64) -> u64 {
        let block = Self::block_of_sat(sat);
        let block_start = Self::first_sat_of_block(block);
        sat - block_start
    }

    /// Calculate the first satoshi of a block
    pub fn first_sat_of_block(block: u64) -> u64 {
        let subsidy_halving_interval: u64 = 210_000;
        let initial_subsidy: u64 = 50 * Self::SATS_PER_BTC;

        let mut sat: u64 = 0;
        let mut current_block: u64 = 0;
        let mut subsidy = initial_subsidy;

        while current_block + subsidy_halving_interval <= block {
            sat += subsidy * subsidy_halving_interval;
            current_block += subsidy_halving_interval;
            subsidy /= 2;

            if subsidy == 0 {
                break;
            }
        }

        sat += subsidy * (block - current_block);
        sat
    }

    /// Get the halving epoch for a satoshi
    pub fn epoch_of_sat(sat: u64) -> u64 {
        let block = Self::block_of_sat(sat);
        block / 210_000
    }

    /// Format satoshi as inscription name (e.g., "Sat 1234567890")
    pub fn format_sat(sat: u64) -> String {
        format!("Sat {}", Self::format_with_commas(sat))
    }

    /// Format number with commas
    fn format_with_commas(n: u64) -> String {
        let s = n.to_string();
        let mut result = String::new();
        for (i, c) in s.chars().rev().enumerate() {
            if i > 0 && i % 3 == 0 {
                result.push(',');
            }
            result.push(c);
        }
        result.chars().rev().collect()
    }

    /// Check if satoshi is a "pizza" sat (from the famous pizza transaction)
    pub fn is_pizza_sat(sat: u64) -> bool {
        // Pizza transaction sats are from block 57,043
        // This is a simplified check
        let pizza_block = 57043;
        let block = Self::block_of_sat(sat);
        block == pizza_block
    }

    /// Check if satoshi is a "vintage" sat (first 1000 blocks)
    pub fn is_vintage(sat: u64) -> bool {
        Self::block_of_sat(sat) < 1000
    }
}

/// BRC-20 transfer builder
pub struct Brc20TransferBuilder {
    tick: String,
    amount: String,
}

impl Brc20TransferBuilder {
    pub fn new(tick: &str, amount: &str) -> Self {
        Self {
            tick: tick.to_string(),
            amount: amount.to_string(),
        }
    }

    /// Build the inscription content
    pub fn build(&self) -> Result<String, OrdinalsError> {
        if self.tick.len() != 4 {
            return Err(OrdinalsError::InvalidBrc20(
                "Ticker must be 4 characters".to_string(),
            ));
        }

        let content = serde_json::json!({
            "p": "brc-20",
            "op": "transfer",
            "tick": self.tick,
            "amt": self.amount
        });

        Ok(content.to_string())
    }

    /// Get the content type for inscription
    pub fn content_type() -> &'static str {
        "text/plain;charset=utf-8"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_inscription_id_colon() {
        let result = InscriptionParser::parse_inscription_id("abc123:0");
        assert!(result.is_ok());
        let (txid, index) = result.unwrap();
        assert_eq!(txid, "abc123");
        assert_eq!(index, 0);
    }

    #[test]
    fn test_parse_inscription_id_i_format() {
        let result = InscriptionParser::parse_inscription_id("abc123i0");
        assert!(result.is_ok());
        let (txid, index) = result.unwrap();
        assert_eq!(txid, "abc123");
        assert_eq!(index, 0);
    }

    #[test]
    fn test_format_inscription_id() {
        let id = InscriptionParser::format_inscription_id("abc123", 0);
        assert_eq!(id, "abc123i0");
    }

    #[test]
    fn test_is_valid_inscription_id() {
        assert!(InscriptionParser::is_valid_inscription_id("abc123i0"));
        assert!(InscriptionParser::is_valid_inscription_id("abc123:0"));
        assert!(!InscriptionParser::is_valid_inscription_id("invalid"));
    }

    #[test]
    fn test_is_likely_brc20() {
        let content = br#"{"p":"brc-20","op":"transfer","tick":"ordi","amt":"100"}"#;
        assert!(InscriptionParser::is_likely_brc20("text/plain", content));
        assert!(InscriptionParser::is_likely_brc20("application/json", content));

        let not_brc20 = b"Hello, world!";
        assert!(!InscriptionParser::is_likely_brc20("text/plain", not_brc20));
    }

    #[test]
    fn test_parse_brc20() {
        let content = br#"{"p":"brc-20","op":"transfer","tick":"ordi","amt":"100"}"#;
        let result = InscriptionParser::parse_brc20(content);
        assert!(result.is_ok());

        let brc20 = result.unwrap();
        assert_eq!(brc20.tick, "ordi");
        assert_eq!(brc20.operation, Brc20Operation::Transfer);
        assert_eq!(brc20.amount(), Some(100.0));
    }

    #[test]
    fn test_detect_content_type() {
        // PNG
        let png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
        assert_eq!(InscriptionParser::detect_content_type(&png), "image/png");

        // JPEG
        let jpeg = [0xFF, 0xD8, 0xFF, 0xE0];
        assert_eq!(InscriptionParser::detect_content_type(&jpeg), "image/jpeg");

        // GIF
        let gif = b"GIF89a";
        assert_eq!(InscriptionParser::detect_content_type(gif), "image/gif");

        // JSON
        let json = b"{\"key\": \"value\"}";
        assert_eq!(InscriptionParser::detect_content_type(json), "application/json");

        // HTML
        let html = b"<!DOCTYPE html>";
        assert_eq!(InscriptionParser::detect_content_type(html), "text/html");
    }

    #[test]
    fn test_extract_text_preview() {
        let content = b"Hello, this is a long text that should be truncated";
        let preview = InscriptionParser::extract_text_preview(content, 20);
        assert!(preview.is_some());
        assert!(preview.unwrap().ends_with("..."));
    }

    #[test]
    fn test_satoshi_block_calculation() {
        // First satoshi of block 0
        assert_eq!(SatoshiUtils::block_of_sat(0), 0);

        // After first block's reward (50 BTC)
        assert_eq!(SatoshiUtils::block_of_sat(5_000_000_000), 1);
    }

    #[test]
    fn test_first_sat_of_block() {
        assert_eq!(SatoshiUtils::first_sat_of_block(0), 0);
        assert_eq!(SatoshiUtils::first_sat_of_block(1), 5_000_000_000);
    }

    #[test]
    fn test_format_sat() {
        assert_eq!(SatoshiUtils::format_sat(1234567890), "Sat 1,234,567,890");
    }

    #[test]
    fn test_is_vintage() {
        assert!(SatoshiUtils::is_vintage(0));
        assert!(SatoshiUtils::is_vintage(1000000));
        assert!(!SatoshiUtils::is_vintage(5_000_000_000_000)); // Way past block 1000
    }

    #[test]
    fn test_brc20_transfer_builder() {
        let builder = Brc20TransferBuilder::new("ordi", "1000");
        let content = builder.build();
        assert!(content.is_ok());

        let json = content.unwrap();
        assert!(json.contains("brc-20"));
        assert!(json.contains("transfer"));
        assert!(json.contains("ordi"));
        assert!(json.contains("1000"));
    }

    #[test]
    fn test_brc20_transfer_builder_invalid_tick() {
        let builder = Brc20TransferBuilder::new("toolong", "1000");
        let result = builder.build();
        assert!(result.is_err());
    }

    #[test]
    fn test_epoch_calculation() {
        assert_eq!(SatoshiUtils::epoch_of_sat(0), 0);
        // After first halving (210000 blocks * 50 BTC)
        let first_halving_sat = 210_000 * 50 * 100_000_000;
        assert_eq!(SatoshiUtils::epoch_of_sat(first_halving_sat), 1);
    }
}
