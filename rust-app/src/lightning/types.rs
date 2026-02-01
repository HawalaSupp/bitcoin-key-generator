//! Lightning Network types

use serde::{Deserialize, Serialize};

/// Lightning Network supported
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum LightningNetwork {
    Mainnet,
    Testnet,
    Signet,
    Regtest,
}

impl LightningNetwork {
    /// Get the BOLT11 prefix for this network
    pub fn prefix(&self) -> &'static str {
        match self {
            LightningNetwork::Mainnet => "lnbc",
            LightningNetwork::Testnet => "lntb",
            LightningNetwork::Signet => "lntbs",
            LightningNetwork::Regtest => "lnbcrt",
        }
    }

    /// Detect network from BOLT11 prefix
    pub fn from_prefix(prefix: &str) -> Option<Self> {
        match prefix.to_lowercase().as_str() {
            "lnbc" => Some(LightningNetwork::Mainnet),
            "lntb" => Some(LightningNetwork::Testnet),
            "lntbs" => Some(LightningNetwork::Signet),
            "lnbcrt" => Some(LightningNetwork::Regtest),
            _ => None,
        }
    }
}

/// Amount in millisatoshis
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct MilliSatoshi(pub u64);

impl MilliSatoshi {
    pub fn from_sat(sats: u64) -> Self {
        Self(sats * 1000)
    }

    pub fn from_msat(msats: u64) -> Self {
        Self(msats)
    }

    pub fn as_sat(&self) -> u64 {
        self.0 / 1000
    }

    pub fn as_msat(&self) -> u64 {
        self.0
    }

    pub fn as_btc(&self) -> f64 {
        self.0 as f64 / 100_000_000_000.0
    }

    /// Format as human-readable string
    pub fn display(&self) -> String {
        if self.0 >= 100_000_000_000 {
            format!("{:.8} BTC", self.as_btc())
        } else if self.0 >= 1000 {
            format!("{} sats", self.as_sat())
        } else {
            format!("{} msats", self.0)
        }
    }
}

/// Parsed BOLT11 invoice
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Bolt11Invoice {
    /// Raw invoice string
    pub raw: String,
    /// Network (mainnet, testnet, etc.)
    pub network: LightningNetwork,
    /// Amount in millisatoshis (if specified)
    pub amount_msat: Option<MilliSatoshi>,
    /// Payment hash (32 bytes, hex encoded)
    pub payment_hash: String,
    /// Description (d tag)
    pub description: Option<String>,
    /// Description hash (h tag) - hex encoded
    pub description_hash: Option<String>,
    /// Payee public key (33 bytes, hex encoded)
    pub payee: Option<String>,
    /// Expiry time in seconds (default 3600)
    pub expiry: u64,
    /// Creation timestamp (Unix seconds)
    pub timestamp: u64,
    /// Minimum final CLTV expiry delta
    pub min_final_cltv_expiry: u32,
    /// Routing hints
    pub route_hints: Vec<RouteHint>,
    /// Feature bits
    pub features: Vec<String>,
    /// Fallback on-chain address
    pub fallback_address: Option<String>,
}

impl Bolt11Invoice {
    /// Check if invoice is expired
    pub fn is_expired(&self) -> bool {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        now > self.timestamp + self.expiry
    }

    /// Get time until expiry in seconds
    pub fn seconds_until_expiry(&self) -> i64 {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        (self.timestamp + self.expiry) as i64 - now as i64
    }

    /// Get amount in satoshis
    pub fn amount_sat(&self) -> Option<u64> {
        self.amount_msat.map(|m| m.as_sat())
    }

    /// Check if this is a zero-amount invoice
    pub fn is_zero_amount(&self) -> bool {
        self.amount_msat.is_none()
    }
}

/// Route hint for private channels
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RouteHint {
    /// Pubkey of the hop
    pub pubkey: String,
    /// Short channel ID
    pub short_channel_id: String,
    /// Base fee in millisatoshis
    pub fee_base_msat: u32,
    /// Fee proportional (parts per million)
    pub fee_proportional_millionths: u32,
    /// CLTV expiry delta
    pub cltv_expiry_delta: u16,
}

/// LNUrl response types
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "tag")]
pub enum LnUrlResponse {
    /// Pay request (LNUrl-pay)
    #[serde(rename = "payRequest")]
    PayRequest(LnUrlPayRequest),
    /// Withdraw request (LNUrl-withdraw)
    #[serde(rename = "withdrawRequest")]
    WithdrawRequest(LnUrlWithdrawRequest),
    /// Auth request (LNUrl-auth)
    #[serde(rename = "login")]
    Auth(LnUrlAuthRequest),
    /// Channel request (LNUrl-channel)
    #[serde(rename = "channelRequest")]
    ChannelRequest(LnUrlChannelRequest),
}

/// LNUrl-pay request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LnUrlPayRequest {
    /// Callback URL to get invoice
    pub callback: String,
    /// Minimum sendable amount in millisatoshis
    #[serde(rename = "minSendable")]
    pub min_sendable: u64,
    /// Maximum sendable amount in millisatoshis
    #[serde(rename = "maxSendable")]
    pub max_sendable: u64,
    /// Metadata JSON string
    pub metadata: String,
    /// Comment allowed length
    #[serde(rename = "commentAllowed")]
    pub comment_allowed: Option<u32>,
    /// Allow nostr pubkey in Zaps
    #[serde(rename = "allowsNostr")]
    pub allows_nostr: Option<bool>,
    /// Nostr pubkey for zaps
    #[serde(rename = "nostrPubkey")]
    pub nostr_pubkey: Option<String>,
}

impl LnUrlPayRequest {
    /// Get minimum amount in satoshis
    pub fn min_sat(&self) -> u64 {
        self.min_sendable / 1000
    }

    /// Get maximum amount in satoshis
    pub fn max_sat(&self) -> u64 {
        self.max_sendable / 1000
    }

    /// Parse metadata to get description
    pub fn description(&self) -> Option<String> {
        // Metadata is JSON array of [["text/plain", "description"], ...]
        serde_json::from_str::<Vec<Vec<String>>>(&self.metadata)
            .ok()
            .and_then(|arr| {
                arr.iter()
                    .find(|item| item.len() >= 2 && item[0] == "text/plain")
                    .map(|item| item[1].clone())
            })
    }

    /// Parse metadata to get image
    pub fn image(&self) -> Option<String> {
        serde_json::from_str::<Vec<Vec<String>>>(&self.metadata)
            .ok()
            .and_then(|arr| {
                arr.iter()
                    .find(|item| item.len() >= 2 && item[0].starts_with("image/"))
                    .map(|item| item[1].clone())
            })
    }
}

/// LNUrl-withdraw request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LnUrlWithdrawRequest {
    /// Callback URL to submit invoice
    pub callback: String,
    /// Unique identifier
    pub k1: String,
    /// Default description
    #[serde(rename = "defaultDescription")]
    pub default_description: String,
    /// Minimum withdrawable in millisatoshis
    #[serde(rename = "minWithdrawable")]
    pub min_withdrawable: u64,
    /// Maximum withdrawable in millisatoshis
    #[serde(rename = "maxWithdrawable")]
    pub max_withdrawable: u64,
}

impl LnUrlWithdrawRequest {
    /// Get minimum amount in satoshis
    pub fn min_sat(&self) -> u64 {
        self.min_withdrawable / 1000
    }

    /// Get maximum amount in satoshis
    pub fn max_sat(&self) -> u64 {
        self.max_withdrawable / 1000
    }
}

/// LNUrl-auth request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LnUrlAuthRequest {
    /// Callback URL for authentication
    pub callback: String,
    /// Challenge
    pub k1: String,
    /// Action (register, login, link, auth)
    pub action: Option<String>,
}

/// LNUrl-channel request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LnUrlChannelRequest {
    /// Remote node URI
    pub uri: String,
    /// Callback URL
    pub callback: String,
    /// Challenge
    pub k1: String,
}

/// Lightning payment status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PaymentStatus {
    Pending,
    Complete,
    Failed,
}

/// Lightning payment
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LightningPayment {
    /// Payment hash
    pub payment_hash: String,
    /// Payment preimage (if complete)
    pub preimage: Option<String>,
    /// Amount in millisatoshis
    pub amount_msat: MilliSatoshi,
    /// Fee paid in millisatoshis
    pub fee_msat: Option<MilliSatoshi>,
    /// Payment status
    pub status: PaymentStatus,
    /// Timestamp
    pub created_at: u64,
    /// Description
    pub description: Option<String>,
    /// Destination pubkey
    pub destination: Option<String>,
}

/// Lightning error types
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum LightningError {
    InvalidInvoice(String),
    InvoiceExpired,
    InvalidLnUrl(String),
    NetworkMismatch { expected: String, got: String },
    AmountMismatch,
    PaymentFailed(String),
    ConnectionError(String),
}

impl std::fmt::Display for LightningError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            LightningError::InvalidInvoice(msg) => write!(f, "Invalid invoice: {}", msg),
            LightningError::InvoiceExpired => write!(f, "Invoice has expired"),
            LightningError::InvalidLnUrl(msg) => write!(f, "Invalid LNUrl: {}", msg),
            LightningError::NetworkMismatch { expected, got } => {
                write!(f, "Network mismatch: expected {}, got {}", expected, got)
            }
            LightningError::AmountMismatch => write!(f, "Amount mismatch"),
            LightningError::PaymentFailed(msg) => write!(f, "Payment failed: {}", msg),
            LightningError::ConnectionError(msg) => write!(f, "Connection error: {}", msg),
        }
    }
}

impl std::error::Error for LightningError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_network_prefix() {
        assert_eq!(LightningNetwork::Mainnet.prefix(), "lnbc");
        assert_eq!(LightningNetwork::Testnet.prefix(), "lntb");
        assert_eq!(
            LightningNetwork::from_prefix("lnbc"),
            Some(LightningNetwork::Mainnet)
        );
    }

    #[test]
    fn test_millisatoshi() {
        let msat = MilliSatoshi::from_sat(1000);
        assert_eq!(msat.as_msat(), 1_000_000);
        assert_eq!(msat.as_sat(), 1000);

        let msat = MilliSatoshi(100_000_000_000); // 1 BTC
        assert_eq!(msat.as_btc(), 1.0);
        assert!(msat.display().contains("BTC"));

        let msat = MilliSatoshi(1000000);
        assert!(msat.display().contains("sats"));

        let msat = MilliSatoshi(500);
        assert!(msat.display().contains("msats"));
    }

    #[test]
    fn test_lnurl_pay_metadata() {
        let req = LnUrlPayRequest {
            callback: "https://example.com/lnurl".to_string(),
            min_sendable: 1000,
            max_sendable: 1000000000,
            metadata: r#"[["text/plain", "Pay to @user"], ["image/png;base64", "abc123"]]"#
                .to_string(),
            comment_allowed: Some(255),
            allows_nostr: Some(true),
            nostr_pubkey: None,
        };

        assert_eq!(req.min_sat(), 1);
        assert_eq!(req.max_sat(), 1000000);
        assert_eq!(req.description(), Some("Pay to @user".to_string()));
        assert_eq!(req.image(), Some("abc123".to_string()));
    }

    #[test]
    fn test_lightning_error_display() {
        let err = LightningError::InvalidInvoice("bad format".to_string());
        assert!(err.to_string().contains("bad format"));

        let err = LightningError::NetworkMismatch {
            expected: "mainnet".to_string(),
            got: "testnet".to_string(),
        };
        assert!(err.to_string().contains("mainnet"));
        assert!(err.to_string().contains("testnet"));
    }
}
