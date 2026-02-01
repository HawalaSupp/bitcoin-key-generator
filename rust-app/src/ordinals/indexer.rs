//! Ordinals indexer API clients
//!
//! Provides integration with popular Ordinals indexers like Hiro Ordinals API and OrdAPI.

use super::types::*;

/// Known Ordinals API endpoints
pub struct OrdinalsEndpoints;

impl OrdinalsEndpoints {
    /// Hiro Ordinals API (mainnet)
    pub const HIRO_MAINNET: &'static str = "https://api.hiro.so/ordinals/v1";

    /// OrdAPI
    pub const ORD_API: &'static str = "https://ordapi.xyz";

    /// Ordinals.com
    pub const ORDINALS_COM: &'static str = "https://ordinals.com";

    /// Magic Eden Ordinals API
    pub const MAGIC_EDEN: &'static str = "https://api-mainnet.magiceden.dev/v2/ord";

    /// Unisat API
    pub const UNISAT: &'static str = "https://open-api.unisat.io/v1";
}

/// Hiro Ordinals API client
pub struct HiroOrdinalsClient {
    base_url: String,
    api_key: Option<String>,
}

impl Default for HiroOrdinalsClient {
    fn default() -> Self {
        Self::new()
    }
}

impl HiroOrdinalsClient {
    pub fn new() -> Self {
        Self {
            base_url: OrdinalsEndpoints::HIRO_MAINNET.to_string(),
            api_key: None,
        }
    }

    pub fn with_api_key(mut self, api_key: &str) -> Self {
        self.api_key = Some(api_key.to_string());
        self
    }

    /// Get inscriptions for an address
    pub fn inscriptions_by_address_url(&self, address: &str) -> String {
        format!("{}/inscriptions?address={}", self.base_url, address)
    }

    /// Get inscription by ID
    pub fn inscription_url(&self, inscription_id: &str) -> String {
        format!("{}/inscriptions/{}", self.base_url, inscription_id)
    }

    /// Get inscription content
    pub fn inscription_content_url(&self, inscription_id: &str) -> String {
        format!("{}/inscriptions/{}/content", self.base_url, inscription_id)
    }

    /// Get inscriptions in a block
    pub fn inscriptions_by_block_url(&self, block_height: u64) -> String {
        format!("{}/inscriptions?genesis_block={}", self.base_url, block_height)
    }

    /// Get inscriptions by satoshi
    pub fn inscriptions_by_sat_url(&self, sat: u64) -> String {
        format!("{}/sats/{}/inscriptions", self.base_url, sat)
    }

    /// Get sat info
    pub fn sat_url(&self, sat: u64) -> String {
        format!("{}/sats/{}", self.base_url, sat)
    }

    /// Get BRC-20 tokens
    pub fn brc20_tokens_url(&self) -> String {
        format!("{}/brc-20/tokens", self.base_url)
    }

    /// Get BRC-20 token info
    pub fn brc20_token_url(&self, ticker: &str) -> String {
        format!("{}/brc-20/tokens/{}", self.base_url, ticker)
    }

    /// Get BRC-20 balances for address
    pub fn brc20_balances_url(&self, address: &str) -> String {
        format!("{}/brc-20/balances/{}", self.base_url, address)
    }

    /// Get BRC-20 activity for address
    pub fn brc20_activity_url(&self, address: &str) -> String {
        format!("{}/brc-20/activity?address={}", self.base_url, address)
    }

    /// Parse inscriptions response
    pub fn parse_inscriptions_response(json: &serde_json::Value) -> Vec<Inscription> {
        let results = json.get("results").and_then(|r| r.as_array());

        results
            .map(|arr| {
                arr.iter()
                    .filter_map(|item| Self::parse_inscription(item))
                    .collect()
            })
            .unwrap_or_default()
    }

    /// Parse a single inscription from JSON
    pub fn parse_inscription(json: &serde_json::Value) -> Option<Inscription> {
        Some(Inscription {
            id: json.get("id")?.as_str()?.to_string(),
            number: json.get("number")?.as_u64()?,
            content_type: json
                .get("content_type")
                .and_then(|v| v.as_str())
                .unwrap_or("application/octet-stream")
                .to_string(),
            content_length: json.get("content_length").and_then(|v| v.as_u64()).unwrap_or(0),
            genesis_tx: json
                .get("genesis_tx_id")
                .or_else(|| json.get("genesis_transaction_id"))
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string(),
            genesis_height: json
                .get("genesis_block_height")
                .and_then(|v| v.as_u64())
                .unwrap_or(0),
            sat: json.get("sat_ordinal").and_then(|v| v.as_u64()).unwrap_or(0),
            output: json.get("output").and_then(|v| v.as_str()).unwrap_or("").to_string(),
            address: json.get("address").and_then(|v| v.as_str()).map(String::from),
            timestamp: json.get("timestamp").and_then(|v| v.as_u64()).unwrap_or(0),
            offset: json.get("offset").and_then(|v| v.as_u64()).unwrap_or(0),
        })
    }

    /// Parse BRC-20 balances response
    pub fn parse_brc20_balances(json: &serde_json::Value) -> Vec<Brc20Balance> {
        let results = json.get("results").and_then(|r| r.as_array());

        results
            .map(|arr| {
                arr.iter()
                    .filter_map(|item| {
                        Some(Brc20Balance {
                            tick: item.get("ticker")?.as_str()?.to_string(),
                            available: item
                                .get("available_balance")
                                .and_then(|v| v.as_str())
                                .unwrap_or("0")
                                .to_string(),
                            transferable: item
                                .get("transferrable_balance")
                                .and_then(|v| v.as_str())
                                .unwrap_or("0")
                                .to_string(),
                            total: item
                                .get("overall_balance")
                                .and_then(|v| v.as_str())
                                .unwrap_or("0")
                                .to_string(),
                        })
                    })
                    .collect()
            })
            .unwrap_or_default()
    }

    /// Parse BRC-20 token info
    pub fn parse_brc20_token(json: &serde_json::Value) -> Option<Brc20Token> {
        let token = json.get("token")?;
        Some(Brc20Token {
            tick: token.get("ticker")?.as_str()?.to_string(),
            max_supply: token
                .get("max_supply")
                .and_then(|v| v.as_str())
                .unwrap_or("0")
                .to_string(),
            minted: token
                .get("minted_supply")
                .and_then(|v| v.as_str())
                .unwrap_or("0")
                .to_string(),
            limit_per_mint: token
                .get("mint_limit")
                .and_then(|v| v.as_str())
                .unwrap_or("0")
                .to_string(),
            decimals: token.get("decimals").and_then(|v| v.as_u64()).unwrap_or(18) as u8,
            deploy_inscription: token
                .get("deploy_inscription_id")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string(),
            deploy_height: token
                .get("block_height")
                .and_then(|v| v.as_u64())
                .unwrap_or(0),
            holders: json
                .get("holders")
                .and_then(|v| v.as_u64())
                .unwrap_or(0),
            transactions: json
                .get("tx_count")
                .and_then(|v| v.as_u64())
                .unwrap_or(0),
        })
    }
}

/// Unisat API client for BRC-20
pub struct UnisatClient {
    base_url: String,
    api_key: Option<String>,
}

impl Default for UnisatClient {
    fn default() -> Self {
        Self::new()
    }
}

impl UnisatClient {
    pub fn new() -> Self {
        Self {
            base_url: OrdinalsEndpoints::UNISAT.to_string(),
            api_key: None,
        }
    }

    pub fn with_api_key(mut self, api_key: &str) -> Self {
        self.api_key = Some(api_key.to_string());
        self
    }

    /// Get BRC-20 summary for address
    pub fn brc20_summary_url(&self, address: &str) -> String {
        format!("{}/indexer/address/{}/brc20/summary", self.base_url, address)
    }

    /// Get inscription UTXO for address
    pub fn inscription_utxo_url(&self, address: &str) -> String {
        format!("{}/indexer/address/{}/inscription-utxo-data", self.base_url, address)
    }

    /// Get BRC-20 transferable list
    pub fn brc20_transferable_url(&self, address: &str, ticker: &str) -> String {
        format!(
            "{}/indexer/address/{}/brc20/{}/transferable-list",
            self.base_url, address, ticker
        )
    }
}

/// Magic Eden Ordinals client
pub struct MagicEdenClient {
    base_url: String,
    api_key: Option<String>,
}

impl Default for MagicEdenClient {
    fn default() -> Self {
        Self::new()
    }
}

impl MagicEdenClient {
    pub fn new() -> Self {
        Self {
            base_url: OrdinalsEndpoints::MAGIC_EDEN.to_string(),
            api_key: None,
        }
    }

    pub fn with_api_key(mut self, api_key: &str) -> Self {
        self.api_key = Some(api_key.to_string());
        self
    }

    /// Get collection stats
    pub fn collection_stats_url(&self, collection_symbol: &str) -> String {
        format!("{}/collection_stats?collectionSymbol={}", self.base_url, collection_symbol)
    }

    /// Get listings for collection
    pub fn listings_url(&self, collection_symbol: &str) -> String {
        format!("{}/tokens?collectionSymbol={}&listStatus=listed", self.base_url, collection_symbol)
    }

    /// Get inscription by ID
    pub fn inscription_url(&self, inscription_id: &str) -> String {
        format!("{}/token/{}", self.base_url, inscription_id)
    }

    /// Get activities for collection
    pub fn activities_url(&self, collection_symbol: &str) -> String {
        format!("{}/activities?collectionSymbol={}", self.base_url, collection_symbol)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hiro_client_urls() {
        let client = HiroOrdinalsClient::new();

        let url = client.inscriptions_by_address_url("bc1q...");
        assert!(url.contains("/inscriptions?address="));

        let url = client.inscription_url("abc123i0");
        assert!(url.contains("/inscriptions/abc123i0"));

        let url = client.inscription_content_url("abc123i0");
        assert!(url.contains("/content"));

        let url = client.brc20_tokens_url();
        assert!(url.contains("/brc-20/tokens"));

        let url = client.brc20_balances_url("bc1q...");
        assert!(url.contains("/brc-20/balances/"));
    }

    #[test]
    fn test_parse_inscription() {
        let json = serde_json::json!({
            "id": "abc123i0",
            "number": 12345,
            "content_type": "image/png",
            "content_length": 50000,
            "genesis_tx_id": "abc123",
            "genesis_block_height": 800000,
            "sat_ordinal": 1234567890,
            "output": "abc123:0",
            "address": "bc1q...",
            "timestamp": 1700000000,
            "offset": 0
        });

        let inscription = HiroOrdinalsClient::parse_inscription(&json);
        assert!(inscription.is_some());

        let inscription = inscription.unwrap();
        assert_eq!(inscription.id, "abc123i0");
        assert_eq!(inscription.number, 12345);
        assert_eq!(inscription.content_type, "image/png");
    }

    #[test]
    fn test_parse_inscriptions_response() {
        let json = serde_json::json!({
            "results": [
                {
                    "id": "abc123i0",
                    "number": 12345,
                    "content_type": "image/png",
                    "content_length": 50000,
                    "genesis_tx_id": "abc123",
                    "genesis_block_height": 800000
                },
                {
                    "id": "def456i0",
                    "number": 12346,
                    "content_type": "text/plain",
                    "content_length": 100,
                    "genesis_tx_id": "def456",
                    "genesis_block_height": 800001
                }
            ],
            "total": 2,
            "limit": 60,
            "offset": 0
        });

        let inscriptions = HiroOrdinalsClient::parse_inscriptions_response(&json);
        assert_eq!(inscriptions.len(), 2);
        assert_eq!(inscriptions[0].id, "abc123i0");
        assert_eq!(inscriptions[1].id, "def456i0");
    }

    #[test]
    fn test_parse_brc20_balances() {
        let json = serde_json::json!({
            "results": [
                {
                    "ticker": "ordi",
                    "available_balance": "1000.5",
                    "transferrable_balance": "0",
                    "overall_balance": "1000.5"
                },
                {
                    "ticker": "sats",
                    "available_balance": "50000000",
                    "transferrable_balance": "10000000",
                    "overall_balance": "60000000"
                }
            ]
        });

        let balances = HiroOrdinalsClient::parse_brc20_balances(&json);
        assert_eq!(balances.len(), 2);
        assert_eq!(balances[0].tick, "ordi");
        assert_eq!(balances[0].available_f64(), 1000.5);
    }

    #[test]
    fn test_parse_brc20_token() {
        let json = serde_json::json!({
            "token": {
                "ticker": "ordi",
                "max_supply": "21000000",
                "minted_supply": "21000000",
                "mint_limit": "1000",
                "decimals": 18,
                "deploy_inscription_id": "abc123i0",
                "block_height": 779832
            },
            "holders": 50000,
            "tx_count": 1000000
        });

        let token = HiroOrdinalsClient::parse_brc20_token(&json);
        assert!(token.is_some());

        let token = token.unwrap();
        assert_eq!(token.tick, "ordi");
        assert!(token.is_fully_minted());
    }

    #[test]
    fn test_unisat_client_urls() {
        let client = UnisatClient::new();

        let url = client.brc20_summary_url("bc1q...");
        assert!(url.contains("/brc20/summary"));

        let url = client.brc20_transferable_url("bc1q...", "ordi");
        assert!(url.contains("/transferable-list"));
    }

    #[test]
    fn test_magic_eden_client_urls() {
        let client = MagicEdenClient::new();

        let url = client.collection_stats_url("bitcoin-puppets");
        assert!(url.contains("collectionSymbol=bitcoin-puppets"));

        let url = client.listings_url("nodemonkes");
        assert!(url.contains("listStatus=listed"));
    }

    #[test]
    fn test_endpoints() {
        assert!(OrdinalsEndpoints::HIRO_MAINNET.starts_with("https://"));
        assert!(OrdinalsEndpoints::MAGIC_EDEN.contains("magiceden"));
        assert!(OrdinalsEndpoints::UNISAT.contains("unisat"));
    }
}
