//! Network Configuration Validation
//!
//! Validates and manages RPC endpoints with:
//! - URL format validation
//! - TLS requirement enforcement
//! - Endpoint health checking
//! - Known provider validation
//! - Custom endpoint whitelisting

use crate::error::{HawalaError, HawalaResult};
use crate::types::Chain;
use std::collections::{HashMap, HashSet};
use std::sync::RwLock;
use std::time::{Duration, Instant};
use url::Url;

/// Network configuration manager
pub struct NetworkConfig {
    /// Custom RPC endpoints per chain
    custom_endpoints: RwLock<HashMap<Chain, Vec<RpcEndpoint>>>,
    /// Whitelisted domains for custom endpoints
    whitelisted_domains: RwLock<HashSet<String>>,
    /// Endpoint health status cache
    health_cache: RwLock<HashMap<String, EndpointHealth>>,
}

/// RPC endpoint configuration
#[derive(Debug, Clone)]
pub struct RpcEndpoint {
    pub url: String,
    pub chain: Chain,
    pub priority: u8,
    pub is_custom: bool,
    pub requires_auth: bool,
    pub rate_limit: Option<u32>,
}

/// Endpoint health status
#[derive(Debug, Clone)]
pub struct EndpointHealth {
    pub url: String,
    pub is_healthy: bool,
    pub last_check: Instant,
    pub latency_ms: Option<u64>,
    pub error_count: u32,
    pub success_count: u32,
}

/// Validation result for RPC endpoint
#[derive(Debug, Clone)]
pub struct EndpointValidation {
    pub is_valid: bool,
    pub url: Option<String>,
    pub warnings: Vec<String>,
    pub errors: Vec<String>,
}

impl NetworkConfig {
    /// Create a new network configuration manager
    pub fn new() -> Self {
        Self {
            custom_endpoints: RwLock::new(HashMap::new()),
            whitelisted_domains: RwLock::new(Self::default_whitelist()),
            health_cache: RwLock::new(HashMap::new()),
        }
    }

    /// Default whitelisted domains for RPC endpoints
    fn default_whitelist() -> HashSet<String> {
        let mut whitelist = HashSet::new();
        
        // Major RPC providers
        whitelist.insert("infura.io".to_string());
        whitelist.insert("alchemy.com".to_string());
        whitelist.insert("quicknode.com".to_string());
        whitelist.insert("ankr.com".to_string());
        whitelist.insert("chainstack.com".to_string());
        whitelist.insert("getblock.io".to_string());
        whitelist.insert("moralis.io".to_string());
        whitelist.insert("drpc.org".to_string());
        whitelist.insert("tenderly.co".to_string());
        
        // Bitcoin
        whitelist.insert("mempool.space".to_string());
        whitelist.insert("blockstream.info".to_string());
        whitelist.insert("blockchain.info".to_string());
        whitelist.insert("btc.com".to_string());
        
        // Ethereum
        whitelist.insert("etherscan.io".to_string());
        whitelist.insert("ethplorer.io".to_string());
        
        // Solana
        whitelist.insert("solana.com".to_string());
        whitelist.insert("helius.xyz".to_string());
        whitelist.insert("triton.one".to_string());
        whitelist.insert("genesysgo.net".to_string());
        
        // XRP
        whitelist.insert("xrpl.org".to_string());
        whitelist.insert("ripple.com".to_string());
        
        // Multi-chain
        whitelist.insert("publicnode.com".to_string());
        whitelist.insert("llamarpc.com".to_string());
        whitelist.insert("1rpc.io".to_string());
        
        whitelist
    }

    /// Validate an RPC endpoint URL
    pub fn validate_endpoint(&self, url: &str, chain: Chain) -> EndpointValidation {
        let mut warnings = Vec::new();
        let mut errors = Vec::new();

        // Parse URL
        let parsed = match Url::parse(url) {
            Ok(u) => u,
            Err(e) => {
                errors.push(format!("Invalid URL format: {}", e));
                return EndpointValidation {
                    is_valid: false,
                    url: None,
                    warnings,
                    errors,
                };
            }
        };

        // Require HTTPS for production
        if parsed.scheme() != "https" {
            if parsed.scheme() == "http" {
                // Allow HTTP only for localhost/development
                if let Some(host) = parsed.host_str() {
                    if host == "localhost" || host == "127.0.0.1" || host.starts_with("192.168.") {
                        warnings.push("HTTP allowed for local development only".to_string());
                    } else {
                        errors.push("HTTPS required for remote endpoints".to_string());
                    }
                }
            } else if parsed.scheme() == "wss" || parsed.scheme() == "ws" {
                // WebSocket is fine for subscriptions
                if parsed.scheme() == "ws" {
                    warnings.push("WSS (secure WebSocket) recommended over WS".to_string());
                }
            } else {
                errors.push(format!("Unsupported URL scheme: {}", parsed.scheme()));
            }
        }

        // Check domain whitelist
        if let Some(host) = parsed.host_str() {
            let is_whitelisted = self.is_domain_whitelisted(host);
            if !is_whitelisted {
                warnings.push(format!(
                    "Domain '{}' is not in the trusted provider list. Ensure you trust this endpoint.",
                    host
                ));
            }

            // Check for suspicious patterns
            if host.contains("..") || host.contains("//") {
                errors.push("URL contains suspicious path patterns".to_string());
            }

            // Warn about IP addresses
            if parsed.host().map(|h| matches!(h, url::Host::Ipv4(_) | url::Host::Ipv6(_))).unwrap_or(false) {
                warnings.push("Using IP address instead of domain name - ensure endpoint is trusted".to_string());
            }
        }

        // Validate chain-specific path patterns
        self.validate_chain_endpoint(&parsed, chain, &mut warnings, &mut errors);

        // Check for sensitive data in URL
        if parsed.username() != "" || parsed.password().is_some() {
            warnings.push("Credentials in URL - consider using headers for authentication".to_string());
        }

        if let Some(query) = parsed.query() {
            if query.to_lowercase().contains("apikey") || query.to_lowercase().contains("api_key") {
                warnings.push("API key in URL query string - ensure URL is not logged".to_string());
            }
        }

        let is_valid = errors.is_empty();
        let normalized_url = if is_valid {
            Some(parsed.to_string())
        } else {
            None
        };

        EndpointValidation {
            is_valid,
            url: normalized_url,
            warnings,
            errors,
        }
    }

    /// Validate chain-specific endpoint requirements
    fn validate_chain_endpoint(
        &self,
        url: &Url,
        chain: Chain,
        warnings: &mut Vec<String>,
        _errors: &mut Vec<String>,
    ) {
        let host = url.host_str().unwrap_or("");
        let path = url.path();

        match chain {
            Chain::Bitcoin | Chain::BitcoinTestnet => {
                // Bitcoin endpoints typically use specific paths
                if host.contains("mempool") && !path.contains("/api") {
                    warnings.push("Mempool.space API typically uses /api path".to_string());
                }
            }
            Chain::Ethereum | Chain::EthereumSepolia | Chain::Bnb | Chain::Polygon
            | Chain::Arbitrum | Chain::Optimism | Chain::Base | Chain::Avalanche => {
                // EVM endpoints should support JSON-RPC
                if host.contains("etherscan") || host.contains("polygonscan") || host.contains("bscscan") {
                    warnings.push("Block explorer API - not a JSON-RPC endpoint".to_string());
                }
            }
            Chain::Solana | Chain::SolanaDevnet => {
                if !path.is_empty() && path != "/" {
                    warnings.push("Solana RPC typically uses root path".to_string());
                }
            }
            Chain::Xrp | Chain::XrpTestnet => {
                // XRP uses different API format
                if host.contains("xrpl.org") && !path.is_empty() && path != "/" {
                    warnings.push("XRPL.org API typically uses root path".to_string());
                }
            }
            _ => {}
        }
    }

    /// Check if a domain is whitelisted
    pub fn is_domain_whitelisted(&self, domain: &str) -> bool {
        let Ok(whitelist) = self.whitelisted_domains.read() else { return false; };
        
        // Check exact match
        if whitelist.contains(domain) {
            return true;
        }

        // Check if it's a subdomain of a whitelisted domain
        for allowed in whitelist.iter() {
            if domain.ends_with(&format!(".{}", allowed)) {
                return true;
            }
        }

        false
    }

    /// Add a domain to the whitelist
    pub fn whitelist_domain(&self, domain: &str) -> HawalaResult<()> {
        // Validate domain format
        if domain.is_empty() || domain.contains('/') || domain.contains(':') {
            return Err(HawalaError::invalid_input(
                "Invalid domain format - should be like 'example.com'"
            ));
        }

        let mut whitelist = self.whitelisted_domains.write()
            .map_err(|_| HawalaError::internal("Whitelist lock poisoned"))?;
        whitelist.insert(domain.to_lowercase());
        Ok(())
    }

    /// Add a custom RPC endpoint
    pub fn add_custom_endpoint(&self, endpoint: RpcEndpoint) -> HawalaResult<()> {
        // Validate first
        let validation = self.validate_endpoint(&endpoint.url, endpoint.chain);
        if !validation.is_valid {
            return Err(HawalaError::invalid_input(
                validation.errors.join("; ")
            ));
        }

        let mut endpoints = self.custom_endpoints.write()
            .map_err(|_| HawalaError::internal("Endpoints lock poisoned"))?;
        endpoints
            .entry(endpoint.chain)
            .or_insert_with(Vec::new)
            .push(endpoint);

        Ok(())
    }

    /// Get endpoints for a chain (custom + defaults)
    pub fn get_endpoints(&self, chain: Chain) -> Vec<RpcEndpoint> {
        let mut result = Vec::new();

        // Add custom endpoints first (higher priority)
        if let Ok(custom) = self.custom_endpoints.read() {
            if let Some(eps) = custom.get(&chain) {
                result.extend(eps.clone());
            }
        }

        // Add default endpoints
        result.extend(Self::default_endpoints(chain));

        // Sort by priority
        result.sort_by_key(|e| e.priority);
        result
    }

    /// Default RPC endpoints per chain
    pub fn default_endpoints(chain: Chain) -> Vec<RpcEndpoint> {
        match chain {
            Chain::Bitcoin => vec![
                RpcEndpoint {
                    url: "https://mempool.space/api".to_string(),
                    chain,
                    priority: 1,
                    is_custom: false,
                    requires_auth: false,
                    rate_limit: Some(10),
                },
                RpcEndpoint {
                    url: "https://blockstream.info/api".to_string(),
                    chain,
                    priority: 2,
                    is_custom: false,
                    requires_auth: false,
                    rate_limit: Some(10),
                },
            ],
            Chain::BitcoinTestnet => vec![
                RpcEndpoint {
                    url: "https://mempool.space/testnet/api".to_string(),
                    chain,
                    priority: 1,
                    is_custom: false,
                    requires_auth: false,
                    rate_limit: Some(10),
                },
            ],
            Chain::Ethereum => vec![
                RpcEndpoint {
                    url: "https://eth.llamarpc.com".to_string(),
                    chain,
                    priority: 1,
                    is_custom: false,
                    requires_auth: false,
                    rate_limit: Some(25),
                },
                RpcEndpoint {
                    url: "https://ethereum.publicnode.com".to_string(),
                    chain,
                    priority: 2,
                    is_custom: false,
                    requires_auth: false,
                    rate_limit: Some(25),
                },
            ],
            Chain::EthereumSepolia => vec![
                RpcEndpoint {
                    url: "https://ethereum-sepolia.publicnode.com".to_string(),
                    chain,
                    priority: 1,
                    is_custom: false,
                    requires_auth: false,
                    rate_limit: Some(25),
                },
            ],
            Chain::Solana => vec![
                RpcEndpoint {
                    url: "https://api.mainnet-beta.solana.com".to_string(),
                    chain,
                    priority: 1,
                    is_custom: false,
                    requires_auth: false,
                    rate_limit: Some(40),
                },
            ],
            Chain::SolanaDevnet => vec![
                RpcEndpoint {
                    url: "https://api.devnet.solana.com".to_string(),
                    chain,
                    priority: 1,
                    is_custom: false,
                    requires_auth: false,
                    rate_limit: Some(40),
                },
            ],
            Chain::Xrp => vec![
                RpcEndpoint {
                    url: "https://xrplcluster.com".to_string(),
                    chain,
                    priority: 1,
                    is_custom: false,
                    requires_auth: false,
                    rate_limit: Some(10),
                },
                RpcEndpoint {
                    url: "https://s1.ripple.com:51234".to_string(),
                    chain,
                    priority: 2,
                    is_custom: false,
                    requires_auth: false,
                    rate_limit: Some(10),
                },
            ],
            Chain::XrpTestnet => vec![
                RpcEndpoint {
                    url: "https://s.altnet.rippletest.net:51234".to_string(),
                    chain,
                    priority: 1,
                    is_custom: false,
                    requires_auth: false,
                    rate_limit: Some(10),
                },
            ],
            _ => vec![],
        }
    }

    /// Update health status for an endpoint
    pub fn update_health(&self, url: &str, is_healthy: bool, latency_ms: Option<u64>) {
        let Ok(mut cache) = self.health_cache.write() else { return; };
        let entry = cache.entry(url.to_string()).or_insert(EndpointHealth {
            url: url.to_string(),
            is_healthy,
            last_check: Instant::now(),
            latency_ms,
            error_count: 0,
            success_count: 0,
        });

        entry.is_healthy = is_healthy;
        entry.last_check = Instant::now();
        entry.latency_ms = latency_ms;
        
        if is_healthy {
            entry.success_count += 1;
        } else {
            entry.error_count += 1;
        }
    }

    /// Get health status for an endpoint
    pub fn get_health(&self, url: &str) -> Option<EndpointHealth> {
        let cache = self.health_cache.read().ok()?;
        cache.get(url).cloned()
    }

    /// Check if health check is stale
    pub fn is_health_stale(&self, url: &str, max_age: Duration) -> bool {
        if let Some(health) = self.get_health(url) {
            health.last_check.elapsed() > max_age
        } else {
            true
        }
    }
}

impl Default for NetworkConfig {
    fn default() -> Self {
        Self::new()
    }
}

/// Global network configuration instance
static NETWORK_CONFIG: std::sync::OnceLock<NetworkConfig> = std::sync::OnceLock::new();

/// Get the global network configuration
pub fn get_network_config() -> &'static NetworkConfig {
    NETWORK_CONFIG.get_or_init(NetworkConfig::new)
}

/// Validate an RPC endpoint (convenience function)
pub fn validate_rpc_endpoint(url: &str, chain: Chain) -> EndpointValidation {
    get_network_config().validate_endpoint(url, chain)
}

/// Check if a domain is trusted
pub fn is_trusted_provider(domain: &str) -> bool {
    get_network_config().is_domain_whitelisted(domain)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_valid_https_endpoint() {
        let config = NetworkConfig::new();
        let result = config.validate_endpoint("https://mempool.space/api", Chain::Bitcoin);
        assert!(result.is_valid);
        assert!(result.errors.is_empty());
    }

    #[test]
    fn test_http_rejected() {
        let config = NetworkConfig::new();
        let result = config.validate_endpoint("http://untrusted.com/api", Chain::Bitcoin);
        assert!(!result.is_valid);
        assert!(result.errors.iter().any(|e| e.contains("HTTPS required")));
    }

    #[test]
    fn test_localhost_http_allowed() {
        let config = NetworkConfig::new();
        let result = config.validate_endpoint("http://localhost:8545", Chain::Ethereum);
        assert!(result.is_valid);
        assert!(result.warnings.iter().any(|w| w.contains("local development")));
    }

    #[test]
    fn test_unknown_domain_warning() {
        let config = NetworkConfig::new();
        let result = config.validate_endpoint("https://unknown-provider.xyz/api", Chain::Bitcoin);
        assert!(result.is_valid); // Valid but with warning
        assert!(result.warnings.iter().any(|w| w.contains("not in the trusted")));
    }

    #[test]
    fn test_whitelisted_domain() {
        let config = NetworkConfig::new();
        assert!(config.is_domain_whitelisted("mempool.space"));
        assert!(config.is_domain_whitelisted("api.mempool.space"));
        assert!(!config.is_domain_whitelisted("fake-mempool.space"));
    }

    #[test]
    fn test_invalid_url() {
        let config = NetworkConfig::new();
        let result = config.validate_endpoint("not a url", Chain::Bitcoin);
        assert!(!result.is_valid);
        assert!(result.errors.iter().any(|e| e.contains("Invalid URL")));
    }

    #[test]
    fn test_credentials_warning() {
        let config = NetworkConfig::new();
        let result = config.validate_endpoint(
            "https://user:pass@mempool.space/api",
            Chain::Bitcoin
        );
        assert!(result.warnings.iter().any(|w| w.contains("Credentials")));
    }
}
