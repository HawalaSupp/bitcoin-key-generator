//! CPFP (Child-Pays-For-Parent) module for accelerating stuck Bitcoin transactions
//!
//! CPFP allows users to speed up unconfirmed transactions by creating a child
//! transaction that pays a higher fee, incentivizing miners to include both.

pub mod types;
pub mod builder;
pub mod calculator;

#[cfg(test)]
pub mod tests;

pub use types::*;
pub use builder::*;
pub use calculator::*;
