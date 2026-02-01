//! Cross-chain bridge module
//!
//! This module provides integration with multiple bridge protocols for cross-chain
//! token transfers including Wormhole, LayerZero, and Stargate.

pub mod types;
pub mod wormhole;
pub mod layerzero;
pub mod stargate;
pub mod aggregator;

#[cfg(test)]
pub mod tests;

pub use types::*;
pub use aggregator::BridgeAggregator;
pub use wormhole::WormholeClient;
pub use layerzero::LayerZeroClient;
pub use stargate::StargateClient;
