//! Security Module
//!
//! Advanced security features including:
//! - Threat detection and anomaly patterns
//! - Transaction policies and spending limits
//! - Key rotation infrastructure
//! - Secure memory utilities
//! - Cryptographic verification
//! - Shamir's Secret Sharing for seed phrase recovery
//! - Transaction simulation and preview
//! - Token approval management
//! - Phishing and scam detection
//! - Address whitelisting

pub mod threat_detection;
pub mod tx_policy;
pub mod key_rotation;
pub mod secure_memory;
pub mod verification;
pub mod shamir;

// Phase 2: Security & Trust Features
pub mod simulation;
pub mod approvals;
pub mod phishing;
pub mod whitelist;

pub use threat_detection::*;
pub use tx_policy::*;
pub use key_rotation::*;
pub use secure_memory::*;
pub use verification::*;
pub use shamir::*;

// Phase 2 exports
pub use simulation::*;
pub use approvals::*;
pub use phishing::*;
pub use whitelist::*;
