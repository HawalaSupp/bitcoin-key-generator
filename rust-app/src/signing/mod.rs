//! External Signature Compilation
//!
//! This module provides functionality for hardware wallet and air-gapped signing:
//! 1. Generate pre-image hashes from unsigned transactions
//! 2. Accept externally-signed signatures
//! 3. Compile signatures into final signed transactions
//!
//! Supported chains:
//! - Bitcoin (Legacy, SegWit, Taproot)
//! - Ethereum (Legacy, EIP-2930, EIP-1559, EIP-7702)
//! - Cosmos (Amino, Protobuf/Direct)
//! - Solana (Legacy, Versioned)

pub mod preimage;
pub mod compiler;

pub use preimage::*;
pub use compiler::*;
