//! Integration tests for on-ramp module

#[cfg(test)]
mod integration_tests {
    use crate::onramp::*;
    
    #[test]
    fn test_provider_comparison() {
        let request = OnRampRequest::new(100.0, "USD", "ETH", "0x742d35Cc6634C0532925a3b844Bc9e7595f1b0E0");
        
        // Build widget URLs for all providers
        let moonpay = MoonPayClient::new("pk_test".into());
        let transak = TransakClient::new("api_test".into());
        let ramp = RampClient::new("host_test".into());
        
        let mp_url = moonpay.build_widget_url(&request);
        let tr_url = transak.build_widget_url(&request);
        let rp_url = ramp.build_widget_url(&request);
        
        // All should contain the wallet address
        assert!(mp_url.contains("0x742d35Cc6634C0532925a3b844Bc9e7595f1b0E0"));
        assert!(tr_url.contains("0x742d35Cc6634C0532925a3b844Bc9e7595f1b0E0"));
        assert!(rp_url.contains("0x742d35Cc6634C0532925a3b844Bc9e7595f1b0E0"));
        
        // All should specify the crypto
        assert!(mp_url.to_lowercase().contains("eth"));
        assert!(tr_url.contains("ETH"));
        assert!(rp_url.contains("ETH"));
    }
    
    #[test]
    fn test_quote_aggregation() {
        let request = OnRampRequest::new(500.0, "USD", "BTC", "bc1qtest...");
        let mut quotes = OnRampQuotes::new(request.clone());
        
        // Add mock quotes from each provider
        quotes.quotes.push(OnRampQuote {
            provider: OnRampProvider::MoonPay,
            fiat_amount: 500.0,
            fiat_currency: "USD".into(),
            crypto_amount: 0.0105,
            crypto_currency: "BTC".into(),
            network_fee: 0.00001,
            provider_fee: 22.50,
            total_fees: 24.99,
            exchange_rate: 47619.05,
            payment_methods: vec![PaymentMethod::CreditCard],
            expires_at: None,
            quote_id: Some("mp-123".into()),
        });
        
        quotes.quotes.push(OnRampQuote {
            provider: OnRampProvider::Transak,
            fiat_amount: 500.0,
            fiat_currency: "USD".into(),
            crypto_amount: 0.0102,
            crypto_currency: "BTC".into(),
            network_fee: 0.00001,
            provider_fee: 25.00,
            total_fees: 27.50,
            exchange_rate: 49019.61,
            payment_methods: vec![PaymentMethod::CreditCard, PaymentMethod::Sepa],
            expires_at: None,
            quote_id: Some("tr-456".into()),
        });
        
        quotes.quotes.push(OnRampQuote {
            provider: OnRampProvider::Ramp,
            fiat_amount: 500.0,
            fiat_currency: "USD".into(),
            crypto_amount: 0.0108,
            crypto_currency: "BTC".into(),
            network_fee: 0.00001,
            provider_fee: 12.50,
            total_fees: 14.99,
            exchange_rate: 46296.30,
            payment_methods: vec![PaymentMethod::CreditCard, PaymentMethod::BankTransfer],
            expires_at: None,
            quote_id: None,
        });
        
        // Best quote should be Ramp (lowest effective rate = most crypto)
        let best = quotes.best_quote().unwrap();
        assert_eq!(best.provider, OnRampProvider::Ramp);
        
        // Lowest fee should also be Ramp
        let lowest_fee = quotes.lowest_fee_quote().unwrap();
        assert_eq!(lowest_fee.provider, OnRampProvider::Ramp);
        
        // Sorted by rate
        let sorted = quotes.sorted_by_rate();
        assert_eq!(sorted[0].provider, OnRampProvider::Ramp);
        assert_eq!(sorted[2].provider, OnRampProvider::Transak);
    }
    
    #[test]
    fn test_all_providers() {
        let providers = OnRampProvider::all();
        
        assert_eq!(providers.len(), 3);
        assert!(providers.contains(&OnRampProvider::MoonPay));
        assert!(providers.contains(&OnRampProvider::Transak));
        assert!(providers.contains(&OnRampProvider::Ramp));
    }
    
    #[test]
    fn test_payment_methods() {
        // MoonPay supports these
        let mp = MoonPayClient::new("key".into());
        let request = OnRampRequest::new(100.0, "USD", "ETH", "0x...");
        let mp_json = r#"{"quoteCurrencyAmount": 0.05, "feeAmount": 4.99, "networkFeeAmount": 0.01}"#;
        let mp_quote = mp.parse_quote(mp_json, &request).unwrap();
        
        assert!(mp_quote.payment_methods.contains(&PaymentMethod::CreditCard));
        assert!(mp_quote.payment_methods.contains(&PaymentMethod::ApplePay));
        
        // Transak supports SEPA
        let tr = TransakClient::new("key".into());
        let tr_json = r#"{"response": {"cryptoAmount": 0.05, "totalFee": 5.50}}"#;
        let tr_quote = tr.parse_quote(tr_json, &request).unwrap();
        
        assert!(tr_quote.payment_methods.contains(&PaymentMethod::Sepa));
        
        // Ramp supports iDEAL
        let rp = RampClient::new("key".into());
        let rp_json = r#"{"cryptoAmount": "50000000000000000", "asset": {"decimals": 18}, "baseRampFee": 2.50, "appliedFee": 0.10}"#;
        let rp_quote = rp.parse_quote(rp_json, &request).unwrap();
        
        assert!(rp_quote.payment_methods.contains(&PaymentMethod::iDEAL));
    }
    
    #[test]
    fn test_network_specific_requests() {
        // Request USDC on Polygon
        let request = OnRampRequest::new(100.0, "USD", "USDC", "0x...")
            .with_network("polygon")
            .with_country("US")
            .with_email("test@example.com");
        
        let ramp = RampClient::new("key".into());
        let url = ramp.build_widget_url(&request);
        
        assert!(url.contains("USDC_POLYGON"));
        
        let transak = TransakClient::new("key".into());
        let tr_url = transak.build_widget_url(&request);
        
        assert!(tr_url.contains("network=polygon"));
        assert!(tr_url.contains("email=test@example.com"));
    }
    
    #[test]
    fn test_fiat_currencies() {
        let common = FiatCurrency::common();
        
        assert_eq!(common.len(), 6);
        assert!(common.contains(&FiatCurrency::USD));
        assert!(common.contains(&FiatCurrency::EUR));
        assert!(common.contains(&FiatCurrency::GBP));
        
        let all = FiatCurrency::all();
        assert_eq!(all.len(), 20);
    }
    
    #[test]
    fn test_fee_calculations() {
        let quote = OnRampQuote {
            provider: OnRampProvider::MoonPay,
            fiat_amount: 100.0,
            fiat_currency: "USD".into(),
            crypto_amount: 0.045,
            crypto_currency: "ETH".into(),
            network_fee: 0.001,
            provider_fee: 4.50,
            total_fees: 5.00,
            exchange_rate: 2222.22,
            payment_methods: vec![],
            expires_at: None,
            quote_id: None,
        };
        
        assert!((quote.effective_rate() - 2222.22).abs() < 0.1);
        assert_eq!(quote.fee_percentage(), 5.0);
    }
    
    #[test]
    fn test_supported_cryptos_union() {
        // All providers should support core assets
        let mp_cryptos = MoonPayClient::supported_cryptos();
        let tr_cryptos = TransakClient::supported_cryptos();
        let rp_cryptos = RampClient::supported_cryptos();
        
        // BTC, ETH, USDC should be universal
        let has_btc = |c: &[SupportedCrypto]| c.iter().any(|x| x.symbol == "BTC");
        let has_eth = |c: &[SupportedCrypto]| c.iter().any(|x| x.symbol == "ETH");
        let has_usdc = |c: &[SupportedCrypto]| c.iter().any(|x| x.symbol == "USDC");
        
        assert!(has_btc(&mp_cryptos));
        assert!(has_btc(&tr_cryptos));
        assert!(has_btc(&rp_cryptos));
        
        assert!(has_eth(&mp_cryptos));
        assert!(has_eth(&tr_cryptos));
        assert!(has_eth(&rp_cryptos));
        
        assert!(has_usdc(&mp_cryptos));
        assert!(has_usdc(&tr_cryptos));
        assert!(has_usdc(&rp_cryptos));
    }
    
    #[test]
    fn test_sandbox_staging_modes() {
        // MoonPay sandbox
        let mp_sandbox = MoonPayClient::sandbox("key".into());
        assert!(mp_sandbox.sandbox);
        assert!(mp_sandbox.widget_url.contains("sandbox"));
        
        // Transak staging
        let tr_staging = TransakClient::staging("key".into());
        assert!(tr_staging.staging);
        assert!(tr_staging.widget_url.contains("stg"));
        
        // Ramp staging
        let rp_staging = RampClient::staging("key".into());
        assert!(rp_staging.staging);
        assert!(rp_staging.widget_url.contains("staging"));
    }
    
    #[test]
    fn test_error_handling() {
        let mp = MoonPayClient::new("key".into());
        let request = OnRampRequest::new(100.0, "USD", "ETH", "0x...");
        
        // Error response
        let error_json = r#"{"message": "Invalid currency"}"#;
        let result = mp.parse_quote(error_json, &request);
        
        assert!(result.is_err());
        match result {
            Err(OnRampError::QuoteFailed(msg)) => assert!(msg.contains("Invalid")),
            _ => panic!("Expected QuoteFailed error"),
        }
    }
}
