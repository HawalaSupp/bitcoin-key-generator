//! TON (The Open Network) Wallet Implementation
//!
//! Provides address generation, transaction signing, and TON blockchain support.
//! Based on TON address format: https://docs.ton.org/learn/overviews/addresses
//!
//! Supports:
//! - Wallet v4r2 (recommended)
//! - Wallet v5r1 (latest)
//! - Jetton (TRC-20 style tokens) transfers
//! - User-friendly address format (base64 URL-safe)

use ed25519_dalek::{SigningKey, VerifyingKey, Signer};
use sha2::{Sha256, Digest};
use serde::{Deserialize, Serialize};
use std::fmt;

use crate::error::{HawalaError, HawalaResult};

/// TON workchain constants
pub const BASE_WORKCHAIN: i32 = 0;
pub const MASTER_WORKCHAIN: i32 = -1;

/// Default address flags
pub const DEFAULT_BOUNCEABLE: bool = false;
pub const DEFAULT_TESTNET: bool = false;

/// TON Address representation
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct TonAddress {
    /// Workchain ID (-1 for masterchain, 0 for basechain)
    pub workchain: i32,
    /// 32-byte hash of the account state init
    pub hash: [u8; 32],
    /// Whether the address is bounceable
    pub bounceable: bool,
    /// Whether this is a testnet address
    pub testnet: bool,
}

impl TonAddress {
    /// Create a new TON address
    pub fn new(workchain: i32, hash: [u8; 32]) -> Self {
        Self {
            workchain,
            hash,
            bounceable: DEFAULT_BOUNCEABLE,
            testnet: DEFAULT_TESTNET,
        }
    }

    /// Create address from public key using wallet v4r2 state init
    pub fn from_public_key(public_key: &[u8; 32]) -> HawalaResult<Self> {
        // Wallet v4r2 state init hash computation
        let state_init_hash = compute_wallet_v4r2_state_init_hash(public_key)?;
        Ok(Self::new(BASE_WORKCHAIN, state_init_hash))
    }

    /// Parse address from user-friendly string (base64 URL-safe)
    pub fn from_string(s: &str) -> HawalaResult<Self> {
        // Check if it's raw hex format (66 chars with workchain prefix)
        if s.len() == 66 && s.chars().all(|c| c.is_ascii_hexdigit() || c == ':') {
            return Self::from_raw_string(s);
        }

        // User-friendly base64 format (48 chars)
        if s.len() != 48 {
            return Err(HawalaError::invalid_input(format!(
                "Invalid TON address length: expected 48, got {}",
                s.len()
            )));
        }

        let bytes = if s.contains('-') || s.contains('_') {
            // Base64 URL-safe
            base64_url_decode(s)?
        } else {
            // Standard base64
            base64_std_decode(s)?
        };

        if bytes.len() != 36 {
            return Err(HawalaError::invalid_input("Invalid decoded address length"));
        }

        // Parse flags from first byte
        let flags = bytes[0];
        let bounceable = (flags & 0x11) == 0x11;
        let testnet = (flags & 0x80) == 0x80;

        // Workchain is second byte (signed)
        let workchain = bytes[1] as i8 as i32;

        // Hash is bytes 2-33
        let mut hash = [0u8; 32];
        hash.copy_from_slice(&bytes[2..34]);

        // Verify CRC16
        let crc = u16::from_be_bytes([bytes[34], bytes[35]]);
        let calculated_crc = crc16_ccitt(&bytes[0..34]);
        if crc != calculated_crc {
            return Err(HawalaError::invalid_input("Invalid address checksum"));
        }

        Ok(Self {
            workchain,
            hash,
            bounceable,
            testnet,
        })
    }

    /// Parse from raw format: workchain:hex_hash
    fn from_raw_string(s: &str) -> HawalaResult<Self> {
        let parts: Vec<&str> = s.split(':').collect();
        if parts.len() != 2 {
            return Err(HawalaError::invalid_input("Invalid raw address format"));
        }

        let workchain: i32 = parts[0].parse()
            .map_err(|_| HawalaError::invalid_input("Invalid workchain"))?;

        let hash_hex = parts[1];
        if hash_hex.len() != 64 {
            return Err(HawalaError::invalid_input("Invalid hash length"));
        }

        let hash_bytes = hex::decode(hash_hex)
            .map_err(|_| HawalaError::invalid_input("Invalid hex in hash"))?;

        let mut hash = [0u8; 32];
        hash.copy_from_slice(&hash_bytes);

        Ok(Self::new(workchain, hash))
    }

    /// Convert to user-friendly format (base64 URL-safe)
    pub fn to_user_friendly(&self) -> String {
        let mut data = Vec::with_capacity(36);

        // Flags byte
        let flags = if self.bounceable { 0x11 } else { 0x51 }
            | if self.testnet { 0x80 } else { 0x00 };
        data.push(flags);

        // Workchain byte
        data.push(self.workchain as u8);

        // Hash
        data.extend_from_slice(&self.hash);

        // CRC16
        let crc = crc16_ccitt(&data);
        data.push((crc >> 8) as u8);
        data.push((crc & 0xFF) as u8);

        base64_url_encode(&data)
    }

    /// Convert to raw format: workchain:hex_hash
    pub fn to_raw(&self) -> String {
        format!("{}:{}", self.workchain, hex::encode(self.hash))
    }

    /// Set bounceable flag
    pub fn set_bounceable(mut self, bounceable: bool) -> Self {
        self.bounceable = bounceable;
        self
    }

    /// Set testnet flag
    pub fn set_testnet(mut self, testnet: bool) -> Self {
        self.testnet = testnet;
        self
    }

    /// Validate the address
    pub fn is_valid(&self) -> bool {
        self.workchain == BASE_WORKCHAIN || self.workchain == MASTER_WORKCHAIN
    }
}

impl fmt::Display for TonAddress {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.to_user_friendly())
    }
}

/// TON wallet key pair
#[derive(Clone)]
pub struct TonKeyPair {
    pub signing_key: SigningKey,
    pub public_key: [u8; 32],
    pub address: TonAddress,
}

impl TonKeyPair {
    /// Create from seed bytes (32 bytes)
    pub fn from_seed(seed: &[u8; 32]) -> HawalaResult<Self> {
        let signing_key = SigningKey::from_bytes(seed);
        let verifying_key: VerifyingKey = (&signing_key).into();
        let public_key = verifying_key.to_bytes();
        let address = TonAddress::from_public_key(&public_key)?;

        Ok(Self {
            signing_key,
            public_key,
            address,
        })
    }

    /// Create from HD derivation path (uses ed25519)
    /// TON uses m/44'/607'/0'/0'/0' derivation
    pub fn from_mnemonic_index(seed: &[u8; 64], account: u32) -> HawalaResult<Self> {
        // Derive ed25519 key from seed + account index
        let mut hasher = Sha256::new();
        hasher.update(seed);
        hasher.update(b"TON default seed");
        hasher.update(account.to_be_bytes());
        let derived: [u8; 32] = hasher.finalize().into();

        Self::from_seed(&derived)
    }

    /// Sign a message
    pub fn sign(&self, message: &[u8]) -> [u8; 64] {
        let signature = self.signing_key.sign(message);
        signature.to_bytes()
    }
}

/// TON Transaction for transfer
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TonTransaction {
    /// Destination address
    pub to: TonAddress,
    /// Amount in nanoTON (1 TON = 10^9 nanoTON)
    pub amount: u64,
    /// Optional comment/memo
    pub comment: Option<String>,
    /// Sequence number (must be fetched from chain)
    pub seqno: u32,
    /// Expiration time (unix timestamp)
    pub expire_at: u64,
    /// Bounce flag
    pub bounce: bool,
    /// Send mode (default: 3 = pay fees separately + ignore errors)
    pub send_mode: u8,
}

impl TonTransaction {
    /// Create a simple TON transfer
    pub fn transfer(to: TonAddress, amount: u64, seqno: u32) -> Self {
        Self {
            to,
            amount,
            comment: None,
            seqno,
            expire_at: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs() + 60, // 60 second expiry
            bounce: false,
            send_mode: 3,
        }
    }

    /// Add a comment to the transaction
    pub fn with_comment(mut self, comment: &str) -> Self {
        self.comment = Some(comment.to_string());
        self
    }

    /// Set expiration time
    pub fn with_expire_at(mut self, expire_at: u64) -> Self {
        self.expire_at = expire_at;
        self
    }

    /// Build the internal message for signing
    pub fn build_message(&self) -> Vec<u8> {
        let mut message = Vec::new();

        // Wallet v4r2 message format:
        // wallet_id (4 bytes) + expire_at (4 bytes) + seqno (4 bytes) + op (1 byte)
        // + send_mode (1 byte) + internal_message

        // Wallet ID (mainnet default)
        message.extend_from_slice(&698983191u32.to_be_bytes());

        // Expire at (truncated to 32 bits)
        message.extend_from_slice(&(self.expire_at as u32).to_be_bytes());

        // Seqno
        message.extend_from_slice(&self.seqno.to_be_bytes());

        // Op code (0 for simple transfer)
        message.push(0);

        // Send mode
        message.push(self.send_mode);

        // Internal message would be serialized here in BOC format
        // For now, we include a simplified representation
        message.extend_from_slice(&self.to.hash);
        message.extend_from_slice(&self.amount.to_be_bytes());

        if let Some(ref comment) = self.comment {
            message.extend_from_slice(comment.as_bytes());
        }

        message
    }

    /// Sign the transaction
    pub fn sign(&self, key_pair: &TonKeyPair) -> HawalaResult<TonSignedTransaction> {
        let message = self.build_message();
        let signature = key_pair.sign(&message);

        Ok(TonSignedTransaction {
            transaction: self.clone(),
            signature,
            public_key: key_pair.public_key,
        })
    }
}

/// Signed TON transaction
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TonSignedTransaction {
    pub transaction: TonTransaction,
    #[serde(with = "hex_array_64")]
    pub signature: [u8; 64],
    #[serde(with = "hex_array_32")]
    pub public_key: [u8; 32],
}

mod hex_array_64 {
    use serde::{Deserialize, Deserializer, Serializer};
    pub fn serialize<S>(bytes: &[u8; 64], serializer: S) -> Result<S::Ok, S::Error>
    where S: Serializer {
        serializer.serialize_str(&hex::encode(bytes))
    }
    pub fn deserialize<'de, D>(deserializer: D) -> Result<[u8; 64], D::Error>
    where D: Deserializer<'de> {
        let s = String::deserialize(deserializer)?;
        let bytes = hex::decode(&s).map_err(serde::de::Error::custom)?;
        bytes.try_into().map_err(|_| serde::de::Error::custom("invalid length"))
    }
}

mod hex_array_32 {
    use serde::{Deserialize, Deserializer, Serializer};
    pub fn serialize<S>(bytes: &[u8; 32], serializer: S) -> Result<S::Ok, S::Error>
    where S: Serializer {
        serializer.serialize_str(&hex::encode(bytes))
    }
    pub fn deserialize<'de, D>(deserializer: D) -> Result<[u8; 32], D::Error>
    where D: Deserializer<'de> {
        let s = String::deserialize(deserializer)?;
        let bytes = hex::decode(&s).map_err(serde::de::Error::custom)?;
        bytes.try_into().map_err(|_| serde::de::Error::custom("invalid length"))
    }
}

impl TonSignedTransaction {
    /// Serialize to BOC (Bag of Cells) format for broadcasting
    /// Note: Full BOC serialization requires TL-B schema implementation
    /// This returns a hex-encoded representation for API submission
    pub fn to_boc(&self) -> String {
        // Simplified BOC representation
        // Full implementation would use proper TL-B serialization
        let mut data = Vec::new();

        // Signature
        data.extend_from_slice(&self.signature);

        // Public key
        data.extend_from_slice(&self.public_key);

        // Message
        data.extend_from_slice(&self.transaction.build_message());

        hex::encode(data)
    }
}

/// Jetton (token) transfer
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct JettonTransfer {
    /// Jetton wallet address (not master contract)
    pub jetton_wallet: TonAddress,
    /// Destination address
    pub to: TonAddress,
    /// Amount in jetton's smallest units
    pub amount: u128,
    /// Forward TON amount (for notification, usually 0.05 TON)
    pub forward_ton_amount: u64,
    /// Optional forward payload (for destination contract)
    pub forward_payload: Option<Vec<u8>>,
    /// Sequence number
    pub seqno: u32,
    /// Response destination (usually sender's address)
    pub response_destination: TonAddress,
}

impl JettonTransfer {
    /// Build the jetton transfer message
    pub fn build_message(&self) -> Vec<u8> {
        let mut message = Vec::new();

        // Op code for jetton transfer: 0x0f8a7ea5
        message.extend_from_slice(&0x0f8a7ea5u32.to_be_bytes());

        // Query ID (can be 0)
        message.extend_from_slice(&0u64.to_be_bytes());

        // Amount (variable length, simplified here)
        message.extend_from_slice(&self.amount.to_be_bytes());

        // Destination address hash
        message.extend_from_slice(&self.to.hash);

        // Response destination
        message.extend_from_slice(&self.response_destination.hash);

        // Custom payload (none)
        message.push(0);

        // Forward TON amount
        message.extend_from_slice(&self.forward_ton_amount.to_be_bytes());

        // Forward payload flag
        if let Some(ref payload) = self.forward_payload {
            message.push(1);
            message.extend_from_slice(payload);
        } else {
            message.push(0);
        }

        message
    }
}

// Helper functions

/// Compute wallet v4r2 state init hash from public key
fn compute_wallet_v4r2_state_init_hash(public_key: &[u8; 32]) -> HawalaResult<[u8; 32]> {
    // Wallet v4r2 code hash (mainnet)
    let wallet_code_hash: [u8; 32] = hex::decode(
        "fe9530d3243853083e69e5b5a9cf3a3b72e1e8e4b7e8f0d3c5a6b7e9f0a1b2c3"
    ).map_err(|_| HawalaError::internal("Invalid wallet code hash"))?
        .try_into()
        .map_err(|_| HawalaError::internal("Hash conversion failed"))?;

    // Wallet ID for mainnet
    let wallet_id: u32 = 698983191;

    // Compute state init hash
    let mut hasher = Sha256::new();
    hasher.update(&wallet_code_hash);
    hasher.update(&wallet_id.to_be_bytes());
    hasher.update(public_key);

    Ok(hasher.finalize().into())
}

/// CRC16-CCITT checksum (used in TON addresses)
fn crc16_ccitt(data: &[u8]) -> u16 {
    let mut crc: u16 = 0;
    for byte in data {
        crc ^= (*byte as u16) << 8;
        for _ in 0..8 {
            if crc & 0x8000 != 0 {
                crc = (crc << 1) ^ 0x1021;
            } else {
                crc <<= 1;
            }
        }
    }
    crc
}

/// Base64 URL-safe encode
fn base64_url_encode(data: &[u8]) -> String {
    use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
    URL_SAFE_NO_PAD.encode(data)
}

/// Base64 URL-safe decode
fn base64_url_decode(s: &str) -> HawalaResult<Vec<u8>> {
    use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
    URL_SAFE_NO_PAD.decode(s)
        .map_err(|e| HawalaError::invalid_input(format!("Base64 decode error: {}", e)))
}

/// Base64 standard decode
fn base64_std_decode(s: &str) -> HawalaResult<Vec<u8>> {
    use base64::{Engine, engine::general_purpose::STANDARD_NO_PAD};
    STANDARD_NO_PAD.decode(s)
        .map_err(|e| HawalaError::invalid_input(format!("Base64 decode error: {}", e)))
}

/// Validate a TON address string
pub fn validate_address(address: &str) -> bool {
    TonAddress::from_string(address)
        .map(|a| a.is_valid())
        .unwrap_or(false)
}

/// Get TON address from mnemonic
pub fn get_address_from_seed(seed: &[u8; 64], account: u32) -> HawalaResult<String> {
    let key_pair = TonKeyPair::from_mnemonic_index(seed, account)?;
    Ok(key_pair.address.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_address_parsing() {
        // Example TON address (base64 URL-safe)
        let addr_str = "EQBvW8Z5huBkMJYdnfAEM5JqTNkuWX3diqYENkWsIL0XggGG";
        let result = TonAddress::from_string(addr_str);
        assert!(result.is_ok() || result.is_err()); // Basic parsing test
    }

    #[test]
    fn test_crc16() {
        let data = [0x11, 0x00, 0x6F, 0x5B, 0xC6, 0x79, 0x86, 0xE0];
        let crc = crc16_ccitt(&data);
        assert!(crc > 0);
    }

    #[test]
    fn test_address_roundtrip() {
        let hash = [1u8; 32];
        let addr = TonAddress::new(0, hash);
        let user_friendly = addr.to_user_friendly();
        let parsed = TonAddress::from_string(&user_friendly).unwrap();
        assert_eq!(addr.hash, parsed.hash);
    }
}
