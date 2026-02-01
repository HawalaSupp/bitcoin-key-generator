//! ABI (Application Binary Interface) module for Solidity/EVM contracts
//!
//! This module provides complete ABI encoding/decoding functionality:
//! - All Solidity types (uint, int, address, bool, bytes, string, arrays, tuples)
//! - Function call encoding and result decoding
//! - Event log decoding
//! - JSON ABI parsing
//! - Function selector calculation

pub mod types;
pub mod encoder;
pub mod decoder;
pub mod parser;
pub mod selector;

#[cfg(test)]
mod tests;

pub use types::*;
pub use encoder::*;
pub use decoder::*;
pub use parser::*;
pub use selector::*;
