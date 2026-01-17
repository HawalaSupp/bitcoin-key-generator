//! Transaction Cancellation
//!
//! Handles transaction cancellation and speed-up for Bitcoin (RBF) and Ethereum (nonce replacement).
//! - Bitcoin/Litecoin: Replace-by-Fee (RBF) - create new tx with same inputs, higher fee
//! - Ethereum/EVM: Nonce replacement - send 0 value to self with same nonce, higher gas

use crate::error::{HawalaError, HawalaResult};
use crate::types::*;
use crate::tx::{signer, broadcaster};
use crate::tx::signer::{SignParams, BitcoinSignParams, LitecoinSignParams, EthereumSignParams, UtxoInput};
use serde::{Deserialize, Serialize};

// =============================================================================
// Types
// =============================================================================

/// Method used to cancel/replace a transaction
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CancellationMethod {
    /// Bitcoin RBF: Send all funds back to self with higher fee
    RbfCancel,
    /// Bitcoin RBF: Rebroadcast same tx with higher fee (from change)
    RbfSpeedUp,
    /// Ethereum: Send 0 value to self with same nonce
    NonceReplace,
    /// Ethereum: Same tx with higher gas
    NonceSpeedUp,
    /// Bitcoin: Child-pays-for-parent
    Cpfp,
}

/// Result of a cancellation attempt
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CancellationResult {
    pub success: bool,
    pub original_txid: String,
    pub replacement_txid: Option<String>,
    pub method: CancellationMethod,
    pub new_fee_rate: u64,
    pub message: String,
}

/// Request to cancel a Bitcoin transaction
#[derive(Debug, Clone, Deserialize)]
pub struct BitcoinCancelRequest {
    pub original_txid: String,
    pub utxos: Vec<CancellableUtxo>,
    pub return_address: String,
    pub private_key_wif: String,
    pub new_fee_rate: u64, // sat/vB
    pub is_testnet: bool,
    pub is_litecoin: bool,
}

/// Request to speed up a Bitcoin transaction
#[derive(Debug, Clone, Deserialize)]
pub struct BitcoinSpeedUpRequest {
    pub original_txid: String,
    pub utxos: Vec<CancellableUtxo>,
    pub original_recipient: String,
    pub original_amount: u64,
    pub change_address: Option<String>,
    pub private_key_wif: String,
    pub new_fee_rate: u64, // sat/vB
    pub original_fee_rate: u64,
    pub is_testnet: bool,
    pub is_litecoin: bool,
}

/// Request to cancel an Ethereum transaction
#[derive(Debug, Clone, Deserialize)]
pub struct EvmCancelRequest {
    pub original_txid: String,
    pub nonce: u64,
    pub from_address: String,
    pub private_key_hex: String,
    pub new_gas_price: String, // wei
    pub chain_id: u64,
}

/// Request to speed up an Ethereum transaction
#[derive(Debug, Clone, Deserialize)]
pub struct EvmSpeedUpRequest {
    pub original_txid: String,
    pub nonce: u64,
    pub from_address: String,
    pub to_address: String,
    pub value: String, // wei
    pub private_key_hex: String,
    pub new_gas_price: String, // wei
    pub original_gas_price: String, // wei for validation
    pub chain_id: u64,
    pub data: Option<String>,
}

/// UTXO data stored for cancellation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CancellableUtxo {
    pub txid: String,
    pub vout: u32,
    pub value: u64,
    pub script_pubkey: String,
}

// =============================================================================
// Bitcoin/Litecoin Cancellation (RBF)
// =============================================================================

/// Cancel a pending Bitcoin/Litecoin transaction using RBF
/// Creates a new transaction spending the same inputs back to the sender
pub fn cancel_bitcoin_rbf(request: &BitcoinCancelRequest) -> HawalaResult<CancellationResult> {
    // Calculate total input value
    let total_input: u64 = request.utxos.iter().map(|u| u.value).sum();
    
    // Estimate transaction size (1-in-1-out P2WPKH ~110 vB, +68 vB per additional input)
    let estimated_vsize = 110 + (request.utxos.len().saturating_sub(1) * 68);
    let new_fee = request.new_fee_rate * estimated_vsize as u64;
    
    // Calculate output value
    let output_value = total_input.saturating_sub(new_fee);
    
    // Check dust limit (546 satoshis for Bitcoin)
    let dust_limit = if request.is_litecoin { 100000 } else { 546 };
    if output_value < dust_limit {
        return Err(HawalaError::invalid_input(format!(
            "Output value {} below dust limit {}",
            output_value, dust_limit
        )));
    }
    
    // Convert UTXOs to UtxoInput format
    let utxo_inputs: Vec<UtxoInput> = request.utxos.iter().map(|u| UtxoInput {
        txid: u.txid.clone(),
        vout: u.vout,
        value: u.value,
    }).collect();
    
    let chain = if request.is_litecoin {
        Chain::Litecoin
    } else if request.is_testnet {
        Chain::BitcoinTestnet
    } else {
        Chain::Bitcoin
    };
    
    // Build sign params
    let sign_params = if request.is_litecoin {
        SignParams::Litecoin(LitecoinSignParams {
            recipient: request.return_address.clone(),
            amount_lits: output_value,
            fee_rate_lits_per_vbyte: request.new_fee_rate,
            sender_wif: request.private_key_wif.clone(),
            sender_address: request.return_address.clone(),
            utxos: Some(utxo_inputs),
        })
    } else {
        SignParams::Bitcoin(BitcoinSignParams {
            chain: chain.clone(),
            recipient: request.return_address.clone(),
            amount_sats: output_value,
            fee_rate_sats_per_vbyte: request.new_fee_rate,
            sender_wif: request.private_key_wif.clone(),
            utxos: Some(utxo_inputs),
        })
    };
    
    // Sign the transaction
    let signed = signer::sign_transaction(sign_params)?;
    
    // Broadcast
    let broadcast_result = broadcaster::broadcast_transaction(chain.clone(), &signed.raw_tx)?;
    
    Ok(CancellationResult {
        success: true,
        original_txid: request.original_txid.clone(),
        replacement_txid: Some(broadcast_result.txid),
        method: CancellationMethod::RbfCancel,
        new_fee_rate: request.new_fee_rate,
        message: format!(
            "Transaction cancelled. {} returning to {}",
            format_satoshis(output_value),
            truncate_address(&request.return_address)
        ),
    })
}

/// Speed up a pending Bitcoin/Litecoin transaction using RBF
/// Creates same transaction with higher fee taken from change
pub fn speed_up_bitcoin_rbf(request: &BitcoinSpeedUpRequest) -> HawalaResult<CancellationResult> {
    // Validate new fee rate is higher
    if request.new_fee_rate <= request.original_fee_rate {
        return Err(HawalaError::invalid_input(format!(
            "New fee rate {} must be higher than original {}",
            request.new_fee_rate, request.original_fee_rate
        )));
    }
    
    // Convert UTXOs to UtxoInput format
    let utxo_inputs: Vec<UtxoInput> = request.utxos.iter().map(|u| UtxoInput {
        txid: u.txid.clone(),
        vout: u.vout,
        value: u.value,
    }).collect();
    
    let chain = if request.is_litecoin {
        Chain::Litecoin
    } else if request.is_testnet {
        Chain::BitcoinTestnet
    } else {
        Chain::Bitcoin
    };
    
    // Build sign params - keeping same recipient and amount
    let sign_params = if request.is_litecoin {
        SignParams::Litecoin(LitecoinSignParams {
            recipient: request.original_recipient.clone(),
            amount_lits: request.original_amount,
            fee_rate_lits_per_vbyte: request.new_fee_rate,
            sender_wif: request.private_key_wif.clone(),
            sender_address: request.change_address.clone().unwrap_or_default(),
            utxos: Some(utxo_inputs),
        })
    } else {
        SignParams::Bitcoin(BitcoinSignParams {
            chain: chain.clone(),
            recipient: request.original_recipient.clone(),
            amount_sats: request.original_amount,
            fee_rate_sats_per_vbyte: request.new_fee_rate,
            sender_wif: request.private_key_wif.clone(),
            utxos: Some(utxo_inputs),
        })
    };
    
    // Sign and broadcast
    let signed = signer::sign_transaction(sign_params)?;
    let broadcast_result = broadcaster::broadcast_transaction(chain, &signed.raw_tx)?;
    
    Ok(CancellationResult {
        success: true,
        original_txid: request.original_txid.clone(),
        replacement_txid: Some(broadcast_result.txid),
        method: CancellationMethod::RbfSpeedUp,
        new_fee_rate: request.new_fee_rate,
        message: format!(
            "Transaction sped up with {} sat/vB fee",
            request.new_fee_rate
        ),
    })
}

// =============================================================================
// Ethereum/EVM Cancellation (Nonce Replacement)
// =============================================================================

/// Cancel a pending Ethereum transaction using nonce replacement
/// Sends 0 value to self with same nonce and higher gas
pub fn cancel_evm_nonce(request: &EvmCancelRequest) -> HawalaResult<CancellationResult> {
    // Parse and validate gas prices
    let new_gas: u128 = request.new_gas_price.parse()
        .map_err(|_| HawalaError::invalid_input("Invalid gas price"))?;
    
    // Get minimum gas (10% higher than estimated current)
    let current_gas = get_current_gas_price(request.chain_id)?;
    let minimum_gas = (current_gas as f64 * 1.1) as u128;
    
    if new_gas < minimum_gas {
        return Err(HawalaError::invalid_input(format!(
            "Gas price {} too low. Minimum: {}",
            new_gas, minimum_gas
        )));
    }
    
    let chain = chain_from_id(request.chain_id)?;
    let use_eip1559 = supports_eip1559(request.chain_id);
    
    // Build EthereumSignParams
    let sign_params = if use_eip1559 {
        let priority_fee = calculate_priority_fee(new_gas, request.chain_id);
        
        SignParams::Ethereum(EthereumSignParams {
            recipient: request.from_address.clone(), // Send to self
            amount_wei: "0".to_string(),
            chain_id: request.chain_id,
            sender_key_hex: request.private_key_hex.clone(),
            nonce: request.nonce,
            gas_limit: 21000,
            gas_price_wei: None,
            max_fee_per_gas_wei: Some(request.new_gas_price.clone()),
            max_priority_fee_per_gas_wei: Some(priority_fee.to_string()),
            data_hex: None,
        })
    } else {
        SignParams::Ethereum(EthereumSignParams {
            recipient: request.from_address.clone(),
            amount_wei: "0".to_string(),
            chain_id: request.chain_id,
            sender_key_hex: request.private_key_hex.clone(),
            nonce: request.nonce,
            gas_limit: 21000,
            gas_price_wei: Some(request.new_gas_price.clone()),
            max_fee_per_gas_wei: None,
            max_priority_fee_per_gas_wei: None,
            data_hex: None,
        })
    };
    
    // Sign and broadcast
    let signed = signer::sign_transaction(sign_params)?;
    let broadcast_result = broadcaster::broadcast_transaction(chain, &signed.raw_tx)?;
    
    Ok(CancellationResult {
        success: true,
        original_txid: request.original_txid.clone(),
        replacement_txid: Some(broadcast_result.txid),
        method: CancellationMethod::NonceReplace,
        new_fee_rate: (new_gas / 1_000_000_000) as u64, // Convert to Gwei
        message: format!(
            "Transaction cancelled. Nonce {} consumed.",
            request.nonce
        ),
    })
}

/// Speed up a pending Ethereum transaction
/// Rebroadcasts same transaction with higher gas
pub fn speed_up_evm(request: &EvmSpeedUpRequest) -> HawalaResult<CancellationResult> {
    // Parse and validate gas prices
    let new_gas: u128 = request.new_gas_price.parse()
        .map_err(|_| HawalaError::invalid_input("Invalid new gas price"))?;
    let original_gas: u128 = request.original_gas_price.parse()
        .map_err(|_| HawalaError::invalid_input("Invalid original gas price"))?;
    
    // Must be at least 10% higher
    let minimum_gas = (original_gas as f64 * 1.1) as u128;
    if new_gas < minimum_gas {
        return Err(HawalaError::invalid_input(format!(
            "Gas price {} too low. Must be at least 10% higher than original ({})",
            new_gas, minimum_gas
        )));
    }
    
    let chain = chain_from_id(request.chain_id)?;
    let use_eip1559 = supports_eip1559(request.chain_id);
    
    // Determine gas limit based on data
    let gas_limit = if request.data.as_ref().map(|d| d.len() > 2).unwrap_or(false) {
        65000 // Contract interaction
    } else {
        21000 // Simple transfer
    };
    
    let sign_params = if use_eip1559 {
        let priority_fee = calculate_priority_fee(new_gas, request.chain_id);
        
        SignParams::Ethereum(EthereumSignParams {
            recipient: request.to_address.clone(),
            amount_wei: request.value.clone(),
            chain_id: request.chain_id,
            sender_key_hex: request.private_key_hex.clone(),
            nonce: request.nonce,
            gas_limit,
            gas_price_wei: None,
            max_fee_per_gas_wei: Some(request.new_gas_price.clone()),
            max_priority_fee_per_gas_wei: Some(priority_fee.to_string()),
            data_hex: request.data.clone(),
        })
    } else {
        SignParams::Ethereum(EthereumSignParams {
            recipient: request.to_address.clone(),
            amount_wei: request.value.clone(),
            chain_id: request.chain_id,
            sender_key_hex: request.private_key_hex.clone(),
            nonce: request.nonce,
            gas_limit,
            gas_price_wei: Some(request.new_gas_price.clone()),
            max_fee_per_gas_wei: None,
            max_priority_fee_per_gas_wei: None,
            data_hex: request.data.clone(),
        })
    };
    
    // Sign and broadcast
    let signed = signer::sign_transaction(sign_params)?;
    let broadcast_result = broadcaster::broadcast_transaction(chain, &signed.raw_tx)?;
    
    Ok(CancellationResult {
        success: true,
        original_txid: request.original_txid.clone(),
        replacement_txid: Some(broadcast_result.txid),
        method: CancellationMethod::NonceSpeedUp,
        new_fee_rate: (new_gas / 1_000_000_000) as u64,
        message: format!(
            "Transaction sped up with {} Gwei gas",
            new_gas / 1_000_000_000
        ),
    })
}

// =============================================================================
// Helper Functions
// =============================================================================

/// Check if transaction can be cancelled
pub fn can_cancel(chain: Chain, has_utxo_data: bool, has_nonce: bool) -> (bool, String) {
    match chain {
        Chain::Bitcoin | Chain::BitcoinTestnet | Chain::Litecoin => {
            if has_utxo_data {
                (true, "RBF enabled - can cancel or speed up".to_string())
            } else {
                (false, "Missing UTXO data - cannot cancel".to_string())
            }
        }
        Chain::Ethereum | Chain::EthereumSepolia | Chain::Bnb | 
        Chain::Polygon | Chain::Arbitrum | Chain::Optimism | Chain::Base | Chain::Avalanche => {
            if has_nonce {
                (true, "Can replace with higher gas".to_string())
            } else {
                (true, "Can cancel by sending 0 ETH to self".to_string())
            }
        }
        _ => (false, format!("Cancellation not supported for {:?}", chain)),
    }
}

/// Get current gas price for a chain
fn get_current_gas_price(chain_id: u64) -> HawalaResult<u128> {
    // Use fee estimator
    match crate::fees::get_gas_price(chain_id) {
        Ok(price) => Ok(price as u128),
        Err(_) => {
            // Return reasonable defaults
            Ok(match chain_id {
                1 => 30_000_000_000,       // 30 Gwei for ETH
                11155111 => 5_000_000_000, // 5 Gwei for Sepolia
                56 => 3_000_000_000,       // 3 Gwei for BNB
                137 => 50_000_000_000,     // 50 Gwei for Polygon
                _ => 1_000_000_000,        // 1 Gwei default for L2s
            })
        }
    }
}

/// Check if chain supports EIP-1559
fn supports_eip1559(chain_id: u64) -> bool {
    matches!(chain_id, 
        1 |        // Ethereum
        11155111 | // Sepolia
        137 |      // Polygon
        42161 |    // Arbitrum
        10 |       // Optimism
        8453 |     // Base
        43114      // Avalanche
    )
    // BSC (56) uses legacy transactions
}

/// Calculate priority fee for EIP-1559
fn calculate_priority_fee(max_fee: u128, chain_id: u64) -> u128 {
    let multiplier = match chain_id {
        11155111 => 0.5, // Sepolia: 50% of max
        _ => 0.1,        // Others: 10% of max
    };
    
    let calculated = (max_fee as f64 * multiplier) as u128;
    calculated.max(2_500_000_000) // At least 2.5 Gwei
}

/// Convert chain ID to Chain enum
fn chain_from_id(chain_id: u64) -> HawalaResult<Chain> {
    match chain_id {
        1 => Ok(Chain::Ethereum),
        11155111 => Ok(Chain::EthereumSepolia),
        56 => Ok(Chain::Bnb),
        137 => Ok(Chain::Polygon),
        42161 => Ok(Chain::Arbitrum),
        10 => Ok(Chain::Optimism),
        8453 => Ok(Chain::Base),
        43114 => Ok(Chain::Avalanche),
        _ => Err(HawalaError::invalid_input(format!("Unknown chain ID: {}", chain_id))),
    }
}

/// Format satoshis for display
fn format_satoshis(sats: u64) -> String {
    let btc = sats as f64 / 100_000_000.0;
    if btc >= 0.001 {
        format!("{:.8} BTC", btc)
    } else {
        format!("{} sats", sats)
    }
}

/// Truncate address for display
fn truncate_address(addr: &str) -> String {
    if addr.len() > 16 {
        format!("{}...{}", &addr[..8], &addr[addr.len()-6..])
    } else {
        addr.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_can_cancel_bitcoin() {
        let (can, _) = can_cancel(Chain::Bitcoin, true, false);
        assert!(can);
        
        let (can, _) = can_cancel(Chain::Bitcoin, false, false);
        assert!(!can);
    }
    
    #[test]
    fn test_can_cancel_ethereum() {
        let (can, _) = can_cancel(Chain::Ethereum, false, true);
        assert!(can);
        
        let (can, _) = can_cancel(Chain::Ethereum, false, false);
        assert!(can); // Can still cancel by sending to self
    }
    
    #[test]
    fn test_eip1559_support() {
        assert!(supports_eip1559(1));
        assert!(supports_eip1559(11155111));
        assert!(!supports_eip1559(56)); // BSC is legacy
    }
}
