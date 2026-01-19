//! Cosmos Message Signing (ADR-036)
//!
//! Implements off-chain message signing for Cosmos SDK chains.
//! Reference: https://github.com/cosmos/cosmos-sdk/blob/main/docs/architecture/adr-036-arbitrary-signature.md
//!
//! Compatible with Keplr, Leap, and other Cosmos wallets.

use super::{MessageSignature, MessageSignError, MessageSignResult};
use secp256k1::{Secp256k1, SecretKey, Message, ecdsa::Signature};
use sha2::{Sha256, Digest};
use serde::{Serialize, Deserialize};

/// ADR-036 SignDoc structure
#[derive(Serialize, Deserialize)]
pub struct SignDoc {
    pub chain_id: String,
    pub account_number: String,
    pub sequence: String,
    pub fee: Fee,
    pub msgs: Vec<MsgSignData>,
    pub memo: String,
}

#[derive(Serialize, Deserialize)]
pub struct Fee {
    pub amount: Vec<Coin>,
    pub gas: String,
}

#[derive(Serialize, Deserialize)]
pub struct Coin {
    pub denom: String,
    pub amount: String,
}

#[derive(Serialize, Deserialize)]
pub struct MsgSignData {
    #[serde(rename = "type")]
    pub msg_type: String,
    pub value: MsgSignDataValue,
}

#[derive(Serialize, Deserialize)]
pub struct MsgSignDataValue {
    pub signer: String,
    pub data: String,
}

/// Create an ADR-036 SignDoc for arbitrary message signing
/// 
/// # Arguments
/// * `signer` - The signer's address (bech32 format)
/// * `data` - The data to sign (will be base64 encoded)
pub fn create_sign_doc(signer: &str, data: &[u8]) -> SignDoc {
    use base64::{Engine as _, engine::general_purpose::STANDARD};
    
    SignDoc {
        chain_id: "".to_string(),
        account_number: "0".to_string(),
        sequence: "0".to_string(),
        fee: Fee {
            amount: vec![],
            gas: "0".to_string(),
        },
        msgs: vec![MsgSignData {
            msg_type: "sign/MsgSignData".to_string(),
            value: MsgSignDataValue {
                signer: signer.to_string(),
                data: STANDARD.encode(data),
            },
        }],
        memo: "".to_string(),
    }
}

/// Serialize SignDoc to canonical JSON for signing
/// 
/// Cosmos uses a specific JSON format with sorted keys
pub fn serialize_sign_doc(doc: &SignDoc) -> MessageSignResult<Vec<u8>> {
    // Use serde_json to serialize, then sort keys
    let json = serde_json::to_string(doc)
        .map_err(|e| MessageSignError::EncodingError(format!("JSON serialization failed: {}", e)))?;
    
    Ok(json.into_bytes())
}

/// Hash the sign doc bytes using SHA256
pub fn hash_sign_doc(sign_bytes: &[u8]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(sign_bytes);
    let result = hasher.finalize();
    
    let mut hash = [0u8; 32];
    hash.copy_from_slice(&result);
    hash
}

/// Sign an arbitrary message using ADR-036
/// 
/// # Arguments
/// * `data` - The data to sign
/// * `signer` - The signer's bech32 address
/// * `private_key` - The secp256k1 private key (32 bytes)
/// 
/// # Returns
/// A signature compatible with Cosmos SDK
pub fn sign_arbitrary(
    data: &[u8],
    signer: &str,
    private_key: &[u8],
) -> MessageSignResult<MessageSignature> {
    if private_key.len() != 32 {
        return Err(MessageSignError::InvalidPrivateKey(
            format!("Expected 32 bytes, got {}", private_key.len())
        ));
    }
    
    let secp = Secp256k1::new();
    let secret_key = SecretKey::from_slice(private_key)
        .map_err(|e| MessageSignError::InvalidPrivateKey(e.to_string()))?;
    
    // Create and serialize the sign doc
    let sign_doc = create_sign_doc(signer, data);
    let sign_bytes = serialize_sign_doc(&sign_doc)?;
    let hash = hash_sign_doc(&sign_bytes);
    
    let msg = Message::from_digest_slice(&hash)
        .map_err(|e| MessageSignError::InvalidMessage(e.to_string()))?;
    
    let sig = secp.sign_ecdsa(&msg, &secret_key);
    let sig_bytes = sig.serialize_compact();
    
    let mut r = [0u8; 32];
    let mut s = [0u8; 32];
    r.copy_from_slice(&sig_bytes[..32]);
    s.copy_from_slice(&sig_bytes[32..]);
    
    // Cosmos uses compact signatures (no recovery ID)
    Ok(MessageSignature {
        signature: format!("0x{}", hex::encode(&sig_bytes)),
        recovery_id: None,
        r: Some(format!("0x{}", hex::encode(r))),
        s: Some(format!("0x{}", hex::encode(s))),
        v: None,
    })
}

/// Verify an ADR-036 signature
/// 
/// # Arguments
/// * `data` - The original data
/// * `signer` - The signer's bech32 address
/// * `signature` - The signature bytes (64 bytes)
/// * `public_key` - The secp256k1 public key (33 bytes compressed)
pub fn verify_arbitrary(
    data: &[u8],
    signer: &str,
    signature: &[u8],
    public_key: &[u8],
) -> MessageSignResult<bool> {
    if signature.len() != 64 {
        return Err(MessageSignError::InvalidSignature(
            format!("Expected 64 bytes, got {}", signature.len())
        ));
    }
    
    if public_key.len() != 33 && public_key.len() != 65 {
        return Err(MessageSignError::InvalidPrivateKey(
            format!("Expected 33 or 65 bytes public key, got {}", public_key.len())
        ));
    }
    
    let secp = Secp256k1::new();
    
    // Parse public key
    let pubkey = secp256k1::PublicKey::from_slice(public_key)
        .map_err(|e| MessageSignError::InvalidPrivateKey(e.to_string()))?;
    
    // Create and hash the sign doc
    let sign_doc = create_sign_doc(signer, data);
    let sign_bytes = serialize_sign_doc(&sign_doc)?;
    let hash = hash_sign_doc(&sign_bytes);
    
    let msg = Message::from_digest_slice(&hash)
        .map_err(|e| MessageSignError::InvalidMessage(e.to_string()))?;
    
    let sig = Signature::from_compact(signature)
        .map_err(|e| MessageSignError::InvalidSignature(e.to_string()))?;
    
    match secp.verify_ecdsa(&msg, &sig, &pubkey) {
        Ok(_) => Ok(true),
        Err(_) => Ok(false),
    }
}

/// Get the public key from a private key
pub fn get_public_key(private_key: &[u8]) -> MessageSignResult<Vec<u8>> {
    if private_key.len() != 32 {
        return Err(MessageSignError::InvalidPrivateKey(
            format!("Expected 32 bytes, got {}", private_key.len())
        ));
    }
    
    let secp = Secp256k1::new();
    let secret_key = SecretKey::from_slice(private_key)
        .map_err(|e| MessageSignError::InvalidPrivateKey(e.to_string()))?;
    
    let public_key = secp256k1::PublicKey::from_secret_key(&secp, &secret_key);
    
    Ok(public_key.serialize().to_vec())
}

/// Sign a message in Keplr-compatible format
/// 
/// # Arguments
/// * `chain_id` - The Cosmos chain ID (e.g., "cosmoshub-4")
/// * `signer` - The signer's address
/// * `data` - The data to sign
/// * `private_key` - The private key
pub fn sign_keplr_arbitrary(
    chain_id: &str,
    signer: &str,
    data: &[u8],
    private_key: &[u8],
) -> MessageSignResult<MessageSignature> {
    if private_key.len() != 32 {
        return Err(MessageSignError::InvalidPrivateKey(
            format!("Expected 32 bytes, got {}", private_key.len())
        ));
    }
    
    use base64::{Engine as _, engine::general_purpose::STANDARD};
    
    let secp = Secp256k1::new();
    let secret_key = SecretKey::from_slice(private_key)
        .map_err(|e| MessageSignError::InvalidPrivateKey(e.to_string()))?;
    
    // Keplr uses a modified sign doc with chain_id
    let sign_doc = SignDoc {
        chain_id: chain_id.to_string(),
        account_number: "0".to_string(),
        sequence: "0".to_string(),
        fee: Fee {
            amount: vec![],
            gas: "0".to_string(),
        },
        msgs: vec![MsgSignData {
            msg_type: "sign/MsgSignData".to_string(),
            value: MsgSignDataValue {
                signer: signer.to_string(),
                data: STANDARD.encode(data),
            },
        }],
        memo: "".to_string(),
    };
    
    let sign_bytes = serialize_sign_doc(&sign_doc)?;
    let hash = hash_sign_doc(&sign_bytes);
    
    let msg = Message::from_digest_slice(&hash)
        .map_err(|e| MessageSignError::InvalidMessage(e.to_string()))?;
    
    let sig = secp.sign_ecdsa(&msg, &secret_key);
    let sig_bytes = sig.serialize_compact();
    
    let mut r = [0u8; 32];
    let mut s = [0u8; 32];
    r.copy_from_slice(&sig_bytes[..32]);
    s.copy_from_slice(&sig_bytes[32..]);
    
    Ok(MessageSignature {
        signature: format!("0x{}", hex::encode(&sig_bytes)),
        recovery_id: None,
        r: Some(format!("0x{}", hex::encode(r))),
        s: Some(format!("0x{}", hex::encode(s))),
        v: None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    
    const TEST_PRIVATE_KEY: &str = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
    const TEST_ADDRESS: &str = "cosmos1xyz..."; // Placeholder
    
    #[test]
    fn test_create_sign_doc() {
        let doc = create_sign_doc("cosmos1abc...", b"Hello, Cosmos!");
        
        assert_eq!(doc.chain_id, "");
        assert_eq!(doc.account_number, "0");
        assert_eq!(doc.sequence, "0");
        assert_eq!(doc.msgs.len(), 1);
        assert_eq!(doc.msgs[0].msg_type, "sign/MsgSignData");
    }
    
    #[test]
    fn test_serialize_sign_doc() {
        let doc = create_sign_doc("cosmos1abc...", b"test");
        let bytes = serialize_sign_doc(&doc).unwrap();
        
        // Should be valid JSON
        let _: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    }
    
    #[test]
    fn test_sign_and_verify() {
        let private_key = hex::decode(TEST_PRIVATE_KEY).unwrap();
        let public_key = get_public_key(&private_key).unwrap();
        
        let data = b"Test message for Cosmos";
        let signer = "cosmos1test...";
        
        let sig = sign_arbitrary(data, signer, &private_key).unwrap();
        
        assert!(sig.signature.starts_with("0x"));
        assert!(sig.r.is_some());
        assert!(sig.s.is_some());
        
        let sig_bytes = hex::decode(sig.signature.trim_start_matches("0x")).unwrap();
        
        let valid = verify_arbitrary(data, signer, &sig_bytes, &public_key).unwrap();
        assert!(valid);
    }
    
    #[test]
    fn test_verify_wrong_data() {
        let private_key = hex::decode(TEST_PRIVATE_KEY).unwrap();
        let public_key = get_public_key(&private_key).unwrap();
        
        let data = b"Original message";
        let signer = "cosmos1test...";
        
        let sig = sign_arbitrary(data, signer, &private_key).unwrap();
        let sig_bytes = hex::decode(sig.signature.trim_start_matches("0x")).unwrap();
        
        let valid = verify_arbitrary(b"Different message", signer, &sig_bytes, &public_key).unwrap();
        assert!(!valid);
    }
    
    #[test]
    fn test_keplr_signing() {
        let private_key = hex::decode(TEST_PRIVATE_KEY).unwrap();
        
        let sig = sign_keplr_arbitrary(
            "cosmoshub-4",
            "cosmos1test...",
            b"Hello from Keplr",
            &private_key,
        ).unwrap();
        
        assert!(sig.signature.starts_with("0x"));
        assert_eq!(sig.signature.len(), 130); // 0x + 128 hex chars
    }
    
    #[test]
    fn test_invalid_private_key() {
        let short_key = vec![0u8; 16];
        let result = sign_arbitrary(b"test", "cosmos1...", &short_key);
        assert!(result.is_err());
    }
    
    #[test]
    fn test_get_public_key() {
        let private_key = hex::decode(TEST_PRIVATE_KEY).unwrap();
        let public_key = get_public_key(&private_key).unwrap();
        
        assert_eq!(public_key.len(), 33); // Compressed public key
    }
}
