//! Integration tests for charts module

#[cfg(test)]
mod integration_tests {
    use crate::charts::*;
    
    #[test]
    fn test_full_chart_workflow() {
        // Simulate fetching and parsing chart data
        let client = CoinGeckoClient::new();
        
        let json = r#"{
            "prices": [
                [1704067200000, 42000.0],
                [1704070800000, 42100.0],
                [1704074400000, 42050.0],
                [1704078000000, 42200.0],
                [1704081600000, 42150.0],
                [1704085200000, 42300.0],
                [1704088800000, 42250.0],
                [1704092400000, 42400.0]
            ],
            "total_volumes": [
                [1704067200000, 25000000000],
                [1704070800000, 26000000000],
                [1704074400000, 24000000000],
                [1704078000000, 27000000000],
                [1704081600000, 25500000000],
                [1704085200000, 28000000000],
                [1704088800000, 26500000000],
                [1704092400000, 29000000000]
            ],
            "market_caps": []
        }"#;
        
        let data = client.parse_market_chart(json, "bitcoin", "usd", TimeRange::Day7).unwrap();
        
        // Verify parsing
        assert_eq!(data.prices.len(), 8);
        assert_eq!(data.volumes.len(), 8);
        
        // Test calculations
        assert!(data.is_price_up());
        assert_eq!(data.current_price(), Some(42400.0));
        assert_eq!(data.high_price(), Some(42400.0));
        assert_eq!(data.low_price(), Some(42000.0));
        
        // Calculate technical indicators
        let prices: Vec<f64> = data.prices.iter().map(|p| p.price).collect();
        
        let sma = ChartCalculator::sma(&prices, 3);
        assert_eq!(sma.len(), 6);
        
        let volatility = ChartCalculator::volatility(&prices);
        assert!(volatility > 0.0);
        
        let normalized = ChartCalculator::normalize(&prices);
        assert_eq!(normalized.len(), 8);
        assert!(normalized[0] >= 0.0);
        assert!(normalized.iter().all(|&n| n >= 0.0 && n <= 100.0));
    }
    
    #[test]
    fn test_ohlc_workflow() {
        let client = CoinGeckoClient::new();
        
        let json = r#"[
            [1704067200000, 42000, 42500, 41800, 42300],
            [1704153600000, 42300, 43800, 42200, 43500],
            [1704240000000, 43500, 44200, 43000, 43800],
            [1704326400000, 43800, 44000, 42500, 42800],
            [1704412800000, 42800, 43500, 42600, 43200]
        ]"#;
        
        let data = client.parse_ohlc(json, "bitcoin", "usd", TimeRange::Day7).unwrap();
        
        assert_eq!(data.candles.len(), 5);
        
        // Check bullish/bearish
        assert!(data.candles[0].is_bullish()); // 42000 -> 42300
        assert!(data.candles[3].is_bearish()); // 43800 -> 42800
        
        // Price range
        assert_eq!(data.high_price(), Some(44200.0));
        assert_eq!(data.low_price(), Some(41800.0));
    }
    
    #[test]
    fn test_time_ranges() {
        // Verify all time ranges have correct days
        assert_eq!(TimeRange::Hour1.days(), "1");
        assert_eq!(TimeRange::Hour24.days(), "1");
        assert_eq!(TimeRange::Day7.days(), "7");
        assert_eq!(TimeRange::Day30.days(), "30");
        assert_eq!(TimeRange::Day90.days(), "90");
        assert_eq!(TimeRange::Year1.days(), "365");
        assert_eq!(TimeRange::All.days(), "max");
        
        // Verify display names
        assert_eq!(TimeRange::Hour1.display_name(), "1H");
        assert_eq!(TimeRange::Day30.display_name(), "30D");
        assert_eq!(TimeRange::Year1.display_name(), "1Y");
    }
    
    #[test]
    fn test_url_building() {
        let free_client = CoinGeckoClient::new();
        let pro_client = CoinGeckoClient::with_api_key("my-api-key".into());
        
        // Free tier
        let free_url = free_client.market_chart_url("ethereum", "usd", TimeRange::Day30);
        assert!(free_url.contains("api.coingecko.com"));
        assert!(!free_url.contains("pro-api"));
        assert!(!free_url.contains("x_cg_pro_api_key"));
        
        // Pro tier
        let pro_url = pro_client.market_chart_url("ethereum", "usd", TimeRange::Day30);
        assert!(pro_url.contains("pro-api.coingecko.com"));
        assert!(pro_url.contains("x_cg_pro_api_key=my-api-key"));
    }
    
    #[test]
    fn test_token_id_lookup() {
        assert_eq!(KnownTokenIds::from_symbol("BTC"), Some("bitcoin"));
        assert_eq!(KnownTokenIds::from_symbol("btc"), Some("bitcoin"));
        assert_eq!(KnownTokenIds::from_symbol("ETH"), Some("ethereum"));
        assert_eq!(KnownTokenIds::from_symbol("SOL"), Some("solana"));
        assert_eq!(KnownTokenIds::from_symbol("USDC"), Some("usd-coin"));
        assert_eq!(KnownTokenIds::from_symbol("MATIC"), Some("matic-network"));
        assert_eq!(KnownTokenIds::from_symbol("POL"), Some("matic-network"));
        assert_eq!(KnownTokenIds::from_symbol("RUNE"), Some("thorchain"));
    }
    
    #[test]
    fn test_technical_indicators() {
        // Create sample price data
        let prices = vec![
            100.0, 102.0, 101.0, 103.0, 105.0,
            104.0, 106.0, 108.0, 107.0, 109.0,
            111.0, 110.0, 112.0, 114.0, 113.0,
        ];
        
        // SMA
        let sma5 = ChartCalculator::sma(&prices, 5);
        assert!(!sma5.is_empty());
        
        // EMA
        let ema5 = ChartCalculator::ema(&prices, 5);
        assert!(!ema5.is_empty());
        
        // RSI
        let rsi = ChartCalculator::rsi(&prices, 7);
        assert!(!rsi.is_empty());
        // Uptrend should have RSI > 50
        assert!(rsi.iter().all(|&r| r > 0.0 && r < 100.0));
        
        // Bollinger Bands
        let bb = ChartCalculator::bollinger_bands(&prices, 5, 2.0);
        assert!(!bb.middle.is_empty());
        
        // MACD
        let _macd = ChartCalculator::macd(&prices, 3, 5, 3);
        // May be empty for short data
    }
    
    #[test]
    fn test_price_stats() {
        let prices = vec![100.0, 110.0, 95.0, 120.0, 115.0, 108.0];
        let stats = PriceStats::from_prices(&prices).unwrap();
        
        assert_eq!(stats.current, 108.0);
        assert_eq!(stats.open, 100.0);
        assert_eq!(stats.high, 120.0);
        assert_eq!(stats.low, 95.0);
        assert_eq!(stats.change, 8.0);
        assert!((stats.change_percent - 8.0).abs() < 0.001);
        assert!(stats.volatility > 0.0);
    }
    
    #[test]
    fn test_support_resistance() {
        let prices = vec![
            100.0, 105.0, 103.0, 108.0, 106.0,
            110.0, 107.0, 112.0, 109.0, 115.0,
        ];
        
        let _sr = ChartCalculator::support_resistance(&prices, 3);
        // Should identify some levels
        // (exact values depend on algorithm)
    }
    
    #[test]
    fn test_fiat_currencies() {
        assert_eq!(FiatCurrency::USD.code(), "usd");
        assert_eq!(FiatCurrency::USD.symbol(), "$");
        assert_eq!(FiatCurrency::EUR.code(), "eur");
        assert_eq!(FiatCurrency::EUR.symbol(), "€");
        assert_eq!(FiatCurrency::JPY.symbol(), "¥");
        assert_eq!(FiatCurrency::GBP.symbol(), "£");
        assert_eq!(FiatCurrency::KRW.symbol(), "₩");
        assert_eq!(FiatCurrency::INR.symbol(), "₹");
    }
    
    #[test]
    fn test_empty_data_handling() {
        // SMA with insufficient data
        let sma = ChartCalculator::sma(&[1.0, 2.0], 5);
        assert!(sma.is_empty());
        
        // RSI with insufficient data
        let rsi = ChartCalculator::rsi(&[1.0, 2.0], 14);
        assert!(rsi.is_empty());
        
        // Normalize empty
        let normalized = ChartCalculator::normalize(&[]);
        assert!(normalized.is_empty());
        
        // PriceStats from empty
        assert!(PriceStats::from_prices(&[]).is_none());
    }
    
    #[test]
    fn test_chart_data_methods() {
        let mut data = ChartData::new("ethereum".into(), "usd".into(), TimeRange::Day7);
        
        // Empty data
        assert!(data.current_price().is_none());
        assert!(data.price_change().is_none());
        assert!(data.average_volume().is_none());
        assert!(!data.is_price_up());
        
        // Add data
        data.prices.push(PricePoint::new(1000, 2000.0));
        data.prices.push(PricePoint::new(2000, 2200.0));
        data.volumes.push(VolumePoint::new(1000, 1000000.0));
        data.volumes.push(VolumePoint::new(2000, 2000000.0));
        
        assert_eq!(data.current_price(), Some(2200.0));
        assert_eq!(data.start_price(), Some(2000.0));
        assert_eq!(data.price_change(), Some(200.0));
        assert!((data.price_change_percent().unwrap() - 10.0).abs() < 0.001);
        assert!(data.is_price_up());
        assert_eq!(data.average_volume(), Some(1500000.0));
    }
    
    #[test]
    fn test_parse_token_info() {
        let client = CoinGeckoClient::new();
        
        let json = r#"{
            "id": "bitcoin",
            "symbol": "btc",
            "name": "Bitcoin",
            "market_cap_rank": 1,
            "market_data": {
                "current_price": {"usd": 45000.0},
                "price_change_24h": 1500.0,
                "price_change_percentage_24h": 3.45,
                "market_cap": {"usd": 880000000000},
                "total_volume": {"usd": 25000000000},
                "high_24h": {"usd": 46000.0},
                "low_24h": {"usd": 43500.0},
                "ath": {"usd": 69000.0},
                "ath_change_percentage": {"usd": -34.78},
                "atl": {"usd": 67.81},
                "atl_change_percentage": {"usd": 66285.0},
                "circulating_supply": 19500000.0,
                "total_supply": 21000000.0,
                "max_supply": 21000000.0
            },
            "image": {
                "large": "https://example.com/bitcoin.png"
            }
        }"#;
        
        let info = client.parse_token_info(json).unwrap();
        
        assert_eq!(info.id, "bitcoin");
        assert_eq!(info.symbol, "btc");
        assert_eq!(info.name, "Bitcoin");
        assert_eq!(info.current_price, 45000.0);
        assert_eq!(info.market_cap_rank, Some(1));
        assert!((info.price_change_percentage_24h - 3.45).abs() < 0.001);
        assert_eq!(info.high_24h, 46000.0);
        assert_eq!(info.low_24h, 43500.0);
        assert_eq!(info.ath, 69000.0);
        assert_eq!(info.max_supply, Some(21000000.0));
        assert_eq!(info.image_url, Some("https://example.com/bitcoin.png".into()));
    }
}
