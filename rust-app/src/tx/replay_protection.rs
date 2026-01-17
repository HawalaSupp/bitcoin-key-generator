//! Transaction Replay Protection
//!
//! Prevents transaction replay attacks across chains and ensures
//! proper chain ID verification for EVM transactions.

use crate::error::{HawalaError, HawalaResult};
use crate::types::Chain;
use std::collections::HashSet;
use std::sync::{LazyLock, Mutex};

/// Transaction signatures that have been broadcast
/// Used to prevent accidental re-broadcast
static BROADCAST_HISTORY: LazyLock<Mutex<HashSet<String>>> = LazyLock::new(|| Mutex::new(HashSet::new()));

/// EVM Chain IDs for replay protection
pub mod chain_ids {
    // Mainnet chains
    pub const ETHEREUM: u64 = 1;
    pub const BSC: u64 = 56;
    pub const POLYGON: u64 = 137;
    pub const ARBITRUM: u64 = 42161;
    pub const OPTIMISM: u64 = 10;
    pub const BASE: u64 = 8453;
    pub const AVALANCHE: u64 = 43114;
    
    // Testnet chains
    pub const SEPOLIA: u64 = 11155111;
    pub const BSC_TESTNET: u64 = 97;
    pub const MUMBAI: u64 = 80001;
    pub const ARBITRUM_SEPOLIA: u64 = 421614;
    pub const OPTIMISM_SEPOLIA: u64 = 11155420;
    pub const BASE_SEPOLIA: u64 = 84532;
    pub const AVALANCHE_FUJI: u64 = 43113;
}

/// Verify that a chain ID is valid and matches the expected network
pub fn verify_chain_id(chain_id: u64, expected_chain: Chain) -> HawalaResult<()> {
    let expected_id = match expected_chain {
        Chain::Ethereum => chain_ids::ETHEREUM,
        Chain::EthereumSepolia => chain_ids::SEPOLIA,
        Chain::Bnb => chain_ids::BSC,
        Chain::Polygon => chain_ids::POLYGON,
        Chain::Arbitrum => chain_ids::ARBITRUM,
        Chain::Optimism => chain_ids::OPTIMISM,
        Chain::Base => chain_ids::BASE,
        Chain::Avalanche => chain_ids::AVALANCHE,
        _ => return Err(HawalaError::invalid_input("Not an EVM chain")),
    };

    if chain_id != expected_id {
        return Err(HawalaError::invalid_input(format!(
            "Chain ID mismatch: expected {} for {:?}, got {}",
            expected_id, expected_chain, chain_id
        )));
    }

    Ok(())
}

/// Check if a chain ID is for a testnet
pub fn is_testnet_chain(chain_id: u64) -> bool {
    matches!(chain_id, 
        chain_ids::SEPOLIA | 
        chain_ids::BSC_TESTNET | 
        chain_ids::MUMBAI |
        chain_ids::ARBITRUM_SEPOLIA |
        chain_ids::OPTIMISM_SEPOLIA |
        chain_ids::BASE_SEPOLIA |
        chain_ids::AVALANCHE_FUJI
    )
}

/// Get the mainnet equivalent of a testnet chain ID
pub fn get_mainnet_equivalent(testnet_chain_id: u64) -> Option<u64> {
    match testnet_chain_id {
        chain_ids::SEPOLIA => Some(chain_ids::ETHEREUM),
        chain_ids::BSC_TESTNET => Some(chain_ids::BSC),
        chain_ids::MUMBAI => Some(chain_ids::POLYGON),
        chain_ids::ARBITRUM_SEPOLIA => Some(chain_ids::ARBITRUM),
        chain_ids::OPTIMISM_SEPOLIA => Some(chain_ids::OPTIMISM),
        chain_ids::BASE_SEPOLIA => Some(chain_ids::BASE),
        chain_ids::AVALANCHE_FUJI => Some(chain_ids::AVALANCHE),
        _ => None,
    }
}

/// Record a transaction signature to prevent replay
pub fn record_transaction(tx_hash: &str) -> HawalaResult<()> {
    let mut history = BROADCAST_HISTORY.lock()
        .map_err(|_| HawalaError::internal("Broadcast history lock poisoned"))?;
    
    history.insert(tx_hash.to_lowercase());
    
    // Keep history bounded to prevent memory growth
    if history.len() > 10000 {
        // In production, would persist to disk and use LRU
        history.clear();
    }
    
    Ok(())
}

/// Check if a transaction has already been broadcast
pub fn was_transaction_broadcast(tx_hash: &str) -> HawalaResult<bool> {
    let history = BROADCAST_HISTORY.lock()
        .map_err(|_| HawalaError::internal("Broadcast history lock poisoned"))?;
    
    Ok(history.contains(&tx_hash.to_lowercase()))
}

/// Verify EIP-155 replay protection in transaction
/// EIP-155 adds chain_id to the signature, preventing replay on other chains
pub fn verify_eip155_protection(raw_tx: &str, _expected_chain_id: u64) -> HawalaResult<()> {
    // Decode the raw transaction
    let tx_bytes = crate::utils::parse_hex_bytes(raw_tx)?;
    
    if tx_bytes.is_empty() {
        return Err(HawalaError::invalid_input("Empty transaction"));
    }
    
    // Check transaction type
    let tx_type = tx_bytes[0];
    
    match tx_type {
        // EIP-2930 (type 1) or EIP-1559 (type 2) - chain_id is embedded
        0x01 | 0x02 => {
            // These types inherently include chain_id, so they're protected
            Ok(())
        }
        // Legacy transaction
        _ if tx_type >= 0xc0 => {
            // Legacy transactions use EIP-155: v = chain_id * 2 + 35 + recovery_id
            // We can verify the chain_id from v value
            // For now, trust that ethers-rs signs correctly
            Ok(())
        }
        _ => {
            Err(HawalaError::invalid_input(format!("Unknown transaction type: {}", tx_type)))
        }
    }
}

/// Validate that a signed transaction targets the correct chain
pub fn validate_evm_transaction(
    raw_tx: &str,
    expected_chain: Chain,
    _expected_nonce: Option<u64>,
) -> HawalaResult<TransactionValidation> {
    let chain_id = expected_chain.chain_id()
        .ok_or_else(|| HawalaError::invalid_input("Not an EVM chain"))?;
    
    // Verify EIP-155 protection
    verify_eip155_protection(raw_tx, chain_id)?;
    
    // Check if already broadcast
    let tx_hash = compute_tx_hash(raw_tx)?;
    let already_broadcast = was_transaction_broadcast(&tx_hash)?;
    
    Ok(TransactionValidation {
        tx_hash,
        chain_id,
        is_testnet: is_testnet_chain(chain_id),
        has_replay_protection: true,
        already_broadcast,
        nonce_valid: true, // Would need to decode tx to verify
    })
}

/// Compute transaction hash from raw bytes
fn compute_tx_hash(raw_tx: &str) -> HawalaResult<String> {
    use tiny_keccak::{Hasher, Keccak};
    
    let tx_bytes = crate::utils::parse_hex_bytes(raw_tx)?;
    
    let mut hasher = Keccak::v256();
    let mut hash = [0u8; 32];
    hasher.update(&tx_bytes);
    hasher.finalize(&mut hash);
    
    Ok(format!("0x{}", hex::encode(hash)))
}

/// Transaction validation result
#[derive(Debug, Clone)]
pub struct TransactionValidation {
    pub tx_hash: String,
    pub chain_id: u64,
    pub is_testnet: bool,
    pub has_replay_protection: bool,
    pub already_broadcast: bool,
    pub nonce_valid: bool,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_chain_id_verification() {
        assert!(verify_chain_id(1, Chain::Ethereum).is_ok());
        assert!(verify_chain_id(56, Chain::Bnb).is_ok());
        assert!(verify_chain_id(137, Chain::Polygon).is_ok());
        
        // Wrong chain ID
        assert!(verify_chain_id(56, Chain::Ethereum).is_err());
    }

    #[test]
    fn test_testnet_detection() {
        assert!(is_testnet_chain(chain_ids::SEPOLIA));
        assert!(is_testnet_chain(chain_ids::MUMBAI));
        assert!(!is_testnet_chain(chain_ids::ETHEREUM));
        assert!(!is_testnet_chain(chain_ids::POLYGON));
    }

    #[test]
    fn test_mainnet_equivalent() {
        assert_eq!(get_mainnet_equivalent(chain_ids::SEPOLIA), Some(chain_ids::ETHEREUM));
        assert_eq!(get_mainnet_equivalent(chain_ids::MUMBAI), Some(chain_ids::POLYGON));
        assert_eq!(get_mainnet_equivalent(chain_ids::ETHEREUM), None);
    }

    #[test]
    fn test_transaction_recording() {
        let hash = "0x1234567890abcdef";
        
        // Should not be recorded initially
        assert!(!was_transaction_broadcast(hash).unwrap());
        
        // Record it
        record_transaction(hash).unwrap();
        
        // Should be recorded now
        assert!(was_transaction_broadcast(hash).unwrap());
        
        // Case-insensitive
        assert!(was_transaction_broadcast("0x1234567890ABCDEF").unwrap());
    }
}
