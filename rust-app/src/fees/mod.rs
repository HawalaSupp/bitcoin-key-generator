//! Fee Estimation Module
//!
//! Provides fee estimates for all supported chains.

mod estimator;
mod intelligence;

pub use estimator::*;
pub use intelligence::*;

use std::os::raw::c_char;
#[allow(unused_imports)]
use crate::error::HawalaError;
use crate::types::*;

/// Estimate fees for a chain (FFI entry point)
pub fn estimate_fees(chain: Chain) -> *mut c_char {
    let result = estimator::get_fee_estimate(chain);
    
    let response = match result {
        Ok(estimate) => ApiResponse::ok(estimate),
        Err(e) => ApiResponse::err(e),
    };
    
    let json = response.to_json();
    match std::ffi::CString::new(json) {
        Ok(c_str) => c_str.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}
