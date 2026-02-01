//! IBC (Inter-Blockchain Communication) Transfer Module
//!
//! Implements cross-chain token transfers for Cosmos SDK chains using the IBC protocol.
//! Supports channel discovery, MsgTransfer building, and packet tracking.

pub mod types;
pub mod channels;
pub mod client;
pub mod transfer;

#[cfg(test)]
mod tests;

pub use types::*;
pub use channels::*;
pub use client::*;
pub use transfer::*;
