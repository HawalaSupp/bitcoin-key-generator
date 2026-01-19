//! Cryptographic primitives for Hawala
//!
//! This module provides low-level cryptographic operations including:
//! - Schnorr signatures (BIP-340) for Bitcoin Taproot
//! - Taproot key tweaking and script trees
//! - Tagged hash functions
//! - Multi-curve abstractions (secp256k1, ed25519, sr25519, secp256r1)

pub mod curves;
pub mod schnorr;
pub mod taproot;

pub use curves::{
    CurveType, CurveError,
    Secp256k1Curve, Ed25519Curve, Sr25519Curve, Secp256r1Curve,
    EllipticCurve, RecoverableSignature, KeyExchange, KeyDerivation,
};
pub use schnorr::*;
pub use taproot::*;
