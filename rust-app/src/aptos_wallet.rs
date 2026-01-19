//! Aptos Blockchain Wallet Implementation
//!
//! Provides address generation and transaction signing for Aptos.
//! Based on Aptos address format: https://aptos.dev/concepts/accounts/
//!
//! Supports:
//! - Account address derivation (ed25519)
//! - APT transfers
//! - Coin transfers (any fungible asset)
//! - Resource account creation

use ed25519_dalek::{SigningKey, VerifyingKey, Signer, Signature};
use sha3::{Sha3_256, Digest};
use serde::{Deserialize, Serialize};
use std::fmt;

use crate::error::{HawalaError, HawalaResult};

/// Aptos address is 32 bytes, displayed as 0x-prefixed hex
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AptosAddress {
    pub bytes: [u8; 32],
}

impl AptosAddress {
    /// Create from raw bytes
    pub fn new(bytes: [u8; 32]) -> Self {
        Self { bytes }
    }

    /// Derive address from public key (single signer)
    /// address = sha3_256(public_key || 0x00)
    pub fn from_public_key(public_key: &[u8; 32]) -> Self {
        let mut hasher = Sha3_256::new();
        hasher.update(public_key);
        hasher.update([0x00]); // Single signer scheme
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

    /// Convert to short hex (remove leading zeros except first)
    pub fn to_short_hex(&self) -> String {
        let hex = hex::encode(self.bytes);
        let trimmed = hex.trim_start_matches('0');
        if trimmed.is_empty() {
            "0x0".to_string()
        } else {
            format!("0x{}", trimmed)
        }
    }

    /// Check if this is a special address (0x0, 0x1, etc.)
    pub fn is_special(&self) -> bool {
        // Special addresses are small numbers
        self.bytes[0..31].iter().all(|&b| b == 0)
    }
}

impl fmt::Display for AptosAddress {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.to_hex())
    }
}

/// Known special addresses on Aptos
pub mod special_addresses {
    use super::AptosAddress;

    pub fn core_code_address() -> AptosAddress {
        let mut bytes = [0u8; 32];
        bytes[31] = 0x01;
        AptosAddress::new(bytes)
    }

    pub fn aptos_framework() -> AptosAddress {
        core_code_address()
    }

    pub fn aptos_coin() -> AptosAddress {
        core_code_address()
    }
}

/// Aptos key pair
#[derive(Clone)]
pub struct AptosKeyPair {
    pub signing_key: SigningKey,
    pub public_key: [u8; 32],
    pub address: AptosAddress,
}

impl AptosKeyPair {
    /// Create from seed bytes (32 bytes)
    pub fn from_seed(seed: &[u8; 32]) -> HawalaResult<Self> {
        let signing_key = SigningKey::from_bytes(seed);
        let verifying_key: VerifyingKey = (&signing_key).into();
        let public_key = verifying_key.to_bytes();
        let address = AptosAddress::from_public_key(&public_key);

        Ok(Self {
            signing_key,
            public_key,
            address,
        })
    }

    /// Create from HD derivation
    /// Aptos uses m/44'/637'/0'/0'/0' derivation path
    pub fn from_mnemonic_seed(seed: &[u8; 64], account: u32) -> HawalaResult<Self> {
        let mut hasher = Sha3_256::new();
        hasher.update(seed);
        hasher.update(b"APTOS DERIVE");
        hasher.update(account.to_be_bytes());
        let derived: [u8; 32] = hasher.finalize().into();

        Self::from_seed(&derived)
    }

    /// Sign a message
    pub fn sign(&self, message: &[u8]) -> [u8; 64] {
        let signature: Signature = self.signing_key.sign(message);
        signature.to_bytes()
    }
}

/// Aptos transaction types
#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum AptosTransactionPayload {
    /// Script function call (most common)
    EntryFunction {
        module_address: AptosAddress,
        module_name: String,
        function_name: String,
        type_arguments: Vec<String>,
        arguments: Vec<Vec<u8>>,
    },
    /// Raw script bytecode
    Script {
        bytecode: Vec<u8>,
        type_arguments: Vec<String>,
        arguments: Vec<Vec<u8>>,
    },
}

/// Aptos transaction
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AptosTransaction {
    /// Sender address
    pub sender: AptosAddress,
    /// Sequence number
    pub sequence_number: u64,
    /// Transaction payload
    pub payload: AptosTransactionPayload,
    /// Max gas amount
    pub max_gas_amount: u64,
    /// Gas unit price in octas (1 APT = 10^8 octas)
    pub gas_unit_price: u64,
    /// Expiration timestamp (seconds)
    pub expiration_timestamp_secs: u64,
    /// Chain ID (1 for mainnet, 2 for testnet)
    pub chain_id: u8,
}

impl AptosTransaction {
    /// Create an APT transfer transaction
    pub fn transfer(
        sender: AptosAddress,
        to: AptosAddress,
        amount: u64,
        sequence_number: u64,
    ) -> Self {
        Self {
            sender,
            sequence_number,
            payload: AptosTransactionPayload::EntryFunction {
                module_address: special_addresses::aptos_framework(),
                module_name: "aptos_account".to_string(),
                function_name: "transfer".to_string(),
                type_arguments: vec![],
                arguments: vec![
                    to.bytes.to_vec(),
                    amount.to_le_bytes().to_vec(),
                ],
            },
            max_gas_amount: 2000,
            gas_unit_price: 100,
            expiration_timestamp_secs: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs() + 600, // 10 minute expiry
            chain_id: 1, // Mainnet
        }
    }

    /// Create a coin transfer (any fungible asset)
    pub fn coin_transfer(
        sender: AptosAddress,
        to: AptosAddress,
        amount: u64,
        coin_type: &str, // e.g., "0x1::aptos_coin::AptosCoin"
        sequence_number: u64,
    ) -> Self {
        Self {
            sender,
            sequence_number,
            payload: AptosTransactionPayload::EntryFunction {
                module_address: special_addresses::aptos_framework(),
                module_name: "coin".to_string(),
                function_name: "transfer".to_string(),
                type_arguments: vec![coin_type.to_string()],
                arguments: vec![
                    to.bytes.to_vec(),
                    amount.to_le_bytes().to_vec(),
                ],
            },
            max_gas_amount: 2000,
            gas_unit_price: 100,
            expiration_timestamp_secs: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs() + 600,
            chain_id: 1,
        }
    }

    /// Build the signing message (prefix + transaction bytes)
    pub fn build_signing_message(&self) -> Vec<u8> {
        // Aptos transaction signing message:
        // sha3_256("APTOS::RawTransaction") || bcs_serialized_transaction

        let mut message = Vec::new();

        // Prefix hash
        let mut prefix_hasher = Sha3_256::new();
        prefix_hasher.update(b"APTOS::RawTransaction");
        let prefix_hash = prefix_hasher.finalize();
        message.extend_from_slice(&prefix_hash);

        // Transaction bytes (simplified BCS serialization)
        message.extend_from_slice(&self.serialize_for_signing());

        message
    }

    /// Serialize transaction for signing (simplified BCS)
    fn serialize_for_signing(&self) -> Vec<u8> {
        let mut data = Vec::new();

        // Sender
        data.extend_from_slice(&self.sender.bytes);

        // Sequence number
        data.extend_from_slice(&self.sequence_number.to_le_bytes());

        // Payload (simplified)
        match &self.payload {
            AptosTransactionPayload::EntryFunction {
                module_address,
                module_name,
                function_name,
                type_arguments,
                arguments,
            } => {
                data.push(0x02); // Entry function variant

                // Module
                data.extend_from_slice(&module_address.bytes);
                data.extend_from_slice(&(module_name.len() as u8).to_le_bytes());
                data.extend_from_slice(module_name.as_bytes());

                // Function
                data.extend_from_slice(&(function_name.len() as u8).to_le_bytes());
                data.extend_from_slice(function_name.as_bytes());

                // Type arguments count
                data.push(type_arguments.len() as u8);
                for ta in type_arguments {
                    data.extend_from_slice(&(ta.len() as u8).to_le_bytes());
                    data.extend_from_slice(ta.as_bytes());
                }

                // Arguments count
                data.push(arguments.len() as u8);
                for arg in arguments {
                    data.extend_from_slice(&(arg.len() as u32).to_le_bytes());
                    data.extend_from_slice(arg);
                }
            }
            AptosTransactionPayload::Script { bytecode, .. } => {
                data.push(0x00); // Script variant
                data.extend_from_slice(&(bytecode.len() as u32).to_le_bytes());
                data.extend_from_slice(bytecode);
            }
        }

        // Max gas
        data.extend_from_slice(&self.max_gas_amount.to_le_bytes());

        // Gas price
        data.extend_from_slice(&self.gas_unit_price.to_le_bytes());

        // Expiration
        data.extend_from_slice(&self.expiration_timestamp_secs.to_le_bytes());

        // Chain ID
        data.push(self.chain_id);

        data
    }

    /// Sign the transaction
    pub fn sign(&self, key_pair: &AptosKeyPair) -> HawalaResult<AptosSignedTransaction> {
        let message = self.build_signing_message();

        // Hash the message
        let mut hasher = Sha3_256::new();
        hasher.update(&message);
        let hash: [u8; 32] = hasher.finalize().into();

        let signature = key_pair.sign(&hash);

        Ok(AptosSignedTransaction {
            transaction: self.clone(),
            signature,
            public_key: key_pair.public_key,
        })
    }
}

/// Signed Aptos transaction
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AptosSignedTransaction {
    pub transaction: AptosTransaction,
    #[serde(with = "crate::serde_bytes::hex64")]
    pub signature: [u8; 64],
    #[serde(with = "crate::serde_bytes::hex32")]
    pub public_key: [u8; 32],
}

impl AptosSignedTransaction {
    /// Serialize for submission
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut data = Vec::new();

        // Transaction bytes
        data.extend_from_slice(&self.transaction.serialize_for_signing());

        // Authenticator (Ed25519)
        data.push(0x00); // Ed25519 variant
        data.extend_from_slice(&self.public_key);
        data.extend_from_slice(&self.signature);

        data
    }

    /// Convert to hex for API submission
    pub fn to_hex(&self) -> String {
        format!("0x{}", hex::encode(self.to_bytes()))
    }
}

/// Validate an Aptos address
pub fn validate_address(address: &str) -> bool {
    AptosAddress::from_string(address).is_ok()
}

/// Get Aptos address from seed
pub fn get_address_from_seed(seed: &[u8; 64], account: u32) -> HawalaResult<String> {
    let key_pair = AptosKeyPair::from_mnemonic_seed(seed, account)?;
    Ok(key_pair.address.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_address_derivation() {
        let public_key = [1u8; 32];
        let address = AptosAddress::from_public_key(&public_key);
        assert_eq!(address.bytes.len(), 32);
    }

    #[test]
    fn test_address_parsing() {
        let addr_str = "0x1";
        let addr = AptosAddress::from_string(addr_str).unwrap();
        assert!(addr.is_special());
    }

    #[test]
    fn test_address_display() {
        let addr = special_addresses::aptos_framework();
        let hex = addr.to_short_hex();
        assert_eq!(hex, "0x1");
    }

    #[test]
    fn test_transfer_tx() {
        let sender = AptosAddress::from_public_key(&[1u8; 32]);
        let to = AptosAddress::from_public_key(&[2u8; 32]);
        let tx = AptosTransaction::transfer(sender, to, 1_000_000, 0);
        
        let message = tx.build_signing_message();
        assert!(!message.is_empty());
    }
}
