//! Fiat Off-Ramp Service
//!
//! Integration with fiat off-ramp providers (MoonPay, Transak, etc.)
//! to sell crypto and receive fiat to bank accounts.

use crate::error::{HawalaError, HawalaResult, ErrorCode};
use crate::types::Chain;
use serde::{Deserialize, Serialize};

// =============================================================================
// Types
// =============================================================================

/// Supported off-ramp providers
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum OffRampProvider {
    MoonPay,
    Transak,
    Ramp,
    Sardine,
    Banxa,
}

/// Supported fiat currencies
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FiatCurrency {
    pub code: String,          // USD, EUR, GBP
    pub name: String,
    pub symbol: String,        // $, €, £
    pub min_amount: f64,
    pub max_amount: f64,
}

/// Crypto asset that can be sold
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SellableCrypto {
    pub symbol: String,        // ETH, BTC, etc.
    pub name: String,
    pub chain: Chain,
    pub contract_address: Option<String>,
    pub min_amount: f64,
    pub max_amount: f64,
}

/// Off-ramp quote request
#[derive(Debug, Clone, Deserialize)]
pub struct OffRampQuoteRequest {
    /// Provider to use
    pub provider: OffRampProvider,
    /// Crypto to sell
    pub crypto_symbol: String,
    /// Amount of crypto to sell
    pub crypto_amount: f64,
    /// Fiat currency to receive
    pub fiat_currency: String,
    /// User's country (ISO code)
    pub country: String,
}

/// Off-ramp quote
#[derive(Debug, Clone, Serialize)]
pub struct OffRampQuote {
    /// Provider
    pub provider: OffRampProvider,
    /// Crypto amount to sell
    pub crypto_amount: f64,
    /// Crypto symbol
    pub crypto_symbol: String,
    /// Fiat amount to receive
    pub fiat_amount: f64,
    /// Fiat currency
    pub fiat_currency: String,
    /// Exchange rate
    pub exchange_rate: f64,
    /// Provider fee
    pub provider_fee: f64,
    /// Network fee
    pub network_fee: f64,
    /// Total fees
    pub total_fees: f64,
    /// Quote expiry (Unix timestamp)
    pub expires_at: u64,
    /// Quote ID for reference
    pub quote_id: String,
}

/// Off-ramp transaction request
#[derive(Debug, Clone, Deserialize)]
pub struct OffRampRequest {
    /// Quote ID from a previous quote request
    pub quote_id: String,
    /// Provider
    pub provider: OffRampProvider,
    /// Wallet address to send crypto from
    pub wallet_address: String,
    /// Email for notifications
    pub email: String,
    /// Bank account details (provider-specific)
    pub bank_details: Option<BankDetails>,
}

/// Bank account details for receiving fiat
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BankDetails {
    /// Account holder name
    pub account_name: String,
    /// Account number or IBAN
    pub account_number: String,
    /// Bank name
    pub bank_name: Option<String>,
    /// Routing/sort code
    pub routing_number: Option<String>,
    /// SWIFT/BIC code
    pub swift_code: Option<String>,
}

/// Off-ramp transaction result
#[derive(Debug, Clone, Serialize)]
pub struct OffRampTransaction {
    /// Transaction ID from provider
    pub id: String,
    /// Provider
    pub provider: OffRampProvider,
    /// Status
    pub status: OffRampStatus,
    /// Crypto amount sent
    pub crypto_amount: f64,
    /// Crypto symbol
    pub crypto_symbol: String,
    /// Fiat amount to receive
    pub fiat_amount: f64,
    /// Fiat currency
    pub fiat_currency: String,
    /// Deposit address (send crypto here)
    pub deposit_address: String,
    /// Created timestamp
    pub created_at: u64,
    /// Widget URL to complete KYC/transaction
    pub widget_url: Option<String>,
}

/// Off-ramp transaction status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum OffRampStatus {
    Pending,
    AwaitingDeposit,
    Processing,
    Completed,
    Failed,
    Expired,
    Refunded,
}

// =============================================================================
// Off-Ramp Service
// =============================================================================

/// Off-ramp service for selling crypto to fiat
pub struct OffRampService {
    /// API keys for providers
    moonpay_api_key: Option<String>,
    transak_api_key: Option<String>,
}

impl OffRampService {
    /// Create a new off-ramp service
    pub fn new() -> Self {
        Self {
            moonpay_api_key: std::env::var("MOONPAY_API_KEY").ok(),
            transak_api_key: std::env::var("TRANSAK_API_KEY").ok(),
        }
    }

    /// Set MoonPay API key
    pub fn set_moonpay_key(&mut self, key: String) {
        self.moonpay_api_key = Some(key);
    }

    /// Set Transak API key
    pub fn set_transak_key(&mut self, key: String) {
        self.transak_api_key = Some(key);
    }

    /// Get supported fiat currencies for a provider
    pub fn get_supported_currencies(&self, provider: OffRampProvider) -> Vec<FiatCurrency> {
        match provider {
            OffRampProvider::MoonPay => vec![
                FiatCurrency {
                    code: "USD".to_string(),
                    name: "US Dollar".to_string(),
                    symbol: "$".to_string(),
                    min_amount: 20.0,
                    max_amount: 50000.0,
                },
                FiatCurrency {
                    code: "EUR".to_string(),
                    name: "Euro".to_string(),
                    symbol: "€".to_string(),
                    min_amount: 20.0,
                    max_amount: 50000.0,
                },
                FiatCurrency {
                    code: "GBP".to_string(),
                    name: "British Pound".to_string(),
                    symbol: "£".to_string(),
                    min_amount: 20.0,
                    max_amount: 50000.0,
                },
            ],
            OffRampProvider::Transak => vec![
                FiatCurrency {
                    code: "USD".to_string(),
                    name: "US Dollar".to_string(),
                    symbol: "$".to_string(),
                    min_amount: 30.0,
                    max_amount: 20000.0,
                },
                FiatCurrency {
                    code: "EUR".to_string(),
                    name: "Euro".to_string(),
                    symbol: "€".to_string(),
                    min_amount: 30.0,
                    max_amount: 20000.0,
                },
            ],
            _ => vec![
                FiatCurrency {
                    code: "USD".to_string(),
                    name: "US Dollar".to_string(),
                    symbol: "$".to_string(),
                    min_amount: 20.0,
                    max_amount: 10000.0,
                },
            ],
        }
    }

    /// Get supported crypto assets for selling
    pub fn get_sellable_cryptos(&self, provider: OffRampProvider) -> Vec<SellableCrypto> {
        match provider {
            OffRampProvider::MoonPay | OffRampProvider::Transak => vec![
                SellableCrypto {
                    symbol: "ETH".to_string(),
                    name: "Ethereum".to_string(),
                    chain: Chain::Ethereum,
                    contract_address: None,
                    min_amount: 0.01,
                    max_amount: 100.0,
                },
                SellableCrypto {
                    symbol: "BTC".to_string(),
                    name: "Bitcoin".to_string(),
                    chain: Chain::Bitcoin,
                    contract_address: None,
                    min_amount: 0.0005,
                    max_amount: 10.0,
                },
                SellableCrypto {
                    symbol: "USDC".to_string(),
                    name: "USD Coin".to_string(),
                    chain: Chain::Ethereum,
                    contract_address: Some("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48".to_string()),
                    min_amount: 20.0,
                    max_amount: 50000.0,
                },
                SellableCrypto {
                    symbol: "USDT".to_string(),
                    name: "Tether".to_string(),
                    chain: Chain::Ethereum,
                    contract_address: Some("0xdac17f958d2ee523a2206206994597c13d831ec7".to_string()),
                    min_amount: 20.0,
                    max_amount: 50000.0,
                },
                SellableCrypto {
                    symbol: "SOL".to_string(),
                    name: "Solana".to_string(),
                    chain: Chain::Solana,
                    contract_address: None,
                    min_amount: 0.5,
                    max_amount: 1000.0,
                },
            ],
            _ => vec![],
        }
    }

    /// Get a quote for selling crypto
    pub fn get_quote(&self, request: &OffRampQuoteRequest) -> HawalaResult<OffRampQuote> {
        match request.provider {
            OffRampProvider::MoonPay => self.get_moonpay_quote(request),
            OffRampProvider::Transak => self.get_transak_quote(request),
            _ => Err(HawalaError::new(
                ErrorCode::InvalidInput,
                format!("{:?} provider not yet supported", request.provider),
            )),
        }
    }

    /// Compare quotes from all available providers
    pub fn compare_quotes(&self, crypto_symbol: &str, crypto_amount: f64, fiat_currency: &str, country: &str) -> Vec<OffRampQuote> {
        let providers = [OffRampProvider::MoonPay, OffRampProvider::Transak];
        
        providers
            .iter()
            .filter_map(|provider| {
                let request = OffRampQuoteRequest {
                    provider: *provider,
                    crypto_symbol: crypto_symbol.to_string(),
                    crypto_amount,
                    fiat_currency: fiat_currency.to_string(),
                    country: country.to_string(),
                };
                self.get_quote(&request).ok()
            })
            .collect()
    }

    /// Start an off-ramp transaction
    pub fn start_transaction(&self, request: &OffRampRequest) -> HawalaResult<OffRampTransaction> {
        match request.provider {
            OffRampProvider::MoonPay => self.start_moonpay_transaction(request),
            OffRampProvider::Transak => self.start_transak_transaction(request),
            _ => Err(HawalaError::new(
                ErrorCode::InvalidInput,
                format!("{:?} provider not yet supported", request.provider),
            )),
        }
    }

    /// Get transaction status
    pub fn get_transaction_status(&self, provider: OffRampProvider, transaction_id: &str) -> HawalaResult<OffRampTransaction> {
        match provider {
            OffRampProvider::MoonPay => self.get_moonpay_transaction(transaction_id),
            OffRampProvider::Transak => self.get_transak_transaction(transaction_id),
            _ => Err(HawalaError::new(ErrorCode::InvalidInput, "Provider not supported")),
        }
    }

    /// Generate widget URL for completing KYC and transaction
    pub fn generate_widget_url(&self, provider: OffRampProvider, request: &OffRampRequest) -> HawalaResult<String> {
        match provider {
            OffRampProvider::MoonPay => {
                let api_key = self.moonpay_api_key.as_ref()
                    .ok_or_else(|| HawalaError::new(ErrorCode::InvalidInput, "MoonPay API key not configured"))?;
                
                Ok(format!(
                    "https://sell.moonpay.com/?apiKey={}&baseCurrencyCode={}&walletAddress={}",
                    api_key,
                    "eth",  // Would use request params
                    request.wallet_address
                ))
            }
            OffRampProvider::Transak => {
                let api_key = self.transak_api_key.as_ref()
                    .ok_or_else(|| HawalaError::new(ErrorCode::InvalidInput, "Transak API key not configured"))?;
                
                Ok(format!(
                    "https://global.transak.com/?apiKey={}&walletAddress={}&productsAvailed=SELL",
                    api_key,
                    request.wallet_address
                ))
            }
            _ => Err(HawalaError::new(ErrorCode::InvalidInput, "Provider not supported")),
        }
    }

    // =========================================================================
    // Provider-specific implementations
    // =========================================================================

    fn get_moonpay_quote(&self, request: &OffRampQuoteRequest) -> HawalaResult<OffRampQuote> {
        // Simulated quote - in production would call MoonPay API
        let exchange_rate = self.get_mock_exchange_rate(&request.crypto_symbol, &request.fiat_currency);
        let fiat_amount = request.crypto_amount * exchange_rate;
        let provider_fee = fiat_amount * 0.015; // 1.5% fee
        let network_fee = 2.0; // Fixed network fee
        let total_fees = provider_fee + network_fee;
        
        Ok(OffRampQuote {
            provider: OffRampProvider::MoonPay,
            crypto_amount: request.crypto_amount,
            crypto_symbol: request.crypto_symbol.clone(),
            fiat_amount: fiat_amount - total_fees,
            fiat_currency: request.fiat_currency.clone(),
            exchange_rate,
            provider_fee,
            network_fee,
            total_fees,
            expires_at: current_timestamp() + 300, // 5 minutes
            quote_id: format!("mp_quote_{}", current_timestamp()),
        })
    }

    fn get_transak_quote(&self, request: &OffRampQuoteRequest) -> HawalaResult<OffRampQuote> {
        // Simulated quote - in production would call Transak API
        let exchange_rate = self.get_mock_exchange_rate(&request.crypto_symbol, &request.fiat_currency);
        let fiat_amount = request.crypto_amount * exchange_rate;
        let provider_fee = fiat_amount * 0.02; // 2% fee
        let network_fee = 1.5;
        let total_fees = provider_fee + network_fee;
        
        Ok(OffRampQuote {
            provider: OffRampProvider::Transak,
            crypto_amount: request.crypto_amount,
            crypto_symbol: request.crypto_symbol.clone(),
            fiat_amount: fiat_amount - total_fees,
            fiat_currency: request.fiat_currency.clone(),
            exchange_rate,
            provider_fee,
            network_fee,
            total_fees,
            expires_at: current_timestamp() + 600, // 10 minutes
            quote_id: format!("tr_quote_{}", current_timestamp()),
        })
    }

    fn start_moonpay_transaction(&self, request: &OffRampRequest) -> HawalaResult<OffRampTransaction> {
        // In production, would call MoonPay API to create sell transaction
        let widget_url = self.generate_widget_url(OffRampProvider::MoonPay, request)?;
        
        Ok(OffRampTransaction {
            id: format!("mp_tx_{}", current_timestamp()),
            provider: OffRampProvider::MoonPay,
            status: OffRampStatus::Pending,
            crypto_amount: 0.0, // Would come from quote
            crypto_symbol: "ETH".to_string(),
            fiat_amount: 0.0,
            fiat_currency: "USD".to_string(),
            deposit_address: "0x...".to_string(), // Would be generated
            created_at: current_timestamp(),
            widget_url: Some(widget_url),
        })
    }

    fn start_transak_transaction(&self, request: &OffRampRequest) -> HawalaResult<OffRampTransaction> {
        let widget_url = self.generate_widget_url(OffRampProvider::Transak, request)?;
        
        Ok(OffRampTransaction {
            id: format!("tr_tx_{}", current_timestamp()),
            provider: OffRampProvider::Transak,
            status: OffRampStatus::Pending,
            crypto_amount: 0.0,
            crypto_symbol: "ETH".to_string(),
            fiat_amount: 0.0,
            fiat_currency: "USD".to_string(),
            deposit_address: "0x...".to_string(),
            created_at: current_timestamp(),
            widget_url: Some(widget_url),
        })
    }

    fn get_moonpay_transaction(&self, _transaction_id: &str) -> HawalaResult<OffRampTransaction> {
        // In production, would call MoonPay API
        Err(HawalaError::new(ErrorCode::InvalidInput, "Transaction lookup requires API integration"))
    }

    fn get_transak_transaction(&self, _transaction_id: &str) -> HawalaResult<OffRampTransaction> {
        // In production, would call Transak API
        Err(HawalaError::new(ErrorCode::InvalidInput, "Transaction lookup requires API integration"))
    }

    fn get_mock_exchange_rate(&self, crypto: &str, fiat: &str) -> f64 {
        // Mock exchange rates
        let base_usd = match crypto.to_uppercase().as_str() {
            "BTC" => 65000.0,
            "ETH" => 2500.0,
            "SOL" => 150.0,
            "USDC" | "USDT" => 1.0,
            _ => 100.0,
        };
        
        // Convert to target fiat
        match fiat.to_uppercase().as_str() {
            "EUR" => base_usd * 0.92,
            "GBP" => base_usd * 0.79,
            _ => base_usd, // USD
        }
    }
}

impl Default for OffRampService {
    fn default() -> Self {
        Self::new()
    }
}

// =============================================================================
// Helper Functions
// =============================================================================

fn current_timestamp() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_supported_currencies() {
        let service = OffRampService::new();
        
        let currencies = service.get_supported_currencies(OffRampProvider::MoonPay);
        assert!(!currencies.is_empty());
        assert!(currencies.iter().any(|c| c.code == "USD"));
        assert!(currencies.iter().any(|c| c.code == "EUR"));
    }

    #[test]
    fn test_get_sellable_cryptos() {
        let service = OffRampService::new();
        
        let cryptos = service.get_sellable_cryptos(OffRampProvider::MoonPay);
        assert!(!cryptos.is_empty());
        assert!(cryptos.iter().any(|c| c.symbol == "ETH"));
        assert!(cryptos.iter().any(|c| c.symbol == "BTC"));
    }

    #[test]
    fn test_get_quote() {
        let service = OffRampService::new();
        
        let request = OffRampQuoteRequest {
            provider: OffRampProvider::MoonPay,
            crypto_symbol: "ETH".to_string(),
            crypto_amount: 1.0,
            fiat_currency: "USD".to_string(),
            country: "US".to_string(),
        };

        let quote = service.get_quote(&request).unwrap();
        assert_eq!(quote.crypto_symbol, "ETH");
        assert_eq!(quote.fiat_currency, "USD");
        assert!(quote.fiat_amount > 0.0);
        assert!(quote.exchange_rate > 0.0);
    }

    #[test]
    fn test_compare_quotes() {
        let service = OffRampService::new();
        
        let quotes = service.compare_quotes("ETH", 1.0, "USD", "US");
        // Should get quotes from multiple providers
        assert!(!quotes.is_empty());
    }

    #[test]
    fn test_quote_fees() {
        let service = OffRampService::new();
        
        let request = OffRampQuoteRequest {
            provider: OffRampProvider::MoonPay,
            crypto_symbol: "ETH".to_string(),
            crypto_amount: 1.0,
            fiat_currency: "USD".to_string(),
            country: "US".to_string(),
        };

        let quote = service.get_quote(&request).unwrap();
        assert!(quote.provider_fee > 0.0);
        assert!(quote.total_fees == quote.provider_fee + quote.network_fee);
    }

    #[test]
    fn test_fiat_currency_conversion() {
        let service = OffRampService::new();
        
        let usd_request = OffRampQuoteRequest {
            provider: OffRampProvider::MoonPay,
            crypto_symbol: "ETH".to_string(),
            crypto_amount: 1.0,
            fiat_currency: "USD".to_string(),
            country: "US".to_string(),
        };

        let eur_request = OffRampQuoteRequest {
            fiat_currency: "EUR".to_string(),
            ..usd_request.clone()
        };

        let usd_quote = service.get_quote(&usd_request).unwrap();
        let eur_quote = service.get_quote(&eur_request).unwrap();
        
        // EUR should be less than USD for same amount
        assert!(eur_quote.fiat_amount < usd_quote.fiat_amount);
    }
}
