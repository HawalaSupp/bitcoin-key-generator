//! Transaction Module
//!
//! Handles transaction building, signing, broadcasting, and tracking.

mod builder;
mod signer;
mod broadcaster;
mod cancellation;
mod replay_protection;
mod tracker;

pub use builder::*;
pub use signer::*;
pub use broadcaster::*;
pub use cancellation::*;
pub use replay_protection::*;
pub use tracker::*;

use std::os::raw::c_char;
use crate::error::HawalaError;
use crate::types::*;

/// Helper to create FFI response
fn ffi_response<T: serde::Serialize>(result: Result<T, HawalaError>) -> *mut c_char {
    let response = match result {
        Ok(data) => ApiResponse::ok(data),
        Err(e) => ApiResponse::err(e),
    };
    
    let json = response.to_json();
    match std::ffi::CString::new(json) {
        Ok(c_str) => c_str.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Prepare a Bitcoin transaction
pub fn prepare_bitcoin_transaction(request: &TransactionRequest) -> *mut c_char {
    let result = builder::build_bitcoin_transaction(request);
    ffi_response(result)
}

/// Prepare an EVM transaction (Ethereum, BSC, Polygon, etc.)
pub fn prepare_evm_transaction(request: &TransactionRequest) -> *mut c_char {
    let result = builder::build_evm_transaction(request);
    ffi_response(result)
}

/// Prepare a Litecoin transaction
pub fn prepare_litecoin_transaction(request: &TransactionRequest) -> *mut c_char {
    let result = builder::build_litecoin_transaction(request);
    ffi_response(result)
}

/// Prepare a Solana transaction
pub fn prepare_solana_transaction(request: &TransactionRequest) -> *mut c_char {
    let result = builder::build_solana_transaction(request);
    ffi_response(result)
}

/// Prepare an XRP transaction
pub fn prepare_xrp_transaction(request: &TransactionRequest) -> *mut c_char {
    let result = builder::build_xrp_transaction(request);
    ffi_response(result)
}

