//! Key Derivation Path Validation
//!
//! Validates BIP-32/44/49/84/86 derivation paths for:
//! - Correct format and syntax
//! - Chain-appropriate paths
//! - Security warnings for unusual paths

use crate::error::{HawalaError, HawalaResult};
use crate::types::Chain;

/// Standard BIP purposes
pub mod bip_purposes {
    pub const BIP44: u32 = 44;  // Legacy (P2PKH)
    pub const BIP49: u32 = 49;  // SegWit compatible (P2SH-P2WPKH)
    pub const BIP84: u32 = 84;  // Native SegWit (P2WPKH)
    pub const BIP86: u32 = 86;  // Taproot (P2TR)
}

/// Coin types from SLIP-0044
pub mod coin_types {
    pub const BITCOIN: u32 = 0;
    pub const BITCOIN_TESTNET: u32 = 1;
    pub const LITECOIN: u32 = 2;
    pub const ETHEREUM: u32 = 60;
    pub const SOLANA: u32 = 501;
    pub const XRP: u32 = 144;
    pub const MONERO: u32 = 128;
}

/// Hardened offset for BIP-32 derivation
pub const HARDENED: u32 = 0x80000000;

/// Parsed derivation path
#[derive(Debug, Clone)]
pub struct DerivationPath {
    pub components: Vec<DerivationComponent>,
    pub purpose: Option<u32>,
    pub coin_type: Option<u32>,
    pub account: Option<u32>,
    pub change: Option<u32>,
    pub address_index: Option<u32>,
}

/// Single component of a derivation path
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct DerivationComponent {
    pub index: u32,
    pub hardened: bool,
}

impl DerivationComponent {
    pub fn new(index: u32, hardened: bool) -> Self {
        Self { index, hardened }
    }
    
    /// Get the full index including hardened bit
    pub fn full_index(&self) -> u32 {
        if self.hardened {
            self.index | HARDENED
        } else {
            self.index
        }
    }
}

impl std::fmt::Display for DerivationComponent {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        if self.hardened {
            write!(f, "{}'", self.index)
        } else {
            write!(f, "{}", self.index)
        }
    }
}

impl std::fmt::Display for DerivationPath {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "m")?;
        for component in &self.components {
            write!(f, "/{}", component)?;
        }
        Ok(())
    }
}

/// Derivation path validation result
#[derive(Debug, Clone)]
pub struct PathValidation {
    pub is_valid: bool,
    pub path: Option<DerivationPath>,
    pub normalized: Option<String>,
    pub warnings: Vec<String>,
    pub errors: Vec<String>,
}

/// Parse and validate a derivation path string
pub fn validate_derivation_path(path: &str, chain: Chain) -> PathValidation {
    let mut warnings = Vec::new();
    let mut errors = Vec::new();
    
    // Parse the path
    let parsed = match parse_path(path) {
        Ok(p) => p,
        Err(e) => {
            return PathValidation {
                is_valid: false,
                path: None,
                normalized: None,
                warnings: vec![],
                errors: vec![e],
            };
        }
    };
    
    // Validate purpose (first component after m/)
    if let Some(purpose) = parsed.purpose {
        match purpose {
            bip_purposes::BIP44 => {
                // Legacy - warn about better options
                if matches!(chain, Chain::Bitcoin | Chain::BitcoinTestnet) {
                    warnings.push("BIP44 creates legacy addresses - consider BIP84 (SegWit) or BIP86 (Taproot) for lower fees".to_string());
                }
            }
            bip_purposes::BIP49 => {
                // SegWit compatible
                if !matches!(chain, Chain::Bitcoin | Chain::BitcoinTestnet | Chain::Litecoin) {
                    warnings.push(format!("BIP49 is not standard for {}", chain.symbol()));
                }
            }
            bip_purposes::BIP84 => {
                // Native SegWit
                if !matches!(chain, Chain::Bitcoin | Chain::BitcoinTestnet | Chain::Litecoin) {
                    warnings.push(format!("BIP84 is not standard for {}", chain.symbol()));
                }
            }
            bip_purposes::BIP86 => {
                // Taproot
                if !matches!(chain, Chain::Bitcoin | Chain::BitcoinTestnet) {
                    warnings.push(format!("BIP86 (Taproot) is not standard for {}", chain.symbol()));
                }
            }
            _ => {
                warnings.push(format!("Non-standard purpose: {}. Standard purposes are 44, 49, 84, 86", purpose));
            }
        }
    }
    
    // Validate coin type
    if let Some(coin_type) = parsed.coin_type {
        let expected_coin_type = get_expected_coin_type(chain);
        if coin_type != expected_coin_type {
            if coin_type == coin_types::BITCOIN_TESTNET && !is_testnet(chain) {
                errors.push("Using testnet coin type on mainnet - funds may be lost!".to_string());
            } else if coin_type != coin_types::BITCOIN_TESTNET && is_testnet(chain) {
                warnings.push("Using mainnet coin type on testnet".to_string());
            } else {
                warnings.push(format!(
                    "Coin type {} is not standard for {} (expected {})",
                    coin_type, chain.symbol(), expected_coin_type
                ));
            }
        }
    }
    
    // Validate account number
    if let Some(account) = parsed.account {
        if account > 100 {
            warnings.push(format!("Unusual account number: {}. Most wallets use 0", account));
        }
    }
    
    // Validate change indicator
    if let Some(change) = parsed.change {
        if change > 1 {
            warnings.push(format!("Non-standard change value: {}. Should be 0 (external) or 1 (internal/change)", change));
        }
    }
    
    // Validate address index
    if let Some(index) = parsed.address_index {
        if index > 10000 {
            warnings.push(format!("Very high address index: {}. This may indicate a problem", index));
        }
    }
    
    // Check hardening
    let has_unhardened_before_account = parsed.components.len() >= 3 
        && parsed.components.iter().take(3).any(|c| !c.hardened);
    if has_unhardened_before_account {
        warnings.push("Purpose, coin type, and account should be hardened (')".to_string());
    }
    
    let normalized = parsed.to_string();
    
    PathValidation {
        is_valid: errors.is_empty(),
        path: Some(parsed),
        normalized: Some(normalized),
        warnings,
        errors,
    }
}

/// Parse a derivation path string
fn parse_path(path: &str) -> Result<DerivationPath, String> {
    let trimmed = path.trim();
    
    // Must start with m/
    if !trimmed.starts_with("m/") && !trimmed.starts_with("M/") {
        return Err("Derivation path must start with 'm/'".to_string());
    }
    
    let path_part = &trimmed[2..];
    if path_part.is_empty() {
        return Err("Empty derivation path".to_string());
    }
    
    let mut components = Vec::new();
    
    for component_str in path_part.split('/') {
        let component = parse_component(component_str)?;
        components.push(component);
    }
    
    // Extract standard components
    let purpose = components.get(0).map(|c| c.index);
    let coin_type = components.get(1).map(|c| c.index);
    let account = components.get(2).map(|c| c.index);
    let change = components.get(3).map(|c| c.index);
    let address_index = components.get(4).map(|c| c.index);
    
    Ok(DerivationPath {
        components,
        purpose,
        coin_type,
        account,
        change,
        address_index,
    })
}

/// Parse a single path component
fn parse_component(s: &str) -> Result<DerivationComponent, String> {
    let trimmed = s.trim();
    
    if trimmed.is_empty() {
        return Err("Empty path component".to_string());
    }
    
    // Check for hardened indicator
    let (number_str, hardened) = if trimmed.ends_with('\'') || trimmed.ends_with('h') || trimmed.ends_with('H') {
        (&trimmed[..trimmed.len() - 1], true)
    } else {
        (trimmed, false)
    };
    
    let index: u32 = number_str.parse()
        .map_err(|e| format!("Invalid path component '{}': {}", s, e))?;
    
    // Check for overflow (excluding hardened bit)
    if index >= HARDENED {
        return Err(format!("Path component {} exceeds maximum value", index));
    }
    
    Ok(DerivationComponent::new(index, hardened))
}

/// Get expected coin type for a chain
fn get_expected_coin_type(chain: Chain) -> u32 {
    match chain {
        Chain::Bitcoin => coin_types::BITCOIN,
        Chain::BitcoinTestnet => coin_types::BITCOIN_TESTNET,
        Chain::Litecoin => coin_types::LITECOIN,
        Chain::Ethereum | Chain::EthereumSepolia | Chain::Bnb | Chain::Polygon
        | Chain::Arbitrum | Chain::Optimism | Chain::Base | Chain::Avalanche => {
            coin_types::ETHEREUM
        }
        Chain::Solana | Chain::SolanaDevnet => coin_types::SOLANA,
        Chain::Xrp | Chain::XrpTestnet => coin_types::XRP,
        Chain::Monero => coin_types::MONERO,
        // EVM chains use Ethereum coin type
        chain if chain.is_evm() => coin_types::ETHEREUM,
        // Default to a high coin type number
        _ => 9999,
    }
}

/// Check if chain is a testnet
fn is_testnet(chain: Chain) -> bool {
    matches!(chain, 
        Chain::BitcoinTestnet | 
        Chain::EthereumSepolia | 
        Chain::SolanaDevnet | 
        Chain::XrpTestnet
    )
}

/// Get the standard derivation path for a chain
pub fn get_standard_path(chain: Chain, account: u32, change: u32, index: u32) -> String {
    let (purpose, coin_type) = match chain {
        Chain::Bitcoin => (bip_purposes::BIP84, coin_types::BITCOIN),
        Chain::BitcoinTestnet => (bip_purposes::BIP84, coin_types::BITCOIN_TESTNET),
        Chain::Litecoin => (bip_purposes::BIP84, coin_types::LITECOIN),
        Chain::Ethereum | Chain::EthereumSepolia | Chain::Bnb | Chain::Polygon
        | Chain::Arbitrum | Chain::Optimism | Chain::Base | Chain::Avalanche => {
            (bip_purposes::BIP44, coin_types::ETHEREUM)
        }
        Chain::Solana | Chain::SolanaDevnet => (bip_purposes::BIP44, coin_types::SOLANA),
        Chain::Xrp | Chain::XrpTestnet => (bip_purposes::BIP44, coin_types::XRP),
        Chain::Monero => (bip_purposes::BIP44, coin_types::MONERO),
        // EVM chains use Ethereum derivation
        chain if chain.is_evm() => (bip_purposes::BIP44, coin_types::ETHEREUM),
        // Default BIP44 with high coin type
        _ => (bip_purposes::BIP44, 9999),
    };
    
    format!("m/{}'/{}'/{}'/{}'/{}",
        purpose, coin_type, account, change, index)
}

/// Get the Taproot derivation path for Bitcoin
pub fn get_taproot_path(testnet: bool, account: u32, change: u32, index: u32) -> String {
    let coin_type = if testnet { coin_types::BITCOIN_TESTNET } else { coin_types::BITCOIN };
    format!("m/{}'/{}'/{}'/{}'/{}",
        bip_purposes::BIP86, coin_type, account, change, index)
}

/// Require valid derivation path
pub fn require_valid_path(path: &str, chain: Chain) -> HawalaResult<DerivationPath> {
    let validation = validate_derivation_path(path, chain);
    
    if !validation.is_valid {
        let errors = validation.errors.join("; ");
        return Err(HawalaError::invalid_input(format!(
            "Invalid derivation path '{}': {}",
            path, errors
        )));
    }
    
    validation.path.ok_or_else(|| HawalaError::internal("Path validation succeeded but path is None"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_standard_path() {
        let result = validate_derivation_path("m/84'/0'/0'/0/0", Chain::Bitcoin);
        assert!(result.is_valid);
        
        let path = result.path.unwrap();
        assert_eq!(path.purpose, Some(84));
        assert_eq!(path.coin_type, Some(0));
        assert_eq!(path.account, Some(0));
        assert_eq!(path.change, Some(0));
        assert_eq!(path.address_index, Some(0));
    }

    #[test]
    fn test_taproot_path() {
        let result = validate_derivation_path("m/86'/0'/0'/0/0", Chain::Bitcoin);
        assert!(result.is_valid);
        assert_eq!(result.path.unwrap().purpose, Some(86));
    }

    #[test]
    fn test_wrong_coin_type_warning() {
        // Ethereum coin type on Bitcoin
        let result = validate_derivation_path("m/44'/60'/0'/0/0", Chain::Bitcoin);
        assert!(result.is_valid); // Still valid, just warning
        assert!(result.warnings.iter().any(|w| w.contains("not standard")));
    }

    #[test]
    fn test_testnet_coin_type_on_mainnet() {
        let result = validate_derivation_path("m/84'/1'/0'/0/0", Chain::Bitcoin);
        assert!(!result.is_valid); // Error, not just warning
        assert!(result.errors.iter().any(|e| e.contains("testnet")));
    }

    #[test]
    fn test_unhardened_warning() {
        // Purpose not hardened
        let result = validate_derivation_path("m/84/0'/0'/0/0", Chain::Bitcoin);
        assert!(result.is_valid);
        assert!(result.warnings.iter().any(|w| w.contains("hardened")));
    }

    #[test]
    fn test_get_standard_path() {
        assert_eq!(
            get_standard_path(Chain::Bitcoin, 0, 0, 0),
            "m/84'/0'/0'/0'/0"
        );
        
        assert_eq!(
            get_standard_path(Chain::Ethereum, 0, 0, 0),
            "m/44'/60'/0'/0'/0"
        );
    }

    #[test]
    fn test_get_taproot_path() {
        assert_eq!(
            get_taproot_path(false, 0, 0, 0),
            "m/86'/0'/0'/0'/0"
        );
        
        assert_eq!(
            get_taproot_path(true, 0, 0, 0),
            "m/86'/1'/0'/0'/0"
        );
    }

    #[test]
    fn test_invalid_paths() {
        // Missing m/
        let result = validate_derivation_path("84'/0'/0'/0/0", Chain::Bitcoin);
        assert!(!result.is_valid);
        
        // Invalid character
        let result = validate_derivation_path("m/84'/abc/0'/0/0", Chain::Bitcoin);
        assert!(!result.is_valid);
    }

    #[test]
    fn test_path_display() {
        let result = validate_derivation_path("m/84'/0'/0'/0/0", Chain::Bitcoin);
        assert_eq!(result.normalized, Some("m/84'/0'/0'/0/0".to_string()));
    }
}
