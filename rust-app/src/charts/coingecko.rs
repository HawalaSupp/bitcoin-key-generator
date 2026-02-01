//! CoinGecko API client for price data
//!
//! API Endpoints used:
//! - /coins/{id}/market_chart - Historical price/volume/market_cap
//! - /coins/{id}/ohlc - Candlestick data
//! - /coins/{id} - Token info and current price
//! - /simple/price - Simple price lookup

use super::types::*;

/// CoinGecko API base URL
pub const COINGECKO_API_BASE: &str = "https://api.coingecko.com/api/v3";
pub const COINGECKO_PRO_API_BASE: &str = "https://pro-api.coingecko.com/api/v3";

/// CoinGecko API client
#[derive(Debug, Clone)]
pub struct CoinGeckoClient {
    /// API base URL
    pub base_url: String,
    /// Optional API key for pro tier
    pub api_key: Option<String>,
}

impl Default for CoinGeckoClient {
    fn default() -> Self {
        Self::new()
    }
}

impl CoinGeckoClient {
    /// Create client with free tier
    pub fn new() -> Self {
        Self {
            base_url: COINGECKO_API_BASE.to_string(),
            api_key: None,
        }
    }
    
    /// Create client with pro API key
    pub fn with_api_key(api_key: String) -> Self {
        Self {
            base_url: COINGECKO_PRO_API_BASE.to_string(),
            api_key: Some(api_key),
        }
    }
    
    /// Build market chart URL for historical data
    /// GET /coins/{id}/market_chart?vs_currency={currency}&days={days}&interval={interval}
    pub fn market_chart_url(&self, token_id: &str, currency: &str, range: TimeRange) -> String {
        let mut url = format!(
            "{}/coins/{}/market_chart?vs_currency={}&days={}",
            self.base_url,
            token_id,
            currency,
            range.days()
        );
        
        if let Some(interval) = range.interval() {
            url.push_str(&format!("&interval={}", interval));
        }
        
        if let Some(ref key) = self.api_key {
            url.push_str(&format!("&x_cg_pro_api_key={}", key));
        }
        
        url
    }
    
    /// Build OHLC URL for candlestick data
    /// GET /coins/{id}/ohlc?vs_currency={currency}&days={days}
    pub fn ohlc_url(&self, token_id: &str, currency: &str, range: TimeRange) -> String {
        let mut url = format!(
            "{}/coins/{}/ohlc?vs_currency={}&days={}",
            self.base_url,
            token_id,
            currency,
            range.days()
        );
        
        if let Some(ref key) = self.api_key {
            url.push_str(&format!("&x_cg_pro_api_key={}", key));
        }
        
        url
    }
    
    /// Build token info URL
    /// GET /coins/{id}
    pub fn token_info_url(&self, token_id: &str) -> String {
        let mut url = format!(
            "{}/coins/{}?localization=false&tickers=false&community_data=false&developer_data=false",
            self.base_url,
            token_id
        );
        
        if let Some(ref key) = self.api_key {
            url.push_str(&format!("&x_cg_pro_api_key={}", key));
        }
        
        url
    }
    
    /// Build simple price URL for multiple tokens
    /// GET /simple/price?ids={ids}&vs_currencies={currencies}
    pub fn simple_price_url(&self, token_ids: &[&str], currencies: &[&str]) -> String {
        let mut url = format!(
            "{}/simple/price?ids={}&vs_currencies={}&include_24hr_change=true&include_24hr_vol=true&include_market_cap=true",
            self.base_url,
            token_ids.join(","),
            currencies.join(",")
        );
        
        if let Some(ref key) = self.api_key {
            url.push_str(&format!("&x_cg_pro_api_key={}", key));
        }
        
        url
    }
    
    /// Build coins list URL for token ID lookup
    /// GET /coins/list
    pub fn coins_list_url(&self) -> String {
        let mut url = format!("{}/coins/list", self.base_url);
        
        if let Some(ref key) = self.api_key {
            url.push_str(&format!("?x_cg_pro_api_key={}", key));
        }
        
        url
    }
    
    /// Build search URL for token lookup
    /// GET /search?query={query}
    pub fn search_url(&self, query: &str) -> String {
        let mut url = format!("{}/search?query={}", self.base_url, query);
        
        if let Some(ref key) = self.api_key {
            url.push_str(&format!("&x_cg_pro_api_key={}", key));
        }
        
        url
    }
    
    /// Parse market chart JSON response into ChartData
    pub fn parse_market_chart(
        &self,
        json: &str,
        token_id: &str,
        currency: &str,
        range: TimeRange,
    ) -> Result<ChartData, ChartError> {
        let parsed: serde_json::Value = serde_json::from_str(json)
            .map_err(|e| ChartError::ParseError(e.to_string()))?;
        
        let mut data = ChartData::new(token_id.to_string(), currency.to_string(), range);
        
        // Parse prices [[timestamp, price], ...]
        if let Some(prices) = parsed.get("prices").and_then(|v| v.as_array()) {
            for point in prices {
                if let Some(arr) = point.as_array() {
                    if arr.len() >= 2 {
                        let timestamp = arr[0].as_f64().unwrap_or(0.0) as u64;
                        let price = arr[1].as_f64().unwrap_or(0.0);
                        data.prices.push(PricePoint::new(timestamp, price));
                    }
                }
            }
        }
        
        // Parse volumes
        if let Some(volumes) = parsed.get("total_volumes").and_then(|v| v.as_array()) {
            for point in volumes {
                if let Some(arr) = point.as_array() {
                    if arr.len() >= 2 {
                        let timestamp = arr[0].as_f64().unwrap_or(0.0) as u64;
                        let volume = arr[1].as_f64().unwrap_or(0.0);
                        data.volumes.push(VolumePoint::new(timestamp, volume));
                    }
                }
            }
        }
        
        // Parse market caps
        if let Some(caps) = parsed.get("market_caps").and_then(|v| v.as_array()) {
            for point in caps {
                if let Some(arr) = point.as_array() {
                    if arr.len() >= 2 {
                        let timestamp = arr[0].as_f64().unwrap_or(0.0) as u64;
                        let cap = arr[1].as_f64().unwrap_or(0.0);
                        data.market_caps.push(MarketCapPoint::new(timestamp, cap));
                    }
                }
            }
        }
        
        if data.prices.is_empty() {
            return Err(ChartError::NoData);
        }
        
        Ok(data)
    }
    
    /// Parse OHLC JSON response into OHLCData
    pub fn parse_ohlc(
        &self,
        json: &str,
        token_id: &str,
        currency: &str,
        range: TimeRange,
    ) -> Result<OHLCData, ChartError> {
        let parsed: serde_json::Value = serde_json::from_str(json)
            .map_err(|e| ChartError::ParseError(e.to_string()))?;
        
        let mut data = OHLCData::new(token_id.to_string(), currency.to_string(), range);
        
        // Parse [[timestamp, open, high, low, close], ...]
        if let Some(candles) = parsed.as_array() {
            for candle in candles {
                if let Some(arr) = candle.as_array() {
                    if arr.len() >= 5 {
                        let timestamp = arr[0].as_f64().unwrap_or(0.0) as u64;
                        let open = arr[1].as_f64().unwrap_or(0.0);
                        let high = arr[2].as_f64().unwrap_or(0.0);
                        let low = arr[3].as_f64().unwrap_or(0.0);
                        let close = arr[4].as_f64().unwrap_or(0.0);
                        data.candles.push(Candlestick::new(timestamp, open, high, low, close));
                    }
                }
            }
        }
        
        if data.candles.is_empty() {
            return Err(ChartError::NoData);
        }
        
        Ok(data)
    }
    
    /// Parse token info JSON response
    pub fn parse_token_info(&self, json: &str) -> Result<TokenInfo, ChartError> {
        let parsed: serde_json::Value = serde_json::from_str(json)
            .map_err(|e| ChartError::ParseError(e.to_string()))?;
        
        let market_data = parsed.get("market_data");
        
        Ok(TokenInfo {
            id: parsed.get("id").and_then(|v| v.as_str()).unwrap_or("").to_string(),
            symbol: parsed.get("symbol").and_then(|v| v.as_str()).unwrap_or("").to_string(),
            name: parsed.get("name").and_then(|v| v.as_str()).unwrap_or("").to_string(),
            current_price: market_data
                .and_then(|m| m.get("current_price"))
                .and_then(|p| p.get("usd"))
                .and_then(|v| v.as_f64())
                .unwrap_or(0.0),
            price_change_24h: market_data
                .and_then(|m| m.get("price_change_24h"))
                .and_then(|v| v.as_f64())
                .unwrap_or(0.0),
            price_change_percentage_24h: market_data
                .and_then(|m| m.get("price_change_percentage_24h"))
                .and_then(|v| v.as_f64())
                .unwrap_or(0.0),
            market_cap: market_data
                .and_then(|m| m.get("market_cap"))
                .and_then(|p| p.get("usd"))
                .and_then(|v| v.as_f64())
                .unwrap_or(0.0),
            market_cap_rank: parsed.get("market_cap_rank").and_then(|v| v.as_u64()).map(|v| v as u32),
            total_volume: market_data
                .and_then(|m| m.get("total_volume"))
                .and_then(|p| p.get("usd"))
                .and_then(|v| v.as_f64())
                .unwrap_or(0.0),
            high_24h: market_data
                .and_then(|m| m.get("high_24h"))
                .and_then(|p| p.get("usd"))
                .and_then(|v| v.as_f64())
                .unwrap_or(0.0),
            low_24h: market_data
                .and_then(|m| m.get("low_24h"))
                .and_then(|p| p.get("usd"))
                .and_then(|v| v.as_f64())
                .unwrap_or(0.0),
            ath: market_data
                .and_then(|m| m.get("ath"))
                .and_then(|p| p.get("usd"))
                .and_then(|v| v.as_f64())
                .unwrap_or(0.0),
            ath_change_percentage: market_data
                .and_then(|m| m.get("ath_change_percentage"))
                .and_then(|p| p.get("usd"))
                .and_then(|v| v.as_f64())
                .unwrap_or(0.0),
            atl: market_data
                .and_then(|m| m.get("atl"))
                .and_then(|p| p.get("usd"))
                .and_then(|v| v.as_f64())
                .unwrap_or(0.0),
            atl_change_percentage: market_data
                .and_then(|m| m.get("atl_change_percentage"))
                .and_then(|p| p.get("usd"))
                .and_then(|v| v.as_f64())
                .unwrap_or(0.0),
            circulating_supply: market_data
                .and_then(|m| m.get("circulating_supply"))
                .and_then(|v| v.as_f64())
                .unwrap_or(0.0),
            total_supply: market_data
                .and_then(|m| m.get("total_supply"))
                .and_then(|v| v.as_f64()),
            max_supply: market_data
                .and_then(|m| m.get("max_supply"))
                .and_then(|v| v.as_f64()),
            image_url: parsed.get("image")
                .and_then(|i| i.get("large"))
                .and_then(|v| v.as_str())
                .map(|s| s.to_string()),
        })
    }
}

/// Known CoinGecko token IDs for common assets
pub struct KnownTokenIds;

impl KnownTokenIds {
    pub const BITCOIN: &'static str = "bitcoin";
    pub const ETHEREUM: &'static str = "ethereum";
    pub const TETHER: &'static str = "tether";
    pub const BNB: &'static str = "binancecoin";
    pub const SOLANA: &'static str = "solana";
    pub const XRP: &'static str = "ripple";
    pub const USDC: &'static str = "usd-coin";
    pub const CARDANO: &'static str = "cardano";
    pub const AVALANCHE: &'static str = "avalanche-2";
    pub const DOGECOIN: &'static str = "dogecoin";
    pub const POLKADOT: &'static str = "polkadot";
    pub const POLYGON: &'static str = "matic-network";
    pub const CHAINLINK: &'static str = "chainlink";
    pub const UNISWAP: &'static str = "uniswap";
    pub const LITECOIN: &'static str = "litecoin";
    pub const COSMOS: &'static str = "cosmos";
    pub const NEAR: &'static str = "near";
    pub const APTOS: &'static str = "aptos";
    pub const SUI: &'static str = "sui";
    pub const ARBITRUM: &'static str = "arbitrum";
    pub const OPTIMISM: &'static str = "optimism";
    pub const THORCHAIN: &'static str = "thorchain";
    
    /// Get token ID from symbol
    pub fn from_symbol(symbol: &str) -> Option<&'static str> {
        match symbol.to_uppercase().as_str() {
            "BTC" => Some(Self::BITCOIN),
            "ETH" => Some(Self::ETHEREUM),
            "USDT" => Some(Self::TETHER),
            "BNB" => Some(Self::BNB),
            "SOL" => Some(Self::SOLANA),
            "XRP" => Some(Self::XRP),
            "USDC" => Some(Self::USDC),
            "ADA" => Some(Self::CARDANO),
            "AVAX" => Some(Self::AVALANCHE),
            "DOGE" => Some(Self::DOGECOIN),
            "DOT" => Some(Self::POLKADOT),
            "MATIC" | "POL" => Some(Self::POLYGON),
            "LINK" => Some(Self::CHAINLINK),
            "UNI" => Some(Self::UNISWAP),
            "LTC" => Some(Self::LITECOIN),
            "ATOM" => Some(Self::COSMOS),
            "NEAR" => Some(Self::NEAR),
            "APT" => Some(Self::APTOS),
            "SUI" => Some(Self::SUI),
            "ARB" => Some(Self::ARBITRUM),
            "OP" => Some(Self::OPTIMISM),
            "RUNE" => Some(Self::THORCHAIN),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_market_chart_url() {
        let client = CoinGeckoClient::new();
        let url = client.market_chart_url("bitcoin", "usd", TimeRange::Day7);
        assert!(url.contains("/coins/bitcoin/market_chart"));
        assert!(url.contains("vs_currency=usd"));
        assert!(url.contains("days=7"));
    }
    
    #[test]
    fn test_ohlc_url() {
        let client = CoinGeckoClient::new();
        let url = client.ohlc_url("ethereum", "eur", TimeRange::Day30);
        assert!(url.contains("/coins/ethereum/ohlc"));
        assert!(url.contains("vs_currency=eur"));
        assert!(url.contains("days=30"));
    }
    
    #[test]
    fn test_parse_market_chart() {
        let client = CoinGeckoClient::new();
        let json = r#"{
            "prices": [[1704067200000, 42000.5], [1704153600000, 43500.75]],
            "total_volumes": [[1704067200000, 25000000000], [1704153600000, 28000000000]],
            "market_caps": [[1704067200000, 820000000000], [1704153600000, 850000000000]]
        }"#;
        
        let data = client.parse_market_chart(json, "bitcoin", "usd", TimeRange::Day7).unwrap();
        
        assert_eq!(data.token_id, "bitcoin");
        assert_eq!(data.currency, "usd");
        assert_eq!(data.prices.len(), 2);
        assert_eq!(data.prices[0].price, 42000.5);
        assert_eq!(data.volumes.len(), 2);
        assert_eq!(data.market_caps.len(), 2);
    }
    
    #[test]
    fn test_parse_ohlc() {
        let client = CoinGeckoClient::new();
        let json = r#"[
            [1704067200000, 42000, 42500, 41800, 42300],
            [1704153600000, 42300, 43800, 42200, 43500]
        ]"#;
        
        let data = client.parse_ohlc(json, "bitcoin", "usd", TimeRange::Day7).unwrap();
        
        assert_eq!(data.candles.len(), 2);
        assert_eq!(data.candles[0].open, 42000.0);
        assert_eq!(data.candles[0].high, 42500.0);
        assert_eq!(data.candles[0].close, 42300.0);
        assert!(data.candles[0].is_bullish());
    }
    
    #[test]
    fn test_known_token_ids() {
        assert_eq!(KnownTokenIds::from_symbol("BTC"), Some("bitcoin"));
        assert_eq!(KnownTokenIds::from_symbol("eth"), Some("ethereum"));
        assert_eq!(KnownTokenIds::from_symbol("SOL"), Some("solana"));
        assert_eq!(KnownTokenIds::from_symbol("UNKNOWN"), None);
    }
    
    #[test]
    fn test_client_with_api_key() {
        let client = CoinGeckoClient::with_api_key("test-key".into());
        let url = client.market_chart_url("bitcoin", "usd", TimeRange::Day7);
        assert!(url.contains("pro-api.coingecko.com"));
        assert!(url.contains("x_cg_pro_api_key=test-key"));
    }
}
