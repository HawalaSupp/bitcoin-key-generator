//! Payment Request Links
//!
//! Create and parse shareable payment request links.
//! Format: hawala://pay?to=0x...&amount=1.5&token=ETH&chain=1&memo=...
//!
//! Also supports EIP-681 (ethereum:) and BIP-21 (bitcoin:) URIs

use crate::error::{HawalaError, HawalaResult, ErrorCode};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

// =============================================================================
// Types
// =============================================================================

/// Payment request details
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PaymentRequest {
    /// Recipient address
    pub to: String,
    /// Amount to send (decimal string)
    pub amount: Option<String>,
    /// Token symbol or contract address
    pub token: Option<String>,
    /// Chain ID
    pub chain_id: Option<u64>,
    /// Memo/note for the payment
    pub memo: Option<String>,
    /// Request ID for tracking
    pub request_id: Option<String>,
    /// Expiration timestamp (Unix)
    pub expires_at: Option<u64>,
    /// Callback URL for payment confirmation
    pub callback_url: Option<String>,
}

/// Parsed payment link result
#[derive(Debug, Clone, Serialize)]
pub struct ParsedPaymentLink {
    /// Original URI
    pub uri: String,
    /// URI scheme (hawala, ethereum, bitcoin)
    pub scheme: String,
    /// Extracted payment request
    pub request: PaymentRequest,
    /// Whether the link is valid
    pub is_valid: bool,
    /// Validation errors if any
    pub errors: Vec<String>,
}

/// Payment link format
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LinkFormat {
    /// hawala://pay?...
    Hawala,
    /// ethereum:0x...@chainId/transfer?...
    Ethereum,
    /// bitcoin:address?amount=...
    Bitcoin,
    /// solana:address?amount=...
    Solana,
}

// =============================================================================
// Payment Link Manager
// =============================================================================

/// Creates and parses payment request links
pub struct PaymentLinkManager;

impl PaymentLinkManager {
    /// Create a new payment link manager
    pub fn new() -> Self {
        Self
    }

    /// Create a Hawala payment link
    pub fn create_link(&self, request: &PaymentRequest) -> HawalaResult<String> {
        self.validate_request(request)?;

        let mut params = Vec::new();
        params.push(format!("to={}", request.to));

        if let Some(ref amount) = request.amount {
            params.push(format!("amount={}", amount));
        }

        if let Some(ref token) = request.token {
            params.push(format!("token={}", urlencoding::encode(token)));
        }

        if let Some(chain_id) = request.chain_id {
            params.push(format!("chain={}", chain_id));
        }

        if let Some(ref memo) = request.memo {
            params.push(format!("memo={}", urlencoding::encode(memo)));
        }

        if let Some(ref request_id) = request.request_id {
            params.push(format!("id={}", request_id));
        }

        if let Some(expires) = request.expires_at {
            params.push(format!("expires={}", expires));
        }

        if let Some(ref callback) = request.callback_url {
            params.push(format!("callback={}", urlencoding::encode(callback)));
        }

        Ok(format!("hawala://pay?{}", params.join("&")))
    }

    /// Create an EIP-681 compatible link (ethereum:)
    pub fn create_eip681_link(&self, request: &PaymentRequest) -> HawalaResult<String> {
        self.validate_request(request)?;

        let chain_suffix = request.chain_id
            .filter(|&c| c != 1)
            .map(|c| format!("@{}", c))
            .unwrap_or_default();

        let mut uri = format!("ethereum:{}{}", request.to, chain_suffix);

        if let Some(ref token) = request.token {
            // ERC-20 transfer
            if token.starts_with("0x") && token.len() == 42 {
                uri = format!("ethereum:{}{}/transfer", token, chain_suffix);
                
                let mut params = vec![format!("address={}", request.to)];
                
                if let Some(ref amount) = request.amount {
                    // Convert to uint256 (wei)
                    params.push(format!("uint256={}", amount));
                }
                
                uri = format!("{}?{}", uri, params.join("&"));
                return Ok(uri);
            }
        }

        // Native ETH transfer
        let mut params = Vec::new();
        
        if let Some(ref amount) = request.amount {
            params.push(format!("value={}", amount));
        }

        if !params.is_empty() {
            uri = format!("{}?{}", uri, params.join("&"));
        }

        Ok(uri)
    }

    /// Create a BIP-21 compatible link (bitcoin:)
    pub fn create_bip21_link(&self, request: &PaymentRequest) -> HawalaResult<String> {
        self.validate_request(request)?;

        let mut uri = format!("bitcoin:{}", request.to);
        let mut params = Vec::new();

        if let Some(ref amount) = request.amount {
            params.push(format!("amount={}", amount));
        }

        if let Some(ref memo) = request.memo {
            params.push(format!("message={}", urlencoding::encode(memo)));
        }

        if !params.is_empty() {
            uri = format!("{}?{}", uri, params.join("&"));
        }

        Ok(uri)
    }

    /// Parse any payment link format
    pub fn parse_link(&self, uri: &str) -> HawalaResult<ParsedPaymentLink> {
        let scheme = self.detect_scheme(uri)?;

        match scheme {
            LinkFormat::Hawala => self.parse_hawala_link(uri),
            LinkFormat::Ethereum => self.parse_eip681_link(uri),
            LinkFormat::Bitcoin => self.parse_bip21_link(uri),
            LinkFormat::Solana => self.parse_solana_link(uri),
        }
    }

    /// Validate a payment request
    pub fn validate_request(&self, request: &PaymentRequest) -> HawalaResult<()> {
        // Validate address
        if request.to.is_empty() {
            return Err(HawalaError::new(ErrorCode::InvalidInput, "Recipient address required"));
        }

        // Validate amount if present
        if let Some(ref amount) = request.amount {
            if amount.parse::<f64>().is_err() {
                return Err(HawalaError::new(ErrorCode::InvalidInput, "Invalid amount format"));
            }
            
            let amt: f64 = amount.parse().unwrap();
            if amt <= 0.0 {
                return Err(HawalaError::new(ErrorCode::InvalidInput, "Amount must be positive"));
            }
        }

        // Check expiration
        if let Some(expires) = request.expires_at {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs();
            
            if expires < now {
                return Err(HawalaError::new(ErrorCode::InvalidInput, "Payment request has expired"));
            }
        }

        Ok(())
    }

    // =========================================================================
    // Private Methods
    // =========================================================================

    fn detect_scheme(&self, uri: &str) -> HawalaResult<LinkFormat> {
        let lower = uri.to_lowercase();
        
        if lower.starts_with("hawala://") {
            Ok(LinkFormat::Hawala)
        } else if lower.starts_with("ethereum:") {
            Ok(LinkFormat::Ethereum)
        } else if lower.starts_with("bitcoin:") {
            Ok(LinkFormat::Bitcoin)
        } else if lower.starts_with("solana:") {
            Ok(LinkFormat::Solana)
        } else {
            Err(HawalaError::new(ErrorCode::InvalidInput, "Unknown payment link scheme"))
        }
    }

    fn parse_hawala_link(&self, uri: &str) -> HawalaResult<ParsedPaymentLink> {
        let rest = uri.strip_prefix("hawala://pay?")
            .or_else(|| uri.strip_prefix("hawala://pay/"))
            .ok_or_else(|| HawalaError::new(ErrorCode::InvalidInput, "Invalid Hawala URI format"))?;

        let params = self.parse_query_string(rest);
        let mut errors = Vec::new();

        let to = params.get("to").cloned().unwrap_or_default();
        if to.is_empty() {
            errors.push("Missing recipient address".to_string());
        }

        let amount = params.get("amount").cloned();
        let token = params.get("token").map(|t| urlencoding::decode(t).unwrap_or_default().to_string());
        let chain_id = params.get("chain").and_then(|c| c.parse().ok());
        let memo = params.get("memo").map(|m| urlencoding::decode(m).unwrap_or_default().to_string());
        let request_id = params.get("id").cloned();
        let expires_at = params.get("expires").and_then(|e| e.parse().ok());
        let callback_url = params.get("callback").map(|c| urlencoding::decode(c).unwrap_or_default().to_string());

        let request = PaymentRequest {
            to,
            amount,
            token,
            chain_id,
            memo,
            request_id,
            expires_at,
            callback_url,
        };

        Ok(ParsedPaymentLink {
            uri: uri.to_string(),
            scheme: "hawala".to_string(),
            request,
            is_valid: errors.is_empty(),
            errors,
        })
    }

    fn parse_eip681_link(&self, uri: &str) -> HawalaResult<ParsedPaymentLink> {
        let rest = uri.strip_prefix("ethereum:")
            .ok_or_else(|| HawalaError::new(ErrorCode::InvalidInput, "Invalid Ethereum URI"))?;

        let mut errors = Vec::new();
        let mut chain_id: Option<u64> = Some(1); // Default to mainnet
        let mut token: Option<String> = None;
        let mut amount: Option<String> = None;

        // Parse address[@chainId][/function]?params
        let (path, query) = rest.split_once('?').unwrap_or((rest, ""));
        
        // Handle chain ID and extract address
        let (mut to, path) = if let Some((addr, chain)) = path.split_once('@') {
            if let Some((chain_str, rest)) = chain.split_once('/') {
                chain_id = chain_str.parse().ok();
                (addr.to_string(), rest)
            } else {
                chain_id = chain.parse().ok();
                (addr.to_string(), "")
            }
        } else if let Some((addr, _func)) = path.split_once('/') {
            (addr.to_string(), path.split_once('/').map(|(_, f)| f).unwrap_or(""))
        } else {
            (path.to_string(), "")
        };

        // If there's a function, this might be an ERC-20 transfer
        if path == "transfer" || path.starts_with("transfer?") {
            token = Some(to.clone());
            // The actual recipient is in the params
        }

        let params = self.parse_query_string(query);
        
        if let Some(addr) = params.get("address") {
            to = addr.clone();
        }
        
        if let Some(val) = params.get("value").or(params.get("uint256")) {
            amount = Some(val.clone());
        }

        if to.is_empty() {
            errors.push("Missing recipient address".to_string());
        }

        let request = PaymentRequest {
            to,
            amount,
            token,
            chain_id,
            memo: None,
            request_id: None,
            expires_at: None,
            callback_url: None,
        };

        Ok(ParsedPaymentLink {
            uri: uri.to_string(),
            scheme: "ethereum".to_string(),
            request,
            is_valid: errors.is_empty(),
            errors,
        })
    }

    fn parse_bip21_link(&self, uri: &str) -> HawalaResult<ParsedPaymentLink> {
        let rest = uri.strip_prefix("bitcoin:")
            .ok_or_else(|| HawalaError::new(ErrorCode::InvalidInput, "Invalid Bitcoin URI"))?;

        let (address, query) = rest.split_once('?').unwrap_or((rest, ""));
        let params = self.parse_query_string(query);

        let mut errors = Vec::new();
        if address.is_empty() {
            errors.push("Missing Bitcoin address".to_string());
        }

        let request = PaymentRequest {
            to: address.to_string(),
            amount: params.get("amount").cloned(),
            token: Some("BTC".to_string()),
            chain_id: None,
            memo: params.get("message").or(params.get("label")).cloned(),
            request_id: None,
            expires_at: None,
            callback_url: None,
        };

        Ok(ParsedPaymentLink {
            uri: uri.to_string(),
            scheme: "bitcoin".to_string(),
            request,
            is_valid: errors.is_empty(),
            errors,
        })
    }

    fn parse_solana_link(&self, uri: &str) -> HawalaResult<ParsedPaymentLink> {
        let rest = uri.strip_prefix("solana:")
            .ok_or_else(|| HawalaError::new(ErrorCode::InvalidInput, "Invalid Solana URI"))?;

        let (address, query) = rest.split_once('?').unwrap_or((rest, ""));
        let params = self.parse_query_string(query);

        let mut errors = Vec::new();
        if address.is_empty() {
            errors.push("Missing Solana address".to_string());
        }

        let request = PaymentRequest {
            to: address.to_string(),
            amount: params.get("amount").cloned(),
            token: params.get("spl-token").cloned().or(Some("SOL".to_string())),
            chain_id: None,
            memo: params.get("memo").cloned(),
            request_id: params.get("reference").cloned(),
            expires_at: None,
            callback_url: None,
        };

        Ok(ParsedPaymentLink {
            uri: uri.to_string(),
            scheme: "solana".to_string(),
            request,
            is_valid: errors.is_empty(),
            errors,
        })
    }

    fn parse_query_string(&self, query: &str) -> HashMap<String, String> {
        query
            .split('&')
            .filter(|s| !s.is_empty())
            .filter_map(|pair| {
                let mut parts = pair.splitn(2, '=');
                let key = parts.next()?;
                let value = parts.next().unwrap_or("");
                Some((key.to_string(), value.to_string()))
            })
            .collect()
    }
}

impl Default for PaymentLinkManager {
    fn default() -> Self {
        Self::new()
    }
}

// =============================================================================
// Convenience Functions
// =============================================================================

/// Create a payment link
pub fn create_payment_link(request: &PaymentRequest) -> HawalaResult<String> {
    PaymentLinkManager::new().create_link(request)
}

/// Parse a payment link
pub fn parse_payment_link(uri: &str) -> HawalaResult<ParsedPaymentLink> {
    PaymentLinkManager::new().parse_link(uri)
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_hawala_link() {
        let manager = PaymentLinkManager::new();
        
        let request = PaymentRequest {
            to: "0x1234567890abcdef1234567890abcdef12345678".to_string(),
            amount: Some("1.5".to_string()),
            token: Some("ETH".to_string()),
            chain_id: Some(1),
            memo: Some("Payment for services".to_string()),
            request_id: Some("req123".to_string()),
            expires_at: None,
            callback_url: None,
        };

        let link = manager.create_link(&request).unwrap();
        assert!(link.starts_with("hawala://pay?"));
        assert!(link.contains("to=0x"));
        assert!(link.contains("amount=1.5"));
        assert!(link.contains("token=ETH"));
        assert!(link.contains("chain=1"));
    }

    #[test]
    fn test_parse_hawala_link() {
        let manager = PaymentLinkManager::new();
        
        let uri = "hawala://pay?to=0x1234&amount=1.5&token=ETH&chain=1&memo=test";
        let parsed = manager.parse_link(uri).unwrap();
        
        assert_eq!(parsed.scheme, "hawala");
        assert_eq!(parsed.request.to, "0x1234");
        assert_eq!(parsed.request.amount, Some("1.5".to_string()));
        assert_eq!(parsed.request.token, Some("ETH".to_string()));
        assert_eq!(parsed.request.chain_id, Some(1));
    }

    #[test]
    fn test_create_bip21_link() {
        let manager = PaymentLinkManager::new();
        
        let request = PaymentRequest {
            to: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh".to_string(),
            amount: Some("0.001".to_string()),
            token: None,
            chain_id: None,
            memo: Some("Coffee payment".to_string()),
            request_id: None,
            expires_at: None,
            callback_url: None,
        };

        let link = manager.create_bip21_link(&request).unwrap();
        assert!(link.starts_with("bitcoin:bc1q"));
        assert!(link.contains("amount=0.001"));
        assert!(link.contains("message="));
    }

    #[test]
    fn test_parse_bip21_link() {
        let manager = PaymentLinkManager::new();
        
        let uri = "bitcoin:bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh?amount=0.001&label=Test";
        let parsed = manager.parse_link(uri).unwrap();
        
        assert_eq!(parsed.scheme, "bitcoin");
        assert!(parsed.request.to.starts_with("bc1q"));
        assert_eq!(parsed.request.amount, Some("0.001".to_string()));
    }

    #[test]
    fn test_parse_eip681_link() {
        let manager = PaymentLinkManager::new();
        
        // Simple ETH transfer
        let uri = "ethereum:0x1234567890abcdef1234567890abcdef12345678?value=1000000000000000000";
        let parsed = manager.parse_link(uri).unwrap();
        
        assert_eq!(parsed.scheme, "ethereum");
        assert!(parsed.request.to.starts_with("0x"));
    }

    #[test]
    fn test_validate_request() {
        let manager = PaymentLinkManager::new();
        
        // Valid request
        let valid = PaymentRequest {
            to: "0x1234".to_string(),
            amount: Some("1.5".to_string()),
            token: None,
            chain_id: None,
            memo: None,
            request_id: None,
            expires_at: None,
            callback_url: None,
        };
        assert!(manager.validate_request(&valid).is_ok());

        // Invalid - empty address
        let invalid_addr = PaymentRequest {
            to: "".to_string(),
            ..valid.clone()
        };
        assert!(manager.validate_request(&invalid_addr).is_err());

        // Invalid - negative amount
        let invalid_amount = PaymentRequest {
            amount: Some("-1".to_string()),
            ..valid.clone()
        };
        assert!(manager.validate_request(&invalid_amount).is_err());
    }

    #[test]
    fn test_detect_scheme() {
        let manager = PaymentLinkManager::new();
        
        assert!(matches!(manager.detect_scheme("hawala://pay?to=0x"), Ok(LinkFormat::Hawala)));
        assert!(matches!(manager.detect_scheme("ethereum:0x123"), Ok(LinkFormat::Ethereum)));
        assert!(matches!(manager.detect_scheme("bitcoin:bc1q"), Ok(LinkFormat::Bitcoin)));
        assert!(matches!(manager.detect_scheme("solana:abc"), Ok(LinkFormat::Solana)));
        assert!(manager.detect_scheme("unknown:test").is_err());
    }
}
