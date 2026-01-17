//! Transaction Builder
//!
//! Constructs unsigned transactions for all supported chains.

use crate::error::{HawalaError, HawalaResult, ErrorCode};
use crate::types::*;

/// Build a Bitcoin transaction
pub fn build_bitcoin_transaction(request: &TransactionRequest) -> HawalaResult<SignedTransaction> {
    // Delegate to existing bitcoin_wallet module for now
    // This will be fully migrated in Phase 2
    
    let utxos = request.utxos.as_ref()
        .ok_or_else(|| HawalaError::invalid_input("UTXOs required for Bitcoin transaction"))?;
    
    let fee_rate = request.fee_rate
        .ok_or_else(|| HawalaError::invalid_input("Fee rate required for Bitcoin transaction"))?;
    
    // Convert our Utxo type to bitcoin_wallet::Utxo
    let btc_utxos: Vec<crate::bitcoin_wallet::Utxo> = utxos.iter().map(|u| {
        crate::bitcoin_wallet::Utxo {
            txid: u.txid.clone(),
            vout: u.vout,
            status: crate::bitcoin_wallet::UtxoStatus {
                confirmed: u.confirmed,
                block_height: u.block_height,
                block_hash: None,
                block_time: None,
            },
            value: u.value,
        }
    }).collect();
    
    // Parse amount - handle both sats and BTC format
    let amount_sats: u64 = if request.amount.contains('.') {
        // Parse as BTC
        let btc: f64 = request.amount.parse()
            .map_err(|_| HawalaError::invalid_input("Invalid amount format"))?;
        (btc * 100_000_000.0) as u64
    } else {
        request.amount.parse()
            .map_err(|_| HawalaError::invalid_input("Invalid amount format"))?
    };
    
    match crate::bitcoin_wallet::prepare_transaction(
        &request.to,
        amount_sats,
        fee_rate,
        &request.private_key,
        Some(btc_utxos),
    ) {
        Ok(raw_tx) => {
            // Extract txid from the signed transaction
            let txid = calculate_btc_txid(&raw_tx);
            
            Ok(SignedTransaction {
                chain: request.chain,
                raw_tx,
                txid,
                estimated_fee: Some(format!("{} sats/vB", fee_rate)),
                size_bytes: None,
            })
        }
        Err(e) => Err(HawalaError::new(ErrorCode::CryptoError, e.to_string())),
    }
}

/// Build an EVM transaction (Ethereum, BSC, Polygon, etc.)
pub fn build_evm_transaction(request: &TransactionRequest) -> HawalaResult<SignedTransaction> {
    let chain_id = request.chain.chain_id()
        .ok_or_else(|| HawalaError::invalid_input("Invalid EVM chain"))?;
    
    let nonce = request.nonce
        .ok_or_else(|| HawalaError::invalid_input("Nonce required for EVM transaction"))?;
    
    let gas_limit = request.gas_limit
        .ok_or_else(|| HawalaError::invalid_input("Gas limit required for EVM transaction"))?;
    
    let data = request.data.clone().unwrap_or_else(|| "0x".to_string());
    
    // Use tokio runtime for async ethereum_wallet
    let rt = tokio::runtime::Runtime::new()
        .map_err(|e| HawalaError::internal(format!("Runtime error: {}", e)))?;
    
    match rt.block_on(crate::ethereum_wallet::prepare_ethereum_transaction(
        &request.to,
        &request.amount,
        chain_id,
        &request.private_key,
        nonce,
        gas_limit,
        request.gas_price.clone(),
        request.max_fee_per_gas.clone(),
        request.max_priority_fee_per_gas.clone(),
        &data,
    )) {
        Ok(raw_tx) => {
            let txid = calculate_eth_txid(&raw_tx);
            
            Ok(SignedTransaction {
                chain: request.chain,
                raw_tx,
                txid,
                estimated_fee: None, // Depends on gas * gasPrice
                size_bytes: None,
            })
        }
        Err(e) => Err(HawalaError::new(ErrorCode::CryptoError, e.to_string())),
    }
}

/// Build a Litecoin transaction
pub fn build_litecoin_transaction(request: &TransactionRequest) -> HawalaResult<SignedTransaction> {
    let utxos = request.utxos.as_ref()
        .ok_or_else(|| HawalaError::invalid_input("UTXOs required for Litecoin transaction"))?;
    
    let fee_rate = request.fee_rate
        .ok_or_else(|| HawalaError::invalid_input("Fee rate required for Litecoin transaction"))?;
    
    // Convert UTXOs to LitecoinUtxo format
    let ltc_utxos: Vec<crate::litecoin_wallet::LitecoinUtxo> = utxos.iter().map(|u| {
        crate::litecoin_wallet::LitecoinUtxo {
            transaction_hash: u.txid.clone(),
            index: u.vout,
            value: u.value,
            script_hex: None,
            block_id: u.block_height.map(|h| h as i64),
        }
    }).collect();
    
    // Parse amount
    let amount_lits: u64 = if request.amount.contains('.') {
        let ltc: f64 = request.amount.parse()
            .map_err(|_| HawalaError::invalid_input("Invalid amount format"))?;
        (ltc * 100_000_000.0) as u64
    } else {
        request.amount.parse()
            .map_err(|_| HawalaError::invalid_input("Invalid amount format"))?
    };
    
    // Get sender address from request
    let sender_address: &str = &request.from;
    
    match crate::litecoin_wallet::prepare_litecoin_transaction(
        &request.to,
        amount_lits,
        fee_rate,
        &request.private_key,
        sender_address,
        Some(ltc_utxos),
    ) {
        Ok(raw_tx) => {
            let txid = calculate_btc_txid(&raw_tx); // Same format as BTC
            
            Ok(SignedTransaction {
                chain: request.chain,
                raw_tx,
                txid,
                estimated_fee: Some(format!("{} lits/vB", fee_rate)),
                size_bytes: None,
            })
        }
        Err(e) => Err(HawalaError::new(ErrorCode::CryptoError, e.to_string())),
    }
}

// Helper to calculate Bitcoin-style txid
fn calculate_btc_txid(tx_hex: &str) -> String {
    use bitcoin::hashes::{Hash, sha256d};
    
    let tx_bytes = match hex::decode(tx_hex.trim_start_matches("0x")) {
        Ok(b) => b,
        Err(_) => return "unknown".to_string(),
    };
    
    let hash = sha256d::Hash::hash(&tx_bytes);
    let mut txid_bytes = hash.to_byte_array();
    txid_bytes.reverse(); // Bitcoin txids are displayed reversed
    hex::encode(txid_bytes)
}

// Helper to calculate Ethereum-style txid (keccak256 of RLP-encoded tx)
fn calculate_eth_txid(tx_hex: &str) -> String {
    use tiny_keccak::{Hasher, Keccak};
    
    let tx_bytes = match hex::decode(tx_hex.trim_start_matches("0x")) {
        Ok(b) => b,
        Err(_) => return "unknown".to_string(),
    };
    
    let mut hasher = Keccak::v256();
    hasher.update(&tx_bytes);
    let mut hash = [0u8; 32];
    hasher.finalize(&mut hash);
    
    format!("0x{}", hex::encode(hash))
}

/// Build a Solana transaction
pub fn build_solana_transaction(request: &TransactionRequest) -> HawalaResult<SignedTransaction> {
    // Parse amount as SOL
    let amount_sol: f64 = request.amount.parse()
        .map_err(|_| HawalaError::invalid_input("Invalid SOL amount"))?;
    
    let recent_blockhash = request.recent_blockhash.as_ref()
        .ok_or_else(|| HawalaError::invalid_input("Recent blockhash required for Solana transaction"))?;
    
    match crate::solana_wallet::prepare_solana_transaction(
        &request.to,
        amount_sol,
        recent_blockhash,
        &request.private_key,
    ) {
        Ok(raw_tx) => {
            Ok(SignedTransaction {
                chain: request.chain,
                raw_tx, // Base58 encoded
                txid: "pending".to_string(), // Signature returned on broadcast
                estimated_fee: Some("5000 lamports".to_string()),
                size_bytes: None,
            })
        }
        Err(e) => Err(HawalaError::new(ErrorCode::CryptoError, e.to_string())),
    }
}

/// Build an XRP transaction
pub fn build_xrp_transaction(request: &TransactionRequest) -> HawalaResult<SignedTransaction> {
    // Parse amount as drops (1 XRP = 1,000,000 drops)
    let amount_drops: u64 = if request.amount.contains('.') {
        let xrp: f64 = request.amount.parse()
            .map_err(|_| HawalaError::invalid_input("Invalid XRP amount"))?;
        (xrp * 1_000_000.0) as u64
    } else {
        request.amount.parse()
            .map_err(|_| HawalaError::invalid_input("Invalid drops amount"))?
    };
    
    let sequence = request.sequence
        .ok_or_else(|| HawalaError::invalid_input("Sequence number required for XRP transaction"))?;
    
    match crate::xrp_wallet::prepare_xrp_transaction(
        &request.to,
        amount_drops,
        &request.private_key,
        sequence,
        request.destination_tag,
    ) {
        Ok(raw_tx) => {
            Ok(SignedTransaction {
                chain: request.chain,
                raw_tx, // XRP blob uppercase hex
                txid: "pending".to_string(), // Hash returned on broadcast
                estimated_fee: Some("12 drops".to_string()),
                size_bytes: None,
            })
        }
        Err(e) => Err(HawalaError::new(ErrorCode::CryptoError, e.to_string())),
    }
}
