//! Wallet Module
//!
//! Handles wallet creation, restoration, key derivation, address validation,
//! UTXO management, and nonce tracking.

mod keygen;
mod derivation;
mod validation;
mod address_validation;
mod amount_validation;
mod derivation_path;
pub mod utxo;
pub mod nonce;

pub use keygen::*;
pub use derivation::*;
pub use validation::*;
pub use address_validation::*;
pub use amount_validation::*;
pub use derivation_path::*;

use crate::error::{HawalaResult};
use crate::types::*;

/// Create a new wallet with random entropy
pub fn create_new_wallet() -> HawalaResult<(String, AllKeys)> {
    keygen::create_wallet_from_entropy()
}

/// Generate keys directly from a BIP39 seed
/// This is the lower-level function used by create_new_wallet and restore_from_mnemonic
pub fn generate_keys_from_seed(seed: &[u8]) -> HawalaResult<AllKeys> {
    derivation::derive_all_keys(seed)
}

/// Restore wallet from mnemonic phrase
pub fn restore_from_mnemonic(mnemonic: &str) -> HawalaResult<AllKeys> {
    keygen::restore_wallet(mnemonic)
}

/// Validate a mnemonic phrase
pub fn validate_mnemonic(mnemonic: &str) -> bool {
    validation::is_valid_mnemonic(mnemonic)
}

/// Validate an address for a specific chain
pub fn validate_address(address: &str, chain: Chain) -> (bool, Option<String>) {
    validation::validate_chain_address(address, chain)
}
