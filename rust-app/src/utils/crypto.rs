//! Legacy Crypto Utilities
//!
//! Helper functions for cryptographic operations that are used
//! by both the legacy code and the new modules.

use bitcoin::hashes::{Hash, sha256d};
use bitcoin::secp256k1::SecretKey;
use tiny_keccak::{Hasher, Keccak};

/// Keccak256 hash (used for Ethereum addresses)
pub fn keccak256(data: &[u8]) -> [u8; 32] {
    let mut hasher = Keccak::v256();
    hasher.update(data);
    let mut out = [0u8; 32];
    hasher.finalize(&mut out);
    out
}

/// Convert raw address bytes to checksummed Ethereum address
pub fn to_checksum_address(address: &[u8]) -> String {
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

/// Encode a secret key as Litecoin WIF format
pub fn encode_litecoin_wif(secret_key: &SecretKey) -> String {
    let mut data = Vec::with_capacity(34);
    data.push(0xB0); // Litecoin mainnet prefix
    data.extend_from_slice(&secret_key.secret_bytes());
    data.push(0x01); // Compressed flag

    let checksum = sha256d::Hash::hash(&data);
    let mut payload = data;
    payload.extend_from_slice(&checksum[..4]);

    bs58::encode(payload).into_string()
}

// Monero Base58 constants
const MONERO_BASE58_ALPHABET: &[u8; 58] =
    b"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
const MONERO_BLOCK_ENCODED_LENGTH: [usize; 9] = [0, 2, 3, 5, 7, 8, 9, 10, 11];

/// Encode bytes using Monero's custom Base58 encoding
pub fn monero_base58_encode(data: &[u8]) -> String {
    let mut result = String::new();
    let full_chunks = data.len() / 8;
    let remainder = data.len() % 8;

    for chunk_index in 0..full_chunks {
        let start = chunk_index * 8;
        let end = start + 8;
        result.push_str(&encode_monero_block(&data[start..end]));
    }

    if remainder > 0 {
        let start = full_chunks * 8;
        result.push_str(&encode_monero_block(&data[start..]));
    }

    result
}

fn encode_monero_block(block: &[u8]) -> String {
    let mut value: u64 = 0;
    for (index, byte) in block.iter().enumerate() {
        value |= (*byte as u64) << (8 * index);
    }

    let mut chars = Vec::new();
    while value > 0 {
        let remainder = (value % 58) as usize;
        chars.push(MONERO_BASE58_ALPHABET[remainder] as char);
        value /= 58;
    }

    let target_len = if block.len() < MONERO_BLOCK_ENCODED_LENGTH.len() {
        MONERO_BLOCK_ENCODED_LENGTH[block.len()]
    } else {
        11
    };

    while chars.len() < target_len {
        chars.push('1');
    }

    chars.into_iter().collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_keccak256() {
        let hash = keccak256(b"hello");
        assert_eq!(hash.len(), 32);
    }
    
    #[test]
    fn test_checksum_address() {
        let addr_bytes = hex::decode("5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed").unwrap();
        let checksummed = to_checksum_address(&addr_bytes);
        assert!(checksummed.starts_with("0x"));
    }
}
