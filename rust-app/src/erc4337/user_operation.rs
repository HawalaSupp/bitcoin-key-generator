//! ERC-4337 UserOperation structure and building
//!
//! Implements the UserOperation (v0.7) format for account abstraction.

use crate::error::{HawalaError, HawalaResult, ErrorCode};
use serde::{Deserialize, Serialize};
use sha3::{Digest, Keccak256};

/// UserOperation for ERC-4337 v0.7
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UserOperation {
    /// The account making the operation
    pub sender: String,
    /// Anti-replay parameter
    pub nonce: String,
    /// Factory address + init data (for account creation)
    pub factory: Option<String>,
    /// Factory init data
    pub factory_data: Option<String>,
    /// The encoded calls to execute
    pub call_data: String,
    /// Gas limit for executing callData
    pub call_gas_limit: String,
    /// Gas for account validation
    pub verification_gas_limit: String,
    /// Gas to compensate bundler for overhead
    pub pre_verification_gas: String,
    /// Maximum total fee per gas
    pub max_fee_per_gas: String,
    /// Maximum priority fee per gas
    pub max_priority_fee_per_gas: String,
    /// Paymaster address + verification data
    pub paymaster: Option<String>,
    /// Gas for paymaster verification
    pub paymaster_verification_gas_limit: Option<String>,
    /// Gas for paymaster post-op
    pub paymaster_post_op_gas_limit: Option<String>,
    /// Additional paymaster data
    pub paymaster_data: Option<String>,
    /// Signature over the userOp
    pub signature: String,
}

impl UserOperation {
    /// Create a new UserOperation with default gas values
    pub fn new(sender: &str, nonce: u64, call_data: &str) -> Self {
        Self {
            sender: sender.to_string(),
            nonce: format!("0x{:x}", nonce),
            factory: None,
            factory_data: None,
            call_data: call_data.to_string(),
            call_gas_limit: "0x30d40".to_string(),        // 200,000
            verification_gas_limit: "0x186a0".to_string(), // 100,000
            pre_verification_gas: "0xc350".to_string(),    // 50,000
            max_fee_per_gas: "0x77359400".to_string(),     // 2 gwei
            max_priority_fee_per_gas: "0x3b9aca00".to_string(), // 1 gwei
            paymaster: None,
            paymaster_verification_gas_limit: None,
            paymaster_post_op_gas_limit: None,
            paymaster_data: None,
            signature: "0x".to_string(),
        }
    }
    
    /// Set factory for account deployment
    pub fn with_factory(mut self, factory: &str, factory_data: &str) -> Self {
        self.factory = Some(factory.to_string());
        self.factory_data = Some(factory_data.to_string());
        self
    }
    
    /// Set gas limits
    pub fn with_gas_limits(
        mut self,
        call_gas: u64,
        verification_gas: u64,
        pre_verification_gas: u64,
    ) -> Self {
        self.call_gas_limit = format!("0x{:x}", call_gas);
        self.verification_gas_limit = format!("0x{:x}", verification_gas);
        self.pre_verification_gas = format!("0x{:x}", pre_verification_gas);
        self
    }
    
    /// Set fee parameters
    pub fn with_fees(mut self, max_fee: u64, priority_fee: u64) -> Self {
        self.max_fee_per_gas = format!("0x{:x}", max_fee);
        self.max_priority_fee_per_gas = format!("0x{:x}", priority_fee);
        self
    }
    
    /// Set paymaster
    pub fn with_paymaster(
        mut self,
        paymaster: &str,
        verification_gas: u64,
        post_op_gas: u64,
        data: &str,
    ) -> Self {
        self.paymaster = Some(paymaster.to_string());
        self.paymaster_verification_gas_limit = Some(format!("0x{:x}", verification_gas));
        self.paymaster_post_op_gas_limit = Some(format!("0x{:x}", post_op_gas));
        self.paymaster_data = Some(data.to_string());
        self
    }
    
    /// Pack the UserOperation for hashing (v0.7 format)
    pub fn pack_for_hash(&self) -> HawalaResult<Vec<u8>> {
        let mut packed = Vec::new();
        
        // sender (address)
        packed.extend(Self::pad_address(&self.sender)?);
        
        // nonce (uint256)
        packed.extend(Self::pad_uint256(&self.nonce)?);
        
        // hash(factory || factoryData)
        let init_code_hash = if let (Some(factory), Some(data)) = (&self.factory, &self.factory_data) {
            let mut init_code = hex::decode(factory.strip_prefix("0x").unwrap_or(factory))
                .map_err(|e| HawalaError::new(ErrorCode::InvalidInput, format!("Invalid factory: {}", e)))?;
            init_code.extend(hex::decode(data.strip_prefix("0x").unwrap_or(data))
                .map_err(|e| HawalaError::new(ErrorCode::InvalidInput, format!("Invalid factory data: {}", e)))?);
            Self::keccak256(&init_code)
        } else {
            Self::keccak256(&[])
        };
        packed.extend(init_code_hash);
        
        // hash(callData)
        let call_data_bytes = hex::decode(self.call_data.strip_prefix("0x").unwrap_or(&self.call_data))
            .map_err(|e| HawalaError::new(ErrorCode::InvalidInput, format!("Invalid call data: {}", e)))?;
        packed.extend(Self::keccak256(&call_data_bytes));
        
        // accountGasLimits: bytes32 = callGasLimit || verificationGasLimit
        packed.extend(Self::pack_gas_limits(&self.call_gas_limit, &self.verification_gas_limit)?);
        
        // preVerificationGas
        packed.extend(Self::pad_uint256(&self.pre_verification_gas)?);
        
        // gasFees: bytes32 = maxPriorityFeePerGas || maxFeePerGas
        packed.extend(Self::pack_gas_limits(&self.max_priority_fee_per_gas, &self.max_fee_per_gas)?);
        
        // hash(paymasterAndData)
        let paymaster_hash = if let Some(paymaster) = &self.paymaster {
            let mut pm_data = hex::decode(paymaster.strip_prefix("0x").unwrap_or(paymaster))
                .map_err(|e| HawalaError::new(ErrorCode::InvalidInput, format!("Invalid paymaster: {}", e)))?;
            if let Some(ver_gas) = &self.paymaster_verification_gas_limit {
                pm_data.extend(Self::pad_uint128(ver_gas)?);
            }
            if let Some(post_gas) = &self.paymaster_post_op_gas_limit {
                pm_data.extend(Self::pad_uint128(post_gas)?);
            }
            if let Some(data) = &self.paymaster_data {
                pm_data.extend(hex::decode(data.strip_prefix("0x").unwrap_or(data))
                    .map_err(|e| HawalaError::new(ErrorCode::InvalidInput, format!("Invalid paymaster data: {}", e)))?);
            }
            Self::keccak256(&pm_data)
        } else {
            Self::keccak256(&[])
        };
        packed.extend(paymaster_hash);
        
        Ok(packed)
    }
    
    /// Get the hash of this UserOperation for signing
    pub fn get_hash(&self, entry_point: &str, chain_id: u64) -> HawalaResult<[u8; 32]> {
        let packed = self.pack_for_hash()?;
        let user_op_hash = Self::keccak256(&packed);
        
        // keccak256(userOpHash || entryPoint || chainId)
        let mut final_data = Vec::new();
        final_data.extend(&user_op_hash);
        final_data.extend(Self::pad_address(entry_point)?);
        final_data.extend(Self::pad_uint256(&format!("0x{:x}", chain_id))?);
        
        let hash = Self::keccak256(&final_data);
        let mut result = [0u8; 32];
        result.copy_from_slice(&hash);
        Ok(result)
    }
    
    /// Set the signature
    pub fn with_signature(mut self, signature: &str) -> Self {
        self.signature = signature.to_string();
        self
    }
    
    // Helper functions
    fn keccak256(data: &[u8]) -> Vec<u8> {
        let mut hasher = Keccak256::new();
        hasher.update(data);
        hasher.finalize().to_vec()
    }
    
    fn pad_address(addr: &str) -> HawalaResult<Vec<u8>> {
        let addr_bytes = hex::decode(addr.strip_prefix("0x").unwrap_or(addr))
            .map_err(|e| HawalaError::new(ErrorCode::InvalidInput, format!("Invalid address: {}", e)))?;
        let mut padded = vec![0u8; 12]; // 32 - 20 = 12 bytes padding
        padded.extend(addr_bytes);
        Ok(padded)
    }
    
    fn pad_uint256(hex_val: &str) -> HawalaResult<Vec<u8>> {
        let val_bytes = hex::decode(hex_val.strip_prefix("0x").unwrap_or(hex_val))
            .map_err(|e| HawalaError::new(ErrorCode::InvalidInput, format!("Invalid uint256: {}", e)))?;
        let mut padded = vec![0u8; 32 - val_bytes.len()];
        padded.extend(val_bytes);
        Ok(padded)
    }
    
    fn pad_uint128(hex_val: &str) -> HawalaResult<Vec<u8>> {
        let val_bytes = hex::decode(hex_val.strip_prefix("0x").unwrap_or(hex_val))
            .map_err(|e| HawalaError::new(ErrorCode::InvalidInput, format!("Invalid uint128: {}", e)))?;
        let mut padded = vec![0u8; 16 - val_bytes.len().min(16)];
        padded.extend(&val_bytes[..val_bytes.len().min(16)]);
        Ok(padded)
    }
    
    fn pack_gas_limits(gas1: &str, gas2: &str) -> HawalaResult<Vec<u8>> {
        let g1 = hex::decode(gas1.strip_prefix("0x").unwrap_or(gas1))
            .map_err(|e| HawalaError::new(ErrorCode::InvalidInput, format!("Invalid gas1: {}", e)))?;
        let g2 = hex::decode(gas2.strip_prefix("0x").unwrap_or(gas2))
            .map_err(|e| HawalaError::new(ErrorCode::InvalidInput, format!("Invalid gas2: {}", e)))?;
        
        let mut result = vec![0u8; 16 - g1.len().min(16)];
        result.extend(&g1[..g1.len().min(16)]);
        result.extend(vec![0u8; 16 - g2.len().min(16)]);
        result.extend(&g2[..g2.len().min(16)]);
        Ok(result)
    }
}

/// Signed UserOperation ready for submission
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignedUserOperation {
    pub user_op: UserOperation,
    pub user_op_hash: String,
}

/// UserOperation receipt from bundler
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UserOperationReceipt {
    pub user_op_hash: String,
    pub entry_point: String,
    pub sender: String,
    pub nonce: String,
    pub paymaster: Option<String>,
    pub actual_gas_cost: String,
    pub actual_gas_used: String,
    pub success: bool,
    pub reason: Option<String>,
    pub logs: Vec<Log>,
    pub receipt: TransactionReceipt,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Log {
    pub address: String,
    pub topics: Vec<String>,
    pub data: String,
    pub block_number: String,
    pub transaction_hash: String,
    pub log_index: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TransactionReceipt {
    pub transaction_hash: String,
    pub block_hash: String,
    pub block_number: String,
    pub gas_used: String,
    pub status: String,
}

/// Builder for complex callData
pub struct CallDataBuilder {
    calls: Vec<Call>,
}

#[derive(Debug, Clone)]
pub struct Call {
    pub target: String,
    pub value: u128,
    pub data: Vec<u8>,
}

impl CallDataBuilder {
    pub fn new() -> Self {
        Self { calls: Vec::new() }
    }
    
    /// Add a call
    pub fn add_call(mut self, target: &str, value: u128, data: Vec<u8>) -> Self {
        self.calls.push(Call {
            target: target.to_string(),
            value,
            data,
        });
        self
    }
    
    /// Build callData for Safe account (execTransaction batch)
    pub fn build_safe_batch(&self) -> HawalaResult<String> {
        if self.calls.is_empty() {
            return Err(HawalaError::new(ErrorCode::InvalidInput, "No calls to batch"));
        }
        
        // Encode multiSend(bytes transactions)
        // For each tx: operation (0 = call), to, value, dataLength, data
        let mut multi_send_data = Vec::new();
        
        for call in &self.calls {
            // operation: 0 (call)
            multi_send_data.push(0u8);
            
            // to: address (20 bytes)
            let target_bytes = hex::decode(call.target.strip_prefix("0x").unwrap_or(&call.target))
                .map_err(|e| HawalaError::new(ErrorCode::InvalidInput, format!("Invalid target: {}", e)))?;
            multi_send_data.extend(&target_bytes);
            
            // value: uint256 (32 bytes)
            let value_bytes = call.value.to_be_bytes();
            multi_send_data.extend(vec![0u8; 16]); // pad to 32 bytes
            multi_send_data.extend(&value_bytes);
            
            // dataLength: uint256 (32 bytes)
            let data_len = call.data.len() as u64;
            multi_send_data.extend(vec![0u8; 24]); // pad to 32 bytes
            multi_send_data.extend(&data_len.to_be_bytes());
            
            // data: bytes
            multi_send_data.extend(&call.data);
        }
        
        // multiSend selector: 0x8d80ff0a
        let mut encoded = hex::decode("8d80ff0a").unwrap();
        
        // offset (0x20)
        encoded.extend(vec![0u8; 31]);
        encoded.push(0x20);
        
        // length
        let len = multi_send_data.len() as u64;
        encoded.extend(vec![0u8; 24]);
        encoded.extend(&len.to_be_bytes());
        
        // data
        encoded.extend(&multi_send_data);
        
        // pad to 32 bytes
        let padding = (32 - (multi_send_data.len() % 32)) % 32;
        encoded.extend(vec![0u8; padding]);
        
        Ok(format!("0x{}", hex::encode(encoded)))
    }
    
    /// Build simple execute callData (for single call accounts)
    pub fn build_execute(&self) -> HawalaResult<String> {
        if self.calls.len() != 1 {
            return Err(HawalaError::new(
                ErrorCode::InvalidInput,
                "execute() requires exactly one call, use batch for multiple",
            ));
        }
        
        let call = &self.calls[0];
        
        // execute(address dest, uint256 value, bytes calldata func)
        // selector: 0xb61d27f6
        let mut encoded = hex::decode("b61d27f6").unwrap();
        
        // dest: address (32 bytes padded)
        let target_bytes = hex::decode(call.target.strip_prefix("0x").unwrap_or(&call.target))
            .map_err(|e| HawalaError::new(ErrorCode::InvalidInput, format!("Invalid target: {}", e)))?;
        encoded.extend(vec![0u8; 12]);
        encoded.extend(&target_bytes);
        
        // value: uint256
        let value_bytes = call.value.to_be_bytes();
        encoded.extend(vec![0u8; 16]);
        encoded.extend(&value_bytes);
        
        // offset to func (0x60)
        encoded.extend(vec![0u8; 31]);
        encoded.push(0x60);
        
        // func length
        let len = call.data.len() as u64;
        encoded.extend(vec![0u8; 24]);
        encoded.extend(&len.to_be_bytes());
        
        // func data
        encoded.extend(&call.data);
        
        // pad
        let padding = (32 - (call.data.len() % 32)) % 32;
        encoded.extend(vec![0u8; padding]);
        
        Ok(format!("0x{}", hex::encode(encoded)))
    }
}

impl Default for CallDataBuilder {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_user_operation_new() {
        let user_op = UserOperation::new(
            "0x1234567890123456789012345678901234567890",
            1,
            "0x",
        );
        assert_eq!(user_op.nonce, "0x1");
        assert_eq!(user_op.sender, "0x1234567890123456789012345678901234567890");
    }

    #[test]
    fn test_user_operation_with_paymaster() {
        let user_op = UserOperation::new(
            "0x1234567890123456789012345678901234567890",
            0,
            "0xabcd",
        )
        .with_paymaster(
            "0x0987654321098765432109876543210987654321",
            50000,
            25000,
            "0x1234",
        );
        
        assert!(user_op.paymaster.is_some());
        assert_eq!(user_op.paymaster_verification_gas_limit, Some("0xc350".to_string()));
    }

    #[test]
    fn test_call_data_builder_single() {
        let call_data = CallDataBuilder::new()
            .add_call(
                "0xdead000000000000000000000000000000000000",
                0,
                vec![0xab, 0xcd],
            )
            .build_execute();
        
        assert!(call_data.is_ok());
        assert!(call_data.unwrap().starts_with("0xb61d27f6"));
    }
}
