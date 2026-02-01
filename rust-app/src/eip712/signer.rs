//! EIP-712 Signing
//!
//! ECDSA signing and verification for EIP-712 typed data.

use super::hasher::hash_typed_data;
use super::types::*;
use secp256k1::{Message, PublicKey, Secp256k1, SecretKey};


/// Sign EIP-712 typed data
///
/// Returns a signature with v, r, s components.
pub fn sign_typed_data(
    typed_data: &TypedData,
    private_key: &[u8],
) -> Result<Eip712Signature, Eip712Error> {
    // Calculate the hash to sign
    let hash = hash_typed_data(typed_data)?;
    
    // Sign the hash
    sign_hash(&hash, private_key)
}

/// Sign a pre-computed hash
pub fn sign_hash(hash: &[u8; 32], private_key: &[u8]) -> Result<Eip712Signature, Eip712Error> {
    if private_key.len() != 32 {
        return Err(Eip712Error::SigningError(format!(
            "invalid private key length: expected 32, got {}",
            private_key.len()
        )));
    }
    
    let secp = Secp256k1::new();
    
    let secret_key = SecretKey::from_slice(private_key)
        .map_err(|e| Eip712Error::SigningError(e.to_string()))?;
    
    let message = Message::from_digest_slice(hash)
        .map_err(|e| Eip712Error::SigningError(e.to_string()))?;
    
    let (recovery_id, signature) = secp
        .sign_ecdsa_recoverable(&message, &secret_key)
        .serialize_compact();
    
    let mut r = [0u8; 32];
    let mut s = [0u8; 32];
    r.copy_from_slice(&signature[0..32]);
    s.copy_from_slice(&signature[32..64]);
    
    // v is recovery_id + 27 (Ethereum standard)
    let v = recovery_id.to_i32() as u8 + 27;
    
    Ok(Eip712Signature::new(r, s, v))
}

/// Verify an EIP-712 signature
///
/// Returns true if the signature is valid for the given address.
pub fn verify_typed_data(
    typed_data: &TypedData,
    signature: &Eip712Signature,
    expected_address: &str,
) -> Result<bool, Eip712Error> {
    let hash = hash_typed_data(typed_data)?;
    verify_signature(&hash, signature, expected_address)
}

/// Verify a signature against a hash and expected address
pub fn verify_signature(
    hash: &[u8; 32],
    signature: &Eip712Signature,
    expected_address: &str,
) -> Result<bool, Eip712Error> {
    let recovered = recover_address(hash, signature)?;
    
    // Normalize addresses for comparison (lowercase, with 0x prefix)
    let expected = expected_address
        .to_lowercase()
        .strip_prefix("0x")
        .unwrap_or(&expected_address.to_lowercase())
        .to_string();
    let recovered_normalized = recovered
        .to_lowercase()
        .strip_prefix("0x")
        .unwrap_or(&recovered.to_lowercase())
        .to_string();
    
    Ok(expected == recovered_normalized)
}

/// Recover the signer's address from a signature
pub fn recover_address(
    hash: &[u8; 32],
    signature: &Eip712Signature,
) -> Result<String, Eip712Error> {
    let secp = Secp256k1::new();
    
    // Reconstruct the recovery ID
    let recovery_id = secp256k1::ecdsa::RecoveryId::from_i32((signature.v - 27) as i32)
        .map_err(|e| Eip712Error::InvalidSignature(e.to_string()))?;
    
    // Reconstruct the signature bytes
    let mut sig_bytes = [0u8; 64];
    sig_bytes[0..32].copy_from_slice(&signature.r);
    sig_bytes[32..64].copy_from_slice(&signature.s);
    
    let recoverable_sig = secp256k1::ecdsa::RecoverableSignature::from_compact(&sig_bytes, recovery_id)
        .map_err(|e| Eip712Error::InvalidSignature(e.to_string()))?;
    
    let message = Message::from_digest_slice(hash)
        .map_err(|e| Eip712Error::SigningError(e.to_string()))?;
    
    // Recover the public key
    let public_key = secp
        .recover_ecdsa(&message, &recoverable_sig)
        .map_err(|e| Eip712Error::InvalidSignature(e.to_string()))?;
    
    // Convert public key to Ethereum address
    let address = public_key_to_address(&public_key);
    
    Ok(format!("0x{}", hex::encode(address)))
}

/// Convert a secp256k1 public key to an Ethereum address
fn public_key_to_address(public_key: &PublicKey) -> [u8; 20] {
    use tiny_keccak::{Hasher, Keccak};
    
    // Get the uncompressed public key (65 bytes, starting with 0x04)
    let pubkey_bytes = public_key.serialize_uncompressed();
    
    // Hash the public key (excluding the 0x04 prefix)
    let mut hasher = Keccak::v256();
    let mut hash = [0u8; 32];
    hasher.update(&pubkey_bytes[1..]);
    hasher.finalize(&mut hash);
    
    // Take the last 20 bytes
    let mut address = [0u8; 20];
    address.copy_from_slice(&hash[12..32]);
    address
}

/// Compute the EIP-55 checksum address
pub fn checksum_address(address: &[u8; 20]) -> String {
    use tiny_keccak::{Hasher, Keccak};
    
    let hex_addr = hex::encode(address);
    
    // Hash the lowercase address
    let mut hasher = Keccak::v256();
    let mut hash = [0u8; 32];
    hasher.update(hex_addr.as_bytes());
    hasher.finalize(&mut hash);
    
    let hash_hex = hex::encode(hash);
    
    // Apply checksum
    let mut checksummed = String::with_capacity(42);
    checksummed.push_str("0x");
    
    for (i, c) in hex_addr.chars().enumerate() {
        let hash_char = hash_hex.chars().nth(i).unwrap();
        if c.is_ascii_alphabetic() {
            if hash_char.to_digit(16).unwrap() >= 8 {
                checksummed.push(c.to_ascii_uppercase());
            } else {
                checksummed.push(c.to_ascii_lowercase());
            }
        } else {
            checksummed.push(c);
        }
    }
    
    checksummed
}

#[cfg(test)]
mod signer_tests {
    use super::*;
    
    fn create_test_typed_data() -> TypedData {
        let json = r#"{
            "types": {
                "EIP712Domain": [
                    {"name": "name", "type": "string"},
                    {"name": "version", "type": "string"},
                    {"name": "chainId", "type": "uint256"},
                    {"name": "verifyingContract", "type": "address"}
                ],
                "Person": [
                    {"name": "name", "type": "string"},
                    {"name": "wallet", "type": "address"}
                ],
                "Mail": [
                    {"name": "from", "type": "Person"},
                    {"name": "to", "type": "Person"},
                    {"name": "contents", "type": "string"}
                ]
            },
            "primaryType": "Mail",
            "domain": {
                "name": "Ether Mail",
                "version": "1",
                "chainId": 1,
                "verifyingContract": "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC"
            },
            "message": {
                "from": {
                    "name": "Cow",
                    "wallet": "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826"
                },
                "to": {
                    "name": "Bob",
                    "wallet": "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB"
                },
                "contents": "Hello, Bob!"
            }
        }"#;
        
        TypedData::from_json(json).unwrap()
    }
    
    #[test]
    fn test_sign_and_verify() {
        let typed_data = create_test_typed_data();
        
        // Known test private key (DO NOT USE IN PRODUCTION)
        let private_key = hex::decode(
            "c85ef7d79691fe79573b1a7e708c6cf5a4e6e6e3c8c6d0a2b5e5e5e5e5e5e5e5"
        ).unwrap();
        
        // Sign the data
        let signature = sign_typed_data(&typed_data, &private_key).unwrap();
        
        // Recover the address
        let hash = hash_typed_data(&typed_data).unwrap();
        let recovered = recover_address(&hash, &signature).unwrap();
        
        // Verify the signature
        let valid = verify_typed_data(&typed_data, &signature, &recovered).unwrap();
        assert!(valid);
    }
    
    #[test]
    fn test_signature_format() {
        let sig = Eip712Signature::new([1u8; 32], [2u8; 32], 27);
        let hex = sig.to_hex();
        assert!(hex.starts_with("0x"));
        assert_eq!(hex.len(), 132); // 0x + 65 bytes * 2
    }
    
    #[test]
    fn test_checksum_address() {
        let addr_bytes = hex::decode("cd2a3d9f938e13cd947ec05abc7fe734df8dd826").unwrap();
        let mut addr = [0u8; 20];
        addr.copy_from_slice(&addr_bytes);
        
        let checksummed = checksum_address(&addr);
        assert_eq!(checksummed, "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826");
    }
}
