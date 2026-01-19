//! EIP-7702 Account Delegation
//!
//! Implements EIP-7702 transaction type (0x04) for temporary EOA delegation.
//! Reference: https://eips.ethereum.org/EIPS/eip-7702
//!
//! EIP-7702 allows EOAs to temporarily delegate to contract code during a
//! transaction, enabling smart account features without permanent migration.

pub mod types;
pub mod authorization;
pub mod transaction;
pub mod signer;

#[cfg(test)]
mod tests;

pub use types::*;
pub use authorization::*;
pub use transaction::*;
pub use signer::*;
