//! Token Approval Manager
//!
//! Manages ERC-20 token approvals (allowances):
//! - Fetch all approvals for an address
//! - Revoke individual approvals
//! - Batch revoke multiple approvals
//! - Risk assessment for approvals
//!
//! Inspired by Rabby, Revoke.cash

use crate::error::{HawalaError, HawalaResult, ErrorCode};
use crate::types::Chain;
use serde::{Deserialize, Serialize};
use std::time::Duration;

// =============================================================================
// Types
// =============================================================================

/// A token approval (allowance)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TokenApproval {
    /// Token contract address
    pub token_address: String,
    /// Token symbol
    pub symbol: String,
    /// Token name
    pub name: String,
    /// Token decimals
    pub decimals: u8,
    /// Contract that has approval (spender)
    pub spender_address: String,
    /// Known name of spender (e.g., "Uniswap V3 Router")
    pub spender_name: Option<String>,
    /// Spender protocol (e.g., "Uniswap", "OpenSea")
    pub spender_protocol: Option<String>,
    /// Approved amount (or "Unlimited")
    pub allowance: String,
    /// Raw allowance in wei
    pub allowance_raw: String,
    /// Whether this is an unlimited approval
    pub is_unlimited: bool,
    /// USD value at risk
    pub value_at_risk_usd: Option<String>,
    /// When the approval was last used (if known)
    pub last_used: Option<u64>,
    /// Risk level assessment
    pub risk_level: ApprovalRiskLevel,
    /// Risk reasons
    pub risk_reasons: Vec<String>,
    /// Chain where approval exists
    pub chain: Chain,
}

/// Risk level for an approval
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "snake_case")]
pub enum ApprovalRiskLevel {
    Low,
    Medium,
    High,
    Critical,
}

/// Request to fetch approvals
#[derive(Debug, Clone, Deserialize)]
pub struct GetApprovalsRequest {
    /// Address to check approvals for
    pub address: String,
    /// Chain to check
    pub chain: Chain,
}

/// Result of fetching approvals
#[derive(Debug, Clone, Serialize)]
pub struct GetApprovalsResult {
    /// All approvals found
    pub approvals: Vec<TokenApproval>,
    /// Total number of approvals
    pub total_count: usize,
    /// Number of unlimited approvals
    pub unlimited_count: usize,
    /// Number of high-risk approvals
    pub high_risk_count: usize,
    /// Total USD value at risk
    pub total_value_at_risk_usd: Option<String>,
}

/// Request to revoke an approval
#[derive(Debug, Clone, Deserialize)]
pub struct RevokeRequest {
    /// Token address to revoke approval for
    pub token_address: String,
    /// Spender address to revoke
    pub spender_address: String,
    /// Chain
    pub chain: Chain,
}

/// Revoke transaction data
#[derive(Debug, Clone, Serialize)]
pub struct RevokeTransaction {
    /// Contract to call (token address)
    pub to: String,
    /// Transaction data (approve(spender, 0))
    pub data: String,
    /// Estimated gas
    pub gas_limit: u64,
}

/// Request to batch revoke multiple approvals
#[derive(Debug, Clone, Deserialize)]
pub struct BatchRevokeRequest {
    /// Approvals to revoke (token, spender pairs)
    pub approvals: Vec<(String, String)>,
    /// Chain
    pub chain: Chain,
}

// =============================================================================
// Approval Manager
// =============================================================================

/// Manages token approvals across chains
pub struct ApprovalManager {
    /// Known spender contracts
    known_spenders: std::collections::HashMap<String, SpenderInfo>,
}

#[derive(Debug, Clone)]
struct SpenderInfo {
    name: String,
    protocol: Option<String>,
    is_trusted: bool,
}

impl ApprovalManager {
    /// Create a new approval manager
    pub fn new() -> Self {
        let mut known_spenders = std::collections::HashMap::new();
        
        // Ethereum mainnet known spenders
        Self::add_known_spender(&mut known_spenders, 
            "0x7a250d5630b4cf539739df2c5dacb4c659f2488d", 
            "Uniswap V2 Router", Some("Uniswap"), true);
        Self::add_known_spender(&mut known_spenders,
            "0xe592427a0aece92de3edee1f18e0157c05861564",
            "Uniswap V3 Router", Some("Uniswap"), true);
        Self::add_known_spender(&mut known_spenders,
            "0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45",
            "Uniswap V3 Router 2", Some("Uniswap"), true);
        Self::add_known_spender(&mut known_spenders,
            "0x000000000022d473030f116ddee9f6b43ac78ba3",
            "Uniswap Permit2", Some("Uniswap"), true);
        Self::add_known_spender(&mut known_spenders,
            "0x1111111254eeb25477b68fb85ed929f73a960582",
            "1inch V5 Router", Some("1inch"), true);
        Self::add_known_spender(&mut known_spenders,
            "0x00000000006c3852cbef3e08e8df289169ede581",
            "OpenSea Seaport 1.1", Some("OpenSea"), true);
        Self::add_known_spender(&mut known_spenders,
            "0x00000000000000adc04c56bf30ac9d3c0aaf14dc",
            "OpenSea Seaport 1.5", Some("OpenSea"), true);
        Self::add_known_spender(&mut known_spenders,
            "0xdef1c0ded9bec7f1a1670819833240f027b25eff",
            "0x Exchange Proxy", Some("0x"), true);
        Self::add_known_spender(&mut known_spenders,
            "0xae7ab96520de3a18e5e111b5eaab095312d7fe84",
            "Lido stETH", Some("Lido"), true);
        Self::add_known_spender(&mut known_spenders,
            "0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0",
            "Lido wstETH", Some("Lido"), true);
        Self::add_known_spender(&mut known_spenders,
            "0x7d2768de32b0b80b7a3454c06bdac94a69ddc7a9",
            "Aave V2 Pool", Some("Aave"), true);
        Self::add_known_spender(&mut known_spenders,
            "0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2",
            "Aave V3 Pool", Some("Aave"), true);
        
        Self { known_spenders }
    }

    fn add_known_spender(
        map: &mut std::collections::HashMap<String, SpenderInfo>,
        address: &str,
        name: &str,
        protocol: Option<&str>,
        is_trusted: bool,
    ) {
        map.insert(address.to_lowercase(), SpenderInfo {
            name: name.to_string(),
            protocol: protocol.map(|s| s.to_string()),
            is_trusted,
        });
    }

    /// Get all token approvals for an address
    pub fn get_approvals(&self, request: &GetApprovalsRequest) -> HawalaResult<GetApprovalsResult> {
        let chain_id = request.chain.chain_id()
            .ok_or_else(|| HawalaError::new(ErrorCode::InvalidInput, "Unsupported chain"))?;
        
        // For production, this would query an indexer like:
        // - Etherscan API (eth_getApprovals endpoint)
        // - Covalent API
        // - Custom indexer
        
        // For now, return empty result (would need API integration)
        // In a real implementation, we'd query approval events:
        // event Approval(address indexed owner, address indexed spender, uint256 value)
        
        let approvals = self.fetch_approvals_from_api(&request.address, chain_id)?;
        
        let unlimited_count = approvals.iter().filter(|a| a.is_unlimited).count();
        let high_risk_count = approvals.iter().filter(|a| a.risk_level >= ApprovalRiskLevel::High).count();
        
        Ok(GetApprovalsResult {
            total_count: approvals.len(),
            unlimited_count,
            high_risk_count,
            total_value_at_risk_usd: None, // Would calculate from token prices
            approvals,
        })
    }

    /// Create a revoke transaction (set allowance to 0)
    pub fn create_revoke_transaction(&self, request: &RevokeRequest) -> HawalaResult<RevokeTransaction> {
        // ERC-20 approve(address spender, uint256 amount)
        // Function selector: 0x095ea7b3
        // Set amount to 0 to revoke
        
        let spender_padded = format!("{:0>64}", request.spender_address.trim_start_matches("0x"));
        let amount_padded = "0000000000000000000000000000000000000000000000000000000000000000";
        
        let data = format!("0x095ea7b3{}{}", spender_padded, amount_padded);
        
        Ok(RevokeTransaction {
            to: request.token_address.clone(),
            data,
            gas_limit: 65000,
        })
    }

    /// Create batch revoke transactions
    pub fn create_batch_revoke_transactions(&self, request: &BatchRevokeRequest) -> HawalaResult<Vec<RevokeTransaction>> {
        let mut transactions = Vec::new();
        
        for (token, spender) in &request.approvals {
            let revoke_request = RevokeRequest {
                token_address: token.clone(),
                spender_address: spender.clone(),
                chain: request.chain,
            };
            transactions.push(self.create_revoke_transaction(&revoke_request)?);
        }
        
        Ok(transactions)
    }

    /// Assess risk of an approval
    pub fn assess_approval_risk(
        &self,
        spender: &str,
        is_unlimited: bool,
        token_balance_usd: Option<f64>,
    ) -> (ApprovalRiskLevel, Vec<String>) {
        let mut risk_level = ApprovalRiskLevel::Low;
        let mut reasons = Vec::new();
        
        let spender_lower = spender.to_lowercase();
        
        // Check if spender is known
        if let Some(info) = self.known_spenders.get(&spender_lower) {
            if info.is_trusted {
                // Known trusted spender - lower risk
            } else {
                reasons.push(format!("Spender {} is not in trusted list", info.name));
                risk_level = ApprovalRiskLevel::Medium;
            }
        } else {
            // Unknown spender
            reasons.push("Unknown spender contract".to_string());
            risk_level = ApprovalRiskLevel::Medium;
        }
        
        // Unlimited approval increases risk
        if is_unlimited {
            reasons.push("Unlimited approval - spender can take all tokens".to_string());
            if risk_level < ApprovalRiskLevel::Medium {
                risk_level = ApprovalRiskLevel::Medium;
            }
        }
        
        // High value at risk
        if let Some(usd) = token_balance_usd {
            if usd > 10000.0 {
                reasons.push(format!("High value at risk: ${:.2}", usd));
                if risk_level < ApprovalRiskLevel::High {
                    risk_level = ApprovalRiskLevel::High;
                }
            } else if usd > 1000.0 {
                reasons.push(format!("Significant value at risk: ${:.2}", usd));
            }
        }
        
        // Unknown + unlimited = high risk
        if !self.known_spenders.contains_key(&spender_lower) && is_unlimited {
            risk_level = ApprovalRiskLevel::High;
        }
        
        (risk_level, reasons)
    }

    /// Get spender info if known
    pub fn get_spender_info(&self, spender: &str) -> Option<(String, Option<String>)> {
        self.known_spenders.get(&spender.to_lowercase())
            .map(|info| (info.name.clone(), info.protocol.clone()))
    }

    // =========================================================================
    // Private Methods
    // =========================================================================

    fn fetch_approvals_from_api(&self, address: &str, chain_id: u64) -> HawalaResult<Vec<TokenApproval>> {
        // In production, this would call an API like:
        // - Etherscan: GET /api?module=account&action=tokenapprovelist
        // - Covalent: GET /v1/{chain_id}/address/{address}/approvals/
        // - Custom indexer
        
        // For now, we'll implement a basic version using eth_getLogs
        // to find Approval events for the user's address
        
        let rpc_url = self.get_rpc_url(chain_id);
        
        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .map_err(|e| HawalaError::network_error(format!("Failed to create client: {}", e)))?;
        
        // Query Approval events where owner = address
        // event Approval(address indexed owner, address indexed spender, uint256 value)
        // Topic0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
        
        let owner_topic = format!("0x000000000000000000000000{}", address.trim_start_matches("0x"));
        
        let payload = serde_json::json!({
            "jsonrpc": "2.0",
            "method": "eth_getLogs",
            "params": [{
                "fromBlock": "earliest",
                "toBlock": "latest",
                "topics": [
                    "0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925",
                    owner_topic
                ]
            }],
            "id": 1
        });
        
        let response = client
            .post(&rpc_url)
            .json(&payload)
            .send();
        
        match response {
            Ok(resp) => {
                let json: serde_json::Value = resp.json()
                    .map_err(|e| HawalaError::parse_error(format!("Failed to parse response: {}", e)))?;
                
                if let Some(logs) = json["result"].as_array() {
                    return self.parse_approval_logs(logs, Chain::from_chain_id(chain_id));
                }
            }
            Err(e) => {
                // Log error but don't fail - return empty list
                eprintln!("Failed to fetch approvals: {}", e);
            }
        }
        
        Ok(Vec::new())
    }

    fn parse_approval_logs(&self, logs: &[serde_json::Value], chain: Chain) -> HawalaResult<Vec<TokenApproval>> {
        let mut approvals_map: std::collections::HashMap<(String, String), TokenApproval> = std::collections::HashMap::new();
        
        for log in logs {
            let token_address = log["address"].as_str().unwrap_or_default().to_lowercase();
            let topics = log["topics"].as_array();
            let data = log["data"].as_str().unwrap_or("0x");
            
            if let Some(topics) = topics {
                if topics.len() >= 3 {
                    let spender = format!("0x{}", topics[2].as_str().unwrap_or_default().trim_start_matches("0x").get(24..).unwrap_or_default());
                    
                    // Parse allowance from data
                    let allowance_raw = data.trim_start_matches("0x");
                    let is_unlimited = allowance_raw == "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
                    let allowance = if is_unlimited {
                        "Unlimited".to_string()
                    } else if allowance_raw.is_empty() || allowance_raw == "0" || allowance_raw.chars().all(|c| c == '0') {
                        "0".to_string()
                    } else {
                        allowance_raw.to_string()
                    };
                    
                    // Skip revoked approvals (allowance = 0)
                    if allowance == "0" {
                        approvals_map.remove(&(token_address.clone(), spender.clone()));
                        continue;
                    }
                    
                    let (spender_name, spender_protocol) = self.get_spender_info(&spender)
                        .map(|(n, p)| (Some(n), p))
                        .unwrap_or((None, None));
                    
                    let (risk_level, risk_reasons) = self.assess_approval_risk(&spender, is_unlimited, None);
                    
                    let approval = TokenApproval {
                        token_address: token_address.clone(),
                        symbol: "?".to_string(), // Would need to fetch
                        name: "Unknown Token".to_string(), // Would need to fetch
                        decimals: 18,
                        spender_address: spender.clone(),
                        spender_name,
                        spender_protocol,
                        allowance,
                        allowance_raw: allowance_raw.to_string(),
                        is_unlimited,
                        value_at_risk_usd: None,
                        last_used: None,
                        risk_level,
                        risk_reasons,
                        chain,
                    };
                    
                    // Update map (later events override earlier)
                    approvals_map.insert((token_address, spender), approval);
                }
            }
        }
        
        Ok(approvals_map.into_values().collect())
    }

    fn get_rpc_url(&self, chain_id: u64) -> String {
        match chain_id {
            1 => "https://eth.llamarpc.com".to_string(),
            56 => "https://bsc-dataseed.binance.org".to_string(),
            137 => "https://polygon-rpc.com".to_string(),
            42161 => "https://arb1.arbitrum.io/rpc".to_string(),
            10 => "https://mainnet.optimism.io".to_string(),
            8453 => "https://mainnet.base.org".to_string(),
            43114 => "https://api.avax.network/ext/bc/C/rpc".to_string(),
            _ => "https://eth.llamarpc.com".to_string(),
        }
    }
}

impl Default for ApprovalManager {
    fn default() -> Self {
        Self::new()
    }
}

// =============================================================================
// Chain Helper
// =============================================================================

impl Chain {
    /// Get chain from chain ID
    pub fn from_chain_id(chain_id: u64) -> Self {
        match chain_id {
            1 => Chain::Ethereum,
            56 => Chain::Bnb,
            137 => Chain::Polygon,
            42161 => Chain::Arbitrum,
            10 => Chain::Optimism,
            8453 => Chain::Base,
            43114 => Chain::Avalanche,
            11155111 => Chain::EthereumSepolia,
            _ => Chain::Ethereum,
        }
    }
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_manager() {
        let manager = ApprovalManager::new();
        assert!(!manager.known_spenders.is_empty());
    }

    #[test]
    fn test_get_spender_info() {
        let manager = ApprovalManager::new();
        
        // Known spender
        let info = manager.get_spender_info("0x7a250d5630b4cf539739df2c5dacb4c659f2488d");
        assert!(info.is_some());
        let (name, protocol) = info.unwrap();
        assert_eq!(name, "Uniswap V2 Router");
        assert_eq!(protocol, Some("Uniswap".to_string()));
        
        // Unknown spender
        let info = manager.get_spender_info("0x1234567890123456789012345678901234567890");
        assert!(info.is_none());
    }

    #[test]
    fn test_assess_risk_known_spender() {
        let manager = ApprovalManager::new();
        
        // Known trusted spender, not unlimited
        let (level, reasons) = manager.assess_approval_risk(
            "0x7a250d5630b4cf539739df2c5dacb4c659f2488d",
            false,
            Some(100.0),
        );
        assert_eq!(level, ApprovalRiskLevel::Low);
        assert!(reasons.is_empty());
    }

    #[test]
    fn test_assess_risk_unknown_unlimited() {
        let manager = ApprovalManager::new();
        
        // Unknown spender, unlimited approval
        let (level, reasons) = manager.assess_approval_risk(
            "0x0000000000000000000000000000000000000001",
            true,
            Some(100.0),
        );
        assert_eq!(level, ApprovalRiskLevel::High);
        assert!(!reasons.is_empty());
    }

    #[test]
    fn test_create_revoke_transaction() {
        let manager = ApprovalManager::new();
        
        let request = RevokeRequest {
            token_address: "0xdac17f958d2ee523a2206206994597c13d831ec7".to_string(),
            spender_address: "0x7a250d5630b4cf539739df2c5dacb4c659f2488d".to_string(),
            chain: Chain::Ethereum,
        };
        
        let tx = manager.create_revoke_transaction(&request).unwrap();
        
        // Check it's an approve call
        assert!(tx.data.starts_with("0x095ea7b3"));
        // Check amount is 0
        assert!(tx.data.ends_with("0000000000000000000000000000000000000000000000000000000000000000"));
    }

    #[test]
    fn test_batch_revoke() {
        let manager = ApprovalManager::new();
        
        let request = BatchRevokeRequest {
            approvals: vec![
                ("0xtoken1".to_string(), "0xspender1".to_string()),
                ("0xtoken2".to_string(), "0xspender2".to_string()),
            ],
            chain: Chain::Ethereum,
        };
        
        let txs = manager.create_batch_revoke_transactions(&request).unwrap();
        assert_eq!(txs.len(), 2);
    }
}
