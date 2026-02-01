//! ERC-4337 Account Abstraction Implementation
//!
//! This module provides comprehensive support for ERC-4337:
//! - Smart account creation and management
//! - UserOperation building and signing
//! - Bundler interaction
//! - Paymaster integration for gasless transactions
//! - Gas account management

pub mod user_operation;
pub mod account;
pub mod bundler;
pub mod paymaster;
pub mod gas_account;

pub use user_operation::*;
pub use account::*;
pub use bundler::*;
pub use paymaster::*;
pub use gas_account::*;

use crate::error::{HawalaError, ErrorCode};
use serde::{Deserialize, Serialize};

/// Chain configurations for ERC-4337
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ERC4337Chain {
    Ethereum,
    Polygon,
    Arbitrum,
    Optimism,
    Base,
    Avalanche,
    BNB,
    Sepolia,
    Mumbai,
}

impl ERC4337Chain {
    /// Get the entry point address (v0.7)
    pub fn entry_point(&self) -> &'static str {
        // ERC-4337 v0.7 EntryPoint (same on all chains)
        "0x0000000071727De22E5E9d8BAf0edAc6f37da032"
    }
    
    /// Get the v0.6 entry point (legacy)
    pub fn entry_point_v06(&self) -> &'static str {
        "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789"
    }
    
    /// Get default bundler URL
    pub fn default_bundler_url(&self) -> &'static str {
        match self {
            Self::Ethereum => "https://api.pimlico.io/v2/1/rpc",
            Self::Polygon => "https://api.pimlico.io/v2/137/rpc",
            Self::Arbitrum => "https://api.pimlico.io/v2/42161/rpc",
            Self::Optimism => "https://api.pimlico.io/v2/10/rpc",
            Self::Base => "https://api.pimlico.io/v2/8453/rpc",
            Self::Avalanche => "https://api.pimlico.io/v2/43114/rpc",
            Self::BNB => "https://api.pimlico.io/v2/56/rpc",
            Self::Sepolia => "https://api.pimlico.io/v2/11155111/rpc",
            Self::Mumbai => "https://api.pimlico.io/v2/80001/rpc",
        }
    }
    
    /// Get chain ID
    pub fn chain_id(&self) -> u64 {
        match self {
            Self::Ethereum => 1,
            Self::Polygon => 137,
            Self::Arbitrum => 42161,
            Self::Optimism => 10,
            Self::Base => 8453,
            Self::Avalanche => 43114,
            Self::BNB => 56,
            Self::Sepolia => 11155111,
            Self::Mumbai => 80001,
        }
    }
    
    /// Get safe singleton address
    pub fn safe_singleton(&self) -> &'static str {
        // Safe v1.4.1 singleton (same on all chains)
        "0x41675C099F32341bf84BFc5382aF534df5C7461a"
    }
    
    /// Get safe factory address
    pub fn safe_factory(&self) -> &'static str {
        // Safe proxy factory (same on all chains)
        "0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67"
    }
}

impl std::str::FromStr for ERC4337Chain {
    type Err = HawalaError;
    
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "ethereum" | "eth" | "1" => Ok(Self::Ethereum),
            "polygon" | "matic" | "137" => Ok(Self::Polygon),
            "arbitrum" | "arb" | "42161" => Ok(Self::Arbitrum),
            "optimism" | "op" | "10" => Ok(Self::Optimism),
            "base" | "8453" => Ok(Self::Base),
            "avalanche" | "avax" | "43114" => Ok(Self::Avalanche),
            "bnb" | "bsc" | "56" => Ok(Self::BNB),
            "sepolia" | "11155111" => Ok(Self::Sepolia),
            "mumbai" | "80001" => Ok(Self::Mumbai),
            _ => Err(HawalaError::new(
                ErrorCode::InvalidInput,
                format!("Unknown ERC-4337 chain: {}", s),
            )),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_chain_entry_point() {
        assert_eq!(
            ERC4337Chain::Ethereum.entry_point(),
            "0x0000000071727De22E5E9d8BAf0edAc6f37da032"
        );
        assert_eq!(
            ERC4337Chain::Polygon.entry_point(),
            ERC4337Chain::Ethereum.entry_point()
        );
    }

    #[test]
    fn test_chain_from_str() {
        assert_eq!(
            "ethereum".parse::<ERC4337Chain>().unwrap(),
            ERC4337Chain::Ethereum
        );
        assert_eq!(
            "137".parse::<ERC4337Chain>().unwrap(),
            ERC4337Chain::Polygon
        );
        assert!("unknown".parse::<ERC4337Chain>().is_err());
    }
    
    #[test]
    fn test_all_chain_ids() {
        assert_eq!(ERC4337Chain::Ethereum.chain_id(), 1);
        assert_eq!(ERC4337Chain::Polygon.chain_id(), 137);
        assert_eq!(ERC4337Chain::Arbitrum.chain_id(), 42161);
        assert_eq!(ERC4337Chain::Optimism.chain_id(), 10);
        assert_eq!(ERC4337Chain::Base.chain_id(), 8453);
        assert_eq!(ERC4337Chain::Avalanche.chain_id(), 43114);
        assert_eq!(ERC4337Chain::BNB.chain_id(), 56);
        assert_eq!(ERC4337Chain::Sepolia.chain_id(), 11155111);
        assert_eq!(ERC4337Chain::Mumbai.chain_id(), 80001);
    }
    
    #[test]
    fn test_all_bundler_urls() {
        // Ensure all chains have valid bundler URLs
        for chain in [
            ERC4337Chain::Ethereum,
            ERC4337Chain::Polygon,
            ERC4337Chain::Arbitrum,
            ERC4337Chain::Optimism,
            ERC4337Chain::Base,
        ] {
            let url = chain.default_bundler_url();
            assert!(url.starts_with("https://"), "Chain {:?} URL should be HTTPS", chain);
            assert!(url.contains("pimlico"), "Chain {:?} should use Pimlico bundler", chain);
        }
    }
    
    #[test]
    fn test_entry_point_v06() {
        assert_eq!(
            ERC4337Chain::Ethereum.entry_point_v06(),
            "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789"
        );
    }
    
    #[test]
    fn test_chain_parse_aliases() {
        // Test all parsing aliases work
        assert_eq!("eth".parse::<ERC4337Chain>().unwrap(), ERC4337Chain::Ethereum);
        assert_eq!("matic".parse::<ERC4337Chain>().unwrap(), ERC4337Chain::Polygon);
        assert_eq!("arb".parse::<ERC4337Chain>().unwrap(), ERC4337Chain::Arbitrum);
        assert_eq!("op".parse::<ERC4337Chain>().unwrap(), ERC4337Chain::Optimism);
        assert_eq!("avax".parse::<ERC4337Chain>().unwrap(), ERC4337Chain::Avalanche);
        assert_eq!("bsc".parse::<ERC4337Chain>().unwrap(), ERC4337Chain::BNB);
    }
    
    #[test]
    fn test_chain_serde() {
        let chain = ERC4337Chain::Ethereum;
        let json = serde_json::to_string(&chain).unwrap();
        assert_eq!(json, "\"ethereum\"");
        
        let parsed: ERC4337Chain = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed, chain);
    }
}
