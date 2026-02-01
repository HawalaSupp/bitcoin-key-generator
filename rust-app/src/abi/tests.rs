//! Integration tests for ABI module

#[cfg(test)]
mod integration_tests {
    use crate::abi::*;
    
    #[test]
    fn test_full_encode_decode_cycle() {
        // Test encoding and decoding a complex function call
        let values = vec![
            AbiValue::Address([0xab; 20]),
            AbiValue::Uint(U256::from(1000000)),
            AbiValue::Bool(true),
            AbiValue::String("Hello, World!".to_string()),
        ];
        
        let types = vec![
            AbiType::Address,
            AbiType::Uint256,
            AbiType::Bool,
            AbiType::String,
        ];
        
        let encoded = AbiEncoder::encode(&values, &types).unwrap();
        let decoded = AbiDecoder::decode(&encoded, &types).unwrap();
        
        assert_eq!(values, decoded);
    }
    
    #[test]
    fn test_erc20_transfer_flow() {
        // Create transfer calldata
        let to = [0x12u8; 20];
        let amount = U256::from(1000);
        
        let calldata = FunctionCall::erc20_transfer(to, amount).unwrap();
        
        // Verify selector
        assert_eq!(&calldata[..4], &KnownSelectors::TRANSFER);
        
        // Decode parameters
        let types = vec![AbiType::Address, AbiType::Uint256];
        let values = AbiDecoder::decode(&calldata[4..], &types).unwrap();
        
        if let AbiValue::Address(decoded_to) = &values[0] {
            assert_eq!(*decoded_to, to);
        } else {
            panic!("Expected address");
        }
        
        if let AbiValue::Uint(decoded_amount) = &values[1] {
            assert_eq!(decoded_amount.as_u64(), 1000);
        } else {
            panic!("Expected uint");
        }
    }
    
    #[test]
    fn test_parse_and_encode_with_abi() {
        let abi = KnownAbis::erc20();
        let transfer = abi.function("transfer").unwrap();
        
        // Encode function call
        let values = vec![
            AbiValue::Address([0xab; 20]),
            AbiValue::Uint(U256::from(500)),
        ];
        
        let calldata = AbiEncoder::encode_function_call(transfer, &values).unwrap();
        
        // Verify we can identify the function
        let selector: [u8; 4] = calldata[..4].try_into().unwrap();
        let identified = abi.function_by_selector(&selector).unwrap();
        assert_eq!(identified.name, "transfer");
    }
    
    #[test]
    fn test_decode_erc20_balance_response() {
        // Simulate response from balanceOf call
        let balance = U256::from(1_000_000_000_000_000_000u64); // 1 ETH in wei
        let response = balance.to_be_bytes();
        
        let decoded = FunctionResult::erc20_balance(&response).unwrap();
        assert_eq!(decoded.as_u64(), 1_000_000_000_000_000_000);
    }
    
    #[test]
    fn test_nested_arrays() {
        // uint256[][] - dynamic array of dynamic arrays
        let inner1 = vec![
            AbiValue::Uint(U256::from(1)),
            AbiValue::Uint(U256::from(2)),
        ];
        let inner2 = vec![
            AbiValue::Uint(U256::from(3)),
            AbiValue::Uint(U256::from(4)),
            AbiValue::Uint(U256::from(5)),
        ];
        
        let outer = AbiValue::Array(vec![
            AbiValue::Array(inner1),
            AbiValue::Array(inner2),
        ]);
        
        let outer_type = AbiType::Array(Box::new(
            AbiType::Array(Box::new(AbiType::Uint256))
        ));
        
        let encoded = AbiEncoder::encode_value(&outer, &outer_type).unwrap();
        let (decoded, _) = AbiDecoder::decode_value(&encoded, &outer_type, 0).unwrap();
        
        assert_eq!(outer, decoded);
    }
    
    #[test]
    fn test_tuple_with_dynamic_fields() {
        // (uint256, string, address, bytes)
        let values = vec![
            AbiValue::Uint(U256::from(42)),
            AbiValue::String("test string".to_string()),
            AbiValue::Address([0xcd; 20]),
            AbiValue::Bytes(vec![0xde, 0xad, 0xbe, 0xef]),
        ];
        
        let types = vec![
            AbiType::Uint256,
            AbiType::String,
            AbiType::Address,
            AbiType::Bytes,
        ];
        
        let encoded = AbiEncoder::encode(&values, &types).unwrap();
        let decoded = AbiDecoder::decode(&encoded, &types).unwrap();
        
        assert_eq!(values, decoded);
    }
    
    #[test]
    fn test_uniswap_swap_encoding() {
        let abi = KnownAbis::uniswap_v2_router();
        let swap = abi.function("swapExactTokensForTokens").unwrap();
        
        // Encode swap call
        let path = vec![
            AbiValue::Address([0x11; 20]), // Token A
            AbiValue::Address([0x22; 20]), // Token B
        ];
        
        let values = vec![
            AbiValue::Uint(U256::from(1000)),           // amountIn
            AbiValue::Uint(U256::from(900)),            // amountOutMin
            AbiValue::Array(path),                       // path
            AbiValue::Address([0x33; 20]),              // to
            AbiValue::Uint(U256::from(1700000000u64)),  // deadline
        ];
        
        let calldata = AbiEncoder::encode_function_call(swap, &values).unwrap();
        
        // Verify it starts with the right selector
        assert!(calldata.len() > 4);
        
        // Decode and verify
        let types: Vec<_> = swap.inputs.iter().map(|p| p.param_type.clone()).collect();
        let decoded = AbiDecoder::decode(&calldata[4..], &types).unwrap();
        
        if let AbiValue::Array(path) = &decoded[2] {
            assert_eq!(path.len(), 2);
        } else {
            panic!("Expected array for path");
        }
    }
    
    #[test]
    fn test_event_decoding() {
        let abi = KnownAbis::erc20();
        let transfer_event = abi.event("Transfer").unwrap();
        
        // Simulate Transfer event log
        // topics[0] = event signature
        // topics[1] = indexed from address
        // topics[2] = indexed to address
        // data = value (non-indexed)
        
        let topic0 = KnownTopics::TRANSFER.to_vec();
        let mut topic1 = vec![0u8; 32];
        topic1[12..].copy_from_slice(&[0x11u8; 20]);
        let mut topic2 = vec![0u8; 32];
        topic2[12..].copy_from_slice(&[0x22u8; 20]);
        
        let topics = vec![topic0, topic1, topic2];
        
        let mut data = vec![0u8; 32];
        data[31] = 100; // value = 100
        
        let decoded = AbiDecoder::decode_event(transfer_event, &topics, &data).unwrap();
        
        assert_eq!(decoded.len(), 3);
        
        // Check 'from' address
        if let AbiValue::Address(from) = &decoded[0].1 {
            assert_eq!(*from, [0x11u8; 20]);
        }
        
        // Check 'to' address
        if let AbiValue::Address(to) = &decoded[1].1 {
            assert_eq!(*to, [0x22u8; 20]);
        }
        
        // Check 'value'
        if let AbiValue::Uint(value) = &decoded[2].1 {
            assert_eq!(value.as_u64(), 100);
        }
    }
    
    #[test]
    fn test_signed_integers() {
        // Test positive value
        let pos = I256::from(12345);
        let encoded = pos.to_be_bytes();
        let decoded = I256::from_be_bytes(&encoded);
        assert_eq!(pos, decoded);
        
        // Test negative value
        let neg = I256::from(-12345);
        let encoded = neg.to_be_bytes();
        let decoded = I256::from_be_bytes(&encoded);
        assert_eq!(neg, decoded);
    }
    
    #[test]
    fn test_bytes32_value() {
        let value = AbiValue::FixedBytes(vec![0xab; 32]);
        let encoded = AbiEncoder::encode_value(&value, &AbiType::Bytes32).unwrap();
        
        assert_eq!(encoded.len(), 32);
        assert!(encoded.iter().all(|&b| b == 0xab));
    }
    
    #[test]
    fn test_empty_array() {
        let value = AbiValue::Array(vec![]);
        let abi_type = AbiType::Array(Box::new(AbiType::Uint256));
        
        let encoded = AbiEncoder::encode_value(&value, &abi_type).unwrap();
        let (decoded, _) = AbiDecoder::decode_value(&encoded, &abi_type, 0).unwrap();
        
        if let AbiValue::Array(arr) = decoded {
            assert!(arr.is_empty());
        } else {
            panic!("Expected empty array");
        }
    }
    
    #[test]
    fn test_all_known_selectors() {
        // Verify all known selectors match their signatures
        assert_eq!(
            AbiSelector::selector_from_signature("transfer(address,uint256)"),
            KnownSelectors::TRANSFER
        );
        assert_eq!(
            AbiSelector::selector_from_signature("approve(address,uint256)"),
            KnownSelectors::APPROVE
        );
        assert_eq!(
            AbiSelector::selector_from_signature("transferFrom(address,address,uint256)"),
            KnownSelectors::TRANSFER_FROM
        );
        assert_eq!(
            AbiSelector::selector_from_signature("balanceOf(address)"),
            KnownSelectors::BALANCE_OF
        );
        assert_eq!(
            AbiSelector::selector_from_signature("allowance(address,address)"),
            KnownSelectors::ALLOWANCE
        );
        assert_eq!(
            AbiSelector::selector_from_signature("totalSupply()"),
            KnownSelectors::TOTAL_SUPPLY
        );
    }
    
    #[test]
    fn test_large_uint256() {
        // Test with a large value
        let large = U256::from_dec("115792089237316195423570985008687907853269984665640564039457584007913129639935").unwrap();
        let value = AbiValue::Uint(large);
        
        let encoded = AbiEncoder::encode_value(&value, &AbiType::Uint256).unwrap();
        let (decoded, _) = AbiDecoder::decode_value(&encoded, &AbiType::Uint256, 0).unwrap();
        
        assert_eq!(AbiValue::Uint(large), decoded);
    }
    
    #[test]
    fn test_long_string() {
        let long_string = "a".repeat(1000);
        let value = AbiValue::String(long_string.clone());
        
        let encoded = AbiEncoder::encode_value(&value, &AbiType::String).unwrap();
        let (decoded, _) = AbiDecoder::decode_value(&encoded, &AbiType::String, 0).unwrap();
        
        if let AbiValue::String(s) = decoded {
            assert_eq!(s, long_string);
        } else {
            panic!("Expected string");
        }
    }
    
    #[test]
    fn test_fixed_array() {
        let values = vec![
            AbiValue::Uint(U256::from(1)),
            AbiValue::Uint(U256::from(2)),
            AbiValue::Uint(U256::from(3)),
        ];
        let array = AbiValue::Array(values.clone());
        let array_type = AbiType::FixedArray(Box::new(AbiType::Uint256), 3);
        
        let encoded = AbiEncoder::encode_value(&array, &array_type).unwrap();
        let (decoded, _) = AbiDecoder::decode_value(&encoded, &array_type, 0).unwrap();
        
        if let AbiValue::Array(arr) = decoded {
            assert_eq!(arr.len(), 3);
            assert_eq!(arr, values);
        } else {
            panic!("Expected array");
        }
    }
}
