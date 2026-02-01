//! Smart Account Management for ERC-4337
//!
//! Supports Safe and SimpleAccount implementations.

use crate::error::{HawalaError, HawalaResult, ErrorCode};
use crate::crypto::curves::secp256k1::Secp256k1Curve;
use crate::crypto::curves::traits::RecoverableSignature;
use serde::{Deserialize, Serialize};
use sha3::{Digest, Keccak256};

/// Account types supported
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AccountType {
    /// Safe (Gnosis Safe) - most battle-tested
    Safe,
    /// Simple Account (ERC-4337 reference implementation)
    SimpleAccount,
    /// Kernel (ZeroDev)
    Kernel,
    /// Alchemy Light Account
    LightAccount,
}

/// Smart account manager
pub struct SmartAccountManager;

impl SmartAccountManager {
    /// Compute counterfactual address for a Safe account
    pub fn compute_safe_address(
        owners: &[String],
        threshold: u32,
        salt: &[u8; 32],
        factory: &str,
        singleton: &str,
    ) -> HawalaResult<String> {
        // Validate inputs
        if owners.is_empty() {
            return Err(HawalaError::new(
                ErrorCode::InvalidInput,
                "At least one owner required",
            ));
        }
        if threshold == 0 || threshold > owners.len() as u32 {
            return Err(HawalaError::new(
                ErrorCode::InvalidInput,
                format!("Invalid threshold: {} for {} owners", threshold, owners.len()),
            ));
        }

        // Build initializer calldata
        let initializer = Self::build_safe_initializer(owners, threshold)?;
        
        // Compute CREATE2 address
        // address = keccak256(0xff ++ factory ++ salt ++ keccak256(initCode))[12:]
        let proxy_code = Self::get_safe_proxy_code(singleton)?;
        
        let mut hasher = Keccak256::new();
        hasher.update(&proxy_code);
        hasher.update(&initializer);
        let init_code_hash = hasher.finalize();
        
        let factory_bytes = hex::decode(factory.strip_prefix("0x").unwrap_or(factory))
            .map_err(|e| HawalaError::new(ErrorCode::InvalidInput, format!("Invalid factory: {}", e)))?;
        
        let mut data = Vec::new();
        data.push(0xff);
        data.extend(&factory_bytes);
        data.extend(salt);
        data.extend(&init_code_hash);
        
        let mut hasher = Keccak256::new();
        hasher.update(&data);
        let address_hash = hasher.finalize();
        
        Ok(format!("0x{}", hex::encode(&address_hash[12..])))
    }
    
    /// Compute SimpleAccount address
    pub fn compute_simple_account_address(
        owner: &str,
        salt: &[u8; 32],
        factory: &str,
    ) -> HawalaResult<String> {
        // SimpleAccount uses owner address in init code
        let owner_bytes = hex::decode(owner.strip_prefix("0x").unwrap_or(owner))
            .map_err(|e| HawalaError::new(ErrorCode::InvalidInput, format!("Invalid owner: {}", e)))?;
        
        let factory_bytes = hex::decode(factory.strip_prefix("0x").unwrap_or(factory))
            .map_err(|e| HawalaError::new(ErrorCode::InvalidInput, format!("Invalid factory: {}", e)))?;
        
        // createAccount(address owner, uint256 salt)
        // function selector: 0x5fbfb9cf
        let mut init_data = hex::decode("5fbfb9cf").unwrap();
        init_data.extend(vec![0u8; 12]);
        init_data.extend(&owner_bytes);
        init_data.extend(salt);
        
        let mut hasher = Keccak256::new();
        hasher.update(&init_data);
        let init_hash = hasher.finalize();
        
        let mut data = Vec::new();
        data.push(0xff);
        data.extend(&factory_bytes);
        data.extend(salt);
        data.extend(&init_hash);
        
        let mut hasher = Keccak256::new();
        hasher.update(&data);
        let address_hash = hasher.finalize();
        
        Ok(format!("0x{}", hex::encode(&address_hash[12..])))
    }
    
    /// Build Safe setup initializer
    fn build_safe_initializer(owners: &[String], threshold: u32) -> HawalaResult<Vec<u8>> {
        // setup(address[] owners, uint256 threshold, address to, bytes data, 
        //       address fallbackHandler, address paymentToken, uint256 payment, address paymentReceiver)
        // selector: 0xb63e800d
        
        let mut encoded = hex::decode("b63e800d").unwrap();
        
        // All parameters are offsets/values
        // owners offset (0x100 = 256 bytes from start of params)
        encoded.extend(vec![0u8; 30]);
        encoded.extend(&[0x01, 0x00]); // 256 as two bytes
        
        // threshold
        encoded.extend(vec![0u8; 28]);
        encoded.extend(&(threshold as u32).to_be_bytes());
        
        // to (zero address)
        encoded.extend(vec![0u8; 32]);
        
        // data offset (points to empty bytes)
        let owners_data_end = 0x100 + 32 + (owners.len() * 32);
        encoded.extend(vec![0u8; 28]);
        encoded.extend(&(owners_data_end as u32).to_be_bytes());
        
        // fallbackHandler (zero)
        encoded.extend(vec![0u8; 32]);
        
        // paymentToken (zero)
        encoded.extend(vec![0u8; 32]);
        
        // payment (zero)
        encoded.extend(vec![0u8; 32]);
        
        // paymentReceiver (zero)
        encoded.extend(vec![0u8; 32]);
        
        // owners array
        // length
        encoded.extend(vec![0u8; 28]);
        encoded.extend(&(owners.len() as u32).to_be_bytes());
        
        // owner addresses
        for owner in owners {
            let owner_bytes = hex::decode(owner.strip_prefix("0x").unwrap_or(owner))
                .map_err(|e| HawalaError::new(ErrorCode::InvalidInput, format!("Invalid owner: {}", e)))?;
            encoded.extend(vec![0u8; 12]);
            encoded.extend(&owner_bytes);
        }
        
        // empty data bytes (length = 0)
        encoded.extend(vec![0u8; 32]);
        
        Ok(encoded)
    }
    
    /// Get Safe proxy creation code
    fn get_safe_proxy_code(singleton: &str) -> HawalaResult<Vec<u8>> {
        // Safe proxy bytecode (simplified - actual is more complex)
        let singleton_bytes = hex::decode(singleton.strip_prefix("0x").unwrap_or(singleton))
            .map_err(|e| HawalaError::new(ErrorCode::InvalidInput, format!("Invalid singleton: {}", e)))?;
        
        // Proxy code that delegates to singleton
        let mut code = Vec::new();
        // PUSH20 singleton
        code.push(0x73);
        code.extend(&singleton_bytes);
        // ... (actual bytecode is ~100 bytes)
        code.extend(&[0x5a, 0xf4, 0x3d, 0x82, 0x80, 0x3e, 0x90, 0x3d, 0x91, 0x60, 0x2b, 0x57, 0xfd, 0x5b, 0xf3]);
        
        Ok(code)
    }
    
    /// Generate signature for Safe transaction
    pub fn sign_safe_transaction(
        safe_tx_hash: &[u8; 32],
        private_key: &[u8; 32],
    ) -> HawalaResult<String> {
        // Sign with secp256k1
        let signature = Secp256k1Curve::sign_recoverable(private_key, safe_tx_hash)
            .map_err(|e| HawalaError::new(ErrorCode::SigningFailed, format!("Signing failed: {}", e)))?;
        
        // Safe expects r || s || v (65 bytes)
        // v should be 27 or 28 (not 0 or 1)
        let mut sig_bytes = signature.0.to_vec();
        if sig_bytes.len() == 65 && sig_bytes[64] < 27 {
            sig_bytes[64] += 27;
        }
        
        Ok(format!("0x{}", hex::encode(sig_bytes)))
    }
    
    /// Get factory + init code for account deployment in UserOperation
    pub fn get_init_code(
        account_type: AccountType,
        owner: &str,
        salt: &[u8; 32],
        factory: &str,
    ) -> HawalaResult<(String, String)> {
        let factory_hex = factory.strip_prefix("0x").unwrap_or(factory).to_string();
        
        let factory_data = match account_type {
            AccountType::SimpleAccount => {
                // createAccount(address owner, uint256 salt)
                let owner_bytes = hex::decode(owner.strip_prefix("0x").unwrap_or(owner))
                    .map_err(|e| HawalaError::new(ErrorCode::InvalidInput, format!("Invalid owner: {}", e)))?;
                
                let mut data = hex::decode("5fbfb9cf").unwrap();
                data.extend(vec![0u8; 12]);
                data.extend(&owner_bytes);
                data.extend(salt);
                
                format!("0x{}", hex::encode(data))
            }
            AccountType::Safe => {
                // createProxyWithNonce(address _singleton, bytes memory initializer, uint256 saltNonce)
                let initializer = Self::build_safe_initializer(&[owner.to_string()], 1)?;
                
                let mut data = hex::decode("1688f0b9").unwrap();
                // singleton offset
                data.extend(vec![0u8; 31]);
                data.push(0x60);
                // initializer offset  
                data.extend(vec![0u8; 31]);
                data.push(0x80);
                // salt
                data.extend(salt);
                // singleton address
                let singleton = "0x41675C099F32341bf84BFc5382aF534df5C7461a"; // Safe v1.4.1
                let singleton_bytes = hex::decode(singleton.strip_prefix("0x").unwrap())
                    .map_err(|e| HawalaError::new(ErrorCode::InvalidInput, format!("Invalid singleton: {}", e)))?;
                data.extend(vec![0u8; 12]);
                data.extend(&singleton_bytes);
                // initializer
                data.extend(vec![0u8; 28]);
                data.extend(&(initializer.len() as u32).to_be_bytes());
                data.extend(&initializer);
                
                format!("0x{}", hex::encode(data))
            }
            _ => {
                return Err(HawalaError::new(
                    ErrorCode::InvalidInput,
                    format!("Account type {:?} not yet supported", account_type),
                ));
            }
        };
        
        Ok((format!("0x{}", factory_hex), factory_data))
    }
}

/// Account info returned from queries
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountInfo {
    pub address: String,
    pub account_type: AccountType,
    pub is_deployed: bool,
    pub owners: Vec<String>,
    pub threshold: u32,
    pub nonce: u64,
    pub entry_point: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compute_simple_account_address() {
        let owner = "0x1234567890123456789012345678901234567890";
        let salt = [0u8; 32];
        let factory = "0xabcdef0123456789abcdef0123456789abcdef01";
        
        let address = SmartAccountManager::compute_simple_account_address(owner, &salt, factory);
        assert!(address.is_ok());
        assert!(address.unwrap().starts_with("0x"));
    }

    #[test]
    fn test_get_init_code_simple() {
        let owner = "0x1234567890123456789012345678901234567890";
        let salt = [0u8; 32];
        let factory = "0xabcdef0123456789abcdef0123456789abcdef01";
        
        let result = SmartAccountManager::get_init_code(
            AccountType::SimpleAccount,
            owner,
            &salt,
            factory,
        );
        
        assert!(result.is_ok());
        let (factory_addr, factory_data) = result.unwrap();
        assert!(factory_addr.starts_with("0x"));
        assert!(factory_data.starts_with("0x5fbfb9cf")); // createAccount selector
    }
}
