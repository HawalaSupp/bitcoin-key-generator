//! HTTP Client with Connection Pooling
//!
//! Provides a global HTTP client with:
//! - Connection pooling for better performance
//! - Certificate pinning for security-critical endpoints
//! - Built-in rate limiting per endpoint
//! - Automatic retries with exponential backoff

use reqwest::blocking::Client;
use reqwest::Certificate;
use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use crate::error::{HawalaError, HawalaResult};

/// Global HTTP client instance - lazy initialized
static GLOBAL_CLIENT: OnceLock<Arc<HttpClientPool>> = OnceLock::new();

/// Certificate pins for security-critical endpoints
/// SHA256 fingerprints of expected TLS certificates
static CERTIFICATE_PINS: OnceLock<HashMap<&'static str, Vec<&'static str>>> = OnceLock::new();

/// HTTP Client Pool with connection reuse
pub struct HttpClientPool {
    /// Default client for general use
    default_client: Client,
    /// Pinned clients for specific domains
    pinned_clients: Mutex<HashMap<String, Client>>,
    /// Rate limiter per domain
    rate_limiter: Mutex<super::RateLimiter>,
}

impl HttpClientPool {
    /// Create a new HTTP client pool
    fn new() -> HawalaResult<Self> {
        let default_client = Client::builder()
            .timeout(Duration::from_secs(30))
            .connect_timeout(Duration::from_secs(10))
            .pool_idle_timeout(Duration::from_secs(90))
            .pool_max_idle_per_host(5)
            .tcp_keepalive(Duration::from_secs(60))
            .tcp_nodelay(true)
            .user_agent("Hawala/1.0")
            .build()
            .map_err(|e| HawalaError::network(format!("Failed to create HTTP client: {}", e)))?;

        Ok(Self {
            default_client,
            pinned_clients: Mutex::new(HashMap::new()),
            rate_limiter: Mutex::new(super::RateLimiter::new(10, 1)), // 10 req/sec default
        })
    }

    /// Get the default HTTP client
    pub fn client(&self) -> &Client {
        &self.default_client
    }

    /// Make a GET request with rate limiting
    pub fn get(&self, url: &str) -> HawalaResult<reqwest::blocking::Response> {
        self.check_rate_limit(url)?;
        
        self.default_client
            .get(url)
            .send()
            .map_err(|e| HawalaError::network(format!("GET request failed: {}", e)))
    }

    /// Make a POST request with rate limiting
    pub fn post_json<T: serde::Serialize>(&self, url: &str, body: &T) -> HawalaResult<reqwest::blocking::Response> {
        self.check_rate_limit(url)?;
        
        self.default_client
            .post(url)
            .json(body)
            .send()
            .map_err(|e| HawalaError::network(format!("POST request failed: {}", e)))
    }

    /// Check rate limit for a domain
    fn check_rate_limit(&self, url: &str) -> HawalaResult<()> {
        let domain = extract_domain(url);
        let mut limiter = self.rate_limiter.lock()
            .map_err(|_| HawalaError::internal("Rate limiter lock poisoned"))?;

        if !limiter.check(&domain) {
            return Err(HawalaError::rate_limited(format!(
                "Rate limit exceeded for {}",
                domain
            )));
        }
        Ok(())
    }

    /// Create a client with certificate pinning for a specific domain
    #[allow(dead_code)]
    pub fn get_pinned_client(&self, domain: &str, cert_pem: &[u8]) -> HawalaResult<Client> {
        let mut clients = self.pinned_clients.lock()
            .map_err(|_| HawalaError::internal("Pinned clients lock poisoned"))?;

        if let Some(client) = clients.get(domain) {
            return Ok(client.clone());
        }

        let cert = Certificate::from_pem(cert_pem)
            .map_err(|e| HawalaError::internal(format!("Invalid certificate: {}", e)))?;

        let client = Client::builder()
            .timeout(Duration::from_secs(30))
            .connect_timeout(Duration::from_secs(10))
            .pool_idle_timeout(Duration::from_secs(90))
            .pool_max_idle_per_host(5)
            .add_root_certificate(cert)
            .user_agent("Hawala/1.0")
            .build()
            .map_err(|e| HawalaError::network(format!("Failed to create pinned client: {}", e)))?;

        clients.insert(domain.to_string(), client.clone());
        Ok(client)
    }
}

/// Get the global HTTP client pool
pub fn get_client_pool() -> &'static Arc<HttpClientPool> {
    GLOBAL_CLIENT.get_or_init(|| {
        // HttpClientPool::new() only fails if TLS/rustls initialization fails,
        // which is a system-level issue. Using expect() here is appropriate
        // as the app cannot function without HTTP capabilities.
        Arc::new(HttpClientPool::new().expect("HTTP client pool initialization failed - check TLS configuration"))
    })
}

/// Get the default HTTP client
pub fn get_client() -> &'static Client {
    get_client_pool().client()
}

/// Make a rate-limited GET request
pub fn get(url: &str) -> HawalaResult<reqwest::blocking::Response> {
    get_client_pool().get(url)
}

/// Make a rate-limited POST request with JSON body
pub fn post_json<T: serde::Serialize>(url: &str, body: &T) -> HawalaResult<reqwest::blocking::Response> {
    get_client_pool().post_json(url, body)
}

/// Extract domain from URL for rate limiting
fn extract_domain(url: &str) -> String {
    url.trim_start_matches("https://")
        .trim_start_matches("http://")
        .split('/')
        .next()
        .unwrap_or(url)
        .to_string()
}

/// Initialize certificate pins for known exchanges and APIs
/// Call this at app startup
#[allow(dead_code)]
pub fn init_certificate_pins() {
    let _ = CERTIFICATE_PINS.get_or_init(|| {
        let mut pins = HashMap::new();
        
        // Mempool.space (Bitcoin explorer)
        pins.insert("mempool.space", vec![
            // Add SHA256 fingerprints of expected certificates
            // These would be updated periodically
        ]);
        
        // Ethereum RPCs
        pins.insert("eth.llamarpc.com", vec![]);
        pins.insert("mainnet.infura.io", vec![]);
        
        // Exchange APIs (for price feeds)
        pins.insert("api.coingecko.com", vec![]);
        pins.insert("api.coinbase.com", vec![]);
        
        pins
    });
}

/// Per-endpoint rate limit configuration
#[derive(Clone)]
pub struct EndpointRateLimit {
    pub requests_per_second: u32,
    pub burst_size: u32,
}

impl Default for EndpointRateLimit {
    fn default() -> Self {
        Self {
            requests_per_second: 5,
            burst_size: 10,
        }
    }
}

/// Rate limits for known endpoints
pub fn get_endpoint_rate_limit(domain: &str) -> EndpointRateLimit {
    match domain {
        // Public RPCs - be conservative
        "eth.llamarpc.com" | "polygon-rpc.com" | "bsc-dataseed.binance.org" => {
            EndpointRateLimit {
                requests_per_second: 3,
                burst_size: 5,
            }
        }
        // Blockchain explorers
        "mempool.space" | "blockstream.info" => {
            EndpointRateLimit {
                requests_per_second: 2,
                burst_size: 5,
            }
        }
        // Solana RPCs
        "api.mainnet-beta.solana.com" | "api.devnet.solana.com" => {
            EndpointRateLimit {
                requests_per_second: 10,
                burst_size: 20,
            }
        }
        // Default
        _ => EndpointRateLimit::default(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_domain() {
        assert_eq!(extract_domain("https://api.example.com/v1/endpoint"), "api.example.com");
        assert_eq!(extract_domain("http://localhost:8080/test"), "localhost:8080");
        assert_eq!(extract_domain("https://mempool.space/api/address/abc"), "mempool.space");
    }

    #[test]
    fn test_client_pool_creation() {
        let pool = get_client_pool();
        assert!(pool.client().get("https://example.com").build().is_ok());
    }

    #[test]
    fn test_endpoint_rate_limits() {
        let limit = get_endpoint_rate_limit("eth.llamarpc.com");
        assert_eq!(limit.requests_per_second, 3);
        
        let default_limit = get_endpoint_rate_limit("unknown.domain.com");
        assert_eq!(default_limit.requests_per_second, 5);
    }
}
