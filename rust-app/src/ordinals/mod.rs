//! Ordinals and BRC-20 module
//!
//! Provides support for Bitcoin Ordinals inscriptions and BRC-20 tokens.

pub mod types;
pub mod indexer;
pub mod parser;

#[cfg(test)]
pub mod tests;

pub use types::*;
pub use indexer::*;
pub use parser::*;
