//! Transaction Signer
//!
//! Signs transactions for all supported chains.
//! Currently delegates to wallet modules that combine prepare + sign.
//! Future: Support separate unsigned transaction signing.

use crate::error::{HawalaError, HawalaResult};
use crate::types::*;
use crate::{bitcoin_wallet, ethereum_wallet, litecoin_wallet, solana_wallet, xrp_wallet};

// =============================================================================
// Bitcoin Signing
// =============================================================================

/// Sign a Bitcoin transaction
/// Returns signed raw transaction hex ready for broadcast
pub fn sign_bitcoin_transaction(params: &BitcoinSignParams) -> HawalaResult<SignedTransaction> {
    // Convert UTXOs to bitcoin_wallet format
    let utxos = params.utxos.as_ref().map(|u| {
        u.iter().map(|utxo| bitcoin_wallet::Utxo {
            txid: utxo.txid.clone(),
            vout: utxo.vout,
            value: utxo.value,
            status: bitcoin_wallet::UtxoStatus {
                confirmed: true,
                block_height: None,
                block_hash: None,
                block_time: None,
            },
        }).collect::<Vec<_>>()
    });
    
    let signed_hex = bitcoin_wallet::prepare_transaction(
        &params.recipient,
        params.amount_sats,
        params.fee_rate_sats_per_vbyte,
        &params.sender_wif,
        utxos,
    ).map_err(|e| HawalaError::signing_failed(e.to_string()))?;
    
    // Calculate txid from raw hex
    let txid = calculate_bitcoin_txid(&signed_hex)?;
    
    Ok(SignedTransaction {
        chain: params.chain.clone(),
        raw_tx: signed_hex,
        txid,
        estimated_fee: None, // Could be calculated from tx size
        size_bytes: None,
    })
}

/// Calculate Bitcoin transaction ID from signed raw hex
fn calculate_bitcoin_txid(raw_hex: &str) -> HawalaResult<String> {
    use bitcoin::consensus::encode::deserialize;
    use bitcoin::Transaction;
    
    let raw_bytes = hex::decode(raw_hex)
        .map_err(|e| HawalaError::parse_error(format!("Invalid hex: {}", e)))?;
    
    let tx: Transaction = deserialize(&raw_bytes)
        .map_err(|e| HawalaError::parse_error(format!("Invalid transaction: {}", e)))?;
    
    Ok(tx.compute_txid().to_string())
}

// =============================================================================
// Litecoin Signing
// =============================================================================

/// Sign a Litecoin transaction
pub fn sign_litecoin_transaction(params: &LitecoinSignParams) -> HawalaResult<SignedTransaction> {
    // Convert UTXOs to litecoin_wallet format
    let utxos = params.utxos.as_ref().map(|u| {
        u.iter().map(|utxo| litecoin_wallet::LitecoinUtxo {
            transaction_hash: utxo.txid.clone(),
            index: utxo.vout,
            value: utxo.value,
            script_hex: None,
            block_id: None,
        }).collect::<Vec<_>>()
    });
    
    let signed_hex = litecoin_wallet::prepare_litecoin_transaction(
        &params.recipient,
        params.amount_lits,
        params.fee_rate_lits_per_vbyte,
        &params.sender_wif,
        &params.sender_address,
        utxos,
    ).map_err(|e| HawalaError::signing_failed(e.to_string()))?;
    
    // For Litecoin we don't have a good txid calculation, use placeholder
    // The txid will be returned by the broadcast response
    let txid = "pending".to_string();
    
    Ok(SignedTransaction {
        chain: Chain::Litecoin,
        raw_tx: signed_hex,
        txid,
        estimated_fee: None,
        size_bytes: None,
    })
}

// =============================================================================
// Ethereum/EVM Signing
// =============================================================================

/// Sign an Ethereum/EVM transaction
/// Note: This is async due to ethers-rs signing being async
pub fn sign_ethereum_transaction(params: &EthereumSignParams) -> HawalaResult<SignedTransaction> {
    // Use tokio runtime for async operation
    let runtime = tokio::runtime::Runtime::new()
        .map_err(|e| HawalaError::internal(format!("Failed to create runtime: {}", e)))?;
    
    let signed_hex = runtime.block_on(async {
        ethereum_wallet::prepare_ethereum_transaction(
            &params.recipient,
            &params.amount_wei,
            params.chain_id,
            &params.sender_key_hex,
            params.nonce,
            params.gas_limit,
            params.gas_price_wei.clone(),
            params.max_fee_per_gas_wei.clone(),
            params.max_priority_fee_per_gas_wei.clone(),
            &params.data_hex.clone().unwrap_or_default(),
        ).await
    }).map_err(|e| HawalaError::signing_failed(e.to_string()))?;
    
    // Extract txid from signed transaction
    let txid = extract_eth_txid(&signed_hex)?;
    
    Ok(SignedTransaction {
        chain: chain_from_id(params.chain_id),
        raw_tx: signed_hex,
        txid,
        estimated_fee: None,
        size_bytes: None,
    })
}

/// Extract transaction hash from signed EVM transaction
fn extract_eth_txid(raw_hex: &str) -> HawalaResult<String> {
    use tiny_keccak::{Hasher, Keccak};
    
    let hex_clean = raw_hex.trim_start_matches("0x");
    let raw_bytes = hex::decode(hex_clean)
        .map_err(|e| HawalaError::parse_error(format!("Invalid hex: {}", e)))?;
    
    let mut hasher = Keccak::v256();
    hasher.update(&raw_bytes);
    let mut hash = [0u8; 32];
    hasher.finalize(&mut hash);
    Ok(format!("0x{}", hex::encode(hash)))
}

// =============================================================================
// Solana Signing
// =============================================================================

/// Sign a Solana transaction
pub fn sign_solana_transaction(params: &SolanaSignParams) -> HawalaResult<SignedTransaction> {
    let signed_base58 = solana_wallet::prepare_solana_transaction(
        &params.recipient,
        params.amount_sol,
        &params.recent_blockhash,
        &params.sender_base58,
    ).map_err(|e| HawalaError::signing_failed(e.to_string()))?;
    
    // Solana signature/txid comes from broadcast response
    let txid = "pending".to_string();
    
    Ok(SignedTransaction {
        chain: Chain::Solana,
        raw_tx: signed_base58,
        txid,
        estimated_fee: None,
        size_bytes: None,
    })
}

// =============================================================================
// XRP Signing
// =============================================================================

/// Sign an XRP transaction
pub fn sign_xrp_transaction(params: &XrpSignParams) -> HawalaResult<SignedTransaction> {
    let signed_blob = xrp_wallet::prepare_xrp_transaction(
        &params.recipient,
        params.amount_drops,
        &params.sender_seed_hex,
        params.sequence,
        params.destination_tag,
    ).map_err(|e| HawalaError::signing_failed(e.to_string()))?;
    
    // XRP hash comes from broadcast response
    let txid = "pending".to_string();
    
    Ok(SignedTransaction {
        chain: Chain::Xrp,
        raw_tx: signed_blob,
        txid,
        estimated_fee: None,
        size_bytes: None,
    })
}

// =============================================================================
// Unified Signing Interface
// =============================================================================

/// Generic sign parameters enum
#[derive(Debug, Clone)]
pub enum SignParams {
    Bitcoin(BitcoinSignParams),
    Litecoin(LitecoinSignParams),
    Ethereum(EthereumSignParams),
    Solana(SolanaSignParams),
    Xrp(XrpSignParams),
}

/// Bitcoin signing parameters
#[derive(Debug, Clone)]
pub struct BitcoinSignParams {
    pub chain: Chain, // Bitcoin or BitcoinTestnet
    pub recipient: String,
    pub amount_sats: u64,
    pub fee_rate_sats_per_vbyte: u64,
    pub sender_wif: String,
    pub utxos: Option<Vec<UtxoInput>>,
}

/// Litecoin signing parameters
#[derive(Debug, Clone)]
pub struct LitecoinSignParams {
    pub recipient: String,
    pub amount_lits: u64,
    pub fee_rate_lits_per_vbyte: u64,
    pub sender_wif: String,
    pub sender_address: String,
    pub utxos: Option<Vec<UtxoInput>>,
}

/// Ethereum/EVM signing parameters
#[derive(Debug, Clone)]
pub struct EthereumSignParams {
    pub recipient: String,
    pub amount_wei: String,
    pub chain_id: u64,
    pub sender_key_hex: String,
    pub nonce: u64,
    pub gas_limit: u64,
    pub gas_price_wei: Option<String>,
    pub max_fee_per_gas_wei: Option<String>,
    pub max_priority_fee_per_gas_wei: Option<String>,
    pub data_hex: Option<String>,
}

/// Solana signing parameters
#[derive(Debug, Clone)]
pub struct SolanaSignParams {
    pub recipient: String,
    pub amount_sol: f64,
    pub recent_blockhash: String,
    pub sender_base58: String,
}

/// XRP signing parameters
#[derive(Debug, Clone)]
pub struct XrpSignParams {
    pub recipient: String,
    pub amount_drops: u64,
    pub sender_seed_hex: String,
    pub sequence: u32,
    pub destination_tag: Option<u32>,
}

/// UTXO input for Bitcoin/Litecoin
#[derive(Debug, Clone)]
pub struct UtxoInput {
    pub txid: String,
    pub vout: u32,
    pub value: u64,
}

/// Unified transaction signing function
pub fn sign_transaction(params: SignParams) -> HawalaResult<SignedTransaction> {
    match params {
        SignParams::Bitcoin(p) => sign_bitcoin_transaction(&p),
        SignParams::Litecoin(p) => sign_litecoin_transaction(&p),
        SignParams::Ethereum(p) => sign_ethereum_transaction(&p),
        SignParams::Solana(p) => sign_solana_transaction(&p),
        SignParams::Xrp(p) => sign_xrp_transaction(&p),
    }
}

// =============================================================================
// Helper Functions
// =============================================================================

fn chain_from_id(chain_id: u64) -> Chain {
    match chain_id {
        1 => Chain::Ethereum,
        11155111 => Chain::EthereumSepolia,
        56 => Chain::Bnb,
        137 => Chain::Polygon,
        42161 => Chain::Arbitrum,
        10 => Chain::Optimism,
        8453 => Chain::Base,
        43114 => Chain::Avalanche,
        _ => Chain::Ethereum,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_chain_from_id() {
        assert!(matches!(chain_from_id(1), Chain::Ethereum));
        assert!(matches!(chain_from_id(56), Chain::Bnb));
        assert!(matches!(chain_from_id(137), Chain::Polygon));
    }
}
