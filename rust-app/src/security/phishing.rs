//! Phishing & Scam Detection
//!
//! Detects and prevents interactions with:
//! - Known scam addresses
//! - Phishing domains
//! - Sanctioned addresses (OFAC)
//! - Honeypot tokens
//!
//! Inspired by MetaMask Snaps, Rabby

use crate::error::HawalaResult;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::sync::RwLock;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

// =============================================================================
// Types
// =============================================================================

/// Result of checking an address
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AddressCheckResult {
    /// Address that was checked
    pub address: String,
    /// Whether the address is flagged
    pub is_flagged: bool,
    /// Type of flag (if flagged)
    pub flag_type: Option<FlagType>,
    /// Risk level
    pub risk_level: PhishingRiskLevel,
    /// Source of the flag
    pub source: Option<String>,
    /// Number of reports
    pub report_count: u32,
    /// Additional details
    pub details: Option<String>,
    /// Whether transactions should be blocked
    pub should_block: bool,
}

/// Result of checking a domain
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DomainCheckResult {
    /// Domain that was checked
    pub domain: String,
    /// Whether the domain is flagged
    pub is_flagged: bool,
    /// Type of flag (if flagged)
    pub flag_type: Option<DomainFlagType>,
    /// Risk level
    pub risk_level: PhishingRiskLevel,
    /// Details about the flag
    pub details: Option<String>,
    /// Legitimate domain it may be impersonating
    pub impersonating: Option<String>,
    /// Whether connection should be blocked
    pub should_block: bool,
}

/// Type of address flag
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum FlagType {
    /// Known scammer
    Scammer,
    /// OFAC sanctioned
    Sanctioned,
    /// Honeypot token contract
    Honeypot,
    /// Phishing contract
    Phishing,
    /// Reported by community
    CommunityReport,
    /// Associated with hack
    HackAssociated,
    /// High-risk mixer
    Mixer,
}

/// Type of domain flag
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum DomainFlagType {
    /// Known phishing site
    Phishing,
    /// Impersonating legitimate site
    Impersonation,
    /// Malware distribution
    Malware,
    /// Suspicious new domain
    Suspicious,
    /// Community reported
    CommunityReport,
}

/// Risk level
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "snake_case")]
pub enum PhishingRiskLevel {
    Safe,
    Low,
    Medium,
    High,
    Critical,
}

/// Blocklist entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlocklistEntry {
    /// Address or domain
    pub value: String,
    /// Type of flag
    pub flag_type: String,
    /// Source of information
    pub source: String,
    /// When it was added
    pub added_at: u64,
    /// Number of reports
    pub report_count: u32,
}

// =============================================================================
// Phishing Detector
// =============================================================================

/// Phishing and scam detection engine
pub struct PhishingDetector {
    /// Blocklisted addresses
    address_blocklist: RwLock<HashSet<String>>,
    /// Sanctioned addresses (OFAC)
    sanctioned_addresses: RwLock<HashSet<String>>,
    /// Blocklisted domains
    domain_blocklist: RwLock<HashSet<String>>,
    /// Trusted domains
    trusted_domains: RwLock<HashSet<String>>,
    /// Known legitimate domains for impersonation detection
    legitimate_domains: Vec<(&'static str, &'static str)>, // (domain, name)
    /// Last blocklist update
    last_update: RwLock<u64>,
}

impl PhishingDetector {
    /// Create a new phishing detector with default blocklists
    pub fn new() -> Self {
        let mut trusted_domains = HashSet::new();
        
        // Add known legitimate domains
        let legit_domains = vec![
            "uniswap.org",
            "app.uniswap.org",
            "opensea.io",
            "aave.com",
            "app.aave.com",
            "compound.finance",
            "curve.fi",
            "lido.fi",
            "metamask.io",
            "walletconnect.org",
            "etherscan.io",
            "polygonscan.com",
            "bscscan.com",
            "arbiscan.io",
            "optimistic.etherscan.io",
            "basescan.org",
            "solscan.io",
            "coingecko.com",
            "coinmarketcap.com",
            "dextools.io",
            "dexscreener.com",
            "1inch.io",
            "paraswap.io",
            "zapper.fi",
            "zerion.io",
            "rainbow.me",
            "safe.global",
            "gnosis-safe.io",
        ];
        
        for domain in legit_domains {
            trusted_domains.insert(domain.to_string());
        }
        
        // Known legitimate domains for impersonation detection
        let legitimate_domains = vec![
            ("uniswap.org", "Uniswap"),
            ("opensea.io", "OpenSea"),
            ("aave.com", "Aave"),
            ("metamask.io", "MetaMask"),
            ("pancakeswap.finance", "PancakeSwap"),
            ("binance.com", "Binance"),
            ("coinbase.com", "Coinbase"),
            ("kraken.com", "Kraken"),
        ];
        
        Self {
            address_blocklist: RwLock::new(HashSet::new()),
            sanctioned_addresses: RwLock::new(Self::default_sanctioned()),
            domain_blocklist: RwLock::new(HashSet::new()),
            trusted_domains: RwLock::new(trusted_domains),
            legitimate_domains,
            last_update: RwLock::new(Self::current_timestamp()),
        }
    }

    /// Check if an address is flagged
    pub fn check_address(&self, address: &str) -> AddressCheckResult {
        let address_lower = address.to_lowercase();
        
        // Check sanctioned list first (most severe)
        if let Ok(sanctioned) = self.sanctioned_addresses.read() {
            if sanctioned.contains(&address_lower) {
                return AddressCheckResult {
                    address: address.to_string(),
                    is_flagged: true,
                    flag_type: Some(FlagType::Sanctioned),
                    risk_level: PhishingRiskLevel::Critical,
                    source: Some("OFAC SDN List".to_string()),
                    report_count: 0,
                    details: Some("This address is on the OFAC Specially Designated Nationals list. Transactions are prohibited.".to_string()),
                    should_block: true,
                };
            }
        }
        
        // Check general blocklist
        if let Ok(blocklist) = self.address_blocklist.read() {
            if blocklist.contains(&address_lower) {
                return AddressCheckResult {
                    address: address.to_string(),
                    is_flagged: true,
                    flag_type: Some(FlagType::Scammer),
                    risk_level: PhishingRiskLevel::High,
                    source: Some("Community Reports".to_string()),
                    report_count: 1,
                    details: Some("This address has been reported as a scam.".to_string()),
                    should_block: false, // Warn but don't block
                };
            }
        }
        
        // Not flagged
        AddressCheckResult {
            address: address.to_string(),
            is_flagged: false,
            flag_type: None,
            risk_level: PhishingRiskLevel::Safe,
            source: None,
            report_count: 0,
            details: None,
            should_block: false,
        }
    }

    /// Check if a domain is flagged
    pub fn check_domain(&self, domain: &str) -> DomainCheckResult {
        let domain_lower = domain.to_lowercase();
        
        // Check trusted list first
        if let Ok(trusted) = self.trusted_domains.read() {
            if trusted.contains(&domain_lower) {
                return DomainCheckResult {
                    domain: domain.to_string(),
                    is_flagged: false,
                    flag_type: None,
                    risk_level: PhishingRiskLevel::Safe,
                    details: Some("Verified legitimate domain".to_string()),
                    impersonating: None,
                    should_block: false,
                };
            }
        }
        
        // Check blocklist
        if let Ok(blocklist) = self.domain_blocklist.read() {
            if blocklist.contains(&domain_lower) {
                return DomainCheckResult {
                    domain: domain.to_string(),
                    is_flagged: true,
                    flag_type: Some(DomainFlagType::Phishing),
                    risk_level: PhishingRiskLevel::Critical,
                    details: Some("This domain has been reported as a phishing site.".to_string()),
                    impersonating: None,
                    should_block: true,
                };
            }
        }
        
        // Check for impersonation (typosquatting)
        if let Some((legit, name)) = self.check_impersonation(&domain_lower) {
            return DomainCheckResult {
                domain: domain.to_string(),
                is_flagged: true,
                flag_type: Some(DomainFlagType::Impersonation),
                risk_level: PhishingRiskLevel::High,
                details: Some(format!("This domain may be impersonating {}", name)),
                impersonating: Some(legit.to_string()),
                should_block: false,
            };
        }
        
        // Check for suspicious patterns
        if self.has_suspicious_pattern(&domain_lower) {
            return DomainCheckResult {
                domain: domain.to_string(),
                is_flagged: true,
                flag_type: Some(DomainFlagType::Suspicious),
                risk_level: PhishingRiskLevel::Medium,
                details: Some("This domain has suspicious patterns.".to_string()),
                impersonating: None,
                should_block: false,
            };
        }
        
        // Unknown domain - low risk warning
        DomainCheckResult {
            domain: domain.to_string(),
            is_flagged: false,
            flag_type: None,
            risk_level: PhishingRiskLevel::Low,
            details: Some("Unknown domain - proceed with caution".to_string()),
            impersonating: None,
            should_block: false,
        }
    }

    /// Add addresses to the blocklist
    pub fn add_to_blocklist(&self, addresses: &[String]) {
        if let Ok(mut blocklist) = self.address_blocklist.write() {
            for addr in addresses {
                blocklist.insert(addr.to_lowercase());
            }
        }
    }

    /// Add domains to the blocklist
    pub fn add_domains_to_blocklist(&self, domains: &[String]) {
        if let Ok(mut blocklist) = self.domain_blocklist.write() {
            for domain in domains {
                blocklist.insert(domain.to_lowercase());
            }
        }
    }

    /// Add trusted domains
    pub fn add_trusted_domains(&self, domains: &[String]) {
        if let Ok(mut trusted) = self.trusted_domains.write() {
            for domain in domains {
                trusted.insert(domain.to_lowercase());
            }
        }
    }

    /// Update blocklists from remote source
    pub fn update_blocklists(&self) -> HawalaResult<u32> {
        // In production, this would fetch from:
        // - ChainAbuse API
        // - MetaMask phishing list
        // - Custom blocklist server
        
        // For now, just update timestamp
        if let Ok(mut last_update) = self.last_update.write() {
            *last_update = Self::current_timestamp();
        }
        
        Ok(0)
    }

    /// Get last update timestamp
    pub fn last_update_time(&self) -> u64 {
        self.last_update.read().map(|t| *t).unwrap_or(0)
    }

    /// Check if blocklists need update (older than 24 hours)
    pub fn needs_update(&self) -> bool {
        let now = Self::current_timestamp();
        let last = self.last_update_time();
        now - last > 86400 // 24 hours
    }

    // =========================================================================
    // Private Methods
    // =========================================================================

    fn default_sanctioned() -> HashSet<String> {
        // OFAC SDN addresses (sample - real list would be much larger)
        // These are real sanctioned addresses
        let addresses = vec![
            // Tornado Cash related
            "0x8589427373d6d84e98730d7795d8f6f8731fda16",
            "0xd882cfc20f52f2599d84b8e8d58c7fb62cfe344b",
            "0xdd4c48c0b24039969fc16d1cdf626eab821d3384",
            "0x722122df12d4e14e13ac3b6895a86e84145b6967",
            "0xa160cdab225685da1d56aa342ad8841c3b53f291",
            "0xd90e2f925da726b50c4ed8d0fb90ad053324f31b",
            "0x4736dcf1b7a3d580672cce6e7c65cd5cc9cfba9d",
            // Lazarus Group
            "0x098b716b8aaf21512996dc57eb0615e2383e2f96",
            "0xa7e5d5a720f06526557c513402f2e6b5fa20b008",
        ];
        
        addresses.into_iter().map(|s| s.to_string()).collect()
    }

    fn check_impersonation(&self, domain: &str) -> Option<(&'static str, &'static str)> {
        for (legit, name) in &self.legitimate_domains {
            // Check if domain is similar but not the same
            if domain != *legit && self.is_similar(domain, legit) {
                return Some((legit, name));
            }
        }
        None
    }

    fn is_similar(&self, a: &str, b: &str) -> bool {
        // Simple similarity check
        // In production, use Levenshtein distance or more sophisticated methods
        
        // Check for common typosquatting patterns
        let patterns = [
            // Substitutions
            ("o", "0"),
            ("l", "1"),
            ("i", "1"),
            ("e", "3"),
            ("a", "4"),
            ("s", "5"),
            // Extra characters
            ("-", ""),
            (".", ""),
            // Common additions
            ("www", ""),
            ("app-", "app."),
            ("-app", ".app"),
        ];
        
        let a_normalized: String = a.chars().filter(|c| c.is_alphanumeric()).collect();
        let b_normalized: String = b.chars().filter(|c| c.is_alphanumeric()).collect();
        
        // Very similar length and content
        if a_normalized.len() == b_normalized.len() {
            let differences: usize = a_normalized.chars()
                .zip(b_normalized.chars())
                .filter(|(ca, cb)| ca != cb)
                .count();
            
            if differences <= 2 {
                return true;
            }
        }
        
        // Check pattern substitutions
        for (from, to) in &patterns {
            let modified = b.replace(from, to);
            if a == modified {
                return true;
            }
        }
        
        false
    }

    fn has_suspicious_pattern(&self, domain: &str) -> bool {
        let suspicious_keywords = [
            "claim",
            "airdrop",
            "free",
            "giveaway",
            "bonus",
            "reward",
            "double",
            "validate",
            "verification",
            "wallet-connect",
            "metamask-",
            "-metamask",
            "dapp-",
            "-dapp",
        ];
        
        for keyword in &suspicious_keywords {
            if domain.contains(keyword) {
                return true;
            }
        }
        
        // Check for excessive hyphens (common in phishing)
        let hyphen_count = domain.chars().filter(|c| *c == '-').count();
        if hyphen_count >= 3 {
            return true;
        }
        
        // Check for punycode (internationalized domains)
        if domain.contains("xn--") {
            return true;
        }
        
        false
    }

    fn current_timestamp() -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or(Duration::ZERO)
            .as_secs()
    }
}

impl Default for PhishingDetector {
    fn default() -> Self {
        Self::new()
    }
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_detector() {
        let detector = PhishingDetector::new();
        assert!(!detector.legitimate_domains.is_empty());
    }

    #[test]
    fn test_check_sanctioned_address() {
        let detector = PhishingDetector::new();
        
        // Known Tornado Cash address
        let result = detector.check_address("0x8589427373d6d84e98730d7795d8f6f8731fda16");
        assert!(result.is_flagged);
        assert_eq!(result.flag_type, Some(FlagType::Sanctioned));
        assert_eq!(result.risk_level, PhishingRiskLevel::Critical);
        assert!(result.should_block);
    }

    #[test]
    fn test_check_safe_address() {
        let detector = PhishingDetector::new();
        
        let result = detector.check_address("0x1234567890123456789012345678901234567890");
        assert!(!result.is_flagged);
        assert_eq!(result.risk_level, PhishingRiskLevel::Safe);
        assert!(!result.should_block);
    }

    #[test]
    fn test_check_trusted_domain() {
        let detector = PhishingDetector::new();
        
        let result = detector.check_domain("uniswap.org");
        assert!(!result.is_flagged);
        assert_eq!(result.risk_level, PhishingRiskLevel::Safe);
    }

    #[test]
    fn test_check_impersonation() {
        let detector = PhishingDetector::new();
        
        // Typosquatting attempt
        let result = detector.check_domain("un1swap.org");
        assert!(result.is_flagged);
        assert_eq!(result.flag_type, Some(DomainFlagType::Impersonation));
    }

    #[test]
    fn test_suspicious_patterns() {
        let detector = PhishingDetector::new();
        
        let result = detector.check_domain("free-airdrop-claim.xyz");
        assert!(result.is_flagged);
        assert_eq!(result.flag_type, Some(DomainFlagType::Suspicious));
    }

    #[test]
    fn test_add_to_blocklist() {
        let detector = PhishingDetector::new();
        
        detector.add_to_blocklist(&["0xbadaddress".to_string()]);
        
        let result = detector.check_address("0xbadaddress");
        assert!(result.is_flagged);
        assert_eq!(result.flag_type, Some(FlagType::Scammer));
    }

    #[test]
    fn test_case_insensitive() {
        let detector = PhishingDetector::new();
        
        // Check uppercase version of sanctioned address
        let result = detector.check_address("0x8589427373D6D84E98730D7795D8F6F8731FDA16");
        assert!(result.is_flagged);
    }
}
