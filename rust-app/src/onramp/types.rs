//! On-ramp types and data structures

use std::fmt;

/// Supported on-ramp providers
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum OnRampProvider {
    MoonPay,
    Transak,
    Ramp,
}

impl OnRampProvider {
    pub fn name(&self) -> &str {
        match self {
            OnRampProvider::MoonPay => "MoonPay",
            OnRampProvider::Transak => "Transak",
            OnRampProvider::Ramp => "Ramp Network",
        }
    }
    
    pub fn website(&self) -> &str {
        match self {
            OnRampProvider::MoonPay => "https://www.moonpay.com",
            OnRampProvider::Transak => "https://transak.com",
            OnRampProvider::Ramp => "https://ramp.network",
        }
    }
    
    pub fn all() -> Vec<OnRampProvider> {
        vec![OnRampProvider::MoonPay, OnRampProvider::Transak, OnRampProvider::Ramp]
    }
}

impl fmt::Display for OnRampProvider {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.name())
    }
}

/// Payment method types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[allow(non_camel_case_types)]
pub enum PaymentMethod {
    CreditCard,
    DebitCard,
    ApplePay,
    GooglePay,
    BankTransfer,
    Sepa,
    ACH,
    Wire,
    PIX,
    iDEAL,
}

impl PaymentMethod {
    pub fn name(&self) -> &str {
        match self {
            PaymentMethod::CreditCard => "Credit Card",
            PaymentMethod::DebitCard => "Debit Card",
            PaymentMethod::ApplePay => "Apple Pay",
            PaymentMethod::GooglePay => "Google Pay",
            PaymentMethod::BankTransfer => "Bank Transfer",
            PaymentMethod::Sepa => "SEPA",
            PaymentMethod::ACH => "ACH",
            PaymentMethod::Wire => "Wire Transfer",
            PaymentMethod::PIX => "PIX",
            PaymentMethod::iDEAL => "iDEAL",
        }
    }
    
    pub fn icon(&self) -> &str {
        match self {
            PaymentMethod::CreditCard => "creditcard",
            PaymentMethod::DebitCard => "creditcard",
            PaymentMethod::ApplePay => "applelogo",
            PaymentMethod::GooglePay => "g.circle",
            PaymentMethod::BankTransfer => "building.columns",
            PaymentMethod::Sepa => "eurosign.circle",
            PaymentMethod::ACH => "dollarsign.circle",
            PaymentMethod::Wire => "arrow.right.arrow.left",
            PaymentMethod::PIX => "qrcode",
            PaymentMethod::iDEAL => "building.2",
        }
    }
}

impl fmt::Display for PaymentMethod {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.name())
    }
}

/// On-ramp quote from a provider
#[derive(Debug, Clone)]
pub struct OnRampQuote {
    /// Provider offering this quote
    pub provider: OnRampProvider,
    /// Fiat amount being spent
    pub fiat_amount: f64,
    /// Fiat currency code (e.g., "USD", "EUR")
    pub fiat_currency: String,
    /// Crypto amount to receive
    pub crypto_amount: f64,
    /// Crypto currency code (e.g., "BTC", "ETH")
    pub crypto_currency: String,
    /// Network fee in crypto
    pub network_fee: f64,
    /// Provider fee in fiat
    pub provider_fee: f64,
    /// Total fees in fiat
    pub total_fees: f64,
    /// Exchange rate (1 crypto = X fiat)
    pub exchange_rate: f64,
    /// Supported payment methods
    pub payment_methods: Vec<PaymentMethod>,
    /// Quote expiry time (unix timestamp)
    pub expires_at: Option<u64>,
    /// Quote ID for reference
    pub quote_id: Option<String>,
}

impl OnRampQuote {
    /// Get effective rate (fiat spent / crypto received)
    pub fn effective_rate(&self) -> f64 {
        if self.crypto_amount == 0.0 {
            return 0.0;
        }
        self.fiat_amount / self.crypto_amount
    }
    
    /// Get fee percentage
    pub fn fee_percentage(&self) -> f64 {
        if self.fiat_amount == 0.0 {
            return 0.0;
        }
        (self.total_fees / self.fiat_amount) * 100.0
    }
}

/// Request for on-ramp quote
#[derive(Debug, Clone)]
pub struct OnRampRequest {
    /// Fiat amount to spend
    pub fiat_amount: f64,
    /// Fiat currency code
    pub fiat_currency: String,
    /// Crypto to buy
    pub crypto_currency: String,
    /// Wallet address to receive crypto
    pub wallet_address: String,
    /// Optional network/chain
    pub network: Option<String>,
    /// User's country code (ISO 3166-1 alpha-2)
    pub country_code: Option<String>,
    /// User's email (for some providers)
    pub email: Option<String>,
}

impl OnRampRequest {
    pub fn new(fiat_amount: f64, fiat_currency: &str, crypto_currency: &str, wallet_address: &str) -> Self {
        Self {
            fiat_amount,
            fiat_currency: fiat_currency.to_uppercase(),
            crypto_currency: crypto_currency.to_uppercase(),
            wallet_address: wallet_address.to_string(),
            network: None,
            country_code: None,
            email: None,
        }
    }
    
    pub fn with_network(mut self, network: &str) -> Self {
        self.network = Some(network.to_string());
        self
    }
    
    pub fn with_country(mut self, country: &str) -> Self {
        self.country_code = Some(country.to_uppercase());
        self
    }
    
    pub fn with_email(mut self, email: &str) -> Self {
        self.email = Some(email.to_string());
        self
    }
}

/// Aggregated quotes from multiple providers
#[derive(Debug, Clone)]
pub struct OnRampQuotes {
    pub request: OnRampRequest,
    pub quotes: Vec<OnRampQuote>,
    pub fetched_at: u64,
}

impl OnRampQuotes {
    pub fn new(request: OnRampRequest) -> Self {
        Self {
            request,
            quotes: Vec::new(),
            fetched_at: 0,
        }
    }
    
    /// Get best quote (lowest effective rate)
    pub fn best_quote(&self) -> Option<&OnRampQuote> {
        self.quotes.iter().min_by(|a, b| {
            a.effective_rate().partial_cmp(&b.effective_rate()).unwrap()
        })
    }
    
    /// Get quote with lowest fees
    pub fn lowest_fee_quote(&self) -> Option<&OnRampQuote> {
        self.quotes.iter().min_by(|a, b| {
            a.total_fees.partial_cmp(&b.total_fees).unwrap()
        })
    }
    
    /// Sort quotes by effective rate (best first)
    pub fn sorted_by_rate(&self) -> Vec<&OnRampQuote> {
        let mut sorted: Vec<_> = self.quotes.iter().collect();
        sorted.sort_by(|a, b| a.effective_rate().partial_cmp(&b.effective_rate()).unwrap());
        sorted
    }
}

/// Supported fiat currencies
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum FiatCurrency {
    USD,
    EUR,
    GBP,
    CAD,
    AUD,
    JPY,
    CHF,
    SEK,
    NOK,
    DKK,
    PLN,
    BRL,
    MXN,
    INR,
    SGD,
    HKD,
    NZD,
    KRW,
    TRY,
    ZAR,
}

impl FiatCurrency {
    pub fn code(&self) -> &str {
        match self {
            FiatCurrency::USD => "USD",
            FiatCurrency::EUR => "EUR",
            FiatCurrency::GBP => "GBP",
            FiatCurrency::CAD => "CAD",
            FiatCurrency::AUD => "AUD",
            FiatCurrency::JPY => "JPY",
            FiatCurrency::CHF => "CHF",
            FiatCurrency::SEK => "SEK",
            FiatCurrency::NOK => "NOK",
            FiatCurrency::DKK => "DKK",
            FiatCurrency::PLN => "PLN",
            FiatCurrency::BRL => "BRL",
            FiatCurrency::MXN => "MXN",
            FiatCurrency::INR => "INR",
            FiatCurrency::SGD => "SGD",
            FiatCurrency::HKD => "HKD",
            FiatCurrency::NZD => "NZD",
            FiatCurrency::KRW => "KRW",
            FiatCurrency::TRY => "TRY",
            FiatCurrency::ZAR => "ZAR",
        }
    }
    
    pub fn symbol(&self) -> &str {
        match self {
            FiatCurrency::USD => "$",
            FiatCurrency::EUR => "€",
            FiatCurrency::GBP => "£",
            FiatCurrency::CAD => "C$",
            FiatCurrency::AUD => "A$",
            FiatCurrency::JPY => "¥",
            FiatCurrency::CHF => "CHF",
            FiatCurrency::SEK => "kr",
            FiatCurrency::NOK => "kr",
            FiatCurrency::DKK => "kr",
            FiatCurrency::PLN => "zł",
            FiatCurrency::BRL => "R$",
            FiatCurrency::MXN => "MX$",
            FiatCurrency::INR => "₹",
            FiatCurrency::SGD => "S$",
            FiatCurrency::HKD => "HK$",
            FiatCurrency::NZD => "NZ$",
            FiatCurrency::KRW => "₩",
            FiatCurrency::TRY => "₺",
            FiatCurrency::ZAR => "R",
        }
    }
    
    pub fn name(&self) -> &str {
        match self {
            FiatCurrency::USD => "US Dollar",
            FiatCurrency::EUR => "Euro",
            FiatCurrency::GBP => "British Pound",
            FiatCurrency::CAD => "Canadian Dollar",
            FiatCurrency::AUD => "Australian Dollar",
            FiatCurrency::JPY => "Japanese Yen",
            FiatCurrency::CHF => "Swiss Franc",
            FiatCurrency::SEK => "Swedish Krona",
            FiatCurrency::NOK => "Norwegian Krone",
            FiatCurrency::DKK => "Danish Krone",
            FiatCurrency::PLN => "Polish Złoty",
            FiatCurrency::BRL => "Brazilian Real",
            FiatCurrency::MXN => "Mexican Peso",
            FiatCurrency::INR => "Indian Rupee",
            FiatCurrency::SGD => "Singapore Dollar",
            FiatCurrency::HKD => "Hong Kong Dollar",
            FiatCurrency::NZD => "New Zealand Dollar",
            FiatCurrency::KRW => "South Korean Won",
            FiatCurrency::TRY => "Turkish Lira",
            FiatCurrency::ZAR => "South African Rand",
        }
    }
    
    pub fn common() -> Vec<FiatCurrency> {
        vec![
            FiatCurrency::USD,
            FiatCurrency::EUR,
            FiatCurrency::GBP,
            FiatCurrency::CAD,
            FiatCurrency::AUD,
            FiatCurrency::JPY,
        ]
    }
    
    pub fn all() -> Vec<FiatCurrency> {
        vec![
            FiatCurrency::USD, FiatCurrency::EUR, FiatCurrency::GBP,
            FiatCurrency::CAD, FiatCurrency::AUD, FiatCurrency::JPY,
            FiatCurrency::CHF, FiatCurrency::SEK, FiatCurrency::NOK,
            FiatCurrency::DKK, FiatCurrency::PLN, FiatCurrency::BRL,
            FiatCurrency::MXN, FiatCurrency::INR, FiatCurrency::SGD,
            FiatCurrency::HKD, FiatCurrency::NZD, FiatCurrency::KRW,
            FiatCurrency::TRY, FiatCurrency::ZAR,
        ]
    }
}

impl fmt::Display for FiatCurrency {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.code())
    }
}

/// Supported crypto for on-ramp
#[derive(Debug, Clone)]
pub struct SupportedCrypto {
    pub symbol: String,
    pub name: String,
    pub networks: Vec<String>,
    pub min_amount: Option<f64>,
    pub max_amount: Option<f64>,
}

/// On-ramp error types
#[derive(Debug, Clone)]
pub enum OnRampError {
    NetworkError(String),
    InvalidAmount(String),
    UnsupportedCurrency(String),
    UnsupportedCountry(String),
    QuoteFailed(String),
    ProviderError(String),
}

impl fmt::Display for OnRampError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            OnRampError::NetworkError(msg) => write!(f, "Network error: {}", msg),
            OnRampError::InvalidAmount(msg) => write!(f, "Invalid amount: {}", msg),
            OnRampError::UnsupportedCurrency(msg) => write!(f, "Unsupported currency: {}", msg),
            OnRampError::UnsupportedCountry(msg) => write!(f, "Unsupported country: {}", msg),
            OnRampError::QuoteFailed(msg) => write!(f, "Quote failed: {}", msg),
            OnRampError::ProviderError(msg) => write!(f, "Provider error: {}", msg),
        }
    }
}

impl std::error::Error for OnRampError {}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_providers() {
        assert_eq!(OnRampProvider::MoonPay.name(), "MoonPay");
        assert_eq!(OnRampProvider::Transak.name(), "Transak");
        assert_eq!(OnRampProvider::Ramp.name(), "Ramp Network");
        
        let all = OnRampProvider::all();
        assert_eq!(all.len(), 3);
    }
    
    #[test]
    fn test_payment_methods() {
        assert_eq!(PaymentMethod::CreditCard.name(), "Credit Card");
        assert_eq!(PaymentMethod::ApplePay.name(), "Apple Pay");
        assert_eq!(PaymentMethod::Sepa.name(), "SEPA");
    }
    
    #[test]
    fn test_quote_calculations() {
        let quote = OnRampQuote {
            provider: OnRampProvider::MoonPay,
            fiat_amount: 100.0,
            fiat_currency: "USD".into(),
            crypto_amount: 0.002,
            crypto_currency: "BTC".into(),
            network_fee: 0.00001,
            provider_fee: 3.99,
            total_fees: 4.99,
            exchange_rate: 50000.0,
            payment_methods: vec![PaymentMethod::CreditCard, PaymentMethod::ApplePay],
            expires_at: None,
            quote_id: None,
        };
        
        assert_eq!(quote.effective_rate(), 50000.0);
        assert!((quote.fee_percentage() - 4.99).abs() < 0.001);
    }
    
    #[test]
    fn test_request_builder() {
        let request = OnRampRequest::new(100.0, "usd", "btc", "bc1q...")
            .with_network("bitcoin")
            .with_country("us")
            .with_email("test@example.com");
        
        assert_eq!(request.fiat_amount, 100.0);
        assert_eq!(request.fiat_currency, "USD");
        assert_eq!(request.crypto_currency, "BTC");
        assert_eq!(request.network, Some("bitcoin".into()));
        assert_eq!(request.country_code, Some("US".into()));
    }
    
    #[test]
    fn test_quotes_aggregation() {
        let request = OnRampRequest::new(100.0, "USD", "ETH", "0x...");
        let mut quotes = OnRampQuotes::new(request);
        
        quotes.quotes.push(OnRampQuote {
            provider: OnRampProvider::MoonPay,
            fiat_amount: 100.0,
            fiat_currency: "USD".into(),
            crypto_amount: 0.05,
            crypto_currency: "ETH".into(),
            network_fee: 0.001,
            provider_fee: 4.99,
            total_fees: 5.99,
            exchange_rate: 2000.0,
            payment_methods: vec![PaymentMethod::CreditCard],
            expires_at: None,
            quote_id: None,
        });
        
        quotes.quotes.push(OnRampQuote {
            provider: OnRampProvider::Transak,
            fiat_amount: 100.0,
            fiat_currency: "USD".into(),
            crypto_amount: 0.052,
            crypto_currency: "ETH".into(),
            network_fee: 0.001,
            provider_fee: 3.99,
            total_fees: 4.99,
            exchange_rate: 1920.0,
            payment_methods: vec![PaymentMethod::CreditCard],
            expires_at: None,
            quote_id: None,
        });
        
        let best = quotes.best_quote().unwrap();
        assert_eq!(best.provider, OnRampProvider::Transak);
        
        let lowest_fee = quotes.lowest_fee_quote().unwrap();
        assert_eq!(lowest_fee.provider, OnRampProvider::Transak);
    }
    
    #[test]
    fn test_fiat_currencies() {
        assert_eq!(FiatCurrency::USD.code(), "USD");
        assert_eq!(FiatCurrency::USD.symbol(), "$");
        assert_eq!(FiatCurrency::EUR.symbol(), "€");
        assert_eq!(FiatCurrency::GBP.symbol(), "£");
        assert_eq!(FiatCurrency::JPY.symbol(), "¥");
        assert_eq!(FiatCurrency::INR.symbol(), "₹");
        
        let common = FiatCurrency::common();
        assert!(common.contains(&FiatCurrency::USD));
        assert!(common.contains(&FiatCurrency::EUR));
    }
}
