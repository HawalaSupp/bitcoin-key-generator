//! Tezos Message Signing
//!
//! Implements off-chain message signing for Tezos.
//! Reference: https://tezostaquito.io/docs/signing/
//!
//! Format: "Tezos Signed Message: {dapp_url} {timestamp} {message}"

use super::{MessageSignature, MessageSignError, MessageSignResult};
use ed25519_dalek::{SigningKey, Signer, Verifier, VerifyingKey, Signature};
use sha2::{Sha256, Digest};

/// Prefix for Tezos signed messages
const TEZOS_MESSAGE_PREFIX: &str = "Tezos Signed Message: ";

/// Format a message for Tezos signing
/// 
/// # Arguments
/// * `message` - The message to sign
/// * `dapp_url` - The dApp URL requesting the signature
/// * `timestamp` - Optional timestamp string
pub fn format_message(message: &str, dapp_url: &str, timestamp: Option<&str>) -> String {
    match timestamp {
        Some(ts) => format!("{}{} {} {}", TEZOS_MESSAGE_PREFIX, dapp_url, ts, message),
        None => format!("{}{} {}", TEZOS_MESSAGE_PREFIX, dapp_url, message),
    }
}

/// Convert a formatted message to signing payload
/// 
/// # Arguments
/// * `formatted_message` - The formatted message string
/// 
/// # Returns
/// The payload bytes ready for signing
pub fn message_to_payload(formatted_message: &str) -> Vec<u8> {
    // Tezos uses a specific encoding - simplified here
    // In production, this would use Micheline encoding
    let mut payload = Vec::new();
    
    // Add Micheline magic bytes for string type
    payload.push(0x05); // Micheline tag
    payload.push(0x01); // String type
    
    // Add length-prefixed message
    let message_bytes = formatted_message.as_bytes();
    let len = message_bytes.len() as u32;
    payload.extend_from_slice(&len.to_be_bytes());
    payload.extend_from_slice(message_bytes);
    
    payload
}

/// Hash the payload for signing
/// 
/// # Arguments
/// * `payload` - The raw payload bytes
/// 
/// # Returns
/// The Blake2b hash of the payload (32 bytes)
pub fn hash_payload(payload: &[u8]) -> [u8; 32] {
    // Tezos uses Blake2b, but for simplicity we use SHA256 here
    // In production, use Blake2b-256
    let mut hasher = Sha256::new();
    hasher.update(payload);
    let result = hasher.finalize();
    
    let mut hash = [0u8; 32];
    hash.copy_from_slice(&result);
    hash
}

/// Sign a Tezos message
/// 
/// # Arguments
/// * `message` - The message to sign
/// * `dapp_url` - The dApp URL requesting the signature
/// * `private_key` - The Ed25519 private key (32 bytes)
/// 
/// # Returns
/// A signature in base58 format (edsig prefix for Ed25519)
pub fn sign_message(
    message: &str,
    dapp_url: &str,
    private_key: &[u8],
) -> MessageSignResult<MessageSignature> {
    if private_key.len() != 32 {
        return Err(MessageSignError::InvalidPrivateKey(
            format!("Expected 32 bytes, got {}", private_key.len())
        ));
    }
    
    // Format and encode the message
    let formatted = format_message(message, dapp_url, None);
    let payload = message_to_payload(&formatted);
    let hash = hash_payload(&payload);
    
    // Sign with Ed25519
    let secret_bytes: [u8; 32] = private_key.try_into()
        .map_err(|_| MessageSignError::InvalidPrivateKey("Invalid key length".to_string()))?;
    
    let signing_key = SigningKey::from_bytes(&secret_bytes);
    let signature = signing_key.sign(&hash);
    
    // Return Ed25519 signature
    Ok(MessageSignature::ed25519(signature.to_bytes()))
}

/// Verify a Tezos signed message
/// 
/// # Arguments
/// * `message` - The original message
/// * `dapp_url` - The dApp URL that requested the signature
/// * `signature` - The signature bytes (64 bytes for Ed25519)
/// * `public_key` - The Ed25519 public key (32 bytes)
pub fn verify_message(
    message: &str,
    dapp_url: &str,
    signature: &[u8],
    public_key: &[u8],
) -> MessageSignResult<bool> {
    if signature.len() != 64 {
        return Err(MessageSignError::InvalidSignature(
            format!("Expected 64 bytes, got {}", signature.len())
        ));
    }
    
    if public_key.len() != 32 {
        return Err(MessageSignError::InvalidPrivateKey(
            format!("Expected 32 bytes public key, got {}", public_key.len())
        ));
    }
    
    // Format and encode the message
    let formatted = format_message(message, dapp_url, None);
    let payload = message_to_payload(&formatted);
    let hash = hash_payload(&payload);
    
    // Verify with Ed25519
    let pub_bytes: [u8; 32] = public_key.try_into()
        .map_err(|_| MessageSignError::InvalidPrivateKey("Invalid public key length".to_string()))?;
    
    let verifying_key = VerifyingKey::from_bytes(&pub_bytes)
        .map_err(|e| MessageSignError::InvalidPrivateKey(e.to_string()))?;
    
    let sig_bytes: [u8; 64] = signature.try_into()
        .map_err(|_| MessageSignError::InvalidSignature("Invalid signature length".to_string()))?;
    
    let sig = Signature::from_bytes(&sig_bytes);
    
    match verifying_key.verify(&hash, &sig) {
        Ok(_) => Ok(true),
        Err(_) => Ok(false),
    }
}

/// Encode a signature to Tezos base58 format (edsig prefix)
pub fn encode_signature_base58(signature: &[u8]) -> MessageSignResult<String> {
    if signature.len() != 64 {
        return Err(MessageSignError::InvalidSignature(
            format!("Expected 64 bytes, got {}", signature.len())
        ));
    }
    
    // edsig prefix bytes for Tezos Ed25519 signatures
    let prefix: [u8; 5] = [0x09, 0xf5, 0xcd, 0x86, 0x12];
    
    let mut data = Vec::with_capacity(prefix.len() + signature.len() + 4);
    data.extend_from_slice(&prefix);
    data.extend_from_slice(signature);
    
    // Add 4-byte checksum (double SHA256)
    let checksum = compute_checksum(&data);
    data.extend_from_slice(&checksum);
    
    Ok(bs58::encode(data).into_string())
}

/// Compute Tezos-style checksum (first 4 bytes of double SHA256)
fn compute_checksum(data: &[u8]) -> [u8; 4] {
    use sha2::{Sha256, Digest};
    let hash1 = Sha256::digest(data);
    let hash2 = Sha256::digest(&hash1);
    let mut checksum = [0u8; 4];
    checksum.copy_from_slice(&hash2[..4]);
    checksum
}

/// Decode a Tezos base58 signature to bytes
pub fn decode_signature_base58(encoded: &str) -> MessageSignResult<[u8; 64]> {
    let decoded = bs58::decode(encoded)
        .into_vec()
        .map_err(|e| MessageSignError::InvalidSignature(format!("Invalid base58: {}", e)))?;
    
    // Remove the 5-byte prefix and 4-byte checksum
    if decoded.len() != 73 {
        return Err(MessageSignError::InvalidSignature(
            format!("Expected 73 bytes (5 prefix + 64 sig + 4 checksum), got {}", decoded.len())
        ));
    }
    
    // Verify checksum
    let payload = &decoded[..69];
    let checksum = &decoded[69..];
    let expected_checksum = compute_checksum(payload);
    if checksum != expected_checksum {
        return Err(MessageSignError::InvalidSignature("Invalid checksum".to_string()));
    }
    
    let mut sig = [0u8; 64];
    sig.copy_from_slice(&decoded[5..69]);
    Ok(sig)
}

#[cfg(test)]
mod tests {
    use super::*;
    
    fn generate_test_keypair() -> (SigningKey, VerifyingKey) {
        let secret = [
            0x9d, 0x61, 0xb1, 0x9d, 0xef, 0xfd, 0x5a, 0x60,
            0xba, 0x84, 0x4a, 0xf4, 0x92, 0xec, 0x2c, 0xc4,
            0x44, 0x49, 0xc5, 0x69, 0x7b, 0x32, 0x69, 0x19,
            0x70, 0x3b, 0xac, 0x03, 0x1c, 0xae, 0x7f, 0x60,
        ];
        let signing_key = SigningKey::from_bytes(&secret);
        let verifying_key = signing_key.verifying_key();
        (signing_key, verifying_key)
    }
    
    #[test]
    fn test_format_message() {
        let formatted = format_message("Hello", "https://example.com", None);
        assert_eq!(formatted, "Tezos Signed Message: https://example.com Hello");
        
        let with_ts = format_message("Hello", "https://example.com", Some("2024-01-01"));
        assert_eq!(with_ts, "Tezos Signed Message: https://example.com 2024-01-01 Hello");
    }
    
    #[test]
    fn test_message_to_payload() {
        let formatted = "Tezos Signed Message: test.com Hello";
        let payload = message_to_payload(formatted);
        
        // Check magic bytes
        assert_eq!(payload[0], 0x05);
        assert_eq!(payload[1], 0x01);
        
        // Check length is encoded
        let len = u32::from_be_bytes([payload[2], payload[3], payload[4], payload[5]]);
        assert_eq!(len as usize, formatted.len());
    }
    
    #[test]
    fn test_sign_and_verify() {
        let (signing_key, verifying_key) = generate_test_keypair();
        
        let sig = sign_message(
            "Test message",
            "https://test.com",
            signing_key.as_bytes(),
        ).unwrap();
        
        assert_eq!(sig.signature.len(), 130); // 0x + 128 hex chars
        
        let sig_bytes = hex::decode(sig.signature.trim_start_matches("0x")).unwrap();
        
        let valid = verify_message(
            "Test message",
            "https://test.com",
            &sig_bytes,
            verifying_key.as_bytes(),
        ).unwrap();
        
        assert!(valid);
    }
    
    #[test]
    fn test_verify_wrong_message() {
        let (signing_key, verifying_key) = generate_test_keypair();
        
        let sig = sign_message(
            "Original message",
            "https://test.com",
            signing_key.as_bytes(),
        ).unwrap();
        
        let sig_bytes = hex::decode(sig.signature.trim_start_matches("0x")).unwrap();
        
        let valid = verify_message(
            "Different message",
            "https://test.com",
            &sig_bytes,
            verifying_key.as_bytes(),
        ).unwrap();
        
        assert!(!valid);
    }
    
    #[test]
    fn test_base58_signature_encoding() {
        let sig = [0u8; 64];
        let encoded = encode_signature_base58(&sig).unwrap();
        assert!(encoded.starts_with("edsig"));
        
        let decoded = decode_signature_base58(&encoded).unwrap();
        assert_eq!(decoded, sig);
    }
}
