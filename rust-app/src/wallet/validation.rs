//! Address and Mnemonic Validation
//!
//! Validates addresses for all supported chains and mnemonic phrases.

use bip39::Mnemonic;
use bitcoin::Address;
use std::str::FromStr;
use tiny_keccak::{Hasher, Keccak};

use crate::types::Chain;

/// Check if a mnemonic phrase is valid
pub fn is_valid_mnemonic(phrase: &str) -> bool {
    Mnemonic::parse(phrase).is_ok()
}

/// Validate an address for a specific chain
/// Returns (is_valid, normalized_address)
pub fn validate_chain_address(address: &str, chain: Chain) -> (bool, Option<String>) {
    match chain {
        Chain::Bitcoin => validate_bitcoin_address(address, false),
        Chain::BitcoinTestnet => validate_bitcoin_address(address, true),
        Chain::Litecoin => validate_litecoin_address(address),
        Chain::Ethereum
        | Chain::EthereumSepolia
        | Chain::Bnb
        | Chain::Polygon
        | Chain::Arbitrum
        | Chain::Optimism
        | Chain::Base
        | Chain::Avalanche => validate_ethereum_address(address),
        Chain::Solana | Chain::SolanaDevnet => validate_solana_address(address),
        Chain::Xrp | Chain::XrpTestnet => validate_xrp_address(address),
        Chain::Monero => validate_monero_address(address),
    }
}

fn validate_bitcoin_address(address: &str, testnet: bool) -> (bool, Option<String>) {
    let trimmed = address.trim();
    
    // Check based on address format directly
    // bc1 = mainnet bech32, tb1 = testnet bech32
    // 1/3 = mainnet legacy/p2sh, m/n/2 = testnet legacy/p2sh
    let is_mainnet = trimmed.starts_with("bc1") || trimmed.starts_with("1") || trimmed.starts_with("3");
    let is_testnet_addr = trimmed.starts_with("tb1") || trimmed.starts_with("m") || trimmed.starts_with("n") || trimmed.starts_with("2");
    
    // Try parsing as Bitcoin address to validate format
    match Address::from_str(trimmed) {
        Ok(_addr) => {
            if testnet && is_testnet_addr {
                (true, Some(trimmed.to_string()))
            } else if !testnet && is_mainnet {
                (true, Some(trimmed.to_string()))
            } else {
                (false, None)
            }
        }
        Err(_) => (false, None),
    }
}

fn validate_litecoin_address(address: &str) -> (bool, Option<String>) {
    let trimmed = address.trim();
    
    // Litecoin addresses: L/M (P2PKH), ltc1 (Bech32), 3 (P2SH)
    if trimmed.starts_with("ltc1") {
        // Bech32 - validate format
        if trimmed.len() >= 42 && trimmed.len() <= 62 {
            // Basic Bech32 validation
            if trimmed.chars().skip(4).all(|c| {
                "qpzry9x8gf2tvdw0s3jn54khce6mua7l".contains(c.to_ascii_lowercase())
            }) {
                return (true, Some(trimmed.to_lowercase()));
            }
        }
    } else if trimmed.starts_with('L') || trimmed.starts_with('M') {
        // P2PKH legacy
        if trimmed.len() >= 26 && trimmed.len() <= 35 {
            if let Ok(_) = bs58::decode(trimmed).into_vec() {
                return (true, Some(trimmed.to_string()));
            }
        }
    } else if trimmed.starts_with('3') {
        // P2SH (compatible with Bitcoin)
        if trimmed.len() >= 26 && trimmed.len() <= 35 {
            if let Ok(_) = bs58::decode(trimmed).into_vec() {
                return (true, Some(trimmed.to_string()));
            }
        }
    }
    
    (false, None)
}

fn validate_ethereum_address(address: &str) -> (bool, Option<String>) {
    let trimmed = address.trim();
    
    if !trimmed.starts_with("0x") || trimmed.len() != 42 {
        return (false, None);
    }

    let hex_part = &trimmed[2..];
    if !hex_part.chars().all(|c| c.is_ascii_hexdigit()) {
        return (false, None);
    }

    // Decode and create checksummed version
    let lower = hex_part.to_lowercase();
    let bytes = match hex::decode(&lower) {
        Ok(b) if b.len() == 20 => b,
        _ => return (false, None),
    };

    let checksummed = to_checksum_address(&bytes);
    (true, Some(checksummed))
}

fn validate_solana_address(address: &str) -> (bool, Option<String>) {
    let trimmed = address.trim();
    
    // Solana addresses are base58-encoded 32-byte public keys
    match bs58::decode(trimmed).into_vec() {
        Ok(bytes) if bytes.len() == 32 => (true, Some(trimmed.to_string())),
        _ => (false, None),
    }
}

fn validate_xrp_address(address: &str) -> (bool, Option<String>) {
    let trimmed = address.trim();
    
    // XRP classic addresses start with 'r'
    if !trimmed.starts_with('r') || trimmed.len() < 25 || trimmed.len() > 35 {
        return (false, None);
    }

    // Decode with Ripple alphabet
    match bs58::decode(trimmed)
        .with_alphabet(bs58::Alphabet::RIPPLE)
        .into_vec()
    {
        Ok(bytes) if bytes.len() >= 21 => (true, Some(trimmed.to_string())),
        _ => (false, None),
    }
}

fn validate_monero_address(address: &str) -> (bool, Option<String>) {
    let trimmed = address.trim();
    
    // Monero mainnet addresses start with '4' and are 95 characters
    // Subaddresses start with '8'
    if (trimmed.starts_with('4') || trimmed.starts_with('8')) && trimmed.len() == 95 {
        // Basic validation - could use monero crate for full validation
        return (true, Some(trimmed.to_string()));
    }
    
    // Integrated addresses are 106 characters
    if trimmed.starts_with('4') && trimmed.len() == 106 {
        return (true, Some(trimmed.to_string()));
    }
    
    (false, None)
}

fn to_checksum_address(address: &[u8]) -> String {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_valid_mnemonic() {
        assert!(is_valid_mnemonic("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"));
        assert!(!is_valid_mnemonic("invalid mnemonic phrase"));
        assert!(!is_valid_mnemonic(""));
    }

    #[test]
    fn test_ethereum_address_validation() {
        let (valid, normalized) = validate_ethereum_address("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045");
        assert!(valid);
        assert!(normalized.is_some());
        
        let (valid, _) = validate_ethereum_address("invalid");
        assert!(!valid);
    }

    #[test]
    fn test_bitcoin_address_validation() {
        // Mainnet bech32
        let (valid, _) = validate_bitcoin_address("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq", false);
        assert!(valid);
        
        // Testnet
        let (valid, _) = validate_bitcoin_address("tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx", true);
        assert!(valid);
    }
}
