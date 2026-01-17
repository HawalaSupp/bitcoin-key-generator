//! Input Sanitization
//!
//! Defense-in-depth input sanitization with:
//! - String sanitization (XSS, injection prevention)
//! - Numeric range validation
//! - Path traversal prevention
//! - Unicode normalization
//! - Length limits

use crate::error::{HawalaError, HawalaResult};
use unicode_normalization::UnicodeNormalization;

/// Maximum length for various input types
pub mod limits {
    /// Maximum address length (Monero integrated addresses are longest at 106)
    pub const MAX_ADDRESS_LENGTH: usize = 120;
    /// Maximum transaction ID length
    pub const MAX_TX_ID_LENGTH: usize = 128;
    /// Maximum label/note length
    pub const MAX_LABEL_LENGTH: usize = 256;
    /// Maximum memo field length
    pub const MAX_MEMO_LENGTH: usize = 512;
    /// Maximum URL length
    pub const MAX_URL_LENGTH: usize = 2048;
    /// Maximum password length
    pub const MAX_PASSWORD_LENGTH: usize = 1024;
    /// Maximum mnemonic length (24 words + spaces)
    pub const MAX_MNEMONIC_LENGTH: usize = 300;
    /// Maximum API key length
    pub const MAX_API_KEY_LENGTH: usize = 256;
    /// Maximum JSON payload size
    pub const MAX_JSON_SIZE: usize = 1024 * 1024; // 1MB
}

/// Sanitization result
#[derive(Debug, Clone)]
pub struct SanitizeResult<T> {
    pub value: T,
    pub was_modified: bool,
    pub modifications: Vec<String>,
}

impl<T> SanitizeResult<T> {
    pub fn unchanged(value: T) -> Self {
        Self {
            value,
            was_modified: false,
            modifications: Vec::new(),
        }
    }

    pub fn modified(value: T, modifications: Vec<String>) -> Self {
        Self {
            value,
            was_modified: true,
            modifications,
        }
    }
}

/// Sanitize a string with configurable options
pub fn sanitize_string(input: &str, options: &SanitizeOptions) -> SanitizeResult<String> {
    let mut result = input.to_string();
    let mut modifications = Vec::new();

    // Trim whitespace
    if options.trim {
        let trimmed = result.trim();
        if trimmed.len() != result.len() {
            modifications.push("Trimmed whitespace".to_string());
            result = trimmed.to_string();
        }
    }

    // Normalize Unicode (NFC)
    if options.normalize_unicode {
        let normalized: String = result.nfc().collect();
        if normalized != result {
            modifications.push("Normalized Unicode".to_string());
            result = normalized;
        }
    }

    // Remove null bytes
    if options.remove_null_bytes && result.contains('\0') {
        result = result.replace('\0', "");
        modifications.push("Removed null bytes".to_string());
    }

    // Remove control characters
    if options.remove_control_chars {
        let cleaned: String = result.chars()
            .filter(|c| !c.is_control() || *c == '\n' || *c == '\t')
            .collect();
        if cleaned != result {
            modifications.push("Removed control characters".to_string());
            result = cleaned;
        }
    }

    // Collapse multiple spaces
    if options.collapse_whitespace {
        let mut prev_space = false;
        let collapsed: String = result.chars()
            .filter(|c| {
                if c.is_whitespace() {
                    if prev_space {
                        return false;
                    }
                    prev_space = true;
                } else {
                    prev_space = false;
                }
                true
            })
            .collect();
        if collapsed != result {
            modifications.push("Collapsed whitespace".to_string());
            result = collapsed;
        }
    }

    // Enforce length limit
    if let Some(max_len) = options.max_length {
        if result.len() > max_len {
            result = result.chars().take(max_len).collect();
            modifications.push(format!("Truncated to {} characters", max_len));
        }
    }

    // Remove HTML/XML tags
    if options.strip_html {
        let stripped = strip_html_tags(&result);
        if stripped != result {
            modifications.push("Stripped HTML tags".to_string());
            result = stripped;
        }
    }

    // Escape special characters
    if options.escape_special {
        let escaped = escape_special_chars(&result);
        if escaped != result {
            modifications.push("Escaped special characters".to_string());
            result = escaped;
        }
    }

    if modifications.is_empty() {
        SanitizeResult::unchanged(result)
    } else {
        SanitizeResult::modified(result, modifications)
    }
}

/// Sanitization options
#[derive(Debug, Clone)]
pub struct SanitizeOptions {
    pub trim: bool,
    pub normalize_unicode: bool,
    pub remove_null_bytes: bool,
    pub remove_control_chars: bool,
    pub collapse_whitespace: bool,
    pub max_length: Option<usize>,
    pub strip_html: bool,
    pub escape_special: bool,
}

impl Default for SanitizeOptions {
    fn default() -> Self {
        Self {
            trim: true,
            normalize_unicode: true,
            remove_null_bytes: true,
            remove_control_chars: true,
            collapse_whitespace: false,
            max_length: None,
            strip_html: false,
            escape_special: false,
        }
    }
}

impl SanitizeOptions {
    /// Options for addresses
    pub fn for_address() -> Self {
        Self {
            trim: true,
            normalize_unicode: false, // Addresses should be ASCII
            remove_null_bytes: true,
            remove_control_chars: true,
            collapse_whitespace: true,
            max_length: Some(limits::MAX_ADDRESS_LENGTH),
            strip_html: false,
            escape_special: false,
        }
    }

    /// Options for user labels/notes
    pub fn for_label() -> Self {
        Self {
            trim: true,
            normalize_unicode: true,
            remove_null_bytes: true,
            remove_control_chars: true,
            collapse_whitespace: true,
            max_length: Some(limits::MAX_LABEL_LENGTH),
            strip_html: true,
            escape_special: false,
        }
    }

    /// Options for memos
    pub fn for_memo() -> Self {
        Self {
            trim: true,
            normalize_unicode: true,
            remove_null_bytes: true,
            remove_control_chars: false, // Allow newlines
            collapse_whitespace: false,
            max_length: Some(limits::MAX_MEMO_LENGTH),
            strip_html: true,
            escape_special: false,
        }
    }

    /// Options for URLs
    pub fn for_url() -> Self {
        Self {
            trim: true,
            normalize_unicode: false,
            remove_null_bytes: true,
            remove_control_chars: true,
            collapse_whitespace: true,
            max_length: Some(limits::MAX_URL_LENGTH),
            strip_html: false,
            escape_special: false,
        }
    }

    /// Options for JSON payloads
    pub fn for_json() -> Self {
        Self {
            trim: false,
            normalize_unicode: true,
            remove_null_bytes: true,
            remove_control_chars: false,
            collapse_whitespace: false,
            max_length: Some(limits::MAX_JSON_SIZE),
            strip_html: false,
            escape_special: false,
        }
    }
}

/// Strip HTML/XML tags from string
fn strip_html_tags(input: &str) -> String {
    let mut result = String::with_capacity(input.len());
    let mut in_tag = false;
    
    for c in input.chars() {
        if c == '<' {
            in_tag = true;
        } else if c == '>' {
            in_tag = false;
        } else if !in_tag {
            result.push(c);
        }
    }
    
    result
}

/// Escape special characters
fn escape_special_chars(input: &str) -> String {
    let mut result = String::with_capacity(input.len() * 2);
    
    for c in input.chars() {
        match c {
            '<' => result.push_str("&lt;"),
            '>' => result.push_str("&gt;"),
            '&' => result.push_str("&amp;"),
            '"' => result.push_str("&quot;"),
            '\'' => result.push_str("&#x27;"),
            '/' => result.push_str("&#x2F;"),
            _ => result.push(c),
        }
    }
    
    result
}

/// Sanitize an address
pub fn sanitize_address(address: &str) -> HawalaResult<String> {
    let result = sanitize_string(address, &SanitizeOptions::for_address());
    
    // Additional address-specific validation
    let sanitized = &result.value;
    
    // Check for empty
    if sanitized.is_empty() {
        return Err(HawalaError::invalid_input("Address cannot be empty"));
    }
    
    // Check for suspicious characters
    if sanitized.contains(|c: char| c.is_whitespace()) {
        return Err(HawalaError::invalid_input("Address contains whitespace"));
    }
    
    // Check for valid character set
    let is_valid_chars = sanitized.chars().all(|c| {
        c.is_ascii_alphanumeric() || c == ':' // For chain: prefix
    });
    
    if !is_valid_chars {
        return Err(HawalaError::invalid_input("Address contains invalid characters"));
    }
    
    Ok(result.value)
}

/// Sanitize a transaction ID
pub fn sanitize_tx_id(tx_id: &str) -> HawalaResult<String> {
    let options = SanitizeOptions {
        trim: true,
        remove_null_bytes: true,
        remove_control_chars: true,
        collapse_whitespace: true,
        max_length: Some(limits::MAX_TX_ID_LENGTH),
        ..Default::default()
    };
    
    let result = sanitize_string(tx_id, &options);
    let sanitized = &result.value;
    
    if sanitized.is_empty() {
        return Err(HawalaError::invalid_input("Transaction ID cannot be empty"));
    }
    
    // TX IDs should be hex
    if !sanitized.chars().all(|c| c.is_ascii_hexdigit()) {
        // Allow 0x prefix
        let without_prefix = sanitized.strip_prefix("0x").unwrap_or(sanitized);
        if !without_prefix.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err(HawalaError::invalid_input("Transaction ID must be hexadecimal"));
        }
    }
    
    Ok(result.value.to_lowercase())
}

/// Sanitize a label/note
pub fn sanitize_label(label: &str) -> SanitizeResult<String> {
    sanitize_string(label, &SanitizeOptions::for_label())
}

/// Sanitize a memo field
pub fn sanitize_memo(memo: &str) -> SanitizeResult<String> {
    sanitize_string(memo, &SanitizeOptions::for_memo())
}

/// Validate numeric amount is within range
pub fn validate_amount_range(amount: u128, min: u128, max: u128) -> HawalaResult<u128> {
    if amount < min {
        return Err(HawalaError::invalid_input(format!(
            "Amount {} is below minimum {}",
            amount, min
        )));
    }
    if amount > max {
        return Err(HawalaError::invalid_input(format!(
            "Amount {} exceeds maximum {}",
            amount, max
        )));
    }
    Ok(amount)
}

/// Validate gas/fee values
pub fn validate_gas_value(gas: u64, min: u64, max: u64, name: &str) -> HawalaResult<u64> {
    if gas < min {
        return Err(HawalaError::invalid_input(format!(
            "{} {} is below minimum {}",
            name, gas, min
        )));
    }
    if gas > max {
        return Err(HawalaError::invalid_input(format!(
            "{} {} exceeds maximum {}",
            name, gas, max
        )));
    }
    Ok(gas)
}

/// Check for path traversal attempts
pub fn validate_no_path_traversal(path: &str) -> HawalaResult<()> {
    let dangerous_patterns = ["../", "..\\", "..", "%2e%2e", "%252e"];
    
    let lower = path.to_lowercase();
    for pattern in &dangerous_patterns {
        if lower.contains(pattern) {
            return Err(HawalaError::invalid_input(
                "Path contains potentially dangerous traversal pattern"
            ));
        }
    }
    
    // Check for absolute paths
    if path.starts_with('/') || path.starts_with('\\') || path.contains(':') {
        return Err(HawalaError::invalid_input(
            "Absolute paths are not allowed"
        ));
    }
    
    Ok(())
}

/// Validate URL is safe
pub fn validate_safe_url(url: &str) -> HawalaResult<String> {
    let result = sanitize_string(url, &SanitizeOptions::for_url());
    let sanitized = &result.value;
    
    // Parse URL
    let parsed = url::Url::parse(sanitized)
        .map_err(|e| HawalaError::invalid_input(format!("Invalid URL: {}", e)))?;
    
    // Only allow http/https/wss
    let scheme = parsed.scheme();
    if !["http", "https", "wss", "ws"].contains(&scheme) {
        return Err(HawalaError::invalid_input(format!(
            "URL scheme '{}' is not allowed",
            scheme
        )));
    }
    
    // Check for credentials in URL
    if !parsed.username().is_empty() || parsed.password().is_some() {
        return Err(HawalaError::invalid_input(
            "URLs with embedded credentials are not allowed"
        ));
    }
    
    // Check for localhost/internal IPs in production
    if let Some(host) = parsed.host_str() {
        let dangerous_hosts = ["localhost", "127.0.0.1", "0.0.0.0", "::1"];
        if dangerous_hosts.contains(&host) {
            // This might be fine for development, but flag it
            // In production, this should be rejected
        }
    }
    
    Ok(result.value)
}

/// Validate mnemonic format (basic checks)
pub fn validate_mnemonic_format(mnemonic: &str) -> HawalaResult<String> {
    let options = SanitizeOptions {
        trim: true,
        normalize_unicode: true,
        remove_null_bytes: true,
        remove_control_chars: true,
        collapse_whitespace: true,
        max_length: Some(limits::MAX_MNEMONIC_LENGTH),
        ..Default::default()
    };
    
    let result = sanitize_string(mnemonic, &options);
    let sanitized = &result.value;
    
    // Count words
    let words: Vec<&str> = sanitized.split_whitespace().collect();
    let word_count = words.len();
    
    // Valid BIP-39 word counts: 12, 15, 18, 21, 24
    if ![12, 15, 18, 21, 24].contains(&word_count) {
        return Err(HawalaError::invalid_input(format!(
            "Invalid mnemonic word count: {}. Expected 12, 15, 18, 21, or 24 words.",
            word_count
        )));
    }
    
    // Check words are lowercase alphanumeric
    for word in &words {
        if !word.chars().all(|c| c.is_ascii_lowercase()) {
            return Err(HawalaError::invalid_input(
                "Mnemonic words should be lowercase letters only"
            ));
        }
    }
    
    Ok(words.join(" "))
}

/// Validate hex string
pub fn validate_hex(input: &str, expected_bytes: Option<usize>) -> HawalaResult<Vec<u8>> {
    let clean = input.strip_prefix("0x").unwrap_or(input);
    
    if !clean.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(HawalaError::invalid_input("Invalid hexadecimal string"));
    }
    
    if clean.len() % 2 != 0 {
        return Err(HawalaError::invalid_input(
            "Hex string must have even number of characters"
        ));
    }
    
    let bytes = hex::decode(clean)
        .map_err(|e| HawalaError::invalid_input(format!("Failed to decode hex: {}", e)))?;
    
    if let Some(expected) = expected_bytes {
        if bytes.len() != expected {
            return Err(HawalaError::invalid_input(format!(
                "Expected {} bytes, got {}",
                expected,
                bytes.len()
            )));
        }
    }
    
    Ok(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sanitize_basic() {
        let result = sanitize_string("  hello world  ", &SanitizeOptions::default());
        assert_eq!(result.value, "hello world");
        assert!(result.was_modified);
    }

    #[test]
    fn test_sanitize_null_bytes() {
        let result = sanitize_string("hello\0world", &SanitizeOptions::default());
        assert_eq!(result.value, "helloworld");
        assert!(result.was_modified);
    }

    #[test]
    fn test_sanitize_address() {
        let addr = sanitize_address("  bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq  ");
        assert!(addr.is_ok());
        assert_eq!(addr.unwrap(), "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq");
    }

    #[test]
    fn test_address_with_whitespace_fails() {
        let addr = sanitize_address("bc1q ar0srrr");
        assert!(addr.is_err());
    }

    #[test]
    fn test_sanitize_tx_id() {
        let tx = sanitize_tx_id("0xABCDEF123456");
        assert!(tx.is_ok());
        assert_eq!(tx.unwrap(), "0xabcdef123456");
    }

    #[test]
    fn test_strip_html() {
        let result = sanitize_string(
            "<script>alert('xss')</script>Hello",
            &SanitizeOptions {
                strip_html: true,
                ..Default::default()
            }
        );
        assert_eq!(result.value, "alert('xss')Hello");
    }

    #[test]
    fn test_escape_special() {
        let result = sanitize_string(
            "<div>test</div>",
            &SanitizeOptions {
                escape_special: true,
                ..Default::default()
            }
        );
        assert!(result.value.contains("&lt;"));
        assert!(result.value.contains("&gt;"));
    }

    #[test]
    fn test_path_traversal() {
        assert!(validate_no_path_traversal("../etc/passwd").is_err());
        assert!(validate_no_path_traversal("..\\windows\\system32").is_err());
        assert!(validate_no_path_traversal("/absolute/path").is_err());
        assert!(validate_no_path_traversal("safe/path/here").is_ok());
    }

    #[test]
    fn test_validate_mnemonic_format() {
        let valid = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        assert!(validate_mnemonic_format(valid).is_ok());
        
        let invalid = "one two three"; // Only 3 words
        assert!(validate_mnemonic_format(invalid).is_err());
    }

    #[test]
    fn test_validate_hex() {
        assert!(validate_hex("abcdef", None).is_ok());
        assert!(validate_hex("0xABCDEF", None).is_ok());
        assert!(validate_hex("not hex", None).is_err());
        assert!(validate_hex("abc", None).is_err()); // Odd length
        assert!(validate_hex("abcd", Some(2)).is_ok());
        assert!(validate_hex("abcd", Some(3)).is_err());
    }

    #[test]
    fn test_amount_range() {
        assert!(validate_amount_range(100, 0, 1000).is_ok());
        assert!(validate_amount_range(0, 1, 1000).is_err());
        assert!(validate_amount_range(1001, 0, 1000).is_err());
    }

    #[test]
    fn test_safe_url() {
        assert!(validate_safe_url("https://example.com/api").is_ok());
        assert!(validate_safe_url("ftp://example.com").is_err());
        assert!(validate_safe_url("https://user:pass@example.com").is_err());
    }
}
