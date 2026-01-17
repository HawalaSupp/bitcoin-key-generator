//! API Module
//!
//! Unified blockchain API clients with fallback support.

mod providers;

pub use providers::*;

use std::os::raw::c_char;
#[allow(unused_imports)]
use crate::error::HawalaError;
use crate::types::*;

/// Fetch balances for multiple addresses (FFI entry point)
/// Delegates to the balances module for actual fetching
pub fn fetch_balances(request: &BalanceRequest) -> *mut c_char {
    // Use the expanded balances module
    let result = crate::balances::fetch_all_balances(request);
    
    let response = match result {
        Ok(balances) => ApiResponse::ok(BalanceResponse { balances }),
        Err(e) => ApiResponse::err(e),
    };
    
    let json = response.to_json();
    match std::ffi::CString::new(json) {
        Ok(c_str) => c_str.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}
