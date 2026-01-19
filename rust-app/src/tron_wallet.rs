// Tron (TRX) Wallet Implementation
// Uses secp256k1 curve, similar to Ethereum but with different address encoding
// Derivation path: m/44'/195'/0'/0/0

use bitcoin::secp256k1::{Secp256k1, SecretKey, PublicKey};
use bitcoin::Network;
use serde::{Deserialize, Serialize};

/// Tron keys structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TronKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub address: String, // T... format (Base58Check)
}

/// Derive Tron keys from a BIP39 seed
pub fn derive_tron_keys(seed: &[u8]) -> Result<TronKeys, String> {
    use bitcoin::bip32::{DerivationPath, Xpriv};
    use std::str::FromStr;

    let secp = Secp256k1::new();

    // BIP32 master key from seed
    let master = Xpriv::new_master(Network::Bitcoin, seed)
        .map_err(|e| format!("Failed to create master key: {}", e))?;

    // Tron derivation path: m/44'/195'/0'/0/0
    let path = DerivationPath::from_str("m/44'/195'/0'/0/0")
        .map_err(|e| format!("Invalid derivation path: {}", e))?;

    let derived = master
        .derive_priv(&secp, &path)
        .map_err(|e| format!("Failed to derive key: {}", e))?;

    let secret_key = derived.private_key;
    let public_key = secret_key.public_key(&secp);

    // Private key hex
    let private_hex = hex::encode(secret_key.secret_bytes());

    // Public key uncompressed hex (65 bytes, without 04 prefix we use 64)
    let public_uncompressed = public_key.serialize_uncompressed();
    let public_hex = hex::encode(&public_uncompressed[1..]); // Skip 04 prefix

    // Generate Tron address
    let address = encode_tron_address(&public_key)?;

    Ok(TronKeys {
        private_hex,
        public_hex,
        address,
    })
}

/// Encode Tron address from public key
fn encode_tron_address(public_key: &PublicKey) -> Result<String, String> {
    use sha3::{Keccak256, Digest};
    use bitcoin::base58;
    use bitcoin::hashes::{sha256, Hash};

    // Get uncompressed public key (skip the 04 prefix)
    let public_uncompressed = public_key.serialize_uncompressed();
    let public_bytes = &public_uncompressed[1..]; // 64 bytes

    // Keccak256 hash of public key
    let mut hasher = Keccak256::new();
    hasher.update(public_bytes);
    let hash = hasher.finalize();

    // Take last 20 bytes
    let address_bytes = &hash[12..];

    // Add Tron prefix (0x41 for mainnet)
    let mut full_address = vec![0x41];
    full_address.extend_from_slice(address_bytes);

    // Double SHA256 for checksum
    let hash1 = sha256::Hash::hash(&full_address);
    let hash2 = sha256::Hash::hash(&hash1[..]);

    // Append first 4 bytes of checksum
    full_address.extend_from_slice(&hash2[..4]);

    // Base58 encode
    Ok(base58::encode(&full_address))
}

/// Convert Ethereum address to Tron address format
pub fn eth_to_tron_address(eth_address: &str) -> Result<String, String> {
    use bitcoin::base58;
    use bitcoin::hashes::{sha256, Hash};

    // Remove 0x prefix if present
    let hex_addr = eth_address.strip_prefix("0x").unwrap_or(eth_address);

    // Decode hex address
    let address_bytes = hex::decode(hex_addr)
        .map_err(|e| format!("Invalid hex: {}", e))?;

    if address_bytes.len() != 20 {
        return Err("Address must be 20 bytes".to_string());
    }

    // Add Tron prefix (0x41 for mainnet)
    let mut full_address = vec![0x41];
    full_address.extend_from_slice(&address_bytes);

    // Double SHA256 for checksum
    let hash1 = sha256::Hash::hash(&full_address);
    let hash2 = sha256::Hash::hash(&hash1[..]);

    // Append first 4 bytes of checksum
    full_address.extend_from_slice(&hash2[..4]);

    // Base58 encode
    Ok(base58::encode(&full_address))
}

#[cfg(test)]
mod tests {
    use super::*;
    use bip39::Mnemonic;

    #[test]
    fn test_derive_tron_keys() {
        let mnemonic = Mnemonic::parse("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about").unwrap();
        let seed = mnemonic.to_seed("");
        
        let keys = derive_tron_keys(&seed).unwrap();
        
        // Verify address starts with T
        assert!(keys.address.starts_with('T'), "Tron address should start with T");
        assert!(!keys.private_hex.is_empty());
        assert!(!keys.public_hex.is_empty());
    }

    #[test]
    fn test_eth_to_tron_address() {
        // Known conversion: ETH 0x... -> TRON T...
        let tron_addr = eth_to_tron_address("0x0000000000000000000000000000000000000000").unwrap();
        assert!(tron_addr.starts_with('T'), "Converted address should start with T");
    }
}
