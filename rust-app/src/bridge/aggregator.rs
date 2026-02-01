//! Bridge aggregator for comparing quotes across providers

use std::collections::HashMap;
use crate::error::{HawalaError, HawalaResult};
use crate::types::Chain;
use super::types::*;
use super::wormhole::WormholeClient;
use super::layerzero::LayerZeroClient;
use super::stargate::StargateClient;

/// Bridge aggregator for multi-provider quote comparison
pub struct BridgeAggregator {
    /// Wormhole client
    wormhole: WormholeClient,
    /// LayerZero client
    layerzero: LayerZeroClient,
    /// Stargate client
    stargate: StargateClient,
    /// Quote cache
    quote_cache: HashMap<String, (u64, AggregatedBridgeQuotes)>,
    /// Cache expiration in seconds
    cache_ttl: u64,
}

impl BridgeAggregator {
    /// Create new bridge aggregator
    pub fn new(
        wormhole_api_key: Option<String>,
        layerzero_api_key: Option<String>,
    ) -> Self {
        Self {
            wormhole: WormholeClient::new(wormhole_api_key),
            layerzero: LayerZeroClient::new(layerzero_api_key),
            stargate: StargateClient::new(),
            quote_cache: HashMap::new(),
            cache_ttl: 30,
        }
    }

    /// Get available providers for a route
    pub fn get_providers_for_route(source: Chain, destination: Chain) -> Vec<BridgeProvider> {
        let mut providers = Vec::new();

        if WormholeClient::is_route_supported(source, destination) {
            providers.push(BridgeProvider::Wormhole);
        }
        if LayerZeroClient::is_route_supported(source, destination) {
            providers.push(BridgeProvider::LayerZero);
        }
        // Stargate needs token info, so we include it if chains are supported
        if super::stargate::StargateChainId::from_chain(source).is_some() &&
           super::stargate::StargateChainId::from_chain(destination).is_some() {
            providers.push(BridgeProvider::Stargate);
        }

        providers
    }

    /// Get quotes from all available providers
    pub fn get_all_quotes(&mut self, request: &BridgeQuoteRequest) -> HawalaResult<AggregatedBridgeQuotes> {
        let cache_key = self.make_cache_key(request);

        // Check cache
        if let Some((timestamp, cached)) = self.quote_cache.get(&cache_key) {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs();
            if now - timestamp < self.cache_ttl {
                return Ok(cached.clone());
            }
        }

        let mut quotes = Vec::new();
        let mut errors = Vec::new();

        // Get Wormhole quote
        if WormholeClient::is_route_supported(request.source_chain, request.destination_chain) {
            match self.wormhole.get_quote(request) {
                Ok(quote) => quotes.push(quote),
                Err(e) => errors.push(format!("Wormhole: {}", e)),
            }
        }

        // Get LayerZero quote
        if LayerZeroClient::is_route_supported(request.source_chain, request.destination_chain) {
            match self.layerzero.get_quote(request) {
                Ok(quote) => quotes.push(quote),
                Err(e) => errors.push(format!("LayerZero: {}", e)),
            }
        }

        // Get Stargate quote (token-dependent)
        let token_symbol = self.get_token_symbol(&request.token);
        if StargateClient::is_route_supported(request.source_chain, request.destination_chain, &token_symbol) {
            match self.stargate.get_quote(request) {
                Ok(quote) => quotes.push(quote),
                Err(e) => errors.push(format!("Stargate: {}", e)),
            }
        }

        if quotes.is_empty() {
            return Err(HawalaError::invalid_input(format!(
                "No bridge quotes available for route {:?} → {:?}. Errors: {:?}",
                request.source_chain, request.destination_chain, errors
            )));
        }

        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        // Find best, cheapest, and fastest quotes
        let best_quote = quotes.iter()
            .max_by(|a, b| {
                let a_out: f64 = a.amount_out.parse().unwrap_or(0.0);
                let b_out: f64 = b.amount_out.parse().unwrap_or(0.0);
                a_out.partial_cmp(&b_out).unwrap_or(std::cmp::Ordering::Equal)
            })
            .cloned();

        let cheapest_quote = quotes.iter()
            .min_by(|a, b| {
                let a_fee = a.total_fee_usd.unwrap_or(f64::MAX);
                let b_fee = b.total_fee_usd.unwrap_or(f64::MAX);
                a_fee.partial_cmp(&b_fee).unwrap_or(std::cmp::Ordering::Equal)
            })
            .cloned();

        let fastest_quote = quotes.iter()
            .min_by_key(|q| q.estimated_time_minutes)
            .cloned();

        let aggregated = AggregatedBridgeQuotes {
            quotes,
            best_quote,
            cheapest_quote,
            fastest_quote,
            fetched_at: now,
        };

        // Cache result
        self.quote_cache.insert(cache_key, (now, aggregated.clone()));

        Ok(aggregated)
    }

    /// Get the best quote (highest output amount)
    pub fn get_best_quote(&mut self, request: &BridgeQuoteRequest) -> HawalaResult<BridgeQuote> {
        let quotes = self.get_all_quotes(request)?;
        quotes.best_quote.ok_or_else(|| 
            HawalaError::invalid_input("No bridge quotes available".to_string())
        )
    }

    /// Get the cheapest quote (lowest total fees)
    pub fn get_cheapest_quote(&mut self, request: &BridgeQuoteRequest) -> HawalaResult<BridgeQuote> {
        let quotes = self.get_all_quotes(request)?;
        quotes.cheapest_quote.ok_or_else(||
            HawalaError::invalid_input("No bridge quotes available".to_string())
        )
    }

    /// Get the fastest quote (shortest transfer time)
    pub fn get_fastest_quote(&mut self, request: &BridgeQuoteRequest) -> HawalaResult<BridgeQuote> {
        let quotes = self.get_all_quotes(request)?;
        quotes.fastest_quote.ok_or_else(||
            HawalaError::invalid_input("No bridge quotes available".to_string())
        )
    }

    /// Get quote from a specific provider
    pub fn get_quote_from_provider(
        &self,
        request: &BridgeQuoteRequest,
        provider: BridgeProvider,
    ) -> HawalaResult<BridgeQuote> {
        match provider {
            BridgeProvider::Wormhole => self.wormhole.get_quote(request),
            BridgeProvider::LayerZero => self.layerzero.get_quote(request),
            BridgeProvider::Stargate => self.stargate.get_quote(request),
            _ => Err(HawalaError::invalid_input(format!(
                "Provider {:?} not yet implemented", provider
            ))),
        }
    }

    /// Track a bridge transfer
    pub fn track_transfer(
        &self,
        tx_hash: &str,
        source_chain: Chain,
        provider: BridgeProvider,
    ) -> HawalaResult<BridgeTransfer> {
        match provider {
            BridgeProvider::Wormhole => self.wormhole.track_vaa(tx_hash, source_chain),
            BridgeProvider::LayerZero => self.layerzero.track_message(tx_hash, source_chain),
            BridgeProvider::Stargate => self.stargate.track_transfer(tx_hash, source_chain),
            _ => Err(HawalaError::invalid_input(format!(
                "Transfer tracking not supported for {:?}", provider
            ))),
        }
    }

    /// Get comparison analysis for quotes
    pub fn compare_quotes(&mut self, request: &BridgeQuoteRequest) -> HawalaResult<BridgeComparison> {
        let quotes = self.get_all_quotes(request)?;

        if quotes.quotes.is_empty() {
            return Err(HawalaError::invalid_input("No quotes to compare".to_string()));
        }

        let by_output = quotes.sorted_by_output();
        let by_fee = quotes.sorted_by_fee();
        let by_time = quotes.sorted_by_time();

        let best = by_output.first().unwrap();
        let worst = by_output.last().unwrap();
        let cheapest = by_fee.first().unwrap();
        let fastest = by_time.first().unwrap();

        let best_amount: f64 = best.amount_out.parse().unwrap_or(0.0);
        let worst_amount: f64 = worst.amount_out.parse().unwrap_or(0.0);
        
        let output_spread = if worst_amount > 0.0 {
            ((best_amount - worst_amount) / worst_amount) * 100.0
        } else {
            0.0
        };

        let fee_spread = if let (Some(lowest), Some(highest)) = (
            by_fee.first().and_then(|q| q.total_fee_usd),
            by_fee.last().and_then(|q| q.total_fee_usd),
        ) {
            highest - lowest
        } else {
            0.0
        };

        let time_spread = by_time.last().unwrap().estimated_time_minutes - 
                         by_time.first().unwrap().estimated_time_minutes;

        let recommendation = self.generate_recommendation(
            &quotes,
            output_spread,
            fee_spread,
            time_spread,
        );

        Ok(BridgeComparison {
            best_output_provider: best.provider,
            best_output_amount: best.amount_out.clone(),
            cheapest_provider: cheapest.provider,
            cheapest_fee_usd: cheapest.total_fee_usd,
            fastest_provider: fastest.provider,
            fastest_time_minutes: fastest.estimated_time_minutes,
            output_spread_percent: output_spread,
            fee_spread_usd: fee_spread,
            time_spread_minutes: time_spread,
            recommendation,
            quotes_count: quotes.quotes.len(),
        })
    }

    /// Clear quote cache
    pub fn clear_cache(&mut self) {
        self.quote_cache.clear();
    }

    // Private methods

    fn make_cache_key(&self, request: &BridgeQuoteRequest) -> String {
        format!(
            "{}:{}:{}:{}:{}",
            format!("{:?}", request.source_chain),
            format!("{:?}", request.destination_chain),
            request.token.to_lowercase(),
            request.amount,
            (request.slippage * 100.0) as u32
        )
    }

    fn get_token_symbol(&self, token: &str) -> String {
        if token.eq_ignore_ascii_case(BridgeQuoteRequest::NATIVE) {
            "ETH".to_string()
        } else if token.len() <= 10 {
            token.to_uppercase()
        } else {
            "TOKEN".to_string()
        }
    }

    fn generate_recommendation(
        &self,
        quotes: &AggregatedBridgeQuotes,
        output_spread: f64,
        fee_spread: f64,
        time_spread: u32,
    ) -> String {
        let best = quotes.best_quote.as_ref();
        let cheapest = quotes.cheapest_quote.as_ref();
        let fastest = quotes.fastest_quote.as_ref();

        // If all point to same provider, that's the clear winner
        if let (Some(b), Some(c), Some(f)) = (best, cheapest, fastest) {
            if b.provider == c.provider && c.provider == f.provider {
                return format!(
                    "{} offers the best rate, lowest fees, and fastest transfer",
                    b.provider.display_name()
                );
            }
        }

        // Prioritize based on spreads
        if output_spread > 5.0 {
            if let Some(b) = best {
                return format!(
                    "Use {} for {:.1}% more tokens received",
                    b.provider.display_name(),
                    output_spread
                );
            }
        }

        if fee_spread > 5.0 {
            if let Some(c) = cheapest {
                return format!(
                    "Use {} to save ${:.2} in fees",
                    c.provider.display_name(),
                    fee_spread
                );
            }
        }

        if time_spread > 10 {
            if let Some(f) = fastest {
                return format!(
                    "Use {} for {} minute faster transfer",
                    f.provider.display_name(),
                    time_spread
                );
            }
        }

        // Default recommendation
        if let Some(b) = best {
            format!("{} offers the best overall value", b.provider.display_name())
        } else {
            "Compare all quotes to find the best option".to_string()
        }
    }
}

impl Default for BridgeAggregator {
    fn default() -> Self {
        Self::new(None, None)
    }
}

/// Bridge comparison result
#[derive(Debug, Clone)]
pub struct BridgeComparison {
    /// Provider with best output amount
    pub best_output_provider: BridgeProvider,
    /// Best output amount
    pub best_output_amount: String,
    /// Provider with lowest fees
    pub cheapest_provider: BridgeProvider,
    /// Lowest total fee in USD
    pub cheapest_fee_usd: Option<f64>,
    /// Provider with fastest transfer
    pub fastest_provider: BridgeProvider,
    /// Fastest transfer time in minutes
    pub fastest_time_minutes: u32,
    /// Output amount spread as percentage
    pub output_spread_percent: f64,
    /// Fee spread in USD
    pub fee_spread_usd: f64,
    /// Time spread in minutes
    pub time_spread_minutes: u32,
    /// Recommendation text
    pub recommendation: String,
    /// Number of quotes compared
    pub quotes_count: usize,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_providers_for_route() {
        let providers = BridgeAggregator::get_providers_for_route(Chain::Ethereum, Chain::Arbitrum);
        assert!(!providers.is_empty());
        assert!(providers.contains(&BridgeProvider::Wormhole));
        assert!(providers.contains(&BridgeProvider::LayerZero));
        assert!(providers.contains(&BridgeProvider::Stargate));

        // Bitcoin routes should only have Wormhole (if at all)
        let btc_providers = BridgeAggregator::get_providers_for_route(Chain::Bitcoin, Chain::Ethereum);
        assert!(btc_providers.is_empty() || btc_providers.contains(&BridgeProvider::Wormhole));
    }

    #[test]
    fn test_get_all_quotes() {
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
        assert!(!quotes.quotes.is_empty());
        assert!(quotes.best_quote.is_some());
        assert!(quotes.cheapest_quote.is_some());
        assert!(quotes.fastest_quote.is_some());
    }

    #[test]
    fn test_compare_quotes() {
        let mut aggregator = BridgeAggregator::new(None, None);
        let request = BridgeQuoteRequest {
            source_chain: Chain::Ethereum,
            destination_chain: Chain::Polygon,
            token: BridgeQuoteRequest::NATIVE.to_string(),
            amount: "1000000000000000000".to_string(), // 1 ETH
            sender: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
            recipient: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
            slippage: 1.0,
            provider: None,
        };

        let comparison = aggregator.compare_quotes(&request).unwrap();
        assert!(comparison.quotes_count > 0);
        assert!(!comparison.recommendation.is_empty());
    }

    #[test]
    fn test_cache_behavior() {
        let mut aggregator = BridgeAggregator::new(None, None);
        let request = BridgeQuoteRequest {
            source_chain: Chain::Ethereum,
            destination_chain: Chain::Arbitrum,
            token: "USDC".to_string(),
            amount: "1000000000".to_string(),
            sender: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
            recipient: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
            slippage: 0.5,
            provider: None,
        };

        // First call
        let quotes1 = aggregator.get_all_quotes(&request).unwrap();
        let ts1 = quotes1.fetched_at;

        // Second call - should use cache
        let quotes2 = aggregator.get_all_quotes(&request).unwrap();
        let ts2 = quotes2.fetched_at;

        assert_eq!(ts1, ts2);
    }

    #[test]
    fn test_specific_provider_quote() {
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
        assert_eq!(quote.provider, BridgeProvider::Wormhole);

        let quote = aggregator.get_quote_from_provider(&request, BridgeProvider::Stargate).unwrap();
        assert_eq!(quote.provider, BridgeProvider::Stargate);
    }
}
