//! FFI Layer for Hawala Core
//!
//! All C-ABI exports are defined here. This is the ONLY file that should
//! contain `extern "C"` functions. All functions follow a consistent pattern:
//! - Input: JSON string (null-terminated C string)
//! - Output: JSON string (must be freed with `hawala_free_string`)
//!
//! Error handling: All functions return JSON with `success` field.
//! On error, `success: false` and `error` object is populated.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::str::FromStr;

use crate::error::{HawalaError, ErrorCode};
use crate::types::*;
use crate::wallet;

// =============================================================================
// Memory Management
// =============================================================================

/// Free a string returned by any hawala_* function
/// 
/// # Safety
/// The pointer must have been returned by a hawala_* function
#[unsafe(no_mangle)]
pub extern "C" fn hawala_free_string(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(s);
    }
}

// =============================================================================
// Helper Functions
// =============================================================================

/// Convert C string to Rust string, returning error JSON if invalid
fn parse_input(input: *const c_char) -> Result<&'static str, *mut c_char> {
    if input.is_null() {
        return Err(error_response(HawalaError::invalid_input("Null input pointer")));
    }
    
    let c_str = unsafe { CStr::from_ptr(input) };
    match c_str.to_str() {
        Ok(s) => Ok(unsafe { std::mem::transmute::<&str, &'static str>(s) }),
        Err(_) => Err(error_response(HawalaError::invalid_input("Invalid UTF-8 string"))),
    }
}

/// Create a success response JSON string
fn success_response<T: serde::Serialize>(data: T) -> *mut c_char {
    let response = ApiResponse::ok(data);
    string_to_ptr(response.to_json())
}

/// Create an error response JSON string
fn error_response(error: HawalaError) -> *mut c_char {
    let response: ApiResponse<()> = ApiResponse::err(error);
    string_to_ptr(response.to_json())
}

/// Convert Rust string to C string pointer
fn string_to_ptr(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(c_str) => c_str.into_raw(),
        Err(_) => {
            // Last resort: return a minimal error
            CString::new(r#"{"success":false,"error":{"code":"internal","message":"String conversion failed"}}"#)
                .unwrap()
                .into_raw()
        }
    }
}

// =============================================================================
// Wallet Operations
// =============================================================================

/// Generate a new wallet with mnemonic and keys for all chains
/// 
/// # Input
/// None (empty string or "{}")
/// 
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "mnemonic": "word1 word2 ...",
///     "keys": { ... }
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_generate_wallet() -> *mut c_char {
    match wallet::create_new_wallet() {
        Ok((mnemonic, keys)) => {
            success_response(WalletResponse { mnemonic, keys })
        }
        Err(e) => error_response(e),
    }
}

/// Restore wallet from mnemonic phrase
/// 
/// # Input
/// ```json
/// { "mnemonic": "word1 word2 ..." }
/// ```
/// 
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": { "bitcoin": {...}, "ethereum": {...}, ... }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_restore_wallet(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct RestoreRequest {
        mnemonic: String,
    }

    let request: RestoreRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    match wallet::restore_from_mnemonic(&request.mnemonic) {
        Ok(keys) => success_response(keys),
        Err(e) => error_response(e),
    }
}

/// Validate a mnemonic phrase
/// 
/// # Input
/// ```json
/// { "mnemonic": "word1 word2 ..." }
/// ```
/// 
/// # Output
/// ```json
/// { "success": true, "data": { "valid": true } }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_validate_mnemonic(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct ValidateRequest {
        mnemonic: String,
    }

    #[derive(serde::Serialize)]
    struct ValidateResponse {
        valid: bool,
    }

    let request: ValidateRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    let valid = wallet::validate_mnemonic(&request.mnemonic);
    success_response(ValidateResponse { valid })
}

// =============================================================================
// Transaction Operations (Stubs - Phase 2)
// =============================================================================

/// Prepare a transaction for signing
/// 
/// # Input
/// See `TransactionRequest` in types.rs
/// 
/// # Output
/// Unsigned transaction data
#[unsafe(no_mangle)]
pub extern "C" fn hawala_prepare_transaction(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    let request: TransactionRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    // Dispatch to chain-specific handler
    match request.chain {
        Chain::Bitcoin | Chain::BitcoinTestnet => {
            crate::tx::prepare_bitcoin_transaction(&request)
        }
        Chain::Ethereum | Chain::EthereumSepolia | Chain::Bnb | Chain::Polygon 
        | Chain::Arbitrum | Chain::Optimism | Chain::Base | Chain::Avalanche => {
            crate::tx::prepare_evm_transaction(&request)
        }
        Chain::Litecoin => {
            crate::tx::prepare_litecoin_transaction(&request)
        }
        Chain::Solana | Chain::SolanaDevnet => {
            crate::tx::prepare_solana_transaction(&request)
        }
        Chain::Xrp | Chain::XrpTestnet => {
            crate::tx::prepare_xrp_transaction(&request)
        }
        Chain::Monero => {
            error_response(HawalaError::new(ErrorCode::NotImplemented, "Monero transactions not yet supported"))
        }
    }
}

/// Sign a prepared transaction
#[unsafe(no_mangle)]
pub extern "C" fn hawala_sign_transaction(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    // Parse signing request and dispatch to appropriate signer
    let result: Result<SignedTransaction, HawalaError> = (|| {
        let v: serde_json::Value = serde_json::from_str(&json_str)
            .map_err(|e| HawalaError::parse_error(e.to_string()))?;
        
        let chain_str = v["chain"].as_str()
            .ok_or_else(|| HawalaError::invalid_input("Missing chain"))?;
        
        match chain_str.to_lowercase().as_str() {
            "bitcoin" | "bitcoin_testnet" => {
                let params = crate::tx::BitcoinSignParams {
                    chain: if chain_str.contains("testnet") { Chain::BitcoinTestnet } else { Chain::Bitcoin },
                    recipient: v["recipient"].as_str().unwrap_or_default().to_string(),
                    amount_sats: v["amount_sats"].as_u64().unwrap_or(0),
                    fee_rate_sats_per_vbyte: v["fee_rate"].as_u64().unwrap_or(1),
                    sender_wif: v["sender_wif"].as_str().unwrap_or_default().to_string(),
                    utxos: None, // Would parse from v["utxos"] if provided
                };
                crate::tx::sign_bitcoin_transaction(&params)
            }
            "ethereum" | "ethereum_sepolia" | "bnb" | "polygon" | "arbitrum" | "optimism" | "base" | "avalanche" => {
                let params = crate::tx::EthereumSignParams {
                    recipient: v["recipient"].as_str().unwrap_or_default().to_string(),
                    amount_wei: v["amount_wei"].as_str().unwrap_or("0").to_string(),
                    chain_id: v["chain_id"].as_u64().unwrap_or(1),
                    sender_key_hex: v["sender_key"].as_str().unwrap_or_default().to_string(),
                    nonce: v["nonce"].as_u64().unwrap_or(0),
                    gas_limit: v["gas_limit"].as_u64().unwrap_or(21000),
                    gas_price_wei: v["gas_price"].as_str().map(|s| s.to_string()),
                    max_fee_per_gas_wei: v["max_fee_per_gas"].as_str().map(|s| s.to_string()),
                    max_priority_fee_per_gas_wei: v["max_priority_fee"].as_str().map(|s| s.to_string()),
                    data_hex: v["data"].as_str().map(|s| s.to_string()),
                };
                crate::tx::sign_ethereum_transaction(&params)
            }
            "solana" | "solana_devnet" => {
                let params = crate::tx::SolanaSignParams {
                    recipient: v["recipient"].as_str().unwrap_or_default().to_string(),
                    amount_sol: v["amount_sol"].as_f64().unwrap_or(0.0),
                    recent_blockhash: v["recent_blockhash"].as_str().unwrap_or_default().to_string(),
                    sender_base58: v["sender_key"].as_str().unwrap_or_default().to_string(),
                };
                crate::tx::sign_solana_transaction(&params)
            }
            "xrp" | "xrp_testnet" => {
                let params = crate::tx::XrpSignParams {
                    recipient: v["recipient"].as_str().unwrap_or_default().to_string(),
                    amount_drops: v["amount_drops"].as_u64().unwrap_or(0),
                    sender_seed_hex: v["sender_seed"].as_str().unwrap_or_default().to_string(),
                    sequence: v["sequence"].as_u64().unwrap_or(0) as u32,
                    destination_tag: v["destination_tag"].as_u64().map(|n| n as u32),
                };
                crate::tx::sign_xrp_transaction(&params)
            }
            _ => Err(HawalaError::invalid_input(format!("Unsupported chain: {}", chain_str))),
        }
    })();
    
    match result {
        Ok(signed) => success_response(signed),
        Err(e) => error_response(e),
    }
}

/// Broadcast a signed transaction
#[unsafe(no_mangle)]
pub extern "C" fn hawala_broadcast_transaction(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    let result: Result<BroadcastResult, HawalaError> = (|| {
        let v: serde_json::Value = serde_json::from_str(&json_str)
            .map_err(|e| HawalaError::parse_error(e.to_string()))?;
        
        let chain_str = v["chain"].as_str()
            .ok_or_else(|| HawalaError::invalid_input("Missing chain"))?;
        let raw_tx = v["raw_tx"].as_str()
            .ok_or_else(|| HawalaError::invalid_input("Missing raw_tx"))?;
        
        let chain = Chain::from_str(chain_str)
            .map_err(|_| HawalaError::invalid_input(format!("Invalid chain: {}", chain_str)))?;
        
        crate::tx::broadcast_transaction(chain, raw_tx)
    })();
    
    match result {
        Ok(broadcast) => success_response(broadcast),
        Err(e) => error_response(e),
    }
}

/// Cancel a pending transaction (RBF/nonce replacement)
#[unsafe(no_mangle)]
pub extern "C" fn hawala_cancel_transaction(input: *const c_char) -> *mut c_char {
    let _json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    // TODO: Phase 4 implementation
    error_response(HawalaError::new(ErrorCode::NotImplemented, "Cancel transaction coming in Phase 4"))
}

// =============================================================================
// Fee Operations
// =============================================================================

/// Get fee estimates for a chain
/// 
/// # Input
/// ```json
/// { "chain": "bitcoin" }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_estimate_fees(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct FeeRequest {
        chain: Chain,
    }

    let request: FeeRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    crate::fees::estimate_fees(request.chain)
}

/// Estimate gas for an EVM transaction
/// 
/// # Input
/// ```json
/// {
///   "from": "0x...",
///   "to": "0x...",
///   "data": "0x...",
///   "value": "0",
///   "chain_id": 1
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_estimate_gas(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct GasRequest {
        from: String,
        to: String,
        #[serde(default)]
        data: Option<String>,
        #[serde(default)]
        value: Option<String>,
        chain_id: u64,
    }

    let request: GasRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    let data = request.data.as_deref().unwrap_or("");
    let value = request.value.as_deref().unwrap_or("0");

    match crate::fees::estimate_gas_limit(
        request.chain_id,
        &request.from,
        &request.to,
        value,
        data,
    ) {
        Ok(result) => success_response(result),
        Err(e) => error_response(e),
    }
}

/// Analyze fees and get intelligent recommendations
/// 
/// # Input
/// ```json
/// { "chain": "bitcoin" }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_analyze_fees(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct AnalyzeRequest {
        chain: Chain,
    }

    let request: AnalyzeRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    // First get the fee estimate
    match crate::fees::get_fee_estimate(request.chain) {
        Ok(estimate) => {
            // Then analyze it
            match crate::fees::analyze_fees(&estimate) {
                Ok(intel) => success_response(intel),
                Err(e) => error_response(e),
            }
        }
        Err(e) => error_response(e),
    }
}

// =============================================================================
// Transaction Cancellation & Tracking (Phase 4)
// =============================================================================

/// Cancel a Bitcoin/Litecoin transaction using RBF
/// 
/// # Input
/// ```json
/// {
///   "original_txid": "abc...",
///   "utxos": [{"txid": "...", "vout": 0, "value": 10000, "script_pubkey": "..."}],
///   "return_address": "bc1q...",
///   "private_key_wif": "...",
///   "new_fee_rate": 50,
///   "is_testnet": false,
///   "is_litecoin": false
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_cancel_bitcoin(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    let request: crate::tx::BitcoinCancelRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    match crate::tx::cancel_bitcoin_rbf(&request) {
        Ok(result) => success_response(result),
        Err(e) => error_response(e),
    }
}

/// Speed up a Bitcoin/Litecoin transaction using RBF
#[unsafe(no_mangle)]
pub extern "C" fn hawala_speedup_bitcoin(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    let request: crate::tx::BitcoinSpeedUpRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    match crate::tx::speed_up_bitcoin_rbf(&request) {
        Ok(result) => success_response(result),
        Err(e) => error_response(e),
    }
}

/// Cancel an Ethereum/EVM transaction using nonce replacement
/// 
/// # Input
/// ```json
/// {
///   "original_txid": "0x...",
///   "nonce": 42,
///   "from_address": "0x...",
///   "private_key_hex": "...",
///   "new_gas_price": "50000000000",
///   "chain_id": 1
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_cancel_evm(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    let request: crate::tx::EvmCancelRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    match crate::tx::cancel_evm_nonce(&request) {
        Ok(result) => success_response(result),
        Err(e) => error_response(e),
    }
}

/// Speed up an Ethereum/EVM transaction
#[unsafe(no_mangle)]
pub extern "C" fn hawala_speedup_evm(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    let request: crate::tx::EvmSpeedUpRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    match crate::tx::speed_up_evm(&request) {
        Ok(result) => success_response(result),
        Err(e) => error_response(e),
    }
}

/// Track a transaction's confirmations
/// 
/// # Input
/// ```json
/// { "txid": "abc...", "chain": "bitcoin" }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_track_transaction(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct TrackRequest {
        txid: String,
        chain: Chain,
    }

    let request: TrackRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    match crate::tx::track_transaction(&request.txid, request.chain) {
        Ok(result) => success_response(result),
        Err(e) => error_response(e),
    }
}

/// Get confirmations for a transaction
/// 
/// # Input
/// ```json
/// { "txid": "abc...", "chain": "bitcoin" }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_get_confirmations(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct ConfirmRequest {
        txid: String,
        chain: Chain,
    }

    #[derive(serde::Serialize)]
    struct ConfirmResponse {
        txid: String,
        confirmations: u32,
        required: u32,
        is_confirmed: bool,
    }

    let request: ConfirmRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    match crate::tx::get_confirmations(&request.txid, request.chain) {
        Ok(confs) => {
            let required = crate::tx::required_confirmations(request.chain);
            success_response(ConfirmResponse {
                txid: request.txid,
                confirmations: confs,
                required,
                is_confirmed: confs >= required,
            })
        }
        Err(e) => error_response(e),
    }
}

/// Get transaction status
/// 
/// # Input
/// ```json
/// { "txid": "abc...", "chain": "bitcoin" }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_get_tx_status(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct StatusRequest {
        txid: String,
        chain: Chain,
    }

    let request: StatusRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    match crate::tx::get_transaction_status(&request.txid, request.chain) {
        Ok(status) => success_response(status),
        Err(e) => error_response(e),
    }
}

// =============================================================================
// History Operations
// =============================================================================

/// Fetch transaction history
/// 
/// # Input
/// See `HistoryRequest` in types.rs
#[unsafe(no_mangle)]
pub extern "C" fn hawala_fetch_history(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    let request: HistoryRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    crate::history::fetch_history(&request)
}

// =============================================================================
// Balance Operations
// =============================================================================

/// Fetch balances for multiple addresses
/// 
/// # Input
/// ```json
/// {
///   "addresses": [
///     { "address": "bc1q...", "chain": "bitcoin" },
///     { "address": "0x...", "chain": "ethereum" }
///   ]
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_fetch_balances(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    let request: BalanceRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    crate::api::fetch_balances(&request)
}

// =============================================================================
// Address Validation
// =============================================================================

/// Validate an address for a specific chain
/// 
/// # Input
/// ```json
/// { "address": "0x...", "chain": "ethereum" }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_validate_address(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct ValidateAddressRequest {
        address: String,
        chain: Chain,
    }

    #[derive(serde::Serialize)]
    struct ValidateAddressResponse {
        valid: bool,
        normalized: Option<String>,
    }

    let request: ValidateAddressRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    let (valid, normalized) = crate::wallet::validate_address(&request.address, request.chain);
    success_response(ValidateAddressResponse { valid, normalized })
}

// =============================================================================
// Token Balance Operations (Phase 5)
// =============================================================================

/// Fetch ERC-20 token balance
/// 
/// # Input
/// ```json
/// { "address": "0x...", "token_contract": "0x...", "chain": "ethereum" }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_fetch_token_balance(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct TokenBalanceRequest {
        address: String,
        token_contract: String,
        chain: Chain,
    }

    let request: TokenBalanceRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    match crate::balances::fetch_erc20_balance(&request.address, &request.token_contract, request.chain) {
        Ok(balance) => success_response(balance),
        Err(e) => error_response(e),
    }
}

/// Fetch SPL token balance (Solana)
/// 
/// # Input
/// ```json
/// { "address": "...", "mint": "...", "chain": "solana" }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_fetch_spl_balance(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct SplBalanceRequest {
        address: String,
        mint: String,
        chain: Chain,
    }

    let request: SplBalanceRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    match crate::balances::fetch_spl_balance(&request.address, &request.mint, request.chain) {
        Ok(balance) => success_response(balance),
        Err(e) => error_response(e),
    }
}

/// Fetch single address balance
/// 
/// # Input
/// ```json
/// { "address": "...", "chain": "bitcoin" }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_fetch_balance(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct SingleBalanceRequest {
        address: String,
        chain: Chain,
    }

    let request: SingleBalanceRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    match crate::balances::fetch_balance(&request.address, request.chain) {
        Ok(balance) => success_response(balance),
        Err(e) => error_response(e),
    }
}

/// Fetch single chain history
/// 
/// # Input
/// ```json
/// { "address": "...", "chain": "bitcoin" }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_fetch_chain_history(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct SingleHistoryRequest {
        address: String,
        chain: Chain,
    }

    let request: SingleHistoryRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    match crate::history::fetch_chain_history(&request.address, request.chain) {
        Ok(entries) => success_response(entries),
        Err(e) => error_response(e),
    }
}

// =============================================================================
// UTXO Management (Phase 6)
// =============================================================================

/// Fetch UTXOs for an address
/// 
/// # Input
/// ```json
/// { "address": "bc1q...", "chain": "bitcoin" }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_fetch_utxos(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct UTXORequest {
        address: String,
        chain: Chain,
    }

    let request: UTXORequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    match crate::wallet::utxo::fetch_managed_utxos(&request.address, request.chain) {
        Ok(utxos) => success_response(utxos),
        Err(e) => error_response(e),
    }
}

/// Select UTXOs for a target amount
/// 
/// # Input
/// ```json
/// { "address": "bc1q...", "chain": "bitcoin", "amount": 100000, "fee_rate": 10, "strategy": "optimal" }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_select_utxos(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct SelectRequest {
        address: String,
        chain: Chain,
        amount: u64,
        fee_rate: u64,
        #[serde(default)]
        strategy: crate::wallet::utxo::UTXOSelectionStrategy,
    }

    let request: SelectRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    // First fetch UTXOs
    let utxos = match crate::wallet::utxo::fetch_managed_utxos(&request.address, request.chain) {
        Ok(u) => u,
        Err(e) => return error_response(e),
    };

    match crate::wallet::utxo::select_utxos(&utxos, request.amount, request.fee_rate, request.strategy) {
        Ok(selection) => success_response(selection),
        Err(e) => error_response(e),
    }
}

/// Set UTXO metadata (label, source, frozen, note)
/// 
/// # Input
/// ```json
/// { "key": "txid:vout", "label": "Salary", "source": "exchange", "is_frozen": false }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_set_utxo_metadata(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct MetadataRequest {
        key: String,
        #[serde(default)]
        label: String,
        #[serde(default)]
        source: crate::wallet::utxo::UTXOSource,
        #[serde(default)]
        is_frozen: bool,
        #[serde(default)]
        note: String,
    }

    let request: MetadataRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    let metadata = crate::wallet::utxo::UTXOMetadata {
        label: request.label,
        source: request.source,
        is_frozen: request.is_frozen,
        note: request.note,
    };

    crate::wallet::utxo::set_utxo_metadata(&request.key, metadata);
    success_response(serde_json::json!({"success": true}))
}

// =============================================================================
// Nonce Management (Phase 6)
// =============================================================================

/// Get next available nonce for an EVM address
/// 
/// # Input
/// ```json
/// { "address": "0x...", "chain_id": 1 }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_get_nonce(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct NonceRequest {
        address: String,
        chain_id: u64,
    }

    let request: NonceRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    match crate::wallet::nonce::get_next_nonce(&request.address, request.chain_id) {
        Ok(result) => success_response(result),
        Err(e) => error_response(e),
    }
}

/// Reserve a nonce for a pending transaction
/// 
/// # Input
/// ```json
/// { "address": "0x...", "chain_id": 1, "nonce": 42 }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_reserve_nonce(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct ReserveRequest {
        address: String,
        chain_id: u64,
        nonce: u64,
    }

    let request: ReserveRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    match crate::wallet::nonce::reserve_nonce(&request.address, request.chain_id, request.nonce) {
        Ok(_) => success_response(serde_json::json!({"reserved": request.nonce})),
        Err(e) => error_response(e),
    }
}

/// Confirm a nonce (transaction included in block)
/// 
/// # Input
/// ```json
/// { "address": "0x...", "chain_id": 1, "nonce": 42 }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_confirm_nonce(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct ConfirmRequest {
        address: String,
        chain_id: u64,
        nonce: u64,
    }

    let request: ConfirmRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    match crate::wallet::nonce::confirm_nonce(&request.address, request.chain_id, request.nonce) {
        Ok(_) => success_response(serde_json::json!({"confirmed": request.nonce})),
        Err(e) => error_response(e),
    }
}

/// Detect nonce gaps
/// 
/// # Input
/// ```json
/// { "address": "0x...", "chain_id": 1 }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_detect_nonce_gaps(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct GapRequest {
        address: String,
        chain_id: u64,
    }

    let request: GapRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    match crate::wallet::nonce::detect_nonce_gaps(&request.address, request.chain_id) {
        Ok(gaps) => success_response(gaps),
        Err(e) => error_response(e),
    }
}

// =============================================================================
// Legacy FFI Compatibility
// =============================================================================
// These functions maintain compatibility with existing Swift code
// They will be deprecated once the new Swift bridge is fully integrated

/// Legacy: Generate keys (returns old format)
#[unsafe(no_mangle)]
pub extern "C" fn generate_keys_ffi() -> *mut c_char {
    match wallet::create_new_wallet() {
        Ok((mnemonic, keys)) => {
            // Return old format for compatibility
            #[derive(serde::Serialize)]
            struct LegacyResponse {
                mnemonic: String,
                keys: AllKeys,
            }
            let response = LegacyResponse { mnemonic, keys };
            match serde_json::to_string(&response) {
                Ok(json) => string_to_ptr(json),
                Err(_) => std::ptr::null_mut(),
            }
        }
        Err(_) => std::ptr::null_mut(),
    }
}

/// Legacy: Restore wallet (returns old format)
#[unsafe(no_mangle)]
pub extern "C" fn restore_wallet_ffi(mnemonic_str: *const c_char) -> *mut c_char {
    let c_str = unsafe {
        if mnemonic_str.is_null() { return std::ptr::null_mut(); }
        CStr::from_ptr(mnemonic_str)
    };
    
    let phrase = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    match wallet::restore_from_mnemonic(phrase) {
        Ok(keys) => {
            match serde_json::to_string(&keys) {
                Ok(json) => string_to_ptr(json),
                Err(_) => std::ptr::null_mut(),
            }
        }
        Err(_) => std::ptr::null_mut(),
    }
}

/// Legacy: Validate mnemonic
#[unsafe(no_mangle)]
pub extern "C" fn validate_mnemonic_ffi(mnemonic_str: *const c_char) -> bool {
    let c_str = unsafe {
        if mnemonic_str.is_null() { return false; }
        CStr::from_ptr(mnemonic_str)
    };
    
    match c_str.to_str() {
        Ok(s) => wallet::validate_mnemonic(s),
        Err(_) => false,
    }
}

/// Legacy: Free string
#[unsafe(no_mangle)]
pub extern "C" fn free_string(s: *mut c_char) {
    hawala_free_string(s);
}

// =============================================================================
// Security Operations (Phase 5)
// =============================================================================

/// Assess transaction for threats
/// 
/// # Input
/// ```json
/// {
///   "wallet_id": "wallet_123",
///   "recipient": "0x...",
///   "amount": "1000000000000000000",
///   "chain": "ethereum"
/// }
/// ```
/// 
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "risk_level": "low|medium|high|critical",
///     "flags": ["new_recipient", "large_amount"],
///     "warnings": ["First time sending to this address"],
///     "blocked": false,
///     "block_reason": null
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_assess_threat(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct ThreatRequest {
        wallet_id: String,
        recipient: String,
        amount: String,
        chain: String,
    }

    let request: ThreatRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    let chain = match Chain::from_str(&request.chain) {
        Ok(c) => c,
        Err(e) => return error_response(HawalaError::invalid_input(e)),
    };

    let amount: u128 = match request.amount.parse() {
        Ok(a) => a,
        Err(_) => return error_response(HawalaError::invalid_input("Invalid amount format")),
    };

    let detector = crate::security::threat_detection::get_threat_detector();
    // Pass empty known addresses - in real implementation, this would come from wallet service
    let known_addresses: Vec<String> = Vec::new();
    let assessment = detector.assess_transaction(&request.wallet_id, &request.recipient, amount, chain, &known_addresses);

    #[derive(serde::Serialize)]
    struct ThreatResponse {
        risk_level: String,
        threats: Vec<ThreatInfo>,
        recommendations: Vec<String>,
        allow_transaction: bool,
    }

    #[derive(serde::Serialize)]
    struct ThreatInfo {
        threat_type: String,
        severity: String,
        description: String,
    }

    let threats: Vec<ThreatInfo> = assessment.threats.iter().map(|t| ThreatInfo {
        threat_type: format!("{:?}", t.threat_type),
        severity: format!("{:?}", t.severity).to_lowercase(),
        description: t.description.clone(),
    }).collect();

    let response = ThreatResponse {
        risk_level: format!("{:?}", assessment.risk_level).to_lowercase(),
        threats,
        recommendations: assessment.recommendations,
        allow_transaction: assessment.allow_transaction,
    };

    success_response(response)
}

/// Blacklist an address
/// 
/// # Input
/// ```json
/// { "address": "0x...", "reason": "Known scam address" }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_blacklist_address(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct BlacklistRequest {
        address: String,
        reason: String,
    }

    let request: BlacklistRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    let detector = crate::security::threat_detection::get_threat_detector();
    detector.blacklist_address(&request.address);

    success_response(serde_json::json!({"blacklisted": true}))
}

/// Whitelist an address
/// 
/// # Input
/// ```json
/// { "address": "0x...", "label": "My cold wallet" }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_whitelist_address(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct WhitelistRequest {
        wallet_id: String,
        address: String,
    }

    let request: WhitelistRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    let detector = crate::security::threat_detection::get_threat_detector();
    detector.whitelist_address(&request.wallet_id, &request.address);

    success_response(serde_json::json!({"whitelisted": true}))
}

/// Check transaction against spending policies
/// 
/// # Input
/// ```json
/// {
///   "wallet_id": "wallet_123",
///   "recipient": "0x...",
///   "amount": "1000000000000000000",
///   "chain": "ethereum"
/// }
/// ```
/// 
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "allowed": true,
///     "reason": null,
///     "remaining_daily": "5000000000000000000",
///     "requires_approval": false
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_check_policy(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct PolicyRequest {
        wallet_id: String,
        recipient: String,
        amount: String,
        chain: String,
    }

    let request: PolicyRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    let chain = match Chain::from_str(&request.chain) {
        Ok(c) => c,
        Err(e) => return error_response(HawalaError::invalid_input(e)),
    };

    let amount: u128 = match request.amount.parse() {
        Ok(a) => a,
        Err(_) => return error_response(HawalaError::invalid_input("Invalid amount format")),
    };

    let manager = crate::security::tx_policy::get_policy_manager();
    let result = manager.check_transaction(&request.wallet_id, &request.recipient, amount, chain);

    #[derive(serde::Serialize)]
    struct ViolationInfo {
        violation_type: String,
        message: String,
    }

    #[derive(serde::Serialize)]
    struct PolicyResponse {
        allowed: bool,
        violations: Vec<ViolationInfo>,
        warnings: Vec<String>,
        remaining_daily: Option<String>,
        remaining_weekly: Option<String>,
        requires_approval: bool,
    }

    let violations: Vec<ViolationInfo> = result.violations.iter().map(|v| ViolationInfo {
        violation_type: format!("{:?}", v.violation_type),
        message: v.message.clone(),
    }).collect();

    let response = PolicyResponse {
        allowed: result.allowed,
        violations,
        warnings: result.warnings,
        remaining_daily: result.remaining_daily_limit.map(|v| v.to_string()),
        remaining_weekly: result.remaining_weekly_limit.map(|v| v.to_string()),
        requires_approval: result.requires_approval,
    };

    success_response(response)
}

/// Set spending limits for a wallet
/// 
/// # Input
/// ```json
/// {
///   "wallet_id": "wallet_123",
///   "per_tx_limit": "1000000000000000000",
///   "daily_limit": "10000000000000000000",
///   "weekly_limit": "50000000000000000000",
///   "require_whitelist": false
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_set_spending_limits(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct LimitsRequest {
        wallet_id: String,
        per_tx_limit: Option<String>,
        daily_limit: Option<String>,
        weekly_limit: Option<String>,
        monthly_limit: Option<String>,
        require_whitelist: Option<bool>,
    }

    let request: LimitsRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    let mut policy = crate::security::tx_policy::WalletPolicy::default();

    if let Some(limit) = request.per_tx_limit {
        if let Ok(v) = limit.parse() {
            policy.per_tx_limit = Some(v);
        }
    }
    if let Some(limit) = request.daily_limit {
        if let Ok(v) = limit.parse() {
            policy.daily_limit = Some(v);
        }
    }
    if let Some(limit) = request.weekly_limit {
        if let Ok(v) = limit.parse() {
            policy.weekly_limit = Some(v);
        }
    }
    if let Some(limit) = request.monthly_limit {
        if let Ok(v) = limit.parse() {
            policy.monthly_limit = Some(v);
        }
    }
    if let Some(require) = request.require_whitelist {
        policy.require_whitelist = require;
    }

    policy.enabled = true; // Enable policy when setting limits

    let manager = crate::security::tx_policy::get_policy_manager();
    manager.set_policy(&request.wallet_id, policy);

    success_response(serde_json::json!({"updated": true}))
}

/// Create an authentication challenge
/// 
/// # Input
/// ```json
/// { "address": "0x...", "domain": "hawala.app" }
/// ```
/// 
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "challenge_id": "chal_abc123",
///     "message": "Sign this message to authenticate...",
///     "expires_at": 1705432800
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_create_challenge(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct ChallengeRequest {
        address: String,
        domain: Option<String>,
    }

    let request: ChallengeRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    let manager = crate::security::verification::get_verification_manager();
    
    match manager.create_challenge(&request.address, request.domain.as_deref()) {
        Ok(challenge) => {
            #[derive(serde::Serialize)]
            struct ChallengeResponse {
                challenge_id: String,
                message: String,
                expires_at: u64,
            }

            success_response(ChallengeResponse {
                challenge_id: challenge.id,
                message: challenge.message,
                expires_at: challenge.expires_at,
            })
        }
        Err(e) => error_response(e),
    }
}

/// Verify a signed challenge
/// 
/// # Input
/// ```json
/// {
///   "challenge_id": "chal_abc123",
///   "signature": "0x...",
///   "signer": "0x..."
/// }
/// ```
/// 
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "valid": true,
///     "signer": "0x...",
///     "error": null
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_verify_challenge(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct VerifyRequest {
        challenge_id: String,
        signature: String,
        signer: String,
    }

    let request: VerifyRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    let manager = crate::security::verification::get_verification_manager();
    
    match manager.verify_challenge(&request.challenge_id, &request.signature, &request.signer) {
        Ok(result) => {
            #[derive(serde::Serialize)]
            struct VerifyResponse {
                valid: bool,
                signer: Option<String>,
                error: Option<String>,
            }

            success_response(VerifyResponse {
                valid: result.valid,
                signer: result.signer,
                error: result.error,
            })
        }
        Err(e) => error_response(e),
    }
}

/// Register a key version for rotation tracking
/// 
/// # Input
/// ```json
/// {
///   "wallet_id": "wallet_123",
///   "key_type": "encryption_key",
///   "algorithm": "AES-256-GCM"
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_register_key_version(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct KeyRegisterRequest {
        wallet_id: String,
        key_type: String,
        derivation_path: Option<String>,
        algorithm: String,
    }

    let request: KeyRegisterRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    let key_type = match request.key_type.as_str() {
        "master_seed" => crate::security::key_rotation::KeyType::MasterSeed,
        "chain_key" => crate::security::key_rotation::KeyType::ChainKey,
        "address_key" => crate::security::key_rotation::KeyType::AddressKey,
        "encryption_key" => crate::security::key_rotation::KeyType::EncryptionKey,
        "signing_key" => crate::security::key_rotation::KeyType::SigningKey,
        _ => return error_response(HawalaError::invalid_input("Unknown key type")),
    };

    let manager = crate::security::key_rotation::get_key_rotation_manager();
    
    match manager.register_key_version(
        &request.wallet_id,
        key_type,
        request.derivation_path.as_deref(),
        &request.algorithm,
    ) {
        Ok(version) => {
            #[derive(serde::Serialize)]
            struct KeyVersionResponse {
                version: u32,
                created_at: u64,
                status: String,
            }

            success_response(KeyVersionResponse {
                version: version.version,
                created_at: version.created_at,
                status: format!("{:?}", version.status),
            })
        }
        Err(e) => error_response(e),
    }
}

/// Check if key rotation is needed
/// 
/// # Input
/// ```json
/// { "wallet_id": "wallet_123" }
/// ```
/// 
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "needs_rotation": true,
///     "keys_to_rotate": [
///       { "key_type": "EncryptionKey", "version": 1, "age_days": 400 }
///     ],
///     "warnings": ["Key approaching max age"]
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_check_key_rotation(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct RotationCheckRequest {
        wallet_id: String,
    }

    let request: RotationCheckRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    let manager = crate::security::key_rotation::get_key_rotation_manager();
    let result = manager.check_rotation_needed(&request.wallet_id);

    #[derive(serde::Serialize)]
    struct KeyRotationInfo {
        key_type: String,
        version: u32,
        age_days: u64,
        reason: String,
    }

    #[derive(serde::Serialize)]
    struct RotationCheckResponse {
        needs_rotation: bool,
        keys_to_rotate: Vec<KeyRotationInfo>,
        warnings: Vec<String>,
    }

    let keys: Vec<KeyRotationInfo> = result.keys_to_rotate.into_iter().map(|k| {
        KeyRotationInfo {
            key_type: format!("{:?}", k.key_type),
            version: k.current_version,
            age_days: k.age_days,
            reason: format!("{:?}", k.reason),
        }
    }).collect();

    success_response(RotationCheckResponse {
        needs_rotation: result.needs_rotation,
        keys_to_rotate: keys,
        warnings: result.warnings,
    })
}

/// Securely compare two values (constant-time)
/// 
/// # Input
/// ```json
/// { "a": "value1", "b": "value2" }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_secure_compare(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct CompareRequest {
        a: String,
        b: String,
    }

    let request: CompareRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    let equal = crate::security::secure_memory::secure_compare_str(&request.a, &request.b);

    success_response(serde_json::json!({"equal": equal}))
}

/// Redact sensitive data for safe logging
/// 
/// # Input
/// ```json
/// { "data": "0x1234567890abcdef..." }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_redact(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    struct RedactRequest {
        data: String,
    }

    let request: RedactRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid JSON: {}", e))),
    };

    let redacted = crate::security::secure_memory::redact(&request.data);

    success_response(serde_json::json!({"redacted": redacted}))
}
