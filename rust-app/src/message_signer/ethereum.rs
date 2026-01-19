//! Ethereum Personal Message Signing (EIP-191)
//!
//! Implements personal_sign and eth_sign functionality.
//! Reference: https://eips.ethereum.org/EIPS/eip-191
//!
//! Format: "\x19Ethereum Signed Message:\n" + len(message) + message

use super::{MessageSignature, MessageSignError, MessageSignResult};
use secp256k1::{Secp256k1, SecretKey, Message, ecdsa::{RecoverableSignature, RecoveryId}};
use tiny_keccak::{Hasher, Keccak};

/// Ethereum message prefix for personal_sign
const ETH_MESSAGE_PREFIX: &str = "\x19Ethereum Signed Message:\n";

/// Hash a message with the Ethereum personal sign prefix
/// 
/// # Arguments
/// * `message` - The raw message bytes
/// 
/// # Returns
/// The keccak256 hash of the prefixed message
pub fn personal_sign_hash(message: &[u8]) -> [u8; 32] {
    let prefix = format!("{}{}", ETH_MESSAGE_PREFIX, message.len());
    let mut data = Vec::with_capacity(prefix.len() + message.len());
    data.extend_from_slice(prefix.as_bytes());
    data.extend_from_slice(message);
    keccak256(&data)
}

/// Sign a message using Ethereum personal_sign
/// 
/// # Arguments
/// * `message` - The raw message to sign (UTF-8 string or raw bytes)
/// * `private_key` - 32-byte private key
/// 
/// # Returns
/// A recoverable signature with r, s, v components
pub fn personal_sign(message: &[u8], private_key: &[u8]) -> MessageSignResult<MessageSignature> {
    if private_key.len() != 32 {
        return Err(MessageSignError::InvalidPrivateKey(
            format!("Expected 32 bytes, got {}", private_key.len())
        ));
    }
    
    let secp = Secp256k1::new();
    let secret_key = SecretKey::from_slice(private_key)
        .map_err(|e| MessageSignError::InvalidPrivateKey(e.to_string()))?;
    
    let hash = personal_sign_hash(message);
    let msg = Message::from_digest_slice(&hash)
        .map_err(|e| MessageSignError::InvalidMessage(e.to_string()))?;
    
    let sig = secp.sign_ecdsa_recoverable(&msg, &secret_key);
    let (recovery_id, sig_bytes) = sig.serialize_compact();
    
    let mut r = [0u8; 32];
    let mut s = [0u8; 32];
    r.copy_from_slice(&sig_bytes[..32]);
    s.copy_from_slice(&sig_bytes[32..]);
    
    // v = 27 + recovery_id (legacy format)
    let v = 27 + recovery_id.to_i32() as u8;
    
    Ok(MessageSignature::ecdsa(r, s, v))
}

/// Sign a hex-encoded message
/// 
/// # Arguments
/// * `hex_message` - Hex-encoded message (with or without 0x prefix)
/// * `private_key` - 32-byte private key
pub fn personal_sign_hex(hex_message: &str, private_key: &[u8]) -> MessageSignResult<MessageSignature> {
    let message = hex::decode(hex_message.trim_start_matches("0x"))
        .map_err(|e| MessageSignError::InvalidMessage(format!("Invalid hex: {}", e)))?;
    personal_sign(&message, private_key)
}

/// Verify an Ethereum personal_sign signature
/// 
/// # Arguments
/// * `message` - The original message
/// * `signature` - The signature (65 bytes: r[32] + s[32] + v[1])
/// * `address` - Expected signer address (hex, with or without 0x)
/// 
/// # Returns
/// true if the signature is valid and matches the address
pub fn verify_personal_sign(
    message: &[u8],
    signature: &[u8],
    address: &str,
) -> MessageSignResult<bool> {
    let recovered = recover_address(message, signature)?;
    let expected = address.trim_start_matches("0x").to_lowercase();
    let actual = recovered.trim_start_matches("0x").to_lowercase();
    Ok(expected == actual)
}

/// Recover the signer's address from a signed message
/// 
/// # Arguments
/// * `message` - The original message
/// * `signature` - The signature (65 bytes: r[32] + s[32] + v[1])
/// 
/// # Returns
/// The checksummed Ethereum address
pub fn recover_address(message: &[u8], signature: &[u8]) -> MessageSignResult<String> {
    if signature.len() != 65 {
        return Err(MessageSignError::InvalidSignature(
            format!("Expected 65 bytes, got {}", signature.len())
        ));
    }
    
    let hash = personal_sign_hash(message);
    
    // Extract r, s, v from signature
    let v = signature[64];
    let recovery_id = if v >= 27 { v - 27 } else { v };
    
    if recovery_id > 3 {
        return Err(MessageSignError::InvalidSignature(
            format!("Invalid recovery id: {}", recovery_id)
        ));
    }
    
    let secp = Secp256k1::new();
    let msg = Message::from_digest_slice(&hash)
        .map_err(|e| MessageSignError::InvalidMessage(e.to_string()))?;
    
    let rec_id = RecoveryId::from_i32(recovery_id as i32)
        .map_err(|e| MessageSignError::InvalidSignature(e.to_string()))?;
    
    let recoverable_sig = RecoverableSignature::from_compact(&signature[..64], rec_id)
        .map_err(|e| MessageSignError::InvalidSignature(e.to_string()))?;
    
    let public_key = secp.recover_ecdsa(&msg, &recoverable_sig)
        .map_err(|e| MessageSignError::RecoveryFailed(e.to_string()))?;
    
    // Get uncompressed public key bytes (65 bytes, starts with 0x04)
    let pub_key_bytes = public_key.serialize_uncompressed();
    
    // Hash the public key (skip the 0x04 prefix)
    let pub_key_hash = keccak256(&pub_key_bytes[1..]);
    
    // Take the last 20 bytes as the address
    let address_bytes = &pub_key_hash[12..];
    let address = checksum_address(&hex::encode(address_bytes));
    
    Ok(address)
}

/// Create a checksummed Ethereum address (EIP-55)
fn checksum_address(address: &str) -> String {
    let address = address.trim_start_matches("0x").to_lowercase();
    let hash = keccak256(address.as_bytes());
    
    let mut result = String::with_capacity(42);
    result.push_str("0x");
    
    for (i, c) in address.chars().enumerate() {
        if c.is_ascii_digit() {
            result.push(c);
        } else {
            let nibble = hash[i / 2];
            let should_upper = if i % 2 == 0 {
                nibble >> 4 >= 8
            } else {
                nibble & 0x0f >= 8
            };
            result.push(if should_upper { c.to_ascii_uppercase() } else { c });
        }
    }
    
    result
}

/// Compute keccak256 hash
fn keccak256(data: &[u8]) -> [u8; 32] {
    let mut hasher = Keccak::v256();
    let mut output = [0u8; 32];
    hasher.update(data);
    hasher.finalize(&mut output);
    output
}

/// Sign a message that will be displayed to the user (eth_sign style)
/// 
/// Note: eth_sign is considered dangerous as it can be used to sign
/// transaction hashes. Prefer personal_sign for user-facing signatures.
/// 
/// # Arguments
/// * `hash` - The 32-byte hash to sign directly (NO prefix applied)
/// * `private_key` - 32-byte private key
pub fn eth_sign(hash: &[u8; 32], private_key: &[u8]) -> MessageSignResult<MessageSignature> {
    if private_key.len() != 32 {
        return Err(MessageSignError::InvalidPrivateKey(
            format!("Expected 32 bytes, got {}", private_key.len())
        ));
    }
    
    let secp = Secp256k1::new();
    let secret_key = SecretKey::from_slice(private_key)
        .map_err(|e| MessageSignError::InvalidPrivateKey(e.to_string()))?;
    
    let msg = Message::from_digest_slice(hash)
        .map_err(|e| MessageSignError::InvalidMessage(e.to_string()))?;
    
    let sig = secp.sign_ecdsa_recoverable(&msg, &secret_key);
    let (recovery_id, sig_bytes) = sig.serialize_compact();
    
    let mut r = [0u8; 32];
    let mut s = [0u8; 32];
    r.copy_from_slice(&sig_bytes[..32]);
    s.copy_from_slice(&sig_bytes[32..]);
    
    let v = 27 + recovery_id.to_i32() as u8;
    
    Ok(MessageSignature::ecdsa(r, s, v))
}

/// Verify an eth_sign signature
pub fn verify_eth_sign(
    hash: &[u8; 32],
    signature: &[u8],
    address: &str,
) -> MessageSignResult<bool> {
    if signature.len() != 65 {
        return Err(MessageSignError::InvalidSignature(
            format!("Expected 65 bytes, got {}", signature.len())
        ));
    }
    
    let v = signature[64];
    let recovery_id = if v >= 27 { v - 27 } else { v };
    
    if recovery_id > 3 {
        return Err(MessageSignError::InvalidSignature(
            format!("Invalid recovery id: {}", recovery_id)
        ));
    }
    
    let secp = Secp256k1::new();
    let msg = Message::from_digest_slice(hash)
        .map_err(|e| MessageSignError::InvalidMessage(e.to_string()))?;
    
    let rec_id = RecoveryId::from_i32(recovery_id as i32)
        .map_err(|e| MessageSignError::InvalidSignature(e.to_string()))?;
    
    let recoverable_sig = RecoverableSignature::from_compact(&signature[..64], rec_id)
        .map_err(|e| MessageSignError::InvalidSignature(e.to_string()))?;
    
    let public_key = secp.recover_ecdsa(&msg, &recoverable_sig)
        .map_err(|e| MessageSignError::RecoveryFailed(e.to_string()))?;
    
    let pub_key_bytes = public_key.serialize_uncompressed();
    let pub_key_hash = keccak256(&pub_key_bytes[1..]);
    let address_bytes = &pub_key_hash[12..];
    let recovered = checksum_address(&hex::encode(address_bytes));
    
    let expected = address.trim_start_matches("0x").to_lowercase();
    let actual = recovered.trim_start_matches("0x").to_lowercase();
    
    Ok(expected == actual)
}

#[cfg(test)]
mod tests {
    use super::*;
    
    // Test vector from EIP-191
    const TEST_PRIVATE_KEY: &str = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
    const TEST_ADDRESS: &str = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
    
    #[test]
    fn test_personal_sign_hash() {
        let message = b"Hello, World!";
        let hash = personal_sign_hash(message);
        
        // Verify the hash is 32 bytes
        assert_eq!(hash.len(), 32);
        
        // The hash should be deterministic
        let hash2 = personal_sign_hash(message);
        assert_eq!(hash, hash2);
    }
    
    #[test]
    fn test_personal_sign_and_recover() {
        let private_key = hex::decode(TEST_PRIVATE_KEY).unwrap();
        let message = b"Hello, Ethereum!";
        
        let sig = personal_sign(message, &private_key).unwrap();
        
        // Verify signature components exist
        assert!(sig.r.is_some());
        assert!(sig.s.is_some());
        assert!(sig.v.is_some());
        assert!(sig.signature.starts_with("0x"));
        assert_eq!(sig.signature.len(), 132); // 0x + 130 hex chars
        
        // Recover address
        let sig_bytes = hex::decode(sig.signature.trim_start_matches("0x")).unwrap();
        let recovered = recover_address(message, &sig_bytes).unwrap();
        
        assert_eq!(recovered.to_lowercase(), TEST_ADDRESS.to_lowercase());
    }
    
    #[test]
    fn test_verify_personal_sign() {
        let private_key = hex::decode(TEST_PRIVATE_KEY).unwrap();
        let message = b"Test message for verification";
        
        let sig = personal_sign(message, &private_key).unwrap();
        let sig_bytes = hex::decode(sig.signature.trim_start_matches("0x")).unwrap();
        
        let valid = verify_personal_sign(message, &sig_bytes, TEST_ADDRESS).unwrap();
        assert!(valid);
        
        // Wrong address should fail
        let wrong_address = "0x1234567890123456789012345678901234567890";
        let invalid = verify_personal_sign(message, &sig_bytes, wrong_address).unwrap();
        assert!(!invalid);
    }
    
    #[test]
    fn test_personal_sign_hex_message() {
        let private_key = hex::decode(TEST_PRIVATE_KEY).unwrap();
        let hex_message = "0x48656c6c6f"; // "Hello" in hex
        
        let sig = personal_sign_hex(hex_message, &private_key).unwrap();
        assert!(sig.signature.starts_with("0x"));
        
        // Verify it's the same as signing raw bytes
        let raw_message = hex::decode("48656c6c6f").unwrap();
        let sig2 = personal_sign(&raw_message, &private_key).unwrap();
        assert_eq!(sig.signature, sig2.signature);
    }
    
    #[test]
    fn test_eth_sign() {
        let private_key = hex::decode(TEST_PRIVATE_KEY).unwrap();
        let hash: [u8; 32] = keccak256(b"Test hash");
        
        let sig = eth_sign(&hash, &private_key).unwrap();
        
        assert!(sig.signature.starts_with("0x"));
        assert_eq!(sig.signature.len(), 132);
        
        let sig_bytes = hex::decode(sig.signature.trim_start_matches("0x")).unwrap();
        let valid = verify_eth_sign(&hash, &sig_bytes, TEST_ADDRESS).unwrap();
        assert!(valid);
    }
    
    #[test]
    fn test_checksum_address() {
        // Known checksummed addresses (EIP-55)
        let addr1 = checksum_address("f39fd6e51aad88f6f4ce6ab8827279cfffb92266");
        assert_eq!(addr1, "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
        
        // Use the same input address for correct test
        let addr2 = checksum_address("5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed");
        assert_eq!(addr2, "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed");
        
        // Test lowercase input produces correct checksum
        let addr3 = checksum_address("0000000000000000000000000000000000000000");
        assert_eq!(addr3, "0x0000000000000000000000000000000000000000");
    }
    
    #[test]
    fn test_empty_message() {
        let private_key = hex::decode(TEST_PRIVATE_KEY).unwrap();
        let message = b"";
        
        let sig = personal_sign(message, &private_key).unwrap();
        let sig_bytes = hex::decode(sig.signature.trim_start_matches("0x")).unwrap();
        
        let recovered = recover_address(message, &sig_bytes).unwrap();
        assert_eq!(recovered.to_lowercase(), TEST_ADDRESS.to_lowercase());
    }
    
    #[test]
    fn test_unicode_message() {
        let private_key = hex::decode(TEST_PRIVATE_KEY).unwrap();
        let message = "Hello 世界 🌍".as_bytes();
        
        let sig = personal_sign(message, &private_key).unwrap();
        let sig_bytes = hex::decode(sig.signature.trim_start_matches("0x")).unwrap();
        
        let valid = verify_personal_sign(message, &sig_bytes, TEST_ADDRESS).unwrap();
        assert!(valid);
    }
    
    #[test]
    fn test_invalid_private_key() {
        let short_key = vec![0u8; 16]; // Too short
        let result = personal_sign(b"test", &short_key);
        assert!(result.is_err());
    }
    
    #[test]
    fn test_invalid_signature_length() {
        let short_sig = vec![0u8; 32]; // Too short
        let result = recover_address(b"test", &short_sig);
        assert!(result.is_err());
    }
}
