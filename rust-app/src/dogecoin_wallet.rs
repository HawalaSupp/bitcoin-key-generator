// Dogecoin Wallet Implementation
// Based on Bitcoin with different parameters
// Derivation path: m/44'/3'/0'/0/0

use bitcoin::secp256k1::Secp256k1;
use bitcoin::hashes::Hash;
use bitcoin::Network;
use serde::{Deserialize, Serialize};

/// Dogecoin network parameters
pub const DOGE_P2PKH_PREFIX: u8 = 30; // 'D' prefix
pub const DOGE_P2SH_PREFIX: u8 = 22;
pub const DOGE_WIF_PREFIX: u8 = 158;

/// Dogecoin keys structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DogecoinKeys {
    pub private_hex: String,
    pub private_wif: String,
    pub public_compressed_hex: String,
    pub address: String,
}

/// Derive Dogecoin keys from a BIP39 seed
pub fn derive_dogecoin_keys(seed: &[u8]) -> Result<DogecoinKeys, String> {
    use bitcoin::bip32::{DerivationPath, Xpriv};
    use std::str::FromStr;

    let secp = Secp256k1::new();

    // BIP32 master key from seed
    let master = Xpriv::new_master(Network::Bitcoin, seed)
        .map_err(|e| format!("Failed to create master key: {}", e))?;

    // Dogecoin derivation path: m/44'/3'/0'/0/0
    let path = DerivationPath::from_str("m/44'/3'/0'/0/0")
        .map_err(|e| format!("Invalid derivation path: {}", e))?;

    let derived = master
        .derive_priv(&secp, &path)
        .map_err(|e| format!("Failed to derive key: {}", e))?;

    let secret_key = derived.private_key;
    let public_key = bitcoin::PublicKey::new(secret_key.public_key(&secp));

    // Private key hex
    let private_hex = hex::encode(secret_key.secret_bytes());

    // WIF encoding for Dogecoin (mainnet)
    let private_wif = encode_doge_wif(&secret_key.secret_bytes(), true);

    // Public key compressed hex
    let public_compressed_hex = hex::encode(public_key.inner.serialize());

    // Dogecoin P2PKH address
    let address = encode_doge_address(&public_key);

    Ok(DogecoinKeys {
        private_hex,
        private_wif,
        public_compressed_hex,
        address,
    })
}

/// Encode WIF for Dogecoin
fn encode_doge_wif(private_key: &[u8], compressed: bool) -> String {
    use bitcoin::base58;

    let mut data = vec![DOGE_WIF_PREFIX];
    data.extend_from_slice(private_key);
    if compressed {
        data.push(0x01);
    }

    // Double SHA256 checksum
    let hash1 = bitcoin::hashes::sha256::Hash::hash(&data);
    let hash2 = bitcoin::hashes::sha256::Hash::hash(&hash1[..]);

    data.extend_from_slice(&hash2[..4]);

    base58::encode(&data)
}

/// Encode Dogecoin P2PKH address
fn encode_doge_address(public_key: &bitcoin::PublicKey) -> String {
    use bitcoin::base58;
    use bitcoin::hashes::{sha256, Hash, ripemd160};

    // SHA256 then RIPEMD160 of public key
    let sha256_hash = sha256::Hash::hash(&public_key.inner.serialize());
    let ripemd_hash = ripemd160::Hash::hash(&sha256_hash[..]);

    // Add version byte
    let mut address_bytes = vec![DOGE_P2PKH_PREFIX];
    address_bytes.extend_from_slice(&ripemd_hash[..]);

    // Double SHA256 checksum
    let hash1 = sha256::Hash::hash(&address_bytes);
    let hash2 = sha256::Hash::hash(&hash1[..]);

    address_bytes.extend_from_slice(&hash2[..4]);

    base58::encode(&address_bytes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use bip39::Mnemonic;

    #[test]
    fn test_derive_dogecoin_keys() {
        let mnemonic = Mnemonic::parse("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about").unwrap();
        let seed = mnemonic.to_seed("");
        
        let keys = derive_dogecoin_keys(&seed).unwrap();
        
        // Verify address starts with 'D'
        assert!(keys.address.starts_with('D'), "Dogecoin address should start with D");
        assert!(!keys.private_hex.is_empty());
        assert!(!keys.private_wif.is_empty());
        assert!(!keys.public_compressed_hex.is_empty());
    }
}
