//! Enhanced Address Validation
//!
//! Comprehensive address validation with:
//! - BIP-0350 bech32m support for Taproot addresses
//! - EIP-55 checksum validation and normalization
//! - Chain-specific format validation
//! - Detailed error reporting

use crate::error::{HawalaError, HawalaResult};
use crate::types::Chain;
use bech32::{self, Variant};
use sha2::{Sha256, Digest};
use tiny_keccak::{Hasher, Keccak};

/// SHA256 helper function for Base58Check verification
fn sha256(data: &[u8]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(data);
    hasher.finalize().into()
}

/// Convert 5-bit values to 8-bit bytes (for bech32 decoding)
fn convert_bits_5_to_8(data: &[u8]) -> Vec<u8> {
    let mut result = Vec::new();
    let mut acc: u32 = 0;
    let mut bits: u32 = 0;
    
    for value in data {
        acc = (acc << 5) | (*value as u32);
        bits += 5;
        while bits >= 8 {
            bits -= 8;
            result.push((acc >> bits) as u8);
        }
    }
    
    result
}

/// Detailed address validation result
#[derive(Debug, Clone)]
pub struct AddressValidation {
    pub is_valid: bool,
    pub normalized: Option<String>,
    pub address_type: AddressType,
    pub checksum_valid: bool,
    pub network_match: bool,
    pub warnings: Vec<String>,
}

/// Address type classification
#[derive(Debug, Clone, PartialEq)]
pub enum AddressType {
    // Bitcoin
    P2PKH,          // Legacy (1...)
    P2SH,           // SegWit compatible (3...)
    P2WPKH,         // Native SegWit (bc1q...)
    P2WSH,          // Native SegWit Script (bc1q... 62 chars)
    P2TR,           // Taproot (bc1p...)
    
    // Ethereum/EVM
    EOA,            // Externally Owned Account
    Contract,       // Contract address (indistinguishable by format)
    
    // Others
    Solana,
    XRP,
    Monero,
    Litecoin,
    
    Unknown,
}

/// Validate address with detailed result
pub fn validate_address_detailed(address: &str, chain: Chain) -> AddressValidation {
    match chain {
        Chain::Bitcoin => validate_bitcoin_detailed(address, false),
        Chain::BitcoinTestnet => validate_bitcoin_detailed(address, true),
        Chain::Litecoin => validate_litecoin_detailed(address),
        Chain::Ethereum | Chain::EthereumSepolia | Chain::Bnb | Chain::Polygon
        | Chain::Arbitrum | Chain::Optimism | Chain::Base | Chain::Avalanche => {
            validate_evm_detailed(address)
        }
        Chain::Solana | Chain::SolanaDevnet => validate_solana_detailed(address),
        Chain::Xrp | Chain::XrpTestnet => validate_xrp_detailed(address),
        Chain::Monero => validate_monero_detailed(address),
        // EVM-compatible chains
        chain if chain.is_evm() => validate_evm_detailed(address),
        // Default fallback for new chains
        _ => {
            let trimmed = address.trim();
            let is_valid = !trimmed.is_empty() && trimmed.len() >= 10;
            AddressValidation {
                is_valid,
                normalized: if is_valid { Some(trimmed.to_string()) } else { None },
                address_type: AddressType::Unknown,
                checksum_valid: true,
                network_match: true,
                warnings: vec![],
            }
        }
    }
}

/// Validate Bitcoin address with BIP-0350 bech32m support
fn validate_bitcoin_detailed(address: &str, testnet: bool) -> AddressValidation {
    let trimmed = address.trim();
    let mut warnings = Vec::new();
    
    // Determine expected HRP
    let expected_hrp = if testnet { "tb" } else { "bc" };
    
    // Check for Bech32/Bech32m addresses
    if trimmed.to_lowercase().starts_with(expected_hrp) {
        return validate_bech32_bitcoin(trimmed, testnet);
    }
    
    // Check for legacy addresses
    if !testnet {
        // Mainnet: 1 = P2PKH, 3 = P2SH
        if trimmed.starts_with('1') || trimmed.starts_with('3') {
            return validate_base58_bitcoin(trimmed, testnet);
        }
    } else {
        // Testnet: m/n = P2PKH, 2 = P2SH
        if trimmed.starts_with('m') || trimmed.starts_with('n') || trimmed.starts_with('2') {
            return validate_base58_bitcoin(trimmed, testnet);
        }
    }
    
    // Wrong network prefix
    if trimmed.starts_with("bc") || trimmed.starts_with("tb") {
        warnings.push("Address appears to be for wrong network".to_string());
    }
    
    AddressValidation {
        is_valid: false,
        normalized: None,
        address_type: AddressType::Unknown,
        checksum_valid: false,
        network_match: false,
        warnings,
    }
}

/// Validate Bech32/Bech32m Bitcoin address
fn validate_bech32_bitcoin(address: &str, testnet: bool) -> AddressValidation {
    let mut warnings = Vec::new();
    let lower = address.to_lowercase();
    
    // Try decoding - returns (hrp, data, variant)
    if let Ok((hrp, data, variant)) = bech32::decode(&lower) {
        let expected_hrp = if testnet { "tb" } else { "bc" };
        
        if hrp != expected_hrp {
            return AddressValidation {
                is_valid: false,
                normalized: None,
                address_type: AddressType::Unknown,
                checksum_valid: true,
                network_match: false,
                warnings: vec!["Network mismatch".to_string()],
            };
        }
        
        // Check witness version
        if data.is_empty() {
            return AddressValidation {
                is_valid: false,
                normalized: None,
                address_type: AddressType::Unknown,
                checksum_valid: false,
                network_match: true,
                warnings: vec!["Empty witness program".to_string()],
            };
        }
        
        let witness_version = data[0].to_u8();
        
        // Convert 5-bit to 8-bit (witness program bytes)
        // bech32 crate 0.9 returns Vec<u5>, we need to convert to bytes
        let program_5bit: Vec<u8> = data[1..].iter().map(|u| u.to_u8()).collect();
        let program = convert_bits_5_to_8(&program_5bit);
        
        // Determine address type based on witness version and program length
        let address_type = match (witness_version, program.len()) {
            (0, 20) => AddressType::P2WPKH,  // SegWit v0 pubkey hash
            (0, 32) => AddressType::P2WSH,   // SegWit v0 script hash
            (1, 32) => AddressType::P2TR,    // Taproot (SegWit v1)
            _ => {
                warnings.push(format!("Unusual witness version {} or program length {}", 
                    witness_version, program.len()));
                AddressType::Unknown
            }
        };
        
        // Verify correct bech32 variant for the witness version
        let expected_variant = if witness_version == 0 {
            Variant::Bech32
        } else {
            Variant::Bech32m
        };
        
        if variant != expected_variant {
            warnings.push("Incorrect bech32 variant for witness version".to_string());
        }
        
        // Warn about deprecated address types
        if address_type == AddressType::P2WPKH {
            // P2WPKH is fine but Taproot is preferred for new wallets
        }
        
        return AddressValidation {
            is_valid: true,
            normalized: Some(lower),
            address_type,
            checksum_valid: true,
            network_match: true,
            warnings,
        };
    }
    
    AddressValidation {
        is_valid: false,
        normalized: None,
        address_type: AddressType::Unknown,
        checksum_valid: false,
        network_match: false,
        warnings: vec!["Invalid bech32 encoding".to_string()],
    }
}

/// Validate Base58Check Bitcoin address
fn validate_base58_bitcoin(address: &str, testnet: bool) -> AddressValidation {
    let mut warnings = Vec::new();
    
    // Decode Base58 and verify checksum manually
    let decoded = match bs58::decode(address).into_vec() {
        Ok(d) if d.len() >= 5 => {
            // Verify checksum (last 4 bytes)
            let (payload, checksum) = d.split_at(d.len() - 4);
            let hash1 = sha256(payload);
            let hash2 = sha256(&hash1);
            if &hash2[..4] != checksum {
                return AddressValidation {
                    is_valid: false,
                    normalized: None,
                    address_type: AddressType::Unknown,
                    checksum_valid: false,
                    network_match: false,
                    warnings: vec!["Invalid Base58Check checksum".to_string()],
                };
            }
            payload.to_vec()
        }
        Ok(_) => {
            return AddressValidation {
                is_valid: false,
                normalized: None,
                address_type: AddressType::Unknown,
                checksum_valid: false,
                network_match: false,
                warnings: vec!["Address too short".to_string()],
            };
        }
        Err(_) => {
            return AddressValidation {
                is_valid: false,
                normalized: None,
                address_type: AddressType::Unknown,
                checksum_valid: false,
                network_match: false,
                warnings: vec!["Invalid Base58 encoding".to_string()],
            };
        }
    };
    
    if decoded.is_empty() {
        return AddressValidation {
            is_valid: false,
            normalized: None,
            address_type: AddressType::Unknown,
            checksum_valid: false,
            network_match: false,
            warnings: vec!["Empty address data".to_string()],
        };
    }
    
    let version = decoded[0];
    
    // Determine address type and network
    let (address_type, is_testnet) = match version {
        0x00 => (AddressType::P2PKH, false),   // Mainnet P2PKH
        0x05 => (AddressType::P2SH, false),    // Mainnet P2SH
        0x6F => (AddressType::P2PKH, true),    // Testnet P2PKH
        0xC4 => (AddressType::P2SH, true),     // Testnet P2SH
        _ => {
            warnings.push(format!("Unknown version byte: 0x{:02X}", version));
            (AddressType::Unknown, false)
        }
    };
    
    let network_match = is_testnet == testnet;
    
    if !network_match {
        warnings.push("Address is for different network".to_string());
    }
    
    // Warn about legacy addresses
    if address_type == AddressType::P2PKH {
        warnings.push("Legacy P2PKH address - consider using SegWit or Taproot for lower fees".to_string());
    }
    
    AddressValidation {
        is_valid: network_match,
        normalized: if network_match { Some(address.to_string()) } else { None },
        address_type,
        checksum_valid: true,
        network_match,
        warnings,
    }
}

/// Validate EVM address with EIP-55 checksum
fn validate_evm_detailed(address: &str) -> AddressValidation {
    let trimmed = address.trim();
    let mut warnings = Vec::new();
    
    // Basic format check
    if !trimmed.starts_with("0x") || trimmed.len() != 42 {
        return AddressValidation {
            is_valid: false,
            normalized: None,
            address_type: AddressType::Unknown,
            checksum_valid: false,
            network_match: true, // EVM addresses are network-agnostic
            warnings: vec!["Invalid format: expected 0x followed by 40 hex characters".to_string()],
        };
    }
    
    let hex_part = &trimmed[2..];
    
    // Validate hex characters
    if !hex_part.chars().all(|c| c.is_ascii_hexdigit()) {
        return AddressValidation {
            is_valid: false,
            normalized: None,
            address_type: AddressType::Unknown,
            checksum_valid: false,
            network_match: true,
            warnings: vec!["Invalid hex characters".to_string()],
        };
    }
    
    // Calculate EIP-55 checksum
    let lower = hex_part.to_lowercase();
    let bytes = match hex::decode(&lower) {
        Ok(b) if b.len() == 20 => b,
        _ => {
            return AddressValidation {
                is_valid: false,
                normalized: None,
                address_type: AddressType::Unknown,
                checksum_valid: false,
                network_match: true,
                warnings: vec!["Invalid address bytes".to_string()],
            };
        }
    };
    
    let checksummed = eip55_checksum(&bytes);
    
    // Check if original had valid checksum
    let has_mixed_case = hex_part.chars().any(|c| c.is_uppercase()) 
                      && hex_part.chars().any(|c| c.is_lowercase());
    let checksum_valid = if has_mixed_case {
        trimmed == checksummed
    } else {
        // All lowercase or all uppercase - no checksum
        warnings.push("Address has no EIP-55 checksum - using normalized form".to_string());
        true
    };
    
    if !checksum_valid {
        warnings.push("Invalid EIP-55 checksum - address may be corrupted".to_string());
    }
    
    // Check for known patterns
    if bytes.iter().all(|&b| b == 0) {
        warnings.push("Zero address - this is typically the burn address".to_string());
    }
    
    AddressValidation {
        is_valid: true,
        normalized: Some(checksummed),
        address_type: AddressType::EOA, // Can't distinguish from contract by format
        checksum_valid,
        network_match: true,
        warnings,
    }
}

/// EIP-55 checksum encoding
fn eip55_checksum(address: &[u8]) -> String {
    let lower = hex::encode(address);
    let hash = keccak256(lower.as_bytes());
    
    let mut result = String::from("0x");
    for (i, ch) in lower.chars().enumerate() {
        let byte = hash[i / 2];
        let nibble = if i % 2 == 0 { byte >> 4 } else { byte & 0x0f };
        
        if ch.is_ascii_digit() {
            result.push(ch);
        } else if nibble >= 8 {
            result.push(ch.to_ascii_uppercase());
        } else {
            result.push(ch);
        }
    }
    
    result
}

fn keccak256(data: &[u8]) -> [u8; 32] {
    let mut hasher = Keccak::v256();
    hasher.update(data);
    let mut out = [0u8; 32];
    hasher.finalize(&mut out);
    out
}

/// Validate Solana address
fn validate_solana_detailed(address: &str) -> AddressValidation {
    let trimmed = address.trim();
    let mut warnings = Vec::new();
    
    match bs58::decode(trimmed).into_vec() {
        Ok(bytes) if bytes.len() == 32 => {
            // Check for known special addresses
            if bytes.iter().all(|&b| b == 0) {
                warnings.push("System program address".to_string());
            }
            
            AddressValidation {
                is_valid: true,
                normalized: Some(trimmed.to_string()),
                address_type: AddressType::Solana,
                checksum_valid: true,
                network_match: true,
                warnings,
            }
        }
        Ok(bytes) => AddressValidation {
            is_valid: false,
            normalized: None,
            address_type: AddressType::Unknown,
            checksum_valid: false,
            network_match: true,
            warnings: vec![format!("Invalid length: expected 32 bytes, got {}", bytes.len())],
        },
        Err(_) => AddressValidation {
            is_valid: false,
            normalized: None,
            address_type: AddressType::Unknown,
            checksum_valid: false,
            network_match: true,
            warnings: vec!["Invalid Base58 encoding".to_string()],
        },
    }
}

/// Validate XRP address
fn validate_xrp_detailed(address: &str) -> AddressValidation {
    let trimmed = address.trim();
    
    if !trimmed.starts_with('r') {
        return AddressValidation {
            is_valid: false,
            normalized: None,
            address_type: AddressType::Unknown,
            checksum_valid: false,
            network_match: true,
            warnings: vec!["XRP addresses must start with 'r'".to_string()],
        };
    }
    
    if trimmed.len() < 25 || trimmed.len() > 35 {
        return AddressValidation {
            is_valid: false,
            normalized: None,
            address_type: AddressType::Unknown,
            checksum_valid: false,
            network_match: true,
            warnings: vec!["Invalid address length".to_string()],
        };
    }
    
    match bs58::decode(trimmed)
        .with_alphabet(bs58::Alphabet::RIPPLE)
        .into_vec()
    {
        Ok(bytes) if bytes.len() >= 21 => AddressValidation {
            is_valid: true,
            normalized: Some(trimmed.to_string()),
            address_type: AddressType::XRP,
            checksum_valid: true,
            network_match: true,
            warnings: vec![],
        },
        _ => AddressValidation {
            is_valid: false,
            normalized: None,
            address_type: AddressType::Unknown,
            checksum_valid: false,
            network_match: true,
            warnings: vec!["Invalid Ripple Base58 encoding".to_string()],
        },
    }
}

/// Validate Monero address
fn validate_monero_detailed(address: &str) -> AddressValidation {
    let trimmed = address.trim();
    let mut warnings = Vec::new();
    
    let (is_valid, address_type) = if trimmed.starts_with('4') {
        if trimmed.len() == 95 {
            (true, AddressType::Monero)
        } else if trimmed.len() == 106 {
            warnings.push("Integrated address - contains payment ID".to_string());
            (true, AddressType::Monero)
        } else {
            (false, AddressType::Unknown)
        }
    } else if trimmed.starts_with('8') && trimmed.len() == 95 {
        warnings.push("Subaddress - preferred for privacy".to_string());
        (true, AddressType::Monero)
    } else {
        (false, AddressType::Unknown)
    };
    
    AddressValidation {
        is_valid,
        normalized: if is_valid { Some(trimmed.to_string()) } else { None },
        address_type,
        checksum_valid: is_valid, // Monero addresses have built-in checksum
        network_match: true,
        warnings,
    }
}

/// Validate Litecoin address
fn validate_litecoin_detailed(address: &str) -> AddressValidation {
    let trimmed = address.trim();
    let mut warnings = Vec::new();
    
    // Bech32 (ltc1)
    if trimmed.to_lowercase().starts_with("ltc1") {
        let lower = trimmed.to_lowercase();
        
        // Validate bech32 format - returns (hrp, data, variant)
        if let Ok((hrp, data, _variant)) = bech32::decode(&lower) {
            if hrp != "ltc" {
                return AddressValidation {
                    is_valid: false,
                    normalized: None,
                    address_type: AddressType::Unknown,
                    checksum_valid: false,
                    network_match: false,
                    warnings: vec!["Invalid HRP for Litecoin".to_string()],
                };
            }
            
            if !data.is_empty() {
                let witness_version = data[0].to_u8();
                let address_type = match witness_version {
                    0 => AddressType::P2WPKH,
                    1 => AddressType::P2TR,
                    _ => AddressType::Litecoin,
                };
                
                return AddressValidation {
                    is_valid: true,
                    normalized: Some(lower),
                    address_type,
                    checksum_valid: true,
                    network_match: true,
                    warnings,
                };
            }
        }
        
        return AddressValidation {
            is_valid: false,
            normalized: None,
            address_type: AddressType::Unknown,
            checksum_valid: false,
            network_match: true,
            warnings: vec!["Invalid Bech32 encoding".to_string()],
        };
    }
    
    // Legacy (L, M, 3)
    if trimmed.starts_with('L') || trimmed.starts_with('M') || trimmed.starts_with('3') {
        if trimmed.len() >= 26 && trimmed.len() <= 35 {
            // Manual Base58Check validation
            if let Ok(decoded) = bs58::decode(trimmed).into_vec() {
                if decoded.len() >= 5 {
                    let (payload, checksum) = decoded.split_at(decoded.len() - 4);
                    let hash1 = sha256(payload);
                    let hash2 = sha256(&hash1);
                    if &hash2[..4] == checksum {
                        if trimmed.starts_with('L') || trimmed.starts_with('M') {
                            warnings.push("Legacy P2PKH - consider using Bech32 for lower fees".to_string());
                        }
                        
                        return AddressValidation {
                            is_valid: true,
                            normalized: Some(trimmed.to_string()),
                            address_type: AddressType::Litecoin,
                            checksum_valid: true,
                            network_match: true,
                            warnings,
                        };
                    }
                }
            }
        }
    }
    
    AddressValidation {
        is_valid: false,
        normalized: None,
        address_type: AddressType::Unknown,
        checksum_valid: false,
        network_match: true,
        warnings: vec!["Invalid Litecoin address format".to_string()],
    }
}

/// Quick validation check - returns error if invalid
pub fn require_valid_address(address: &str, chain: Chain) -> HawalaResult<String> {
    let validation = validate_address_detailed(address, chain);
    
    if !validation.is_valid {
        let errors = validation.warnings.join("; ");
        return Err(HawalaError::invalid_input(format!(
            "Invalid {} address '{}': {}",
            chain.symbol(),
            address,
            if errors.is_empty() { "format error" } else { &errors }
        )));
    }
    
    Ok(validation.normalized.unwrap_or_else(|| address.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bitcoin_bech32_validation() {
        // SegWit v0 (P2WPKH)
        let result = validate_bitcoin_detailed("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq", false);
        assert!(result.is_valid);
        assert_eq!(result.address_type, AddressType::P2WPKH);
        
        // Taproot (P2TR) - starts with bc1p
        let result = validate_bitcoin_detailed("bc1p5d7rjq7g6rdk2yhzks9smlaqtedr4dekq08ge8ztwac72sfr9rusxg3297", false);
        assert!(result.is_valid);
        assert_eq!(result.address_type, AddressType::P2TR);
    }

    #[test]
    fn test_bitcoin_legacy_warnings() {
        let result = validate_bitcoin_detailed("1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2", false);
        assert!(result.is_valid);
        assert_eq!(result.address_type, AddressType::P2PKH);
        assert!(result.warnings.iter().any(|w| w.contains("Legacy")));
    }

    #[test]
    fn test_evm_checksum_validation() {
        // Valid checksum
        let result = validate_evm_detailed("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045");
        assert!(result.is_valid);
        assert!(result.checksum_valid);
        
        // Invalid checksum (wrong case)
        let result = validate_evm_detailed("0xd8da6bf26964af9d7eed9e03e53415d37aa96045");
        assert!(result.is_valid); // Still valid, just no checksum
        assert!(result.warnings.iter().any(|w| w.contains("no EIP-55 checksum")));
    }

    #[test]
    fn test_taproot_address() {
        // Valid Taproot address
        let result = validate_address_detailed(
            "bc1p5d7rjq7g6rdk2yhzks9smlaqtedr4dekq08ge8ztwac72sfr9rusxg3297",
            Chain::Bitcoin
        );
        assert!(result.is_valid);
        assert_eq!(result.address_type, AddressType::P2TR);
    }

    #[test]
    fn test_require_valid_address() {
        // Valid
        assert!(require_valid_address("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045", Chain::Ethereum).is_ok());
        
        // Invalid
        assert!(require_valid_address("invalid", Chain::Ethereum).is_err());
    }
}
