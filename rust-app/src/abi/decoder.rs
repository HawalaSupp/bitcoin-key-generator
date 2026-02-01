//! ABI decoder for Solidity/EVM contracts

use super::types::*;

/// ABI decoder
pub struct AbiDecoder;

impl AbiDecoder {
    /// Decode a single value from bytes according to its type
    pub fn decode_value(data: &[u8], abi_type: &AbiType, offset: usize) -> Result<(AbiValue, usize), AbiError> {
        if data.len() < offset + 32 {
            return Err(AbiError::DecodingError("Insufficient data".to_string()));
        }
        
        match abi_type {
            // Unsigned integers
            AbiType::Uint8 | AbiType::Uint16 | AbiType::Uint32 | 
            AbiType::Uint64 | AbiType::Uint128 | AbiType::Uint256 => {
                let value = U256::from_be_bytes(&data[offset..offset + 32]);
                Ok((AbiValue::Uint(value), offset + 32))
            }
            
            // Signed integers
            AbiType::Int8 | AbiType::Int16 | AbiType::Int32 |
            AbiType::Int64 | AbiType::Int128 | AbiType::Int256 => {
                let value = I256::from_be_bytes(&data[offset..offset + 32]);
                Ok((AbiValue::Int(value), offset + 32))
            }
            
            // Address
            AbiType::Address => {
                let mut addr = [0u8; 20];
                addr.copy_from_slice(&data[offset + 12..offset + 32]);
                Ok((AbiValue::Address(addr), offset + 32))
            }
            
            // Bool
            AbiType::Bool => {
                let value = data[offset + 31] != 0;
                Ok((AbiValue::Bool(value), offset + 32))
            }
            
            // Fixed bytes
            AbiType::Bytes1 => {
                Ok((AbiValue::FixedBytes(data[offset..offset + 1].to_vec()), offset + 32))
            }
            AbiType::Bytes2 => {
                Ok((AbiValue::FixedBytes(data[offset..offset + 2].to_vec()), offset + 32))
            }
            AbiType::Bytes3 => {
                Ok((AbiValue::FixedBytes(data[offset..offset + 3].to_vec()), offset + 32))
            }
            AbiType::Bytes4 => {
                Ok((AbiValue::FixedBytes(data[offset..offset + 4].to_vec()), offset + 32))
            }
            AbiType::Bytes8 => {
                Ok((AbiValue::FixedBytes(data[offset..offset + 8].to_vec()), offset + 32))
            }
            AbiType::Bytes16 => {
                Ok((AbiValue::FixedBytes(data[offset..offset + 16].to_vec()), offset + 32))
            }
            AbiType::Bytes20 => {
                Ok((AbiValue::FixedBytes(data[offset..offset + 20].to_vec()), offset + 32))
            }
            AbiType::Bytes32 => {
                Ok((AbiValue::FixedBytes(data[offset..offset + 32].to_vec()), offset + 32))
            }
            AbiType::FixedBytes(size) => {
                Ok((AbiValue::FixedBytes(data[offset..offset + size].to_vec()), offset + 32))
            }
            
            // Dynamic bytes
            AbiType::Bytes => {
                Self::decode_dynamic_bytes(data, offset)
            }
            
            // String
            AbiType::String => {
                let (value, new_offset) = Self::decode_dynamic_bytes(data, offset)?;
                if let AbiValue::Bytes(bytes) = value {
                    let s = String::from_utf8(bytes)
                        .map_err(|_| AbiError::DecodingError("Invalid UTF-8 in string".to_string()))?;
                    Ok((AbiValue::String(s), new_offset))
                } else {
                    Err(AbiError::DecodingError("Expected bytes".to_string()))
                }
            }
            
            // Dynamic array
            AbiType::Array(inner_type) => {
                Self::decode_dynamic_array(data, offset, inner_type)
            }
            
            // Fixed array
            AbiType::FixedArray(inner_type, size) => {
                Self::decode_fixed_array(data, offset, inner_type, *size)
            }
            
            // Tuple
            AbiType::Tuple(types) => {
                Self::decode_tuple(data, offset, types)
            }
        }
    }
    
    /// Decode multiple values (for function return values)
    pub fn decode(data: &[u8], types: &[AbiType]) -> Result<Vec<AbiValue>, AbiError> {
        let (values, _) = Self::decode_tuple(data, 0, types)?;
        if let AbiValue::Tuple(values) = values {
            Ok(values)
        } else {
            Err(AbiError::DecodingError("Expected tuple".to_string()))
        }
    }
    
    /// Decode a tuple
    fn decode_tuple(data: &[u8], base_offset: usize, types: &[AbiType]) -> Result<(AbiValue, usize), AbiError> {
        let mut values = Vec::with_capacity(types.len());
        let mut head_offset = base_offset;
        
        for abi_type in types {
            if abi_type.is_dynamic() {
                // For dynamic types, read offset from head
                if data.len() < head_offset + 32 {
                    return Err(AbiError::DecodingError("Insufficient data for offset".to_string()));
                }
                
                let offset_value = U256::from_be_bytes(&data[head_offset..head_offset + 32]);
                let data_offset = base_offset + offset_value.as_u64() as usize;
                
                let (value, _) = Self::decode_value(data, abi_type, data_offset)?;
                values.push(value);
                head_offset += 32;
            } else {
                // For static types, read directly from head
                let (value, new_offset) = Self::decode_value(data, abi_type, head_offset)?;
                values.push(value);
                head_offset = new_offset;
            }
        }
        
        Ok((AbiValue::Tuple(values), head_offset))
    }
    
    /// Decode dynamic bytes
    fn decode_dynamic_bytes(data: &[u8], offset: usize) -> Result<(AbiValue, usize), AbiError> {
        if data.len() < offset + 32 {
            return Err(AbiError::DecodingError("Insufficient data for length".to_string()));
        }
        
        // Read length
        let length_u256 = U256::from_be_bytes(&data[offset..offset + 32]);
        let length = length_u256.as_u64() as usize;
        
        // Read data
        if data.len() < offset + 32 + length {
            return Err(AbiError::DecodingError("Insufficient data for bytes".to_string()));
        }
        
        let bytes = data[offset + 32..offset + 32 + length].to_vec();
        
        // Calculate padded length
        let padded_length = ((length + 31) / 32) * 32;
        
        Ok((AbiValue::Bytes(bytes), offset + 32 + padded_length))
    }
    
    /// Decode a dynamic array
    fn decode_dynamic_array(data: &[u8], offset: usize, inner_type: &AbiType) -> Result<(AbiValue, usize), AbiError> {
        if data.len() < offset + 32 {
            return Err(AbiError::DecodingError("Insufficient data for array length".to_string()));
        }
        
        // Read length
        let length_u256 = U256::from_be_bytes(&data[offset..offset + 32]);
        let length = length_u256.as_u64() as usize;
        
        // Decode elements as a tuple
        let element_types: Vec<AbiType> = (0..length).map(|_| inner_type.clone()).collect();
        let (tuple, end_offset) = Self::decode_tuple(data, offset + 32, &element_types)?;
        
        if let AbiValue::Tuple(values) = tuple {
            Ok((AbiValue::Array(values), end_offset))
        } else {
            Err(AbiError::DecodingError("Expected tuple from array elements".to_string()))
        }
    }
    
    /// Decode a fixed-size array
    fn decode_fixed_array(data: &[u8], offset: usize, inner_type: &AbiType, size: usize) -> Result<(AbiValue, usize), AbiError> {
        let element_types: Vec<AbiType> = (0..size).map(|_| inner_type.clone()).collect();
        let (tuple, end_offset) = Self::decode_tuple(data, offset, &element_types)?;
        
        if let AbiValue::Tuple(values) = tuple {
            Ok((AbiValue::Array(values), end_offset))
        } else {
            Err(AbiError::DecodingError("Expected tuple from array elements".to_string()))
        }
    }
    
    /// Decode function return value using ABI
    pub fn decode_function_result(
        function: &AbiFunction,
        data: &[u8],
    ) -> Result<Vec<AbiValue>, AbiError> {
        let types: Vec<AbiType> = function.outputs.iter()
            .map(|p| p.param_type.clone())
            .collect();
        
        Self::decode(data, &types)
    }
    
    /// Decode an event log
    pub fn decode_event(
        event: &AbiEvent,
        topics: &[Vec<u8>],
        data: &[u8],
    ) -> Result<Vec<(String, AbiValue)>, AbiError> {
        let mut result = Vec::new();
        
        // First topic is event signature (skip for anonymous events)
        let topic_offset = if event.anonymous { 0 } else { 1 };
        let mut topic_idx = topic_offset;
        
        // Collect indexed and non-indexed parameters
        let mut data_types = Vec::new();
        
        for param in &event.inputs {
            if param.indexed {
                // Indexed parameters come from topics
                if topic_idx >= topics.len() {
                    return Err(AbiError::DecodingError("Missing indexed parameter topic".to_string()));
                }
                
                let topic = &topics[topic_idx];
                topic_idx += 1;
                
                // For dynamic types, indexed value is hash, not actual value
                if param.param.param_type.is_dynamic() {
                    // Return the hash as bytes32
                    result.push((param.param.name.clone(), AbiValue::FixedBytes(topic.clone())));
                } else {
                    // Decode static type from topic
                    let (value, _) = Self::decode_value(topic, &param.param.param_type, 0)?;
                    result.push((param.param.name.clone(), value));
                }
            } else {
                // Non-indexed parameters come from data
                data_types.push((param.param.name.clone(), param.param.param_type.clone()));
            }
        }
        
        // Decode non-indexed parameters from data
        if !data_types.is_empty() {
            let types: Vec<AbiType> = data_types.iter().map(|(_, t)| t.clone()).collect();
            let values = Self::decode(data, &types)?;
            
            for ((name, _), value) in data_types.into_iter().zip(values.into_iter()) {
                result.push((name, value));
            }
        }
        
        Ok(result)
    }
}

/// Common function result decoders
pub struct FunctionResult;

impl FunctionResult {
    /// Decode ERC-20 balanceOf result
    pub fn erc20_balance(data: &[u8]) -> Result<U256, AbiError> {
        let values = AbiDecoder::decode(data, &[AbiType::Uint256])?;
        if let Some(AbiValue::Uint(balance)) = values.first() {
            Ok(*balance)
        } else {
            Err(AbiError::DecodingError("Expected uint256".to_string()))
        }
    }
    
    /// Decode ERC-20 name/symbol result
    pub fn erc20_string(data: &[u8]) -> Result<String, AbiError> {
        let values = AbiDecoder::decode(data, &[AbiType::String])?;
        if let Some(AbiValue::String(s)) = values.into_iter().next() {
            Ok(s)
        } else {
            Err(AbiError::DecodingError("Expected string".to_string()))
        }
    }
    
    /// Decode ERC-20 decimals result
    pub fn erc20_decimals(data: &[u8]) -> Result<u8, AbiError> {
        let values = AbiDecoder::decode(data, &[AbiType::Uint8])?;
        if let Some(AbiValue::Uint(decimals)) = values.first() {
            Ok(decimals.as_u64() as u8)
        } else {
            Err(AbiError::DecodingError("Expected uint8".to_string()))
        }
    }
    
    /// Decode ERC-20 totalSupply result
    pub fn erc20_total_supply(data: &[u8]) -> Result<U256, AbiError> {
        Self::erc20_balance(data)
    }
    
    /// Decode ERC-721 ownerOf result
    pub fn erc721_owner(data: &[u8]) -> Result<[u8; 20], AbiError> {
        let values = AbiDecoder::decode(data, &[AbiType::Address])?;
        if let Some(AbiValue::Address(addr)) = values.first() {
            Ok(*addr)
        } else {
            Err(AbiError::DecodingError("Expected address".to_string()))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_decode_uint256() {
        let mut data = [0u8; 32];
        data[31] = 42;
        
        let (value, offset) = AbiDecoder::decode_value(&data, &AbiType::Uint256, 0).unwrap();
        
        assert_eq!(offset, 32);
        if let AbiValue::Uint(u) = value {
            assert_eq!(u.as_u64(), 42);
        } else {
            panic!("Expected Uint");
        }
    }
    
    #[test]
    fn test_decode_address() {
        let mut data = [0u8; 32];
        data[12] = 0xde;
        data[31] = 0xad;
        
        let (value, offset) = AbiDecoder::decode_value(&data, &AbiType::Address, 0).unwrap();
        
        assert_eq!(offset, 32);
        if let AbiValue::Address(addr) = value {
            assert_eq!(addr[0], 0xde);
            assert_eq!(addr[19], 0xad);
        } else {
            panic!("Expected Address");
        }
    }
    
    #[test]
    fn test_decode_bool() {
        let mut data_true = [0u8; 32];
        data_true[31] = 1;
        let data_false = [0u8; 32];
        
        let (value_true, _) = AbiDecoder::decode_value(&data_true, &AbiType::Bool, 0).unwrap();
        let (value_false, _) = AbiDecoder::decode_value(&data_false, &AbiType::Bool, 0).unwrap();
        
        assert_eq!(value_true, AbiValue::Bool(true));
        assert_eq!(value_false, AbiValue::Bool(false));
    }
    
    #[test]
    fn test_decode_dynamic_bytes() {
        // Length = 4, data = [0xde, 0xad, 0xbe, 0xef]
        let mut data = vec![0u8; 64];
        data[31] = 4; // length
        data[32] = 0xde;
        data[33] = 0xad;
        data[34] = 0xbe;
        data[35] = 0xef;
        
        let (value, _) = AbiDecoder::decode_value(&data, &AbiType::Bytes, 0).unwrap();
        
        if let AbiValue::Bytes(bytes) = value {
            assert_eq!(bytes, vec![0xde, 0xad, 0xbe, 0xef]);
        } else {
            panic!("Expected Bytes");
        }
    }
    
    #[test]
    fn test_decode_string() {
        // Length = 5, data = "Hello"
        let mut data = vec![0u8; 64];
        data[31] = 5; // length
        data[32..37].copy_from_slice(b"Hello");
        
        let (value, _) = AbiDecoder::decode_value(&data, &AbiType::String, 0).unwrap();
        
        if let AbiValue::String(s) = value {
            assert_eq!(s, "Hello");
        } else {
            panic!("Expected String");
        }
    }
    
    #[test]
    fn test_decode_tuple() {
        // (uint256, bool) = (42, true)
        let mut data = vec![0u8; 64];
        data[31] = 42;
        data[63] = 1;
        
        let values = AbiDecoder::decode(&data, &[AbiType::Uint256, AbiType::Bool]).unwrap();
        
        assert_eq!(values.len(), 2);
        if let AbiValue::Uint(u) = &values[0] {
            assert_eq!(u.as_u64(), 42);
        } else {
            panic!("Expected Uint");
        }
        assert_eq!(values[1], AbiValue::Bool(true));
    }
    
    #[test]
    fn test_decode_dynamic_array() {
        // [1, 2, 3]
        let mut data = vec![0u8; 128];
        data[31] = 3; // length
        data[63] = 1; // elements
        data[95] = 2;
        data[127] = 3;
        
        let (value, _) = AbiDecoder::decode_value(&data, &AbiType::Array(Box::new(AbiType::Uint256)), 0).unwrap();
        
        if let AbiValue::Array(values) = value {
            assert_eq!(values.len(), 3);
            if let AbiValue::Uint(u) = &values[0] {
                assert_eq!(u.as_u64(), 1);
            }
            if let AbiValue::Uint(u) = &values[1] {
                assert_eq!(u.as_u64(), 2);
            }
            if let AbiValue::Uint(u) = &values[2] {
                assert_eq!(u.as_u64(), 3);
            }
        } else {
            panic!("Expected Array");
        }
    }
    
    #[test]
    fn test_decode_mixed_types() {
        // (uint256, string, uint256) = (42, "test", 100)
        // Head: 32 (uint256=42) + 32 (offset=96) + 32 (uint256=100) = 96
        // Tail: 32 (length=4) + 32 (padded "test") = 64
        let mut data = vec![0u8; 160];
        data[31] = 42;      // uint256
        data[63] = 96;      // offset to string
        data[95] = 100;     // uint256
        data[127] = 4;      // string length
        data[128..132].copy_from_slice(b"test");
        
        let values = AbiDecoder::decode(&data, &[AbiType::Uint256, AbiType::String, AbiType::Uint256]).unwrap();
        
        assert_eq!(values.len(), 3);
        if let AbiValue::Uint(u) = &values[0] {
            assert_eq!(u.as_u64(), 42);
        }
        if let AbiValue::String(s) = &values[1] {
            assert_eq!(s, "test");
        }
        if let AbiValue::Uint(u) = &values[2] {
            assert_eq!(u.as_u64(), 100);
        }
    }
    
    #[test]
    fn test_erc20_balance_decode() {
        let mut data = vec![0u8; 32];
        // 1000000 in hex = 0xF4240
        data[29] = 0x0f;
        data[30] = 0x42;
        data[31] = 0x40;
        
        let balance = FunctionResult::erc20_balance(&data).unwrap();
        assert_eq!(balance.as_u64(), 1000000);
    }
    
    #[test]
    fn test_encode_decode_roundtrip() {
        use super::super::encoder::AbiEncoder;
        
        // Create original values
        let original = vec![
            AbiValue::Uint(U256::from(12345)),
            AbiValue::Address([0xab; 20]),
            AbiValue::Bool(true),
        ];
        let types = vec![AbiType::Uint256, AbiType::Address, AbiType::Bool];
        
        // Encode
        let encoded = AbiEncoder::encode(&original, &types).unwrap();
        
        // Decode
        let decoded = AbiDecoder::decode(&encoded, &types).unwrap();
        
        // Verify
        assert_eq!(original, decoded);
    }
}
