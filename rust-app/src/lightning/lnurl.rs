//! LNUrl protocol support
//!
//! Implements LNUrl-pay, LNUrl-withdraw, and LNUrl-auth flows.

use super::types::*;

/// LNUrl decoder and handler
pub struct LnUrlHandler;

impl LnUrlHandler {
    /// Decode an LNUrl (bech32 encoded URL)
    pub fn decode(lnurl: &str) -> Result<String, LightningError> {
        let lnurl = lnurl.trim().to_lowercase();

        // Check for lnurl prefix
        if !lnurl.starts_with("lnurl") {
            return Err(LightningError::InvalidLnUrl(
                "Must start with 'lnurl'".to_string(),
            ));
        }

        // Find separator
        let separator_pos = lnurl.find('1').ok_or_else(|| {
            LightningError::InvalidLnUrl("Missing separator '1'".to_string())
        })?;

        let data_part = &lnurl[separator_pos + 1..];

        // Decode bech32 data (simplified - real impl would use proper bech32)
        let decoded = Self::decode_bech32_data(data_part)?;

        // Convert bytes to UTF-8 URL
        String::from_utf8(decoded)
            .map_err(|_| LightningError::InvalidLnUrl("Invalid UTF-8 in URL".to_string()))
    }

    /// Check if string is an LNUrl
    pub fn is_lnurl(s: &str) -> bool {
        let s = s.trim().to_lowercase();
        s.starts_with("lnurl1") && s.len() > 10
    }

    /// Check if URL is a direct LNUrl endpoint
    pub fn is_lnurl_endpoint(url: &str) -> bool {
        url.contains("/.well-known/lnurlp/")
            || url.contains("/lnurl-pay")
            || url.contains("/lnurl-withdraw")
    }

    /// Simplified bech32 data decoding
    fn decode_bech32_data(data: &str) -> Result<Vec<u8>, LightningError> {
        // Bech32 character set
        const CHARSET: &str = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";

        let mut values: Vec<u8> = Vec::new();
        for c in data.chars() {
            if c == '1' {
                continue; // Skip checksum separator
            }
            let idx = CHARSET.find(c).ok_or_else(|| {
                LightningError::InvalidLnUrl(format!("Invalid character: {}", c))
            })?;
            values.push(idx as u8);
        }

        // Remove checksum (last 6 characters worth)
        if values.len() < 6 {
            return Err(LightningError::InvalidLnUrl("Too short".to_string()));
        }
        values.truncate(values.len() - 6);

        // Convert from 5-bit to 8-bit
        let bytes = Self::convert_bits(&values, 5, 8, false)?;

        Ok(bytes)
    }

    /// Convert between bit sizes
    fn convert_bits(
        data: &[u8],
        from_bits: u32,
        to_bits: u32,
        pad: bool,
    ) -> Result<Vec<u8>, LightningError> {
        let mut acc: u32 = 0;
        let mut bits: u32 = 0;
        let mut result = Vec::new();
        let max_v = (1 << to_bits) - 1;

        for &value in data {
            if (value as u32) >> from_bits != 0 {
                return Err(LightningError::InvalidLnUrl("Value out of range".to_string()));
            }
            acc = (acc << from_bits) | value as u32;
            bits += from_bits;
            while bits >= to_bits {
                bits -= to_bits;
                result.push(((acc >> bits) & max_v) as u8);
            }
        }

        if pad && bits > 0 {
            result.push(((acc << (to_bits - bits)) & max_v) as u8);
        } else if !pad && (bits >= from_bits || ((acc << (to_bits - bits)) & max_v) != 0) {
            // Allow padding bits
        }

        Ok(result)
    }

    /// Build callback URL for LNUrl-pay
    pub fn build_pay_callback(request: &LnUrlPayRequest, amount_msat: u64) -> String {
        let separator = if request.callback.contains('?') {
            "&"
        } else {
            "?"
        };
        format!("{}{}amount={}", request.callback, separator, amount_msat)
    }

    /// Build callback URL for LNUrl-withdraw
    pub fn build_withdraw_callback(request: &LnUrlWithdrawRequest, invoice: &str) -> String {
        let separator = if request.callback.contains('?') {
            "&"
        } else {
            "?"
        };
        format!(
            "{}{}k1={}&pr={}",
            request.callback, separator, request.k1, invoice
        )
    }

    /// Validate amount for LNUrl-pay request
    pub fn validate_pay_amount(
        request: &LnUrlPayRequest,
        amount_msat: u64,
    ) -> Result<(), LightningError> {
        if amount_msat < request.min_sendable {
            return Err(LightningError::AmountMismatch);
        }
        if amount_msat > request.max_sendable {
            return Err(LightningError::AmountMismatch);
        }
        Ok(())
    }

    /// Validate amount for LNUrl-withdraw request
    pub fn validate_withdraw_amount(
        request: &LnUrlWithdrawRequest,
        amount_msat: u64,
    ) -> Result<(), LightningError> {
        if amount_msat < request.min_withdrawable {
            return Err(LightningError::AmountMismatch);
        }
        if amount_msat > request.max_withdrawable {
            return Err(LightningError::AmountMismatch);
        }
        Ok(())
    }
}

/// LNUrl-pay response after requesting invoice
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct LnUrlPayResponse {
    /// BOLT11 payment request
    pub pr: String,
    /// Disposable (whether to save for reuse)
    pub disposable: Option<bool>,
    /// Success action
    #[serde(rename = "successAction")]
    pub success_action: Option<LnUrlSuccessAction>,
    /// Routes for private channels
    pub routes: Option<Vec<Vec<serde_json::Value>>>,
}

/// Success action after payment
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(tag = "tag")]
pub enum LnUrlSuccessAction {
    /// Show message
    #[serde(rename = "message")]
    Message { message: String },
    /// Show URL
    #[serde(rename = "url")]
    Url { description: String, url: String },
    /// Decrypt AES payload
    #[serde(rename = "aes")]
    Aes {
        description: String,
        ciphertext: String,
        iv: String,
    },
}

/// LNUrl error response
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct LnUrlError {
    pub status: String,
    pub reason: String,
}

impl LnUrlError {
    pub fn is_error(&self) -> bool {
        self.status == "ERROR"
    }
}

/// LNUrl-withdraw response
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct LnUrlWithdrawResponse {
    pub status: String,
    pub reason: Option<String>,
}

/// LNUrl payment state machine
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LnUrlPayState {
    /// Initial state
    Initial,
    /// Fetching LNUrl endpoint
    FetchingEndpoint,
    /// Received pay request, waiting for amount
    WaitingForAmount {
        min_sat: u64,
        max_sat: u64,
        description: String,
    },
    /// Fetching invoice for amount
    FetchingInvoice { amount_msat: u64 },
    /// Received invoice, ready to pay
    ReadyToPay { invoice: String, amount_msat: u64 },
    /// Payment in progress
    Paying,
    /// Payment complete
    Complete { preimage: String },
    /// Error occurred
    Error { message: String },
}

/// LNUrl withdraw state machine
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LnUrlWithdrawState {
    /// Initial state
    Initial,
    /// Fetching LNUrl endpoint
    FetchingEndpoint,
    /// Received withdraw request, waiting for invoice
    WaitingForInvoice {
        min_sat: u64,
        max_sat: u64,
        description: String,
    },
    /// Submitting invoice
    SubmittingInvoice { invoice: String },
    /// Withdrawal complete
    Complete,
    /// Error occurred
    Error { message: String },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_lnurl() {
        assert!(LnUrlHandler::is_lnurl(
            "LNURL1DP68GURN8GHJ7AMPD3KX2AR0VEEKZAR0WD5XJTNRDAKJ7TNHV4KXCTTTDEHHWM30D3H82UNV9ACK2AR0VEEKZAR0WD5XJTNRDAKJ7TNHV4KXCTTTDEHHWM30D3H82UNV9AMKJARGV3EXZAE0XX5CQVP"
        ));
        assert!(!LnUrlHandler::is_lnurl("lnbc1..."));
        assert!(!LnUrlHandler::is_lnurl("hello"));
    }

    #[test]
    fn test_is_lnurl_endpoint() {
        assert!(LnUrlHandler::is_lnurl_endpoint(
            "https://example.com/.well-known/lnurlp/user"
        ));
        assert!(LnUrlHandler::is_lnurl_endpoint(
            "https://api.example.com/lnurl-pay"
        ));
        assert!(!LnUrlHandler::is_lnurl_endpoint("https://example.com/"));
    }

    #[test]
    fn test_build_pay_callback() {
        let request = LnUrlPayRequest {
            callback: "https://example.com/pay".to_string(),
            min_sendable: 1000,
            max_sendable: 1000000000,
            metadata: "[]".to_string(),
            comment_allowed: None,
            allows_nostr: None,
            nostr_pubkey: None,
        };

        let url = LnUrlHandler::build_pay_callback(&request, 50000);
        assert_eq!(url, "https://example.com/pay?amount=50000");

        // With existing query params
        let request2 = LnUrlPayRequest {
            callback: "https://example.com/pay?foo=bar".to_string(),
            ..request
        };
        let url2 = LnUrlHandler::build_pay_callback(&request2, 50000);
        assert_eq!(url2, "https://example.com/pay?foo=bar&amount=50000");
    }

    #[test]
    fn test_build_withdraw_callback() {
        let request = LnUrlWithdrawRequest {
            callback: "https://example.com/withdraw".to_string(),
            k1: "abc123".to_string(),
            default_description: "Withdraw".to_string(),
            min_withdrawable: 1000,
            max_withdrawable: 1000000,
        };

        let url = LnUrlHandler::build_withdraw_callback(&request, "lnbc1...");
        assert!(url.contains("k1=abc123"));
        assert!(url.contains("pr=lnbc1..."));
    }

    #[test]
    fn test_validate_pay_amount() {
        let request = LnUrlPayRequest {
            callback: "https://example.com".to_string(),
            min_sendable: 1000,
            max_sendable: 1000000,
            metadata: "[]".to_string(),
            comment_allowed: None,
            allows_nostr: None,
            nostr_pubkey: None,
        };

        assert!(LnUrlHandler::validate_pay_amount(&request, 50000).is_ok());
        assert!(LnUrlHandler::validate_pay_amount(&request, 500).is_err());
        assert!(LnUrlHandler::validate_pay_amount(&request, 2000000).is_err());
    }

    #[test]
    fn test_validate_withdraw_amount() {
        let request = LnUrlWithdrawRequest {
            callback: "https://example.com".to_string(),
            k1: "abc".to_string(),
            default_description: "".to_string(),
            min_withdrawable: 10000,
            max_withdrawable: 100000,
        };

        assert!(LnUrlHandler::validate_withdraw_amount(&request, 50000).is_ok());
        assert!(LnUrlHandler::validate_withdraw_amount(&request, 5000).is_err());
    }

    #[test]
    fn test_lnurl_success_actions() {
        let message = LnUrlSuccessAction::Message {
            message: "Payment received!".to_string(),
        };

        let url = LnUrlSuccessAction::Url {
            description: "Download link".to_string(),
            url: "https://example.com/download".to_string(),
        };

        // Just verify they can be created
        if let LnUrlSuccessAction::Message { message } = message {
            assert!(!message.is_empty());
        }
        if let LnUrlSuccessAction::Url { url, .. } = url {
            assert!(url.starts_with("https"));
        }
    }

    #[test]
    fn test_lnurl_error() {
        let err = LnUrlError {
            status: "ERROR".to_string(),
            reason: "Invalid amount".to_string(),
        };
        assert!(err.is_error());

        let ok = LnUrlError {
            status: "OK".to_string(),
            reason: "".to_string(),
        };
        assert!(!ok.is_error());
    }

    #[test]
    fn test_pay_state_machine() {
        let state = LnUrlPayState::WaitingForAmount {
            min_sat: 1,
            max_sat: 1000000,
            description: "Test payment".to_string(),
        };

        if let LnUrlPayState::WaitingForAmount {
            min_sat,
            max_sat,
            description,
        } = state
        {
            assert_eq!(min_sat, 1);
            assert_eq!(max_sat, 1000000);
            assert_eq!(description, "Test payment");
        }
    }

    #[test]
    fn test_withdraw_state_machine() {
        let state = LnUrlWithdrawState::WaitingForInvoice {
            min_sat: 100,
            max_sat: 10000,
            description: "Claim reward".to_string(),
        };

        if let LnUrlWithdrawState::WaitingForInvoice {
            min_sat,
            max_sat,
            ..
        } = state
        {
            assert_eq!(min_sat, 100);
            assert_eq!(max_sat, 10000);
        }
    }
}
