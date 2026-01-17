//! JSON Parsing Utilities
//!
//! Safe JSON parsing with proper error handling.

use crate::error::{HawalaError, HawalaResult};
use serde::de::DeserializeOwned;

/// Safely parse JSON string into a type
pub fn parse_json<T: DeserializeOwned>(json_str: &str) -> HawalaResult<T> {
    serde_json::from_str(json_str)
        .map_err(|e| HawalaError::parse_error(format!("JSON parse error: {}", e)))
}

/// Safely parse JSON value from response body
pub fn parse_json_value(json_str: &str) -> HawalaResult<serde_json::Value> {
    serde_json::from_str(json_str)
        .map_err(|e| HawalaError::parse_error(format!("JSON parse error: {}", e)))
}

/// Safely extract a string field from JSON object
pub fn get_json_string(value: &serde_json::Value, field: &str) -> Option<String> {
    value.get(field).and_then(|v| v.as_str()).map(|s| s.to_string())
}

/// Safely extract a u64 field from JSON object (handles both number and hex string)
pub fn get_json_u64(value: &serde_json::Value, field: &str) -> Option<u64> {
    value.get(field).and_then(|v| {
        if let Some(n) = v.as_u64() {
            Some(n)
        } else if let Some(s) = v.as_str() {
            // Try parsing as hex
            if s.starts_with("0x") || s.starts_with("0X") {
                u64::from_str_radix(s.trim_start_matches("0x").trim_start_matches("0X"), 16).ok()
            } else {
                s.parse().ok()
            }
        } else {
            None
        }
    })
}

/// Safely extract a u128 field from JSON object (handles both number and hex string)
pub fn get_json_u128(value: &serde_json::Value, field: &str) -> Option<u128> {
    value.get(field).and_then(|v| {
        if let Some(n) = v.as_u64() {
            Some(n as u128)
        } else if let Some(s) = v.as_str() {
            // Try parsing as hex
            if s.starts_with("0x") || s.starts_with("0X") {
                u128::from_str_radix(s.trim_start_matches("0x").trim_start_matches("0X"), 16).ok()
            } else {
                s.parse().ok()
            }
        } else {
            None
        }
    })
}

/// Safely extract a bool field from JSON object
pub fn get_json_bool(value: &serde_json::Value, field: &str) -> Option<bool> {
    value.get(field).and_then(|v| v.as_bool())
}

/// Parse hex string to u64 safely
pub fn parse_hex_u64(hex_str: &str) -> HawalaResult<u64> {
    let cleaned = hex_str.trim_start_matches("0x").trim_start_matches("0X");
    u64::from_str_radix(cleaned, 16)
        .map_err(|e| HawalaError::parse_error(format!("Invalid hex u64 '{}': {}", hex_str, e)))
}

/// Parse hex string to u128 safely
pub fn parse_hex_u128(hex_str: &str) -> HawalaResult<u128> {
    let cleaned = hex_str.trim_start_matches("0x").trim_start_matches("0X");
    u128::from_str_radix(cleaned, 16)
        .map_err(|e| HawalaError::parse_error(format!("Invalid hex u128 '{}': {}", hex_str, e)))
}

/// Parse hex string to bytes safely
pub fn parse_hex_bytes(hex_str: &str) -> HawalaResult<Vec<u8>> {
    let cleaned = hex_str.trim_start_matches("0x").trim_start_matches("0X");
    hex::decode(cleaned)
        .map_err(|e| HawalaError::parse_error(format!("Invalid hex '{}': {}", hex_str, e)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_hex_u64() {
        assert_eq!(parse_hex_u64("0x5208").unwrap(), 21000);
        assert_eq!(parse_hex_u64("5208").unwrap(), 21000);
        assert_eq!(parse_hex_u64("0xFF").unwrap(), 255);
    }

    #[test]
    fn test_parse_hex_u128() {
        assert_eq!(parse_hex_u128("0xDE0B6B3A7640000").unwrap(), 1_000_000_000_000_000_000u128);
    }

    #[test]
    fn test_get_json_u64() {
        let json: serde_json::Value = serde_json::json!({
            "number": 42,
            "hex_string": "0x2A",
            "string": "42"
        });
        
        assert_eq!(get_json_u64(&json, "number"), Some(42));
        assert_eq!(get_json_u64(&json, "hex_string"), Some(42));
        assert_eq!(get_json_u64(&json, "string"), Some(42));
        assert_eq!(get_json_u64(&json, "missing"), None);
    }
}
