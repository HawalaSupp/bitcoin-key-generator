//! DEX Aggregator
//!
//! Unified interface for fetching and comparing quotes from multiple DEX providers.

use std::collections::HashMap;
use crate::types::Chain;
use crate::error::{HawalaError, HawalaResult};
use super::types::*;
use super::oneinch::OneInchClient;
use super::zerox::ZeroXClient;

/// DEX Aggregator - fetches and compares quotes from multiple sources
pub struct DEXAggregator {
    oneinch: OneInchClient,
    zerox: ZeroXClient,
    /// Cache of recent quotes (key: request hash, value: (timestamp, quotes))
    quote_cache: HashMap<String, (u64, AggregatedQuotes)>,
    /// Cache TTL in seconds
    cache_ttl: u64,
}

impl DEXAggregator {
    /// Create a new DEX aggregator
    pub fn new(oneinch_api_key: Option<String>, zerox_api_key: Option<String>) -> Self {
        Self {
            oneinch: OneInchClient::new(oneinch_api_key),
            zerox: ZeroXClient::new(zerox_api_key),
            quote_cache: HashMap::new(),
            cache_ttl: 30, // 30 second cache
        }
    }

    /// Get the best available providers for a chain
    pub fn get_providers_for_chain(chain: Chain) -> Vec<DEXProvider> {
        let mut providers = Vec::new();
        
        if OneInchClient::is_chain_supported(chain) {
            providers.push(DEXProvider::OneInch);
        }
        if ZeroXClient::is_chain_supported(chain) {
            providers.push(DEXProvider::ZeroX);
        }
        
        // Add native providers
        match chain {
            Chain::Bitcoin | Chain::Ethereum | Chain::Bnb | 
            Chain::Avalanche | Chain::Cosmos | Chain::Litecoin | 
            Chain::BitcoinCash | Chain::Dogecoin => {
                providers.push(DEXProvider::THORChain);
            }
            _ => {}
        }
        
        match chain {
            Chain::Osmosis | Chain::Cosmos => {
                providers.push(DEXProvider::Osmosis);
            }
            _ => {}
        }

        providers
    }

    /// Get quotes from all available providers
    pub fn get_all_quotes(&mut self, request: &SwapQuoteRequest) -> HawalaResult<AggregatedQuotes> {
        // Check cache first
        let cache_key = self.make_cache_key(request);
        if let Some(cached) = self.get_cached(&cache_key) {
            return Ok(cached);
        }

        let mut quotes = Vec::new();
        let mut errors = Vec::new();

        // Fetch from 1inch
        if OneInchClient::is_chain_supported(request.chain) {
            match self.oneinch.get_swap(request) {
                Ok(quote) => quotes.push(quote),
                Err(e) => errors.push(format!("1inch: {}", e)),
            }
        }

        // Fetch from 0x
        if ZeroXClient::is_chain_supported(request.chain) {
            match self.zerox.get_quote(request) {
                Ok(quote) => quotes.push(quote),
                Err(e) => errors.push(format!("0x: {}", e)),
            }
        }

        // If no quotes and we have errors, return an error
        if quotes.is_empty() && !errors.is_empty() {
            return Err(HawalaError::invalid_input(
                format!("Failed to get quotes: {}", errors.join("; "))
            ));
        }

        // Find best quote (highest output)
        let best_quote = quotes.iter()
            .max_by(|a, b| {
                let a_amount = a.to_amount.parse::<u128>().unwrap_or(0);
                let b_amount = b.to_amount.parse::<u128>().unwrap_or(0);
                a_amount.cmp(&b_amount)
            })
            .cloned();

        let fetched_at = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        let result = AggregatedQuotes {
            quotes,
            best_quote,
            request: request.clone(),
            fetched_at,
        };

        // Cache the result
        self.set_cached(cache_key, result.clone());

        Ok(result)
    }

    /// Get quote from a specific provider
    pub fn get_quote_from_provider(&self, request: &SwapQuoteRequest, provider: DEXProvider) -> HawalaResult<SwapQuote> {
        match provider {
            DEXProvider::OneInch => self.oneinch.get_swap(request),
            DEXProvider::ZeroX => self.zerox.get_quote(request),
            DEXProvider::THORChain => {
                // THORChain uses its own quote format - for now just use 1inch
                Err(HawalaError::invalid_input("THORChain quotes should use thorchain_swap module directly".to_string()))
            }
            DEXProvider::Osmosis => {
                // Osmosis uses its own quote format - for now just use existing swap module
                Err(HawalaError::invalid_input("Osmosis quotes should use swap module directly".to_string()))
            }
            _ => Err(HawalaError::invalid_input(
                format!("Provider {:?} not yet implemented", provider)
            )),
        }
    }

    /// Get the best quote across all providers
    pub fn get_best_quote(&mut self, request: &SwapQuoteRequest) -> HawalaResult<SwapQuote> {
        let all_quotes = self.get_all_quotes(request)?;
        all_quotes.best_quote.ok_or_else(|| 
            HawalaError::invalid_input("No quotes available for this swap".to_string())
        )
    }

    /// Compare quotes and return analysis
    pub fn compare_quotes(&mut self, request: &SwapQuoteRequest) -> HawalaResult<QuoteComparison> {
        let all_quotes = self.get_all_quotes(request)?;
        
        if all_quotes.quotes.is_empty() {
            return Err(HawalaError::invalid_input("No quotes available".to_string()));
        }

        let sorted = all_quotes.sorted_by_output();
        let best = sorted.first().unwrap();
        let worst = sorted.last().unwrap();

        let best_amount: f64 = best.to_amount.parse().unwrap_or(0.0);
        let worst_amount: f64 = worst.to_amount.parse().unwrap_or(0.0);
        
        let spread_percent = if worst_amount > 0.0 {
            ((best_amount - worst_amount) / worst_amount) * 100.0
        } else {
            0.0
        };

        Ok(QuoteComparison {
            best_provider: best.provider,
            best_output: best.to_amount.clone(),
            worst_provider: worst.provider,
            worst_output: worst.to_amount.clone(),
            spread_percent,
            gas_savings_usd: self.calculate_gas_savings(&all_quotes),
            recommendation: self.get_recommendation(&all_quotes),
        })
    }

    /// Check if token needs approval for a specific provider
    pub fn check_approval(&self, chain: Chain, token: &str, wallet: &str, provider: DEXProvider) -> HawalaResult<TokenApproval> {
        match provider {
            DEXProvider::OneInch => self.oneinch.check_approval(chain, token, wallet),
            DEXProvider::ZeroX => self.zerox.check_allowance(chain, token, wallet),
            _ => Err(HawalaError::invalid_input(
                format!("Approval check not supported for {:?}", provider)
            )),
        }
    }

    /// Get approval transaction for a token
    pub fn get_approval_tx(&self, chain: Chain, token: &str, provider: DEXProvider, amount: Option<&str>) -> HawalaResult<SwapTransaction> {
        match provider {
            DEXProvider::OneInch => self.oneinch.get_approval_tx(chain, token, amount),
            DEXProvider::ZeroX => {
                // 0x uses the same approval pattern
                self.oneinch.get_approval_tx(chain, token, amount)
            }
            _ => Err(HawalaError::invalid_input(
                format!("Approval tx not supported for {:?}", provider)
            )),
        }
    }

    // Private methods

    fn make_cache_key(&self, request: &SwapQuoteRequest) -> String {
        format!(
            "{}:{}:{}:{}:{}",
            request.chain.chain_id().unwrap_or(1),
            request.from_token.to_lowercase(),
            request.to_token.to_lowercase(),
            request.amount,
            (request.slippage * 100.0) as u32
        )
    }

    fn get_cached(&self, key: &str) -> Option<AggregatedQuotes> {
        if let Some((timestamp, quotes)) = self.quote_cache.get(key) {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs();
            
            if now - timestamp < self.cache_ttl {
                return Some(quotes.clone());
            }
        }
        None
    }

    fn set_cached(&mut self, key: String, quotes: AggregatedQuotes) {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        self.quote_cache.insert(key, (now, quotes));
    }

    fn calculate_gas_savings(&self, quotes: &AggregatedQuotes) -> Option<f64> {
        let sorted_by_gas = quotes.sorted_by_gas();
        if sorted_by_gas.len() < 2 {
            return None;
        }
        
        let cheapest = sorted_by_gas.first()?.gas_cost_usd?;
        let most_expensive = sorted_by_gas.last()?.gas_cost_usd?;
        Some(most_expensive - cheapest)
    }

    fn get_recommendation(&self, quotes: &AggregatedQuotes) -> String {
        let sorted = quotes.sorted_by_output();
        if sorted.is_empty() {
            return "No quotes available".to_string();
        }

        let best = sorted.first().unwrap();
        let provider_name = best.provider.display_name();

        if sorted.len() == 1 {
            return format!("Only {} available for this route", provider_name);
        }

        let best_amount: f64 = best.to_amount.parse().unwrap_or(0.0);
        let second: f64 = sorted.get(1).map(|q| q.to_amount.parse().unwrap_or(0.0)).unwrap_or(0.0);
        
        let diff_percent = if second > 0.0 {
            ((best_amount - second) / second) * 100.0
        } else {
            0.0
        };

        if diff_percent > 1.0 {
            format!("{} offers {:.2}% more output", provider_name, diff_percent)
        } else if diff_percent > 0.1 {
            format!("{} is slightly better ({:.2}% more)", provider_name, diff_percent)
        } else {
            format!("Prices are similar, {} has lowest gas", 
                quotes.sorted_by_gas().first().map(|q| q.provider.display_name()).unwrap_or("unknown")
            )
        }
    }
}

/// Quote comparison result
#[derive(Debug, Clone)]
pub struct QuoteComparison {
    pub best_provider: DEXProvider,
    pub best_output: String,
    pub worst_provider: DEXProvider,
    pub worst_output: String,
    pub spread_percent: f64,
    pub gas_savings_usd: Option<f64>,
    pub recommendation: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_providers_for_chain() {
        let eth_providers = DEXAggregator::get_providers_for_chain(Chain::Ethereum);
        assert!(eth_providers.contains(&DEXProvider::OneInch));
        assert!(eth_providers.contains(&DEXProvider::ZeroX));
        assert!(eth_providers.contains(&DEXProvider::THORChain));

        let btc_providers = DEXAggregator::get_providers_for_chain(Chain::Bitcoin);
        assert!(btc_providers.contains(&DEXProvider::THORChain));
        assert!(!btc_providers.contains(&DEXProvider::OneInch));

        let osmosis_providers = DEXAggregator::get_providers_for_chain(Chain::Osmosis);
        assert!(osmosis_providers.contains(&DEXProvider::Osmosis));
    }

    #[test]
    fn test_get_all_quotes() {
        let mut aggregator = DEXAggregator::new(None, None);
        let request = SwapQuoteRequest {
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
        };

        let result = aggregator.get_all_quotes(&request).unwrap();
        assert!(!result.quotes.is_empty());
        assert!(result.best_quote.is_some());
    }

    #[test]
    fn test_compare_quotes() {
        let mut aggregator = DEXAggregator::new(None, None);
        let request = SwapQuoteRequest {
            chain: Chain::Polygon,
            from_token: SwapQuoteRequest::NATIVE_ETH.to_string(),
            to_token: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174".to_string(),
            amount: "1000000000000000000".to_string(),
            slippage: 1.0,
            from_address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
            provider: None,
            deadline_seconds: None,
            referrer: None,
            gas_price_gwei: None,
        };

        let comparison = aggregator.compare_quotes(&request).unwrap();
        assert!(!comparison.recommendation.is_empty());
    }

    #[test]
    fn test_cache_behavior() {
        let mut aggregator = DEXAggregator::new(None, None);
        let request = SwapQuoteRequest {
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
        };

        // First call - should fetch
        let result1 = aggregator.get_all_quotes(&request).unwrap();
        let ts1 = result1.fetched_at;

        // Second call - should use cache
        let result2 = aggregator.get_all_quotes(&request).unwrap();
        let ts2 = result2.fetched_at;

        // Timestamps should be identical (cached)
        assert_eq!(ts1, ts2);
    }
}
