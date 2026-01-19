//! Transaction Compiler
//!
//! Compiles external signatures back into complete, broadcast-ready transactions.

use crate::signing::preimage::{
    ExternalSignature, PreImageError, PreImageResult,
    bitcoin::{UnsignedBitcoinTransaction, BitcoinInputType},
    ethereum::{UnsignedEthereumTransaction, EthereumTxType},
    cosmos::UnsignedCosmosTransaction,
    solana::UnsignedSolanaTransaction,
};
use serde::{Deserialize, Serialize};

/// Compiled Bitcoin transaction
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompiledBitcoinTransaction {
    /// Raw transaction bytes (ready to broadcast)
    pub raw_tx: Vec<u8>,
    /// Transaction ID (txid)
    pub txid: [u8; 32],
    /// Witness transaction ID (wtxid) for SegWit
    pub wtxid: Option<[u8; 32]>,
    /// Virtual size in vbytes
    pub vsize: usize,
}

/// Compiled Ethereum transaction
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompiledEthereumTransaction {
    /// RLP-encoded signed transaction
    pub raw_tx: Vec<u8>,
    /// Transaction hash
    pub tx_hash: [u8; 32],
    /// Sender address (recovered from signature)
    pub from: [u8; 20],
}

/// Compiled Cosmos transaction
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompiledCosmosTransaction {
    /// Protobuf-encoded TxRaw
    pub raw_tx: Vec<u8>,
    /// Transaction hash
    pub tx_hash: [u8; 32],
}

/// Compiled Solana transaction
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompiledSolanaTransaction {
    /// Serialized transaction (base58 or raw bytes)
    pub raw_tx: Vec<u8>,
    /// Transaction signature (first signature is the ID)
    #[serde(with = "crate::serde_bytes::bytes64")]
    pub signature: [u8; 64],
}

/// Compile a Bitcoin transaction with external signatures
pub fn compile_bitcoin_transaction(
    tx: &UnsignedBitcoinTransaction,
    signatures: &[ExternalSignature],
) -> PreImageResult<CompiledBitcoinTransaction> {
    use bitcoin::hashes::{sha256d, Hash};
    
    if signatures.len() != tx.inputs.len() {
        return Err(PreImageError::InvalidSignature(format!(
            "Expected {} signatures, got {}",
            tx.inputs.len(),
            signatures.len()
        )));
    }
    
    // Determine if we need SegWit serialization
    let has_witness = tx.inputs.iter().any(|i| 
        i.input_type.is_segwit() || i.input_type.is_taproot()
    );
    
    let mut raw_tx = Vec::new();
    let mut witness_data = Vec::new();
    
    // Version
    raw_tx.extend_from_slice(&tx.version.to_le_bytes());
    
    // SegWit marker and flag
    if has_witness {
        raw_tx.push(0x00); // marker
        raw_tx.push(0x01); // flag
    }
    
    // Inputs
    raw_tx.push(tx.inputs.len() as u8);
    for (i, input) in tx.inputs.iter().enumerate() {
        // txid (reversed)
        let mut txid = input.txid;
        txid.reverse();
        raw_tx.extend_from_slice(&txid);
        
        // vout
        raw_tx.extend_from_slice(&input.vout.to_le_bytes());
        
        // scriptSig
        let sig = &signatures[i];
        let script_sig = build_script_sig(input, sig)?;
        write_var_int(script_sig.len() as u64, &mut raw_tx);
        raw_tx.extend_from_slice(&script_sig);
        
        // sequence
        raw_tx.extend_from_slice(&input.sequence.to_le_bytes());
        
        // Build witness for this input
        if has_witness {
            let witness = build_witness(input, sig)?;
            witness_data.extend_from_slice(&witness);
        }
    }
    
    // Outputs
    raw_tx.push(tx.outputs.len() as u8);
    for output in &tx.outputs {
        raw_tx.extend_from_slice(&output.value.to_le_bytes());
        write_var_int(output.script_pubkey.len() as u64, &mut raw_tx);
        raw_tx.extend_from_slice(&output.script_pubkey);
    }
    
    // Witness data (if SegWit)
    if has_witness {
        raw_tx.extend_from_slice(&witness_data);
    }
    
    // Locktime
    raw_tx.extend_from_slice(&tx.locktime.to_le_bytes());
    
    // Calculate txid (without witness data)
    let txid = {
        let mut tx_for_hash = Vec::new();
        tx_for_hash.extend_from_slice(&tx.version.to_le_bytes());
        tx_for_hash.push(tx.inputs.len() as u8);
        for (i, input) in tx.inputs.iter().enumerate() {
            let mut txid_inner = input.txid;
            txid_inner.reverse();
            tx_for_hash.extend_from_slice(&txid_inner);
            tx_for_hash.extend_from_slice(&input.vout.to_le_bytes());
            let sig = &signatures[i];
            let script_sig = build_script_sig(input, sig)?;
            write_var_int(script_sig.len() as u64, &mut tx_for_hash);
            tx_for_hash.extend_from_slice(&script_sig);
            tx_for_hash.extend_from_slice(&input.sequence.to_le_bytes());
        }
        tx_for_hash.push(tx.outputs.len() as u8);
        for output in &tx.outputs {
            tx_for_hash.extend_from_slice(&output.value.to_le_bytes());
            write_var_int(output.script_pubkey.len() as u64, &mut tx_for_hash);
            tx_for_hash.extend_from_slice(&output.script_pubkey);
        }
        tx_for_hash.extend_from_slice(&tx.locktime.to_le_bytes());
        
        let mut hash = sha256d::Hash::hash(&tx_for_hash).to_byte_array();
        hash.reverse(); // txid is displayed reversed
        hash
    };
    
    // Calculate wtxid
    let wtxid = if has_witness {
        let mut hash = sha256d::Hash::hash(&raw_tx).to_byte_array();
        hash.reverse();
        Some(hash)
    } else {
        None
    };
    
    // Calculate virtual size
    let base_size = raw_tx.len() - if has_witness { witness_data.len() + 2 } else { 0 };
    let total_size = raw_tx.len();
    let vsize = (base_size * 3 + total_size + 3) / 4;
    
    Ok(CompiledBitcoinTransaction {
        raw_tx,
        txid,
        wtxid,
        vsize,
    })
}

/// Build scriptSig for an input
fn build_script_sig(
    input: &crate::signing::preimage::bitcoin::BitcoinInput,
    sig: &ExternalSignature,
) -> PreImageResult<Vec<u8>> {
    match input.input_type {
        BitcoinInputType::P2PKH => {
            // <sig> <pubkey>
            let mut script = Vec::new();
            
            // DER signature with sighash type
            let der_sig = &sig.signature;
            script.push(der_sig.len() as u8 + 1); // +1 for sighash byte
            script.extend_from_slice(der_sig);
            script.push(0x01); // SIGHASH_ALL
            
            // Compressed public key (33 bytes)
            script.push(sig.public_key.len() as u8);
            script.extend_from_slice(&sig.public_key);
            
            Ok(script)
        }
        BitcoinInputType::P2SH_P2WPKH => {
            // Nested SegWit: scriptSig = <redeemScript>
            // redeemScript = 0x0014 <20-byte-key-hash>
            let mut script = Vec::new();
            
            // Push the redeem script
            let redeem_script = &input.script_code;
            script.push(redeem_script.len() as u8);
            script.extend_from_slice(redeem_script);
            
            Ok(script)
        }
        BitcoinInputType::P2WPKH | BitcoinInputType::P2WSH 
        | BitcoinInputType::P2TR_KeyPath | BitcoinInputType::P2TR_ScriptPath => {
            // Native SegWit/Taproot: empty scriptSig
            Ok(Vec::new())
        }
        BitcoinInputType::P2SH => {
            // Generic P2SH (needs redeem script)
            let mut script = Vec::new();
            script.push(sig.signature.len() as u8 + 1);
            script.extend_from_slice(&sig.signature);
            script.push(0x01);
            script.push(sig.public_key.len() as u8);
            script.extend_from_slice(&sig.public_key);
            // Push redeem script
            script.push(input.script_code.len() as u8);
            script.extend_from_slice(&input.script_code);
            Ok(script)
        }
    }
}

/// Build witness for an input
fn build_witness(
    input: &crate::signing::preimage::bitcoin::BitcoinInput,
    sig: &ExternalSignature,
) -> PreImageResult<Vec<u8>> {
    match input.input_type {
        BitcoinInputType::P2WPKH | BitcoinInputType::P2SH_P2WPKH => {
            // 2 items: <sig> <pubkey>
            let mut witness = Vec::new();
            witness.push(0x02); // 2 items
            
            // Signature with sighash byte
            let sig_len = sig.signature.len() + 1;
            witness.push(sig_len as u8);
            witness.extend_from_slice(&sig.signature);
            witness.push(0x01); // SIGHASH_ALL
            
            // Public key
            witness.push(sig.public_key.len() as u8);
            witness.extend_from_slice(&sig.public_key);
            
            Ok(witness)
        }
        BitcoinInputType::P2TR_KeyPath => {
            // 1 item: Schnorr signature (64 bytes, no sighash byte for default)
            let mut witness = Vec::new();
            witness.push(0x01); // 1 item
            witness.push(sig.signature.len() as u8);
            witness.extend_from_slice(&sig.signature);
            Ok(witness)
        }
        BitcoinInputType::P2WSH => {
            // Script path witness (variable)
            let mut witness = Vec::new();
            // For now, just signature + pubkey + script
            witness.push(0x03);
            witness.push(0x00); // OP_0 (multisig compatibility)
            witness.push((sig.signature.len() + 1) as u8);
            witness.extend_from_slice(&sig.signature);
            witness.push(0x01);
            witness.push(input.script_code.len() as u8);
            witness.extend_from_slice(&input.script_code);
            Ok(witness)
        }
        _ => {
            // No witness for legacy
            Ok(vec![0x00])
        }
    }
}

/// Compile an Ethereum transaction with external signature
pub fn compile_ethereum_transaction(
    tx: &UnsignedEthereumTransaction,
    signature: &ExternalSignature,
) -> PreImageResult<CompiledEthereumTransaction> {
    use tiny_keccak::{Hasher, Keccak};
    
    let recovery_id = signature.recovery_id
        .ok_or_else(|| PreImageError::MissingField("recovery_id".to_string()))?;
    
    // Extract r, s from signature
    if signature.signature.len() < 64 {
        return Err(PreImageError::InvalidSignature("Signature too short".to_string()));
    }
    let r = &signature.signature[0..32];
    let s = &signature.signature[32..64];
    
    let raw_tx = match tx.tx_type {
        EthereumTxType::Legacy => compile_legacy_tx(tx, r, s, recovery_id)?,
        EthereumTxType::AccessList => compile_eip2930_tx(tx, r, s, recovery_id)?,
        EthereumTxType::FeeMarket => compile_eip1559_tx(tx, r, s, recovery_id)?,
        EthereumTxType::AccountDelegation => compile_eip7702_tx(tx, r, s, recovery_id)?,
    };
    
    // Calculate tx hash
    let mut hasher = Keccak::v256();
    let mut tx_hash = [0u8; 32];
    hasher.update(&raw_tx);
    hasher.finalize(&mut tx_hash);
    
    // Recover sender address from signature
    let from = recover_sender(tx, &signature.signature, recovery_id)?;
    
    Ok(CompiledEthereumTransaction {
        raw_tx,
        tx_hash,
        from,
    })
}

fn compile_legacy_tx(tx: &UnsignedEthereumTransaction, r: &[u8], s: &[u8], v: u8) -> PreImageResult<Vec<u8>> {
    let gas_price = tx.gas_price.ok_or_else(|| PreImageError::MissingField("gas_price".to_string()))?;
    
    // EIP-155: v = chain_id * 2 + 35 + recovery_id
    let v_value = tx.chain_id * 2 + 35 + v as u64;
    
    let mut items = Vec::new();
    items.push(rlp_encode_u64(tx.nonce));
    items.push(rlp_encode_u128(gas_price));
    items.push(rlp_encode_u64(tx.gas_limit));
    items.push(rlp_encode_address(tx.to));
    items.push(rlp_encode_u128(tx.value));
    items.push(rlp_encode_bytes(&tx.data));
    items.push(rlp_encode_u64(v_value));
    items.push(rlp_encode_bytes(r));
    items.push(rlp_encode_bytes(s));
    
    Ok(rlp_encode_list(&items))
}

fn compile_eip2930_tx(tx: &UnsignedEthereumTransaction, r: &[u8], s: &[u8], v: u8) -> PreImageResult<Vec<u8>> {
    let gas_price = tx.gas_price.ok_or_else(|| PreImageError::MissingField("gas_price".to_string()))?;
    let access_list = tx.access_list.as_ref().ok_or_else(|| PreImageError::MissingField("access_list".to_string()))?;
    
    let mut items = Vec::new();
    items.push(rlp_encode_u64(tx.chain_id));
    items.push(rlp_encode_u64(tx.nonce));
    items.push(rlp_encode_u128(gas_price));
    items.push(rlp_encode_u64(tx.gas_limit));
    items.push(rlp_encode_address(tx.to));
    items.push(rlp_encode_u128(tx.value));
    items.push(rlp_encode_bytes(&tx.data));
    items.push(rlp_encode_access_list(access_list));
    items.push(rlp_encode_u64(v as u64));
    items.push(rlp_encode_bytes(r));
    items.push(rlp_encode_bytes(s));
    
    let rlp_data = rlp_encode_list(&items);
    let mut result = vec![0x01];
    result.extend_from_slice(&rlp_data);
    Ok(result)
}

fn compile_eip1559_tx(tx: &UnsignedEthereumTransaction, r: &[u8], s: &[u8], v: u8) -> PreImageResult<Vec<u8>> {
    let max_priority = tx.max_priority_fee_per_gas.ok_or_else(|| PreImageError::MissingField("max_priority_fee_per_gas".to_string()))?;
    let max_fee = tx.max_fee_per_gas.ok_or_else(|| PreImageError::MissingField("max_fee_per_gas".to_string()))?;
    let access_list = tx.access_list.as_ref().cloned().unwrap_or_default();
    
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
    items.push(rlp_encode_u64(v as u64));
    items.push(rlp_encode_bytes(r));
    items.push(rlp_encode_bytes(s));
    
    let rlp_data = rlp_encode_list(&items);
    let mut result = vec![0x02];
    result.extend_from_slice(&rlp_data);
    Ok(result)
}

fn compile_eip7702_tx(tx: &UnsignedEthereumTransaction, r: &[u8], s: &[u8], v: u8) -> PreImageResult<Vec<u8>> {
    let max_priority = tx.max_priority_fee_per_gas.ok_or_else(|| PreImageError::MissingField("max_priority_fee_per_gas".to_string()))?;
    let max_fee = tx.max_fee_per_gas.ok_or_else(|| PreImageError::MissingField("max_fee_per_gas".to_string()))?;
    let access_list = tx.access_list.as_ref().cloned().unwrap_or_default();
    let auth_list = tx.authorization_list.as_ref().ok_or_else(|| PreImageError::MissingField("authorization_list".to_string()))?;
    
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
    items.push(rlp_encode_u64(v as u64));
    items.push(rlp_encode_bytes(r));
    items.push(rlp_encode_bytes(s));
    
    let rlp_data = rlp_encode_list(&items);
    let mut result = vec![0x04];
    result.extend_from_slice(&rlp_data);
    Ok(result)
}

/// Compile a Cosmos transaction with external signature
pub fn compile_cosmos_transaction(
    tx: &UnsignedCosmosTransaction,
    signature: &ExternalSignature,
) -> PreImageResult<CompiledCosmosTransaction> {
    use sha2::{Sha256, Digest};
    
    // Build TxRaw protobuf: { body_bytes, auth_info_bytes, signatures }
    let mut tx_raw = Vec::new();
    
    // body_bytes
    let body_bytes = encode_cosmos_body(tx)?;
    tx_raw.push(0x0a);
    encode_varint(body_bytes.len() as u64, &mut tx_raw);
    tx_raw.extend_from_slice(&body_bytes);
    
    // auth_info_bytes
    let auth_info_bytes = encode_cosmos_auth_info(tx)?;
    tx_raw.push(0x12);
    encode_varint(auth_info_bytes.len() as u64, &mut tx_raw);
    tx_raw.extend_from_slice(&auth_info_bytes);
    
    // signatures (repeated bytes)
    tx_raw.push(0x1a);
    encode_varint(signature.signature.len() as u64, &mut tx_raw);
    tx_raw.extend_from_slice(&signature.signature);
    
    // Calculate hash
    let mut hasher = Sha256::new();
    hasher.update(&tx_raw);
    let result = hasher.finalize();
    let mut tx_hash = [0u8; 32];
    tx_hash.copy_from_slice(&result);
    
    Ok(CompiledCosmosTransaction {
        raw_tx: tx_raw,
        tx_hash,
    })
}

/// Compile a Solana transaction with external signatures
pub fn compile_solana_transaction(
    tx: &UnsignedSolanaTransaction,
    signatures: &[ExternalSignature],
) -> PreImageResult<CompiledSolanaTransaction> {
    if signatures.len() != tx.signers.len() {
        return Err(PreImageError::InvalidSignature(format!(
            "Expected {} signatures, got {}",
            tx.signers.len(),
            signatures.len()
        )));
    }
    
    let mut raw_tx = Vec::new();
    
    // Number of signatures
    write_compact_u16(signatures.len() as u16, &mut raw_tx);
    
    // Signatures (64 bytes each)
    for sig in signatures {
        if sig.signature.len() != 64 {
            return Err(PreImageError::InvalidSignature("Solana signatures must be 64 bytes".to_string()));
        }
        raw_tx.extend_from_slice(&sig.signature);
    }
    
    // Message
    let message = serialize_solana_message(tx)?;
    raw_tx.extend_from_slice(&message);
    
    // First signature is the transaction ID
    let mut signature = [0u8; 64];
    signature.copy_from_slice(&signatures[0].signature);
    
    Ok(CompiledSolanaTransaction {
        raw_tx,
        signature,
    })
}

// Helper functions

fn write_var_int(value: u64, buf: &mut Vec<u8>) {
    if value < 0xfd {
        buf.push(value as u8);
    } else if value <= 0xffff {
        buf.push(0xfd);
        buf.extend_from_slice(&(value as u16).to_le_bytes());
    } else if value <= 0xffffffff {
        buf.push(0xfe);
        buf.extend_from_slice(&(value as u32).to_le_bytes());
    } else {
        buf.push(0xff);
        buf.extend_from_slice(&value.to_le_bytes());
    }
}

fn encode_varint(mut value: u64, buf: &mut Vec<u8>) {
    loop {
        let mut byte = (value & 0x7f) as u8;
        value >>= 7;
        if value != 0 {
            byte |= 0x80;
        }
        buf.push(byte);
        if value == 0 {
            break;
        }
    }
}

fn write_compact_u16(value: u16, buf: &mut Vec<u8>) {
    if value < 0x80 {
        buf.push(value as u8);
    } else if value < 0x4000 {
        buf.push((value & 0x7f) as u8 | 0x80);
        buf.push((value >> 7) as u8);
    } else {
        buf.push((value & 0x7f) as u8 | 0x80);
        buf.push(((value >> 7) & 0x7f) as u8 | 0x80);
        buf.push((value >> 14) as u8);
    }
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
    // Strip leading zeros for signature components
    let start = data.iter().take_while(|&&b| b == 0).count();
    let data = &data[start..];
    
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

fn encode_length(len: usize) -> Vec<u8> {
    if len == 0 {
        return vec![];
    }
    let bytes = len.to_be_bytes();
    let leading_zeros = bytes.iter().take_while(|&&b| b == 0).count();
    bytes[leading_zeros..].to_vec()
}

fn rlp_encode_address(addr: Option<[u8; 20]>) -> Vec<u8> {
    match addr {
        Some(a) => {
            let mut result = vec![0x80 + 20];
            result.extend_from_slice(&a);
            result
        }
        None => vec![0x80],
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

fn rlp_encode_access_list(list: &[crate::signing::preimage::ethereum::AccessListEntry]) -> Vec<u8> {
    let items: Vec<Vec<u8>> = list.iter().map(|entry| {
        let addr = {
            let mut r = vec![0x80 + 20];
            r.extend_from_slice(&entry.address);
            r
        };
        let keys: Vec<Vec<u8>> = entry.storage_keys.iter()
            .map(|k| {
                let mut r = vec![0x80 + 32];
                r.extend_from_slice(k);
                r
            })
            .collect();
        let keys_list = rlp_encode_list(&keys);
        rlp_encode_list(&[addr, keys_list])
    }).collect();
    
    rlp_encode_list(&items)
}

fn rlp_encode_auth_list(list: &[crate::signing::preimage::ethereum::Eip7702Auth]) -> Vec<u8> {
    let items: Vec<Vec<u8>> = list.iter().map(|auth| {
        let chain_id = rlp_encode_u64(auth.chain_id);
        let address = {
            let mut r = vec![0x80 + 20];
            r.extend_from_slice(&auth.address);
            r
        };
        let nonce = rlp_encode_u64(auth.nonce);
        rlp_encode_list(&[chain_id, address, nonce])
    }).collect();
    
    rlp_encode_list(&items)
}

fn recover_sender(
    _tx: &UnsignedEthereumTransaction,
    _signature: &[u8],
    _recovery_id: u8,
) -> PreImageResult<[u8; 20]> {
    // In a full implementation, this would use secp256k1 ECDSA recovery
    // For now, return a placeholder
    // The actual recovery would:
    // 1. Compute the signing hash
    // 2. Use ecrecover with (hash, v, r, s)
    // 3. Take keccak256 of uncompressed public key
    // 4. Return last 20 bytes
    Ok([0u8; 20])
}

fn encode_cosmos_body(tx: &UnsignedCosmosTransaction) -> PreImageResult<Vec<u8>> {
    let mut body = Vec::new();
    
    for msg in &tx.messages {
        body.push(0x0a);
        let mut any = Vec::new();
        any.push(0x0a);
        encode_varint(msg.type_url.len() as u64, &mut any);
        any.extend_from_slice(msg.type_url.as_bytes());
        any.push(0x12);
        encode_varint(msg.value.len() as u64, &mut any);
        any.extend_from_slice(&msg.value);
        encode_varint(any.len() as u64, &mut body);
        body.extend_from_slice(&any);
    }
    
    if !tx.memo.is_empty() {
        body.push(0x12);
        encode_varint(tx.memo.len() as u64, &mut body);
        body.extend_from_slice(tx.memo.as_bytes());
    }
    
    if tx.timeout_height > 0 {
        body.push(0x18);
        encode_varint(tx.timeout_height, &mut body);
    }
    
    Ok(body)
}

fn encode_cosmos_auth_info(tx: &UnsignedCosmosTransaction) -> PreImageResult<Vec<u8>> {
    let mut auth_info = Vec::new();
    
    // SignerInfo
    let mut signer_info = Vec::new();
    
    if let Some(pk) = &tx.signer.public_key {
        signer_info.push(0x0a);
        let mut any = Vec::new();
        let type_url = "/cosmos.crypto.secp256k1.PubKey";
        any.push(0x0a);
        encode_varint(type_url.len() as u64, &mut any);
        any.extend_from_slice(type_url.as_bytes());
        let mut pk_proto = Vec::new();
        pk_proto.push(0x0a);
        encode_varint(pk.len() as u64, &mut pk_proto);
        pk_proto.extend_from_slice(pk);
        any.push(0x12);
        encode_varint(pk_proto.len() as u64, &mut any);
        any.extend_from_slice(&pk_proto);
        encode_varint(any.len() as u64, &mut signer_info);
        signer_info.extend_from_slice(&any);
    }
    
    // ModeInfo
    let mut mode_info = Vec::new();
    let mode = match tx.sign_mode {
        crate::signing::preimage::cosmos::CosmosSignMode::Amino => 127,
        crate::signing::preimage::cosmos::CosmosSignMode::Direct => 1,
        crate::signing::preimage::cosmos::CosmosSignMode::Textual => 2,
    };
    let mut single = Vec::new();
    single.push(0x08);
    encode_varint(mode, &mut single);
    mode_info.push(0x0a);
    encode_varint(single.len() as u64, &mut mode_info);
    mode_info.extend_from_slice(&single);
    
    signer_info.push(0x12);
    encode_varint(mode_info.len() as u64, &mut signer_info);
    signer_info.extend_from_slice(&mode_info);
    
    // Sequence
    signer_info.push(0x18);
    encode_varint(tx.signer.sequence, &mut signer_info);
    
    auth_info.push(0x0a);
    encode_varint(signer_info.len() as u64, &mut auth_info);
    auth_info.extend_from_slice(&signer_info);
    
    // Fee
    let mut fee = Vec::new();
    for coin in &tx.fee.amount {
        fee.push(0x0a);
        let mut coin_proto = Vec::new();
        coin_proto.push(0x0a);
        encode_varint(coin.denom.len() as u64, &mut coin_proto);
        coin_proto.extend_from_slice(coin.denom.as_bytes());
        coin_proto.push(0x12);
        encode_varint(coin.amount.len() as u64, &mut coin_proto);
        coin_proto.extend_from_slice(coin.amount.as_bytes());
        encode_varint(coin_proto.len() as u64, &mut fee);
        fee.extend_from_slice(&coin_proto);
    }
    fee.push(0x10);
    encode_varint(tx.fee.gas, &mut fee);
    
    auth_info.push(0x12);
    encode_varint(fee.len() as u64, &mut auth_info);
    auth_info.extend_from_slice(&fee);
    
    Ok(auth_info)
}

fn serialize_solana_message(tx: &UnsignedSolanaTransaction) -> PreImageResult<Vec<u8>> {
    use crate::signing::preimage::solana::{SolanaVersion, serialize_legacy_message, serialize_v0_message};
    
    match tx.version {
        SolanaVersion::Legacy => serialize_legacy_message(tx),
        SolanaVersion::V0 => serialize_v0_message(tx),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::signing::preimage::bitcoin::{BitcoinInput, BitcoinOutput, BitcoinInputType};
    use crate::signing::preimage::ethereum::EthereumTxType;
    
    #[test]
    fn test_compile_simple_bitcoin() {
        let tx = UnsignedBitcoinTransaction {
            version: 1,
            inputs: vec![BitcoinInput {
                txid: [0; 32],
                vout: 0,
                script_code: vec![0x76, 0xa9, 0x14],
                value: 100000,
                sequence: 0xffffffff,
                derivation_path: None,
                input_type: BitcoinInputType::P2PKH,
            }],
            outputs: vec![BitcoinOutput {
                value: 90000,
                script_pubkey: vec![0x76, 0xa9, 0x14],
            }],
            locktime: 0,
        };
        
        let sig = ExternalSignature::new(
            vec![0x30; 35], // Mock DER signature
            vec![0x02; 33], // Mock compressed pubkey
        );
        
        let result = compile_bitcoin_transaction(&tx, &[sig]);
        assert!(result.is_ok());
    }
    
    #[test]
    fn test_compile_ethereum_legacy() {
        let tx = UnsignedEthereumTransaction {
            tx_type: EthereumTxType::Legacy,
            chain_id: 1,
            nonce: 0,
            gas_price: Some(20_000_000_000),
            max_priority_fee_per_gas: None,
            max_fee_per_gas: None,
            gas_limit: 21000,
            to: Some([0; 20]),
            value: 1_000_000_000_000_000_000,
            data: vec![],
            access_list: None,
            authorization_list: None,
            derivation_path: None,
        };
        
        let sig = ExternalSignature::new(
            vec![0; 64],
            vec![0x04; 65],
        ).with_recovery_id(0);
        
        let result = compile_ethereum_transaction(&tx, &sig);
        assert!(result.is_ok());
    }
    
    #[test]
    fn test_rlp_encoding() {
        assert_eq!(rlp_encode_u64(0), vec![0x80]);
        assert_eq!(rlp_encode_u64(127), vec![127]);
        assert_eq!(rlp_encode_u64(128), vec![0x81, 128]);
    }
    
    #[test]
    fn test_var_int_encoding() {
        let mut buf = Vec::new();
        write_var_int(0, &mut buf);
        assert_eq!(buf, vec![0]);
        
        buf.clear();
        write_var_int(252, &mut buf);
        assert_eq!(buf, vec![252]);
        
        buf.clear();
        write_var_int(253, &mut buf);
        assert_eq!(buf, vec![0xfd, 253, 0]);
    }
}
