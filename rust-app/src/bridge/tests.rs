//! Bridge module tests

use super::*;
use crate::types::Chain;

#[test]
fn test_full_bridge_flow() {
    // Test end-to-end bridge flow: quote → compare → select → (track)
    let mut aggregator = BridgeAggregator::new(None, None);
    
    // Create bridge request
    let request = BridgeQuoteRequest {
        source_chain: Chain::Ethereum,
        destination_chain: Chain::Arbitrum,
        token: "USDC".to_string(),
        amount: "1000000000".to_string(), // 1000 USDC (6 decimals)
        sender: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
        recipient: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
        slippage: 0.5,
        provider: None,
    };

    // Get all quotes
    let quotes = aggregator.get_all_quotes(&request).unwrap();
    assert!(!quotes.quotes.is_empty(), "Should have at least one quote");
    
    // Verify best quote
    let best = quotes.best_quote.as_ref().unwrap();
    assert!(best.amount_out.parse::<u128>().unwrap() > 0);
    assert!(best.is_valid());
    
    // Compare quotes
    let comparison = aggregator.compare_quotes(&request).unwrap();
    assert!(comparison.quotes_count > 0);
    assert!(!comparison.recommendation.is_empty());
}

#[test]
fn test_multi_chain_bridge_support() {
    // Test various chain combinations
    let test_routes = vec![
        (Chain::Ethereum, Chain::Arbitrum),
        (Chain::Ethereum, Chain::Optimism),
        (Chain::Ethereum, Chain::Polygon),
        (Chain::Ethereum, Chain::Base),
        (Chain::Arbitrum, Chain::Optimism),
        (Chain::Polygon, Chain::Avalanche),
    ];

    for (source, dest) in test_routes {
        let providers = BridgeAggregator::get_providers_for_route(source, dest);
        assert!(
            !providers.is_empty(),
            "Route {:?} → {:?} should have at least one provider",
            source, dest
        );
    }
}

#[test]
fn test_native_token_bridge() {
    let mut aggregator = BridgeAggregator::new(None, None);
    
    let request = BridgeQuoteRequest {
        source_chain: Chain::Ethereum,
        destination_chain: Chain::Arbitrum,
        token: BridgeQuoteRequest::NATIVE.to_string(),
        amount: "1000000000000000000".to_string(), // 1 ETH
        sender: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
        recipient: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
        slippage: 1.0,
        provider: None,
    };

    assert!(request.is_native_token());

    let quotes = aggregator.get_all_quotes(&request).unwrap();
    assert!(!quotes.quotes.is_empty());
}

#[test]
fn test_stablecoin_bridge_comparison() {
    let mut aggregator = BridgeAggregator::new(None, None);
    
    // USDC should be supported by all major bridges
    let request = BridgeQuoteRequest {
        source_chain: Chain::Ethereum,
        destination_chain: Chain::Polygon,
        token: "USDC".to_string(),
        amount: "10000000000".to_string(), // 10,000 USDC
        sender: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
        recipient: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
        slippage: 0.5,
        provider: None,
    };

    let quotes = aggregator.get_all_quotes(&request).unwrap();
    
    // Should have multiple quotes for comparison
    assert!(quotes.quotes.len() >= 2, "USDC should be supported by multiple bridges");
    
    // Stargate should definitely be included for stablecoin
    let has_stargate = quotes.quotes.iter().any(|q| q.provider == BridgeProvider::Stargate);
    assert!(has_stargate, "Stargate should be available for USDC bridging");
}

#[test]
fn test_bridge_fee_calculation() {
    let mut aggregator = BridgeAggregator::new(None, None);
    
    let request = BridgeQuoteRequest {
        source_chain: Chain::Ethereum,
        destination_chain: Chain::Arbitrum,
        token: "USDC".to_string(),
        amount: "1000000000".to_string(), // 1000 USDC
        sender: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
        recipient: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
        slippage: 0.5,
        provider: None,
    };

    let quotes = aggregator.get_all_quotes(&request).unwrap();
    
    for quote in &quotes.quotes {
        // Output should be less than or equal to input
        let amount_in: u128 = quote.amount_in.parse().unwrap();
        let amount_out: u128 = quote.amount_out.parse().unwrap();
        assert!(amount_out <= amount_in, "Output cannot exceed input");
        
        // Fees should be reasonable (< 5% for any bridge)
        let fee_percent = ((amount_in - amount_out) as f64 / amount_in as f64) * 100.0;
        assert!(fee_percent < 5.0, "Fee {} is too high for {:?}", fee_percent, quote.provider);
        
        // Should have estimated time
        assert!(quote.estimated_time_minutes > 0);
        
        // Should have transaction data
        assert!(quote.transaction.is_some());
    }
}

#[test]
fn test_slippage_handling() {
    let aggregator = BridgeAggregator::new(None, None);
    
    // Test with different slippage values
    for slippage in &[0.1, 0.5, 1.0, 3.0] {
        let request = BridgeQuoteRequest {
            source_chain: Chain::Ethereum,
            destination_chain: Chain::Arbitrum,
            token: "USDC".to_string(),
            amount: "1000000000".to_string(),
            sender: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
            recipient: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
            slippage: *slippage,
            provider: Some(BridgeProvider::Wormhole),
        };

        let quote = aggregator.get_quote_from_provider(&request, BridgeProvider::Wormhole).unwrap();
        
        let amount_out: f64 = quote.amount_out.parse().unwrap();
        let amount_out_min: f64 = quote.amount_out_min.parse().unwrap();
        
        // Min should account for slippage
        let expected_min = amount_out * (1.0 - slippage / 100.0);
        let tolerance = amount_out * 0.001; // 0.1% tolerance for rounding
        
        assert!(
            (amount_out_min - expected_min).abs() < tolerance,
            "Slippage {} not correctly applied", slippage
        );
    }
}

#[test]
fn test_quote_expiration() {
    let aggregator = BridgeAggregator::new(None, None);
    
    let request = BridgeQuoteRequest {
        source_chain: Chain::Ethereum,
        destination_chain: Chain::Arbitrum,
        token: "USDC".to_string(),
        amount: "1000000000".to_string(),
        sender: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
        recipient: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
        slippage: 0.5,
        provider: Some(BridgeProvider::Wormhole),
    };

    let quote = aggregator.get_quote_from_provider(&request, BridgeProvider::Wormhole).unwrap();
    
    // Quote should be valid initially
    assert!(quote.is_valid());
    
    // Expiry should be in the future
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    assert!(quote.expires_at > now);
}

#[test]
fn test_bridge_status_tracking() {
    let aggregator = BridgeAggregator::new(None, None);
    
    // Track a mock transfer
    let transfer = aggregator.track_transfer(
        "0x1234567890abcdef",
        Chain::Ethereum,
        BridgeProvider::Wormhole,
    ).unwrap();

    assert_eq!(transfer.provider, BridgeProvider::Wormhole);
    assert_eq!(transfer.status, BridgeStatus::InTransit);
    assert!(!transfer.is_complete());
    assert!(transfer.tracking_data.is_some());
}

#[test]
fn test_unsupported_route() {
    let mut aggregator = BridgeAggregator::new(None, None);
    
    // Bitcoin to Ethereum should have no/limited providers
    let request = BridgeQuoteRequest {
        source_chain: Chain::Bitcoin,
        destination_chain: Chain::Ethereum,
        token: "BTC".to_string(),
        amount: "100000000".to_string(), // 1 BTC
        sender: "bc1qtest...".to_string(),
        recipient: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
        slippage: 1.0,
        provider: None,
    };

    let result = aggregator.get_all_quotes(&request);
    // Either no quotes or error
    assert!(result.is_err() || result.unwrap().quotes.is_empty());
}

#[test]
fn test_aggregated_quotes_sorting() {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();

    let make_quote = |provider, amount_out: &str, fee: f64, time: u32| BridgeQuote {
        id: format!("{:?}", provider),
        provider,
        source_chain: Chain::Ethereum,
        destination_chain: Chain::Arbitrum,
        token: "USDC".to_string(),
        token_symbol: "USDC".to_string(),
        amount_in: "1000000000".to_string(),
        amount_out: amount_out.to_string(),
        amount_out_min: amount_out.to_string(),
        bridge_fee: "0".to_string(),
        bridge_fee_usd: Some(fee),
        source_gas_usd: Some(0.0),
        destination_gas_usd: Some(0.0),
        total_fee_usd: Some(fee),
        estimated_time_minutes: time,
        exchange_rate: 1.0,
        price_impact: None,
        expires_at: now + 300,
        transaction: None,
    };

    let quotes = vec![
        make_quote(BridgeProvider::Wormhole, "995000000", 5.0, 15),
        make_quote(BridgeProvider::Stargate, "998000000", 2.0, 2),
        make_quote(BridgeProvider::LayerZero, "997000000", 3.0, 5),
    ];

    let agg = AggregatedBridgeQuotes {
        quotes: quotes.clone(),
        best_quote: Some(quotes[1].clone()),
        cheapest_quote: Some(quotes[1].clone()),
        fastest_quote: Some(quotes[1].clone()),
        fetched_at: now,
    };

    // Test sorting by output (Stargate should be first)
    let by_output = agg.sorted_by_output();
    assert_eq!(by_output[0].provider, BridgeProvider::Stargate);
    assert_eq!(by_output[2].provider, BridgeProvider::Wormhole);

    // Test sorting by fee (Stargate should be first)
    let by_fee = agg.sorted_by_fee();
    assert_eq!(by_fee[0].provider, BridgeProvider::Stargate);

    // Test sorting by time (Stargate should be first)
    let by_time = agg.sorted_by_time();
    assert_eq!(by_time[0].provider, BridgeProvider::Stargate);
}
