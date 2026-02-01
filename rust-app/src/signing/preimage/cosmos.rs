//! Cosmos Pre-Image Hashing
//!
//! Generates signing hashes for Cosmos SDK transactions.
//! Supports Amino (legacy) and Protobuf (modern) sign modes.

use super::{PreImageHash, PreImageResult, SigningAlgorithm};
use serde::{Deserialize, Serialize};
use sha2::{Sha256, Digest};

/// Cosmos sign mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CosmosSignMode {
    /// Legacy Amino JSON signing
    Amino,
    /// Direct Protobuf signing (SIGN_MODE_DIRECT)
    Direct,
    /// Textual signing (SIGN_MODE_TEXTUAL) 
    Textual,
}

/// Cosmos fee specification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CosmosFee {
    /// Fee amount
    pub amount: Vec<CosmosCoin>,
    /// Gas limit
    pub gas: u64,
    /// Fee payer (optional)
    pub payer: Option<String>,
    /// Fee granter (optional)
    pub granter: Option<String>,
}

/// Cosmos coin denomination and amount
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CosmosCoin {
    /// Denomination (e.g., "uatom", "uosmo")
    pub denom: String,
    /// Amount as string (to handle large values)
    pub amount: String,
}

/// Cosmos message for signing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CosmosMessage {
    /// Message type URL (e.g., "/cosmos.bank.v1beta1.MsgSend")
    pub type_url: String,
    /// Protobuf-encoded message value
    pub value: Vec<u8>,
    /// JSON representation (for Amino mode)
    pub json_value: Option<serde_json::Value>,
}

/// Signer information for Cosmos transaction
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CosmosSignerInfo {
    /// Bech32 address
    pub address: String,
    /// Account number
    pub account_number: u64,
    /// Sequence number
    pub sequence: u64,
    /// Public key bytes (compressed secp256k1 or ed25519)
    pub public_key: Option<Vec<u8>>,
    /// Derivation path
    pub derivation_path: Option<String>,
}

/// Unsigned Cosmos transaction
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UnsignedCosmosTransaction {
    /// Chain ID
    pub chain_id: String,
    /// Transaction messages
    pub messages: Vec<CosmosMessage>,
    /// Fee specification
    pub fee: CosmosFee,
    /// Memo
    pub memo: String,
    /// Timeout height (0 for no timeout)
    pub timeout_height: u64,
    /// Signing mode
    pub sign_mode: CosmosSignMode,
    /// Signer info
    pub signer: CosmosSignerInfo,
}

/// Get the signing hash for a Cosmos transaction
pub fn get_cosmos_sign_doc_hash(
    tx: &UnsignedCosmosTransaction,
) -> PreImageResult<PreImageHash> {
    let hash = match tx.sign_mode {
        CosmosSignMode::Amino => get_amino_sign_doc_hash(tx)?,
        CosmosSignMode::Direct => get_direct_sign_doc_hash(tx)?,
        CosmosSignMode::Textual => get_textual_sign_doc_hash(tx)?,
    };
    
    let signer_id = tx.signer.derivation_path.clone()
        .unwrap_or_else(|| tx.signer.address.clone());
    
    let description = format!(
        "Cosmos {} tx on {}: {} message(s)",
        format!("{:?}", tx.sign_mode),
        tx.chain_id,
        tx.messages.len()
    );
    
    // Cosmos uses secp256k1 ECDSA for most chains
    // Some chains (like Terra) use ed25519
    let algorithm = if tx.chain_id.contains("terra") || tx.chain_id.contains("injective") {
        SigningAlgorithm::Secp256k1Ecdsa // Injective uses secp256k1
    } else {
        SigningAlgorithm::Secp256k1Ecdsa
    };
    
    Ok(PreImageHash::new(hash, signer_id, algorithm)
        .with_description(description))
}

/// Generate Amino sign doc hash (legacy JSON signing)
fn get_amino_sign_doc_hash(tx: &UnsignedCosmosTransaction) -> PreImageResult<[u8; 32]> {
    // Build Amino sign doc JSON
    let sign_doc = serde_json::json!({
        "account_number": tx.signer.account_number.to_string(),
        "chain_id": tx.chain_id,
        "fee": {
            "amount": tx.fee.amount.iter().map(|c| {
                serde_json::json!({
                    "denom": c.denom,
                    "amount": c.amount
                })
            }).collect::<Vec<_>>(),
            "gas": tx.fee.gas.to_string()
        },
        "memo": tx.memo,
        "msgs": tx.messages.iter().map(|m| {
            m.json_value.clone().unwrap_or_else(|| {
                serde_json::json!({
                    "@type": m.type_url,
                    "value": hex::encode(&m.value)
                })
            })
        }).collect::<Vec<_>>(),
        "sequence": tx.signer.sequence.to_string()
    });
    
    // Amino requires deterministic JSON serialization (sorted keys, no whitespace)
    let json_bytes = canonical_json_bytes(&sign_doc)?;
    
    // SHA256 hash
    let mut hasher = Sha256::new();
    hasher.update(&json_bytes);
    let result = hasher.finalize();
    
    let mut hash = [0u8; 32];
    hash.copy_from_slice(&result);
    Ok(hash)
}

/// Generate Direct (Protobuf) sign doc hash
fn get_direct_sign_doc_hash(tx: &UnsignedCosmosTransaction) -> PreImageResult<[u8; 32]> {
    // Build SignDoc protobuf
    // SignDoc = { body_bytes, auth_info_bytes, chain_id, account_number }
    
    // Build TxBody
    let body_bytes = encode_tx_body(tx)?;
    
    // Build AuthInfo
    let auth_info_bytes = encode_auth_info(tx)?;
    
    // Encode SignDoc
    let mut sign_doc_bytes = Vec::new();
    
    // Field 1: body_bytes (bytes)
    if !body_bytes.is_empty() {
        sign_doc_bytes.push(0x0a); // field 1, wire type 2 (length-delimited)
        encode_varint(body_bytes.len() as u64, &mut sign_doc_bytes);
        sign_doc_bytes.extend_from_slice(&body_bytes);
    }
    
    // Field 2: auth_info_bytes (bytes)
    if !auth_info_bytes.is_empty() {
        sign_doc_bytes.push(0x12); // field 2, wire type 2
        encode_varint(auth_info_bytes.len() as u64, &mut sign_doc_bytes);
        sign_doc_bytes.extend_from_slice(&auth_info_bytes);
    }
    
    // Field 3: chain_id (string)
    if !tx.chain_id.is_empty() {
        sign_doc_bytes.push(0x1a); // field 3, wire type 2
        encode_varint(tx.chain_id.len() as u64, &mut sign_doc_bytes);
        sign_doc_bytes.extend_from_slice(tx.chain_id.as_bytes());
    }
    
    // Field 4: account_number (uint64)
    if tx.signer.account_number > 0 {
        sign_doc_bytes.push(0x20); // field 4, wire type 0 (varint)
        encode_varint(tx.signer.account_number, &mut sign_doc_bytes);
    }
    
    // SHA256 hash
    let mut hasher = Sha256::new();
    hasher.update(&sign_doc_bytes);
    let result = hasher.finalize();
    
    let mut hash = [0u8; 32];
    hash.copy_from_slice(&result);
    Ok(hash)
}

/// Generate Textual sign doc hash (ADR-050)
fn get_textual_sign_doc_hash(tx: &UnsignedCosmosTransaction) -> PreImageResult<[u8; 32]> {
    // Textual signing creates human-readable text for hardware wallets
    // For now, we use a simplified version
    let text = format!(
        "Chain: {}\nMessages: {}\nFee: {} {}\nMemo: {}\n",
        tx.chain_id,
        tx.messages.len(),
        tx.fee.amount.first().map(|c| c.amount.as_str()).unwrap_or("0"),
        tx.fee.amount.first().map(|c| c.denom.as_str()).unwrap_or("unknown"),
        tx.memo
    );
    
    let mut hasher = Sha256::new();
    hasher.update(text.as_bytes());
    let result = hasher.finalize();
    
    let mut hash = [0u8; 32];
    hash.copy_from_slice(&result);
    Ok(hash)
}

/// Encode TxBody protobuf
fn encode_tx_body(tx: &UnsignedCosmosTransaction) -> PreImageResult<Vec<u8>> {
    let mut body = Vec::new();
    
    // Field 1: messages (repeated Any)
    for msg in &tx.messages {
        body.push(0x0a); // field 1, wire type 2
        
        // Encode Any { type_url, value }
        let mut any = Vec::new();
        
        // type_url
        any.push(0x0a);
        encode_varint(msg.type_url.len() as u64, &mut any);
        any.extend_from_slice(msg.type_url.as_bytes());
        
        // value
        any.push(0x12);
        encode_varint(msg.value.len() as u64, &mut any);
        any.extend_from_slice(&msg.value);
        
        encode_varint(any.len() as u64, &mut body);
        body.extend_from_slice(&any);
    }
    
    // Field 2: memo (string)
    if !tx.memo.is_empty() {
        body.push(0x12);
        encode_varint(tx.memo.len() as u64, &mut body);
        body.extend_from_slice(tx.memo.as_bytes());
    }
    
    // Field 3: timeout_height (uint64)
    if tx.timeout_height > 0 {
        body.push(0x18);
        encode_varint(tx.timeout_height, &mut body);
    }
    
    Ok(body)
}

/// Encode AuthInfo protobuf
fn encode_auth_info(tx: &UnsignedCosmosTransaction) -> PreImageResult<Vec<u8>> {
    let mut auth_info = Vec::new();
    
    // Field 1: signer_infos (repeated SignerInfo)
    let signer_info = encode_signer_info(tx)?;
    auth_info.push(0x0a);
    encode_varint(signer_info.len() as u64, &mut auth_info);
    auth_info.extend_from_slice(&signer_info);
    
    // Field 2: fee (Fee)
    let fee = encode_fee(tx)?;
    auth_info.push(0x12);
    encode_varint(fee.len() as u64, &mut auth_info);
    auth_info.extend_from_slice(&fee);
    
    Ok(auth_info)
}

/// Encode SignerInfo protobuf
fn encode_signer_info(tx: &UnsignedCosmosTransaction) -> PreImageResult<Vec<u8>> {
    let mut signer_info = Vec::new();
    
    // Field 1: public_key (Any)
    if let Some(pk) = &tx.signer.public_key {
        signer_info.push(0x0a);
        
        // Encode Any for secp256k1 public key
        let mut any = Vec::new();
        let type_url = "/cosmos.crypto.secp256k1.PubKey";
        any.push(0x0a);
        encode_varint(type_url.len() as u64, &mut any);
        any.extend_from_slice(type_url.as_bytes());
        
        // PubKey { key: bytes }
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
    
    // Field 2: mode_info (ModeInfo)
    let mode_info = encode_mode_info(tx)?;
    signer_info.push(0x12);
    encode_varint(mode_info.len() as u64, &mut signer_info);
    signer_info.extend_from_slice(&mode_info);
    
    // Field 3: sequence (uint64)
    signer_info.push(0x18);
    encode_varint(tx.signer.sequence, &mut signer_info);
    
    Ok(signer_info)
}

/// Encode ModeInfo protobuf
fn encode_mode_info(tx: &UnsignedCosmosTransaction) -> PreImageResult<Vec<u8>> {
    let mut mode_info = Vec::new();
    
    // single { mode: SIGN_MODE_xxx }
    let mode = match tx.sign_mode {
        CosmosSignMode::Amino => 127, // SIGN_MODE_LEGACY_AMINO_JSON
        CosmosSignMode::Direct => 1,  // SIGN_MODE_DIRECT
        CosmosSignMode::Textual => 2, // SIGN_MODE_TEXTUAL
    };
    
    // Field 1: single (ModeInfo.Single)
    let mut single = Vec::new();
    single.push(0x08); // field 1 (mode), wire type 0
    encode_varint(mode, &mut single);
    
    mode_info.push(0x0a); // field 1, wire type 2
    encode_varint(single.len() as u64, &mut mode_info);
    mode_info.extend_from_slice(&single);
    
    Ok(mode_info)
}

/// Encode Fee protobuf
fn encode_fee(tx: &UnsignedCosmosTransaction) -> PreImageResult<Vec<u8>> {
    let mut fee = Vec::new();
    
    // Field 1: amount (repeated Coin)
    for coin in &tx.fee.amount {
        fee.push(0x0a);
        
        let mut coin_proto = Vec::new();
        // denom
        coin_proto.push(0x0a);
        encode_varint(coin.denom.len() as u64, &mut coin_proto);
        coin_proto.extend_from_slice(coin.denom.as_bytes());
        // amount
        coin_proto.push(0x12);
        encode_varint(coin.amount.len() as u64, &mut coin_proto);
        coin_proto.extend_from_slice(coin.amount.as_bytes());
        
        encode_varint(coin_proto.len() as u64, &mut fee);
        fee.extend_from_slice(&coin_proto);
    }
    
    // Field 2: gas_limit (uint64)
    fee.push(0x10);
    encode_varint(tx.fee.gas, &mut fee);
    
    Ok(fee)
}

/// Encode varint (protobuf base 128 varint)
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

/// Serialize JSON canonically (sorted keys, no whitespace)
fn canonical_json_bytes(value: &serde_json::Value) -> PreImageResult<Vec<u8>> {
    // Use sorted map serialization
    fn serialize_canonical(value: &serde_json::Value, out: &mut Vec<u8>) {
        match value {
            serde_json::Value::Null => out.extend_from_slice(b"null"),
            serde_json::Value::Bool(b) => {
                out.extend_from_slice(if *b { b"true" } else { b"false" });
            }
            serde_json::Value::Number(n) => {
                out.extend_from_slice(n.to_string().as_bytes());
            }
            serde_json::Value::String(s) => {
                out.push(b'"');
                for c in s.chars() {
                    match c {
                        '"' => out.extend_from_slice(b"\\\""),
                        '\\' => out.extend_from_slice(b"\\\\"),
                        '\n' => out.extend_from_slice(b"\\n"),
                        '\r' => out.extend_from_slice(b"\\r"),
                        '\t' => out.extend_from_slice(b"\\t"),
                        c if c.is_control() => {
                            out.extend_from_slice(format!("\\u{:04x}", c as u32).as_bytes());
                        }
                        c => {
                            let mut buf = [0u8; 4];
                            out.extend_from_slice(c.encode_utf8(&mut buf).as_bytes());
                        }
                    }
                }
                out.push(b'"');
            }
            serde_json::Value::Array(arr) => {
                out.push(b'[');
                for (i, v) in arr.iter().enumerate() {
                    if i > 0 {
                        out.push(b',');
                    }
                    serialize_canonical(v, out);
                }
                out.push(b']');
            }
            serde_json::Value::Object(obj) => {
                out.push(b'{');
                let mut keys: Vec<_> = obj.keys().collect();
                keys.sort();
                for (i, key) in keys.iter().enumerate() {
                    if i > 0 {
                        out.push(b',');
                    }
                    out.push(b'"');
                    out.extend_from_slice(key.as_bytes());
                    out.push(b'"');
                    out.push(b':');
                    serialize_canonical(&obj[*key], out);
                }
                out.push(b'}');
            }
        }
    }
    
    let mut out = Vec::new();
    serialize_canonical(value, &mut out);
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    
    fn sample_cosmos_tx() -> UnsignedCosmosTransaction {
        UnsignedCosmosTransaction {
            chain_id: "cosmoshub-4".to_string(),
            messages: vec![CosmosMessage {
                type_url: "/cosmos.bank.v1beta1.MsgSend".to_string(),
                value: vec![1, 2, 3, 4],
                json_value: Some(serde_json::json!({
                    "@type": "/cosmos.bank.v1beta1.MsgSend",
                    "from_address": "cosmos1...",
                    "to_address": "cosmos1...",
                    "amount": [{"denom": "uatom", "amount": "1000000"}]
                })),
            }],
            fee: CosmosFee {
                amount: vec![CosmosCoin {
                    denom: "uatom".to_string(),
                    amount: "5000".to_string(),
                }],
                gas: 200000,
                payer: None,
                granter: None,
            },
            memo: "test transaction".to_string(),
            timeout_height: 0,
            sign_mode: CosmosSignMode::Direct,
            signer: CosmosSignerInfo {
                address: "cosmos1abcdef...".to_string(),
                account_number: 12345,
                sequence: 42,
                public_key: Some(vec![0x02; 33]), // Compressed secp256k1
                derivation_path: Some("m/44'/118'/0'/0/0".to_string()),
            },
        }
    }
    
    #[test]
    fn test_direct_signing() {
        let tx = sample_cosmos_tx();
        let result = get_cosmos_sign_doc_hash(&tx);
        
        assert!(result.is_ok());
        let hash = result.unwrap();
        assert_eq!(hash.algorithm, SigningAlgorithm::Secp256k1Ecdsa);
        assert!(hash.description.contains("cosmoshub-4"));
    }
    
    #[test]
    fn test_amino_signing() {
        let mut tx = sample_cosmos_tx();
        tx.sign_mode = CosmosSignMode::Amino;
        
        let result = get_cosmos_sign_doc_hash(&tx);
        assert!(result.is_ok());
    }
    
    #[test]
    fn test_textual_signing() {
        let mut tx = sample_cosmos_tx();
        tx.sign_mode = CosmosSignMode::Textual;
        
        let result = get_cosmos_sign_doc_hash(&tx);
        assert!(result.is_ok());
    }
    
    #[test]
    fn test_canonical_json() {
        let json = serde_json::json!({
            "z": 1,
            "a": 2,
            "m": [3, 4, 5]
        });
        
        let bytes = canonical_json_bytes(&json).unwrap();
        let s = String::from_utf8(bytes).unwrap();
        
        // Keys should be sorted
        assert!(s.find("\"a\"").unwrap() < s.find("\"m\"").unwrap());
        assert!(s.find("\"m\"").unwrap() < s.find("\"z\"").unwrap());
    }
    
    #[test]
    fn test_encode_varint() {
        let mut buf = Vec::new();
        encode_varint(0, &mut buf);
        assert_eq!(buf, vec![0]);
        
        buf.clear();
        encode_varint(127, &mut buf);
        assert_eq!(buf, vec![127]);
        
        buf.clear();
        encode_varint(128, &mut buf);
        assert_eq!(buf, vec![0x80, 0x01]);
        
        buf.clear();
        encode_varint(300, &mut buf);
        assert_eq!(buf, vec![0xac, 0x02]);
    }
    
    #[test]
    fn test_multiple_messages() {
        let mut tx = sample_cosmos_tx();
        tx.messages.push(CosmosMessage {
            type_url: "/cosmos.staking.v1beta1.MsgDelegate".to_string(),
            value: vec![5, 6, 7, 8],
            json_value: None,
        });
        
        let result = get_cosmos_sign_doc_hash(&tx);
        assert!(result.is_ok());
        assert!(result.unwrap().description.contains("2 message(s)"));
    }
}
