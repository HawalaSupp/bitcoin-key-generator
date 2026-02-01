//! Multi-Chain Gas Account
//!
//! Manages a unified gas balance that can pay for transactions on any chain.
//! Inspired by Rabby's Gas Account feature.

use crate::error::{HawalaError, HawalaResult, ErrorCode};
use super::ERC4337Chain;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Gas account manager for multi-chain gas abstraction
pub struct GasAccountManager {
    /// Account owner address
    owner: String,
    /// Current balances per chain
    balances: HashMap<ERC4337Chain, ChainGasBalance>,
    /// Total USD value
    total_usd: f64,
}

/// Gas balance on a specific chain
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChainGasBalance {
    pub chain: ERC4337Chain,
    pub native_balance: String,
    pub native_symbol: String,
    pub usd_value: f64,
    pub last_updated: u64,
}

/// Gas account info
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GasAccountInfo {
    pub owner: String,
    pub total_usd: f64,
    pub chains: Vec<ChainGasBalance>,
    pub deposit_address: String,
    pub is_enabled: bool,
}

/// Deposit request
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GasDeposit {
    pub amount: String,
    pub token: String,
    pub chain: ERC4337Chain,
    pub tx_hash: Option<String>,
    pub status: DepositStatus,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum DepositStatus {
    Pending,
    Confirmed,
    Failed,
}

/// Withdraw request
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GasWithdraw {
    pub amount: String,
    pub to_address: String,
    pub chain: ERC4337Chain,
    pub token: String,
    pub tx_hash: Option<String>,
    pub status: WithdrawStatus,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum WithdrawStatus {
    Pending,
    Processing,
    Completed,
    Failed,
}

/// Gas payment for a transaction
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GasPayment {
    pub transaction_hash: String,
    pub chain: ERC4337Chain,
    pub gas_used: String,
    pub gas_price: String,
    pub total_cost_wei: String,
    pub total_cost_usd: f64,
    pub paid_from_balance: bool,
    pub remaining_balance_usd: f64,
}

impl GasAccountManager {
    /// Create a new gas account manager
    pub fn new(owner: &str) -> Self {
        Self {
            owner: owner.to_string(),
            balances: HashMap::new(),
            total_usd: 0.0,
        }
    }
    
    /// Get account info
    pub fn get_info(&self) -> GasAccountInfo {
        GasAccountInfo {
            owner: self.owner.clone(),
            total_usd: self.total_usd,
            chains: self.balances.values().cloned().collect(),
            deposit_address: self.get_deposit_address(),
            is_enabled: self.total_usd > 0.0,
        }
    }
    
    /// Get deposit address (usually the smart account address)
    pub fn get_deposit_address(&self) -> String {
        // For now, deposit address is the owner
        // In a real implementation, this would be a dedicated gas tank contract
        self.owner.clone()
    }
    
    /// Refresh balances from chain
    pub fn refresh_balances(&mut self) -> HawalaResult<()> {
        // In a real implementation, this would query balances on each chain
        // For now, we'll just update timestamps
        
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        
        for balance in self.balances.values_mut() {
            balance.last_updated = now;
        }
        
        self.recalculate_total();
        Ok(())
    }
    
    /// Add balance (after deposit confirmed)
    pub fn add_balance(&mut self, chain: ERC4337Chain, amount: &str, usd_value: f64) {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        
        let entry = self.balances.entry(chain).or_insert_with(|| ChainGasBalance {
            chain,
            native_balance: "0".to_string(),
            native_symbol: Self::get_native_symbol(chain),
            usd_value: 0.0,
            last_updated: now,
        });
        
        // Add to existing balance
        let current = Self::parse_amount(&entry.native_balance);
        let addition = Self::parse_amount(amount);
        entry.native_balance = format!("{}", current + addition);
        entry.usd_value += usd_value;
        entry.last_updated = now;
        
        self.recalculate_total();
    }
    
    /// Deduct balance (after gas payment)
    pub fn deduct_balance(&mut self, chain: ERC4337Chain, amount: &str, usd_value: f64) -> HawalaResult<()> {
        let entry = self.balances.get_mut(&chain)
            .ok_or_else(|| HawalaError::new(
                ErrorCode::InvalidInput,
                format!("No balance on {:?}", chain),
            ))?;
        
        let current = Self::parse_amount(&entry.native_balance);
        let deduction = Self::parse_amount(amount);
        
        if deduction > current {
            return Err(HawalaError::new(
                ErrorCode::InsufficientFunds,
                format!("Insufficient balance: {} < {}", current, deduction),
            ));
        }
        
        entry.native_balance = format!("{}", current - deduction);
        entry.usd_value = (entry.usd_value - usd_value).max(0.0);
        entry.last_updated = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        
        self.recalculate_total();
        Ok(())
    }
    
    /// Estimate gas cost in USD
    pub fn estimate_gas_cost_usd(
        &self,
        chain: ERC4337Chain,
        gas_limit: u64,
        gas_price_gwei: f64,
    ) -> f64 {
        let gas_cost_eth = (gas_limit as f64) * gas_price_gwei / 1e9;
        let eth_price = self.get_native_price(chain);
        gas_cost_eth * eth_price
    }
    
    /// Check if we can pay for transaction
    pub fn can_pay(&self, chain: ERC4337Chain, estimated_cost_usd: f64) -> bool {
        self.balances.get(&chain)
            .map(|b| b.usd_value >= estimated_cost_usd)
            .unwrap_or(false)
    }
    
    /// Check balance across all chains
    pub fn can_pay_any_chain(&self, estimated_cost_usd: f64) -> Option<ERC4337Chain> {
        for (chain, balance) in &self.balances {
            if balance.usd_value >= estimated_cost_usd {
                return Some(*chain);
            }
        }
        None
    }
    
    /// Get suggested deposit amount
    pub fn get_suggested_deposit(&self, target_usd: f64) -> SuggestedDeposit {
        let current = self.total_usd;
        let needed = (target_usd - current).max(0.0);
        
        // Find cheapest chain for deposit (by gas cost)
        let suggested_chain = ERC4337Chain::Base; // Base typically has lowest fees
        
        SuggestedDeposit {
            amount_usd: needed,
            suggested_chain,
            suggested_token: "ETH".to_string(),
            current_balance_usd: current,
            target_balance_usd: target_usd,
        }
    }
    
    // Helper functions
    fn recalculate_total(&mut self) {
        self.total_usd = self.balances.values().map(|b| b.usd_value).sum();
    }
    
    fn parse_amount(s: &str) -> f64 {
        s.parse().unwrap_or(0.0)
    }
    
    fn get_native_symbol(chain: ERC4337Chain) -> String {
        match chain {
            ERC4337Chain::Polygon | ERC4337Chain::Mumbai => "MATIC".to_string(),
            ERC4337Chain::BNB => "BNB".to_string(),
            ERC4337Chain::Avalanche => "AVAX".to_string(),
            _ => "ETH".to_string(),
        }
    }
    
    fn get_native_price(&self, chain: ERC4337Chain) -> f64 {
        // In a real implementation, this would fetch live prices
        match chain {
            ERC4337Chain::Polygon | ERC4337Chain::Mumbai => 0.85,
            ERC4337Chain::BNB => 300.0,
            ERC4337Chain::Avalanche => 35.0,
            _ => 2500.0, // ETH
        }
    }
}

/// Suggested deposit information
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SuggestedDeposit {
    pub amount_usd: f64,
    pub suggested_chain: ERC4337Chain,
    pub suggested_token: String,
    pub current_balance_usd: f64,
    pub target_balance_usd: f64,
}

/// Gas account statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GasAccountStats {
    pub total_deposited_usd: f64,
    pub total_spent_usd: f64,
    pub transactions_paid: u64,
    pub avg_gas_saved_percent: f64,
    pub most_used_chain: Option<ERC4337Chain>,
}

/// Auto-refill configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AutoRefillConfig {
    pub enabled: bool,
    pub threshold_usd: f64,
    pub refill_amount_usd: f64,
    pub source_chain: ERC4337Chain,
    pub source_token: String,
    pub max_daily_refills: u32,
}

impl Default for AutoRefillConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            threshold_usd: 5.0,
            refill_amount_usd: 20.0,
            source_chain: ERC4337Chain::Ethereum,
            source_token: "ETH".to_string(),
            max_daily_refills: 3,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_gas_account_creation() {
        let manager = GasAccountManager::new("0x1234...");
        let info = manager.get_info();
        
        assert_eq!(info.total_usd, 0.0);
        assert!(!info.is_enabled);
    }

    #[test]
    fn test_add_balance() {
        let mut manager = GasAccountManager::new("0x1234...");
        manager.add_balance(ERC4337Chain::Ethereum, "0.01", 25.0);
        
        let info = manager.get_info();
        assert_eq!(info.total_usd, 25.0);
        assert!(info.is_enabled);
        assert_eq!(info.chains.len(), 1);
    }

    #[test]
    fn test_deduct_balance() {
        let mut manager = GasAccountManager::new("0x1234...");
        manager.add_balance(ERC4337Chain::Ethereum, "0.01", 25.0);
        
        let result = manager.deduct_balance(ERC4337Chain::Ethereum, "0.005", 12.5);
        assert!(result.is_ok());
        
        let info = manager.get_info();
        assert_eq!(info.total_usd, 12.5);
    }

    #[test]
    fn test_insufficient_balance() {
        let mut manager = GasAccountManager::new("0x1234...");
        manager.add_balance(ERC4337Chain::Ethereum, "0.01", 25.0);
        
        let result = manager.deduct_balance(ERC4337Chain::Ethereum, "0.02", 50.0);
        assert!(result.is_err());
    }

    #[test]
    fn test_can_pay() {
        let mut manager = GasAccountManager::new("0x1234...");
        manager.add_balance(ERC4337Chain::Base, "0.01", 25.0);
        
        assert!(manager.can_pay(ERC4337Chain::Base, 10.0));
        assert!(!manager.can_pay(ERC4337Chain::Base, 30.0));
        assert!(!manager.can_pay(ERC4337Chain::Ethereum, 1.0));
    }

    #[test]
    fn test_estimate_gas_cost() {
        let manager = GasAccountManager::new("0x1234...");
        
        // 100,000 gas at 10 gwei on ETH ($2500)
        let cost = manager.estimate_gas_cost_usd(ERC4337Chain::Ethereum, 100_000, 10.0);
        // 100000 * 10 / 1e9 * 2500 = 2.5
        assert!((cost - 2.5).abs() < 0.01);
    }
}
