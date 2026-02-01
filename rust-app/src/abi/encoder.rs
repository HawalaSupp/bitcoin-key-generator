//! ABI encoder for Solidity/EVM contracts

use super::types::*;

/// ABI encoder
pub struct AbiEncoder;

impl AbiEncoder {
    /// Encode a single value according to its type
    pub fn encode_value(value: &AbiValue, abi_type: &AbiType) -> Result<Vec<u8>, AbiError> {
        match (value, abi_type) {
            // Unsigned integers
            (AbiValue::Uint(u), AbiType::Uint8 | AbiType::Uint16 | AbiType::Uint32 | 
             AbiType::Uint64 | AbiType::Uint128 | AbiType::Uint256) => {
                Ok(u.to_be_bytes().to_vec())
            }
            
            // Signed integers
            (AbiValue::Int(i), AbiType::Int8 | AbiType::Int16 | AbiType::Int32 |
             AbiType::Int64 | AbiType::Int128 | AbiType::Int256) => {
                Ok(i.to_be_bytes().to_vec())
            }
            
            // Address
            (AbiValue::Address(addr), AbiType::Address) => {
                let mut result = [0u8; 32];
                result[12..].copy_from_slice(addr);
                Ok(result.to_vec())
            }
            
            // Bool
            (AbiValue::Bool(b), AbiType::Bool) => {
                let mut result = [0u8; 32];
                result[31] = if *b { 1 } else { 0 };
                Ok(result.to_vec())
            }
            
            // Fixed bytes (bytes1 through bytes32)
            (AbiValue::FixedBytes(bytes), AbiType::Bytes1 | AbiType::Bytes2 | 
             AbiType::Bytes3 | AbiType::Bytes4 | AbiType::Bytes8 | 
             AbiType::Bytes16 | AbiType::Bytes20 | AbiType::Bytes32 | 
             AbiType::FixedBytes(_)) => {
                let mut result = [0u8; 32];
                let len = bytes.len().min(32);
                result[..len].copy_from_slice(&bytes[..len]);
                Ok(result.to_vec())
            }
            
            // Dynamic bytes
            (AbiValue::Bytes(bytes), AbiType::Bytes) => {
                Self::encode_dynamic_bytes(bytes)
            }
            
            // String
            (AbiValue::String(s), AbiType::String) => {
                Self::encode_dynamic_bytes(s.as_bytes())
            }
            
            // Dynamic array
            (AbiValue::Array(values), AbiType::Array(inner_type)) => {
                Self::encode_dynamic_array(values, inner_type)
            }
            
            // Fixed array
            (AbiValue::Array(values), AbiType::FixedArray(inner_type, size)) => {
                if values.len() != *size {
                    return Err(AbiError::TypeMismatch {
                        expected: format!("array of size {}", size),
                        got: format!("array of size {}", values.len()),
                    });
                }
                Self::encode_fixed_array(values, inner_type)
            }
            
            // Tuple
            (AbiValue::Tuple(values), AbiType::Tuple(types)) => {
                if values.len() != types.len() {
                    return Err(AbiError::TypeMismatch {
                        expected: format!("tuple of {} elements", types.len()),
                        got: format!("tuple of {} elements", values.len()),
                    });
                }
                Self::encode_tuple(values, types)
            }
            
            // Type mismatch
            _ => Err(AbiError::TypeMismatch {
                expected: abi_type.canonical_type(),
                got: value.get_type().canonical_type(),
            }),
        }
    }
    
    /// Encode multiple values (for function calls)
    pub fn encode(values: &[AbiValue], types: &[AbiType]) -> Result<Vec<u8>, AbiError> {
        if values.len() != types.len() {
            return Err(AbiError::EncodingError(format!(
                "Value count {} doesn't match type count {}",
                values.len(),
                types.len()
            )));
        }
        
        Self::encode_tuple(values, types)
    }
    
    /// Encode a tuple (also used for function parameters)
    fn encode_tuple(values: &[AbiValue], types: &[AbiType]) -> Result<Vec<u8>, AbiError> {
        // Calculate head size (sum of all head sizes)
        let head_size: usize = types.iter().map(|t| t.head_size()).sum();
        
        // Head and tail buffers
        let mut head = Vec::with_capacity(head_size);
        let mut tail = Vec::new();
        
        for (value, abi_type) in values.iter().zip(types.iter()) {
            if abi_type.is_dynamic() {
                // For dynamic types, head contains offset to tail
                let offset = head_size + tail.len();
                let offset_u256 = U256::from(offset as u64);
                head.extend_from_slice(&offset_u256.to_be_bytes());
                
                // Tail contains the actual encoded data
                let encoded = Self::encode_value(value, abi_type)?;
                tail.extend_from_slice(&encoded);
            } else {
                // For static types, head contains the value directly
                let encoded = Self::encode_value(value, abi_type)?;
                head.extend_from_slice(&encoded);
            }
        }
        
        // Concatenate head and tail
        head.extend_from_slice(&tail);
        Ok(head)
    }
    
    /// Encode dynamic bytes
    fn encode_dynamic_bytes(bytes: &[u8]) -> Result<Vec<u8>, AbiError> {
        let len = bytes.len();
        
        // Calculate padded length (multiple of 32)
        let padded_len = ((len + 31) / 32) * 32;
        
        // Result: length (32 bytes) + padded data
        let mut result = Vec::with_capacity(32 + padded_len);
        
        // Encode length
        let len_u256 = U256::from(len as u64);
        result.extend_from_slice(&len_u256.to_be_bytes());
        
        // Encode data with padding
        result.extend_from_slice(bytes);
        result.resize(32 + padded_len, 0);
        
        Ok(result)
    }
    
    /// Encode a dynamic array
    fn encode_dynamic_array(values: &[AbiValue], inner_type: &AbiType) -> Result<Vec<u8>, AbiError> {
        let len = values.len();
        
        // Result: length (32 bytes) + encoded elements
        let mut result = Vec::new();
        
        // Encode length
        let len_u256 = U256::from(len as u64);
        result.extend_from_slice(&len_u256.to_be_bytes());
        
        // Encode elements as a tuple
        let types: Vec<AbiType> = (0..len).map(|_| inner_type.clone()).collect();
        let encoded = Self::encode_tuple(values, &types)?;
        result.extend_from_slice(&encoded);
        
        Ok(result)
    }
    
    /// Encode a fixed-size array
    fn encode_fixed_array(values: &[AbiValue], inner_type: &AbiType) -> Result<Vec<u8>, AbiError> {
        // For fixed arrays, no length prefix - just encode as tuple
        let types: Vec<AbiType> = (0..values.len()).map(|_| inner_type.clone()).collect();
        Self::encode_tuple(values, &types)
    }
    
    /// Encode a function call (selector + parameters)
    pub fn encode_function_call(
        function: &AbiFunction,
        values: &[AbiValue],
    ) -> Result<Vec<u8>, AbiError> {
        use super::selector::AbiSelector;
        
        // Get function selector
        let selector = AbiSelector::function_selector(function);
        
        // Get parameter types
        let types: Vec<AbiType> = function.inputs.iter()
            .map(|p| p.param_type.clone())
            .collect();
        
        // Encode parameters
        let params = Self::encode(values, &types)?;
        
        // Concatenate selector + params
        let mut result = Vec::with_capacity(4 + params.len());
        result.extend_from_slice(&selector);
        result.extend_from_slice(&params);
        
        Ok(result)
    }
    
    /// Encode a function call by signature string
    /// e.g., "transfer(address,uint256)" with values
    pub fn encode_function_call_by_signature(
        signature: &str,
        values: &[AbiValue],
    ) -> Result<Vec<u8>, AbiError> {
        use super::selector::AbiSelector;
        
        // Parse signature to get selector
        let selector = AbiSelector::selector_from_signature(signature);
        
        // Parse types from signature
        let types = Self::parse_types_from_signature(signature)?;
        
        if types.len() != values.len() {
            return Err(AbiError::EncodingError(format!(
                "Expected {} values for signature '{}', got {}",
                types.len(),
                signature,
                values.len()
            )));
        }
        
        // Encode parameters
        let params = Self::encode(values, &types)?;
        
        // Concatenate selector + params
        let mut result = Vec::with_capacity(4 + params.len());
        result.extend_from_slice(&selector);
        result.extend_from_slice(&params);
        
        Ok(result)
    }
    
    /// Parse types from a function signature
    fn parse_types_from_signature(signature: &str) -> Result<Vec<AbiType>, AbiError> {
        // Extract parameter part: "name(params)"
        let start = signature.find('(')
            .ok_or_else(|| AbiError::InvalidAbi("Missing '(' in signature".to_string()))?;
        let end = signature.rfind(')')
            .ok_or_else(|| AbiError::InvalidAbi("Missing ')' in signature".to_string()))?;
        
        let params_str = &signature[start + 1..end];
        
        if params_str.is_empty() {
            return Ok(vec![]);
        }
        
        // Parse comma-separated types, handling nested parentheses
        let mut types = Vec::new();
        let mut current = String::new();
        let mut depth = 0;
        
        for c in params_str.chars() {
            match c {
                '(' => {
                    depth += 1;
                    current.push(c);
                }
                ')' => {
                    depth -= 1;
                    current.push(c);
                }
                ',' if depth == 0 => {
                    types.push(AbiType::from_str(current.trim())?);
                    current.clear();
                }
                _ => current.push(c),
            }
        }
        
        if !current.trim().is_empty() {
            types.push(AbiType::from_str(current.trim())?);
        }
        
        Ok(types)
    }
}

/// Helper to create common function call data
pub struct FunctionCall;

impl FunctionCall {
    /// Create ERC-20 transfer calldata
    pub fn erc20_transfer(to: [u8; 20], amount: U256) -> Result<Vec<u8>, AbiError> {
        AbiEncoder::encode_function_call_by_signature(
            "transfer(address,uint256)",
            &[
                AbiValue::Address(to),
                AbiValue::Uint(amount),
            ],
        )
    }
    
    /// Create ERC-20 approve calldata
    pub fn erc20_approve(spender: [u8; 20], amount: U256) -> Result<Vec<u8>, AbiError> {
        AbiEncoder::encode_function_call_by_signature(
            "approve(address,uint256)",
            &[
                AbiValue::Address(spender),
                AbiValue::Uint(amount),
            ],
        )
    }
    
    /// Create ERC-20 transferFrom calldata
    pub fn erc20_transfer_from(from: [u8; 20], to: [u8; 20], amount: U256) -> Result<Vec<u8>, AbiError> {
        AbiEncoder::encode_function_call_by_signature(
            "transferFrom(address,address,uint256)",
            &[
                AbiValue::Address(from),
                AbiValue::Address(to),
                AbiValue::Uint(amount),
            ],
        )
    }
    
    /// Create ERC-721 safeTransferFrom calldata
    pub fn erc721_safe_transfer_from(from: [u8; 20], to: [u8; 20], token_id: U256) -> Result<Vec<u8>, AbiError> {
        AbiEncoder::encode_function_call_by_signature(
            "safeTransferFrom(address,address,uint256)",
            &[
                AbiValue::Address(from),
                AbiValue::Address(to),
                AbiValue::Uint(token_id),
            ],
        )
    }
    
    /// Create ERC-1155 safeTransferFrom calldata
    pub fn erc1155_safe_transfer_from(
        from: [u8; 20],
        to: [u8; 20],
        token_id: U256,
        amount: U256,
        data: Vec<u8>,
    ) -> Result<Vec<u8>, AbiError> {
        AbiEncoder::encode_function_call_by_signature(
            "safeTransferFrom(address,address,uint256,uint256,bytes)",
            &[
                AbiValue::Address(from),
                AbiValue::Address(to),
                AbiValue::Uint(token_id),
                AbiValue::Uint(amount),
                AbiValue::Bytes(data),
            ],
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_encode_uint256() {
        let value = AbiValue::Uint(U256::from(256));
        let encoded = AbiEncoder::encode_value(&value, &AbiType::Uint256).unwrap();
        
        assert_eq!(encoded.len(), 32);
        assert_eq!(encoded[30], 1);
        assert_eq!(encoded[31], 0);
    }
    
    #[test]
    fn test_encode_address() {
        let mut addr = [0u8; 20];
        addr[0] = 0xde;
        addr[19] = 0xad;
        
        let value = AbiValue::Address(addr);
        let encoded = AbiEncoder::encode_value(&value, &AbiType::Address).unwrap();
        
        assert_eq!(encoded.len(), 32);
        assert_eq!(encoded[12], 0xde);
        assert_eq!(encoded[31], 0xad);
    }
    
    #[test]
    fn test_encode_bool() {
        let value_true = AbiValue::Bool(true);
        let value_false = AbiValue::Bool(false);
        
        let encoded_true = AbiEncoder::encode_value(&value_true, &AbiType::Bool).unwrap();
        let encoded_false = AbiEncoder::encode_value(&value_false, &AbiType::Bool).unwrap();
        
        assert_eq!(encoded_true[31], 1);
        assert_eq!(encoded_false[31], 0);
    }
    
    #[test]
    fn test_encode_fixed_bytes() {
        let value = AbiValue::FixedBytes(vec![0xde, 0xad, 0xbe, 0xef]);
        let encoded = AbiEncoder::encode_value(&value, &AbiType::Bytes4).unwrap();
        
        assert_eq!(encoded.len(), 32);
        assert_eq!(&encoded[..4], &[0xde, 0xad, 0xbe, 0xef]);
    }
    
    #[test]
    fn test_encode_dynamic_bytes() {
        let value = AbiValue::Bytes(vec![0xde, 0xad, 0xbe, 0xef]);
        let encoded = AbiEncoder::encode_value(&value, &AbiType::Bytes).unwrap();
        
        // 32 bytes for length + 32 bytes for padded data
        assert_eq!(encoded.len(), 64);
        
        // Length = 4
        assert_eq!(encoded[31], 4);
        
        // Data at offset 32
        assert_eq!(&encoded[32..36], &[0xde, 0xad, 0xbe, 0xef]);
    }
    
    #[test]
    fn test_encode_string() {
        let value = AbiValue::String("Hello".to_string());
        let encoded = AbiEncoder::encode_value(&value, &AbiType::String).unwrap();
        
        // 32 bytes for length + 32 bytes for padded data
        assert_eq!(encoded.len(), 64);
        
        // Length = 5
        assert_eq!(encoded[31], 5);
        
        // Data
        assert_eq!(&encoded[32..37], b"Hello");
    }
    
    #[test]
    fn test_encode_tuple() {
        let values = vec![
            AbiValue::Uint(U256::from(100)),
            AbiValue::Bool(true),
        ];
        let types = vec![AbiType::Uint256, AbiType::Bool];
        
        let encoded = AbiEncoder::encode(&values, &types).unwrap();
        
        // 32 + 32 bytes
        assert_eq!(encoded.len(), 64);
        assert_eq!(encoded[31], 100);
        assert_eq!(encoded[63], 1);
    }
    
    #[test]
    fn test_encode_dynamic_array() {
        let values = vec![
            AbiValue::Uint(U256::from(1)),
            AbiValue::Uint(U256::from(2)),
            AbiValue::Uint(U256::from(3)),
        ];
        let value = AbiValue::Array(values);
        
        let encoded = AbiEncoder::encode_value(&value, &AbiType::Array(Box::new(AbiType::Uint256))).unwrap();
        
        // 32 (length) + 3 * 32 (elements)
        assert_eq!(encoded.len(), 128);
        
        // Length = 3
        assert_eq!(encoded[31], 3);
        
        // Elements
        assert_eq!(encoded[63], 1);
        assert_eq!(encoded[95], 2);
        assert_eq!(encoded[127], 3);
    }
    
    #[test]
    fn test_encode_erc20_transfer() {
        let mut to = [0u8; 20];
        to[0] = 0xab;
        to[19] = 0xcd;
        
        let amount = U256::from(1000);
        
        let calldata = FunctionCall::erc20_transfer(to, amount).unwrap();
        
        // 4 bytes selector + 32 bytes address + 32 bytes amount
        assert_eq!(calldata.len(), 68);
        
        // Selector for transfer(address,uint256) = 0xa9059cbb
        assert_eq!(&calldata[..4], &[0xa9, 0x05, 0x9c, 0xbb]);
    }
    
    #[test]
    fn test_encode_function_call_by_signature() {
        let calldata = AbiEncoder::encode_function_call_by_signature(
            "balanceOf(address)",
            &[AbiValue::Address([0; 20])],
        ).unwrap();
        
        // 4 bytes selector + 32 bytes address
        assert_eq!(calldata.len(), 36);
        
        // Selector for balanceOf(address) = 0x70a08231
        assert_eq!(&calldata[..4], &[0x70, 0xa0, 0x82, 0x31]);
    }
    
    #[test]
    fn test_encode_mixed_dynamic_static() {
        // Encode (uint256, string, uint256)
        let values = vec![
            AbiValue::Uint(U256::from(42)),
            AbiValue::String("test".to_string()),
            AbiValue::Uint(U256::from(100)),
        ];
        let types = vec![AbiType::Uint256, AbiType::String, AbiType::Uint256];
        
        let encoded = AbiEncoder::encode(&values, &types).unwrap();
        
        // Head: 32 (uint256) + 32 (offset) + 32 (uint256) = 96
        // Tail: 32 (length) + 32 (padded string) = 64
        // Total: 160
        assert_eq!(encoded.len(), 160);
        
        // First uint256 = 42
        assert_eq!(encoded[31], 42);
        
        // Offset to string = 96
        assert_eq!(encoded[63], 96);
        
        // Third uint256 = 100
        assert_eq!(encoded[95], 100);
        
        // String length = 4
        assert_eq!(encoded[127], 4);
        
        // String data = "test"
        assert_eq!(&encoded[128..132], b"test");
    }
}
