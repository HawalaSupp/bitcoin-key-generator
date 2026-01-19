//! Solana Message Signing
//!
//! Implements off-chain message signing for Solana.
//! Solana uses Ed25519 directly without a message prefix.
//! Compatible with Phantom, Backpack, and other Solana wallets.

use super::{MessageSignature, MessageSignError, MessageSignResult};
use ed25519_dalek::{SigningKey, Signer, Verifier, VerifyingKey, Signature};

/// Sign a Solana off-chain message
/// 
/// Solana uses raw Ed25519 signatures without any prefix.
/// The message is signed directly as bytes.
/// 
/// # Arguments
/// * `message` - The message bytes to sign
/// * `private_key` - The Ed25519 private key (32 bytes)
/// 
/// # Returns
/// A 64-byte Ed25519 signature
pub fn sign_message(message: &[u8], private_key: &[u8]) -> MessageSignResult<MessageSignature> {
    if private_key.len() != 32 {
        return Err(MessageSignError::InvalidPrivateKey(
            format!("Expected 32 bytes, got {}", private_key.len())
        ));
    }
    
    let secret_bytes: [u8; 32] = private_key.try_into()
        .map_err(|_| MessageSignError::InvalidPrivateKey("Invalid key length".to_string()))?;
    
    let signing_key = SigningKey::from_bytes(&secret_bytes);
    let signature = signing_key.sign(message);
    
    Ok(MessageSignature::ed25519(signature.to_bytes()))
}

/// Verify a Solana signed message
/// 
/// # Arguments
/// * `message` - The original message bytes
/// * `signature` - The signature bytes (64 bytes)
/// * `public_key` - The Ed25519 public key (32 bytes)
/// 
/// # Returns
/// true if the signature is valid
pub fn verify_message(
    message: &[u8],
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
    
    let pub_bytes: [u8; 32] = public_key.try_into()
        .map_err(|_| MessageSignError::InvalidPrivateKey("Invalid public key length".to_string()))?;
    
    let verifying_key = VerifyingKey::from_bytes(&pub_bytes)
        .map_err(|e| MessageSignError::InvalidPrivateKey(e.to_string()))?;
    
    let sig_bytes: [u8; 64] = signature.try_into()
        .map_err(|_| MessageSignError::InvalidSignature("Invalid signature length".to_string()))?;
    
    let sig = Signature::from_bytes(&sig_bytes);
    
    match verifying_key.verify(message, &sig) {
        Ok(_) => Ok(true),
        Err(_) => Ok(false),
    }
}

/// Get the public key from a private key
/// 
/// # Arguments
/// * `private_key` - The Ed25519 private key (32 bytes)
/// 
/// # Returns
/// The 32-byte public key
pub fn get_public_key(private_key: &[u8]) -> MessageSignResult<[u8; 32]> {
    if private_key.len() != 32 {
        return Err(MessageSignError::InvalidPrivateKey(
            format!("Expected 32 bytes, got {}", private_key.len())
        ));
    }
    
    let secret_bytes: [u8; 32] = private_key.try_into()
        .map_err(|_| MessageSignError::InvalidPrivateKey("Invalid key length".to_string()))?;
    
    let signing_key = SigningKey::from_bytes(&secret_bytes);
    let verifying_key = signing_key.verifying_key();
    
    Ok(verifying_key.to_bytes())
}

/// Encode a public key to base58 (Solana address format)
pub fn encode_public_key_base58(public_key: &[u8; 32]) -> String {
    bs58::encode(public_key).into_string()
}

/// Decode a base58 Solana address to public key bytes
pub fn decode_public_key_base58(address: &str) -> MessageSignResult<[u8; 32]> {
    let decoded = bs58::decode(address)
        .into_vec()
        .map_err(|e| MessageSignError::EncodingError(format!("Invalid base58: {}", e)))?;
    
    if decoded.len() != 32 {
        return Err(MessageSignError::InvalidPrivateKey(
            format!("Expected 32 bytes, got {}", decoded.len())
        ));
    }
    
    let mut result = [0u8; 32];
    result.copy_from_slice(&decoded);
    Ok(result)
}

/// Sign a message with verification data for Phantom wallet
/// 
/// # Arguments
/// * `message` - The message to sign (typically a human-readable string)
/// * `private_key` - The Ed25519 private key (32 bytes)
/// 
/// # Returns
/// Signature and public key for verification
pub fn sign_message_for_phantom(
    message: &str,
    private_key: &[u8],
) -> MessageSignResult<(MessageSignature, String)> {
    let sig = sign_message(message.as_bytes(), private_key)?;
    let public_key = get_public_key(private_key)?;
    let address = encode_public_key_base58(&public_key);
    
    Ok((sig, address))
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
    fn test_sign_and_verify() {
        let (signing_key, verifying_key) = generate_test_keypair();
        
        let message = b"Hello, Solana!";
        let sig = sign_message(message, signing_key.as_bytes()).unwrap();
        
        assert_eq!(sig.signature.len(), 130); // 0x + 128 hex chars
        assert!(sig.v.is_none()); // Ed25519 has no v value
        
        let sig_bytes = hex::decode(sig.signature.trim_start_matches("0x")).unwrap();
        
        let valid = verify_message(message, &sig_bytes, verifying_key.as_bytes()).unwrap();
        assert!(valid);
    }
    
    #[test]
    fn test_verify_wrong_message() {
        let (signing_key, verifying_key) = generate_test_keypair();
        
        let message = b"Original message";
        let sig = sign_message(message, signing_key.as_bytes()).unwrap();
        let sig_bytes = hex::decode(sig.signature.trim_start_matches("0x")).unwrap();
        
        let valid = verify_message(b"Different message", &sig_bytes, verifying_key.as_bytes()).unwrap();
        assert!(!valid);
    }
    
    #[test]
    fn test_get_public_key() {
        let (signing_key, verifying_key) = generate_test_keypair();
        
        let pub_key = get_public_key(signing_key.as_bytes()).unwrap();
        assert_eq!(pub_key, verifying_key.to_bytes());
    }
    
    #[test]
    fn test_base58_encoding() {
        let (_, verifying_key) = generate_test_keypair();
        let pub_bytes = verifying_key.to_bytes();
        
        let encoded = encode_public_key_base58(&pub_bytes);
        let decoded = decode_public_key_base58(&encoded).unwrap();
        
        assert_eq!(decoded, pub_bytes);
    }
    
    #[test]
    fn test_phantom_signing() {
        let (signing_key, _) = generate_test_keypair();
        
        let (sig, address) = sign_message_for_phantom(
            "Please sign this message",
            signing_key.as_bytes(),
        ).unwrap();
        
        assert!(!address.is_empty());
        assert!(sig.signature.starts_with("0x"));
    }
    
    #[test]
    fn test_invalid_key_length() {
        let short_key = vec![0u8; 16];
        let result = sign_message(b"test", &short_key);
        assert!(result.is_err());
    }
    
    #[test]
    fn test_empty_message() {
        let (signing_key, verifying_key) = generate_test_keypair();
        
        let message = b"";
        let sig = sign_message(message, signing_key.as_bytes()).unwrap();
        let sig_bytes = hex::decode(sig.signature.trim_start_matches("0x")).unwrap();
        
        let valid = verify_message(message, &sig_bytes, verifying_key.as_bytes()).unwrap();
        assert!(valid);
    }
}
