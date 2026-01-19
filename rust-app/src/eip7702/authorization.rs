//! EIP-7702 Authorization Handling
//!
//! Implements authorization signing and verification for EIP-7702.

use super::types::{Authorization, Eip7702Error, Eip7702Result, AUTHORIZATION_MAGIC};
use secp256k1::{Secp256k1, SecretKey, Message, ecdsa::RecoverableSignature, ecdsa::RecoveryId};
use tiny_keccak::{Hasher, Keccak};

/// RLP encode an authorization for signing
/// 
/// Per EIP-7702: `rlp([chain_id, address, nonce])`
pub fn rlp_encode_authorization_for_signing(
    chain_id: u64,
    address: &[u8; 20],
    nonce: u64,
) -> Vec<u8> {
    let mut encoded = Vec::new();
    
    // RLP encode each field
    let chain_id_bytes = rlp_encode_u64(chain_id);
    let address_bytes = rlp_encode_bytes(address);
    let nonce_bytes = rlp_encode_u64(nonce);
    
    // Calculate total length
    let content_len = chain_id_bytes.len() + address_bytes.len() + nonce_bytes.len();
    
    // RLP list prefix
    if content_len < 56 {
        encoded.push(0xc0 + content_len as u8);
    } else {
        let len_bytes = encode_length(content_len);
        encoded.push(0xf7 + len_bytes.len() as u8);
        encoded.extend_from_slice(&len_bytes);
    }
    
    encoded.extend_from_slice(&chain_id_bytes);
    encoded.extend_from_slice(&address_bytes);
    encoded.extend_from_slice(&nonce_bytes);
    
    encoded
}

/// RLP encode a signed authorization
/// 
/// Per EIP-7702: `rlp([chain_id, address, nonce, y_parity, r, s])`
pub fn rlp_encode_authorization(auth: &Authorization) -> Vec<u8> {
    let mut encoded = Vec::new();
    
    // RLP encode each field
    let chain_id_bytes = rlp_encode_u64(auth.chain_id);
    let address_bytes = rlp_encode_bytes(&auth.address);
    let nonce_bytes = rlp_encode_u64(auth.nonce);
    let y_parity_bytes = rlp_encode_u64(auth.y_parity as u64);
    let r_bytes = rlp_encode_bytes_trimmed(&auth.r);
    let s_bytes = rlp_encode_bytes_trimmed(&auth.s);
    
    // Calculate total length
    let content_len = chain_id_bytes.len() + address_bytes.len() + nonce_bytes.len() 
        + y_parity_bytes.len() + r_bytes.len() + s_bytes.len();
    
    // RLP list prefix
    if content_len < 56 {
        encoded.push(0xc0 + content_len as u8);
    } else {
        let len_bytes = encode_length(content_len);
        encoded.push(0xf7 + len_bytes.len() as u8);
        encoded.extend_from_slice(&len_bytes);
    }
    
    encoded.extend_from_slice(&chain_id_bytes);
    encoded.extend_from_slice(&address_bytes);
    encoded.extend_from_slice(&nonce_bytes);
    encoded.extend_from_slice(&y_parity_bytes);
    encoded.extend_from_slice(&r_bytes);
    encoded.extend_from_slice(&s_bytes);
    
    encoded
}

/// Get the hash to sign for an authorization
/// 
/// Per EIP-7702: `keccak256(0x05 || rlp([chain_id, address, nonce]))`
pub fn authorization_signing_hash(
    chain_id: u64,
    address: &[u8; 20],
    nonce: u64,
) -> [u8; 32] {
    let rlp = rlp_encode_authorization_for_signing(chain_id, address, nonce);
    
    let mut data = Vec::with_capacity(1 + rlp.len());
    data.push(AUTHORIZATION_MAGIC);
    data.extend_from_slice(&rlp);
    
    keccak256(&data)
}

/// Sign an authorization
/// 
/// # Arguments
/// * `chain_id` - Chain ID for the authorization
/// * `address` - Contract address to delegate to
/// * `nonce` - Nonce of the authorizing account
/// * `private_key` - Private key of the authorizing account (32 bytes)
/// 
/// # Returns
/// A signed authorization
pub fn sign_authorization(
    chain_id: u64,
    address: [u8; 20],
    nonce: u64,
    private_key: &[u8],
) -> Eip7702Result<Authorization> {
    if private_key.len() != 32 {
        return Err(Eip7702Error::InvalidPrivateKey(
            format!("Expected 32 bytes, got {}", private_key.len())
        ));
    }
    
    let secp = Secp256k1::new();
    let secret_key = SecretKey::from_slice(private_key)
        .map_err(|e| Eip7702Error::InvalidPrivateKey(e.to_string()))?;
    
    // Get the signing hash
    let hash = authorization_signing_hash(chain_id, &address, nonce);
    
    let msg = Message::from_digest_slice(&hash)
        .map_err(|e| Eip7702Error::SigningError(e.to_string()))?;
    
    // Sign with recoverable signature
    let sig = secp.sign_ecdsa_recoverable(&msg, &secret_key);
    let (recovery_id, sig_bytes) = sig.serialize_compact();
    
    let mut r = [0u8; 32];
    let mut s = [0u8; 32];
    r.copy_from_slice(&sig_bytes[..32]);
    s.copy_from_slice(&sig_bytes[32..]);
    
    let y_parity = recovery_id.to_i32() as u8;
    
    Ok(Authorization::with_signature(chain_id, address, nonce, y_parity, r, s))
}

/// Recover the signer address from a signed authorization
/// 
/// # Arguments
/// * `auth` - The signed authorization
/// 
/// # Returns
/// The 20-byte Ethereum address of the signer
pub fn recover_authorization_signer(auth: &Authorization) -> Eip7702Result<[u8; 20]> {
    if !auth.is_signed() {
        return Err(Eip7702Error::UnsignedAuthorization);
    }
    
    let hash = authorization_signing_hash(auth.chain_id, &auth.address, auth.nonce);
    
    let secp = Secp256k1::new();
    let msg = Message::from_digest_slice(&hash)
        .map_err(|e| Eip7702Error::SigningError(e.to_string()))?;
    
    // Reconstruct signature
    let mut sig_bytes = [0u8; 64];
    sig_bytes[..32].copy_from_slice(&auth.r);
    sig_bytes[32..].copy_from_slice(&auth.s);
    
    let rec_id = RecoveryId::from_i32(auth.y_parity as i32)
        .map_err(|e| Eip7702Error::InvalidSignature(e.to_string()))?;
    
    let recoverable_sig = RecoverableSignature::from_compact(&sig_bytes, rec_id)
        .map_err(|e| Eip7702Error::InvalidSignature(e.to_string()))?;
    
    let public_key = secp.recover_ecdsa(&msg, &recoverable_sig)
        .map_err(|e| Eip7702Error::InvalidSignature(e.to_string()))?;
    
    // Hash public key to get address
    let pub_key_bytes = public_key.serialize_uncompressed();
    let pub_key_hash = keccak256(&pub_key_bytes[1..]);
    
    let mut address = [0u8; 20];
    address.copy_from_slice(&pub_key_hash[12..]);
    
    Ok(address)
}

/// Verify an authorization was signed by a specific address
pub fn verify_authorization(auth: &Authorization, expected_signer: &[u8; 20]) -> Eip7702Result<bool> {
    let recovered = recover_authorization_signer(auth)?;
    Ok(recovered == *expected_signer)
}

// =============================================================================
// RLP Encoding Helpers
// =============================================================================

pub(crate) fn keccak256(data: &[u8]) -> [u8; 32] {
    let mut hasher = Keccak::v256();
    let mut output = [0u8; 32];
    hasher.update(data);
    hasher.finalize(&mut output);
    output
}

pub(crate) fn rlp_encode_u64(value: u64) -> Vec<u8> {
    if value == 0 {
        return vec![0x80];
    }
    
    let bytes = value.to_be_bytes();
    let start = bytes.iter().position(|&b| b != 0).unwrap_or(8);
    let significant = &bytes[start..];
    
    if significant.len() == 1 && significant[0] < 0x80 {
        significant.to_vec()
    } else {
        let mut encoded = vec![0x80 + significant.len() as u8];
        encoded.extend_from_slice(significant);
        encoded
    }
}

pub(crate) fn rlp_encode_u128(value: u128) -> Vec<u8> {
    if value == 0 {
        return vec![0x80];
    }
    
    let bytes = value.to_be_bytes();
    let start = bytes.iter().position(|&b| b != 0).unwrap_or(16);
    let significant = &bytes[start..];
    
    if significant.len() == 1 && significant[0] < 0x80 {
        significant.to_vec()
    } else {
        let mut encoded = vec![0x80 + significant.len() as u8];
        encoded.extend_from_slice(significant);
        encoded
    }
}

pub(crate) fn rlp_encode_bytes(data: &[u8]) -> Vec<u8> {
    if data.len() == 1 && data[0] < 0x80 {
        data.to_vec()
    } else if data.len() < 56 {
        let mut encoded = vec![0x80 + data.len() as u8];
        encoded.extend_from_slice(data);
        encoded
    } else {
        let len_bytes = encode_length(data.len());
        let mut encoded = vec![0xb7 + len_bytes.len() as u8];
        encoded.extend_from_slice(&len_bytes);
        encoded.extend_from_slice(data);
        encoded
    }
}

fn rlp_encode_bytes_trimmed(data: &[u8]) -> Vec<u8> {
    // Trim leading zeros for integers stored as bytes
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
