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
        // EVM-compatible chains
        chain if chain.is_evm() => {
            crate::tx::prepare_evm_transaction(&request)
        }
        // Default fallback
        _ => {
            error_response(HawalaError::new(ErrorCode::NotImplemented, format!("Transactions not yet supported for {:?}", request.chain)))
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

// =============================================================================
// EIP-712 Typed Data Signing
// =============================================================================

/// Hash EIP-712 typed data
/// 
/// # Input
/// ```json
/// {
///   "types": { ... },
///   "primaryType": "Mail",
///   "domain": { ... },
///   "message": { ... }
/// }
/// ```
/// 
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "hash": "0x...",
///     "domainSeparator": "0x...",
///     "structHash": "0x..."
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_eip712_hash(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    let typed_data: crate::eip712::TypedData = match serde_json::from_str(json_str) {
        Ok(t) => t,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid typed data: {}", e))),
    };

    // Validate the typed data
    if let Err(e) = typed_data.validate() {
        return error_response(HawalaError::invalid_input(format!("Validation failed: {}", e)));
    }

    // Get the pre-image components
    let pre_image = match crate::eip712::get_pre_image(&typed_data) {
        Ok(p) => p,
        Err(e) => return error_response(HawalaError::crypto_error(format!("Hash failed: {}", e))),
    };

    success_response(serde_json::json!({
        "hash": format!("0x{}", hex::encode(pre_image.final_hash)),
        "domainSeparator": format!("0x{}", hex::encode(pre_image.domain_separator)),
        "structHash": format!("0x{}", hex::encode(pre_image.struct_hash))
    }))
}

/// Sign EIP-712 typed data
/// 
/// # Input
/// ```json
/// {
///   "typedData": { ... },
///   "privateKey": "0x..."
/// }
/// ```
/// 
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "signature": "0x...",
///     "r": "0x...",
///     "s": "0x...",
///     "v": 27
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_eip712_sign(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct SignRequest {
        typed_data: crate::eip712::TypedData,
        private_key: String,
    }

    let request: SignRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid request: {}", e))),
    };

    // Parse the private key
    let key_hex = request.private_key.strip_prefix("0x").unwrap_or(&request.private_key);
    let private_key = match hex::decode(key_hex) {
        Ok(k) => k,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid private key: {}", e))),
    };

    // Sign the typed data
    let signature = match crate::eip712::sign_typed_data(&request.typed_data, &private_key) {
        Ok(s) => s,
        Err(e) => return error_response(HawalaError::crypto_error(format!("Signing failed: {}", e))),
    };

    success_response(serde_json::json!({
        "signature": signature.to_hex(),
        "r": format!("0x{}", hex::encode(signature.r)),
        "s": format!("0x{}", hex::encode(signature.s)),
        "v": signature.v
    }))
}

/// Verify an EIP-712 signature
/// 
/// # Input
/// ```json
/// {
///   "typedData": { ... },
///   "signature": "0x...",
///   "address": "0x..."
/// }
/// ```
/// 
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "valid": true,
///     "recoveredAddress": "0x..."
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_eip712_verify(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct VerifyRequest {
        typed_data: crate::eip712::TypedData,
        signature: String,
        address: String,
    }

    let request: VerifyRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid request: {}", e))),
    };

    // Parse the signature
    let sig_hex = request.signature.strip_prefix("0x").unwrap_or(&request.signature);
    let sig_bytes = match hex::decode(sig_hex) {
        Ok(b) => b,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid signature: {}", e))),
    };

    let signature = match crate::eip712::Eip712Signature::from_bytes(&sig_bytes) {
        Ok(s) => s,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid signature format: {}", e))),
    };

    // Calculate the hash
    let hash = match crate::eip712::hash_typed_data(&request.typed_data) {
        Ok(h) => h,
        Err(e) => return error_response(HawalaError::crypto_error(format!("Hash failed: {}", e))),
    };

    // Recover the address
    let recovered = match crate::eip712::recover_address(&hash, &signature) {
        Ok(a) => a,
        Err(e) => return error_response(HawalaError::crypto_error(format!("Recovery failed: {}", e))),
    };

    // Verify the address matches
    let valid = match crate::eip712::verify_signature(&hash, &signature, &request.address) {
        Ok(v) => v,
        Err(e) => return error_response(HawalaError::crypto_error(format!("Verification failed: {}", e))),
    };

    success_response(serde_json::json!({
        "valid": valid,
        "recoveredAddress": recovered
    }))
}

/// Recover address from EIP-712 signature
/// 
/// # Input
/// ```json
/// {
///   "typedData": { ... },
///   "signature": "0x..."
/// }
/// ```
/// 
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "address": "0x..."
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_eip712_recover(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct RecoverRequest {
        typed_data: crate::eip712::TypedData,
        signature: String,
    }

    let request: RecoverRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid request: {}", e))),
    };

    // Parse the signature
    let sig_hex = request.signature.strip_prefix("0x").unwrap_or(&request.signature);
    let sig_bytes = match hex::decode(sig_hex) {
        Ok(b) => b,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid signature: {}", e))),
    };

    let signature = match crate::eip712::Eip712Signature::from_bytes(&sig_bytes) {
        Ok(s) => s,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid signature format: {}", e))),
    };

    // Calculate the hash
    let hash = match crate::eip712::hash_typed_data(&request.typed_data) {
        Ok(h) => h,
        Err(e) => return error_response(HawalaError::crypto_error(format!("Hash failed: {}", e))),
    };

    // Recover the address
    let address = match crate::eip712::recover_address(&hash, &signature) {
        Ok(a) => a,
        Err(e) => return error_response(HawalaError::crypto_error(format!("Recovery failed: {}", e))),
    };

    success_response(serde_json::json!({
        "address": address
    }))
}

// =============================================================================
// Message Signing (Personal Sign / EIP-191)
// =============================================================================

/// Sign a message using Ethereum personal_sign
/// 
/// # Input
/// ```json
/// {
///   "message": "Hello, World!",
///   "privateKey": "0x...",
///   "encoding": "utf8"  // or "hex"
/// }
/// ```
/// 
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "signature": "0x...",
///     "r": "0x...",
///     "s": "0x...",
///     "v": 27
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_personal_sign(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct SignRequest {
        message: String,
        private_key: String,
        #[serde(default)]
        encoding: Option<String>,
    }

    let request: SignRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid request: {}", e))),
    };

    // Parse the private key
    let key_hex = request.private_key.strip_prefix("0x").unwrap_or(&request.private_key);
    let private_key = match hex::decode(key_hex) {
        Ok(k) => k,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid private key: {}", e))),
    };

    // Parse the message based on encoding
    let message_bytes = match request.encoding.as_deref() {
        Some("hex") => {
            let msg_hex = request.message.strip_prefix("0x").unwrap_or(&request.message);
            match hex::decode(msg_hex) {
                Ok(m) => m,
                Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid hex message: {}", e))),
            }
        }
        _ => request.message.into_bytes(),
    };

    // Sign the message
    let sig = match crate::message_signer::ethereum::personal_sign(&message_bytes, &private_key) {
        Ok(s) => s,
        Err(e) => return error_response(HawalaError::crypto_error(format!("Signing failed: {}", e))),
    };

    success_response(serde_json::json!({
        "signature": sig.signature,
        "r": sig.r,
        "s": sig.s,
        "v": sig.v
    }))
}

/// Verify an Ethereum personal_sign signature
/// 
/// # Input
/// ```json
/// {
///   "message": "Hello, World!",
///   "signature": "0x...",
///   "address": "0x...",
///   "encoding": "utf8"
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_personal_verify(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct VerifyRequest {
        message: String,
        signature: String,
        address: String,
        #[serde(default)]
        encoding: Option<String>,
    }

    let request: VerifyRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid request: {}", e))),
    };

    // Parse the signature
    let sig_hex = request.signature.strip_prefix("0x").unwrap_or(&request.signature);
    let sig_bytes = match hex::decode(sig_hex) {
        Ok(s) => s,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid signature: {}", e))),
    };

    // Parse the message
    let message_bytes = match request.encoding.as_deref() {
        Some("hex") => {
            let msg_hex = request.message.strip_prefix("0x").unwrap_or(&request.message);
            match hex::decode(msg_hex) {
                Ok(m) => m,
                Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid hex message: {}", e))),
            }
        }
        _ => request.message.into_bytes(),
    };

    // Verify the signature
    let valid = match crate::message_signer::ethereum::verify_personal_sign(&message_bytes, &sig_bytes, &request.address) {
        Ok(v) => v,
        Err(e) => return error_response(HawalaError::crypto_error(format!("Verification failed: {}", e))),
    };

    success_response(serde_json::json!({
        "valid": valid,
        "address": request.address
    }))
}

/// Recover the signer's address from a personal_sign signature
/// 
/// # Input
/// ```json
/// {
///   "message": "Hello, World!",
///   "signature": "0x...",
///   "encoding": "utf8"
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_personal_recover(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct RecoverRequest {
        message: String,
        signature: String,
        #[serde(default)]
        encoding: Option<String>,
    }

    let request: RecoverRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid request: {}", e))),
    };

    // Parse the signature
    let sig_hex = request.signature.strip_prefix("0x").unwrap_or(&request.signature);
    let sig_bytes = match hex::decode(sig_hex) {
        Ok(s) => s,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid signature: {}", e))),
    };

    // Parse the message
    let message_bytes = match request.encoding.as_deref() {
        Some("hex") => {
            let msg_hex = request.message.strip_prefix("0x").unwrap_or(&request.message);
            match hex::decode(msg_hex) {
                Ok(m) => m,
                Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid hex message: {}", e))),
            }
        }
        _ => request.message.into_bytes(),
    };

    // Recover the address
    let address = match crate::message_signer::ethereum::recover_address(&message_bytes, &sig_bytes) {
        Ok(a) => a,
        Err(e) => return error_response(HawalaError::crypto_error(format!("Recovery failed: {}", e))),
    };

    success_response(serde_json::json!({
        "address": address
    }))
}

/// Sign a message for Solana (Ed25519)
/// 
/// # Input
/// ```json
/// {
///   "message": "Hello, Solana!",
///   "privateKey": "0x...",
///   "encoding": "utf8"
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_solana_sign_message(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct SignRequest {
        message: String,
        private_key: String,
        #[serde(default)]
        encoding: Option<String>,
    }

    let request: SignRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid request: {}", e))),
    };

    // Parse the private key
    let key_hex = request.private_key.strip_prefix("0x").unwrap_or(&request.private_key);
    let private_key = match hex::decode(key_hex) {
        Ok(k) => k,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid private key: {}", e))),
    };

    // Parse the message
    let message_bytes = match request.encoding.as_deref() {
        Some("hex") => {
            let msg_hex = request.message.strip_prefix("0x").unwrap_or(&request.message);
            match hex::decode(msg_hex) {
                Ok(m) => m,
                Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid hex message: {}", e))),
            }
        }
        _ => request.message.into_bytes(),
    };

    // Sign the message
    let sig = match crate::message_signer::solana::sign_message(&message_bytes, &private_key) {
        Ok(s) => s,
        Err(e) => return error_response(HawalaError::crypto_error(format!("Signing failed: {}", e))),
    };

    // Get the public key for verification
    let public_key = match crate::message_signer::solana::get_public_key(&private_key) {
        Ok(p) => crate::message_signer::solana::encode_public_key_base58(&p),
        Err(e) => return error_response(HawalaError::crypto_error(format!("Failed to get public key: {}", e))),
    };

    success_response(serde_json::json!({
        "signature": sig.signature,
        "publicKey": public_key
    }))
}

/// Verify a Solana message signature
/// 
/// # Input
/// ```json
/// {
///   "message": "Hello, Solana!",
///   "signature": "0x...",
///   "publicKey": "base58address",
///   "encoding": "utf8"
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_solana_verify_message(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct VerifyRequest {
        message: String,
        signature: String,
        public_key: String,
        #[serde(default)]
        encoding: Option<String>,
    }

    let request: VerifyRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid request: {}", e))),
    };

    // Parse the signature
    let sig_hex = request.signature.strip_prefix("0x").unwrap_or(&request.signature);
    let sig_bytes = match hex::decode(sig_hex) {
        Ok(s) => s,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid signature: {}", e))),
    };

    // Parse the public key (base58)
    let public_key = match crate::message_signer::solana::decode_public_key_base58(&request.public_key) {
        Ok(p) => p,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid public key: {}", e))),
    };

    // Parse the message
    let message_bytes = match request.encoding.as_deref() {
        Some("hex") => {
            let msg_hex = request.message.strip_prefix("0x").unwrap_or(&request.message);
            match hex::decode(msg_hex) {
                Ok(m) => m,
                Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid hex message: {}", e))),
            }
        }
        _ => request.message.into_bytes(),
    };

    // Verify the signature
    let valid = match crate::message_signer::solana::verify_message(&message_bytes, &sig_bytes, &public_key) {
        Ok(v) => v,
        Err(e) => return error_response(HawalaError::crypto_error(format!("Verification failed: {}", e))),
    };

    success_response(serde_json::json!({
        "valid": valid,
        "publicKey": request.public_key
    }))
}

/// Sign a Cosmos ADR-036 arbitrary message
/// 
/// # Input
/// ```json
/// {
///   "message": "Hello, Cosmos!",
///   "signer": "cosmos1...",
///   "privateKey": "0x...",
///   "chainId": "cosmoshub-4"
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_cosmos_sign_arbitrary(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct SignRequest {
        message: String,
        signer: String,
        private_key: String,
        #[serde(default)]
        chain_id: Option<String>,
    }

    let request: SignRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid request: {}", e))),
    };

    // Parse the private key
    let key_hex = request.private_key.strip_prefix("0x").unwrap_or(&request.private_key);
    let private_key = match hex::decode(key_hex) {
        Ok(k) => k,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid private key: {}", e))),
    };

    let message_bytes = request.message.as_bytes();

    // Sign with or without chain ID
    let sig = match &request.chain_id {
        Some(chain_id) => {
            match crate::message_signer::cosmos::sign_keplr_arbitrary(chain_id, &request.signer, message_bytes, &private_key) {
                Ok(s) => s,
                Err(e) => return error_response(HawalaError::crypto_error(format!("Signing failed: {}", e))),
            }
        }
        None => {
            match crate::message_signer::cosmos::sign_arbitrary(message_bytes, &request.signer, &private_key) {
                Ok(s) => s,
                Err(e) => return error_response(HawalaError::crypto_error(format!("Signing failed: {}", e))),
            }
        }
    };

    // Get the public key
    let public_key = match crate::message_signer::cosmos::get_public_key(&private_key) {
        Ok(p) => format!("0x{}", hex::encode(&p)),
        Err(e) => return error_response(HawalaError::crypto_error(format!("Failed to get public key: {}", e))),
    };

    success_response(serde_json::json!({
        "signature": sig.signature,
        "publicKey": public_key,
        "r": sig.r,
        "s": sig.s
    }))
}

/// Sign a Tezos message
/// 
/// # Input
/// ```json
/// {
///   "message": "Hello, Tezos!",
///   "dappUrl": "https://example.com",
///   "privateKey": "0x..."
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_tezos_sign_message(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(ptr) => return ptr,
    };

    #[derive(serde::Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct SignRequest {
        message: String,
        dapp_url: String,
        private_key: String,
    }

    let request: SignRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::parse_error(format!("Invalid request: {}", e))),
    };

    // Parse the private key
    let key_hex = request.private_key.strip_prefix("0x").unwrap_or(&request.private_key);
    let private_key = match hex::decode(key_hex) {
        Ok(k) => k,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid private key: {}", e))),
    };

    // Sign the message
    let sig = match crate::message_signer::tezos::sign_message(&request.message, &request.dapp_url, &private_key) {
        Ok(s) => s,
        Err(e) => return error_response(HawalaError::crypto_error(format!("Signing failed: {}", e))),
    };

    // Encode signature in base58
    let sig_bytes = match hex::decode(sig.signature.trim_start_matches("0x")) {
        Ok(b) => b,
        Err(e) => return error_response(HawalaError::crypto_error(format!("Signature encoding failed: {}", e))),
    };

    let sig_base58 = if sig_bytes.len() == 64 {
        match crate::message_signer::tezos::encode_signature_base58(&sig_bytes) {
            Ok(s) => s,
            Err(e) => return error_response(HawalaError::crypto_error(format!("Base58 encoding failed: {}", e))),
        }
    } else {
        sig.signature.clone()
    };

    success_response(serde_json::json!({
        "signature": sig.signature,
        "signatureBase58": sig_base58
    }))
}

// =============================================================================
// EIP-7702 Account Delegation
// =============================================================================

/// Sign an EIP-7702 authorization
/// 
/// Allows an EOA to authorize delegation to a contract address.
/// 
/// # Input
/// ```json
/// {
///   "chainId": 1,
///   "address": "0x...",  // Contract to delegate to (20 bytes hex)
///   "nonce": 0,
///   "privateKey": "0x..." // 32 bytes hex
/// }
/// ```
/// 
/// # Output
/// ```json
/// {
///   "success": true,
///   "chainId": 1,
///   "address": "0x...",
///   "nonce": 0,
///   "yParity": 0,
///   "r": "0x...",
///   "s": "0x..."
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_eip7702_sign_authorization(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        #[serde(rename = "chainId")]
        chain_id: u64,
        address: String,
        nonce: u64,
        #[serde(rename = "privateKey")]
        private_key: String,
    }

    let request: Request = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid JSON: {}", e))),
    };

    // Parse address
    let addr_hex = request.address.trim_start_matches("0x");
    let addr_bytes = match hex::decode(addr_hex) {
        Ok(b) if b.len() == 20 => {
            let mut arr = [0u8; 20];
            arr.copy_from_slice(&b);
            arr
        }
        Ok(_) => return error_response(HawalaError::invalid_input("Address must be 20 bytes")),
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid address hex: {}", e))),
    };

    // Parse private key
    let key_hex = request.private_key.trim_start_matches("0x");
    let key_bytes: [u8; 32] = match hex::decode(key_hex) {
        Ok(k) if k.len() == 32 => {
            let mut arr = [0u8; 32];
            arr.copy_from_slice(&k);
            arr
        }
        Ok(_) => return error_response(HawalaError::invalid_input("Private key must be 32 bytes")),
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid private key: {}", e))),
    };

    // Sign authorization
    let signed = match crate::eip7702::authorization::sign_authorization(
        request.chain_id,
        addr_bytes,
        request.nonce,
        &key_bytes,
    ) {
        Ok(s) => s,
        Err(e) => return error_response(HawalaError::crypto_error(format!("Authorization signing failed: {}", e))),
    };

    success_response(serde_json::json!({
        "chainId": signed.chain_id,
        "address": format!("0x{}", hex::encode(signed.address)),
        "nonce": signed.nonce,
        "yParity": signed.y_parity,
        "r": format!("0x{}", hex::encode(signed.r)),
        "s": format!("0x{}", hex::encode(signed.s))
    }))
}

/// Sign an EIP-7702 transaction
/// 
/// Creates and signs a complete EIP-7702 transaction (type 0x04).
/// 
/// # Input
/// ```json
/// {
///   "chainId": 1,
///   "nonce": 0,
///   "maxPriorityFeePerGas": "1000000000",
///   "maxFeePerGas": "50000000000",
///   "gasLimit": 100000,
///   "to": "0x...",           // Optional, 20 bytes hex
///   "value": "0",            // Wei as string
///   "data": "0x...",         // Optional hex data
///   "authorizationList": [   // Array of signed authorizations
///     {
///       "chainId": 1,
///       "address": "0x...",
///       "nonce": 0,
///       "yParity": 0,
///       "r": "0x...",
///       "s": "0x..."
///     }
///   ],
///   "privateKey": "0x..."    // Transaction signer key
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_eip7702_sign_transaction(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct AuthItem {
        #[serde(rename = "chainId")]
        chain_id: u64,
        address: String,
        nonce: u64,
        #[serde(rename = "yParity")]
        y_parity: u8,
        r: String,
        s: String,
    }

    #[derive(serde::Deserialize)]
    struct Request {
        #[serde(rename = "chainId")]
        chain_id: u64,
        nonce: u64,
        #[serde(rename = "maxPriorityFeePerGas")]
        max_priority_fee_per_gas: String,
        #[serde(rename = "maxFeePerGas")]
        max_fee_per_gas: String,
        #[serde(rename = "gasLimit")]
        gas_limit: u64,
        to: Option<String>,
        value: Option<String>,
        data: Option<String>,
        #[serde(rename = "authorizationList")]
        authorization_list: Vec<AuthItem>,
        #[serde(rename = "privateKey")]
        private_key: String,
    }

    let request: Request = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid JSON: {}", e))),
    };

    // Build transaction
    let mut tx = crate::eip7702::Eip7702Transaction::new(request.chain_id);
    tx.nonce = request.nonce;
    tx.max_priority_fee_per_gas = request.max_priority_fee_per_gas.parse().unwrap_or(0);
    tx.max_fee_per_gas = request.max_fee_per_gas.parse().unwrap_or(0);
    tx.gas_limit = request.gas_limit;

    if let Some(to_str) = &request.to {
        let to_hex = to_str.trim_start_matches("0x");
        if let Ok(to_bytes) = hex::decode(to_hex) {
            if to_bytes.len() == 20 {
                let mut arr = [0u8; 20];
                arr.copy_from_slice(&to_bytes);
                tx.to = Some(arr);
            }
        }
    }

    if let Some(value_str) = &request.value {
        tx.value = value_str.parse().unwrap_or(0);
    }

    if let Some(data_str) = &request.data {
        let data_hex = data_str.trim_start_matches("0x");
        if let Ok(data_bytes) = hex::decode(data_hex) {
            tx.data = data_bytes;
        }
    }

    // Parse authorization list
    for auth_item in &request.authorization_list {
        let addr_hex = auth_item.address.trim_start_matches("0x");
        let addr_bytes = match hex::decode(addr_hex) {
            Ok(b) if b.len() == 20 => {
                let mut arr = [0u8; 20];
                arr.copy_from_slice(&b);
                arr
            }
            _ => continue,
        };

        let r_hex = auth_item.r.trim_start_matches("0x");
        let r_bytes = match hex::decode(r_hex) {
            Ok(b) if b.len() == 32 => {
                let mut arr = [0u8; 32];
                arr.copy_from_slice(&b);
                arr
            }
            _ => continue,
        };

        let s_hex = auth_item.s.trim_start_matches("0x");
        let s_bytes = match hex::decode(s_hex) {
            Ok(b) if b.len() == 32 => {
                let mut arr = [0u8; 32];
                arr.copy_from_slice(&b);
                arr
            }
            _ => continue,
        };

        let auth = crate::eip7702::Authorization::with_signature(
            auth_item.chain_id,
            addr_bytes,
            auth_item.nonce,
            auth_item.y_parity,
            r_bytes,
            s_bytes,
        );
        tx.authorization_list.push(auth);
    }

    // Parse private key
    let key_hex = request.private_key.trim_start_matches("0x");
    let key_bytes: [u8; 32] = match hex::decode(key_hex) {
        Ok(k) if k.len() == 32 => {
            let mut arr = [0u8; 32];
            arr.copy_from_slice(&k);
            arr
        }
        Ok(_) => return error_response(HawalaError::invalid_input("Private key must be 32 bytes")),
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid private key: {}", e))),
    };

    // Sign transaction
    let signed = match crate::eip7702::signer::sign_eip7702_transaction(&tx, &key_bytes) {
        Ok(s) => s,
        Err(e) => return error_response(HawalaError::crypto_error(format!("Transaction signing failed: {}", e))),
    };

    // Serialize for broadcast
    let serialized = crate::eip7702::signer::serialize_for_broadcast(&signed);
    let tx_hash = crate::eip7702::signer::get_transaction_hash(&signed);

    success_response(serde_json::json!({
        "rawTransaction": format!("0x{}", hex::encode(&serialized)),
        "transactionHash": format!("0x{}", hex::encode(&tx_hash)),
        "yParity": signed.y_parity,
        "r": format!("0x{}", hex::encode(signed.r)),
        "s": format!("0x{}", hex::encode(signed.s))
    }))
}

/// Recover the signer of an EIP-7702 authorization
/// 
/// # Input
/// ```json
/// {
///   "chainId": 1,
///   "address": "0x...",
///   "nonce": 0,
///   "yParity": 0,
///   "r": "0x...",
///   "s": "0x..."
/// }
/// ```
/// 
/// # Output
/// ```json
/// {
///   "success": true,
///   "signer": "0x..."
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_eip7702_recover_authorization_signer(input: *const c_char) -> *mut c_char {
    let json_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        #[serde(rename = "chainId")]
        chain_id: u64,
        address: String,
        nonce: u64,
        #[serde(rename = "yParity")]
        y_parity: u8,
        r: String,
        s: String,
    }

    let request: Request = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid JSON: {}", e))),
    };

    // Parse address
    let addr_hex = request.address.trim_start_matches("0x");
    let addr_bytes = match hex::decode(addr_hex) {
        Ok(b) if b.len() == 20 => {
            let mut arr = [0u8; 20];
            arr.copy_from_slice(&b);
            arr
        }
        Ok(_) => return error_response(HawalaError::invalid_input("Address must be 20 bytes")),
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid address: {}", e))),
    };

    // Parse r
    let r_hex = request.r.trim_start_matches("0x");
    let r_bytes = match hex::decode(r_hex) {
        Ok(b) if b.len() == 32 => {
            let mut arr = [0u8; 32];
            arr.copy_from_slice(&b);
            arr
        }
        Ok(_) => return error_response(HawalaError::invalid_input("R must be 32 bytes")),
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid r: {}", e))),
    };

    // Parse s
    let s_hex = request.s.trim_start_matches("0x");
    let s_bytes = match hex::decode(s_hex) {
        Ok(b) if b.len() == 32 => {
            let mut arr = [0u8; 32];
            arr.copy_from_slice(&b);
            arr
        }
        Ok(_) => return error_response(HawalaError::invalid_input("S must be 32 bytes")),
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid s: {}", e))),
    };

    let auth = crate::eip7702::Authorization::with_signature(
        request.chain_id,
        addr_bytes,
        request.nonce,
        request.y_parity,
        r_bytes,
        s_bytes,
    );

    let signer = match crate::eip7702::authorization::recover_authorization_signer(&auth) {
        Ok(s) => s,
        Err(e) => return error_response(HawalaError::crypto_error(format!("Recovery failed: {}", e))),
    };

    success_response(serde_json::json!({
        "signer": format!("0x{}", hex::encode(signer))
    }))
}

// =============================================================================
// External Signature Compilation (Section 4)
// =============================================================================

/// Generate pre-image hashes for Bitcoin transaction signing
/// 
/// # Input
/// ```json
/// {
///   "transaction": {
///     "version": 2,
///     "inputs": [...],
///     "outputs": [...],
///     "locktime": 0
///   },
///   "sighash_type": "All"
/// }
/// ```
/// 
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "hashes": [
///       {
///         "hash": "0x...",
///         "signer_id": "m/44'/0'/0'/0/0",
///         "input_index": 0,
///         "algorithm": "Secp256k1Ecdsa"
///       }
///     ]
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_get_bitcoin_sighashes(input: *const c_char) -> *mut c_char {
    let input_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        transaction: crate::signing::preimage::bitcoin::UnsignedBitcoinTransaction,
        sighash_type: Option<String>,
    }

    let request: Request = match serde_json::from_str(input_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("JSON parse error: {}", e))),
    };

    let sighash_type = match request.sighash_type.as_deref() {
        Some("All") | None => crate::signing::preimage::bitcoin::BitcoinSigHashType::All,
        Some("None") => crate::signing::preimage::bitcoin::BitcoinSigHashType::None,
        Some("Single") => crate::signing::preimage::bitcoin::BitcoinSigHashType::Single,
        Some("AllAnyoneCanPay") => crate::signing::preimage::bitcoin::BitcoinSigHashType::AllAnyoneCanPay,
        Some("NoneAnyoneCanPay") => crate::signing::preimage::bitcoin::BitcoinSigHashType::NoneAnyoneCanPay,
        Some("SingleAnyoneCanPay") => crate::signing::preimage::bitcoin::BitcoinSigHashType::SingleAnyoneCanPay,
        Some("TaprootDefault") => crate::signing::preimage::bitcoin::BitcoinSigHashType::TaprootDefault,
        Some(other) => return error_response(HawalaError::invalid_input(format!("Unknown sighash type: {}", other))),
    };

    match crate::signing::preimage::get_bitcoin_sighashes(&request.transaction, sighash_type) {
        Ok(hashes) => {
            let result: Vec<_> = hashes.iter().map(|h| serde_json::json!({
                "hash": h.hash_hex(),
                "signer_id": h.signer_id,
                "input_index": h.input_index,
                "description": h.description,
                "algorithm": format!("{:?}", h.algorithm)
            })).collect();
            success_response(serde_json::json!({ "hashes": result }))
        }
        Err(e) => error_response(HawalaError::crypto_error(format!("Sighash error: {}", e))),
    }
}

/// Generate signing hash for Ethereum transaction
/// 
/// # Input
/// ```json
/// {
///   "transaction": {
///     "tx_type": "FeeMarket",
///     "chain_id": 1,
///     "nonce": 0,
///     ...
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_get_ethereum_signing_hash(input: *const c_char) -> *mut c_char {
    let input_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        transaction: crate::signing::preimage::ethereum::UnsignedEthereumTransaction,
    }

    let request: Request = match serde_json::from_str(input_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("JSON parse error: {}", e))),
    };

    match crate::signing::preimage::get_ethereum_signing_hash(&request.transaction) {
        Ok(hash) => success_response(serde_json::json!({
            "hash": hash.hash_hex(),
            "signer_id": hash.signer_id,
            "description": hash.description,
            "algorithm": format!("{:?}", hash.algorithm)
        })),
        Err(e) => error_response(HawalaError::crypto_error(format!("Hash error: {}", e))),
    }
}

/// Generate signing hash for Cosmos transaction
#[unsafe(no_mangle)]
pub extern "C" fn hawala_get_cosmos_sign_doc_hash(input: *const c_char) -> *mut c_char {
    let input_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        transaction: crate::signing::preimage::cosmos::UnsignedCosmosTransaction,
    }

    let request: Request = match serde_json::from_str(input_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("JSON parse error: {}", e))),
    };

    match crate::signing::preimage::get_cosmos_sign_doc_hash(&request.transaction) {
        Ok(hash) => success_response(serde_json::json!({
            "hash": hash.hash_hex(),
            "signer_id": hash.signer_id,
            "description": hash.description,
            "algorithm": format!("{:?}", hash.algorithm)
        })),
        Err(e) => error_response(HawalaError::crypto_error(format!("Hash error: {}", e))),
    }
}

/// Generate signing hashes for Solana transaction
#[unsafe(no_mangle)]
pub extern "C" fn hawala_get_solana_message_hash(input: *const c_char) -> *mut c_char {
    let input_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        transaction: crate::signing::preimage::solana::UnsignedSolanaTransaction,
    }

    let request: Request = match serde_json::from_str(input_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("JSON parse error: {}", e))),
    };

    match crate::signing::preimage::get_solana_message_hash(&request.transaction) {
        Ok(hashes) => {
            let result: Vec<_> = hashes.iter().map(|h| serde_json::json!({
                "hash": h.hash_hex(),
                "signer_id": h.signer_id,
                "input_index": h.input_index,
                "description": h.description,
                "algorithm": format!("{:?}", h.algorithm)
            })).collect();
            success_response(serde_json::json!({ "hashes": result }))
        }
        Err(e) => error_response(HawalaError::crypto_error(format!("Hash error: {}", e))),
    }
}

/// Compile a Bitcoin transaction with external signatures
#[unsafe(no_mangle)]
pub extern "C" fn hawala_compile_bitcoin_transaction(input: *const c_char) -> *mut c_char {
    let input_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        transaction: crate::signing::preimage::bitcoin::UnsignedBitcoinTransaction,
        signatures: Vec<crate::signing::preimage::ExternalSignature>,
    }

    let request: Request = match serde_json::from_str(input_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("JSON parse error: {}", e))),
    };

    match crate::signing::compile_bitcoin_transaction(&request.transaction, &request.signatures) {
        Ok(compiled) => success_response(serde_json::json!({
            "raw_tx": format!("0x{}", hex::encode(&compiled.raw_tx)),
            "txid": format!("0x{}", hex::encode(compiled.txid)),
            "wtxid": compiled.wtxid.map(|w| format!("0x{}", hex::encode(w))),
            "vsize": compiled.vsize
        })),
        Err(e) => error_response(HawalaError::crypto_error(format!("Compile error: {}", e))),
    }
}

/// Compile an Ethereum transaction with external signature
#[unsafe(no_mangle)]
pub extern "C" fn hawala_compile_ethereum_transaction(input: *const c_char) -> *mut c_char {
    let input_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        transaction: crate::signing::preimage::ethereum::UnsignedEthereumTransaction,
        signature: crate::signing::preimage::ExternalSignature,
    }

    let request: Request = match serde_json::from_str(input_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("JSON parse error: {}", e))),
    };

    match crate::signing::compile_ethereum_transaction(&request.transaction, &request.signature) {
        Ok(compiled) => success_response(serde_json::json!({
            "raw_tx": format!("0x{}", hex::encode(&compiled.raw_tx)),
            "tx_hash": format!("0x{}", hex::encode(compiled.tx_hash)),
            "from": format!("0x{}", hex::encode(compiled.from))
        })),
        Err(e) => error_response(HawalaError::crypto_error(format!("Compile error: {}", e))),
    }
}

/// Compile a Cosmos transaction with external signature
#[unsafe(no_mangle)]
pub extern "C" fn hawala_compile_cosmos_transaction(input: *const c_char) -> *mut c_char {
    let input_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        transaction: crate::signing::preimage::cosmos::UnsignedCosmosTransaction,
        signature: crate::signing::preimage::ExternalSignature,
    }

    let request: Request = match serde_json::from_str(input_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("JSON parse error: {}", e))),
    };

    match crate::signing::compile_cosmos_transaction(&request.transaction, &request.signature) {
        Ok(compiled) => success_response(serde_json::json!({
            "raw_tx": format!("0x{}", hex::encode(&compiled.raw_tx)),
            "tx_hash": format!("0x{}", hex::encode(compiled.tx_hash))
        })),
        Err(e) => error_response(HawalaError::crypto_error(format!("Compile error: {}", e))),
    }
}

/// Compile a Solana transaction with external signatures
#[unsafe(no_mangle)]
pub extern "C" fn hawala_compile_solana_transaction(input: *const c_char) -> *mut c_char {
    let input_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        transaction: crate::signing::preimage::solana::UnsignedSolanaTransaction,
        signatures: Vec<crate::signing::preimage::ExternalSignature>,
    }

    let request: Request = match serde_json::from_str(input_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("JSON parse error: {}", e))),
    };

    match crate::signing::compile_solana_transaction(&request.transaction, &request.signatures) {
        Ok(compiled) => success_response(serde_json::json!({
            "raw_tx": format!("0x{}", hex::encode(&compiled.raw_tx)),
            "signature": bs58::encode(&compiled.signature).into_string()
        })),
        Err(e) => error_response(HawalaError::crypto_error(format!("Compile error: {}", e))),
    }
}

// =============================================================================
// BIP-340 Schnorr Signatures (Section 6: Bitcoin Taproot)
// =============================================================================

/// Sign a message using BIP-340 Schnorr signature scheme
/// 
/// # Input
/// ```json
/// {
///   "message": "0x...",  // 32-byte message hash (hex)
///   "private_key": "0x...",  // 32-byte private key (hex)
///   "aux_rand": "0x..."  // optional 32-byte auxiliary randomness (hex)
/// }
/// ```
/// 
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "signature": "0x...",  // 64-byte Schnorr signature (hex)
///     "public_key": "0x..."  // 32-byte x-only public key (hex)
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_schnorr_sign(input: *const c_char) -> *mut c_char {
    let input_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        message: String,
        private_key: String,
        aux_rand: Option<String>,
    }

    let request: Request = match serde_json::from_str(input_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("JSON parse error: {}", e))),
    };

    // Parse message (32 bytes)
    let message_str = request.message.strip_prefix("0x").unwrap_or(&request.message);
    let message_bytes = match hex::decode(message_str) {
        Ok(b) if b.len() == 32 => {
            let mut arr = [0u8; 32];
            arr.copy_from_slice(&b);
            arr
        },
        Ok(b) => return error_response(HawalaError::invalid_input(format!("Message must be 32 bytes, got {}", b.len()))),
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid message hex: {}", e))),
    };

    // Parse private key (32 bytes)
    let key_str = request.private_key.strip_prefix("0x").unwrap_or(&request.private_key);
    let private_key = match hex::decode(key_str) {
        Ok(b) if b.len() == 32 => b,
        Ok(b) => return error_response(HawalaError::invalid_input(format!("Private key must be 32 bytes, got {}", b.len()))),
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid private key hex: {}", e))),
    };

    let signer = crate::crypto::schnorr::SchnorrSigner::new();

    // Sign with or without auxiliary randomness
    let signature = if let Some(aux) = request.aux_rand {
        let aux_str = aux.strip_prefix("0x").unwrap_or(&aux);
        let aux_bytes = match hex::decode(aux_str) {
            Ok(b) if b.len() == 32 => {
                let mut arr = [0u8; 32];
                arr.copy_from_slice(&b);
                arr
            },
            Ok(b) => return error_response(HawalaError::invalid_input(format!("Aux random must be 32 bytes, got {}", b.len()))),
            Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid aux random hex: {}", e))),
        };
        match signer.sign_with_aux_rand(&message_bytes, &private_key, &aux_bytes) {
            Ok(sig) => sig,
            Err(e) => return error_response(HawalaError::crypto_error(format!("Schnorr signing failed: {}", e))),
        }
    } else {
        match signer.sign(&message_bytes, &private_key) {
            Ok(sig) => sig,
            Err(e) => return error_response(HawalaError::crypto_error(format!("Schnorr signing failed: {}", e))),
        }
    };

    // Get public key
    let public_key = match signer.public_key(&private_key) {
        Ok(pk) => pk,
        Err(e) => return error_response(HawalaError::crypto_error(format!("Failed to derive public key: {}", e))),
    };

    success_response(serde_json::json!({
        "signature": format!("0x{}", signature.to_hex()),
        "public_key": format!("0x{}", public_key.to_hex())
    }))
}

/// Verify a BIP-340 Schnorr signature
/// 
/// # Input
/// ```json
/// {
///   "message": "0x...",  // 32-byte message hash (hex)
///   "signature": "0x...",  // 64-byte Schnorr signature (hex)
///   "public_key": "0x..."  // 32-byte x-only public key (hex)
/// }
/// ```
/// 
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "valid": true
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_schnorr_verify(input: *const c_char) -> *mut c_char {
    let input_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        message: String,
        signature: String,
        public_key: String,
    }

    let request: Request = match serde_json::from_str(input_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("JSON parse error: {}", e))),
    };

    // Parse message (32 bytes)
    let message_str = request.message.strip_prefix("0x").unwrap_or(&request.message);
    let message_bytes = match hex::decode(message_str) {
        Ok(b) if b.len() == 32 => {
            let mut arr = [0u8; 32];
            arr.copy_from_slice(&b);
            arr
        },
        Ok(b) => return error_response(HawalaError::invalid_input(format!("Message must be 32 bytes, got {}", b.len()))),
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid message hex: {}", e))),
    };

    // Parse signature (64 bytes)
    let sig_str = request.signature.strip_prefix("0x").unwrap_or(&request.signature);
    let signature = match hex::decode(sig_str) {
        Ok(b) => match crate::crypto::schnorr::SchnorrSig::from_slice(&b) {
            Ok(sig) => sig,
            Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid signature: {}", e))),
        },
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid signature hex: {}", e))),
    };

    // Parse public key (32 bytes)
    let pk_str = request.public_key.strip_prefix("0x").unwrap_or(&request.public_key);
    let public_key = match hex::decode(pk_str) {
        Ok(b) => match crate::crypto::schnorr::XOnlyPubKey::from_slice(&b) {
            Ok(pk) => pk,
            Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid public key: {}", e))),
        },
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid public key hex: {}", e))),
    };

    let signer = crate::crypto::schnorr::SchnorrSigner::new();
    
    match signer.verify(&message_bytes, &signature, &public_key) {
        Ok(valid) => success_response(serde_json::json!({
            "valid": valid
        })),
        Err(e) => error_response(HawalaError::crypto_error(format!("Verification failed: {}", e))),
    }
}

/// Tweak a public key for Taproot (key-path or with merkle root)
/// 
/// # Input
/// ```json
/// {
///   "internal_key": "0x...",  // 32-byte x-only public key (hex)
///   "merkle_root": "0x..."  // optional 32-byte merkle root (hex)
/// }
/// ```
/// 
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "output_key": "0x...",  // 32-byte tweaked x-only public key (hex)
///     "parity": true  // parity of output key (for script-path)
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_taproot_tweak_pubkey(input: *const c_char) -> *mut c_char {
    let input_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        internal_key: String,
        merkle_root: Option<String>,
    }

    let request: Request = match serde_json::from_str(input_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("JSON parse error: {}", e))),
    };

    // Parse internal key (32 bytes)
    let key_str = request.internal_key.strip_prefix("0x").unwrap_or(&request.internal_key);
    let internal_key = match hex::decode(key_str) {
        Ok(b) => match crate::crypto::schnorr::XOnlyPubKey::from_slice(&b) {
            Ok(pk) => pk,
            Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid internal key: {}", e))),
        },
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid internal key hex: {}", e))),
    };

    // Parse optional merkle root (32 bytes)
    let merkle_root = if let Some(root) = request.merkle_root {
        let root_str = root.strip_prefix("0x").unwrap_or(&root);
        match hex::decode(root_str) {
            Ok(b) => match crate::crypto::taproot::TapMerkleRoot::from_slice(&b) {
                Ok(mr) => Some(mr),
                Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid merkle root: {}", e))),
            },
            Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid merkle root hex: {}", e))),
        }
    } else {
        None
    };

    let tweaker = crate::crypto::taproot::TaprootTweaker::new();
    
    match tweaker.tweak_public_key(&internal_key, merkle_root.as_ref()) {
        Ok(output) => success_response(serde_json::json!({
            "output_key": format!("0x{}", output.output_key.to_hex()),
            "parity": output.parity
        })),
        Err(e) => error_response(HawalaError::crypto_error(format!("Tweak failed: {}", e))),
    }
}

/// Sign a transaction hash for Taproot key-path spending
/// 
/// # Input
/// ```json
/// {
///   "sighash": "0x...",  // 32-byte sighash (hex)
///   "private_key": "0x...",  // 32-byte private key (hex)
///   "merkle_root": "0x..."  // optional 32-byte merkle root (hex)
/// }
/// ```
/// 
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "signature": "0x...",  // 64-byte Schnorr signature (hex)
///     "output_key": "0x..."  // 32-byte tweaked x-only public key (hex)
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_taproot_sign_key_path(input: *const c_char) -> *mut c_char {
    let input_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        sighash: String,
        private_key: String,
        merkle_root: Option<String>,
    }

    let request: Request = match serde_json::from_str(input_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("JSON parse error: {}", e))),
    };

    // Parse sighash (32 bytes)
    let hash_str = request.sighash.strip_prefix("0x").unwrap_or(&request.sighash);
    let sighash = match hex::decode(hash_str) {
        Ok(b) if b.len() == 32 => {
            let mut arr = [0u8; 32];
            arr.copy_from_slice(&b);
            arr
        },
        Ok(b) => return error_response(HawalaError::invalid_input(format!("Sighash must be 32 bytes, got {}", b.len()))),
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid sighash hex: {}", e))),
    };

    // Parse private key (32 bytes)
    let key_str = request.private_key.strip_prefix("0x").unwrap_or(&request.private_key);
    let private_key = match hex::decode(key_str) {
        Ok(b) if b.len() == 32 => b,
        Ok(b) => return error_response(HawalaError::invalid_input(format!("Private key must be 32 bytes, got {}", b.len()))),
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid private key hex: {}", e))),
    };

    // Parse optional merkle root (32 bytes)
    let merkle_root = if let Some(root) = request.merkle_root {
        let root_str = root.strip_prefix("0x").unwrap_or(&root);
        match hex::decode(root_str) {
            Ok(b) => match crate::crypto::taproot::TapMerkleRoot::from_slice(&b) {
                Ok(mr) => Some(mr),
                Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid merkle root: {}", e))),
            },
            Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid merkle root hex: {}", e))),
        }
    } else {
        None
    };

    let signer = crate::crypto::taproot::TaprootSigner::new();
    
    // Sign
    let signature = match signer.sign_key_path(&sighash, &private_key, merkle_root.as_ref()) {
        Ok(sig) => sig,
        Err(e) => return error_response(HawalaError::crypto_error(format!("Signing failed: {}", e))),
    };

    // Get output key
    let output = match signer.get_output_key(&private_key, merkle_root.as_ref()) {
        Ok(o) => o,
        Err(e) => return error_response(HawalaError::crypto_error(format!("Failed to derive output key: {}", e))),
    };

    success_response(serde_json::json!({
        "signature": format!("0x{}", signature.to_hex()),
        "output_key": format!("0x{}", output.output_key.to_hex())
    }))
}

/// Compute a TapLeaf hash for script-path spending
/// 
/// # Input
/// ```json
/// {
///   "script": "0x...",  // script bytes (hex)
///   "version": 192  // optional leaf version (default: 0xc0)
/// }
/// ```
/// 
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "leaf_hash": "0x..."  // 32-byte leaf hash (hex)
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_taproot_leaf_hash(input: *const c_char) -> *mut c_char {
    let input_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        script: String,
        version: Option<u8>,
    }

    let request: Request = match serde_json::from_str(input_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("JSON parse error: {}", e))),
    };

    // Parse script
    let script_str = request.script.strip_prefix("0x").unwrap_or(&request.script);
    let script_bytes = match hex::decode(script_str) {
        Ok(b) => b,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid script hex: {}", e))),
    };

    let version = request.version.unwrap_or(crate::crypto::taproot::TAPSCRIPT_LEAF_VERSION);
    let leaf = crate::crypto::taproot::TapLeaf::with_version(version, script_bytes);

    success_response(serde_json::json!({
        "leaf_hash": format!("0x{}", hex::encode(leaf.hash()))
    }))
}

/// Build a Merkle root from a list of TapLeaf scripts
/// 
/// # Input
/// ```json
/// {
///   "scripts": ["0x...", "0x..."],  // array of script bytes (hex)
///   "versions": [192, 192]  // optional array of leaf versions
/// }
/// ```
/// 
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "merkle_root": "0x..."  // 32-byte merkle root (hex)
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_taproot_merkle_root(input: *const c_char) -> *mut c_char {
    let input_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        scripts: Vec<String>,
        versions: Option<Vec<u8>>,
    }

    let request: Request = match serde_json::from_str(input_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("JSON parse error: {}", e))),
    };

    let default_version = crate::crypto::taproot::TAPSCRIPT_LEAF_VERSION;
    let mut leaves = Vec::with_capacity(request.scripts.len());

    for (i, script) in request.scripts.iter().enumerate() {
        let script_str = script.strip_prefix("0x").unwrap_or(script);
        let script_bytes = match hex::decode(script_str) {
            Ok(b) => b,
            Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid script hex at index {}: {}", i, e))),
        };

        let version = request.versions
            .as_ref()
            .and_then(|v| v.get(i).copied())
            .unwrap_or(default_version);

        leaves.push(crate::crypto::taproot::TapLeaf::with_version(version, script_bytes));
    }

    let tweaker = crate::crypto::taproot::TaprootTweaker::new();
    
    match tweaker.build_merkle_root(&leaves) {
        Ok(root) => success_response(serde_json::json!({
            "merkle_root": format!("0x{}", root.to_hex())
        })),
        Err(e) => error_response(HawalaError::crypto_error(format!("Failed to build merkle root: {}", e))),
    }
}

// =============================================================================
// Multi-Curve Cryptography Operations
// =============================================================================

/// Generate a keypair for the specified curve
///
/// # Input
/// ```json
/// {
///   "curve": "secp256k1" | "ed25519" | "sr25519" | "secp256r1",
///   "seed": "0x..." // 32-byte seed (hex)
/// }
/// ```
///
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "private_key": "0x...",
///     "public_key": "0x...",
///     "curve": "secp256k1"
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_curve_generate_keypair(input: *const c_char) -> *mut c_char {
    let input_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        curve: String,
        seed: String,
    }

    let request: Request = match serde_json::from_str(input_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("JSON parse error: {}", e))),
    };

    let curve_type = match crate::crypto::curves::CurveType::from_str(&request.curve) {
        Some(c) => c,
        None => return error_response(HawalaError::invalid_input(format!("Unknown curve: {}", request.curve))),
    };

    let seed_str = request.seed.strip_prefix("0x").unwrap_or(&request.seed);
    let seed = match hex::decode(seed_str) {
        Ok(b) => b,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid seed hex: {}", e))),
    };

    if seed.len() < 32 {
        return error_response(HawalaError::invalid_input("Seed must be at least 32 bytes"));
    }

    match crate::crypto::curves::generate_keypair(curve_type, &seed) {
        Ok((private_key, public_key)) => success_response(serde_json::json!({
            "private_key": format!("0x{}", hex::encode(&private_key)),
            "public_key": format!("0x{}", hex::encode(&public_key)),
            "curve": curve_type.name()
        })),
        Err(e) => error_response(HawalaError::crypto_error(format!("Keypair generation failed: {}", e))),
    }
}

/// Derive public key from private key for the specified curve
///
/// # Input
/// ```json
/// {
///   "curve": "secp256k1" | "ed25519" | "sr25519" | "secp256r1",
///   "private_key": "0x..." // hex-encoded private key
/// }
/// ```
///
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "public_key": "0x...",
///     "curve": "secp256k1"
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_curve_public_key(input: *const c_char) -> *mut c_char {
    let input_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        curve: String,
        private_key: String,
    }

    let request: Request = match serde_json::from_str(input_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("JSON parse error: {}", e))),
    };

    let curve_type = match crate::crypto::curves::CurveType::from_str(&request.curve) {
        Some(c) => c,
        None => return error_response(HawalaError::invalid_input(format!("Unknown curve: {}", request.curve))),
    };

    let pk_str = request.private_key.strip_prefix("0x").unwrap_or(&request.private_key);
    let private_key = match hex::decode(pk_str) {
        Ok(b) => b,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid private key hex: {}", e))),
    };

    match crate::crypto::curves::public_key_from_private(curve_type, &private_key) {
        Ok(public_key) => success_response(serde_json::json!({
            "public_key": format!("0x{}", hex::encode(&public_key)),
            "curve": curve_type.name()
        })),
        Err(e) => error_response(HawalaError::crypto_error(format!("Public key derivation failed: {}", e))),
    }
}

/// Sign a message using the specified curve
///
/// # Input
/// ```json
/// {
///   "curve": "secp256k1" | "ed25519" | "sr25519" | "secp256r1",
///   "private_key": "0x...",
///   "message": "0x..." // hex-encoded message to sign
/// }
/// ```
///
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "signature": "0x...",
///     "public_key": "0x...",
///     "curve": "secp256k1"
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_curve_sign(input: *const c_char) -> *mut c_char {
    let input_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        curve: String,
        private_key: String,
        message: String,
    }

    let request: Request = match serde_json::from_str(input_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("JSON parse error: {}", e))),
    };

    let curve_type = match crate::crypto::curves::CurveType::from_str(&request.curve) {
        Some(c) => c,
        None => return error_response(HawalaError::invalid_input(format!("Unknown curve: {}", request.curve))),
    };

    let pk_str = request.private_key.strip_prefix("0x").unwrap_or(&request.private_key);
    let private_key = match hex::decode(pk_str) {
        Ok(b) => b,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid private key hex: {}", e))),
    };

    let msg_str = request.message.strip_prefix("0x").unwrap_or(&request.message);
    let message = match hex::decode(msg_str) {
        Ok(b) => b,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid message hex: {}", e))),
    };

    match crate::crypto::curves::sign_with_pubkey(curve_type, &private_key, &message) {
        Ok((signature, public_key)) => success_response(serde_json::json!({
            "signature": format!("0x{}", hex::encode(&signature)),
            "public_key": format!("0x{}", hex::encode(&public_key)),
            "curve": curve_type.name()
        })),
        Err(e) => error_response(HawalaError::crypto_error(format!("Signing failed: {}", e))),
    }
}

/// Verify a signature using the specified curve
///
/// # Input
/// ```json
/// {
///   "curve": "secp256k1" | "ed25519" | "sr25519" | "secp256r1",
///   "public_key": "0x...",
///   "message": "0x...",
///   "signature": "0x..."
/// }
/// ```
///
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "valid": true,
///     "curve": "secp256k1"
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_curve_verify(input: *const c_char) -> *mut c_char {
    let input_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        curve: String,
        public_key: String,
        message: String,
        signature: String,
    }

    let request: Request = match serde_json::from_str(input_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("JSON parse error: {}", e))),
    };

    let curve_type = match crate::crypto::curves::CurveType::from_str(&request.curve) {
        Some(c) => c,
        None => return error_response(HawalaError::invalid_input(format!("Unknown curve: {}", request.curve))),
    };

    let pk_str = request.public_key.strip_prefix("0x").unwrap_or(&request.public_key);
    let public_key = match hex::decode(pk_str) {
        Ok(b) => b,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid public key hex: {}", e))),
    };

    let msg_str = request.message.strip_prefix("0x").unwrap_or(&request.message);
    let message = match hex::decode(msg_str) {
        Ok(b) => b,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid message hex: {}", e))),
    };

    let sig_str = request.signature.strip_prefix("0x").unwrap_or(&request.signature);
    let signature = match hex::decode(sig_str) {
        Ok(b) => b,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid signature hex: {}", e))),
    };

    match crate::crypto::curves::verify(curve_type, &public_key, &message, &signature) {
        Ok(valid) => success_response(serde_json::json!({
            "valid": valid,
            "curve": curve_type.name()
        })),
        Err(e) => error_response(HawalaError::crypto_error(format!("Verification failed: {}", e))),
    }
}

/// Get information about a curve type
///
/// # Input
/// ```json
/// {
///   "curve": "secp256k1" | "ed25519" | "sr25519" | "secp256r1"
/// }
/// ```
///
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "name": "secp256k1",
///     "private_key_size": 32,
///     "public_key_size": 33,
///     "signature_size": 64,
///     "chains": ["bitcoin", "ethereum", ...]
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_curve_info(input: *const c_char) -> *mut c_char {
    let input_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        curve: String,
    }

    let request: Request = match serde_json::from_str(input_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("JSON parse error: {}", e))),
    };

    let curve_type = match crate::crypto::curves::CurveType::from_str(&request.curve) {
        Some(c) => c,
        None => return error_response(HawalaError::invalid_input(format!("Unknown curve: {}", request.curve))),
    };

    success_response(serde_json::json!({
        "name": curve_type.name(),
        "private_key_size": curve_type.private_key_size(),
        "public_key_size": curve_type.public_key_size(),
        "signature_size": curve_type.signature_size(),
        "chains": curve_type.chains()
    }))
}

// =============================================================================
// QR Code Encoding/Decoding for Air-Gapped Signing
// =============================================================================

/// Encode data as UR (Uniform Resource) frames for animated QR display
///
/// # Input
/// ```json
/// {
///   "type": "crypto-psbt" | "crypto-account" | "crypto-hdkey" | "bytes",
///   "data": "0x...",  // hex-encoded data
///   "max_fragment_size": 100  // optional, default 100
/// }
/// ```
///
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "frames": ["ur:crypto-psbt/1-3/...", "ur:crypto-psbt/2-3/...", ...],
///     "frame_count": 3,
///     "type": "crypto-psbt"
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_qr_encode_ur(input: *const c_char) -> *mut c_char {
    let input_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        #[serde(rename = "type")]
        ur_type: String,
        data: String,
        max_fragment_size: Option<usize>,
    }

    let request: Request = match serde_json::from_str(input_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("JSON parse error: {}", e))),
    };

    let ur_type = match crate::qr::UrType::from_str(&request.ur_type) {
        Some(t) => t,
        None => return error_response(HawalaError::invalid_input(format!("Unknown UR type: {}", request.ur_type))),
    };

    let data_str = request.data.strip_prefix("0x").unwrap_or(&request.data);
    let data = match hex::decode(data_str) {
        Ok(b) => b,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid data hex: {}", e))),
    };

    let max_frag_size = request.max_fragment_size.unwrap_or(crate::qr::RECOMMENDED_FRAGMENT_SIZE);
    
    let encoder = crate::qr::UrEncoder::new(ur_type, &data)
        .with_fragment_size(max_frag_size);
    
    match encoder.encode() {
        Ok(frames) => {
            let frame_count = frames.len();
            success_response(serde_json::json!({
                "frames": frames,
                "frame_count": frame_count,
                "type": ur_type.as_str()
            }))
        }
        Err(e) => error_response(HawalaError::crypto_error(format!("UR encoding failed: {}", e))),
    }
}

/// Encode data as a simple QR-ready payload (for small data)
///
/// # Input
/// ```json
/// {
///   "data": "0x...",  // hex-encoded data
///   "format": "hex" | "base64" | "raw"  // output format
/// }
/// ```
///
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "payload": "...",
///     "size": 256,
///     "can_fit_single_qr": true
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_qr_encode_simple(input: *const c_char) -> *mut c_char {
    let input_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        data: String,
        format: Option<String>,
    }

    let request: Request = match serde_json::from_str(input_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("JSON parse error: {}", e))),
    };

    let data_str = request.data.strip_prefix("0x").unwrap_or(&request.data);
    let data = match hex::decode(data_str) {
        Ok(b) => b,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid data hex: {}", e))),
    };

    let format = request.format.unwrap_or_else(|| "hex".to_string());
    
    let payload = match format.as_str() {
        "hex" => format!("0x{}", hex::encode(&data)),
        "base64" => {
            use base64::Engine;
            base64::engine::general_purpose::STANDARD.encode(&data)
        },
        "raw" => String::from_utf8_lossy(&data).to_string(),
        _ => return error_response(HawalaError::invalid_input(format!("Unknown format: {}", format))),
    };

    let size = data.len();
    let can_fit = size <= crate::qr::MAX_QR_BYTES_M;

    success_response(serde_json::json!({
        "payload": payload,
        "size": size,
        "can_fit_single_qr": can_fit
    }))
}

/// Decode a UR (Uniform Resource) string
///
/// # Input
/// ```json
/// {
///   "ur": "ur:crypto-psbt/..."
/// }
/// ```
///
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "type": "crypto-psbt",
///     "data": "0x...",
///     "complete": true
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_qr_decode_ur(input: *const c_char) -> *mut c_char {
    let input_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        ur: String,
    }

    let request: Request = match serde_json::from_str(input_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("JSON parse error: {}", e))),
    };

    let mut decoder = crate::qr::UrDecoder::new();
    
    // Try single-part decode first
    match crate::qr::UrDecoder::decode_single(&request.ur) {
        Ok((ur_type, data)) => success_response(serde_json::json!({
            "type": ur_type.as_str(),
            "data": format!("0x{}", hex::encode(&data)),
            "complete": true
        })),
        Err(_) => {
            // Try multi-part decode
            match decoder.receive(&request.ur) {
                Ok(complete) => {
                    if complete {
                        match decoder.result() {
                            Ok((ur_type, data)) => success_response(serde_json::json!({
                                "type": ur_type.as_str(),
                                "data": format!("0x{}", hex::encode(&data)),
                                "complete": true
                            })),
                            Err(e) => error_response(HawalaError::parse_error(format!("Failed to extract result: {}", e))),
                        }
                    } else {
                        success_response(serde_json::json!({
                            "complete": false,
                            "progress": decoder.progress(),
                            "message": "Submit more parts to complete"
                        }))
                    }
                }
                Err(e) => error_response(HawalaError::parse_error(format!("UR decode error: {}", e))),
            }
        }
    }
}

/// Create a new UR decoder session for multi-part QR scanning
///
/// # Input
/// None (empty string or "{}")
///
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "session_id": "abc123..."
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_qr_decoder_create() -> *mut c_char {
    // Generate a simple session ID
    let session_id = format!("{:016x}", std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos());

    success_response(serde_json::json!({
        "session_id": session_id,
        "message": "Use hawala_qr_decoder_receive to submit frames"
    }))
}

/// Get supported UR types
///
/// # Input
/// None
///
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "types": [
///       {"name": "crypto-psbt", "description": "Partially Signed Bitcoin Transaction"},
///       {"name": "crypto-account", "description": "Cryptocurrency account"},
///       ...
///     ]
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_qr_supported_types() -> *mut c_char {
    success_response(serde_json::json!({
        "types": [
            {"name": "crypto-psbt", "description": "Partially Signed Bitcoin Transaction (BIP-174)"},
            {"name": "crypto-account", "description": "Cryptocurrency account descriptor"},
            {"name": "crypto-hdkey", "description": "HD wallet key (BIP-32)"},
            {"name": "crypto-output", "description": "Bitcoin output descriptor"},
            {"name": "crypto-seed", "description": "Cryptographic seed"},
            {"name": "crypto-keypath", "description": "Key derivation path"},
            {"name": "bytes", "description": "Raw byte data"},
            {"name": "crypto-request", "description": "Signing request"},
            {"name": "crypto-response", "description": "Signing response"}
        ],
        "max_single_qr_size_bytes": crate::qr::MAX_QR_BYTES_M,
        "recommended_fragment_size": crate::qr::RECOMMENDED_FRAGMENT_SIZE
    }))
}

// =============================================================================
// HD Key Derivation (BIP-32 / SLIP-0010)
// =============================================================================

/// Derive a child key from a parent key using BIP-32 or SLIP-0010
///
/// # Input
/// ```json
/// {
///   "curve": "secp256k1" | "ed25519",
///   "seed": "0x...",  // 64-byte seed from mnemonic
///   "path": "m/44'/0'/0'/0/0"  // derivation path
/// }
/// ```
///
/// # Output
/// ```json
/// {
///   "success": true,
///   "data": {
///     "private_key": "0x...",
///     "public_key": "0x...",
///     "chain_code": "0x...",
///     "path": "m/44'/0'/0'/0/0"
///   }
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn hawala_derive_key(input: *const c_char) -> *mut c_char {
    let input_str = match parse_input(input) {
        Ok(s) => s,
        Err(e) => return e,
    };

    #[derive(serde::Deserialize)]
    struct Request {
        curve: String,
        seed: String,
        path: String,
    }

    let request: Request = match serde_json::from_str(input_str) {
        Ok(r) => r,
        Err(e) => return error_response(HawalaError::invalid_input(format!("JSON parse error: {}", e))),
    };

    let seed_str = request.seed.strip_prefix("0x").unwrap_or(&request.seed);
    let seed = match hex::decode(seed_str) {
        Ok(b) => b,
        Err(e) => return error_response(HawalaError::invalid_input(format!("Invalid seed hex: {}", e))),
    };

    // Use existing wallet derivation logic based on curve
    match request.curve.to_lowercase().as_str() {
        "secp256k1" => {
            // BIP-32 derivation
            match derive_secp256k1_key(&seed, &request.path) {
                Ok((private_key, public_key, chain_code)) => success_response(serde_json::json!({
                    "private_key": format!("0x{}", hex::encode(&private_key)),
                    "public_key": format!("0x{}", hex::encode(&public_key)),
                    "chain_code": format!("0x{}", hex::encode(&chain_code)),
                    "path": request.path,
                    "curve": "secp256k1"
                })),
                Err(e) => error_response(HawalaError::crypto_error(format!("Derivation failed: {}", e))),
            }
        }
        "ed25519" => {
            // SLIP-0010 derivation
            match derive_ed25519_key(&seed, &request.path) {
                Ok((private_key, public_key, chain_code)) => success_response(serde_json::json!({
                    "private_key": format!("0x{}", hex::encode(&private_key)),
                    "public_key": format!("0x{}", hex::encode(&public_key)),
                    "chain_code": format!("0x{}", hex::encode(&chain_code)),
                    "path": request.path,
                    "curve": "ed25519"
                })),
                Err(e) => error_response(HawalaError::crypto_error(format!("Derivation failed: {}", e))),
            }
        }
        _ => error_response(HawalaError::invalid_input(format!("Unsupported curve for derivation: {}", request.curve))),
    }
}

// Helper for BIP-32 secp256k1 derivation
fn derive_secp256k1_key(seed: &[u8], path: &str) -> Result<(Vec<u8>, Vec<u8>, Vec<u8>), String> {
    use hmac::{Hmac, Mac};
    use sha2::Sha512;
    
    type HmacSha512 = Hmac<Sha512>;
    
    // Master key derivation
    let mut mac = HmacSha512::new_from_slice(b"Bitcoin seed")
        .map_err(|e| format!("HMAC error: {}", e))?;
    mac.update(seed);
    let result = mac.finalize().into_bytes();
    
    let mut key = result[..32].to_vec();
    let mut chain_code = result[32..].to_vec();
    
    // Parse and apply path
    let path = path.trim_start_matches("m/");
    if !path.is_empty() {
        for component in path.split('/') {
            let (index, hardened) = if component.ends_with('\'') || component.ends_with('h') {
                let idx: u32 = component.trim_end_matches(|c| c == '\'' || c == 'h')
                    .parse()
                    .map_err(|_| format!("Invalid path component: {}", component))?;
                (idx | 0x80000000, true)
            } else {
                let idx: u32 = component.parse()
                    .map_err(|_| format!("Invalid path component: {}", component))?;
                (idx, false)
            };
            
            let mut mac = HmacSha512::new_from_slice(&chain_code)
                .map_err(|e| format!("HMAC error: {}", e))?;
            
            if hardened {
                mac.update(&[0u8]);
                mac.update(&key);
            } else {
                // Compute public key for non-hardened derivation
                let secp = secp256k1::Secp256k1::new();
                let secret_key = secp256k1::SecretKey::from_slice(&key)
                    .map_err(|e| format!("Invalid key: {}", e))?;
                let public_key = secp256k1::PublicKey::from_secret_key(&secp, &secret_key);
                mac.update(&public_key.serialize());
            }
            
            mac.update(&index.to_be_bytes());
            let result = mac.finalize().into_bytes();
            
            // Add to parent key
            let mut key_int = secp256k1::SecretKey::from_slice(&key)
                .map_err(|e| format!("Invalid key: {}", e))?;
            key_int = key_int.add_tweak(&secp256k1::Scalar::from_be_bytes(result[..32].try_into().unwrap()).unwrap())
                .map_err(|e| format!("Key tweak failed: {}", e))?;
            
            key = key_int.secret_bytes().to_vec();
            chain_code = result[32..].to_vec();
        }
    }
    
    // Compute public key
    let secp = secp256k1::Secp256k1::new();
    let secret_key = secp256k1::SecretKey::from_slice(&key)
        .map_err(|e| format!("Invalid derived key: {}", e))?;
    let public_key = secp256k1::PublicKey::from_secret_key(&secp, &secret_key);
    
    Ok((key, public_key.serialize().to_vec(), chain_code))
}

// Helper for SLIP-0010 ed25519 derivation
fn derive_ed25519_key(seed: &[u8], path: &str) -> Result<(Vec<u8>, Vec<u8>, Vec<u8>), String> {
    use hmac::{Hmac, Mac};
    use sha2::Sha512;
    
    type HmacSha512 = Hmac<Sha512>;
    
    // Master key derivation (SLIP-0010 uses "ed25519 seed" for Ed25519)
    let mut mac = HmacSha512::new_from_slice(b"ed25519 seed")
        .map_err(|e| format!("HMAC error: {}", e))?;
    mac.update(seed);
    let result = mac.finalize().into_bytes();
    
    let mut key = result[..32].to_vec();
    let mut chain_code = result[32..].to_vec();
    
    // Parse and apply path (Ed25519 only supports hardened derivation)
    let path = path.trim_start_matches("m/");
    if !path.is_empty() {
        for component in path.split('/') {
            let index: u32 = if component.ends_with('\'') || component.ends_with('h') {
                let idx: u32 = component.trim_end_matches(|c| c == '\'' || c == 'h')
                    .parse()
                    .map_err(|_| format!("Invalid path component: {}", component))?;
                idx | 0x80000000
            } else {
                // Ed25519 SLIP-0010 requires all hardened
                let idx: u32 = component.parse()
                    .map_err(|_| format!("Invalid path component: {}", component))?;
                idx | 0x80000000
            };
            
            let mut mac = HmacSha512::new_from_slice(&chain_code)
                .map_err(|e| format!("HMAC error: {}", e))?;
            mac.update(&[0u8]);
            mac.update(&key);
            mac.update(&index.to_be_bytes());
            let result = mac.finalize().into_bytes();
            
            key = result[..32].to_vec();
            chain_code = result[32..].to_vec();
        }
    }
    
    // Compute public key
    use ed25519_dalek::{SigningKey, VerifyingKey};
    let signing_key = SigningKey::from_bytes(&key.clone().try_into().map_err(|_| "Invalid key length")?);
    let verifying_key: VerifyingKey = (&signing_key).into();
    
    Ok((key, verifying_key.to_bytes().to_vec(), chain_code))
}
