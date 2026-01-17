//! Hawala Core Library
//!
//! Rust backend for the Hawala multi-chain cryptocurrency wallet.
//! 
//! # Architecture
//! 
//! This crate provides:
//! - **wallet**: Key generation, derivation, and validation
//! - **tx**: Transaction building, signing, broadcasting
//! - **fees**: Fee estimation across all chains
//! - **history**: Transaction history fetching
//! - **api**: Unified blockchain API clients
//! - **ffi**: C-ABI exports for Swift integration
//!
//! # FFI Usage
//! 
//! All public FFI functions are in the `ffi` module and follow this pattern:
//! - Input: JSON string (null-terminated C string)
//! - Output: JSON string (must be freed with `hawala_free_string`)
//! 
//! # Security
//! 
//! This crate uses `zeroize` to securely clear sensitive data from memory.
//! All private keys, seeds, and entropy are automatically zeroed when dropped.
//! 
//! # Example
//! 
//! ```rust,ignore
//! use rust_app::wallet;
//! 
//! let (mnemonic, keys) = wallet::create_new_wallet()?;
//! println!("Mnemonic: {}", mnemonic);
//! println!("Bitcoin address: {}", keys.bitcoin.address);
//! ```

// Core modules (new structure)
pub mod error;
pub mod types;
pub mod ffi;
pub mod wallet;
pub mod tx;
pub mod fees;
pub mod history;
pub mod api;
pub mod utils;
pub mod security;

// Legacy modules (kept for compatibility during migration)
pub mod balances;
pub mod bitcoin_wallet;
pub mod ethereum_wallet;
pub mod solana_wallet;
pub mod monero_wallet;
pub mod xrp_wallet;
pub mod litecoin_wallet;
pub mod taproot_wallet;
pub mod history_legacy;

// Re-export key types for convenience
pub use error::{HawalaError, HawalaResult, ErrorCode};
pub use types::*;

// Re-export wallet functions
pub use wallet::{
    create_new_wallet,
    generate_keys_from_seed,
    restore_from_mnemonic,
    validate_mnemonic as wallet_validate_mnemonic,
};

// Re-export crypto utilities for binaries
pub use utils::crypto::{
    encode_litecoin_wif,
    keccak256,
    monero_base58_encode,
    to_checksum_address,
};

// Re-export FFI functions at crate root for backwards compatibility
pub use ffi::{
    hawala_free_string,
    hawala_generate_wallet,
    hawala_restore_wallet,
    hawala_validate_mnemonic,
    hawala_prepare_transaction,
    hawala_sign_transaction,
    hawala_broadcast_transaction,
    hawala_cancel_transaction,
    hawala_estimate_fees,
    hawala_fetch_history,
    hawala_track_transaction,
    hawala_fetch_balances,
    hawala_validate_address,
    // Legacy compatibility
    generate_keys_ffi,
    restore_wallet_ffi,
    validate_mnemonic_ffi,
    free_string,
};

// Re-export legacy functions that existing code depends on
// Note: these now return Balance struct instead of String
pub use balances::{fetch_bitcoin_balance, fetch_evm_balance as fetch_ethereum_balance};
pub use bitcoin_wallet::prepare_transaction;
pub use ethereum_wallet::prepare_ethereum_transaction;
pub use solana_wallet::prepare_solana_transaction;
pub use monero_wallet::prepare_monero_transaction;
pub use xrp_wallet::prepare_xrp_transaction;
pub use litecoin_wallet::prepare_litecoin_transaction;
pub use taproot_wallet::{prepare_taproot_transaction, prepare_taproot_transaction_from_wif, derive_taproot_address};
pub use history_legacy::fetch_bitcoin_history;

// =============================================================================
// Legacy FFI Exports (kept for backwards compatibility)
// These will be removed once Swift is fully migrated to new API
// =============================================================================

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// Helper to safely convert string to C pointer, returning error JSON on failure
fn safe_cstring(s: &str) -> *mut c_char {
    CString::new(s)
        .map(|cs| cs.into_raw())
        .unwrap_or_else(|_| {
            // If the string contains null bytes, return a safe error
            // SAFETY: This string is known to be valid
            CString::new(r#"{"error":"string conversion failed"}"#)
                .expect("static string is valid")
                .into_raw()
        })
}

/// Helper to create error JSON response
fn legacy_error_json(msg: &str) -> *mut c_char {
    safe_cstring(&format!(r#"{{"error":"{}"}}"#, msg.replace('"', "\\\"").replace('\n', " ")))
}

/// Legacy: Validate Ethereum address
#[unsafe(no_mangle)]
pub extern "C" fn validate_ethereum_address_ffi(address: *const c_char) -> bool {
    let c_str = unsafe {
        if address.is_null() { return false; }
        CStr::from_ptr(address)
    };

    match c_str.to_str() {
        Ok(addr) => {
            let (valid, _) = wallet::validate_address(addr, types::Chain::Ethereum);
            valid
        }
        Err(_) => false,
    }
}

/// Legacy: Fetch balances
#[unsafe(no_mangle)]
pub extern "C" fn fetch_balances_ffi(json_input: *const c_char) -> *mut c_char {
    let c_str = unsafe {
        if json_input.is_null() { return std::ptr::null_mut(); }
        CStr::from_ptr(json_input)
    };

    let json_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    #[derive(serde::Deserialize)]
    struct LegacyBalanceRequest {
        bitcoin: Option<String>,
        ethereum: Option<String>,
    }

    #[derive(serde::Serialize)]
    struct LegacyBalanceResponse {
        bitcoin: Option<String>,
        ethereum: Option<String>,
    }

    let request: LegacyBalanceRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(_) => return legacy_error_json("Invalid JSON"),
    };

    let btc_bal = if let Some(addr) = request.bitcoin {
        fetch_bitcoin_balance(&addr, types::Chain::Bitcoin)
            .map(|b| b.balance)
            .unwrap_or_else(|_| "0.00000000".to_string())
    } else {
        "0.00000000".to_string()
    };

    let eth_bal = if let Some(addr) = request.ethereum {
        fetch_ethereum_balance(&addr, types::Chain::Ethereum)
            .map(|b| b.balance)
            .unwrap_or_else(|_| "0.0000".to_string())
    } else {
        "0.0000".to_string()
    };

    let response = LegacyBalanceResponse {
        bitcoin: Some(btc_bal),
        ethereum: Some(eth_bal),
    };

    match serde_json::to_string(&response) {
        Ok(json) => safe_cstring(&json),
        Err(_) => legacy_error_json("JSON serialization failed"),
    }
}

/// Legacy: Fetch Bitcoin history
#[unsafe(no_mangle)]
pub extern "C" fn fetch_bitcoin_history_ffi(address: *const c_char) -> *mut c_char {
    let c_str = unsafe {
        if address.is_null() { return std::ptr::null_mut(); }
        CStr::from_ptr(address)
    };
    let addr_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return safe_cstring("[]"),
    };

    // Use legacy history function
    match crate::history_legacy::fetch_bitcoin_history(addr_str) {
        Ok(items) => {
            let json = serde_json::to_string(&items).unwrap_or_else(|_| "[]".to_string());
            safe_cstring(&json)
        },
        Err(_) => safe_cstring("[]"),
    }
}

/// Legacy: Prepare Bitcoin transaction
#[unsafe(no_mangle)]
pub extern "C" fn prepare_transaction_ffi(json_input: *const c_char) -> *mut c_char {
    let c_str = unsafe {
        if json_input.is_null() { return std::ptr::null_mut(); }
        CStr::from_ptr(json_input)
    };

    let json_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    #[derive(serde::Deserialize)]
    struct TransactionRequest {
        recipient: String,
        amount_sats: u64,
        fee_rate: u64,
        sender_wif: String,
        utxos: Option<Vec<bitcoin_wallet::Utxo>>,
    }

    let request: TransactionRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(_) => return legacy_error_json("Invalid JSON"),
    };

    match prepare_transaction(
        &request.recipient,
        request.amount_sats,
        request.fee_rate,
        &request.sender_wif,
        request.utxos,
    ) {
        Ok(hex) => safe_cstring(&format!(r#"{{"success": true, "tx_hex": "{}"}}"#, hex)),
        Err(e) => safe_cstring(&format!(r#"{{"success": false, "error": "{}"}}"#, e)),
    }
}

/// Legacy: Prepare Ethereum transaction
#[unsafe(no_mangle)]
pub extern "C" fn prepare_ethereum_transaction_ffi(json_input: *const c_char) -> *mut c_char {
    let c_str = unsafe {
        if json_input.is_null() { return std::ptr::null_mut(); }
        CStr::from_ptr(json_input)
    };

    let json_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    #[derive(serde::Deserialize)]
    struct EthTransactionRequest {
        recipient: String,
        amount: String,
        chain_id: u64,
        sender_key_hex: String,
        nonce: u64,
        gas_limit: u64,
        gas_price: Option<String>,
        max_fee_per_gas: Option<String>,
        max_priority_fee_per_gas: Option<String>,
        data: Option<String>,
    }

    let request: EthTransactionRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return legacy_error_json(&format!("Invalid JSON: {}", e)),
    };

    let data = request.data.unwrap_or_else(|| "0x".to_string());

    let rt = match tokio::runtime::Runtime::new() {
        Ok(rt) => rt,
        Err(e) => return legacy_error_json(&format!("Runtime error: {}", e)),
    };
    
    match rt.block_on(prepare_ethereum_transaction(
        &request.recipient,
        &request.amount,
        request.chain_id,
        &request.sender_key_hex,
        request.nonce,
        request.gas_limit,
        request.gas_price,
        request.max_fee_per_gas,
        request.max_priority_fee_per_gas,
        &data,
    )) {
        Ok(hex) => safe_cstring(&format!(r#"{{"success": true, "tx_hex": "0x{}"}}"#, hex)),
        Err(e) => safe_cstring(&format!(r#"{{"success": false, "error": "{}"}}"#, e)),
    }
}

/// Legacy: Prepare Taproot transaction
#[unsafe(no_mangle)]
pub extern "C" fn prepare_taproot_transaction_ffi(json_input: *const c_char) -> *mut c_char {
    let c_str = unsafe {
        if json_input.is_null() { return std::ptr::null_mut(); }
        CStr::from_ptr(json_input)
    };

    let json_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    #[derive(serde::Deserialize)]
    struct TaprootTransactionRequest {
        recipient: String,
        amount_sats: u64,
        fee_rate: u64,
        sender_wif: String,
        utxos: Option<Vec<taproot_wallet::Utxo>>,
    }

    let request: TaprootTransactionRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return legacy_error_json(&format!("Invalid JSON: {}", e)),
    };

    match prepare_taproot_transaction_from_wif(
        &request.recipient,
        request.amount_sats,
        request.fee_rate,
        &request.sender_wif,
        request.utxos,
    ) {
        Ok(hex) => safe_cstring(&format!(r#"{{"success": true, "tx_hex": "{}"}}"#, hex)),
        Err(e) => safe_cstring(&format!(r#"{{"success": false, "error": "{}"}}"#, e)),
    }
}

/// Legacy: Derive Taproot address
#[unsafe(no_mangle)]
pub extern "C" fn derive_taproot_address_ffi(wif: *const c_char) -> *mut c_char {
    let c_str = unsafe {
        if wif.is_null() { return std::ptr::null_mut(); }
        CStr::from_ptr(wif)
    };

    let wif_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let private_key = match bitcoin::PrivateKey::from_wif(wif_str) {
        Ok(pk) => pk,
        Err(e) => return legacy_error_json(&format!("Invalid WIF: {}", e)),
    };

    let network = match private_key.network {
        bitcoin::NetworkKind::Main => bitcoin::Network::Bitcoin,
        bitcoin::NetworkKind::Test => bitcoin::Network::Testnet,
    };

    let private_key_hex = hex::encode(private_key.inner.secret_bytes());

    match derive_taproot_address(&private_key_hex, network) {
        Ok((address, x_only_pubkey)) => {
            safe_cstring(&format!(
                r#"{{"success": true, "address": "{}", "x_only_pubkey": "{}"}}"#,
                address, x_only_pubkey
            ))
        }
        Err(e) => legacy_error_json(&e.to_string()),
    }
}

/// Legacy: Keccak256 hash
#[unsafe(no_mangle)]
pub extern "C" fn keccak256_ffi(data: *const u8, len: usize, output: *mut u8) {
    use tiny_keccak::{Hasher, Keccak};
    
    // Safety check for null pointers
    if data.is_null() || output.is_null() || len == 0 {
        return;
    }
    
    let slice = unsafe { std::slice::from_raw_parts(data, len) };
    let mut hasher = Keccak::v256();
    hasher.update(slice);
    let mut hash = [0u8; 32];
    hasher.finalize(&mut hash);
    unsafe {
        std::ptr::copy_nonoverlapping(hash.as_ptr(), output, 32);
    }
}
