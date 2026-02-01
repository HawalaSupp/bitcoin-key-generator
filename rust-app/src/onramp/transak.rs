//! Transak integration
//!
//! Widget URL: https://global.transak.com
//! API: https://api.transak.com

use super::types::*;

/// Transak widget base URL
pub const TRANSAK_WIDGET_URL: &str = "https://global.transak.com";
pub const TRANSAK_STAGING_URL: &str = "https://global-stg.transak.com";
pub const TRANSAK_API_BASE: &str = "https://api.transak.com";

/// Transak on-ramp client
#[derive(Debug, Clone)]
pub struct TransakClient {
    /// API key
    pub api_key: String,
    /// Widget URL
    pub widget_url: String,
    /// Staging mode
    pub staging: bool,
}

impl TransakClient {
    /// Create new Transak client
    pub fn new(api_key: String) -> Self {
        Self {
            api_key,
            widget_url: TRANSAK_WIDGET_URL.to_string(),
            staging: false,
        }
    }
    
    /// Create staging client for testing
    pub fn staging(api_key: String) -> Self {
        Self {
            api_key,
            widget_url: TRANSAK_STAGING_URL.to_string(),
            staging: true,
        }
    }
    
    /// Build widget URL for buy flow
    pub fn build_widget_url(&self, request: &OnRampRequest) -> String {
        let mut url = format!(
            "{}?apiKey={}&cryptoCurrencyCode={}&fiatCurrency={}&fiatAmount={}",
            self.widget_url,
            self.api_key,
            request.crypto_currency.to_uppercase(),
            request.fiat_currency.to_uppercase(),
            request.fiat_amount
        );
        
        // Add wallet address
        url.push_str(&format!("&walletAddress={}", request.wallet_address));
        
        // Add network if specified
        if let Some(ref network) = request.network {
            url.push_str(&format!("&network={}", network));
        }
        
        // Add email if specified
        if let Some(ref email) = request.email {
            url.push_str(&format!("&email={}", email));
        }
        
        // Add theme
        url.push_str("&themeColor=FF6B00&hideMenu=true");
        
        // Disable address edit for security
        url.push_str("&disableWalletAddressForm=true");
        
        url
    }
    
    /// Build quote URL
    /// GET /api/v1/pricing/public/quotes
    pub fn quote_url(&self, request: &OnRampRequest) -> String {
        format!(
            "{}/api/v1/pricing/public/quotes?partnerApiKey={}&cryptoCurrency={}&fiatCurrency={}&fiatAmount={}&isBuyOrSell=BUY&paymentMethod=credit_debit_card",
            TRANSAK_API_BASE,
            self.api_key,
            request.crypto_currency.to_uppercase(),
            request.fiat_currency.to_uppercase(),
            request.fiat_amount
        )
    }
    
    /// Build supported cryptocurrencies URL
    /// GET /api/v1/currencies/crypto-currencies
    pub fn cryptocurrencies_url(&self) -> String {
        format!("{}/api/v1/currencies/crypto-currencies", TRANSAK_API_BASE)
    }
    
    /// Build supported fiat currencies URL
    /// GET /api/v1/currencies/fiat-currencies
    pub fn fiat_currencies_url(&self) -> String {
        format!("{}/api/v1/currencies/fiat-currencies", TRANSAK_API_BASE)
    }
    
    /// Parse quote response
    pub fn parse_quote(&self, json: &str, request: &OnRampRequest) -> Result<OnRampQuote, OnRampError> {
        let parsed: serde_json::Value = serde_json::from_str(json)
            .map_err(|e| OnRampError::QuoteFailed(e.to_string()))?;
        
        // Check for error
        if let Some(error) = parsed.get("error") {
            return Err(OnRampError::QuoteFailed(
                error.get("message").and_then(|m| m.as_str()).unwrap_or("Unknown error").to_string()
            ));
        }
        
        let response = parsed.get("response").unwrap_or(&parsed);
        
        let crypto_amount = response.get("cryptoAmount")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0);
        
        let fee_amount = response.get("totalFee")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0);
        
        let network_fee = response.get("networkFee")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0);
        
        Ok(OnRampQuote {
            provider: OnRampProvider::Transak,
            fiat_amount: request.fiat_amount,
            fiat_currency: request.fiat_currency.clone(),
            crypto_amount,
            crypto_currency: request.crypto_currency.clone(),
            network_fee,
            provider_fee: fee_amount - network_fee,
            total_fees: fee_amount,
            exchange_rate: if crypto_amount > 0.0 { request.fiat_amount / crypto_amount } else { 0.0 },
            payment_methods: vec![
                PaymentMethod::CreditCard,
                PaymentMethod::DebitCard,
                PaymentMethod::ApplePay,
                PaymentMethod::GooglePay,
                PaymentMethod::BankTransfer,
                PaymentMethod::Sepa,
            ],
            expires_at: None,
            quote_id: response.get("quoteId").and_then(|v| v.as_str()).map(|s| s.to_string()),
        })
    }
    
    /// Get supported cryptocurrencies
    pub fn supported_cryptos() -> Vec<SupportedCrypto> {
        vec![
            SupportedCrypto {
                symbol: "BTC".into(),
                name: "Bitcoin".into(),
                networks: vec!["mainnet".into()],
                min_amount: Some(0.0001),
                max_amount: None,
            },
            SupportedCrypto {
                symbol: "ETH".into(),
                name: "Ethereum".into(),
                networks: vec!["ethereum".into(), "arbitrum".into(), "optimism".into(), "base".into()],
                min_amount: Some(0.001),
                max_amount: None,
            },
            SupportedCrypto {
                symbol: "USDT".into(),
                name: "Tether".into(),
                networks: vec!["ethereum".into(), "polygon".into(), "bsc".into(), "tron".into()],
                min_amount: Some(1.0),
                max_amount: None,
            },
            SupportedCrypto {
                symbol: "USDC".into(),
                name: "USD Coin".into(),
                networks: vec!["ethereum".into(), "polygon".into(), "solana".into(), "base".into()],
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
                symbol: "AVAX".into(),
                name: "Avalanche".into(),
                networks: vec!["avalanche".into()],
                min_amount: Some(0.1),
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
                symbol: "BNB".into(),
                name: "BNB".into(),
                networks: vec!["bsc".into()],
                min_amount: Some(0.01),
                max_amount: None,
            },
        ]
    }
    
    /// Get fee estimate
    pub fn estimated_fee_percent() -> f64 {
        5.0 // Transak typically charges ~5%
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_widget_url() {
        let client = TransakClient::new("api_key_123".into());
        let request = OnRampRequest::new(100.0, "USD", "ETH", "0xtest...")
            .with_network("ethereum");
        
        let url = client.build_widget_url(&request);
        
        assert!(url.contains("global.transak.com"));
        assert!(url.contains("apiKey=api_key_123"));
        assert!(url.contains("cryptoCurrencyCode=ETH"));
        assert!(url.contains("fiatCurrency=USD"));
        assert!(url.contains("fiatAmount=100"));
        assert!(url.contains("walletAddress=0xtest"));
        assert!(url.contains("network=ethereum"));
        assert!(url.contains("disableWalletAddressForm=true"));
    }
    
    #[test]
    fn test_staging_mode() {
        let client = TransakClient::staging("api_key_123".into());
        
        assert!(client.staging);
        assert!(client.widget_url.contains("stg"));
    }
    
    #[test]
    fn test_quote_url() {
        let client = TransakClient::new("api_key_123".into());
        let request = OnRampRequest::new(200.0, "EUR", "BTC", "bc1q...");
        
        let url = client.quote_url(&request);
        
        assert!(url.contains("/api/v1/pricing/public/quotes"));
        assert!(url.contains("cryptoCurrency=BTC"));
        assert!(url.contains("fiatCurrency=EUR"));
        assert!(url.contains("fiatAmount=200"));
    }
    
    #[test]
    fn test_parse_quote() {
        let client = TransakClient::new("api_key_123".into());
        let request = OnRampRequest::new(100.0, "USD", "SOL", "...address");
        
        let json = r#"{
            "response": {
                "cryptoAmount": 1.5,
                "totalFee": 5.50,
                "networkFee": 0.01,
                "quoteId": "quote-123"
            }
        }"#;
        
        let quote = client.parse_quote(json, &request).unwrap();
        
        assert_eq!(quote.provider, OnRampProvider::Transak);
        assert_eq!(quote.crypto_amount, 1.5);
        assert_eq!(quote.total_fees, 5.50);
        assert_eq!(quote.quote_id, Some("quote-123".into()));
    }
    
    #[test]
    fn test_supported_cryptos() {
        let cryptos = TransakClient::supported_cryptos();
        
        assert!(!cryptos.is_empty());
        assert!(cryptos.iter().any(|c| c.symbol == "BTC"));
        assert!(cryptos.iter().any(|c| c.symbol == "SOL"));
        assert!(cryptos.iter().any(|c| c.symbol == "AVAX"));
    }
}
