// Cosmos Ecosystem Wallet Implementation
// Supports all Cosmos SDK chains with different HRPs (bech32 prefixes)
// Derivation path: m/44'/118'/0'/0/0 (standard Cosmos)

use bitcoin::secp256k1::{Secp256k1, PublicKey as Secp256k1PublicKey};
use bitcoin::Network;
use serde::{Deserialize, Serialize};
use bech32::{self, Variant, ToBase32};

/// Cosmos keys structure (supports multiple chains via different HRPs)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CosmosKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub cosmos_address: String,      // cosmos1...
    pub osmosis_address: String,     // osmo1...
    pub celestia_address: String,    // celestia1...
    pub dydx_address: String,        // dydx1...
    pub injective_address: String,   // inj1...
    pub sei_address: String,         // sei1...
    pub akash_address: String,       // akash1...
    pub kujira_address: String,      // kujira1...
    pub stride_address: String,      // stride1...
    pub secret_address: String,      // secret1...
    pub stargaze_address: String,    // stars1...
    pub juno_address: String,        // juno1...
    pub terra_address: String,       // terra1...
    pub neutron_address: String,     // neutron1...
    pub noble_address: String,       // noble1...
    pub axelar_address: String,      // axelar1...
    pub fetch_address: String,       // fetch1...
    pub persistence_address: String, // persistence1...
    pub sommelier_address: String,   // somm1...
}

/// All supported Cosmos chain HRPs
pub const COSMOS_CHAINS: &[(&str, &str)] = &[
    ("cosmos", "Cosmos Hub"),
    ("osmo", "Osmosis"),
    ("celestia", "Celestia"),
    ("dydx", "dYdX"),
    ("inj", "Injective"),
    ("sei", "Sei"),
    ("akash", "Akash"),
    ("kujira", "Kujira"),
    ("stride", "Stride"),
    ("secret", "Secret Network"),
    ("stars", "Stargaze"),
    ("juno", "Juno"),
    ("terra", "Terra"),
    ("neutron", "Neutron"),
    ("noble", "Noble"),
    ("axelar", "Axelar"),
    ("fetch", "Fetch.AI"),
    ("persistence", "Persistence"),
    ("somm", "Sommelier"),
];

/// Derive Cosmos keys from a BIP39 seed
pub fn derive_cosmos_keys(seed: &[u8]) -> Result<CosmosKeys, String> {
    use bitcoin::bip32::{DerivationPath, Xpriv};
    use std::str::FromStr;

    let secp = Secp256k1::new();

    // BIP32 master key from seed
    let master = Xpriv::new_master(Network::Bitcoin, seed)
        .map_err(|e| format!("Failed to create master key: {}", e))?;

    // Standard Cosmos derivation path: m/44'/118'/0'/0/0
    let path = DerivationPath::from_str("m/44'/118'/0'/0/0")
        .map_err(|e| format!("Invalid derivation path: {}", e))?;

    let derived = master
        .derive_priv(&secp, &path)
        .map_err(|e| format!("Failed to derive key: {}", e))?;

    let secret_key = derived.private_key;
    let public_key = secret_key.public_key(&secp);

    // Private key hex
    let private_hex = hex::encode(secret_key.secret_bytes());

    // Public key compressed hex (33 bytes)
    let public_hex = hex::encode(public_key.serialize());

    // Derive addresses for all chains
    let cosmos_address = encode_cosmos_address(&public_key, "cosmos")?;
    let osmosis_address = encode_cosmos_address(&public_key, "osmo")?;
    let celestia_address = encode_cosmos_address(&public_key, "celestia")?;
    let dydx_address = encode_cosmos_address(&public_key, "dydx")?;
    let injective_address = encode_cosmos_address(&public_key, "inj")?;
    let sei_address = encode_cosmos_address(&public_key, "sei")?;
    let akash_address = encode_cosmos_address(&public_key, "akash")?;
    let kujira_address = encode_cosmos_address(&public_key, "kujira")?;
    let stride_address = encode_cosmos_address(&public_key, "stride")?;
    let secret_address = encode_cosmos_address(&public_key, "secret")?;
    let stargaze_address = encode_cosmos_address(&public_key, "stars")?;
    let juno_address = encode_cosmos_address(&public_key, "juno")?;
    let terra_address = encode_cosmos_address(&public_key, "terra")?;
    let neutron_address = encode_cosmos_address(&public_key, "neutron")?;
    let noble_address = encode_cosmos_address(&public_key, "noble")?;
    let axelar_address = encode_cosmos_address(&public_key, "axelar")?;
    let fetch_address = encode_cosmos_address(&public_key, "fetch")?;
    let persistence_address = encode_cosmos_address(&public_key, "persistence")?;
    let sommelier_address = encode_cosmos_address(&public_key, "somm")?;

    Ok(CosmosKeys {
        private_hex,
        public_hex,
        cosmos_address,
        osmosis_address,
        celestia_address,
        dydx_address,
        injective_address,
        sei_address,
        akash_address,
        kujira_address,
        stride_address,
        secret_address,
        stargaze_address,
        juno_address,
        terra_address,
        neutron_address,
        noble_address,
        axelar_address,
        fetch_address,
        persistence_address,
        sommelier_address,
    })
}

/// Encode a Cosmos address with the given HRP
pub fn encode_cosmos_address(public_key: &Secp256k1PublicKey, hrp: &str) -> Result<String, String> {
    use bitcoin::hashes::{sha256, Hash, ripemd160};

    // SHA256 then RIPEMD160 of compressed public key
    let sha256_hash = sha256::Hash::hash(&public_key.serialize());
    let ripemd_hash = ripemd160::Hash::hash(&sha256_hash[..]);

    // Convert to bytes for bech32 encoding (bech32 v0.9 API)
    let hash_bytes: &[u8] = ripemd_hash.as_ref();
    let address = bech32::encode(hrp, hash_bytes.to_base32(), Variant::Bech32)
        .map_err(|e| format!("Bech32 encoding failed: {}", e))?;

    Ok(address)
}

/// Get address for a specific Cosmos chain by HRP
pub fn get_cosmos_chain_address(seed: &[u8], hrp: &str) -> Result<String, String> {
    use bitcoin::bip32::{DerivationPath, Xpriv};
    use std::str::FromStr;

    let secp = Secp256k1::new();
    let master = Xpriv::new_master(Network::Bitcoin, seed)
        .map_err(|e| format!("Failed to create master key: {}", e))?;

    let path = DerivationPath::from_str("m/44'/118'/0'/0/0")
        .map_err(|e| format!("Invalid derivation path: {}", e))?;

    let derived = master
        .derive_priv(&secp, &path)
        .map_err(|e| format!("Failed to derive key: {}", e))?;

    let public_key = derived.private_key.public_key(&secp);
    encode_cosmos_address(&public_key, hrp)
}

#[cfg(test)]
mod tests {
    use super::*;
    use bip39::Mnemonic;

    #[test]
    fn test_derive_cosmos_keys() {
        let mnemonic = Mnemonic::parse("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about").unwrap();
        let seed = mnemonic.to_seed("");
        
        let keys = derive_cosmos_keys(&seed).unwrap();
        
        // Verify all addresses have correct prefixes
        assert!(keys.cosmos_address.starts_with("cosmos1"), "Cosmos address should start with cosmos1");
        assert!(keys.osmosis_address.starts_with("osmo1"), "Osmosis address should start with osmo1");
        assert!(keys.celestia_address.starts_with("celestia1"), "Celestia address should start with celestia1");
        assert!(keys.dydx_address.starts_with("dydx1"), "dYdX address should start with dydx1");
        assert!(keys.injective_address.starts_with("inj1"), "Injective address should start with inj1");
        assert!(keys.sei_address.starts_with("sei1"), "Sei address should start with sei1");
        assert!(!keys.private_hex.is_empty());
        assert!(!keys.public_hex.is_empty());
    }

    #[test]
    fn test_get_cosmos_chain_address() {
        let mnemonic = Mnemonic::parse("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about").unwrap();
        let seed = mnemonic.to_seed("");
        
        let kava_address = get_cosmos_chain_address(&seed, "kava").unwrap();
        assert!(kava_address.starts_with("kava1"), "Kava address should start with kava1");
    }
}
