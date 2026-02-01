//! DEX Aggregator Module
//!
//! Provides unified interface for fetching swap quotes from multiple DEX aggregators:
//! - 1inch Fusion API (primary)
//! - 0x API (fallback)
//! - Native DEX integration (THORChain, Osmosis - existing)
//!
//! # Example
//! ```rust,ignore
//! use hawala::dex::{DEXAggregator, SwapQuoteRequest};
//!
//! let request = SwapQuoteRequest {
//!     chain: Chain::Ethereum,
//!     from_token: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE".to_string(), // ETH
//!     to_token: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48".to_string(),   // USDC
//!     amount: "1000000000000000000".to_string(), // 1 ETH
//!     slippage: 0.5,
//!     from_address: "0x...".to_string(),
//! };
//!
//! let quotes = DEXAggregator::get_best_quote(&request)?;
//! ```

pub mod types;
pub mod oneinch;
pub mod zerox;
pub mod aggregator;

pub use types::*;
pub use aggregator::*;

#[cfg(test)]
mod tests;
