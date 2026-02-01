//! Ramp Network integration
//!
//! Widget URL: https://buy.ramp.network
//! API: https://api.ramp.network

use super::types::*;

/// Ramp Network widget URL
pub const RAMP_WIDGET_URL: &str = "https://buy.ramp.network";
pub const RAMP_STAGING_URL: &str = "https://ri-widget-staging.firebaseapp.com";
pub const RAMP_API_BASE: &str = "https://api.ramp.network/api";

/// Ramp Network on-ramp client
#[derive(Debug, Clone)]
pub struct RampClient {
    /// Host API key
    pub host_api_key: String,
    /// Widget URL
    pub widget_url: String,
    /// Staging mode
    pub staging: bool,
}

impl RampClient {
    /// Create new Ramp client
    pub fn new(host_api_key: String) -> Self {
        Self {
            host_api_key,
            widget_url: RAMP_WIDGET_URL.to_string(),
            staging: false,
        }
    }
    
    /// Create staging client for testing
    pub fn staging(host_api_key: String) -> Self {
        Self {
            host_api_key,
            widget_url: RAMP_STAGING_URL.to_string(),
            staging: true,
        }
    }
    
    /// Build widget URL for buy flow
    pub fn build_widget_url(&self, request: &OnRampRequest) -> String {
        // Ramp uses asset notation like ETH_ETH, BTC_BTC, USDC_POLYGON
        let swap_asset = self.format_asset(&request.crypto_currency, request.network.as_deref());
        
        let mut url = format!(
            "{}?hostApiKey={}&swapAsset={}&fiatCurrency={}&fiatValue={}",
            self.widget_url,
            self.host_api_key,
            swap_asset,
            request.fiat_currency.to_uppercase(),
            request.fiat_amount
        );
        
        // Add wallet address
        url.push_str(&format!("&userAddress={}", request.wallet_address));
        
        // Add email if specified
        if let Some(ref email) = request.email {
            url.push_str(&format!("&userEmailAddress={}", email));
        }
        
        // Add host app name and logo
        url.push_str("&hostAppName=Hawala");
        
        // Variant (auto, hosted-auto, manual, etc.)
        url.push_str("&variant=auto");
        
        url
    }
    
    /// Format asset code for Ramp (e.g., ETH_ETHEREUM, USDC_POLYGON)
    fn format_asset(&self, crypto: &str, network: Option<&str>) -> String {
        let crypto = crypto.to_uppercase();
        
        match network {
            Some("polygon") | Some("matic") => format!("{}_POLYGON", crypto),
            Some("arbitrum") => format!("{}_ARBITRUM", crypto),
            Some("optimism") => format!("{}_OPTIMISM", crypto),
            Some("avalanche") | Some("avax") => format!("{}_AVALANCHE", crypto),
            Some("bsc") | Some("binance") => format!("{}_BSC", crypto),
            Some("solana") => format!("{}_SOLANA", crypto),
            _ => match crypto.as_str() {
                "BTC" => "BTC_BTC".to_string(),
                "ETH" => "ETH_ETHEREUM".to_string(),
                "SOL" => "SOL_SOLANA".to_string(),
                "MATIC" => "MATIC_POLYGON".to_string(),
                "AVAX" => "AVAX_AVALANCHE".to_string(),
                _ => format!("{}_ETHEREUM", crypto), // Default to Ethereum
            },
        }
    }
    
    /// Build quote URL
    /// GET /host-api/v3/onramp/quote
    pub fn quote_url(&self, request: &OnRampRequest) -> String {
        let swap_asset = self.format_asset(&request.crypto_currency, request.network.as_deref());
        
        format!(
            "{}/host-api/v3/onramp/quote?hostApiKey={}&swapAsset={}&fiatCurrency={}&fiatValue={}",
            RAMP_API_BASE,
            self.host_api_key,
            swap_asset,
            request.fiat_currency.to_uppercase(),
            request.fiat_amount
        )
    }
    
    /// Build assets URL
    /// GET /host-api/v3/assets
    pub fn assets_url(&self) -> String {
        format!("{}/host-api/v3/assets?hostApiKey={}", RAMP_API_BASE, self.host_api_key)
    }
    
    /// Parse quote response
    pub fn parse_quote(&self, json: &str, request: &OnRampRequest) -> Result<OnRampQuote, OnRampError> {
        let parsed: serde_json::Value = serde_json::from_str(json)
            .map_err(|e| OnRampError::QuoteFailed(e.to_string()))?;
        
        // Check for error
        if let Some(error) = parsed.get("error") {
            return Err(OnRampError::QuoteFailed(
                error.as_str().unwrap_or("Unknown error").to_string()
            ));
        }
        
        // Ramp returns amounts in smallest unit, need to convert
        let crypto_amount_raw = parsed.get("cryptoAmount")
            .and_then(|v| v.as_str())
            .and_then(|s| s.parse::<f64>().ok())
            .unwrap_or(0.0);
        
        // Get asset decimals (default to 18 for ERC-20)
        let asset_info = parsed.get("asset");
        let decimals = asset_info
            .and_then(|a| a.get("decimals"))
            .and_then(|v| v.as_u64())
            .unwrap_or(18) as i32;
        
        let crypto_amount = crypto_amount_raw / 10_f64.powi(decimals);
        
        let base_fee = parsed.get("baseRampFee")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0);
        
        let network_fee = parsed.get("appliedFee")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0);
        
        let total_fees = base_fee + network_fee;
        
        Ok(OnRampQuote {
            provider: OnRampProvider::Ramp,
            fiat_amount: request.fiat_amount,
            fiat_currency: request.fiat_currency.clone(),
            crypto_amount,
            crypto_currency: request.crypto_currency.clone(),
            network_fee,
            provider_fee: base_fee,
            total_fees,
            exchange_rate: if crypto_amount > 0.0 { request.fiat_amount / crypto_amount } else { 0.0 },
            payment_methods: vec![
                PaymentMethod::CreditCard,
                PaymentMethod::DebitCard,
                PaymentMethod::ApplePay,
                PaymentMethod::BankTransfer,
                PaymentMethod::Sepa,
                PaymentMethod::iDEAL,
            ],
            expires_at: None,
            quote_id: None,
        })
    }
    
    /// Get supported cryptocurrencies
    pub fn supported_cryptos() -> Vec<SupportedCrypto> {
        vec![
            SupportedCrypto {
                symbol: "BTC".into(),
                name: "Bitcoin".into(),
                networks: vec!["bitcoin".into()],
                min_amount: Some(0.0001),
                max_amount: None,
            },
            SupportedCrypto {
                symbol: "ETH".into(),
                name: "Ethereum".into(),
                networks: vec!["ethereum".into(), "arbitrum".into(), "optimism".into(), "polygon".into()],
                min_amount: Some(0.001),
                max_amount: None,
            },
            SupportedCrypto {
                symbol: "USDC".into(),
                name: "USD Coin".into(),
                networks: vec!["ethereum".into(), "polygon".into(), "solana".into(), "arbitrum".into()],
                min_amount: Some(1.0),
                max_amount: None,
            },
            SupportedCrypto {
                symbol: "USDT".into(),
                name: "Tether".into(),
                networks: vec!["ethereum".into(), "polygon".into(), "bsc".into()],
                min_amount: Some(1.0),
                max_amount: None,
            },
            SupportedCrypto {
                symbol: "SOL".into(),
                name: "Solana".into(),
                networks: vec!["solana".into()],
                min_amount: Some(0.01),
                max_amount: None,
            },
            SupportedCrypto {
                symbol: "MATIC".into(),
                name: "Polygon".into(),
                networks: vec!["polygon".into()],
                min_amount: Some(1.0),
                max_amount: None,
            },
            SupportedCrypto {
                symbol: "AVAX".into(),
                name: "Avalanche".into(),
                networks: vec!["avalanche".into()],
                min_amount: Some(0.1),
                max_amount: None,
            },
        ]
    }
    
    /// Get fee estimate
    pub fn estimated_fee_percent() -> f64 {
        2.5 // Ramp typically charges ~2.5%
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_widget_url() {
        let client = RampClient::new("host_key_123".into());
        let request = OnRampRequest::new(100.0, "USD", "ETH", "0xtest...");
        
        let url = client.build_widget_url(&request);
        
        assert!(url.contains("buy.ramp.network"));
        assert!(url.contains("hostApiKey=host_key_123"));
        assert!(url.contains("swapAsset=ETH_ETHEREUM"));
        assert!(url.contains("fiatCurrency=USD"));
        assert!(url.contains("fiatValue=100"));
        assert!(url.contains("userAddress=0xtest"));
    }
    
    #[test]
    fn test_asset_formatting() {
        let client = RampClient::new("key".into());
        
        // Test various networks
        let request_poly = OnRampRequest::new(100.0, "USD", "USDC", "0x...")
            .with_network("polygon");
        let url_poly = client.build_widget_url(&request_poly);
        assert!(url_poly.contains("swapAsset=USDC_POLYGON"));
        
        let request_arb = OnRampRequest::new(100.0, "USD", "ETH", "0x...")
            .with_network("arbitrum");
        let url_arb = client.build_widget_url(&request_arb);
        assert!(url_arb.contains("swapAsset=ETH_ARBITRUM"));
        
        // Default Bitcoin
        let request_btc = OnRampRequest::new(100.0, "USD", "BTC", "bc1q...");
        let url_btc = client.build_widget_url(&request_btc);
        assert!(url_btc.contains("swapAsset=BTC_BTC"));
    }
    
    #[test]
    fn test_staging_mode() {
        let client = RampClient::staging("key".into());
        
        assert!(client.staging);
        assert!(client.widget_url.contains("staging"));
    }
    
    #[test]
    fn test_quote_url() {
        let client = RampClient::new("key_123".into());
        let request = OnRampRequest::new(50.0, "EUR", "SOL", "...")
            .with_network("solana");
        
        let url = client.quote_url(&request);
        
        assert!(url.contains("/host-api/v3/onramp/quote"));
        assert!(url.contains("swapAsset=SOL_SOLANA"));
        assert!(url.contains("fiatCurrency=EUR"));
        assert!(url.contains("fiatValue=50"));
    }
    
    #[test]
    fn test_parse_quote() {
        let client = RampClient::new("key".into());
        let request = OnRampRequest::new(100.0, "USD", "ETH", "0x...");
        
        // Amount in wei (18 decimals)
        let json = r#"{
            "cryptoAmount": "45000000000000000",
            "asset": {"decimals": 18},
            "baseRampFee": 2.50,
            "appliedFee": 0.10
        }"#;
        
        let quote = client.parse_quote(json, &request).unwrap();
        
        assert_eq!(quote.provider, OnRampProvider::Ramp);
        assert!((quote.crypto_amount - 0.045).abs() < 0.001);
        assert_eq!(quote.provider_fee, 2.50);
        assert!((quote.total_fees - 2.60).abs() < 0.001);
    }
    
    #[test]
    fn test_supported_cryptos() {
        let cryptos = RampClient::supported_cryptos();
        
        assert!(!cryptos.is_empty());
        assert!(cryptos.iter().any(|c| c.symbol == "BTC"));
        assert!(cryptos.iter().any(|c| c.symbol == "SOL"));
        assert!(cryptos.iter().any(|c| c.symbol == "AVAX"));
    }
    
    #[test]
    fn test_fee_comparison() {
        // Compare estimated fees (Ramp should be cheapest)
        assert!(RampClient::estimated_fee_percent() < 4.5); // MoonPay ~4.5%
        assert!(RampClient::estimated_fee_percent() < 5.0); // Transak ~5.0%
    }
}
