//! Rate Limiter
//!
//! Token bucket rate limiting for API calls with per-endpoint configuration.

use std::collections::HashMap;
use std::time::{Duration, Instant};

/// Token bucket rate limiter with per-endpoint configuration
pub struct RateLimiter {
    buckets: HashMap<String, Bucket>,
    default_rate: u32,
    default_period: Duration,
    endpoint_configs: HashMap<String, EndpointConfig>,
}

/// Configuration for a specific endpoint
#[derive(Clone)]
pub struct EndpointConfig {
    pub rate: u32,
    pub period: Duration,
    pub burst: u32,
}

impl Default for EndpointConfig {
    fn default() -> Self {
        Self {
            rate: 5,
            period: Duration::from_secs(1),
            burst: 10,
        }
    }
}

struct Bucket {
    tokens: u32,
    max_tokens: u32,
    last_refill: Instant,
    refill_period: Duration,
    tokens_per_refill: u32,
}

impl RateLimiter {
    /// Create a new rate limiter with default settings
    /// `rate` is the number of requests allowed per `period`
    pub fn new(rate: u32, period_seconds: u64) -> Self {
        Self {
            buckets: HashMap::new(),
            default_rate: rate,
            default_period: Duration::from_secs(period_seconds),
            endpoint_configs: Self::default_endpoint_configs(),
        }
    }

    /// Default configurations for known endpoints
    fn default_endpoint_configs() -> HashMap<String, EndpointConfig> {
        let mut configs = HashMap::new();
        
        // Public RPCs - be conservative
        for endpoint in &[
            "eth.llamarpc.com",
            "polygon-rpc.com", 
            "bsc-dataseed.binance.org",
            "arb1.arbitrum.io",
            "mainnet.optimism.io",
            "mainnet.base.org",
        ] {
            configs.insert(endpoint.to_string(), EndpointConfig {
                rate: 3,
                period: Duration::from_secs(1),
                burst: 5,
            });
        }
        
        // Blockchain explorers - more conservative
        for endpoint in &["mempool.space", "blockstream.info"] {
            configs.insert(endpoint.to_string(), EndpointConfig {
                rate: 2,
                period: Duration::from_secs(1),
                burst: 5,
            });
        }
        
        // Solana - more generous
        for endpoint in &["api.mainnet-beta.solana.com", "api.devnet.solana.com"] {
            configs.insert(endpoint.to_string(), EndpointConfig {
                rate: 10,
                period: Duration::from_secs(1),
                burst: 20,
            });
        }
        
        // XRP Ledger
        for endpoint in &["xrplcluster.com", "s.altnet.rippletest.net"] {
            configs.insert(endpoint.to_string(), EndpointConfig {
                rate: 5,
                period: Duration::from_secs(1),
                burst: 10,
            });
        }
        
        configs
    }

    /// Check if a request is allowed for the given key
    pub fn check(&mut self, key: &str) -> bool {
        // Get endpoint-specific config or use defaults
        let config = self.endpoint_configs.get(key).cloned();
        
        let bucket = self.buckets.entry(key.to_string()).or_insert_with(|| {
            if let Some(cfg) = config {
                Bucket {
                    tokens: cfg.burst,
                    max_tokens: cfg.burst,
                    last_refill: Instant::now(),
                    refill_period: cfg.period,
                    tokens_per_refill: cfg.rate,
                }
            } else {
                Bucket {
                    tokens: self.default_rate,
                    max_tokens: self.default_rate,
                    last_refill: Instant::now(),
                    refill_period: self.default_period,
                    tokens_per_refill: self.default_rate,
                }
            }
        });

        // Refill tokens based on elapsed time
        let elapsed = bucket.last_refill.elapsed();
        if elapsed >= bucket.refill_period {
            let refills = (elapsed.as_millis() / bucket.refill_period.as_millis()) as u32;
            let new_tokens = bucket.tokens.saturating_add(refills * bucket.tokens_per_refill);
            bucket.tokens = new_tokens.min(bucket.max_tokens);
            bucket.last_refill = Instant::now();
        }

        // Try to consume a token
        if bucket.tokens > 0 {
            bucket.tokens -= 1;
            true
        } else {
            false
        }
    }

    /// Configure rate limit for a specific endpoint
    pub fn configure_endpoint(&mut self, endpoint: &str, config: EndpointConfig) {
        self.endpoint_configs.insert(endpoint.to_string(), config);
        // Reset bucket if it exists
        self.buckets.remove(endpoint);
    }

    /// Get time until next allowed request
    pub fn time_until_allowed(&self, key: &str) -> Option<Duration> {
        self.buckets.get(key).and_then(|bucket| {
            if bucket.tokens > 0 {
                None
            } else {
                let elapsed = bucket.last_refill.elapsed();
                if elapsed < bucket.refill_period {
                    Some(bucket.refill_period - elapsed)
                } else {
                    None
                }
            }
        })
    }

    /// Get current token count for monitoring
    pub fn get_tokens(&self, key: &str) -> Option<u32> {
        self.buckets.get(key).map(|b| b.tokens)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rate_limiter_basic() {
        let mut limiter = RateLimiter::new(3, 60);
        
        assert!(limiter.check("api1"));
        assert!(limiter.check("api1"));
        assert!(limiter.check("api1"));
        assert!(!limiter.check("api1")); // Should be rate limited
        
        // Different key should work
        assert!(limiter.check("api2"));
    }

    #[test]
    fn test_endpoint_specific_config() {
        let mut limiter = RateLimiter::new(10, 1);
        
        // mempool.space has lower limit
        assert!(limiter.check("mempool.space"));
        assert!(limiter.check("mempool.space"));
        // After 2 requests with burst of 5, should still have tokens
        assert!(limiter.check("mempool.space"));
    }

    #[test]
    fn test_custom_endpoint_config() {
        let mut limiter = RateLimiter::new(10, 1);
        
        limiter.configure_endpoint("custom.api.com", EndpointConfig {
            rate: 1,
            period: Duration::from_secs(1),
            burst: 2,
        });
        
        assert!(limiter.check("custom.api.com"));
        assert!(limiter.check("custom.api.com"));
        assert!(!limiter.check("custom.api.com")); // burst of 2 exceeded
    }
}
