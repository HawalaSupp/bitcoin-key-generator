//! EIP-7702 Type Definitions
//!
//! Core types for EIP-7702 account delegation transactions.

use serde::{Deserialize, Serialize};

/// EIP-7702 Transaction type identifier
pub const EIP7702_TX_TYPE: u8 = 0x04;

/// Magic byte for authorization signing (per EIP-7702 spec)
pub const AUTHORIZATION_MAGIC: u8 = 0x05;

/// An EIP-7702 authorization tuple
/// 
/// Authorizes an EOA to delegate to a contract address for the transaction.
/// The authorization is signed by the EOA owner.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Authorization {
    /// Chain ID for replay protection
    pub chain_id: u64,
    
    /// Contract address to delegate to
    pub address: [u8; 20],
    
    /// Nonce of the authorizing account (for replay protection)
    pub nonce: u64,
    
    /// Signature y_parity (0 or 1)
    pub y_parity: u8,
    
    /// Signature r value (32 bytes)
    pub r: [u8; 32],
    
    /// Signature s value (32 bytes)
    pub s: [u8; 32],
}

impl Authorization {
    /// Create a new unsigned authorization
    pub fn new(chain_id: u64, address: [u8; 20], nonce: u64) -> Self {
        Self {
            chain_id,
            address,
            nonce,
            y_parity: 0,
            r: [0u8; 32],
            s: [0u8; 32],
        }
    }
    
    /// Create authorization with signature
    pub fn with_signature(
        chain_id: u64,
        address: [u8; 20],
        nonce: u64,
        y_parity: u8,
        r: [u8; 32],
        s: [u8; 32],
    ) -> Self {
        Self {
            chain_id,
            address,
            nonce,
            y_parity,
            r,
            s,
        }
    }
    
    /// Check if authorization is signed
    pub fn is_signed(&self) -> bool {
        self.r != [0u8; 32] || self.s != [0u8; 32]
    }
    
    /// Get the address as hex string
    pub fn address_hex(&self) -> String {
        format!("0x{}", hex::encode(self.address))
    }
    
    /// Get the 65-byte signature (r || s || v)
    pub fn signature_bytes(&self) -> [u8; 65] {
        let mut sig = [0u8; 65];
        sig[..32].copy_from_slice(&self.r);
        sig[32..64].copy_from_slice(&self.s);
        sig[64] = self.y_parity + 27;
        sig
    }
}

/// Access list entry (address + storage keys)
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AccessListEntry {
    /// Address
    pub address: [u8; 20],
    
    /// Storage keys
    pub storage_keys: Vec<[u8; 32]>,
}

/// EIP-7702 Transaction
/// 
/// Transaction type 0x04 with authorization list
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Eip7702Transaction {
    /// Chain ID
    pub chain_id: u64,
    
    /// Nonce
    pub nonce: u64,
    
    /// Max priority fee per gas (tip)
    pub max_priority_fee_per_gas: u128,
    
    /// Max fee per gas
    pub max_fee_per_gas: u128,
    
    /// Gas limit
    pub gas_limit: u64,
    
    /// Destination address (None for contract creation)
    pub to: Option<[u8; 20]>,
    
    /// Value in wei
    pub value: u128,
    
    /// Call data
    pub data: Vec<u8>,
    
    /// Access list (EIP-2930)
    pub access_list: Vec<AccessListEntry>,
    
    /// Authorization list (EIP-7702)
    pub authorization_list: Vec<Authorization>,
}

impl Eip7702Transaction {
    /// Create a new EIP-7702 transaction
    pub fn new(chain_id: u64) -> Self {
        Self {
            chain_id,
            nonce: 0,
            max_priority_fee_per_gas: 0,
            max_fee_per_gas: 0,
            gas_limit: 21000,
            to: None,
            value: 0,
            data: Vec::new(),
            access_list: Vec::new(),
            authorization_list: Vec::new(),
        }
    }
    
    /// Set the nonce
    pub fn with_nonce(mut self, nonce: u64) -> Self {
        self.nonce = nonce;
        self
    }
    
    /// Set max priority fee per gas
    pub fn with_max_priority_fee(mut self, fee: u128) -> Self {
        self.max_priority_fee_per_gas = fee;
        self
    }
    
    /// Set max fee per gas
    pub fn with_max_fee(mut self, fee: u128) -> Self {
        self.max_fee_per_gas = fee;
        self
    }
    
    /// Set gas limit
    pub fn with_gas_limit(mut self, limit: u64) -> Self {
        self.gas_limit = limit;
        self
    }
    
    /// Set destination address
    pub fn with_to(mut self, to: [u8; 20]) -> Self {
        self.to = Some(to);
        self
    }
    
    /// Set value
    pub fn with_value(mut self, value: u128) -> Self {
        self.value = value;
        self
    }
    
    /// Set call data
    pub fn with_data(mut self, data: Vec<u8>) -> Self {
        self.data = data;
        self
    }
    
    /// Add an access list entry
    pub fn add_access_list_entry(mut self, entry: AccessListEntry) -> Self {
        self.access_list.push(entry);
        self
    }
    
    /// Add an authorization
    pub fn add_authorization(mut self, auth: Authorization) -> Self {
        self.authorization_list.push(auth);
        self
    }
    
    /// Set authorization list
    pub fn with_authorizations(mut self, auths: Vec<Authorization>) -> Self {
        self.authorization_list = auths;
        self
    }
}

/// Signed EIP-7702 Transaction
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignedEip7702Transaction {
    /// The transaction
    pub tx: Eip7702Transaction,
    
    /// Signature y_parity
    pub y_parity: u8,
    
    /// Signature r value
    pub r: [u8; 32],
    
    /// Signature s value
    pub s: [u8; 32],
}

impl SignedEip7702Transaction {
    /// Get the 65-byte signature
    pub fn signature_bytes(&self) -> [u8; 65] {
        let mut sig = [0u8; 65];
        sig[..32].copy_from_slice(&self.r);
        sig[32..64].copy_from_slice(&self.s);
        sig[64] = self.y_parity + 27;
        sig
    }
}

/// Error types for EIP-7702 operations
#[derive(Debug, thiserror::Error)]
pub enum Eip7702Error {
    #[error("Invalid private key: {0}")]
    InvalidPrivateKey(String),
    
    #[error("Invalid address: {0}")]
    InvalidAddress(String),
    
    #[error("Invalid signature: {0}")]
    InvalidSignature(String),
    
    #[error("RLP encoding error: {0}")]
    RlpError(String),
    
    #[error("Authorization not signed")]
    UnsignedAuthorization,
    
    #[error("Empty authorization list")]
    EmptyAuthorizationList,
    
    #[error("Chain ID mismatch")]
    ChainIdMismatch,
    
    #[error("Signing error: {0}")]
    SigningError(String),
    
    #[error("Signature error: {0}")]
    SignatureError(String),
}

pub type Eip7702Result<T> = Result<T, Eip7702Error>;
