// Bitcoin Cash Wallet Implementation
// Derivation path: m/44'/145'/0'/0/0
// Uses CashAddr format (bitcoincash:q...)

use bitcoin::secp256k1::Secp256k1;
use bitcoin::Network;
use serde::{Deserialize, Serialize};

/// Bitcoin Cash keys structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BitcoinCashKeys {
    pub private_hex: String,
    pub private_wif: String,
    pub public_compressed_hex: String,
    pub legacy_address: String,
    pub cash_address: String,
}

/// Derive Bitcoin Cash keys from a BIP39 seed
pub fn derive_bitcoin_cash_keys(seed: &[u8]) -> Result<BitcoinCashKeys, String> {
    use bitcoin::bip32::{DerivationPath, Xpriv};
    use std::str::FromStr;

    let secp = Secp256k1::new();

    // BIP32 master key from seed
    let master = Xpriv::new_master(Network::Bitcoin, seed)
        .map_err(|e| format!("Failed to create master key: {}", e))?;

    // Bitcoin Cash derivation path: m/44'/145'/0'/0/0
    let path = DerivationPath::from_str("m/44'/145'/0'/0/0")
        .map_err(|e| format!("Invalid derivation path: {}", e))?;

    let derived = master
        .derive_priv(&secp, &path)
        .map_err(|e| format!("Failed to derive key: {}", e))?;

    let secret_key = derived.private_key;
    let public_key = bitcoin::PublicKey::new(secret_key.public_key(&secp));

    // Private key hex
    let private_hex = hex::encode(secret_key.secret_bytes());

    // WIF encoding (same as Bitcoin mainnet)
    let private_wif = bitcoin::PrivateKey::new(secret_key, Network::Bitcoin).to_wif();

    // Public key compressed hex
    let public_compressed_hex = hex::encode(public_key.inner.serialize());

    // Legacy address (1... format)
    let legacy_address = encode_legacy_address(&public_key);

    // CashAddr format
    let cash_address = encode_cash_address(&public_key);

    Ok(BitcoinCashKeys {
        private_hex,
        private_wif,
        public_compressed_hex,
        legacy_address,
        cash_address,
    })
}

/// Encode legacy P2PKH address (same as Bitcoin)
fn encode_legacy_address(public_key: &bitcoin::PublicKey) -> String {
    use bitcoin::base58;
    use bitcoin::hashes::{sha256, Hash, ripemd160};

    let sha256_hash = sha256::Hash::hash(&public_key.inner.serialize());
    let ripemd_hash = ripemd160::Hash::hash(&sha256_hash[..]);

    // Version 0 for mainnet P2PKH
    let mut address_bytes = vec![0x00];
    address_bytes.extend_from_slice(&ripemd_hash[..]);

    let hash1 = sha256::Hash::hash(&address_bytes);
    let hash2 = sha256::Hash::hash(&hash1[..]);

    address_bytes.extend_from_slice(&hash2[..4]);

    base58::encode(&address_bytes)
}

/// Encode CashAddr format (bitcoincash:q...)
fn encode_cash_address(public_key: &bitcoin::PublicKey) -> String {
    use bitcoin::hashes::{sha256, Hash, ripemd160};

    // Get hash160 of public key
    let sha256_hash = sha256::Hash::hash(&public_key.inner.serialize());
    let hash160 = ripemd160::Hash::hash(&sha256_hash[..]);

    // Version byte: 0 for P2PKH
    let version = 0u8;

    // Payload: version (5 bits) + hash type (3 bits) + hash160 (160 bits)
    let mut payload = Vec::new();
    payload.push(version); // Type 0 = P2PKH, size 0 = 160 bits
    payload.extend_from_slice(&hash160[..]);

    // Convert to 5-bit groups for base32
    let converted = convert_bits(&payload, 8, 5, true);

    // Add checksum
    let checksum = calculate_cashaddr_checksum("bitcoincash", &converted);

    let mut full_payload = converted;
    full_payload.extend_from_slice(&checksum);

    // Encode to base32
    let encoded = encode_base32(&full_payload);

    format!("bitcoincash:{}", encoded)
}

/// Convert between bit sizes
fn convert_bits(data: &[u8], from_bits: u32, to_bits: u32, pad: bool) -> Vec<u8> {
    let mut acc: u32 = 0;
    let mut bits: u32 = 0;
    let mut result = Vec::new();
    let max_value = (1u32 << to_bits) - 1;

    for &byte in data {
        acc = (acc << from_bits) | (byte as u32);
        bits += from_bits;
        while bits >= to_bits {
            bits -= to_bits;
            result.push(((acc >> bits) & max_value) as u8);
        }
    }

    if pad && bits > 0 {
        result.push(((acc << (to_bits - bits)) & max_value) as u8);
    }

    result
}

/// Calculate CashAddr checksum
fn calculate_cashaddr_checksum(prefix: &str, payload: &[u8]) -> [u8; 8] {
    let mut values = Vec::new();

    // Prefix characters (lower 5 bits)
    for c in prefix.chars() {
        values.push((c as u8) & 0x1f);
    }
    values.push(0); // Separator

    // Payload
    values.extend_from_slice(payload);

    // Add template for checksum
    values.extend_from_slice(&[0, 0, 0, 0, 0, 0, 0, 0]);

    let polymod = polymod(&values) ^ 1;

    let mut checksum = [0u8; 8];
    for i in 0..8 {
        checksum[i] = ((polymod >> (5 * (7 - i))) & 0x1f) as u8;
    }

    checksum
}

/// BCH polymod function
fn polymod(values: &[u8]) -> u64 {
    const GENERATORS: [u64; 5] = [
        0x98f2bc8e61,
        0x79b76d99e2,
        0xf33e5fb3c4,
        0xae2eabe2a8,
        0x1e4f43e470,
    ];

    let mut c: u64 = 1;
    for &v in values {
        let c0 = c >> 35;
        c = ((c & 0x07ffffffff) << 5) ^ (v as u64);
        for (i, &gen) in GENERATORS.iter().enumerate() {
            if (c0 >> i) & 1 != 0 {
                c ^= gen;
            }
        }
    }

    c
}

/// Encode to CashAddr base32
fn encode_base32(data: &[u8]) -> String {
    const CHARSET: &[u8] = b"qpzry9x8gf2tvdw0s3jn54khce6mua7l";
    data.iter().map(|&b| CHARSET[b as usize] as char).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use bip39::Mnemonic;

    #[test]
    fn test_derive_bitcoin_cash_keys() {
        let mnemonic = Mnemonic::parse("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about").unwrap();
        let seed = mnemonic.to_seed("");
        
        let keys = derive_bitcoin_cash_keys(&seed).unwrap();
        
        // Verify cash address format
        assert!(keys.cash_address.starts_with("bitcoincash:q"), "BCH address should start with bitcoincash:q");
        assert!(keys.legacy_address.starts_with('1'), "Legacy address should start with 1");
        assert!(!keys.private_hex.is_empty());
    }
}
