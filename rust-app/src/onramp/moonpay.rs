//! MoonPay integration
//!
//! Widget URL: https://buy.moonpay.com
//! API: https://api.moonpay.com

use super::types::*;

/// MoonPay API base URL
pub const MOONPAY_API_BASE: &str = "https://api.moonpay.com";
pub const MOONPAY_WIDGET_URL: &str = "https://buy.moonpay.com";

/// MoonPay on-ramp client
#[derive(Debug, Clone)]
pub struct MoonPayClient {
    /// API key
    pub api_key: String,
    /// Widget base URL
    pub widget_url: String,
    /// Use sandbox mode
    pub sandbox: bool,
}

impl MoonPayClient {
    /// Create new MoonPay client
    pub fn new(api_key: String) -> Self {
        Self {
            api_key,
            widget_url: MOONPAY_WIDGET_URL.to_string(),
            sandbox: false,
        }
    }
    
    /// Create sandbox client for testing
    pub fn sandbox(api_key: String) -> Self {
        Self {
            api_key,
            widget_url: "https://buy-sandbox.moonpay.com".to_string(),
            sandbox: true,
        }
    }
    
    /// Build widget URL for buy flow
    pub fn build_widget_url(&self, request: &OnRampRequest) -> String {
        let mut url = format!(
            "{}?apiKey={}&currencyCode={}&baseCurrencyCode={}&baseCurrencyAmount={}",
            self.widget_url,
            self.api_key,
            request.crypto_currency.to_lowercase(),
            request.fiat_currency.to_lowercase(),
            request.fiat_amount
        );
        
        // Add wallet address
        url.push_str(&format!("&walletAddress={}", request.wallet_address));
        
        // Add optional parameters
        if let Some(ref email) = request.email {
            url.push_str(&format!("&email={}", email));
        }
        
        // Add theme and color
        url.push_str("&theme=dark&colorCode=%23FF6B00");
        
        url
    }
    
    /// Build quote URL
    /// GET /v3/currencies/{crypto}/buy_quote
    pub fn quote_url(&self, request: &OnRampRequest) -> String {
        format!(
            "{}/v3/currencies/{}/buy_quote?apiKey={}&baseCurrencyCode={}&baseCurrencyAmount={}&areFeesIncluded=true",
            MOONPAY_API_BASE,
            request.crypto_currency.to_lowercase(),
            self.api_key,
            request.fiat_currency.to_lowercase(),
            request.fiat_amount
        )
    }
    
    /// Build supported currencies URL
    /// GET /v3/currencies
    pub fn currencies_url(&self) -> String {
        format!("{}/v3/currencies?apiKey={}", MOONPAY_API_BASE, self.api_key)
    }
    
    /// Build IP address country check URL
    /// GET /v4/ip_address
    pub fn ip_check_url(&self) -> String {
        format!("{}/v4/ip_address?apiKey={}", MOONPAY_API_BASE, self.api_key)
    }
    
    /// Parse quote response
    pub fn parse_quote(&self, json: &str, request: &OnRampRequest) -> Result<OnRampQuote, OnRampError> {
        let parsed: serde_json::Value = serde_json::from_str(json)
            .map_err(|e| OnRampError::QuoteFailed(e.to_string()))?;
        
        // Check for error
        if let Some(error) = parsed.get("message") {
            return Err(OnRampError::QuoteFailed(error.as_str().unwrap_or("Unknown error").to_string()));
        }
        
        let quote_amount = parsed.get("quoteCurrencyAmount")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0);
        
        let fee_amount = parsed.get("feeAmount")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0);
        
        let network_fee = parsed.get("networkFeeAmount")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0);
        
        let extra_fee = parsed.get("extraFeeAmount")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0);
        
        let total_fees = fee_amount + extra_fee;
        
        Ok(OnRampQuote {
            provider: OnRampProvider::MoonPay,
            fiat_amount: request.fiat_amount,
            fiat_currency: request.fiat_currency.clone(),
            crypto_amount: quote_amount,
            crypto_currency: request.crypto_currency.clone(),
            network_fee,
            provider_fee: fee_amount,
            total_fees,
            exchange_rate: if quote_amount > 0.0 { request.fiat_amount / quote_amount } else { 0.0 },
            payment_methods: vec![
                PaymentMethod::CreditCard,
                PaymentMethod::DebitCard,
                PaymentMethod::ApplePay,
                PaymentMethod::GooglePay,
                PaymentMethod::BankTransfer,
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
                networks: vec!["ethereum".into(), "arbitrum".into(), "optimism".into()],
                min_amount: Some(0.001),
                max_amount: None,
            },
            SupportedCrypto {
                symbol: "USDT".into(),
                name: "Tether".into(),
                networks: vec!["ethereum".into(), "polygon".into(), "tron".into()],
                min_amount: Some(1.0),
                max_amount: None,
            },
            SupportedCrypto {
                symbol: "USDC".into(),
                name: "USD Coin".into(),
                networks: vec!["ethereum".into(), "polygon".into(), "solana".into()],
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
        ]
    }
    
    /// Get fee estimate
    pub fn estimated_fee_percent() -> f64 {
        4.5 // MoonPay typically charges ~4.5%
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_widget_url() {
        let client = MoonPayClient::new("pk_test_123".into());
        let request = OnRampRequest::new(100.0, "USD", "BTC", "bc1qtest...");
        
        let url = client.build_widget_url(&request);
        
        assert!(url.contains("buy.moonpay.com"));
        assert!(url.contains("apiKey=pk_test_123"));
        assert!(url.contains("currencyCode=btc"));
        assert!(url.contains("baseCurrencyCode=usd"));
        assert!(url.contains("baseCurrencyAmount=100"));
        assert!(url.contains("walletAddress=bc1qtest"));
    }
    
    #[test]
    fn test_sandbox_mode() {
        let client = MoonPayClient::sandbox("pk_test_123".into());
        
        assert!(client.sandbox);
        assert!(client.widget_url.contains("sandbox"));
    }
    
    #[test]
    fn test_quote_url() {
        let client = MoonPayClient::new("pk_test_123".into());
        let request = OnRampRequest::new(100.0, "EUR", "ETH", "0x...");
        
        let url = client.quote_url(&request);
        
        assert!(url.contains("/v3/currencies/eth/buy_quote"));
        assert!(url.contains("baseCurrencyCode=eur"));
        assert!(url.contains("baseCurrencyAmount=100"));
    }
    
    #[test]
    fn test_parse_quote() {
        let client = MoonPayClient::new("pk_test_123".into());
        let request = OnRampRequest::new(100.0, "USD", "ETH", "0x...");
        
        let json = r#"{
            "quoteCurrencyAmount": 0.045,
            "feeAmount": 3.99,
            "networkFeeAmount": 0.001,
            "extraFeeAmount": 0.50
        }"#;
        
        let quote = client.parse_quote(json, &request).unwrap();
        
        assert_eq!(quote.provider, OnRampProvider::MoonPay);
        assert_eq!(quote.crypto_amount, 0.045);
        assert_eq!(quote.provider_fee, 3.99);
        assert!((quote.total_fees - 4.49).abs() < 0.001);
    }
    
    #[test]
    fn test_supported_cryptos() {
        let cryptos = MoonPayClient::supported_cryptos();
        
        assert!(!cryptos.is_empty());
        assert!(cryptos.iter().any(|c| c.symbol == "BTC"));
        assert!(cryptos.iter().any(|c| c.symbol == "ETH"));
    }
}
