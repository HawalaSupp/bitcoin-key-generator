//! EIP-712 Typed Data Signing
//!
//! Implementation of EIP-712 typed structured data hashing and signing.
//! Used for secure, human-readable signing requests in dApps.
//!
//! # Reference
//! - <https://eips.ethereum.org/EIPS/eip-712>
//!
//! # Example
//! ```rust,ignore
//! use rust_app::eip712::{TypedData, Eip712Signer};
//!
//! let typed_data = TypedData::from_json(json_string)?;
//! let hash = typed_data.encode_hash()?;
//! let signature = Eip712Signer::sign(&hash, &private_key)?;
//! ```

pub mod types;
pub mod encoder;
pub mod hasher;
pub mod signer;

pub use types::*;
pub use encoder::*;
pub use hasher::*;
pub use signer::*;

#[cfg(test)]
mod tests;
