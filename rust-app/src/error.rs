//! Unified error types for Hawala Core
//! 
//! All errors flow through this module for consistent handling
//! and FFI-safe error reporting.

use serde::{Deserialize, Serialize};
use std::fmt;

/// Main error type for all Hawala operations
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HawalaError {
    pub code: ErrorCode,
    pub message: String,
    pub details: Option<String>,
}

impl HawalaError {
    pub fn new(code: ErrorCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
            details: None,
        }
    }

    pub fn with_details(mut self, details: impl Into<String>) -> Self {
        self.details = Some(details.into());
        self
    }

    // Convenience constructors
    pub fn invalid_input(msg: impl Into<String>) -> Self {
        Self::new(ErrorCode::InvalidInput, msg)
    }

    pub fn network_error(msg: impl Into<String>) -> Self {
        Self::new(ErrorCode::NetworkError, msg)
    }

    pub fn crypto_error(msg: impl Into<String>) -> Self {
        Self::new(ErrorCode::CryptoError, msg)
    }

    pub fn signing_failed(msg: impl Into<String>) -> Self {
        Self::new(ErrorCode::SigningFailed, msg)
    }

    pub fn insufficient_funds(msg: impl Into<String>) -> Self {
        Self::new(ErrorCode::InsufficientFunds, msg)
    }

    pub fn broadcast_failed(msg: impl Into<String>) -> Self {
        Self::new(ErrorCode::BroadcastFailed, msg)
    }

    pub fn parse_error(msg: impl Into<String>) -> Self {
        Self::new(ErrorCode::ParseError, msg)
    }

    pub fn internal(msg: impl Into<String>) -> Self {
        Self::new(ErrorCode::Internal, msg)
    }

    pub fn not_implemented(msg: impl Into<String>) -> Self {
        Self::new(ErrorCode::NotImplemented, msg)
    }

    pub fn network(msg: impl Into<String>) -> Self {
        Self::new(ErrorCode::NetworkError, msg)
    }

    pub fn rate_limited(msg: impl Into<String>) -> Self {
        Self::new(ErrorCode::RateLimited, msg)
    }

    pub fn auth_error(msg: impl Into<String>) -> Self {
        Self::new(ErrorCode::AuthError, msg)
    }

    pub fn session_expired(msg: impl Into<String>) -> Self {
        Self::new(ErrorCode::SessionExpired, msg)
    }
}

impl fmt::Display for HawalaError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "[{:?}] {}", self.code, self.message)?;
        if let Some(ref details) = self.details {
            write!(f, " ({})", details)?;
        }
        Ok(())
    }
}

impl std::error::Error for HawalaError {}

/// Error codes for categorization
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorCode {
    // Input errors
    InvalidInput,
    InvalidAddress,
    InvalidMnemonic,
    InvalidPrivateKey,
    InvalidTransaction,
    
    // Authentication errors
    AuthError,
    SessionExpired,
    SessionInvalid,
    
    // Network errors
    NetworkError,
    RateLimited,
    ProviderUnavailable,
    Timeout,
    
    // Transaction errors
    InsufficientFunds,
    InsufficientFee,
    NonceTooLow,
    NonceTooHigh,
    BroadcastFailed,
    TransactionNotFound,
    TransactionRejected,
    
    // Crypto errors
    CryptoError,
    SigningFailed,
    VerificationFailed,
    
    // Parse errors
    ParseError,
    JsonError,
    HexError,
    
    // Internal
    Internal,
    NotImplemented,
}

/// Result type alias for Hawala operations
pub type HawalaResult<T> = Result<T, HawalaError>;

// Conversions from common error types

impl From<serde_json::Error> for HawalaError {
    fn from(e: serde_json::Error) -> Self {
        HawalaError::new(ErrorCode::JsonError, e.to_string())
    }
}

impl From<hex::FromHexError> for HawalaError {
    fn from(e: hex::FromHexError) -> Self {
        HawalaError::new(ErrorCode::HexError, e.to_string())
    }
}

impl From<std::io::Error> for HawalaError {
    fn from(e: std::io::Error) -> Self {
        HawalaError::new(ErrorCode::Internal, e.to_string())
    }
}

impl From<reqwest::Error> for HawalaError {
    fn from(e: reqwest::Error) -> Self {
        if e.is_timeout() {
            HawalaError::new(ErrorCode::Timeout, "Request timed out")
        } else if e.is_connect() {
            HawalaError::new(ErrorCode::NetworkError, "Connection failed")
        } else {
            HawalaError::new(ErrorCode::NetworkError, e.to_string())
        }
    }
}

impl From<bitcoin::bip32::Error> for HawalaError {
    fn from(e: bitcoin::bip32::Error) -> Self {
        HawalaError::new(ErrorCode::CryptoError, format!("BIP32 error: {}", e))
    }
}

impl From<bitcoin::secp256k1::Error> for HawalaError {
    fn from(e: bitcoin::secp256k1::Error) -> Self {
        HawalaError::new(ErrorCode::CryptoError, format!("Secp256k1 error: {}", e))
    }
}

impl From<bip39::Error> for HawalaError {
    fn from(e: bip39::Error) -> Self {
        HawalaError::new(ErrorCode::InvalidMnemonic, format!("BIP39 error: {}", e))
    }
}

impl From<Box<dyn std::error::Error>> for HawalaError {
    fn from(e: Box<dyn std::error::Error>) -> Self {
        HawalaError::new(ErrorCode::Internal, e.to_string())
    }
}

impl From<Box<dyn std::error::Error + Send + Sync>> for HawalaError {
    fn from(e: Box<dyn std::error::Error + Send + Sync>) -> Self {
        HawalaError::new(ErrorCode::Internal, e.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_serialization() {
        let err = HawalaError::insufficient_funds("Not enough BTC")
            .with_details("Required: 0.01 BTC, Available: 0.005 BTC");
        
        let json = serde_json::to_string(&err).unwrap();
        assert!(json.contains("insufficient_funds"));
        assert!(json.contains("Not enough BTC"));
    }
}
