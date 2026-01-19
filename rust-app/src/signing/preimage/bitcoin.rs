//! Bitcoin Pre-Image Hashing
//!
//! Generates sighashes for Bitcoin transaction inputs.
//! Supports Legacy, SegWit (BIP-143), and Taproot (BIP-341) sighash algorithms.

use super::{PreImageHash, PreImageError, PreImageResult, SigningAlgorithm};
use bitcoin::hashes::{sha256d, Hash};
use serde::{Deserialize, Serialize};

/// Bitcoin sighash types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum BitcoinSigHashType {
    /// Sign all inputs and all outputs
    All = 0x01,
    /// Sign all inputs, no outputs
    None = 0x02,
    /// Sign all inputs, only output at same index
    Single = 0x03,
    /// SIGHASH_ALL | ANYONECANPAY (only sign own input, all outputs)
    AllAnyoneCanPay = 0x81,
    /// SIGHASH_NONE | ANYONECANPAY
    NoneAnyoneCanPay = 0x82,
    /// SIGHASH_SINGLE | ANYONECANPAY
    SingleAnyoneCanPay = 0x83,
    /// Taproot default (implicit SIGHASH_ALL)
    TaprootDefault = 0x00,
}

impl BitcoinSigHashType {
    pub fn to_byte(&self) -> u8 {
        *self as u8
    }
    
    pub fn from_byte(b: u8) -> Option<Self> {
        match b {
            0x00 => Some(Self::TaprootDefault),
            0x01 => Some(Self::All),
            0x02 => Some(Self::None),
            0x03 => Some(Self::Single),
            0x81 => Some(Self::AllAnyoneCanPay),
            0x82 => Some(Self::NoneAnyoneCanPay),
            0x83 => Some(Self::SingleAnyoneCanPay),
            _ => None,
        }
    }
    
    pub fn is_anyonecanpay(&self) -> bool {
        (*self as u8) & 0x80 != 0
    }
}

/// Bitcoin transaction input for sighash calculation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BitcoinInput {
    /// Previous transaction hash (txid)
    pub txid: [u8; 32],
    /// Output index in previous transaction
    pub vout: u32,
    /// Script code for signing (scriptPubKey or redeemScript)
    pub script_code: Vec<u8>,
    /// Value in satoshis (required for SegWit)
    pub value: u64,
    /// Sequence number
    pub sequence: u32,
    /// Derivation path for this input's key
    pub derivation_path: Option<String>,
    /// Input type
    pub input_type: BitcoinInputType,
}

/// Type of Bitcoin input
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum BitcoinInputType {
    /// Legacy P2PKH
    P2PKH,
    /// Legacy P2SH
    P2SH,
    /// Native SegWit P2WPKH
    P2WPKH,
    /// Native SegWit P2WSH
    P2WSH,
    /// SegWit-in-P2SH
    P2SH_P2WPKH,
    /// Taproot key path
    P2TR_KeyPath,
    /// Taproot script path
    P2TR_ScriptPath,
}

impl BitcoinInputType {
    pub fn is_segwit(&self) -> bool {
        matches!(self, Self::P2WPKH | Self::P2WSH | Self::P2SH_P2WPKH)
    }
    
    pub fn is_taproot(&self) -> bool {
        matches!(self, Self::P2TR_KeyPath | Self::P2TR_ScriptPath)
    }
}

/// Bitcoin transaction output
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BitcoinOutput {
    /// Value in satoshis
    pub value: u64,
    /// Output script (scriptPubKey)
    pub script_pubkey: Vec<u8>,
}

/// Unsigned Bitcoin transaction for pre-image generation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UnsignedBitcoinTransaction {
    /// Transaction version
    pub version: i32,
    /// Transaction inputs
    pub inputs: Vec<BitcoinInput>,
    /// Transaction outputs
    pub outputs: Vec<BitcoinOutput>,
    /// Locktime
    pub locktime: u32,
}

/// Get sighashes for all inputs in a Bitcoin transaction
pub fn get_bitcoin_sighashes(
    tx: &UnsignedBitcoinTransaction,
    sighash_type: BitcoinSigHashType,
) -> PreImageResult<Vec<PreImageHash>> {
    let mut hashes = Vec::with_capacity(tx.inputs.len());
    
    for (index, input) in tx.inputs.iter().enumerate() {
        let hash = if input.input_type.is_taproot() {
            get_taproot_sighash(tx, index, sighash_type)?
        } else if input.input_type.is_segwit() {
            get_segwit_sighash(tx, index, sighash_type)?
        } else {
            get_legacy_sighash(tx, index, sighash_type)?
        };
        
        let algorithm = if input.input_type.is_taproot() {
            SigningAlgorithm::Secp256k1Schnorr
        } else {
            SigningAlgorithm::Secp256k1Ecdsa
        };
        
        let signer_id = input.derivation_path.clone()
            .unwrap_or_else(|| format!("input_{}", index));
        
        let pre_image = PreImageHash::new(hash, signer_id, algorithm)
            .with_input_index(index)
            .with_description(format!(
                "Bitcoin {} input {} ({} sats)",
                format!("{:?}", input.input_type),
                index,
                input.value
            ));
        
        hashes.push(pre_image);
    }
    
    Ok(hashes)
}

/// Calculate legacy (pre-SegWit) sighash
fn get_legacy_sighash(
    tx: &UnsignedBitcoinTransaction,
    input_index: usize,
    sighash_type: BitcoinSigHashType,
) -> PreImageResult<[u8; 32]> {
    if input_index >= tx.inputs.len() {
        return Err(PreImageError::InvalidInputIndex(input_index));
    }
    
    let mut serialized = Vec::new();
    
    // Version
    serialized.extend_from_slice(&tx.version.to_le_bytes());
    
    // Inputs
    let input_count = if sighash_type.is_anyonecanpay() { 1 } else { tx.inputs.len() };
    serialized.push(input_count as u8);
    
    for (i, input) in tx.inputs.iter().enumerate() {
        if sighash_type.is_anyonecanpay() && i != input_index {
            continue;
        }
        
        // txid (reversed for Bitcoin)
        let mut txid = input.txid;
        txid.reverse();
        serialized.extend_from_slice(&txid);
        
        // vout
        serialized.extend_from_slice(&input.vout.to_le_bytes());
        
        // script (only for the input being signed)
        if i == input_index {
            let script_len = input.script_code.len();
            serialized.push(script_len as u8);
            serialized.extend_from_slice(&input.script_code);
        } else {
            serialized.push(0x00); // Empty script for other inputs
        }
        
        // sequence
        let seq = match sighash_type {
            BitcoinSigHashType::None | BitcoinSigHashType::Single
            | BitcoinSigHashType::NoneAnyoneCanPay | BitcoinSigHashType::SingleAnyoneCanPay => {
                if i != input_index { 0 } else { input.sequence }
            }
            _ => input.sequence,
        };
        serialized.extend_from_slice(&seq.to_le_bytes());
    }
    
    // Outputs
    match sighash_type {
        BitcoinSigHashType::None | BitcoinSigHashType::NoneAnyoneCanPay => {
            serialized.push(0x00);
        }
        BitcoinSigHashType::Single | BitcoinSigHashType::SingleAnyoneCanPay => {
            if input_index >= tx.outputs.len() {
                // SIGHASH_SINGLE bug: if no corresponding output, hash is all zeros
                return Ok([0u8; 32]);
            }
            serialized.push(1);
            let output = &tx.outputs[input_index];
            serialized.extend_from_slice(&output.value.to_le_bytes());
            serialized.push(output.script_pubkey.len() as u8);
            serialized.extend_from_slice(&output.script_pubkey);
        }
        _ => {
            serialized.push(tx.outputs.len() as u8);
            for output in &tx.outputs {
                serialized.extend_from_slice(&output.value.to_le_bytes());
                serialized.push(output.script_pubkey.len() as u8);
                serialized.extend_from_slice(&output.script_pubkey);
            }
        }
    }
    
    // Locktime
    serialized.extend_from_slice(&tx.locktime.to_le_bytes());
    
    // Sighash type (4 bytes, little endian)
    serialized.extend_from_slice(&(sighash_type.to_byte() as u32).to_le_bytes());
    
    // Double SHA256
    let hash = sha256d::Hash::hash(&serialized);
    Ok(hash.to_byte_array())
}

/// Calculate BIP-143 (SegWit) sighash
fn get_segwit_sighash(
    tx: &UnsignedBitcoinTransaction,
    input_index: usize,
    sighash_type: BitcoinSigHashType,
) -> PreImageResult<[u8; 32]> {
    if input_index >= tx.inputs.len() {
        return Err(PreImageError::InvalidInputIndex(input_index));
    }
    
    let input = &tx.inputs[input_index];
    let mut serialized = Vec::new();
    
    // 1. Version
    serialized.extend_from_slice(&tx.version.to_le_bytes());
    
    // 2. hashPrevouts (all or none based on ANYONECANPAY)
    let hash_prevouts = if sighash_type.is_anyonecanpay() {
        [0u8; 32]
    } else {
        let mut prevouts = Vec::new();
        for inp in &tx.inputs {
            let mut txid = inp.txid;
            txid.reverse();
            prevouts.extend_from_slice(&txid);
            prevouts.extend_from_slice(&inp.vout.to_le_bytes());
        }
        sha256d::Hash::hash(&prevouts).to_byte_array()
    };
    serialized.extend_from_slice(&hash_prevouts);
    
    // 3. hashSequence
    let hash_sequence = match sighash_type {
        BitcoinSigHashType::All | BitcoinSigHashType::TaprootDefault => {
            let mut sequences = Vec::new();
            for inp in &tx.inputs {
                sequences.extend_from_slice(&inp.sequence.to_le_bytes());
            }
            sha256d::Hash::hash(&sequences).to_byte_array()
        }
        _ => [0u8; 32],
    };
    serialized.extend_from_slice(&hash_sequence);
    
    // 4. outpoint (txid + vout of input being signed)
    let mut txid = input.txid;
    txid.reverse();
    serialized.extend_from_slice(&txid);
    serialized.extend_from_slice(&input.vout.to_le_bytes());
    
    // 5. scriptCode
    let script_len = input.script_code.len();
    if script_len < 0xfd {
        serialized.push(script_len as u8);
    } else {
        serialized.push(0xfd);
        serialized.extend_from_slice(&(script_len as u16).to_le_bytes());
    }
    serialized.extend_from_slice(&input.script_code);
    
    // 6. value
    serialized.extend_from_slice(&input.value.to_le_bytes());
    
    // 7. nSequence
    serialized.extend_from_slice(&input.sequence.to_le_bytes());
    
    // 8. hashOutputs
    let hash_outputs = match sighash_type {
        BitcoinSigHashType::All | BitcoinSigHashType::AllAnyoneCanPay | BitcoinSigHashType::TaprootDefault => {
            let mut outputs = Vec::new();
            for out in &tx.outputs {
                outputs.extend_from_slice(&out.value.to_le_bytes());
                if out.script_pubkey.len() < 0xfd {
                    outputs.push(out.script_pubkey.len() as u8);
                } else {
                    outputs.push(0xfd);
                    outputs.extend_from_slice(&(out.script_pubkey.len() as u16).to_le_bytes());
                }
                outputs.extend_from_slice(&out.script_pubkey);
            }
            sha256d::Hash::hash(&outputs).to_byte_array()
        }
        BitcoinSigHashType::Single | BitcoinSigHashType::SingleAnyoneCanPay => {
            if input_index < tx.outputs.len() {
                let out = &tx.outputs[input_index];
                let mut output_ser = Vec::new();
                output_ser.extend_from_slice(&out.value.to_le_bytes());
                output_ser.push(out.script_pubkey.len() as u8);
                output_ser.extend_from_slice(&out.script_pubkey);
                sha256d::Hash::hash(&output_ser).to_byte_array()
            } else {
                [0u8; 32]
            }
        }
        _ => [0u8; 32],
    };
    serialized.extend_from_slice(&hash_outputs);
    
    // 9. nLocktime
    serialized.extend_from_slice(&tx.locktime.to_le_bytes());
    
    // 10. sighash type
    serialized.extend_from_slice(&(sighash_type.to_byte() as u32).to_le_bytes());
    
    // Double SHA256
    let hash = sha256d::Hash::hash(&serialized);
    Ok(hash.to_byte_array())
}

/// Calculate BIP-341 (Taproot) sighash
fn get_taproot_sighash(
    tx: &UnsignedBitcoinTransaction,
    input_index: usize,
    sighash_type: BitcoinSigHashType,
) -> PreImageResult<[u8; 32]> {
    use bitcoin::hashes::sha256;
    
    if input_index >= tx.inputs.len() {
        return Err(PreImageError::InvalidInputIndex(input_index));
    }
    
    // Taproot uses tagged hashes
    fn tagged_hash(tag: &str, data: &[u8]) -> [u8; 32] {
        let tag_hash = sha256::Hash::hash(tag.as_bytes()).to_byte_array();
        let mut engine = sha256::Hash::engine();
        bitcoin::hashes::HashEngine::input(&mut engine, &tag_hash);
        bitcoin::hashes::HashEngine::input(&mut engine, &tag_hash);
        bitcoin::hashes::HashEngine::input(&mut engine, data);
        sha256::Hash::from_engine(engine).to_byte_array()
    }
    
    let input = &tx.inputs[input_index];
    let sighash_byte = sighash_type.to_byte();
    let base_type = sighash_byte & 0x03;
    let anyone_can_pay = sighash_byte & 0x80 != 0;
    
    let mut serialized = Vec::new();
    
    // Epoch (0x00)
    serialized.push(0x00);
    
    // Sighash type
    serialized.push(sighash_byte);
    
    // Version
    serialized.extend_from_slice(&tx.version.to_le_bytes());
    
    // Locktime
    serialized.extend_from_slice(&tx.locktime.to_le_bytes());
    
    // sha_prevouts
    if !anyone_can_pay {
        let mut prevouts = Vec::new();
        for inp in &tx.inputs {
            let mut txid = inp.txid;
            txid.reverse();
            prevouts.extend_from_slice(&txid);
            prevouts.extend_from_slice(&inp.vout.to_le_bytes());
        }
        let sha_prevouts = sha256::Hash::hash(&prevouts).to_byte_array();
        serialized.extend_from_slice(&sha_prevouts);
    }
    
    // sha_amounts
    if !anyone_can_pay {
        let mut amounts = Vec::new();
        for inp in &tx.inputs {
            amounts.extend_from_slice(&inp.value.to_le_bytes());
        }
        let sha_amounts = sha256::Hash::hash(&amounts).to_byte_array();
        serialized.extend_from_slice(&sha_amounts);
    }
    
    // sha_scriptpubkeys
    if !anyone_can_pay {
        let mut scripts = Vec::new();
        for inp in &tx.inputs {
            scripts.push(inp.script_code.len() as u8);
            scripts.extend_from_slice(&inp.script_code);
        }
        let sha_scripts = sha256::Hash::hash(&scripts).to_byte_array();
        serialized.extend_from_slice(&sha_scripts);
    }
    
    // sha_sequences
    if !anyone_can_pay {
        let mut sequences = Vec::new();
        for inp in &tx.inputs {
            sequences.extend_from_slice(&inp.sequence.to_le_bytes());
        }
        let sha_sequences = sha256::Hash::hash(&sequences).to_byte_array();
        serialized.extend_from_slice(&sha_sequences);
    }
    
    // sha_outputs (based on sighash type)
    if base_type != 0x02 && base_type != 0x03 {
        // Not NONE or SINGLE
        let mut outputs = Vec::new();
        for out in &tx.outputs {
            outputs.extend_from_slice(&out.value.to_le_bytes());
            outputs.push(out.script_pubkey.len() as u8);
            outputs.extend_from_slice(&out.script_pubkey);
        }
        let sha_outputs = sha256::Hash::hash(&outputs).to_byte_array();
        serialized.extend_from_slice(&sha_outputs);
    }
    
    // spend_type (0x00 for key path)
    serialized.push(0x00);
    
    // input_index
    serialized.extend_from_slice(&(input_index as u32).to_le_bytes());
    
    // If ANYONECANPAY, add single input data
    if anyone_can_pay {
        let mut txid = input.txid;
        txid.reverse();
        serialized.extend_from_slice(&txid);
        serialized.extend_from_slice(&input.vout.to_le_bytes());
        serialized.extend_from_slice(&input.value.to_le_bytes());
        serialized.push(input.script_code.len() as u8);
        serialized.extend_from_slice(&input.script_code);
        serialized.extend_from_slice(&input.sequence.to_le_bytes());
    }
    
    // If SINGLE, add single output
    if base_type == 0x03 && input_index < tx.outputs.len() {
        let out = &tx.outputs[input_index];
        let mut output_ser = Vec::new();
        output_ser.extend_from_slice(&out.value.to_le_bytes());
        output_ser.push(out.script_pubkey.len() as u8);
        output_ser.extend_from_slice(&out.script_pubkey);
        let sha_output = sha256::Hash::hash(&output_ser).to_byte_array();
        serialized.extend_from_slice(&sha_output);
    }
    
    Ok(tagged_hash("TapSighash", &serialized))
}

#[cfg(test)]
mod tests {
    use super::*;
    
    fn sample_input() -> BitcoinInput {
        BitcoinInput {
            txid: [0u8; 32],
            vout: 0,
            script_code: vec![0x76, 0xa9, 0x14], // Partial P2PKH
            value: 100000,
            sequence: 0xffffffff,
            derivation_path: Some("m/44'/0'/0'/0/0".to_string()),
            input_type: BitcoinInputType::P2PKH,
        }
    }
    
    fn sample_output() -> BitcoinOutput {
        BitcoinOutput {
            value: 90000,
            script_pubkey: vec![0x76, 0xa9, 0x14],
        }
    }
    
    #[test]
    fn test_legacy_sighash() {
        let tx = UnsignedBitcoinTransaction {
            version: 1,
            inputs: vec![sample_input()],
            outputs: vec![sample_output()],
            locktime: 0,
        };
        
        let hashes = get_bitcoin_sighashes(&tx, BitcoinSigHashType::All).unwrap();
        
        assert_eq!(hashes.len(), 1);
        assert_eq!(hashes[0].input_index, Some(0));
        assert_eq!(hashes[0].algorithm, SigningAlgorithm::Secp256k1Ecdsa);
    }
    
    #[test]
    fn test_segwit_sighash() {
        let mut input = sample_input();
        input.input_type = BitcoinInputType::P2WPKH;
        
        let tx = UnsignedBitcoinTransaction {
            version: 2,
            inputs: vec![input],
            outputs: vec![sample_output()],
            locktime: 0,
        };
        
        let hashes = get_bitcoin_sighashes(&tx, BitcoinSigHashType::All).unwrap();
        
        assert_eq!(hashes.len(), 1);
        assert_eq!(hashes[0].algorithm, SigningAlgorithm::Secp256k1Ecdsa);
    }
    
    #[test]
    fn test_taproot_sighash() {
        let mut input = sample_input();
        input.input_type = BitcoinInputType::P2TR_KeyPath;
        
        let tx = UnsignedBitcoinTransaction {
            version: 2,
            inputs: vec![input],
            outputs: vec![sample_output()],
            locktime: 0,
        };
        
        let hashes = get_bitcoin_sighashes(&tx, BitcoinSigHashType::TaprootDefault).unwrap();
        
        assert_eq!(hashes.len(), 1);
        assert_eq!(hashes[0].algorithm, SigningAlgorithm::Secp256k1Schnorr);
    }
    
    #[test]
    fn test_multi_input() {
        let tx = UnsignedBitcoinTransaction {
            version: 1,
            inputs: vec![sample_input(), sample_input(), sample_input()],
            outputs: vec![sample_output()],
            locktime: 0,
        };
        
        let hashes = get_bitcoin_sighashes(&tx, BitcoinSigHashType::All).unwrap();
        
        assert_eq!(hashes.len(), 3);
        assert_eq!(hashes[0].input_index, Some(0));
        assert_eq!(hashes[1].input_index, Some(1));
        assert_eq!(hashes[2].input_index, Some(2));
    }
    
    #[test]
    fn test_invalid_input_index() {
        let tx = UnsignedBitcoinTransaction {
            version: 1,
            inputs: vec![sample_input()],
            outputs: vec![sample_output()],
            locktime: 0,
        };
        
        let result = get_legacy_sighash(&tx, 5, BitcoinSigHashType::All);
        assert!(result.is_err());
    }
    
    #[test]
    fn test_sighash_type_parsing() {
        assert_eq!(BitcoinSigHashType::from_byte(0x01), Some(BitcoinSigHashType::All));
        assert_eq!(BitcoinSigHashType::from_byte(0x81), Some(BitcoinSigHashType::AllAnyoneCanPay));
        assert!(BitcoinSigHashType::All.is_anyonecanpay() == false);
        assert!(BitcoinSigHashType::AllAnyoneCanPay.is_anyonecanpay());
    }
}
