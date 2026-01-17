//! Threat Detection
//!
//! Pattern-based detection of suspicious activities:
//! - Address poisoning detection
//! - Unusual transaction patterns
//! - Velocity checks
//! - Geographic anomalies
//! - Known malicious address database

use crate::error::{HawalaError, HawalaResult};
use crate::types::Chain;
use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::RwLock;
use std::time::{Duration, Instant};

/// Threat detection engine
pub struct ThreatDetector {
    /// Known malicious addresses
    blacklist: RwLock<HashSet<String>>,
    /// Trusted addresses per wallet
    whitelist: RwLock<HashMap<String, HashSet<String>>>,
    /// Transaction history for pattern analysis
    tx_history: RwLock<VecDeque<TxRecord>>,
    /// Configuration
    config: ThreatConfig,
}

/// Threat detection configuration
#[derive(Debug, Clone)]
pub struct ThreatConfig {
    /// Maximum transactions per hour before alert
    pub max_tx_per_hour: u32,
    /// Maximum unique recipients per hour
    pub max_recipients_per_hour: u32,
    /// Minimum time between transactions to same address
    pub min_tx_interval: Duration,
    /// Enable address similarity checking
    pub check_address_similarity: bool,
    /// Similarity threshold (0-100)
    pub similarity_threshold: u8,
    /// Maximum history size
    pub max_history_size: usize,
}

impl Default for ThreatConfig {
    fn default() -> Self {
        Self {
            max_tx_per_hour: 20,
            max_recipients_per_hour: 10,
            min_tx_interval: Duration::from_secs(60),
            check_address_similarity: true,
            similarity_threshold: 80,
            max_history_size: 1000,
        }
    }
}

/// Transaction record for analysis
#[derive(Debug, Clone)]
struct TxRecord {
    wallet_id: String,
    recipient: String,
    amount: u128,
    chain: Chain,
    timestamp: Instant,
}

/// Threat assessment result
#[derive(Debug, Clone)]
pub struct ThreatAssessment {
    pub risk_level: RiskLevel,
    pub threats: Vec<ThreatIndicator>,
    pub recommendations: Vec<String>,
    pub allow_transaction: bool,
}

/// Risk levels
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum RiskLevel {
    Low,
    Medium,
    High,
    Critical,
}

/// Individual threat indicators
#[derive(Debug, Clone)]
pub struct ThreatIndicator {
    pub threat_type: ThreatType,
    pub severity: RiskLevel,
    pub description: String,
    pub evidence: Option<String>,
}

/// Types of threats
#[derive(Debug, Clone, PartialEq)]
pub enum ThreatType {
    /// Address is on blacklist
    BlacklistedAddress,
    /// Address looks similar to known address (poisoning)
    AddressPoisoning,
    /// Unusual transaction velocity
    HighVelocity,
    /// Multiple recipients in short time
    BurstActivity,
    /// Duplicate transaction attempt
    DuplicateTransaction,
    /// Unusual amount pattern
    UnusualAmount,
    /// New/unknown recipient
    UnknownRecipient,
    /// Transaction to self
    SelfTransaction,
    /// Round number amount (potential scam)
    RoundAmount,
    /// Time-based anomaly
    TimeAnomaly,
}

impl ThreatDetector {
    /// Create a new threat detector
    pub fn new() -> Self {
        Self::with_config(ThreatConfig::default())
    }

    /// Create with custom configuration
    pub fn with_config(config: ThreatConfig) -> Self {
        Self {
            blacklist: RwLock::new(HashSet::new()),
            whitelist: RwLock::new(HashMap::new()),
            tx_history: RwLock::new(VecDeque::with_capacity(config.max_history_size)),
            config,
        }
    }

    /// Assess a transaction for threats
    pub fn assess_transaction(
        &self,
        wallet_id: &str,
        recipient: &str,
        amount: u128,
        chain: Chain,
        known_addresses: &[String],
    ) -> ThreatAssessment {
        let mut threats = Vec::new();
        let mut recommendations = Vec::new();

        // Check blacklist
        if self.is_blacklisted(recipient) {
            threats.push(ThreatIndicator {
                threat_type: ThreatType::BlacklistedAddress,
                severity: RiskLevel::Critical,
                description: "Recipient address is on the blacklist".to_string(),
                evidence: Some(recipient.to_string()),
            });
            recommendations.push("Do NOT proceed with this transaction".to_string());
        }

        // Check address poisoning
        if self.config.check_address_similarity {
            if let Some(similar) = self.find_similar_address(recipient, known_addresses) {
                threats.push(ThreatIndicator {
                    threat_type: ThreatType::AddressPoisoning,
                    severity: RiskLevel::High,
                    description: format!(
                        "Address is similar to known address - possible poisoning attack"
                    ),
                    evidence: Some(format!("Similar to: {}", similar)),
                });
                recommendations.push("Verify the address character by character".to_string());
            }
        }

        // Check velocity
        let velocity_threat = self.check_velocity(wallet_id);
        if let Some(threat) = velocity_threat {
            threats.push(threat);
            recommendations.push("Consider waiting before making more transactions".to_string());
        }

        // Check for burst activity
        if let Some(threat) = self.check_burst_activity(wallet_id) {
            threats.push(threat);
            recommendations.push("Multiple recipients detected - verify each carefully".to_string());
        }

        // Check for duplicate transaction
        if let Some(threat) = self.check_duplicate(wallet_id, recipient, amount) {
            threats.push(threat);
            recommendations.push("This looks like a duplicate transaction".to_string());
        }

        // Check if recipient is unknown
        if !self.is_whitelisted(wallet_id, recipient) {
            threats.push(ThreatIndicator {
                threat_type: ThreatType::UnknownRecipient,
                severity: RiskLevel::Low,
                description: "Recipient is not in your trusted addresses".to_string(),
                evidence: None,
            });
            recommendations.push("Consider adding this address to trusted list after verification".to_string());
        }

        // Check for round amounts (common in scams)
        if self.is_suspiciously_round(amount, chain) {
            threats.push(ThreatIndicator {
                threat_type: ThreatType::RoundAmount,
                severity: RiskLevel::Low,
                description: "Transaction amount is suspiciously round".to_string(),
                evidence: Some(format!("Amount: {}", amount)),
            });
        }

        // Determine overall risk level
        let risk_level = threats.iter()
            .map(|t| t.severity)
            .max()
            .unwrap_or(RiskLevel::Low);

        // Determine if transaction should be allowed
        let allow_transaction = !threats.iter().any(|t| {
            t.severity == RiskLevel::Critical ||
            t.threat_type == ThreatType::BlacklistedAddress
        });

        ThreatAssessment {
            risk_level,
            threats,
            recommendations,
            allow_transaction,
        }
    }

    /// Record a completed transaction
    pub fn record_transaction(
        &self,
        wallet_id: &str,
        recipient: &str,
        amount: u128,
        chain: Chain,
    ) {
        let record = TxRecord {
            wallet_id: wallet_id.to_string(),
            recipient: recipient.to_string(),
            amount,
            chain,
            timestamp: Instant::now(),
        };

        let mut history = self.tx_history.write().unwrap();
        
        if history.len() >= self.config.max_history_size {
            history.pop_front();
        }
        history.push_back(record);
    }

    /// Add address to blacklist
    pub fn blacklist_address(&self, address: &str) {
        let mut blacklist = self.blacklist.write().unwrap();
        blacklist.insert(normalize_address(address));
    }

    /// Remove address from blacklist
    pub fn unblacklist_address(&self, address: &str) {
        let mut blacklist = self.blacklist.write().unwrap();
        blacklist.remove(&normalize_address(address));
    }

    /// Check if address is blacklisted
    pub fn is_blacklisted(&self, address: &str) -> bool {
        let blacklist = self.blacklist.read().unwrap();
        blacklist.contains(&normalize_address(address))
    }

    /// Add address to whitelist for a wallet
    pub fn whitelist_address(&self, wallet_id: &str, address: &str) {
        let mut whitelist = self.whitelist.write().unwrap();
        whitelist
            .entry(wallet_id.to_string())
            .or_insert_with(HashSet::new)
            .insert(normalize_address(address));
    }

    /// Check if address is whitelisted
    pub fn is_whitelisted(&self, wallet_id: &str, address: &str) -> bool {
        let whitelist = self.whitelist.read().unwrap();
        whitelist
            .get(wallet_id)
            .map(|addrs| addrs.contains(&normalize_address(address)))
            .unwrap_or(false)
    }

    /// Import known malicious addresses
    pub fn import_blacklist(&self, addresses: &[String]) {
        let mut blacklist = self.blacklist.write().unwrap();
        for addr in addresses {
            blacklist.insert(normalize_address(addr));
        }
    }

    /// Find similar address (for poisoning detection)
    fn find_similar_address(&self, address: &str, known: &[String]) -> Option<String> {
        let normalized = normalize_address(address);
        
        for known_addr in known {
            let known_normalized = normalize_address(known_addr);
            
            // Skip exact matches
            if normalized == known_normalized {
                continue;
            }

            // Check similarity
            let similarity = calculate_similarity(&normalized, &known_normalized);
            if similarity >= self.config.similarity_threshold {
                return Some(known_addr.clone());
            }
        }
        
        None
    }

    /// Check transaction velocity
    fn check_velocity(&self, wallet_id: &str) -> Option<ThreatIndicator> {
        let history = self.tx_history.read().unwrap();
        let one_hour_ago = Instant::now() - Duration::from_secs(3600);
        
        let recent_count = history.iter()
            .filter(|tx| tx.wallet_id == wallet_id && tx.timestamp > one_hour_ago)
            .count() as u32;

        if recent_count >= self.config.max_tx_per_hour {
            Some(ThreatIndicator {
                threat_type: ThreatType::HighVelocity,
                severity: RiskLevel::Medium,
                description: format!(
                    "High transaction velocity: {} transactions in the last hour",
                    recent_count
                ),
                evidence: Some(format!("Threshold: {}", self.config.max_tx_per_hour)),
            })
        } else {
            None
        }
    }

    /// Check for burst activity (many recipients)
    fn check_burst_activity(&self, wallet_id: &str) -> Option<ThreatIndicator> {
        let history = self.tx_history.read().unwrap();
        let one_hour_ago = Instant::now() - Duration::from_secs(3600);
        
        let unique_recipients: HashSet<_> = history.iter()
            .filter(|tx| tx.wallet_id == wallet_id && tx.timestamp > one_hour_ago)
            .map(|tx| &tx.recipient)
            .collect();

        if unique_recipients.len() as u32 >= self.config.max_recipients_per_hour {
            Some(ThreatIndicator {
                threat_type: ThreatType::BurstActivity,
                severity: RiskLevel::Medium,
                description: format!(
                    "Transactions to {} unique addresses in the last hour",
                    unique_recipients.len()
                ),
                evidence: Some(format!("Threshold: {}", self.config.max_recipients_per_hour)),
            })
        } else {
            None
        }
    }

    /// Check for duplicate transaction
    fn check_duplicate(&self, wallet_id: &str, recipient: &str, amount: u128) -> Option<ThreatIndicator> {
        let history = self.tx_history.read().unwrap();
        let recipient_normalized = normalize_address(recipient);
        
        for tx in history.iter().rev().take(10) {
            if tx.wallet_id == wallet_id
                && normalize_address(&tx.recipient) == recipient_normalized
                && tx.amount == amount
                && tx.timestamp.elapsed() < self.config.min_tx_interval
            {
                return Some(ThreatIndicator {
                    threat_type: ThreatType::DuplicateTransaction,
                    severity: RiskLevel::High,
                    description: "This transaction appears to be a duplicate".to_string(),
                    evidence: Some(format!(
                        "Same recipient and amount {} seconds ago",
                        tx.timestamp.elapsed().as_secs()
                    )),
                });
            }
        }
        
        None
    }

    /// Check if amount is suspiciously round
    fn is_suspiciously_round(&self, amount: u128, chain: Chain) -> bool {
        let decimals = match chain {
            Chain::Bitcoin | Chain::BitcoinTestnet | Chain::Litecoin => 8,
            Chain::Ethereum | Chain::EthereumSepolia | Chain::Bnb | Chain::Polygon
            | Chain::Arbitrum | Chain::Optimism | Chain::Base | Chain::Avalanche => 18,
            _ => return false,
        };

        let divisor = 10u128.pow(decimals as u32 - 2); // Check if divisible by 0.01
        amount > 0 && amount % divisor == 0
    }
}

impl Default for ThreatDetector {
    fn default() -> Self {
        Self::new()
    }
}

/// Normalize address for comparison
fn normalize_address(address: &str) -> String {
    address.trim().to_lowercase()
}

/// Calculate similarity between two addresses (0-100)
fn calculate_similarity(a: &str, b: &str) -> u8 {
    if a.len() != b.len() {
        // Different lengths - check prefix/suffix similarity
        let min_len = a.len().min(b.len());
        if min_len < 8 {
            return 0;
        }

        // Check if prefix matches (first 6 chars)
        let prefix_match = a.chars().take(6).zip(b.chars().take(6))
            .filter(|(x, y)| x == y)
            .count();
        
        // Check if suffix matches (last 4 chars)
        let suffix_match = a.chars().rev().take(4).zip(b.chars().rev().take(4))
            .filter(|(x, y)| x == y)
            .count();

        // Poisoning typically matches prefix and suffix
        if prefix_match >= 4 && suffix_match >= 3 {
            return 85;
        }
        
        return ((prefix_match + suffix_match) * 10) as u8;
    }

    // Same length - count matching characters
    let matches = a.chars().zip(b.chars())
        .filter(|(x, y)| x == y)
        .count();

    ((matches * 100) / a.len()) as u8
}

/// Global threat detector instance
static THREAT_DETECTOR: std::sync::OnceLock<ThreatDetector> = std::sync::OnceLock::new();

/// Get the global threat detector
pub fn get_threat_detector() -> &'static ThreatDetector {
    THREAT_DETECTOR.get_or_init(ThreatDetector::new)
}

/// Assess a transaction for threats (convenience function)
pub fn assess_transaction(
    wallet_id: &str,
    recipient: &str,
    amount: u128,
    chain: Chain,
    known_addresses: &[String],
) -> ThreatAssessment {
    get_threat_detector().assess_transaction(wallet_id, recipient, amount, chain, known_addresses)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_blacklist() {
        let detector = ThreatDetector::new();
        
        detector.blacklist_address("0xbad123");
        assert!(detector.is_blacklisted("0xbad123"));
        assert!(detector.is_blacklisted("0xBAD123")); // Case insensitive
        
        detector.unblacklist_address("0xbad123");
        assert!(!detector.is_blacklisted("0xbad123"));
    }

    #[test]
    fn test_whitelist() {
        let detector = ThreatDetector::new();
        
        detector.whitelist_address("wallet1", "0xgood123");
        assert!(detector.is_whitelisted("wallet1", "0xgood123"));
        assert!(!detector.is_whitelisted("wallet2", "0xgood123"));
    }

    #[test]
    fn test_similarity() {
        // Very similar (poisoning attempt)
        let sim = calculate_similarity(
            "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5abc"
        );
        assert!(sim > 90);

        // Different
        let sim = calculate_similarity(
            "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            "bc1qcompletely_different_addressxyz123456"
        );
        assert!(sim < 50);
    }

    #[test]
    fn test_threat_assessment_blacklist() {
        let detector = ThreatDetector::new();
        detector.blacklist_address("0xmalicious");

        let assessment = detector.assess_transaction(
            "wallet1",
            "0xmalicious",
            1000,
            Chain::Ethereum,
            &[]
        );

        assert_eq!(assessment.risk_level, RiskLevel::Critical);
        assert!(!assessment.allow_transaction);
        assert!(assessment.threats.iter().any(|t| t.threat_type == ThreatType::BlacklistedAddress));
    }

    #[test]
    fn test_threat_assessment_unknown_recipient() {
        let detector = ThreatDetector::new();

        let assessment = detector.assess_transaction(
            "wallet1",
            "0xunknown",
            1000,
            Chain::Ethereum,
            &[]
        );

        assert!(assessment.threats.iter().any(|t| t.threat_type == ThreatType::UnknownRecipient));
        assert!(assessment.allow_transaction); // Unknown is low risk
    }

    #[test]
    fn test_duplicate_detection() {
        let detector = ThreatDetector::new();
        
        // Record first transaction
        detector.record_transaction("wallet1", "0xrecipient", 1000, Chain::Ethereum);

        // Assess same transaction again
        let assessment = detector.assess_transaction(
            "wallet1",
            "0xrecipient",
            1000,
            Chain::Ethereum,
            &[]
        );

        assert!(assessment.threats.iter().any(|t| t.threat_type == ThreatType::DuplicateTransaction));
    }

    #[test]
    fn test_address_poisoning_detection() {
        let detector = ThreatDetector::new();
        
        let known = vec!["bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq".to_string()];
        
        // Similar address (poisoning attempt)
        let assessment = detector.assess_transaction(
            "wallet1",
            "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5abc",
            1000,
            Chain::Bitcoin,
            &known
        );

        assert!(assessment.threats.iter().any(|t| t.threat_type == ThreatType::AddressPoisoning));
    }
}
