//! EIP-7702 Transaction Signing
//!
//! High-level signing interface for EIP-7702 transactions.

use secp256k1::{Secp256k1, Message, SecretKey};
use super::types::{Eip7702Transaction, SignedEip7702Transaction, Authorization, Eip7702Error, Eip7702Result};
use super::authorization::{sign_authorization, recover_authorization_signer};
use super::transaction::{transaction_signing_hash, rlp_encode_signed_transaction, transaction_hash};

/// Sign an EIP-7702 transaction with a private key
pub fn sign_eip7702_transaction(
    tx: &Eip7702Transaction,
    private_key: &[u8; 32],
) -> Eip7702Result<SignedEip7702Transaction> {
    if private_key.iter().all(|&b| b == 0) {
        return Err(Eip7702Error::InvalidPrivateKey("Private key is all zeros".to_string()));
    }
    
    let secp = Secp256k1::new();
    
    let secret_key = SecretKey::from_slice(private_key)
        .map_err(|e| Eip7702Error::InvalidPrivateKey(e.to_string()))?;
    
    let signing_hash = transaction_signing_hash(tx);
    
    let message = Message::from_digest_slice(&signing_hash)
        .map_err(|e| Eip7702Error::SignatureError(e.to_string()))?;
    
    let (recovery_id, signature) = secp.sign_ecdsa_recoverable(&message, &secret_key)
        .serialize_compact();
    
    let y_parity = recovery_id.to_i32() as u8;
    
    let mut r = [0u8; 32];
    let mut s = [0u8; 32];
    r.copy_from_slice(&signature[..32]);
    s.copy_from_slice(&signature[32..]);
    
    Ok(SignedEip7702Transaction {
        tx: tx.clone(),
        y_parity,
        r,
        s,
    })
}

/// Create a complete EIP-7702 transaction with signed authorizations
/// 
/// This is a convenience function that:
/// 1. Signs all authorizations in the transaction
/// 2. Signs the transaction itself
pub fn create_complete_eip7702_transaction(
    mut tx: Eip7702Transaction,
    authorization_keys: &[[u8; 32]],
    tx_signer_key: &[u8; 32],
) -> Eip7702Result<SignedEip7702Transaction> {
    if authorization_keys.len() != tx.authorization_list.len() {
        return Err(Eip7702Error::SignatureError(
            format!("Expected {} keys for {} authorizations", 
                    tx.authorization_list.len(), authorization_keys.len())
        ));
    }
    
    // Sign each authorization
    let mut signed_auths = Vec::with_capacity(tx.authorization_list.len());
    for (auth, key) in tx.authorization_list.iter().zip(authorization_keys.iter()) {
        let signed = sign_authorization(auth.chain_id, auth.address, auth.nonce, key)?;
        signed_auths.push(signed);
    }
    tx.authorization_list = signed_auths;
    
    // Sign the transaction
    sign_eip7702_transaction(&tx, tx_signer_key)
}

/// Verify all authorizations in a transaction
pub fn verify_transaction_authorizations(tx: &Eip7702Transaction) -> Eip7702Result<Vec<[u8; 20]>> {
    let mut signers = Vec::with_capacity(tx.authorization_list.len());
    
    for auth in &tx.authorization_list {
        let signer = recover_authorization_signer(auth)?;
        signers.push(signer);
    }
    
    Ok(signers)
}

/// Recover the signer of a signed transaction
pub fn recover_transaction_signer(signed: &SignedEip7702Transaction) -> Eip7702Result<[u8; 20]> {
    use secp256k1::ecdsa::{RecoverableSignature, RecoveryId};
    use super::authorization::keccak256;
    
    let secp = Secp256k1::new();
    
    let signing_hash = transaction_signing_hash(&signed.tx);
    
    let message = Message::from_digest_slice(&signing_hash)
        .map_err(|e| Eip7702Error::SignatureError(e.to_string()))?;
    
    let recovery_id = RecoveryId::from_i32(signed.y_parity as i32)
        .map_err(|e| Eip7702Error::SignatureError(e.to_string()))?;
    
    let mut sig_bytes = [0u8; 64];
    sig_bytes[..32].copy_from_slice(&signed.r);
    sig_bytes[32..].copy_from_slice(&signed.s);
    
    let sig = RecoverableSignature::from_compact(&sig_bytes, recovery_id)
        .map_err(|e| Eip7702Error::SignatureError(e.to_string()))?;
    
    let pubkey = secp.recover_ecdsa(&message, &sig)
        .map_err(|e| Eip7702Error::SignatureError(e.to_string()))?;
    
    // Convert public key to address
    let pubkey_bytes = pubkey.serialize_uncompressed();
    let hash = keccak256(&pubkey_bytes[1..]);
    
    let mut address = [0u8; 20];
    address.copy_from_slice(&hash[12..]);
    
    Ok(address)
}

/// Serialize a signed transaction for broadcast
pub fn serialize_for_broadcast(signed: &SignedEip7702Transaction) -> Vec<u8> {
    rlp_encode_signed_transaction(signed)
}

/// Get the transaction hash for tracking
pub fn get_transaction_hash(signed: &SignedEip7702Transaction) -> [u8; 32] {
    transaction_hash(signed)
}

/// High-level transaction builder
pub struct Eip7702TransactionBuilder {
    tx: Eip7702Transaction,
    authorization_keys: Vec<[u8; 32]>,
}

impl Eip7702TransactionBuilder {
    /// Create a new builder for a chain
    pub fn new(chain_id: u64) -> Self {
        Self {
            tx: Eip7702Transaction::new(chain_id),
            authorization_keys: Vec::new(),
        }
    }
    
    /// Set the nonce
    pub fn nonce(mut self, nonce: u64) -> Self {
        self.tx.nonce = nonce;
        self
    }
    
    /// Set max priority fee per gas
    pub fn max_priority_fee(mut self, fee: u128) -> Self {
        self.tx.max_priority_fee_per_gas = fee;
        self
    }
    
    /// Set max fee per gas
    pub fn max_fee(mut self, fee: u128) -> Self {
        self.tx.max_fee_per_gas = fee;
        self
    }
    
    /// Set gas limit
    pub fn gas_limit(mut self, limit: u64) -> Self {
        self.tx.gas_limit = limit;
        self
    }
    
    /// Set recipient address
    pub fn to(mut self, address: [u8; 20]) -> Self {
        self.tx.to = Some(address);
        self
    }
    
    /// Set value to transfer
    pub fn value(mut self, value: u128) -> Self {
        self.tx.value = value;
        self
    }
    
    /// Set transaction data
    pub fn data(mut self, data: Vec<u8>) -> Self {
        self.tx.data = data;
        self
    }
    
    /// Add an authorization with its signing key
    pub fn add_authorization(mut self, auth: Authorization, private_key: [u8; 32]) -> Self {
        self.tx.authorization_list.push(auth);
        self.authorization_keys.push(private_key);
        self
    }
    
    /// Add a pre-signed authorization
    pub fn add_signed_authorization(mut self, auth: Authorization) -> Self {
        self.tx.authorization_list.push(auth);
        self
    }
    
    /// Build and sign the transaction
    pub fn sign(self, tx_signer_key: &[u8; 32]) -> Eip7702Result<SignedEip7702Transaction> {
        if self.authorization_keys.is_empty() {
            // All authorizations are already signed
            sign_eip7702_transaction(&self.tx, tx_signer_key)
        } else {
            // Sign authorizations and transaction
            create_complete_eip7702_transaction(self.tx, &self.authorization_keys, tx_signer_key)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    fn test_key() -> [u8; 32] {
        let mut key = [0u8; 32];
        key[31] = 1;
        key
    }
    
    #[test]
    fn test_transaction_builder() {
        let mut to = [0u8; 20];
        to[19] = 0xAB;
        
        let builder = Eip7702TransactionBuilder::new(1)
            .nonce(5)
            .max_priority_fee(1_000_000_000)
            .max_fee(50_000_000_000)
            .gas_limit(21000)
            .to(to)
            .value(1_000_000_000_000_000_000); // 1 ETH
        
        assert_eq!(builder.tx.chain_id, 1);
        assert_eq!(builder.tx.nonce, 5);
        assert_eq!(builder.tx.gas_limit, 21000);
    }
    
    #[test]
    fn test_sign_basic_transaction() {
        let tx = Eip7702Transaction::new(1);
        let key = test_key();
        
        let signed = sign_eip7702_transaction(&tx, &key).unwrap();
        
        assert!(signed.y_parity <= 1);
        assert!(signed.r.iter().any(|&b| b != 0));
        assert!(signed.s.iter().any(|&b| b != 0));
    }
    
    #[test]
    fn test_recover_signer() {
        let tx = Eip7702Transaction::new(1);
        let key = test_key();
        
        let signed = sign_eip7702_transaction(&tx, &key).unwrap();
        let recovered = recover_transaction_signer(&signed).unwrap();
        
        // Calculate expected address from key
        let secp = Secp256k1::new();
        let secret = SecretKey::from_slice(&key).unwrap();
        let pubkey = secp256k1::PublicKey::from_secret_key(&secp, &secret);
        let pubkey_bytes = pubkey.serialize_uncompressed();
        let hash = super::super::authorization::keccak256(&pubkey_bytes[1..]);
        let mut expected = [0u8; 20];
        expected.copy_from_slice(&hash[12..]);
        
        assert_eq!(recovered, expected);
    }
    
    #[test]
    fn test_serialization_roundtrip() {
        let tx = Eip7702Transaction::new(1);
        let key = test_key();
        
        let signed = sign_eip7702_transaction(&tx, &key).unwrap();
        let serialized = serialize_for_broadcast(&signed);
        
        // Should start with 0x04 (EIP-7702 type)
        assert_eq!(serialized[0], 0x04);
        assert!(serialized.len() > 1);
    }
    
    #[test]
    fn test_transaction_hash() {
        let tx = Eip7702Transaction::new(1);
        let key = test_key();
        
        let signed = sign_eip7702_transaction(&tx, &key).unwrap();
        let hash = get_transaction_hash(&signed);
        
        // Hash should be non-zero
        assert!(hash.iter().any(|&b| b != 0));
        
        // Same transaction should produce same hash
        let hash2 = get_transaction_hash(&signed);
        assert_eq!(hash, hash2);
    }
    
    #[test]
    fn test_invalid_key_rejected() {
        let tx = Eip7702Transaction::new(1);
        let zero_key = [0u8; 32];
        
        let result = sign_eip7702_transaction(&tx, &zero_key);
        assert!(result.is_err());
    }
}
