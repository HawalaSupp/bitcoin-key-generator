//! Ethereum Pre-Image Hashing
//!
//! Generates signing hashes for Ethereum transactions.
//! Supports Legacy, EIP-2930 (Access Lists), EIP-1559 (Fee Market), and EIP-7702.

use super::{PreImageHash, PreImageError, PreImageResult, SigningAlgorithm};
use serde::{Deserialize, Serialize};
use tiny_keccak::{Hasher, Keccak};

/// Ethereum transaction types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EthereumTxType {
    /// Legacy transaction (pre-EIP-2718)
    Legacy,
    /// EIP-2930: Access list transaction (type 0x01)
    AccessList,
    /// EIP-1559: Fee market transaction (type 0x02)
    FeeMarket,
    /// EIP-7702: Account delegation transaction (type 0x04)
    AccountDelegation,
}

impl EthereumTxType {
    pub fn type_byte(&self) -> Option<u8> {
        match self {
            Self::Legacy => None,
            Self::AccessList => Some(0x01),
            Self::FeeMarket => Some(0x02),
            Self::AccountDelegation => Some(0x04),
        }
    }
}

/// Access list entry (EIP-2930)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccessListEntry {
    /// Contract address
    pub address: [u8; 20],
    /// Storage keys
    pub storage_keys: Vec<[u8; 32]>,
}

/// EIP-7702 Authorization tuple
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Eip7702Auth {
    /// Chain ID
    pub chain_id: u64,
    /// Contract address to delegate to
    pub address: [u8; 20],
    /// Authorization nonce
    pub nonce: u64,
}

/// Unsigned Ethereum transaction
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UnsignedEthereumTransaction {
    /// Transaction type
    pub tx_type: EthereumTxType,
    /// Chain ID
    pub chain_id: u64,
    /// Sender nonce
    pub nonce: u64,
    /// Gas price (Legacy & EIP-2930)
    pub gas_price: Option<u128>,
    /// Max priority fee per gas (EIP-1559)
    pub max_priority_fee_per_gas: Option<u128>,
    /// Max fee per gas (EIP-1559)
    pub max_fee_per_gas: Option<u128>,
    /// Gas limit
    pub gas_limit: u64,
    /// Recipient address (None for contract creation)
    pub to: Option<[u8; 20]>,
    /// Value in wei
    pub value: u128,
    /// Transaction data
    pub data: Vec<u8>,
    /// Access list (EIP-2930, EIP-1559, EIP-7702)
    pub access_list: Option<Vec<AccessListEntry>>,
    /// EIP-7702 authorization list
    pub authorization_list: Option<Vec<Eip7702Auth>>,
    /// Derivation path for signing key
    pub derivation_path: Option<String>,
}

/// Get the signing hash for an Ethereum transaction
pub fn get_ethereum_signing_hash(
    tx: &UnsignedEthereumTransaction,
) -> PreImageResult<PreImageHash> {
    let hash = match tx.tx_type {
        EthereumTxType::Legacy => get_legacy_hash(tx)?,
        EthereumTxType::AccessList => get_eip2930_hash(tx)?,
        EthereumTxType::FeeMarket => get_eip1559_hash(tx)?,
        EthereumTxType::AccountDelegation => get_eip7702_hash(tx)?,
    };
    
    let signer_id = tx.derivation_path.clone()
        .unwrap_or_else(|| "ethereum".to_string());
    
    let description = format!(
        "Ethereum {:?} tx: {} wei to {}",
        tx.tx_type,
        tx.value,
        tx.to.map(|a| hex::encode(a))
            .unwrap_or_else(|| "contract creation".to_string())
    );
    
    Ok(PreImageHash::new(hash, signer_id, SigningAlgorithm::Secp256k1Ecdsa)
        .with_description(description))
}

/// Get signing hash for Legacy transaction
fn get_legacy_hash(tx: &UnsignedEthereumTransaction) -> PreImageResult<[u8; 32]> {
    let gas_price = tx.gas_price
        .ok_or_else(|| PreImageError::MissingField("gas_price".to_string()))?;
    
    // RLP encode: [nonce, gasPrice, gasLimit, to, value, data, chainId, 0, 0]
    // For EIP-155 replay protection
    let mut items = Vec::new();
    
    items.push(rlp_encode_u64(tx.nonce));
    items.push(rlp_encode_u128(gas_price));
    items.push(rlp_encode_u64(tx.gas_limit));
    items.push(rlp_encode_address(tx.to));
    items.push(rlp_encode_u128(tx.value));
    items.push(rlp_encode_bytes(&tx.data));
    items.push(rlp_encode_u64(tx.chain_id));
    items.push(rlp_encode_u64(0)); // v placeholder
    items.push(rlp_encode_u64(0)); // r placeholder
    
    let encoded = rlp_encode_list(&items);
    Ok(keccak256(&encoded))
}

/// Get signing hash for EIP-2930 transaction
fn get_eip2930_hash(tx: &UnsignedEthereumTransaction) -> PreImageResult<[u8; 32]> {
    let gas_price = tx.gas_price
        .ok_or_else(|| PreImageError::MissingField("gas_price".to_string()))?;
    let access_list = tx.access_list.as_ref()
        .ok_or_else(|| PreImageError::MissingField("access_list".to_string()))?;
    
    // RLP encode: 0x01 || RLP([chainId, nonce, gasPrice, gasLimit, to, value, data, accessList])
    let mut items = Vec::new();
    
    items.push(rlp_encode_u64(tx.chain_id));
    items.push(rlp_encode_u64(tx.nonce));
    items.push(rlp_encode_u128(gas_price));
    items.push(rlp_encode_u64(tx.gas_limit));
    items.push(rlp_encode_address(tx.to));
    items.push(rlp_encode_u128(tx.value));
    items.push(rlp_encode_bytes(&tx.data));
    items.push(rlp_encode_access_list(access_list));
    
    let rlp_data = rlp_encode_list(&items);
    
    // Prepend type byte
    let mut typed_data = vec![0x01];
    typed_data.extend_from_slice(&rlp_data);
    
    Ok(keccak256(&typed_data))
}

/// Get signing hash for EIP-1559 transaction
fn get_eip1559_hash(tx: &UnsignedEthereumTransaction) -> PreImageResult<[u8; 32]> {
    let max_priority = tx.max_priority_fee_per_gas
        .ok_or_else(|| PreImageError::MissingField("max_priority_fee_per_gas".to_string()))?;
    let max_fee = tx.max_fee_per_gas
        .ok_or_else(|| PreImageError::MissingField("max_fee_per_gas".to_string()))?;
    let access_list = tx.access_list.as_ref().cloned().unwrap_or_default();
    
    // RLP encode: 0x02 || RLP([chainId, nonce, maxPriorityFeePerGas, maxFeePerGas, gasLimit, to, value, data, accessList])
    let mut items = Vec::new();
    
    items.push(rlp_encode_u64(tx.chain_id));
    items.push(rlp_encode_u64(tx.nonce));
    items.push(rlp_encode_u128(max_priority));
    items.push(rlp_encode_u128(max_fee));
    items.push(rlp_encode_u64(tx.gas_limit));
    items.push(rlp_encode_address(tx.to));
    items.push(rlp_encode_u128(tx.value));
    items.push(rlp_encode_bytes(&tx.data));
    items.push(rlp_encode_access_list(&access_list));
    
    let rlp_data = rlp_encode_list(&items);
    
    // Prepend type byte
    let mut typed_data = vec![0x02];
    typed_data.extend_from_slice(&rlp_data);
    
    Ok(keccak256(&typed_data))
}

/// Get signing hash for EIP-7702 transaction
fn get_eip7702_hash(tx: &UnsignedEthereumTransaction) -> PreImageResult<[u8; 32]> {
    let max_priority = tx.max_priority_fee_per_gas
        .ok_or_else(|| PreImageError::MissingField("max_priority_fee_per_gas".to_string()))?;
    let max_fee = tx.max_fee_per_gas
        .ok_or_else(|| PreImageError::MissingField("max_fee_per_gas".to_string()))?;
    let access_list = tx.access_list.as_ref().cloned().unwrap_or_default();
    let auth_list = tx.authorization_list.as_ref()
        .ok_or_else(|| PreImageError::MissingField("authorization_list".to_string()))?;
    
    // RLP encode: 0x04 || RLP([chainId, nonce, maxPriorityFeePerGas, maxFeePerGas, gasLimit, to, value, data, accessList, authorizationList])
    let mut items = Vec::new();
    
    items.push(rlp_encode_u64(tx.chain_id));
    items.push(rlp_encode_u64(tx.nonce));
    items.push(rlp_encode_u128(max_priority));
    items.push(rlp_encode_u128(max_fee));
    items.push(rlp_encode_u64(tx.gas_limit));
    items.push(rlp_encode_address(tx.to));
    items.push(rlp_encode_u128(tx.value));
    items.push(rlp_encode_bytes(&tx.data));
    items.push(rlp_encode_access_list(&access_list));
    items.push(rlp_encode_auth_list(auth_list));
    
    let rlp_data = rlp_encode_list(&items);
    
    // Prepend type byte
    let mut typed_data = vec![0x04];
    typed_data.extend_from_slice(&rlp_data);
    
    Ok(keccak256(&typed_data))
}

// RLP encoding helpers

fn keccak256(data: &[u8]) -> [u8; 32] {
    let mut hasher = Keccak::v256();
    let mut output = [0u8; 32];
    hasher.update(data);
    hasher.finalize(&mut output);
    output
}

fn rlp_encode_u64(val: u64) -> Vec<u8> {
    if val == 0 {
        return vec![0x80];
    }
    let bytes = val.to_be_bytes();
    let leading_zeros = bytes.iter().take_while(|&&b| b == 0).count();
    let significant = &bytes[leading_zeros..];
    
    if significant.len() == 1 && significant[0] < 0x80 {
        significant.to_vec()
    } else {
        let mut result = vec![0x80 + significant.len() as u8];
        result.extend_from_slice(significant);
        result
    }
}

fn rlp_encode_u128(val: u128) -> Vec<u8> {
    if val == 0 {
        return vec![0x80];
    }
    let bytes = val.to_be_bytes();
    let leading_zeros = bytes.iter().take_while(|&&b| b == 0).count();
    let significant = &bytes[leading_zeros..];
    
    if significant.len() == 1 && significant[0] < 0x80 {
        significant.to_vec()
    } else {
        let mut result = vec![0x80 + significant.len() as u8];
        result.extend_from_slice(significant);
        result
    }
}

fn rlp_encode_bytes(data: &[u8]) -> Vec<u8> {
    if data.is_empty() {
        return vec![0x80];
    }
    if data.len() == 1 && data[0] < 0x80 {
        return data.to_vec();
    }
    
    if data.len() < 56 {
        let mut result = vec![0x80 + data.len() as u8];
        result.extend_from_slice(data);
        result
    } else {
        let len_bytes = encode_length(data.len());
        let mut result = vec![0xb7 + len_bytes.len() as u8];
        result.extend_from_slice(&len_bytes);
        result.extend_from_slice(data);
        result
    }
}

fn rlp_encode_address(addr: Option<[u8; 20]>) -> Vec<u8> {
    match addr {
        Some(a) => rlp_encode_bytes(&a),
        None => vec![0x80], // Empty for contract creation
    }
}

fn rlp_encode_list(items: &[Vec<u8>]) -> Vec<u8> {
    let mut payload = Vec::new();
    for item in items {
        payload.extend_from_slice(item);
    }
    
    if payload.len() < 56 {
        let mut result = vec![0xc0 + payload.len() as u8];
        result.extend_from_slice(&payload);
        result
    } else {
        let len_bytes = encode_length(payload.len());
        let mut result = vec![0xf7 + len_bytes.len() as u8];
        result.extend_from_slice(&len_bytes);
        result.extend_from_slice(&payload);
        result
    }
}

fn encode_length(len: usize) -> Vec<u8> {
    if len == 0 {
        return vec![];
    }
    let bytes = len.to_be_bytes();
    let leading_zeros = bytes.iter().take_while(|&&b| b == 0).count();
    bytes[leading_zeros..].to_vec()
}

fn rlp_encode_access_list(list: &[AccessListEntry]) -> Vec<u8> {
    let items: Vec<Vec<u8>> = list.iter().map(|entry| {
        let addr = rlp_encode_bytes(&entry.address);
        let keys: Vec<Vec<u8>> = entry.storage_keys.iter()
            .map(|k| rlp_encode_bytes(k))
            .collect();
        let keys_list = rlp_encode_list(&keys);
        rlp_encode_list(&[addr, keys_list])
    }).collect();
    
    rlp_encode_list(&items)
}

fn rlp_encode_auth_list(list: &[Eip7702Auth]) -> Vec<u8> {
    let items: Vec<Vec<u8>> = list.iter().map(|auth| {
        let chain_id = rlp_encode_u64(auth.chain_id);
        let address = rlp_encode_bytes(&auth.address);
        let nonce = rlp_encode_u64(auth.nonce);
        rlp_encode_list(&[chain_id, address, nonce])
    }).collect();
    
    rlp_encode_list(&items)
}

#[cfg(test)]
mod tests {
    use super::*;
    
    fn sample_legacy_tx() -> UnsignedEthereumTransaction {
        UnsignedEthereumTransaction {
            tx_type: EthereumTxType::Legacy,
            chain_id: 1,
            nonce: 0,
            gas_price: Some(20_000_000_000), // 20 gwei
            max_priority_fee_per_gas: None,
            max_fee_per_gas: None,
            gas_limit: 21000,
            to: Some([0u8; 20]),
            value: 1_000_000_000_000_000_000, // 1 ETH
            data: vec![],
            access_list: None,
            authorization_list: None,
            derivation_path: Some("m/44'/60'/0'/0/0".to_string()),
        }
    }
    
    fn sample_eip1559_tx() -> UnsignedEthereumTransaction {
        UnsignedEthereumTransaction {
            tx_type: EthereumTxType::FeeMarket,
            chain_id: 1,
            nonce: 5,
            gas_price: None,
            max_priority_fee_per_gas: Some(2_000_000_000), // 2 gwei
            max_fee_per_gas: Some(100_000_000_000), // 100 gwei
            gas_limit: 21000,
            to: Some([0xaa; 20]),
            value: 500_000_000_000_000_000, // 0.5 ETH
            data: vec![0x01, 0x02, 0x03],
            access_list: Some(vec![]),
            authorization_list: None,
            derivation_path: Some("m/44'/60'/0'/0/1".to_string()),
        }
    }
    
    #[test]
    fn test_legacy_hash() {
        let tx = sample_legacy_tx();
        let result = get_ethereum_signing_hash(&tx);
        assert!(result.is_ok());
        
        let hash = result.unwrap();
        assert_eq!(hash.algorithm, SigningAlgorithm::Secp256k1Ecdsa);
        assert_eq!(hash.signer_id, "m/44'/60'/0'/0/0");
    }
    
    #[test]
    fn test_eip1559_hash() {
        let tx = sample_eip1559_tx();
        let result = get_ethereum_signing_hash(&tx);
        assert!(result.is_ok());
        
        let hash = result.unwrap();
        assert_eq!(hash.algorithm, SigningAlgorithm::Secp256k1Ecdsa);
    }
    
    #[test]
    fn test_eip2930_hash() {
        let mut tx = sample_legacy_tx();
        tx.tx_type = EthereumTxType::AccessList;
        tx.access_list = Some(vec![AccessListEntry {
            address: [0xbb; 20],
            storage_keys: vec![[0xcc; 32]],
        }]);
        
        let result = get_ethereum_signing_hash(&tx);
        assert!(result.is_ok());
    }
    
    #[test]
    fn test_eip7702_hash() {
        let mut tx = sample_eip1559_tx();
        tx.tx_type = EthereumTxType::AccountDelegation;
        tx.authorization_list = Some(vec![Eip7702Auth {
            chain_id: 1,
            address: [0xdd; 20],
            nonce: 0,
        }]);
        
        let result = get_ethereum_signing_hash(&tx);
        assert!(result.is_ok());
    }
    
    #[test]
    fn test_missing_gas_price() {
        let mut tx = sample_legacy_tx();
        tx.gas_price = None;
        
        let result = get_ethereum_signing_hash(&tx);
        assert!(matches!(result, Err(PreImageError::MissingField(_))));
    }
    
    #[test]
    fn test_contract_creation() {
        let mut tx = sample_legacy_tx();
        tx.to = None;
        tx.data = vec![0x60, 0x80, 0x60, 0x40]; // Contract bytecode
        
        let result = get_ethereum_signing_hash(&tx);
        assert!(result.is_ok());
        assert!(result.unwrap().description.contains("contract creation"));
    }
    
    #[test]
    fn test_rlp_encode_u64() {
        assert_eq!(rlp_encode_u64(0), vec![0x80]);
        assert_eq!(rlp_encode_u64(127), vec![127]);
        assert_eq!(rlp_encode_u64(128), vec![0x81, 128]);
        assert_eq!(rlp_encode_u64(256), vec![0x82, 1, 0]);
    }
    
    #[test]
    fn test_rlp_encode_bytes() {
        assert_eq!(rlp_encode_bytes(&[]), vec![0x80]);
        assert_eq!(rlp_encode_bytes(&[0x7f]), vec![0x7f]);
        assert_eq!(rlp_encode_bytes(&[0x80]), vec![0x81, 0x80]);
        assert_eq!(rlp_encode_bytes(&[1, 2, 3]), vec![0x83, 1, 2, 3]);
    }
    
    #[test]
    fn test_tx_type_bytes() {
        assert_eq!(EthereumTxType::Legacy.type_byte(), None);
        assert_eq!(EthereumTxType::AccessList.type_byte(), Some(0x01));
        assert_eq!(EthereumTxType::FeeMarket.type_byte(), Some(0x02));
        assert_eq!(EthereumTxType::AccountDelegation.type_byte(), Some(0x04));
    }
}
