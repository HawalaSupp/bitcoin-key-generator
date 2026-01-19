//! EIP-7702 Transaction Building and Encoding
//!
//! Implements RLP encoding for EIP-7702 transactions.

use super::types::{Eip7702Transaction, SignedEip7702Transaction, AccessListEntry, Eip7702Error, Eip7702Result, EIP7702_TX_TYPE};
use super::authorization::{rlp_encode_authorization, rlp_encode_u64, rlp_encode_u128, rlp_encode_bytes, keccak256};

/// RLP encode an access list entry
fn rlp_encode_access_list_entry(entry: &AccessListEntry) -> Vec<u8> {
    let address_bytes = rlp_encode_bytes(&entry.address);
    
    // Encode storage keys as a list
    let mut keys_content = Vec::new();
    for key in &entry.storage_keys {
        keys_content.extend_from_slice(&rlp_encode_bytes(key));
    }
    
    let keys_list = if keys_content.len() < 56 {
        let mut encoded = vec![0xc0 + keys_content.len() as u8];
        encoded.extend_from_slice(&keys_content);
        encoded
    } else {
        let len_bytes = encode_length(keys_content.len());
        let mut encoded = vec![0xf7 + len_bytes.len() as u8];
        encoded.extend_from_slice(&len_bytes);
        encoded.extend_from_slice(&keys_content);
        encoded
    };
    
    // Encode the entry as [address, storage_keys]
    let content_len = address_bytes.len() + keys_list.len();
    
    if content_len < 56 {
        let mut encoded = vec![0xc0 + content_len as u8];
        encoded.extend_from_slice(&address_bytes);
        encoded.extend_from_slice(&keys_list);
        encoded
    } else {
        let len_bytes = encode_length(content_len);
        let mut encoded = vec![0xf7 + len_bytes.len() as u8];
        encoded.extend_from_slice(&len_bytes);
        encoded.extend_from_slice(&address_bytes);
        encoded.extend_from_slice(&keys_list);
        encoded
    }
}

/// RLP encode an access list
fn rlp_encode_access_list(access_list: &[AccessListEntry]) -> Vec<u8> {
    let mut content = Vec::new();
    for entry in access_list {
        content.extend_from_slice(&rlp_encode_access_list_entry(entry));
    }
    
    if content.len() < 56 {
        let mut encoded = vec![0xc0 + content.len() as u8];
        encoded.extend_from_slice(&content);
        encoded
    } else {
        let len_bytes = encode_length(content.len());
        let mut encoded = vec![0xf7 + len_bytes.len() as u8];
        encoded.extend_from_slice(&len_bytes);
        encoded.extend_from_slice(&content);
        encoded
    }
}

/// RLP encode an authorization list
fn rlp_encode_authorization_list(auths: &[super::types::Authorization]) -> Vec<u8> {
    let mut content = Vec::new();
    for auth in auths {
        content.extend_from_slice(&rlp_encode_authorization(auth));
    }
    
    if content.len() < 56 {
        let mut encoded = vec![0xc0 + content.len() as u8];
        encoded.extend_from_slice(&content);
        encoded
    } else {
        let len_bytes = encode_length(content.len());
        let mut encoded = vec![0xf7 + len_bytes.len() as u8];
        encoded.extend_from_slice(&len_bytes);
        encoded.extend_from_slice(&content);
        encoded
    }
}

/// RLP encode the transaction for signing (without signature)
/// 
/// Per EIP-7702:
/// `rlp([chain_id, nonce, max_priority_fee_per_gas, max_fee_per_gas, gas_limit, 
///       destination, value, data, access_list, authorization_list])`
pub fn rlp_encode_transaction_for_signing(tx: &Eip7702Transaction) -> Vec<u8> {
    let chain_id = rlp_encode_u64(tx.chain_id);
    let nonce = rlp_encode_u64(tx.nonce);
    let max_priority_fee = rlp_encode_u128(tx.max_priority_fee_per_gas);
    let max_fee = rlp_encode_u128(tx.max_fee_per_gas);
    let gas_limit = rlp_encode_u64(tx.gas_limit);
    
    let to = match &tx.to {
        Some(addr) => rlp_encode_bytes(addr),
        None => vec![0x80], // Empty bytes
    };
    
    let value = rlp_encode_u128(tx.value);
    let data = rlp_encode_bytes(&tx.data);
    let access_list = rlp_encode_access_list(&tx.access_list);
    let auth_list = rlp_encode_authorization_list(&tx.authorization_list);
    
    let content_len = chain_id.len() + nonce.len() + max_priority_fee.len() + max_fee.len()
        + gas_limit.len() + to.len() + value.len() + data.len()
        + access_list.len() + auth_list.len();
    
    let mut encoded = Vec::with_capacity(content_len + 3);
    
    // RLP list prefix
    if content_len < 56 {
        encoded.push(0xc0 + content_len as u8);
    } else {
        let len_bytes = encode_length(content_len);
        encoded.push(0xf7 + len_bytes.len() as u8);
        encoded.extend_from_slice(&len_bytes);
    }
    
    encoded.extend_from_slice(&chain_id);
    encoded.extend_from_slice(&nonce);
    encoded.extend_from_slice(&max_priority_fee);
    encoded.extend_from_slice(&max_fee);
    encoded.extend_from_slice(&gas_limit);
    encoded.extend_from_slice(&to);
    encoded.extend_from_slice(&value);
    encoded.extend_from_slice(&data);
    encoded.extend_from_slice(&access_list);
    encoded.extend_from_slice(&auth_list);
    
    encoded
}

/// Get the signing hash for an EIP-7702 transaction
/// 
/// `keccak256(0x04 || rlp(...))`
pub fn transaction_signing_hash(tx: &Eip7702Transaction) -> [u8; 32] {
    let rlp = rlp_encode_transaction_for_signing(tx);
    
    let mut data = Vec::with_capacity(1 + rlp.len());
    data.push(EIP7702_TX_TYPE);
    data.extend_from_slice(&rlp);
    
    keccak256(&data)
}

/// RLP encode a signed transaction
/// 
/// Per EIP-7702:
/// `0x04 || rlp([chain_id, nonce, max_priority_fee_per_gas, max_fee_per_gas, gas_limit,
///               destination, value, data, access_list, authorization_list, 
///               y_parity, r, s])`
pub fn rlp_encode_signed_transaction(signed: &SignedEip7702Transaction) -> Vec<u8> {
    let tx = &signed.tx;
    
    let chain_id = rlp_encode_u64(tx.chain_id);
    let nonce = rlp_encode_u64(tx.nonce);
    let max_priority_fee = rlp_encode_u128(tx.max_priority_fee_per_gas);
    let max_fee = rlp_encode_u128(tx.max_fee_per_gas);
    let gas_limit = rlp_encode_u64(tx.gas_limit);
    
    let to = match &tx.to {
        Some(addr) => rlp_encode_bytes(addr),
        None => vec![0x80],
    };
    
    let value = rlp_encode_u128(tx.value);
    let data = rlp_encode_bytes(&tx.data);
    let access_list = rlp_encode_access_list(&tx.access_list);
    let auth_list = rlp_encode_authorization_list(&tx.authorization_list);
    
    // Signature fields
    let y_parity = rlp_encode_u64(signed.y_parity as u64);
    let r = rlp_encode_bytes_trimmed(&signed.r);
    let s = rlp_encode_bytes_trimmed(&signed.s);
    
    let content_len = chain_id.len() + nonce.len() + max_priority_fee.len() + max_fee.len()
        + gas_limit.len() + to.len() + value.len() + data.len()
        + access_list.len() + auth_list.len()
        + y_parity.len() + r.len() + s.len();
    
    let mut rlp_list = Vec::with_capacity(content_len + 3);
    
    // RLP list prefix
    if content_len < 56 {
        rlp_list.push(0xc0 + content_len as u8);
    } else {
        let len_bytes = encode_length(content_len);
        rlp_list.push(0xf7 + len_bytes.len() as u8);
        rlp_list.extend_from_slice(&len_bytes);
    }
    
    rlp_list.extend_from_slice(&chain_id);
    rlp_list.extend_from_slice(&nonce);
    rlp_list.extend_from_slice(&max_priority_fee);
    rlp_list.extend_from_slice(&max_fee);
    rlp_list.extend_from_slice(&gas_limit);
    rlp_list.extend_from_slice(&to);
    rlp_list.extend_from_slice(&value);
    rlp_list.extend_from_slice(&data);
    rlp_list.extend_from_slice(&access_list);
    rlp_list.extend_from_slice(&auth_list);
    rlp_list.extend_from_slice(&y_parity);
    rlp_list.extend_from_slice(&r);
    rlp_list.extend_from_slice(&s);
    
    // Prepend transaction type
    let mut encoded = Vec::with_capacity(1 + rlp_list.len());
    encoded.push(EIP7702_TX_TYPE);
    encoded.extend_from_slice(&rlp_list);
    
    encoded
}

/// Get the transaction hash (for tracking after broadcast)
pub fn transaction_hash(signed: &SignedEip7702Transaction) -> [u8; 32] {
    let encoded = rlp_encode_signed_transaction(signed);
    keccak256(&encoded)
}

/// Build a transaction from JSON parameters
pub fn build_transaction_from_json(json: &serde_json::Value) -> Eip7702Result<Eip7702Transaction> {
    let chain_id = json.get("chainId")
        .and_then(|v| v.as_u64())
        .ok_or_else(|| Eip7702Error::RlpError("Missing chainId".to_string()))?;
    
    let mut tx = Eip7702Transaction::new(chain_id);
    
    if let Some(nonce) = json.get("nonce").and_then(|v| v.as_u64()) {
        tx.nonce = nonce;
    }
    
    if let Some(fee) = json.get("maxPriorityFeePerGas").and_then(|v| parse_u128(v)) {
        tx.max_priority_fee_per_gas = fee;
    }
    
    if let Some(fee) = json.get("maxFeePerGas").and_then(|v| parse_u128(v)) {
        tx.max_fee_per_gas = fee;
    }
    
    if let Some(gas) = json.get("gasLimit").and_then(|v| v.as_u64()) {
        tx.gas_limit = gas;
    }
    
    if let Some(to) = json.get("to").and_then(|v| v.as_str()) {
        let addr = parse_address(to)?;
        tx.to = Some(addr);
    }
    
    if let Some(value) = json.get("value").and_then(|v| parse_u128(v)) {
        tx.value = value;
    }
    
    if let Some(data) = json.get("data").and_then(|v| v.as_str()) {
        let data_hex = data.strip_prefix("0x").unwrap_or(data);
        tx.data = hex::decode(data_hex)
            .map_err(|e| Eip7702Error::RlpError(format!("Invalid data hex: {}", e)))?;
    }
    
    Ok(tx)
}

fn parse_u128(v: &serde_json::Value) -> Option<u128> {
    if let Some(n) = v.as_u64() {
        Some(n as u128)
    } else if let Some(s) = v.as_str() {
        let s = s.strip_prefix("0x").unwrap_or(s);
        u128::from_str_radix(s, 16).ok()
    } else {
        None
    }
}

fn parse_address(s: &str) -> Eip7702Result<[u8; 20]> {
    let s = s.strip_prefix("0x").unwrap_or(s);
    let bytes = hex::decode(s)
        .map_err(|e| Eip7702Error::InvalidAddress(format!("Invalid hex: {}", e)))?;
    
    if bytes.len() != 20 {
        return Err(Eip7702Error::InvalidAddress(format!("Expected 20 bytes, got {}", bytes.len())));
    }
    
    let mut addr = [0u8; 20];
    addr.copy_from_slice(&bytes);
    Ok(addr)
}

fn rlp_encode_bytes_trimmed(data: &[u8]) -> Vec<u8> {
    let start = data.iter().position(|&b| b != 0).unwrap_or(data.len());
    let trimmed = &data[start..];
    
    if trimmed.is_empty() {
        vec![0x80]
    } else {
        rlp_encode_bytes(trimmed)
    }
}

fn encode_length(len: usize) -> Vec<u8> {
    if len < 256 {
        vec![len as u8]
    } else if len < 65536 {
        vec![(len >> 8) as u8, len as u8]
    } else if len < 16777216 {
        vec![(len >> 16) as u8, (len >> 8) as u8, len as u8]
    } else {
        vec![(len >> 24) as u8, (len >> 16) as u8, (len >> 8) as u8, len as u8]
    }
}
