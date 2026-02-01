//! Transaction Simulation & Preview
//!
//! Simulates EVM transactions before execution to show users
//! what will happen (balance changes, approvals, risks).
//! Inspired by Rabby, Blowfish, Pocket Universe.

use crate::error::{HawalaError, HawalaResult, ErrorCode};
use crate::types::Chain;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::Duration;

// =============================================================================
// Types
// =============================================================================

/// Result of simulating a transaction
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimulationResult {
    /// Whether the transaction would succeed
    pub success: bool,
    /// Gas that would be used
    pub gas_used: u64,
    /// Changes to token balances
    pub balance_changes: Vec<BalanceChange>,
    /// Token approvals being set
    pub token_approvals: Vec<TokenApprovalChange>,
    /// NFT transfers
    pub nft_transfers: Vec<NFTTransfer>,
    /// Contract interactions
    pub contract_interactions: Vec<ContractInteraction>,
    /// Warnings and risks detected
    pub warnings: Vec<SimulationWarning>,
    /// Overall risk assessment
    pub risk_level: SimulationRiskLevel,
    /// Human-readable summary
    pub summary: String,
}

/// A change in token balance
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BalanceChange {
    /// Token contract address (or "native" for ETH/BNB/etc)
    pub token_address: String,
    /// Token symbol (ETH, USDC, etc)
    pub symbol: String,
    /// Token name
    pub name: String,
    /// Decimals
    pub decimals: u8,
    /// Amount change (negative = outgoing, positive = incoming)
    pub amount: String,
    /// Amount in raw units
    pub raw_amount: String,
    /// USD value of the change
    pub usd_value: Option<String>,
    /// Direction of the change
    pub direction: TransferDirection,
}

/// Direction of a transfer
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum TransferDirection {
    Incoming,
    Outgoing,
}

/// A token approval being set or changed
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TokenApprovalChange {
    /// Token being approved
    pub token_address: String,
    /// Token symbol
    pub symbol: String,
    /// Contract being given approval
    pub spender_address: String,
    /// Known name of spender (e.g., "Uniswap V3 Router")
    pub spender_name: Option<String>,
    /// New allowance amount
    pub new_allowance: String,
    /// Whether this is unlimited approval
    pub is_unlimited: bool,
    /// Previous allowance (if known)
    pub previous_allowance: Option<String>,
    /// Risk level of this approval
    pub risk_level: SimulationRiskLevel,
}

/// An NFT transfer
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NFTTransfer {
    /// NFT contract address
    pub contract_address: String,
    /// Collection name
    pub collection_name: Option<String>,
    /// Token ID
    pub token_id: String,
    /// Direction
    pub direction: TransferDirection,
    /// From address
    pub from: String,
    /// To address
    pub to: String,
    /// Floor price in USD (if known)
    pub floor_price_usd: Option<String>,
}

/// A contract interaction
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContractInteraction {
    /// Contract address
    pub address: String,
    /// Contract name (if known)
    pub name: Option<String>,
    /// Function being called
    pub function_name: Option<String>,
    /// Whether contract is verified
    pub is_verified: bool,
    /// Whether contract is a known protocol
    pub is_known_protocol: bool,
    /// Protocol name (e.g., "Uniswap", "Aave")
    pub protocol: Option<String>,
}

/// A simulation warning
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimulationWarning {
    /// Severity of the warning
    pub severity: SimulationRiskLevel,
    /// Warning type code
    pub code: WarningCode,
    /// Human-readable message
    pub message: String,
    /// Additional details
    pub details: Option<String>,
    /// Whether this should block the transaction
    pub should_block: bool,
}

/// Warning type codes
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum WarningCode {
    /// Unlimited token approval
    UnlimitedApproval,
    /// Approval to unknown contract
    UnknownSpender,
    /// Sending all tokens
    DrainAttempt,
    /// Known scam contract
    KnownScam,
    /// Contract recently deployed
    NewContract,
    /// Unusual function call
    UnusualFunction,
    /// High gas usage
    HighGas,
    /// Transaction would fail
    WouldFail,
    /// Sending to contract
    SendingToContract,
    /// Honeypot token
    HoneypotToken,
    /// Sanctioned address
    SanctionedAddress,
    /// Approval without spending
    ApprovalOnly,
    /// Unusual amount pattern
    UnusualAmount,
    /// Multiple approvals
    MultipleApprovals,
    /// setApprovalForAll
    ApprovalForAll,
}

/// Risk level assessment for simulation
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "snake_case")]
pub enum SimulationRiskLevel {
    Safe,
    Low,
    Medium,
    High,
    Critical,
}

/// Request to simulate a transaction
#[derive(Debug, Clone, Deserialize)]
pub struct SimulationRequest {
    /// Chain to simulate on
    pub chain: Chain,
    /// From address
    pub from: String,
    /// To address  
    pub to: String,
    /// Value in wei (hex)
    pub value: String,
    /// Transaction data (hex)
    pub data: String,
    /// Gas limit (optional)
    pub gas_limit: Option<u64>,
}

// =============================================================================
// Transaction Simulator
// =============================================================================

/// Transaction simulator for previewing transaction effects
pub struct TransactionSimulator {
    /// Known contract labels
    known_contracts: HashMap<String, ContractInfo>,
    /// Known scam addresses
    scam_addresses: std::collections::HashSet<String>,
}

#[derive(Debug, Clone)]
struct ContractInfo {
    name: String,
    protocol: Option<String>,
    is_verified: bool,
}

impl TransactionSimulator {
    /// Create a new transaction simulator
    pub fn new() -> Self {
        let mut known_contracts = HashMap::new();
        
        // Add known contracts (Ethereum mainnet)
        known_contracts.insert(
            "0x7a250d5630b4cf539739df2c5dacb4c659f2488d".to_lowercase(),
            ContractInfo {
                name: "Uniswap V2 Router".to_string(),
                protocol: Some("Uniswap".to_string()),
                is_verified: true,
            },
        );
        known_contracts.insert(
            "0xe592427a0aece92de3edee1f18e0157c05861564".to_lowercase(),
            ContractInfo {
                name: "Uniswap V3 Router".to_string(),
                protocol: Some("Uniswap".to_string()),
                is_verified: true,
            },
        );
        known_contracts.insert(
            "0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45".to_lowercase(),
            ContractInfo {
                name: "Uniswap V3 Router 2".to_string(),
                protocol: Some("Uniswap".to_string()),
                is_verified: true,
            },
        );
        known_contracts.insert(
            "0x1111111254eeb25477b68fb85ed929f73a960582".to_lowercase(),
            ContractInfo {
                name: "1inch V5 Router".to_string(),
                protocol: Some("1inch".to_string()),
                is_verified: true,
            },
        );
        known_contracts.insert(
            "0x00000000006c3852cbef3e08e8df289169ede581".to_lowercase(),
            ContractInfo {
                name: "OpenSea Seaport 1.1".to_string(),
                protocol: Some("OpenSea".to_string()),
                is_verified: true,
            },
        );
        known_contracts.insert(
            "0xae7ab96520de3a18e5e111b5eaab095312d7fe84".to_lowercase(),
            ContractInfo {
                name: "Lido stETH".to_string(),
                protocol: Some("Lido".to_string()),
                is_verified: true,
            },
        );
        known_contracts.insert(
            "0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0".to_lowercase(),
            ContractInfo {
                name: "Lido wstETH".to_string(),
                protocol: Some("Lido".to_string()),
                is_verified: true,
            },
        );
        known_contracts.insert(
            "0x000000000022d473030f116ddee9f6b43ac78ba3".to_lowercase(),
            ContractInfo {
                name: "Uniswap Permit2".to_string(),
                protocol: Some("Uniswap".to_string()),
                is_verified: true,
            },
        );
        
        Self {
            known_contracts,
            scam_addresses: std::collections::HashSet::new(),
        }
    }

    /// Simulate a transaction and return the result
    pub fn simulate(&self, request: &SimulationRequest) -> HawalaResult<SimulationResult> {
        let chain_id = request.chain.chain_id()
            .ok_or_else(|| HawalaError::new(ErrorCode::InvalidInput, "Unsupported chain"))?;
        
        // Get RPC endpoint
        let rpc_url = self.get_rpc_endpoint(chain_id);
        
        // Call eth_call to simulate
        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(15))
            .build()
            .map_err(|e| HawalaError::network_error(format!("Failed to create client: {}", e)))?;
        
        // Simulate with eth_call
        let call_result = self.simulate_via_eth_call(&client, &rpc_url, request);
        
        // Parse transaction data to understand what's happening
        let analysis = self.analyze_transaction_data(request)?;
        
        // Build the result
        let mut warnings = analysis.warnings.clone();
        let mut risk_level = SimulationRiskLevel::Safe;
        
        // Check if simulation succeeded
        let success = call_result.is_ok();
        
        // Add warnings based on analysis
        if !success {
            warnings.push(SimulationWarning {
                severity: SimulationRiskLevel::High,
                code: WarningCode::WouldFail,
                message: "Transaction would fail".to_string(),
                details: call_result.clone().err(),
                should_block: true,
            });
            risk_level = SimulationRiskLevel::High;
        }
        
        // Check for unlimited approvals
        for approval in &analysis.token_approvals {
            if approval.is_unlimited {
                warnings.push(SimulationWarning {
                    severity: SimulationRiskLevel::Medium,
                    code: WarningCode::UnlimitedApproval,
                    message: format!("Unlimited approval for {}", approval.symbol),
                    details: Some(format!("Spender: {}", approval.spender_name.as_deref().unwrap_or(&approval.spender_address))),
                    should_block: false,
                });
                if risk_level < SimulationRiskLevel::Medium {
                    risk_level = SimulationRiskLevel::Medium;
                }
            }
        }
        
        // Check for setApprovalForAll
        if analysis.has_approval_for_all {
            warnings.push(SimulationWarning {
                severity: SimulationRiskLevel::High,
                code: WarningCode::ApprovalForAll,
                message: "setApprovalForAll detected - gives access to ALL your NFTs".to_string(),
                details: None,
                should_block: false,
            });
            if risk_level < SimulationRiskLevel::High {
                risk_level = SimulationRiskLevel::High;
            }
        }
        
        // Check for scam addresses
        let to_lower = request.to.to_lowercase();
        if self.scam_addresses.contains(&to_lower) {
            warnings.push(SimulationWarning {
                severity: SimulationRiskLevel::Critical,
                code: WarningCode::KnownScam,
                message: "Known scam address detected!".to_string(),
                details: Some("This address has been reported as a scam. Do not proceed.".to_string()),
                should_block: true,
            });
            risk_level = SimulationRiskLevel::Critical;
        }
        
        // Build summary
        let summary = self.build_summary(&analysis, &warnings, success);
        
        Ok(SimulationResult {
            success,
            gas_used: analysis.estimated_gas,
            balance_changes: analysis.balance_changes,
            token_approvals: analysis.token_approvals,
            nft_transfers: analysis.nft_transfers,
            contract_interactions: analysis.contract_interactions,
            warnings,
            risk_level,
            summary,
        })
    }

    /// Analyze transaction risk without full simulation
    pub fn analyze_risk(&self, request: &SimulationRequest) -> HawalaResult<Vec<SimulationWarning>> {
        let analysis = self.analyze_transaction_data(request)?;
        Ok(analysis.warnings)
    }

    /// Add addresses to scam list
    pub fn add_scam_addresses(&mut self, addresses: &[String]) {
        for addr in addresses {
            self.scam_addresses.insert(addr.to_lowercase());
        }
    }

    /// Check if an address is a known scam
    pub fn is_scam_address(&self, address: &str) -> bool {
        self.scam_addresses.contains(&address.to_lowercase())
    }

    // =========================================================================
    // Private Methods
    // =========================================================================

    fn get_rpc_endpoint(&self, chain_id: u64) -> String {
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

    fn simulate_via_eth_call(
        &self,
        client: &reqwest::blocking::Client,
        rpc_url: &str,
        request: &SimulationRequest,
    ) -> Result<String, String> {
        let payload = serde_json::json!({
            "jsonrpc": "2.0",
            "method": "eth_call",
            "params": [{
                "from": request.from,
                "to": request.to,
                "value": request.value,
                "data": request.data,
                "gas": request.gas_limit.map(|g| format!("0x{:x}", g)),
            }, "latest"],
            "id": 1
        });

        let response = client
            .post(rpc_url)
            .json(&payload)
            .send()
            .map_err(|e| e.to_string())?;

        let json: serde_json::Value = response.json().map_err(|e| e.to_string())?;

        if let Some(error) = json.get("error") {
            return Err(error["message"].as_str().unwrap_or("Unknown error").to_string());
        }

        Ok(json["result"].as_str().unwrap_or("0x").to_string())
    }

    fn analyze_transaction_data(&self, request: &SimulationRequest) -> HawalaResult<TransactionAnalysis> {
        let data = &request.data;
        let mut analysis = TransactionAnalysis::default();
        
        // Estimate gas based on data size
        let data_bytes = data.len().saturating_sub(2) / 2; // Remove "0x" and divide by 2
        analysis.estimated_gas = 21000 + (data_bytes as u64 * 16);
        
        // If no data, it's a simple transfer
        if data.len() <= 2 || data == "0x" {
            // Native token transfer
            if let Ok(value) = parse_hex_u128(&request.value) {
                if value > 0 {
                    analysis.balance_changes.push(BalanceChange {
                        token_address: "native".to_string(),
                        symbol: self.get_native_symbol(request.chain),
                        name: self.get_native_name(request.chain),
                        decimals: 18,
                        amount: format!("-{}", format_wei(value, 18)),
                        raw_amount: format!("-{}", value),
                        usd_value: None,
                        direction: TransferDirection::Outgoing,
                    });
                }
            }
            return Ok(analysis);
        }

        // Parse function selector (first 4 bytes)
        let selector = if data.len() >= 10 { &data[..10] } else { data };
        
        // Check for known function selectors
        match selector {
            // ERC-20 approve(address,uint256)
            "0x095ea7b3" => {
                analysis.estimated_gas = 65000;
                if data.len() >= 138 {
                    let spender = format!("0x{}", &data[34..74]);
                    let amount_hex = &data[74..138];
                    let is_unlimited = amount_hex == "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
                    
                    analysis.token_approvals.push(TokenApprovalChange {
                        token_address: request.to.clone(),
                        symbol: "TOKEN".to_string(), // Would need to fetch
                        spender_address: spender.clone(),
                        spender_name: self.known_contracts.get(&spender.to_lowercase())
                            .map(|c| c.name.clone()),
                        new_allowance: if is_unlimited { "Unlimited".to_string() } else { amount_hex.to_string() },
                        is_unlimited,
                        previous_allowance: None,
                        risk_level: if is_unlimited { SimulationRiskLevel::Medium } else { SimulationRiskLevel::Low },
                    });
                }
            }
            
            // ERC-20 transfer(address,uint256)
            "0xa9059cbb" => {
                analysis.estimated_gas = 65000;
                if data.len() >= 138 {
                    let _to = format!("0x{}", &data[34..74]);
                    let amount_hex = &data[74..138];
                    if let Ok(amount) = u128::from_str_radix(amount_hex, 16) {
                        analysis.balance_changes.push(BalanceChange {
                            token_address: request.to.clone(),
                            symbol: "TOKEN".to_string(),
                            name: "Unknown Token".to_string(),
                            decimals: 18,
                            amount: format!("-{}", format_wei(amount, 18)),
                            raw_amount: format!("-{}", amount),
                            usd_value: None,
                            direction: TransferDirection::Outgoing,
                        });
                    }
                }
            }
            
            // ERC-721/1155 setApprovalForAll(address,bool)
            "0xa22cb465" => {
                analysis.estimated_gas = 50000;
                analysis.has_approval_for_all = true;
            }
            
            // multicall (common in Uniswap)
            "0xac9650d8" | "0x5ae401dc" => {
                analysis.estimated_gas = 250000;
            }
            
            // swap functions (Uniswap-like)
            "0x38ed1739" | "0x8803dbee" | "0x7ff36ab5" | "0xfb3bdb41" => {
                analysis.estimated_gas = 200000;
            }
            
            _ => {}
        }
        
        // Add contract interaction
        let to_lower = request.to.to_lowercase();
        if let Some(info) = self.known_contracts.get(&to_lower) {
            analysis.contract_interactions.push(ContractInteraction {
                address: request.to.clone(),
                name: Some(info.name.clone()),
                function_name: self.get_function_name(selector),
                is_verified: info.is_verified,
                is_known_protocol: info.protocol.is_some(),
                protocol: info.protocol.clone(),
            });
        } else if data.len() > 2 {
            // Unknown contract
            analysis.contract_interactions.push(ContractInteraction {
                address: request.to.clone(),
                name: None,
                function_name: self.get_function_name(selector),
                is_verified: false,
                is_known_protocol: false,
                protocol: None,
            });
            
            // Add warning for unknown contract
            analysis.warnings.push(SimulationWarning {
                severity: SimulationRiskLevel::Low,
                code: WarningCode::UnknownSpender,
                message: "Interacting with unknown contract".to_string(),
                details: Some(request.to.clone()),
                should_block: false,
            });
        }
        
        Ok(analysis)
    }

    fn get_function_name(&self, selector: &str) -> Option<String> {
        match selector {
            "0x095ea7b3" => Some("approve".to_string()),
            "0xa9059cbb" => Some("transfer".to_string()),
            "0x23b872dd" => Some("transferFrom".to_string()),
            "0xa22cb465" => Some("setApprovalForAll".to_string()),
            "0x38ed1739" => Some("swapExactTokensForTokens".to_string()),
            "0x7ff36ab5" => Some("swapExactETHForTokens".to_string()),
            "0x18cbafe5" => Some("swapExactTokensForETH".to_string()),
            "0xac9650d8" => Some("multicall".to_string()),
            "0x5ae401dc" => Some("multicall".to_string()),
            _ => None,
        }
    }

    fn get_native_symbol(&self, chain: Chain) -> String {
        match chain {
            Chain::Ethereum | Chain::EthereumSepolia => "ETH",
            Chain::Bnb => "BNB",
            Chain::Polygon => "MATIC",
            Chain::Avalanche => "AVAX",
            Chain::Arbitrum | Chain::Optimism | Chain::Base => "ETH",
            _ => "ETH",
        }.to_string()
    }

    fn get_native_name(&self, chain: Chain) -> String {
        match chain {
            Chain::Ethereum | Chain::EthereumSepolia => "Ether",
            Chain::Bnb => "BNB",
            Chain::Polygon => "Polygon",
            Chain::Avalanche => "Avalanche",
            Chain::Arbitrum => "Arbitrum ETH",
            Chain::Optimism => "Optimism ETH",
            Chain::Base => "Base ETH",
            _ => "Ether",
        }.to_string()
    }

    fn build_summary(
        &self,
        analysis: &TransactionAnalysis,
        warnings: &[SimulationWarning],
        success: bool,
    ) -> String {
        if !success {
            return "⚠️ Transaction would fail".to_string();
        }
        
        let mut parts = Vec::new();
        
        // Balance changes
        for change in &analysis.balance_changes {
            if change.direction == TransferDirection::Outgoing {
                parts.push(format!("Send {} {}", change.amount.trim_start_matches('-'), change.symbol));
            } else {
                parts.push(format!("Receive {} {}", change.amount, change.symbol));
            }
        }
        
        // Approvals
        for approval in &analysis.token_approvals {
            if approval.is_unlimited {
                parts.push(format!("Unlimited approval for {}", approval.symbol));
            } else {
                parts.push(format!("Approve {} for spending", approval.symbol));
            }
        }
        
        // NFT transfers
        for nft in &analysis.nft_transfers {
            if nft.direction == TransferDirection::Outgoing {
                parts.push(format!("Send NFT #{}", nft.token_id));
            } else {
                parts.push(format!("Receive NFT #{}", nft.token_id));
            }
        }
        
        // Warnings
        let critical_warnings: Vec<_> = warnings.iter()
            .filter(|w| w.severity >= SimulationRiskLevel::High)
            .collect();
        
        if !critical_warnings.is_empty() {
            parts.push(format!("⚠️ {} warning(s)", critical_warnings.len()));
        }
        
        if parts.is_empty() {
            "Contract interaction".to_string()
        } else {
            parts.join(", ")
        }
    }
}

impl Default for TransactionSimulator {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug, Default)]
struct TransactionAnalysis {
    estimated_gas: u64,
    balance_changes: Vec<BalanceChange>,
    token_approvals: Vec<TokenApprovalChange>,
    nft_transfers: Vec<NFTTransfer>,
    contract_interactions: Vec<ContractInteraction>,
    warnings: Vec<SimulationWarning>,
    has_approval_for_all: bool,
}

// =============================================================================
// Helper Functions
// =============================================================================

fn parse_hex_u128(hex: &str) -> Result<u128, std::num::ParseIntError> {
    let hex = hex.trim_start_matches("0x");
    if hex.is_empty() {
        return Ok(0);
    }
    u128::from_str_radix(hex, 16)
}

fn format_wei(wei: u128, decimals: u8) -> String {
    let divisor = 10u128.pow(decimals as u32);
    let whole = wei / divisor;
    let frac = wei % divisor;
    
    if frac == 0 {
        format!("{}", whole)
    } else {
        let frac_str = format!("{:0width$}", frac, width = decimals as usize);
        let trimmed = frac_str.trim_end_matches('0');
        format!("{}.{}", whole, trimmed)
    }
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_simulator() {
        let sim = TransactionSimulator::new();
        assert!(!sim.known_contracts.is_empty());
    }

    #[test]
    fn test_is_scam_address() {
        let mut sim = TransactionSimulator::new();
        sim.add_scam_addresses(&["0x1234567890abcdef".to_string()]);
        assert!(sim.is_scam_address("0x1234567890abcdef"));
        assert!(sim.is_scam_address("0x1234567890ABCDEF")); // Case insensitive
        assert!(!sim.is_scam_address("0xabcdef"));
    }

    #[test]
    fn test_parse_approve_selector() {
        let sim = TransactionSimulator::new();
        let request = SimulationRequest {
            chain: Chain::Ethereum,
            from: "0x1234567890123456789012345678901234567890".to_string(),
            to: "0xdac17f958d2ee523a2206206994597c13d831ec7".to_string(), // USDT
            value: "0x0".to_string(),
            data: "0x095ea7b30000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488dffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff".to_string(),
            gas_limit: None,
        };
        
        let analysis = sim.analyze_transaction_data(&request).unwrap();
        assert_eq!(analysis.token_approvals.len(), 1);
        assert!(analysis.token_approvals[0].is_unlimited);
    }

    #[test]
    fn test_format_wei() {
        assert_eq!(format_wei(1_000_000_000_000_000_000, 18), "1");
        assert_eq!(format_wei(1_500_000_000_000_000_000, 18), "1.5");
        assert_eq!(format_wei(100_000_000, 6), "100");
    }

    #[test]
    fn test_risk_levels() {
        assert!(SimulationRiskLevel::Critical > SimulationRiskLevel::High);
        assert!(SimulationRiskLevel::High > SimulationRiskLevel::Medium);
        assert!(SimulationRiskLevel::Medium > SimulationRiskLevel::Low);
        assert!(SimulationRiskLevel::Low > SimulationRiskLevel::Safe);
    }
}
