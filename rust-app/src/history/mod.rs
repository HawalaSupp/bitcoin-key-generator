//! History Module
//!
//! Fetches transaction history across all chains.

mod fetcher;

pub use fetcher::*;

use std::os::raw::c_char;
#[allow(unused_imports)]
use crate::error::HawalaError;
use crate::types::*;

/// Fetch transaction history (FFI entry point)
pub fn fetch_history(request: &HistoryRequest) -> *mut c_char {
    let result = fetcher::fetch_all_history(request);
    
    let response = match result {
        Ok(entries) => ApiResponse::ok(entries),
        Err(e) => ApiResponse::err(e),
    };
    
    let json = response.to_json();
    match std::ffi::CString::new(json) {
        Ok(c_str) => c_str.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}
