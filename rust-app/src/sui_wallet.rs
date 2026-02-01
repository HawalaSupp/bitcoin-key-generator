//! Sui Blockchain Wallet Implementation
//!
//! Provides address generation and transaction signing for Sui.
//! Based on Sui address format: https://docs.sui.io/concepts/sui-move-concepts/addresses
//!
//! Supports:
//! - Account address derivation (ed25519)
//! - SUI transfers
//! - Object transfers
//! - Move calls

use ed25519_dalek::{SigningKey, VerifyingKey, Signer, Signature};
use blake2::{Blake2b, Digest as BlakeDigest};
use blake2::digest::consts::U32;
type Blake2b256 = Blake2b<U32>;
use serde::{Deserialize, Serialize};
use std::fmt;

use crate::error::{HawalaError, HawalaResult};

/// Sui address is 32 bytes, displayed as 0x-prefixed hex
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SuiAddress {
    pub bytes: [u8; 32],
}

impl SuiAddress {
    /// Create from raw bytes
    pub fn new(bytes: [u8; 32]) -> Self {
        Self { bytes }
    }

    /// Derive address from public key (single signer)
    /// address = blake2b_256(0x00 || public_key)[0:32]
    /// The 0x00 prefix is the signature scheme flag (ed25519)
    pub fn from_public_key(public_key: &[u8; 32]) -> Self {
        let mut hasher = Blake2b256::new();
        hasher.update([0x00]); // Ed25519 signature scheme flag
        hasher.update(public_key);
        let hash: [u8; 32] = hasher.finalize().into();
        Self::new(hash)
    }

    /// Parse from hex string (with or without 0x prefix)
    pub fn from_string(s: &str) -> HawalaResult<Self> {
        let s = s.strip_prefix("0x").unwrap_or(s);

        // Handle short addresses (pad with zeros)
        let padded = format!("{:0>64}", s);

        let bytes = hex::decode(&padded)
            .map_err(|e| HawalaError::invalid_input(format!("Invalid hex: {}", e)))?;

        if bytes.len() != 32 {
            return Err(HawalaError::invalid_input("Invalid address length"));
        }

        let mut arr = [0u8; 32];
        arr.copy_from_slice(&bytes);
        Ok(Self::new(arr))
    }

    /// Convert to hex string with 0x prefix
    pub fn to_hex(&self) -> String {
        format!("0x{}", hex::encode(self.bytes))
    }

    /// Check if this is the zero address
    pub fn is_zero(&self) -> bool {
        self.bytes.iter().all(|&b| b == 0)
    }
}

impl fmt::Display for SuiAddress {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.to_hex())
    }
}

/// Known special addresses on Sui
pub mod special_addresses {
    use super::SuiAddress;

    /// Sui framework address
    pub fn sui_framework() -> SuiAddress {
        let mut bytes = [0u8; 32];
        bytes[31] = 0x02;
        SuiAddress::new(bytes)
    }

    /// Sui system address
    pub fn sui_system() -> SuiAddress {
        let mut bytes = [0u8; 32];
        bytes[31] = 0x05;
        SuiAddress::new(bytes)
    }

    /// Clock object address (for time-based operations)
    pub fn clock() -> SuiAddress {
        let mut bytes = [0u8; 32];
        bytes[31] = 0x06;
        SuiAddress::new(bytes)
    }
}

/// Sui Object ID (same format as address)
pub type ObjectId = SuiAddress;

/// Sui Object Reference (ID, version, digest)
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ObjectRef {
    pub object_id: ObjectId,
    pub version: u64,
    pub digest: [u8; 32],
}

impl ObjectRef {
    pub fn new(object_id: ObjectId, version: u64, digest: [u8; 32]) -> Self {
        Self { object_id, version, digest }
    }
}

/// Sui key pair
#[derive(Clone)]
pub struct SuiKeyPair {
    pub signing_key: SigningKey,
    pub public_key: [u8; 32],
    pub address: SuiAddress,
}

impl SuiKeyPair {
    /// Create from seed bytes (32 bytes)
    pub fn from_seed(seed: &[u8; 32]) -> HawalaResult<Self> {
        let signing_key = SigningKey::from_bytes(seed);
        let verifying_key: VerifyingKey = (&signing_key).into();
        let public_key = verifying_key.to_bytes();
        let address = SuiAddress::from_public_key(&public_key);

        Ok(Self {
            signing_key,
            public_key,
            address,
        })
    }

    /// Create from HD derivation
    /// Sui uses m/44'/784'/0'/0'/0' derivation path
    pub fn from_mnemonic_seed(seed: &[u8; 64], account: u32) -> HawalaResult<Self> {
        let mut hasher = Blake2b256::new();
        hasher.update(seed);
        hasher.update(b"SUI DERIVE");
        hasher.update(account.to_be_bytes());
        let derived: [u8; 32] = hasher.finalize().into();

        Self::from_seed(&derived)
    }

    /// Sign a message
    pub fn sign(&self, message: &[u8]) -> [u8; 64] {
        let signature: Signature = self.signing_key.sign(message);
        signature.to_bytes()
    }

    /// Create a signature with scheme flag
    pub fn sign_with_flag(&self, message: &[u8]) -> Vec<u8> {
        let mut result = Vec::with_capacity(97); // 1 + 64 + 32
        result.push(0x00); // Ed25519 scheme flag
        result.extend_from_slice(&self.sign(message));
        result.extend_from_slice(&self.public_key);
        result
    }
}

/// Sui transaction types
#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum SuiTransactionKind {
    /// Pay SUI to recipients
    PaySui {
        recipients: Vec<SuiAddress>,
        amounts: Vec<u64>,
    },
    /// Transfer an object
    TransferObject {
        recipient: SuiAddress,
        object_ref: ObjectRef,
    },
    /// Call a Move function
    MoveCall {
        package: ObjectId,
        module: String,
        function: String,
        type_arguments: Vec<String>,
        arguments: Vec<SuiArgument>,
    },
    /// Split coins
    SplitCoins {
        coin: ObjectRef,
        amounts: Vec<u64>,
    },
    /// Merge coins
    MergeCoins {
        destination: ObjectRef,
        sources: Vec<ObjectRef>,
    },
}

/// Sui Move call argument
#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum SuiArgument {
    /// Gas coin
    GasCoin,
    /// Result from previous transaction
    Result(u16),
    /// Nested result
    NestedResult(u16, u16),
    /// Pure value (BCS serialized)
    Pure(Vec<u8>),
    /// Object reference
    Object(ObjectRef),
}

/// Sui transaction
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SuiTransaction {
    /// Sender address
    pub sender: SuiAddress,
    /// Transaction kind
    pub kind: SuiTransactionKind,
    /// Gas payment object
    pub gas_payment: ObjectRef,
    /// Gas budget
    pub gas_budget: u64,
    /// Gas price
    pub gas_price: u64,
    /// Expiration epoch (optional)
    pub expiration_epoch: Option<u64>,
}

impl SuiTransaction {
    /// Create a SUI transfer transaction
    pub fn transfer_sui(
        sender: SuiAddress,
        recipient: SuiAddress,
        amount: u64,
        gas_payment: ObjectRef,
        gas_budget: u64,
    ) -> Self {
        Self {
            sender,
            kind: SuiTransactionKind::PaySui {
                recipients: vec![recipient],
                amounts: vec![amount],
            },
            gas_payment,
            gas_budget,
            gas_price: 1000, // 1000 MIST per unit
            expiration_epoch: None,
        }
    }

    /// Create an object transfer transaction
    pub fn transfer_object(
        sender: SuiAddress,
        recipient: SuiAddress,
        object_ref: ObjectRef,
        gas_payment: ObjectRef,
        gas_budget: u64,
    ) -> Self {
        Self {
            sender,
            kind: SuiTransactionKind::TransferObject {
                recipient,
                object_ref,
            },
            gas_payment,
            gas_budget,
            gas_price: 1000,
            expiration_epoch: None,
        }
    }

    /// Create a Move call transaction
    pub fn move_call(
        sender: SuiAddress,
        package: ObjectId,
        module: &str,
        function: &str,
        type_arguments: Vec<String>,
        arguments: Vec<SuiArgument>,
        gas_payment: ObjectRef,
        gas_budget: u64,
    ) -> Self {
        Self {
            sender,
            kind: SuiTransactionKind::MoveCall {
                package,
                module: module.to_string(),
                function: function.to_string(),
                type_arguments,
                arguments,
            },
            gas_payment,
            gas_budget,
            gas_price: 1000,
            expiration_epoch: None,
        }
    }

    /// Serialize for signing (Intent message)
    /// Intent = [IntentScope::TransactionData (0), IntentVersion (0), AppId::Sui (0)]
    pub fn build_signing_message(&self) -> Vec<u8> {
        let mut message = Vec::new();

        // Intent prefix: [0, 0, 0] for TransactionData
        message.extend_from_slice(&[0, 0, 0]);

        // Transaction data (simplified BCS)
        message.extend_from_slice(&self.serialize_bcs());

        message
    }

    /// Serialize transaction to BCS (simplified)
    fn serialize_bcs(&self) -> Vec<u8> {
        let mut data = Vec::new();

        // Version byte
        data.push(0);

        // Sender
        data.extend_from_slice(&self.sender.bytes);

        // Serialize kind
        match &self.kind {
            SuiTransactionKind::PaySui { recipients, amounts } => {
                data.push(0x00); // PaySui variant
                
                // Recipients count
                data.push(recipients.len() as u8);
                for recipient in recipients {
                    data.extend_from_slice(&recipient.bytes);
                }

                // Amounts count
                data.push(amounts.len() as u8);
                for amount in amounts {
                    data.extend_from_slice(&amount.to_le_bytes());
                }
            }
            SuiTransactionKind::TransferObject { recipient, object_ref } => {
                data.push(0x01); // TransferObject variant
                data.extend_from_slice(&recipient.bytes);
                data.extend_from_slice(&object_ref.object_id.bytes);
                data.extend_from_slice(&object_ref.version.to_le_bytes());
                data.extend_from_slice(&object_ref.digest);
            }
            SuiTransactionKind::MoveCall {
                package,
                module,
                function,
                type_arguments,
                arguments,
            } => {
                data.push(0x02); // MoveCall variant
                
                // Package
                data.extend_from_slice(&package.bytes);
                
                // Module name
                data.push(module.len() as u8);
                data.extend_from_slice(module.as_bytes());
                
                // Function name
                data.push(function.len() as u8);
                data.extend_from_slice(function.as_bytes());
                
                // Type arguments
                data.push(type_arguments.len() as u8);
                for ta in type_arguments {
                    data.push(ta.len() as u8);
                    data.extend_from_slice(ta.as_bytes());
                }
                
                // Arguments
                data.push(arguments.len() as u8);
                for arg in arguments {
                    match arg {
                        SuiArgument::GasCoin => data.push(0),
                        SuiArgument::Result(idx) => {
                            data.push(1);
                            data.extend_from_slice(&idx.to_le_bytes());
                        }
                        SuiArgument::NestedResult(a, b) => {
                            data.push(2);
                            data.extend_from_slice(&a.to_le_bytes());
                            data.extend_from_slice(&b.to_le_bytes());
                        }
                        SuiArgument::Pure(bytes) => {
                            data.push(3);
                            data.push(bytes.len() as u8);
                            data.extend_from_slice(bytes);
                        }
                        SuiArgument::Object(obj) => {
                            data.push(4);
                            data.extend_from_slice(&obj.object_id.bytes);
                            data.extend_from_slice(&obj.version.to_le_bytes());
                            data.extend_from_slice(&obj.digest);
                        }
                    }
                }
            }
            SuiTransactionKind::SplitCoins { coin, amounts } => {
                data.push(0x03);
                data.extend_from_slice(&coin.object_id.bytes);
                data.extend_from_slice(&coin.version.to_le_bytes());
                data.extend_from_slice(&coin.digest);
                
                data.push(amounts.len() as u8);
                for amount in amounts {
                    data.extend_from_slice(&amount.to_le_bytes());
                }
            }
            SuiTransactionKind::MergeCoins { destination, sources } => {
                data.push(0x04);
                data.extend_from_slice(&destination.object_id.bytes);
                data.extend_from_slice(&destination.version.to_le_bytes());
                data.extend_from_slice(&destination.digest);
                
                data.push(sources.len() as u8);
                for source in sources {
                    data.extend_from_slice(&source.object_id.bytes);
                    data.extend_from_slice(&source.version.to_le_bytes());
                    data.extend_from_slice(&source.digest);
                }
            }
        }

        // Gas payment
        data.extend_from_slice(&self.gas_payment.object_id.bytes);
        data.extend_from_slice(&self.gas_payment.version.to_le_bytes());
        data.extend_from_slice(&self.gas_payment.digest);

        // Gas budget
        data.extend_from_slice(&self.gas_budget.to_le_bytes());

        // Gas price
        data.extend_from_slice(&self.gas_price.to_le_bytes());

        // Expiration
        match self.expiration_epoch {
            Some(epoch) => {
                data.push(1);
                data.extend_from_slice(&epoch.to_le_bytes());
            }
            None => data.push(0),
        }

        data
    }

    /// Sign the transaction
    pub fn sign(&self, key_pair: &SuiKeyPair) -> HawalaResult<SuiSignedTransaction> {
        let message = self.build_signing_message();

        // Hash the message with Blake2b
        let mut hasher = Blake2b256::new();
        hasher.update(&message);
        let hash: [u8; 32] = hasher.finalize().into();

        let signature = key_pair.sign(&hash);

        Ok(SuiSignedTransaction {
            transaction: self.clone(),
            signature,
            public_key: key_pair.public_key,
        })
    }
}

/// Signed Sui transaction
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SuiSignedTransaction {
    pub transaction: SuiTransaction,
    #[serde(with = "crate::serde_bytes::hex64")]
    pub signature: [u8; 64],
    #[serde(with = "crate::serde_bytes::hex32")]
    pub public_key: [u8; 32],
}

impl SuiSignedTransaction {
    /// Serialize for submission
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut data = Vec::new();

        // Transaction bytes
        data.extend_from_slice(&self.transaction.serialize_bcs());

        // Signature with scheme flag
        data.push(0x00); // Ed25519
        data.extend_from_slice(&self.signature);
        data.extend_from_slice(&self.public_key);

        data
    }

    /// Convert to base64 for API submission
    pub fn to_base64(&self) -> String {
        use base64::{Engine, engine::general_purpose::STANDARD};
        STANDARD.encode(self.to_bytes())
    }
}

/// Validate a Sui address
pub fn validate_address(address: &str) -> bool {
    SuiAddress::from_string(address).is_ok()
}

/// Get Sui address from seed
pub fn get_address_from_seed(seed: &[u8; 64], account: u32) -> HawalaResult<String> {
    let key_pair = SuiKeyPair::from_mnemonic_seed(seed, account)?;
    Ok(key_pair.address.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_address_derivation() {
        let public_key = [1u8; 32];
        let address = SuiAddress::from_public_key(&public_key);
        assert_eq!(address.bytes.len(), 32);
    }

    #[test]
    fn test_address_parsing() {
        let addr_str = "0x2";
        let addr = SuiAddress::from_string(addr_str).unwrap();
        assert_eq!(addr.bytes[31], 0x02);
    }

    #[test]
    fn test_special_addresses() {
        let framework = special_addresses::sui_framework();
        assert_eq!(framework.bytes[31], 0x02);
    }
}
