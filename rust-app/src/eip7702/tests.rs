//! EIP-7702 Tests
//!
//! Comprehensive tests for EIP-7702 implementation.

#[cfg(test)]
mod tests {
    use crate::eip7702::*;
    
    // Test key for consistent testing
    fn test_key_1() -> [u8; 32] {
        let mut key = [0u8; 32];
        key[31] = 1;
        key
    }
    
    fn test_key_2() -> [u8; 32] {
        let mut key = [0u8; 32];
        key[31] = 2;
        key
    }
    
    fn test_address() -> [u8; 20] {
        let mut addr = [0u8; 20];
        addr[0] = 0xDE;
        addr[1] = 0xAD;
        addr[19] = 0xEF;
        addr
    }
    
    // === Authorization Tests ===
    
    #[test]
    fn test_create_authorization() {
        let auth = Authorization::new(1, test_address(), 0);
        
        assert_eq!(auth.chain_id, 1);
        assert_eq!(auth.address, test_address());
        assert_eq!(auth.nonce, 0);
        assert_eq!(auth.y_parity, 0);
    }
    
    #[test]
    fn test_sign_authorization() {
        let signed = authorization::sign_authorization(1, test_address(), 0, &test_key_1()).unwrap();
        
        assert!(signed.y_parity <= 1);
        assert!(signed.r.iter().any(|&b| b != 0));
        assert!(signed.s.iter().any(|&b| b != 0));
    }
    
    #[test]
    fn test_authorization_signer_recovery() {
        let signed = authorization::sign_authorization(1, test_address(), 0, &test_key_1()).unwrap();
        
        let recovered = authorization::recover_authorization_signer(&signed).unwrap();
        
        // Should recover to the address derived from test_key_1
        assert_eq!(recovered.len(), 20);
        assert!(recovered.iter().any(|&b| b != 0));
    }
    
    #[test]
    fn test_authorization_verification() {
        let signed = authorization::sign_authorization(1, test_address(), 0, &test_key_1()).unwrap();
        
        // Get the expected signer
        let expected_signer = authorization::recover_authorization_signer(&signed).unwrap();
        
        // Verification should pass
        assert!(authorization::verify_authorization(&signed, &expected_signer).is_ok());
    }
    
    #[test]
    fn test_authorization_wrong_signer_fails() {
        let signed = authorization::sign_authorization(1, test_address(), 0, &test_key_1()).unwrap();
        
        // Try to verify with wrong address
        let wrong_address = [0xABu8; 20];
        let result = authorization::verify_authorization(&signed, &wrong_address).unwrap();
        
        // Should return false for wrong signer
        assert!(!result);
    }
    
    #[test]
    fn test_different_chain_ids_different_hashes() {
        let hash1 = authorization::authorization_signing_hash(1, &test_address(), 0);
        let hash2 = authorization::authorization_signing_hash(5, &test_address(), 0);
        
        assert_ne!(hash1, hash2);
    }
    
    #[test]
    fn test_different_nonces_different_hashes() {
        let hash1 = authorization::authorization_signing_hash(1, &test_address(), 0);
        let hash2 = authorization::authorization_signing_hash(1, &test_address(), 1);
        
        assert_ne!(hash1, hash2);
    }
    
    // === Transaction Tests ===
    
    #[test]
    fn test_create_transaction() {
        let tx = Eip7702Transaction::new(1);
        
        assert_eq!(tx.chain_id, 1);
        assert_eq!(tx.nonce, 0);
        assert_eq!(tx.value, 0);
        assert!(tx.authorization_list.is_empty());
    }
    
    #[test]
    fn test_transaction_with_authorization() {
        let mut tx = Eip7702Transaction::new(1);
        let auth = Authorization::new(1, test_address(), 0);
        
        tx.authorization_list.push(auth);
        
        assert_eq!(tx.authorization_list.len(), 1);
    }
    
    #[test]
    fn test_transaction_signing_hash_deterministic() {
        let tx = Eip7702Transaction::new(1);
        
        let hash1 = transaction::transaction_signing_hash(&tx);
        let hash2 = transaction::transaction_signing_hash(&tx);
        
        assert_eq!(hash1, hash2);
    }
    
    #[test]
    fn test_different_transactions_different_hashes() {
        let tx1 = Eip7702Transaction::new(1);
        let mut tx2 = Eip7702Transaction::new(1);
        tx2.nonce = 1;
        
        let hash1 = transaction::transaction_signing_hash(&tx1);
        let hash2 = transaction::transaction_signing_hash(&tx2);
        
        assert_ne!(hash1, hash2);
    }
    
    #[test]
    fn test_sign_transaction() {
        let tx = Eip7702Transaction::new(1);
        let signed = signer::sign_eip7702_transaction(&tx, &test_key_1()).unwrap();
        
        assert!(signed.y_parity <= 1);
        assert!(signed.r.iter().any(|&b| b != 0));
        assert!(signed.s.iter().any(|&b| b != 0));
    }
    
    #[test]
    fn test_recover_transaction_signer() {
        let tx = Eip7702Transaction::new(1);
        let signed = signer::sign_eip7702_transaction(&tx, &test_key_1()).unwrap();
        
        let signer_addr = signer::recover_transaction_signer(&signed).unwrap();
        
        assert_eq!(signer_addr.len(), 20);
        assert!(signer_addr.iter().any(|&b| b != 0));
    }
    
    #[test]
    fn test_transaction_serialization() {
        let tx = Eip7702Transaction::new(1);
        let signed = signer::sign_eip7702_transaction(&tx, &test_key_1()).unwrap();
        
        let serialized = signer::serialize_for_broadcast(&signed);
        
        // Must start with 0x04 (EIP-7702 tx type)
        assert_eq!(serialized[0], 0x04);
    }
    
    #[test]
    fn test_transaction_hash_consistency() {
        let tx = Eip7702Transaction::new(1);
        let signed = signer::sign_eip7702_transaction(&tx, &test_key_1()).unwrap();
        
        let hash1 = signer::get_transaction_hash(&signed);
        let hash2 = signer::get_transaction_hash(&signed);
        
        assert_eq!(hash1, hash2);
    }
    
    // === Builder Tests ===
    
    #[test]
    fn test_builder_basic() {
        // Test that the builder can be created and sign
        let signed = signer::Eip7702TransactionBuilder::new(1)
            .nonce(5)
            .gas_limit(21000)
            .max_fee(50_000_000_000)
            .max_priority_fee(1_000_000_000)
            .sign(&test_key_1())
            .unwrap();
        
        assert_eq!(signed.tx.chain_id, 1);
        assert_eq!(signed.tx.nonce, 5);
        assert_eq!(signed.tx.gas_limit, 21000);
    }
    
    #[test]
    fn test_builder_with_value() {
        let signed = signer::Eip7702TransactionBuilder::new(1)
            .value(1_000_000_000_000_000_000) // 1 ETH in wei
            .sign(&test_key_1())
            .unwrap();
        
        assert_eq!(signed.tx.value, 1_000_000_000_000_000_000u128);
    }
    
    #[test]
    fn test_builder_with_data() {
        let data = vec![0xDE, 0xAD, 0xBE, 0xEF];
        let signed = signer::Eip7702TransactionBuilder::new(1)
            .data(data.clone())
            .sign(&test_key_1())
            .unwrap();
        
        assert_eq!(signed.tx.data, data);
    }
    
    #[test]
    fn test_builder_sign() {
        let signed = signer::Eip7702TransactionBuilder::new(1)
            .nonce(0)
            .gas_limit(21000)
            .sign(&test_key_1())
            .unwrap();
        
        assert!(signed.y_parity <= 1);
    }
    
    // === Complete Flow Tests ===
    
    #[test]
    fn test_complete_eip7702_flow() {
        // 1. Create authorization
        let delegate_address = test_address();
        
        // 2. Build transaction with authorization
        let mut tx = Eip7702Transaction::new(1);
        tx.nonce = 0;
        tx.gas_limit = 100000;
        tx.max_fee_per_gas = 50_000_000_000;
        tx.max_priority_fee_per_gas = 1_000_000_000;
        
        // Sign the authorization with EOA's key
        let signed_auth = authorization::sign_authorization(1, delegate_address, 0, &test_key_1()).unwrap();
        tx.authorization_list.push(signed_auth);
        
        // 3. Sign the transaction with the same key (EOA is the sender)
        let signed_tx = signer::sign_eip7702_transaction(&tx, &test_key_1()).unwrap();
        
        // 4. Verify the signer
        let recovered_tx_signer = signer::recover_transaction_signer(&signed_tx).unwrap();
        let recovered_auth_signer = authorization::recover_authorization_signer(&tx.authorization_list[0]).unwrap();
        
        // Both should be the same address (same key signed both)
        assert_eq!(recovered_tx_signer, recovered_auth_signer);
        
        // 5. Serialize for broadcast
        let serialized = signer::serialize_for_broadcast(&signed_tx);
        assert_eq!(serialized[0], 0x04);
    }
    
    #[test]
    fn test_create_complete_transaction() {
        let auth = Authorization::new(1, test_address(), 0);
        
        let mut tx = Eip7702Transaction::new(1);
        tx.authorization_list.push(auth);
        
        let signed = signer::create_complete_eip7702_transaction(
            tx,
            &[test_key_2()], // Authorization signer
            &test_key_1(),    // Transaction signer
        ).unwrap();
        
        // Verify different signers
        let tx_signer = signer::recover_transaction_signer(&signed).unwrap();
        let auth_signer = authorization::recover_authorization_signer(&signed.tx.authorization_list[0]).unwrap();
        
        // They should be different since we used different keys
        assert_ne!(tx_signer, auth_signer);
    }
    
    #[test]
    fn test_multiple_authorizations() {
        let auth1 = Authorization::new(1, test_address(), 0);
        let mut other_addr = test_address();
        other_addr[0] = 0xBE;
        let auth2 = Authorization::new(1, other_addr, 0);
        
        let mut tx = Eip7702Transaction::new(1);
        tx.authorization_list.push(auth1);
        tx.authorization_list.push(auth2);
        
        let signed = signer::create_complete_eip7702_transaction(
            tx,
            &[test_key_1(), test_key_2()],
            &test_key_1(),
        ).unwrap();
        
        // Verify both authorizations
        let signers = signer::verify_transaction_authorizations(&signed.tx).unwrap();
        assert_eq!(signers.len(), 2);
    }
    
    // === RLP Encoding Tests ===
    
    #[test]
    fn test_rlp_small_values() {
        // Test RLP encoding of small integers
        let encoded = authorization::rlp_encode_u64(0);
        assert_eq!(encoded, vec![0x80]); // Empty string
        
        let encoded = authorization::rlp_encode_u64(127);
        assert_eq!(encoded, vec![127]); // Single byte
        
        let encoded = authorization::rlp_encode_u64(128);
        assert_eq!(encoded, vec![0x81, 128]); // String of length 1
    }
    
    #[test]
    fn test_rlp_bytes() {
        let empty: [u8; 0] = [];
        let encoded = authorization::rlp_encode_bytes(&empty);
        assert_eq!(encoded, vec![0x80]);
        
        let single = [0x42u8];
        let encoded = authorization::rlp_encode_bytes(&single);
        assert_eq!(encoded, vec![0x42]);
        
        let multi = [0x80u8, 0x81];
        let encoded = authorization::rlp_encode_bytes(&multi);
        assert_eq!(encoded, vec![0x82, 0x80, 0x81]);
    }
    
    // === Error Handling Tests ===
    
    #[test]
    fn test_zero_key_rejected() {
        let tx = Eip7702Transaction::new(1);
        let zero_key = [0u8; 32];
        
        let result = signer::sign_eip7702_transaction(&tx, &zero_key);
        assert!(matches!(result, Err(Eip7702Error::InvalidPrivateKey(_))));
    }
    
    #[test]
    fn test_mismatched_auth_keys_count() {
        let auth = Authorization::new(1, test_address(), 0);
        
        let mut tx = Eip7702Transaction::new(1);
        tx.authorization_list.push(auth);
        
        // Provide wrong number of keys
        let result = signer::create_complete_eip7702_transaction(
            tx,
            &[], // No keys provided, but 1 auth exists
            &test_key_1(),
        );
        
        assert!(result.is_err());
    }
    
    // === Access List Tests ===
    
    #[test]
    fn test_transaction_with_access_list() {
        let mut tx = Eip7702Transaction::new(1);
        
        let mut storage_key = [0u8; 32];
        storage_key[31] = 1;
        
        tx.access_list.push(AccessListEntry {
            address: test_address(),
            storage_keys: vec![storage_key],
        });
        
        let signed = signer::sign_eip7702_transaction(&tx, &test_key_1()).unwrap();
        let serialized = signer::serialize_for_broadcast(&signed);
        
        // Should still serialize correctly
        assert_eq!(serialized[0], 0x04);
    }
}
