//! Fiat on-ramp integration module
//!
//! Supports:
//! - MoonPay
//! - Transak
//! - Ramp Network
//! - Quote comparison

pub mod types;
pub mod moonpay;
pub mod transak;
pub mod ramp;
#[cfg(test)]
pub mod tests;

pub use types::*;
pub use moonpay::*;
pub use transak::*;
pub use ramp::*;
