//! Legacy Helper Functions
//! 
//! These functions are kept for backward compatibility with existing binaries.
//! They will be migrated to the new module structure over time.

use bech32::{self, Variant};
use bitcoin::hashes::{Hash, hash160, sha256d};
use bitcoin::key::{CompressedPublicKey, PublicKey as BitcoinPublicKey};
use bitcoin::secp256k1::{self, Secp256k1, SecretKey};
use bitcoin::{Address, Network, PrivateKey};
use bs58::Alphabet;
use curve25519_dalek::edwards::EdwardsPoint;
use curve25519_dalek::scalar::Scalar;
use ed25519_dalek::SigningKey;
use rand::RngCore;
use rand::rngs::OsRng;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::convert::TryFrom;
use std::error::Error;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use bip39::Mnemonic;
use bitcoin::bip32::DerivationPath;
use std::str::FromStr;
use monero::{Network as MoneroNetwork, Address as MoneroAddress, PublicKey as MoneroPublicKey};

// Import from parent crate's modules
use crate::bitcoin_wallet;
use crate::taproot_wallet;
use tiny_keccak::{Hasher, Keccak};

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct AllKeys {
    pub bitcoin: BitcoinKeys,
    pub bitcoin_testnet: BitcoinKeys,
    pub litecoin: LitecoinKeys,
    pub monero: MoneroKeys,
    pub solana: SolanaKeys,
    pub ethereum: EthereumKeys,
    pub ethereum_sepolia: EthereumKeys,
    pub bnb: BnbKeys,
    pub xrp: XrpKeys,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct BitcoinKeys {
    pub private_hex: String,
    pub private_wif: String,
    pub public_compressed_hex: String,
    pub address: String,
    // Taproot (P2TR) address - bc1p... for mainnet, tb1p... for testnet
    pub taproot_address: Option<String>,
    pub x_only_pubkey: Option<String>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct LitecoinKeys {
    pub private_hex: String,
    pub private_wif: String,
    pub public_compressed_hex: String,
    pub address: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct MoneroKeys {
    pub private_spend_hex: String,
    pub private_view_hex: String,
    pub public_spend_hex: String,
    pub public_view_hex: String,
    pub address: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct SolanaKeys {
    pub private_seed_hex: String,
    pub private_key_base58: String,
    pub public_key_base58: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct EthereumKeys {
    pub private_hex: String,
    pub public_uncompressed_hex: String,
    pub address: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct BnbKeys {
    pub private_hex: String,
    pub public_uncompressed_hex: String,
    pub address: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct XrpKeys {
    pub private_hex: String,
    pub public_compressed_hex: String,
    pub classic_address: String,
}

pub fn create_new_wallet() -> Result<(String, AllKeys), Box<dyn Error>> {
    let mut entropy = [0u8; 16];
    OsRng.fill_bytes(&mut entropy);
    let mnemonic = Mnemonic::from_entropy(&entropy)?;
    let phrase = mnemonic.to_string();
    let seed = mnemonic.to_seed("");
    let keys = generate_keys_from_seed(&seed)?;
    Ok((phrase, keys))
}

pub fn generate_keys_from_seed(seed: &[u8]) -> Result<AllKeys, Box<dyn Error>> {
    let secp = Secp256k1::new();
    let master_xprv = bitcoin::bip32::Xpriv::new_master(Network::Bitcoin, seed)?;

    Ok(AllKeys {
        bitcoin: derive_bitcoin_keys(&secp, &master_xprv)?,
        bitcoin_testnet: derive_bitcoin_testnet_keys(&secp, &master_xprv)?,
        litecoin: derive_litecoin_keys(&secp, &master_xprv)?,
        monero: derive_monero_keys(seed)?,
        solana: derive_solana_keys(seed)?,
        ethereum: derive_ethereum_keys(&secp, &master_xprv)?,
        ethereum_sepolia: derive_ethereum_keys(&secp, &master_xprv)?,
        bnb: derive_bnb_keys(&secp, &master_xprv)?,
        xrp: derive_xrp_keys(&secp, &master_xprv)?,
    })
}

fn derive_bitcoin_keys(secp: &Secp256k1<secp256k1::All>, master: &bitcoin::bip32::Xpriv) -> Result<BitcoinKeys, Box<dyn Error>> {
    let path = DerivationPath::from_str("m/84'/0'/0'/0/0")?;
    let child = master.derive_priv(secp, &path)?;
    let secret_key = child.private_key;
    
    let private_hex = hex::encode(secret_key.secret_bytes());
    let secp_public_key = secret_key.public_key(secp);
    let public_key = BitcoinPublicKey::from(secp_public_key);
    let compressed = CompressedPublicKey::try_from(public_key)?;
    let address = Address::p2wpkh(&compressed, Network::Bitcoin);

    // Derive Taproot address from same private key
    let (taproot_address, x_only_pubkey) = match derive_taproot_address(&private_hex, Network::Bitcoin) {
        Ok((addr, xonly)) => (Some(addr), Some(xonly)),
        Err(_) => (None, None),
    };

    Ok(BitcoinKeys {
        private_hex,
        private_wif: PrivateKey::new(secret_key, Network::Bitcoin).to_wif(),
        public_compressed_hex: hex::encode(compressed.to_bytes()),
        address: address.to_string(),
        taproot_address,
        x_only_pubkey,
    })
}

fn derive_bitcoin_testnet_keys(secp: &Secp256k1<secp256k1::All>, master: &bitcoin::bip32::Xpriv) -> Result<BitcoinKeys, Box<dyn Error>> {
    let path = DerivationPath::from_str("m/84'/1'/0'/0/0")?;
    let child = master.derive_priv(secp, &path)?;
    let secret_key = child.private_key;
    
    let private_hex = hex::encode(secret_key.secret_bytes());
    let secp_public_key = secret_key.public_key(secp);
    let public_key = BitcoinPublicKey::from(secp_public_key);
    let compressed = CompressedPublicKey::try_from(public_key)?;
    let private_key = PrivateKey::new(secret_key, Network::Testnet);
    let address = Address::p2wpkh(&compressed, Network::Testnet);

    // Derive Taproot address from same private key
    let (taproot_address, x_only_pubkey) = match derive_taproot_address(&private_hex, Network::Testnet) {
        Ok((addr, xonly)) => (Some(addr), Some(xonly)),
        Err(_) => (None, None),
    };

    Ok(BitcoinKeys {
        private_hex,
        private_wif: private_key.to_wif(),
        public_compressed_hex: hex::encode(compressed.to_bytes()),
        address: address.to_string(),
        taproot_address,
        x_only_pubkey,
    })
}

fn derive_litecoin_keys(secp: &Secp256k1<secp256k1::All>, master: &bitcoin::bip32::Xpriv) -> Result<LitecoinKeys, Box<dyn Error>> {
    let path = DerivationPath::from_str("m/84'/2'/0'/0/0")?;
    let child = master.derive_priv(secp, &path)?;
    let secret_key = child.private_key;

    let private_hex = hex::encode(secret_key.secret_bytes());
    let secp_public_key = secret_key.public_key(secp);
    let public_key = BitcoinPublicKey::from(secp_public_key);
    let compressed = CompressedPublicKey::try_from(public_key)?;
    let compressed_bytes = compressed.to_bytes();

    let private_wif = encode_litecoin_wif(&secret_key);
    let pubkey_hash = hash160::Hash::hash(&compressed_bytes);

    let version = bech32::u5::try_from_u8(0).map_err(|e| Box::<dyn Error>::from(e))?;
    let converted = bech32::convert_bits(pubkey_hash.as_ref(), 8, 5, true)
        .map_err(|e| Box::<dyn Error>::from(e))?;
    let mut bech32_data = Vec::with_capacity(1 + converted.len());
    bech32_data.push(version);
    for value in converted {
        let u5 = bech32::u5::try_from_u8(value).map_err(|e| Box::<dyn Error>::from(e))?;
        bech32_data.push(u5);
    }
    let address = bech32::encode("ltc", bech32_data, Variant::Bech32)
        .map_err(|e| Box::<dyn Error>::from(e))?;

    Ok(LitecoinKeys {
        private_hex,
        private_wif,
        public_compressed_hex: hex::encode(compressed_bytes),
        address,
    })
}

fn derive_monero_keys(seed: &[u8]) -> Result<MoneroKeys, Box<dyn Error>> {
    let mut hasher = Sha256::new();
    hasher.update(seed);
    hasher.update(b"MONERO_DERIVATION");
    let result = hasher.finalize();
    
    let mut spend_seed = [0u8; 32];
    spend_seed.copy_from_slice(&result);
    
    let spend_scalar = Scalar::from_bytes_mod_order(spend_seed);
    let private_spend = spend_scalar.to_bytes();

    let view_seed = keccak256(&private_spend);
    let view_scalar = Scalar::from_bytes_mod_order(view_seed);
    let private_view = view_scalar.to_bytes();

    let spend_point = EdwardsPoint::mul_base(&spend_scalar);
    let view_point = EdwardsPoint::mul_base(&view_scalar);
    let public_spend_bytes = spend_point.compress().to_bytes();
    let public_view_bytes = view_point.compress().to_bytes();

    let public_spend_key = MoneroPublicKey::from_slice(&public_spend_bytes)?;
    let public_view_key = MoneroPublicKey::from_slice(&public_view_bytes)?;
    let address = MoneroAddress::standard(MoneroNetwork::Mainnet, public_spend_key, public_view_key);

    Ok(MoneroKeys {
        private_spend_hex: hex::encode(private_spend),
        private_view_hex: hex::encode(private_view),
        public_spend_hex: hex::encode(public_spend_bytes),
        public_view_hex: hex::encode(public_view_bytes),
        address: address.to_string(),
    })
}

fn derive_solana_keys(seed: &[u8]) -> Result<SolanaKeys, Box<dyn Error>> {
    let mut hasher = Sha256::new();
    hasher.update(seed);
    hasher.update(b"SOLANA_DERIVATION");
    let result = hasher.finalize();
    
    let signing_key = SigningKey::from_bytes(&result.into());
    let private_seed = signing_key.to_bytes();
    let public_key_bytes = signing_key.verifying_key().to_bytes();

    let mut keypair_bytes = [0u8; 64];
    keypair_bytes[..32].copy_from_slice(&private_seed);
    keypair_bytes[32..].copy_from_slice(&public_key_bytes);

    Ok(SolanaKeys {
        private_seed_hex: hex::encode(private_seed),
        private_key_base58: bs58::encode(keypair_bytes).into_string(),
        public_key_base58: bs58::encode(public_key_bytes).into_string(),
    })
}

fn derive_ethereum_keys(secp: &Secp256k1<secp256k1::All>, master: &bitcoin::bip32::Xpriv) -> Result<EthereumKeys, Box<dyn Error>> {
    let path = DerivationPath::from_str("m/44'/60'/0'/0/0")?;
    let child = master.derive_priv(secp, &path)?;
    let secret_key = child.private_key;

    let private_hex = hex::encode(secret_key.secret_bytes());
    let secp_public_key = secret_key.public_key(secp);
    let uncompressed = secp_public_key.serialize_uncompressed();
    let public_key_bytes = &uncompressed[1..];

    let public_uncompressed_hex = hex::encode(public_key_bytes);
    let address_bytes = keccak256(public_key_bytes);
    let address = to_checksum_address(&address_bytes[12..]);

    Ok(EthereumKeys {
        private_hex,
        public_uncompressed_hex,
        address,
    })
}

fn derive_bnb_keys(secp: &Secp256k1<secp256k1::All>, master: &bitcoin::bip32::Xpriv) -> Result<BnbKeys, Box<dyn Error>> {
    let path = DerivationPath::from_str("m/44'/60'/0'/0/0")?; 
    let child = master.derive_priv(secp, &path)?;
    let secret_key = child.private_key;

    let private_hex = hex::encode(secret_key.secret_bytes());
    let secp_public_key = secret_key.public_key(secp);
    let uncompressed = secp_public_key.serialize_uncompressed();
    let public_key_bytes = &uncompressed[1..];

    let public_uncompressed_hex = hex::encode(public_key_bytes);
    let address_bytes = keccak256(public_key_bytes);
    let address = to_checksum_address(&address_bytes[12..]);

    Ok(BnbKeys {
        private_hex,
        public_uncompressed_hex,
        address,
    })
}

fn derive_xrp_keys(secp: &Secp256k1<secp256k1::All>, master: &bitcoin::bip32::Xpriv) -> Result<XrpKeys, Box<dyn Error>> {
    let path = DerivationPath::from_str("m/44'/144'/0'/0/0")?;
    let child = master.derive_priv(secp, &path)?;
    let secret_key = child.private_key;

    let private_hex = hex::encode(secret_key.secret_bytes());
    let secp_public_key = secret_key.public_key(secp);
    let compressed = secp_public_key.serialize();

    let account_id = hash160::Hash::hash(&compressed);
    let mut payload = Vec::new();
    payload.push(0x00); 
    payload.extend_from_slice(account_id.as_ref());

    let checksum = sha256d::Hash::hash(&payload);
    let mut address_bytes = payload;
    address_bytes.extend_from_slice(&checksum[..4]);
    let classic_address = bs58::encode(address_bytes)
        .with_alphabet(Alphabet::RIPPLE)
        .into_string();

    Ok(XrpKeys {
        private_hex,
        public_compressed_hex: hex::encode(compressed),
        classic_address,
    })
}


pub fn keccak256(data: &[u8]) -> [u8; 32] {
    let mut hasher = Keccak::v256();
    hasher.update(data);
    let mut out = [0u8; 32];
    hasher.finalize(&mut out);
    out
}

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

fn is_valid_ethereum_address(address: &str) -> bool {
    let trimmed = address.trim();
    if !trimmed.starts_with("0x") || trimmed.len() != 42 {
        return false;
    }

    let hex_part = &trimmed[2..];
    if !hex_part.chars().all(|c| c.is_ascii_hexdigit()) {
        return false;
    }

    let lower = hex_part.to_lowercase();
    let bytes = match hex::decode(&lower) {
        Ok(b) => b,
        Err(_) => return false,
    };

    if bytes.len() != 20 {
        return false;
    }

    // Accept fully lowercase or uppercase addresses without checksum
    if hex_part == lower || hex_part == hex_part.to_uppercase() {
        return true;
    }

    let checksummed = to_checksum_address(&bytes);
    match checksummed.get(2..) {
        Some(stripped) => stripped == hex_part,
        None => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn litecoin_wif_has_correct_prefix() {
        let secret_key = SecretKey::from_slice(&[1u8; 32]).expect("valid secret");
        let wif = encode_litecoin_wif(&secret_key);
        assert!(wif.starts_with('T'));
    }
}

/// FFI Interface

#[derive(Serialize)]
struct WalletResponse {
    mnemonic: String,
    keys: AllKeys,
}

#[unsafe(no_mangle)]
pub extern "C" fn generate_keys_ffi() -> *mut c_char {
    let (mnemonic, keys) = match create_new_wallet() {
        Ok(res) => res,
        Err(_) => return std::ptr::null_mut(),
    };

    let response = WalletResponse { mnemonic, keys };

    let json = match serde_json::to_string(&response) {
        Ok(j) => j,
        Err(_) => return std::ptr::null_mut(),
    };

    let c_str = match CString::new(json) {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    c_str.into_raw()
}

#[unsafe(no_mangle)]
pub extern "C" fn restore_wallet_ffi(mnemonic_str: *const c_char) -> *mut c_char {
    let c_str = unsafe {
        assert!(!mnemonic_str.is_null());
        CStr::from_ptr(mnemonic_str)
    };
    let phrase = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let mnemonic = match Mnemonic::parse(phrase) {
        Ok(m) => m,
        Err(_) => return std::ptr::null_mut(),
    };
    let seed = mnemonic.to_seed("");
    let keys = match generate_keys_from_seed(&seed) {
        Ok(k) => k,
        Err(_) => return std::ptr::null_mut(),
    };

    let json = match serde_json::to_string(&keys) {
        Ok(j) => j,
        Err(_) => return std::ptr::null_mut(),
    };
    
    CString::new(json).unwrap().into_raw()
}

#[unsafe(no_mangle)]
pub extern "C" fn validate_mnemonic_ffi(mnemonic_str: *const c_char) -> bool {
    let c_str = unsafe {
        if mnemonic_str.is_null() { return false; }
        CStr::from_ptr(mnemonic_str)
    };
    let phrase = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return false,
    };
    
    Mnemonic::parse(phrase).is_ok()
}

#[unsafe(no_mangle)]
pub extern "C" fn validate_ethereum_address_ffi(address: *const c_char) -> bool {
    let c_str = unsafe {
        if address.is_null() { return false; }
        CStr::from_ptr(address)
    };

    match c_str.to_str() {
        Ok(addr) => is_valid_ethereum_address(addr),
        Err(_) => false,
    }
}

#[derive(Deserialize)]
struct BalanceRequest {
    bitcoin: Option<String>,
    ethereum: Option<String>,
}

#[derive(Serialize)]
struct BalanceResponse {
    bitcoin: Option<String>,
    ethereum: Option<String>,
}

#[unsafe(no_mangle)]
pub extern "C" fn fetch_balances_ffi(json_input: *const c_char) -> *mut c_char {
    let c_str = unsafe {
        assert!(!json_input.is_null());
        CStr::from_ptr(json_input)
    };

    let json_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let request: BalanceRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(_) => {
            return CString::new("{\"error\": \"Invalid JSON\"}")
                .unwrap()
                .into_raw();
        }
    };

    // In a real implementation, we'd use threads/rayon here.
    // For MVP, we'll do serial blocking calls (which is still faster than process spawning).

    let btc_bal = if let Some(addr) = request.bitcoin {
        fetch_bitcoin_balance(&addr).unwrap_or_else(|_| "0.00000000".to_string())
    } else {
        "0.00000000".to_string()
    };

    let eth_bal = if let Some(addr) = request.ethereum {
        fetch_ethereum_balance(&addr).unwrap_or_else(|_| "0.0000".to_string())
    } else {
        "0.0000".to_string()
    };

    let response = BalanceResponse {
        bitcoin: Some(btc_bal),
        ethereum: Some(eth_bal),
    };

    let output_json = serde_json::to_string(&response).unwrap();
    CString::new(output_json).unwrap().into_raw()
}

#[unsafe(no_mangle)]
pub extern "C" fn fetch_bitcoin_history_ffi(address: *const c_char) -> *mut c_char {
    let c_str = unsafe {
        if address.is_null() { return std::ptr::null_mut(); }
        CStr::from_ptr(address)
    };
    let addr_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return CString::new("[]").unwrap().into_raw(),
    };

    match fetch_bitcoin_history(addr_str) {
        Ok(items) => {
            let json = serde_json::to_string(&items).unwrap_or_else(|_| "[]".to_string());
            CString::new(json).unwrap().into_raw()
        },
        Err(_) => CString::new("[]").unwrap().into_raw(),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn free_string(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(s);
    }
}

#[derive(Deserialize)]
struct TransactionRequest {
    recipient: String,
    amount_sats: u64,
    fee_rate: u64,
    sender_wif: String,
    utxos: Option<Vec<bitcoin_wallet::Utxo>>,
}

#[unsafe(no_mangle)]
pub extern "C" fn prepare_transaction_ffi(json_input: *const c_char) -> *mut c_char {
    let c_str = unsafe {
        assert!(!json_input.is_null());
        CStr::from_ptr(json_input)
    };

    let json_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let request: TransactionRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(_) => {
            return CString::new("{\"error\": \"Invalid JSON\"}")
                .unwrap()
                .into_raw();
        }
    };

    match prepare_transaction(
        &request.recipient,
        request.amount_sats,
        request.fee_rate,
        &request.sender_wif,
        request.utxos,
    ) {
        Ok(hex) => CString::new(format!("{{\"success\": true, \"tx_hex\": \"{}\"}}", hex))
            .unwrap()
            .into_raw(),
        Err(e) => CString::new(format!("{{\"success\": false, \"error\": \"{}\"}}", e))
            .unwrap()
            .into_raw(),
    }
}

#[derive(Deserialize)]
struct EthTransactionRequest {
    recipient: String,
    amount: String, // Wei (hex or decimal)
    chain_id: u64,
    sender_key_hex: String,
    nonce: u64,
    gas_limit: u64,
    gas_price: Option<String>, // Wei (hex or decimal)
    max_fee_per_gas: Option<String>,
    max_priority_fee_per_gas: Option<String>,
    data: Option<String>,
}

#[unsafe(no_mangle)]
pub extern "C" fn prepare_ethereum_transaction_ffi(json_input: *const c_char) -> *mut c_char {
    let c_str = unsafe {
        assert!(!json_input.is_null());
        CStr::from_ptr(json_input)
    };

    let json_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let request: EthTransactionRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => {
            return CString::new(format!("{{\"error\": \"Invalid JSON: {}\"}}", e))
                .unwrap()
                .into_raw();
        }
    };

    let data = request.data.unwrap_or_else(|| "0x".to_string());

    // Block on async function for FFI (simplest for now)
    let rt = tokio::runtime::Runtime::new().unwrap();
    match rt.block_on(prepare_ethereum_transaction(
        &request.recipient,
        &request.amount,
        request.chain_id,
        &request.sender_key_hex,
        request.nonce,
        request.gas_limit,
        request.gas_price,
        request.max_fee_per_gas,
        request.max_priority_fee_per_gas,
        &data,
    )) {
        Ok(hex) => CString::new(format!("{{\"success\": true, \"tx_hex\": \"0x{}\"}}", hex))
            .unwrap()
            .into_raw(),
        Err(e) => CString::new(format!("{{\"success\": false, \"error\": \"{}\"}}", e))
            .unwrap()
            .into_raw(),
    }
}

pub fn encode_litecoin_wif(secret_key: &SecretKey) -> String {
    let mut data = Vec::with_capacity(34);
    data.push(0xB0);
    data.extend_from_slice(&secret_key.secret_bytes());
    data.push(0x01);

    let checksum = sha256d::Hash::hash(&data);
    let mut payload = data;
    payload.extend_from_slice(&checksum[..4]);

    bs58::encode(payload).into_string()
}

const MONERO_BASE58_ALPHABET: &[u8; 58] =
    b"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
const MONERO_BLOCK_ENCODED_LENGTH: [usize; 9] = [0, 2, 3, 5, 7, 8, 9, 10, 11];

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
        value /= 58;
        chars.push(MONERO_BASE58_ALPHABET[remainder] as char);
    }

    if chars.is_empty() {
        chars.push('1');
    }

    chars.reverse();
    let target_len = MONERO_BLOCK_ENCODED_LENGTH[block.len()];
    while chars.len() < target_len {
        chars.insert(0, '1');
    }

    chars.into_iter().collect()
}

#[unsafe(no_mangle)]
pub extern "C" fn keccak256_ffi(data: *const u8, len: usize, output: *mut u8) {
    let slice = unsafe { std::slice::from_raw_parts(data, len) };
    let hash = keccak256(slice);
    unsafe {
        std::ptr::copy_nonoverlapping(hash.as_ptr(), output, 32);
    }
}

// Taproot (P2TR) Transaction FFI

#[derive(Deserialize)]
struct TaprootTransactionRequest {
    recipient: String,
    amount_sats: u64,
    fee_rate: u64,
    sender_wif: String,
    utxos: Option<Vec<taproot_wallet::Utxo>>,
}

/// Prepare a Taproot (P2TR) transaction - uses Schnorr signatures for ~7% fee savings
#[unsafe(no_mangle)]
pub extern "C" fn prepare_taproot_transaction_ffi(json_input: *const c_char) -> *mut c_char {
    let c_str = unsafe {
        assert!(!json_input.is_null());
        CStr::from_ptr(json_input)
    };

    let json_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let request: TaprootTransactionRequest = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(e) => {
            return CString::new(format!("{{\"error\": \"Invalid JSON: {}\"}}", e))
                .unwrap()
                .into_raw();
        }
    };

    match prepare_taproot_transaction_from_wif(
        &request.recipient,
        request.amount_sats,
        request.fee_rate,
        &request.sender_wif,
        request.utxos,
    ) {
        Ok(hex) => CString::new(format!("{{\"success\": true, \"tx_hex\": \"{}\"}}", hex))
            .unwrap()
            .into_raw(),
        Err(e) => CString::new(format!("{{\"success\": false, \"error\": \"{}\"}}", e))
            .unwrap()
            .into_raw(),
    }
}

/// Derive Taproot address from WIF private key
#[unsafe(no_mangle)]
pub extern "C" fn derive_taproot_address_ffi(wif: *const c_char) -> *mut c_char {
    let c_str = unsafe {
        if wif.is_null() { return std::ptr::null_mut(); }
        CStr::from_ptr(wif)
    };

    let wif_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    // Parse WIF to get private key and network
    let private_key = match bitcoin::PrivateKey::from_wif(wif_str) {
        Ok(pk) => pk,
        Err(e) => {
            return CString::new(format!("{{\"error\": \"Invalid WIF: {}\"}}", e))
                .unwrap()
                .into_raw();
        }
    };

    let network = match private_key.network {
        bitcoin::NetworkKind::Main => Network::Bitcoin,
        bitcoin::NetworkKind::Test => Network::Testnet,
    };

    let private_key_hex = hex::encode(private_key.inner.secret_bytes());

    match derive_taproot_address(&private_key_hex, network) {
        Ok((address, x_only_pubkey)) => {
            CString::new(format!(
                "{{\"success\": true, \"address\": \"{}\", \"x_only_pubkey\": \"{}\"}}",
                address, x_only_pubkey
            ))
            .unwrap()
            .into_raw()
        }
        Err(e) => CString::new(format!("{{\"error\": \"{}\"}}", e))
            .unwrap()
            .into_raw(),
    }
}
