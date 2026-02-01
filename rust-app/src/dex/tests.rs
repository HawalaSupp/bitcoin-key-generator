//! DEX Module Tests

use super::*;
use crate::types::Chain;

#[test]
fn test_full_swap_flow() {
    let mut aggregator = DEXAggregator::new(None, None);
    
    // 1. Create swap request
    let request = SwapQuoteRequest {
        chain: Chain::Ethereum,
        from_token: SwapQuoteRequest::NATIVE_ETH.to_string(),
        to_token: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48".to_string(), // USDC
        amount: "1000000000000000000".to_string(), // 1 ETH
        slippage: 0.5,
        from_address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
        provider: None,
        deadline_seconds: None,
        referrer: None,
        gas_price_gwei: Some(30.0),
    };

    // 2. Get all quotes
    let quotes = aggregator.get_all_quotes(&request).unwrap();
    assert!(quotes.quotes.len() >= 2, "Should have quotes from 1inch and 0x");

    // 3. Get best quote
    let best = aggregator.get_best_quote(&request).unwrap();
    assert!(!best.to_amount.is_empty());
    assert!(best.tx.is_some(), "Best quote should include tx data");

    // 4. Compare quotes
    let comparison = aggregator.compare_quotes(&request).unwrap();
    assert!(comparison.spread_percent >= 0.0);
    assert!(!comparison.recommendation.is_empty());

    // 5. Verify quote details
    assert_eq!(best.from_token_symbol, "ETH");
    assert_eq!(best.to_token_symbol, "USDC");
    assert_eq!(best.from_token_decimals, 18);
    assert_eq!(best.to_token_decimals, 6);
}

#[test]
fn test_token_approval_flow() {
    let aggregator = DEXAggregator::new(None, None);
    
    // Check if approval is needed for USDC -> ETH swap
    let approval = aggregator.check_approval(
        Chain::Ethereum,
        "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", // USDC
        "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2",
        DEXProvider::OneInch,
    ).unwrap();

    assert!(approval.needs_approval);
    assert!(!approval.spender.is_empty());

    // Get approval tx
    let approval_tx = aggregator.get_approval_tx(
        Chain::Ethereum,
        "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
        DEXProvider::OneInch,
        None, // Unlimited approval
    ).unwrap();

    assert!(approval_tx.data.starts_with("0x095ea7b3")); // approve selector
    assert_eq!(approval_tx.value, "0");
}

#[test]
fn test_multi_chain_support() {
    let mut aggregator = DEXAggregator::new(None, None);

    // Test on multiple chains
    let chains = vec![
        (Chain::Ethereum, "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"), // USDC Ethereum
        (Chain::Polygon, "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174"),   // USDC Polygon
        (Chain::Arbitrum, "0xaf88d065e77c8cC2239327C5EDb3A432268e5831"),  // USDC Arbitrum
    ];

    for (chain, usdc_address) in chains {
        let request = SwapQuoteRequest {
            chain,
            from_token: SwapQuoteRequest::NATIVE_ETH.to_string(),
            to_token: usdc_address.to_string(),
            amount: "1000000000000000000".to_string(),
            slippage: 0.5,
            from_address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
            provider: None,
            deadline_seconds: None,
            referrer: None,
            gas_price_gwei: None,
        };

        let result = aggregator.get_all_quotes(&request);
        assert!(result.is_ok(), "Failed to get quotes for {:?}", chain);
        
        let quotes = result.unwrap();
        assert!(!quotes.quotes.is_empty(), "No quotes for {:?}", chain);
    }
}

#[test]
fn test_slippage_validation() {
    let mut aggregator = DEXAggregator::new(None, None);
    
    let request = SwapQuoteRequest {
        chain: Chain::Ethereum,
        from_token: SwapQuoteRequest::NATIVE_ETH.to_string(),
        to_token: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48".to_string(),
        amount: "1000000000000000000".to_string(),
        slippage: 100.0, // Invalid: > 50%
        from_address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
        provider: None,
        deadline_seconds: None,
        referrer: None,
        gas_price_gwei: None,
    };

    // Should still get quotes (individual providers may reject)
    // The aggregator will return whatever it can get
    let _result = aggregator.get_all_quotes(&request);
    // Just verify it doesn't panic
}

#[test]
fn test_quote_expiry() {
    let quote = SwapQuote {
        provider: DEXProvider::OneInch,
        chain: Chain::Ethereum,
        from_token: "ETH".to_string(),
        from_token_symbol: "ETH".to_string(),
        from_token_decimals: 18,
        to_token: "USDC".to_string(),
        to_token_symbol: "USDC".to_string(),
        to_token_decimals: 6,
        from_amount: "1000000000000000000".to_string(),
        to_amount: "3000000000".to_string(),
        to_amount_min: "2970000000".to_string(),
        estimated_gas: "150000".to_string(),
        gas_price_gwei: 30.0,
        gas_cost_usd: Some(5.0),
        price_impact: -0.1,
        routes: vec![],
        expires_at: 0, // Expired (Unix timestamp 0)
        tx: None,
    };

    assert!(quote.is_expired());

    // Future expiry
    let future_quote = SwapQuote {
        expires_at: 9999999999,
        ..quote
    };
    assert!(!future_quote.is_expired());
}

#[test]
fn test_aggregated_quotes_sorting() {
    let quotes = AggregatedQuotes {
        quotes: vec![
            SwapQuote {
                provider: DEXProvider::OneInch,
                to_amount: "3000".to_string(),
                gas_cost_usd: Some(5.0),
                ..make_test_quote()
            },
            SwapQuote {
                provider: DEXProvider::ZeroX,
                to_amount: "3100".to_string(), // Higher output
                gas_cost_usd: Some(7.0),       // But higher gas
                ..make_test_quote()
            },
        ],
        best_quote: None,
        request: make_test_request(),
        fetched_at: 0,
    };

    // Sort by output - 0x should be first (higher output)
    let by_output = quotes.sorted_by_output();
    assert_eq!(by_output[0].provider, DEXProvider::ZeroX);

    // Sort by gas - 1inch should be first (lower gas)
    let by_gas = quotes.sorted_by_gas();
    assert_eq!(by_gas[0].provider, DEXProvider::OneInch);
}

// Helper functions for tests
fn make_test_quote() -> SwapQuote {
    SwapQuote {
        provider: DEXProvider::OneInch,
        chain: Chain::Ethereum,
        from_token: "ETH".to_string(),
        from_token_symbol: "ETH".to_string(),
        from_token_decimals: 18,
        to_token: "USDC".to_string(),
        to_token_symbol: "USDC".to_string(),
        to_token_decimals: 6,
        from_amount: "1000000000000000000".to_string(),
        to_amount: "3000000000".to_string(),
        to_amount_min: "2970000000".to_string(),
        estimated_gas: "150000".to_string(),
        gas_price_gwei: 30.0,
        gas_cost_usd: Some(5.0),
        price_impact: -0.1,
        routes: vec![],
        expires_at: 9999999999,
        tx: None,
    }
}

fn make_test_request() -> SwapQuoteRequest {
    SwapQuoteRequest {
        chain: Chain::Ethereum,
        from_token: SwapQuoteRequest::NATIVE_ETH.to_string(),
        to_token: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48".to_string(),
        amount: "1000000000000000000".to_string(),
        slippage: 0.5,
        from_address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
        provider: None,
        deadline_seconds: None,
        referrer: None,
        gas_price_gwei: None,
    }
}
