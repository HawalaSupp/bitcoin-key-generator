//! Ordinals and BRC-20 types

use serde::{Deserialize, Serialize};

/// A Bitcoin Ordinal inscription
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Inscription {
    /// Inscription ID (txid:index format)
    pub id: String,
    /// Inscription number
    pub number: u64,
    /// Content type (MIME type)
    pub content_type: String,
    /// Content length in bytes
    pub content_length: u64,
    /// Genesis transaction ID
    pub genesis_tx: String,
    /// Genesis block height
    pub genesis_height: u64,
    /// Current location (satoshi ordinal)
    pub sat: u64,
    /// Current output (txid:vout)
    pub output: String,
    /// Current owner address
    pub address: Option<String>,
    /// Timestamp of inscription
    pub timestamp: u64,
    /// Offset within output
    pub offset: u64,
}

impl Inscription {
    /// Get the inscription content URL from an indexer
    pub fn content_url(&self, base_url: &str) -> String {
        format!("{}/content/{}", base_url, self.id)
    }

    /// Get the inscription preview URL
    pub fn preview_url(&self, base_url: &str) -> String {
        format!("{}/preview/{}", base_url, self.id)
    }

    /// Check if this is an image inscription
    pub fn is_image(&self) -> bool {
        self.content_type.starts_with("image/")
    }

    /// Check if this is a text inscription
    pub fn is_text(&self) -> bool {
        self.content_type.starts_with("text/") || self.content_type == "application/json"
    }

    /// Check if this is HTML
    pub fn is_html(&self) -> bool {
        self.content_type == "text/html"
    }

    /// Check if this might be a BRC-20 inscription
    pub fn is_brc20(&self) -> bool {
        self.content_type == "text/plain" || self.content_type == "application/json"
    }

    /// Get file extension based on content type
    pub fn file_extension(&self) -> &'static str {
        match self.content_type.as_str() {
            "image/png" => "png",
            "image/jpeg" => "jpg",
            "image/gif" => "gif",
            "image/webp" => "webp",
            "image/svg+xml" => "svg",
            "text/plain" => "txt",
            "text/html" => "html",
            "application/json" => "json",
            "audio/mpeg" => "mp3",
            "video/mp4" => "mp4",
            "video/webm" => "webm",
            "model/gltf-binary" => "glb",
            _ => "bin",
        }
    }
}

/// BRC-20 token operation type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Brc20Operation {
    Deploy,
    Mint,
    Transfer,
}

impl Brc20Operation {
    pub fn as_str(&self) -> &'static str {
        match self {
            Brc20Operation::Deploy => "deploy",
            Brc20Operation::Mint => "mint",
            Brc20Operation::Transfer => "transfer",
        }
    }
}

/// BRC-20 inscription content
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Brc20Inscription {
    /// Protocol identifier (always "brc-20")
    #[serde(rename = "p")]
    pub protocol: String,
    /// Operation type
    #[serde(rename = "op")]
    pub operation: Brc20Operation,
    /// Token ticker (4 chars)
    pub tick: String,
    /// Max supply (for deploy)
    pub max: Option<String>,
    /// Mint limit per inscription (for deploy)
    pub lim: Option<String>,
    /// Amount (for mint/transfer)
    pub amt: Option<String>,
    /// Decimals (for deploy, default 18)
    pub dec: Option<String>,
}

impl Brc20Inscription {
    /// Validate the BRC-20 inscription
    pub fn is_valid(&self) -> bool {
        // Protocol must be "brc-20"
        if self.protocol != "brc-20" {
            return false;
        }

        // Ticker must be 4 characters
        if self.tick.len() != 4 {
            return false;
        }

        // Validate based on operation
        match self.operation {
            Brc20Operation::Deploy => self.max.is_some(),
            Brc20Operation::Mint => self.amt.is_some(),
            Brc20Operation::Transfer => self.amt.is_some(),
        }
    }

    /// Get amount as f64
    pub fn amount(&self) -> Option<f64> {
        self.amt.as_ref().and_then(|s| s.parse().ok())
    }

    /// Get max supply as f64
    pub fn max_supply(&self) -> Option<f64> {
        self.max.as_ref().and_then(|s| s.parse().ok())
    }

    /// Get mint limit as f64
    pub fn mint_limit(&self) -> Option<f64> {
        self.lim.as_ref().and_then(|s| s.parse().ok())
    }

    /// Get decimals
    pub fn decimals(&self) -> u8 {
        self.dec
            .as_ref()
            .and_then(|s| s.parse().ok())
            .unwrap_or(18)
    }
}

/// BRC-20 token balance
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Brc20Balance {
    /// Token ticker
    pub tick: String,
    /// Available balance
    pub available: String,
    /// Transferable balance (in pending transfers)
    pub transferable: String,
    /// Total balance
    pub total: String,
}

impl Brc20Balance {
    pub fn available_f64(&self) -> f64 {
        self.available.parse().unwrap_or(0.0)
    }

    pub fn transferable_f64(&self) -> f64 {
        self.transferable.parse().unwrap_or(0.0)
    }

    pub fn total_f64(&self) -> f64 {
        self.total.parse().unwrap_or(0.0)
    }
}

/// BRC-20 token info
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Brc20Token {
    /// Token ticker
    pub tick: String,
    /// Max supply
    pub max_supply: String,
    /// Minted amount
    pub minted: String,
    /// Limit per mint
    pub limit_per_mint: String,
    /// Decimals
    pub decimals: u8,
    /// Deploy inscription ID
    pub deploy_inscription: String,
    /// Deploy block height
    pub deploy_height: u64,
    /// Number of holders
    pub holders: u64,
    /// Number of transactions
    pub transactions: u64,
}

impl Brc20Token {
    /// Calculate mint progress percentage
    pub fn mint_progress(&self) -> f64 {
        let max: f64 = self.max_supply.parse().unwrap_or(0.0);
        let minted: f64 = self.minted.parse().unwrap_or(0.0);
        if max > 0.0 {
            (minted / max) * 100.0
        } else {
            0.0
        }
    }

    /// Check if fully minted
    pub fn is_fully_minted(&self) -> bool {
        self.mint_progress() >= 100.0
    }

    /// Get remaining mintable amount
    pub fn remaining_supply(&self) -> f64 {
        let max: f64 = self.max_supply.parse().unwrap_or(0.0);
        let minted: f64 = self.minted.parse().unwrap_or(0.0);
        (max - minted).max(0.0)
    }
}

/// Ordinals collection
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OrdinalsCollection {
    /// Collection ID
    pub id: String,
    /// Collection name
    pub name: String,
    /// Description
    pub description: Option<String>,
    /// Total supply
    pub supply: u64,
    /// Floor price in BTC
    pub floor_price: Option<f64>,
    /// Total volume in BTC
    pub total_volume: Option<f64>,
    /// Inscription range
    pub inscription_range: Option<(u64, u64)>,
    /// Icon inscription ID
    pub icon: Option<String>,
}

/// Satoshi rarity
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SatoshiRarity {
    Common,
    Uncommon,
    Rare,
    Epic,
    Legendary,
    Mythic,
}

impl SatoshiRarity {
    pub fn from_sat(sat: u64) -> Self {
        // Simplified rarity calculation
        // In reality, this depends on the satoshi's position in blocks/halvings
        if sat == 0 {
            SatoshiRarity::Mythic
        } else if sat % 2_100_000_000_000_000 == 0 {
            SatoshiRarity::Legendary
        } else if sat % 210_000_000_000_000 == 0 {
            SatoshiRarity::Epic
        } else if sat % 52_500_000_000_000 == 0 {
            SatoshiRarity::Rare
        } else if sat % 6_250_000_000 == 0 {
            SatoshiRarity::Uncommon
        } else {
            SatoshiRarity::Common
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            SatoshiRarity::Common => "Common",
            SatoshiRarity::Uncommon => "Uncommon",
            SatoshiRarity::Rare => "Rare",
            SatoshiRarity::Epic => "Epic",
            SatoshiRarity::Legendary => "Legendary",
            SatoshiRarity::Mythic => "Mythic",
        }
    }

    pub fn emoji(&self) -> &'static str {
        match self {
            SatoshiRarity::Common => "⚪",
            SatoshiRarity::Uncommon => "🟢",
            SatoshiRarity::Rare => "🔵",
            SatoshiRarity::Epic => "🟣",
            SatoshiRarity::Legendary => "🟡",
            SatoshiRarity::Mythic => "🔴",
        }
    }
}

/// Error types for Ordinals operations
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum OrdinalsError {
    InvalidInscriptionId(String),
    InscriptionNotFound(String),
    InvalidBrc20(String),
    ApiError(String),
    ParseError(String),
}

impl std::fmt::Display for OrdinalsError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            OrdinalsError::InvalidInscriptionId(id) => {
                write!(f, "Invalid inscription ID: {}", id)
            }
            OrdinalsError::InscriptionNotFound(id) => {
                write!(f, "Inscription not found: {}", id)
            }
            OrdinalsError::InvalidBrc20(msg) => write!(f, "Invalid BRC-20: {}", msg),
            OrdinalsError::ApiError(msg) => write!(f, "API error: {}", msg),
            OrdinalsError::ParseError(msg) => write!(f, "Parse error: {}", msg),
        }
    }
}

impl std::error::Error for OrdinalsError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_inscription() {
        let inscription = Inscription {
            id: "abc123i0".to_string(),
            number: 12345,
            content_type: "image/png".to_string(),
            content_length: 50000,
            genesis_tx: "abc123".to_string(),
            genesis_height: 800000,
            sat: 1234567890,
            output: "abc123:0".to_string(),
            address: Some("bc1q...".to_string()),
            timestamp: 1700000000,
            offset: 0,
        };

        assert!(inscription.is_image());
        assert!(!inscription.is_text());
        assert_eq!(inscription.file_extension(), "png");
        assert!(inscription.content_url("https://ord.io").contains("/content/"));
    }

    #[test]
    fn test_inscription_content_types() {
        let types = vec![
            ("image/png", true, false),
            ("image/jpeg", true, false),
            ("text/plain", false, true),
            ("text/html", false, true),
            ("application/json", false, true),
            ("video/mp4", false, false),
        ];

        for (content_type, is_image, is_text) in types {
            let inscription = Inscription {
                id: "test".to_string(),
                number: 0,
                content_type: content_type.to_string(),
                content_length: 100,
                genesis_tx: "".to_string(),
                genesis_height: 0,
                sat: 0,
                output: "".to_string(),
                address: None,
                timestamp: 0,
                offset: 0,
            };

            assert_eq!(inscription.is_image(), is_image, "Failed for {}", content_type);
            assert_eq!(inscription.is_text(), is_text, "Failed for {}", content_type);
        }
    }

    #[test]
    fn test_brc20_inscription() {
        let deploy = Brc20Inscription {
            protocol: "brc-20".to_string(),
            operation: Brc20Operation::Deploy,
            tick: "ordi".to_string(),
            max: Some("21000000".to_string()),
            lim: Some("1000".to_string()),
            amt: None,
            dec: Some("18".to_string()),
        };

        assert!(deploy.is_valid());
        assert_eq!(deploy.max_supply(), Some(21000000.0));
        assert_eq!(deploy.mint_limit(), Some(1000.0));
        assert_eq!(deploy.decimals(), 18);

        let mint = Brc20Inscription {
            protocol: "brc-20".to_string(),
            operation: Brc20Operation::Mint,
            tick: "ordi".to_string(),
            max: None,
            lim: None,
            amt: Some("1000".to_string()),
            dec: None,
        };

        assert!(mint.is_valid());
        assert_eq!(mint.amount(), Some(1000.0));
    }

    #[test]
    fn test_brc20_validation() {
        // Invalid protocol
        let invalid = Brc20Inscription {
            protocol: "brc-21".to_string(),
            operation: Brc20Operation::Mint,
            tick: "test".to_string(),
            max: None,
            lim: None,
            amt: Some("100".to_string()),
            dec: None,
        };
        assert!(!invalid.is_valid());

        // Invalid ticker length
        let invalid = Brc20Inscription {
            protocol: "brc-20".to_string(),
            operation: Brc20Operation::Mint,
            tick: "toolong".to_string(),
            max: None,
            lim: None,
            amt: Some("100".to_string()),
            dec: None,
        };
        assert!(!invalid.is_valid());
    }

    #[test]
    fn test_brc20_token() {
        let token = Brc20Token {
            tick: "ordi".to_string(),
            max_supply: "21000000".to_string(),
            minted: "21000000".to_string(),
            limit_per_mint: "1000".to_string(),
            decimals: 18,
            deploy_inscription: "abc123i0".to_string(),
            deploy_height: 779832,
            holders: 50000,
            transactions: 1000000,
        };

        assert!(token.is_fully_minted());
        assert_eq!(token.mint_progress(), 100.0);
        assert_eq!(token.remaining_supply(), 0.0);
    }

    #[test]
    fn test_satoshi_rarity() {
        assert_eq!(SatoshiRarity::from_sat(0), SatoshiRarity::Mythic);
        assert_eq!(SatoshiRarity::from_sat(12345), SatoshiRarity::Common);
        assert_eq!(SatoshiRarity::from_sat(6_250_000_000), SatoshiRarity::Uncommon);

        assert_eq!(SatoshiRarity::Common.name(), "Common");
        assert_eq!(SatoshiRarity::Legendary.emoji(), "🟡");
    }

    #[test]
    fn test_brc20_balance() {
        let balance = Brc20Balance {
            tick: "ordi".to_string(),
            available: "1000.5".to_string(),
            transferable: "500.25".to_string(),
            total: "1500.75".to_string(),
        };

        assert_eq!(balance.available_f64(), 1000.5);
        assert_eq!(balance.transferable_f64(), 500.25);
        assert_eq!(balance.total_f64(), 1500.75);
    }

    #[test]
    fn test_ordinals_error() {
        let errors = vec![
            OrdinalsError::InvalidInscriptionId("bad".to_string()),
            OrdinalsError::InscriptionNotFound("notfound".to_string()),
            OrdinalsError::InvalidBrc20("invalid json".to_string()),
            OrdinalsError::ApiError("timeout".to_string()),
            OrdinalsError::ParseError("parse failed".to_string()),
        ];

        for err in errors {
            assert!(!err.to_string().is_empty());
        }
    }
}
