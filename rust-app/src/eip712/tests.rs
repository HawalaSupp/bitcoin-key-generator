//! EIP-712 Test Suite
//!
//! Comprehensive tests for EIP-712 typed data signing.

use super::*;

/// Test the canonical Mail example from EIP-712 specification
#[test]
fn test_eip712_mail_example() {
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
    
    let typed_data = TypedData::from_json(json).unwrap();
    let hash = hash_typed_data(&typed_data).unwrap();
    
    // Expected hash from EIP-712 specification
    assert_eq!(
        hex::encode(hash),
        "be609aee343fb3c4b28e1df9e632fca64fcfaede20f02e86244efddf30957bd2"
    );
}

/// Test Uniswap-style Permit message
#[test]
fn test_eip712_permit() {
    let json = r#"{
        "types": {
            "EIP712Domain": [
                {"name": "name", "type": "string"},
                {"name": "version", "type": "string"},
                {"name": "chainId", "type": "uint256"},
                {"name": "verifyingContract", "type": "address"}
            ],
            "Permit": [
                {"name": "owner", "type": "address"},
                {"name": "spender", "type": "address"},
                {"name": "value", "type": "uint256"},
                {"name": "nonce", "type": "uint256"},
                {"name": "deadline", "type": "uint256"}
            ]
        },
        "primaryType": "Permit",
        "domain": {
            "name": "Uniswap V2",
            "version": "1",
            "chainId": 1,
            "verifyingContract": "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"
        },
        "message": {
            "owner": "0x1234567890123456789012345678901234567890",
            "spender": "0x0987654321098765432109876543210987654321",
            "value": "1000000000000000000",
            "nonce": 0,
            "deadline": 1893456000
        }
    }"#;
    
    let typed_data = TypedData::from_json(json).unwrap();
    typed_data.validate().unwrap();
    
    let hash = hash_typed_data(&typed_data).unwrap();
    assert_eq!(hash.len(), 32);
}

/// Test with array types
#[test]
fn test_eip712_with_arrays() {
    let json = r#"{
        "types": {
            "EIP712Domain": [
                {"name": "name", "type": "string"},
                {"name": "chainId", "type": "uint256"}
            ],
            "Order": [
                {"name": "items", "type": "uint256[]"},
                {"name": "prices", "type": "uint256[]"}
            ]
        },
        "primaryType": "Order",
        "domain": {
            "name": "Test",
            "chainId": 1
        },
        "message": {
            "items": [1, 2, 3],
            "prices": [100, 200, 300]
        }
    }"#;
    
    let typed_data = TypedData::from_json(json).unwrap();
    typed_data.validate().unwrap();
    
    let hash = hash_typed_data(&typed_data).unwrap();
    assert_eq!(hash.len(), 32);
}

/// Test with nested struct arrays
#[test]
fn test_eip712_struct_arrays() {
    let json = r#"{
        "types": {
            "EIP712Domain": [
                {"name": "name", "type": "string"},
                {"name": "chainId", "type": "uint256"}
            ],
            "Item": [
                {"name": "id", "type": "uint256"},
                {"name": "name", "type": "string"}
            ],
            "Order": [
                {"name": "items", "type": "Item[]"},
                {"name": "buyer", "type": "address"}
            ]
        },
        "primaryType": "Order",
        "domain": {
            "name": "Marketplace",
            "chainId": 1
        },
        "message": {
            "items": [
                {"id": 1, "name": "Widget"},
                {"id": 2, "name": "Gadget"}
            ],
            "buyer": "0x1234567890123456789012345678901234567890"
        }
    }"#;
    
    let typed_data = TypedData::from_json(json).unwrap();
    typed_data.validate().unwrap();
    
    let hash = hash_typed_data(&typed_data).unwrap();
    assert_eq!(hash.len(), 32);
}

/// Test OpenSea-style order
#[test]
fn test_eip712_opensea_order() {
    let json = r#"{
        "types": {
            "EIP712Domain": [
                {"name": "name", "type": "string"},
                {"name": "version", "type": "string"},
                {"name": "chainId", "type": "uint256"},
                {"name": "verifyingContract", "type": "address"}
            ],
            "OrderComponents": [
                {"name": "offerer", "type": "address"},
                {"name": "zone", "type": "address"},
                {"name": "orderType", "type": "uint8"},
                {"name": "startTime", "type": "uint256"},
                {"name": "endTime", "type": "uint256"},
                {"name": "zoneHash", "type": "bytes32"},
                {"name": "salt", "type": "uint256"},
                {"name": "conduitKey", "type": "bytes32"},
                {"name": "counter", "type": "uint256"}
            ]
        },
        "primaryType": "OrderComponents",
        "domain": {
            "name": "Seaport",
            "version": "1.1",
            "chainId": 1,
            "verifyingContract": "0x00000000006c3852cbEf3e08E8dF289169EdE581"
        },
        "message": {
            "offerer": "0x1234567890123456789012345678901234567890",
            "zone": "0x0000000000000000000000000000000000000000",
            "orderType": 0,
            "startTime": 1640000000,
            "endTime": 1893456000,
            "zoneHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
            "salt": "12345",
            "conduitKey": "0x0000000000000000000000000000000000000000000000000000000000000000",
            "counter": 0
        }
    }"#;
    
    let typed_data = TypedData::from_json(json).unwrap();
    typed_data.validate().unwrap();
    
    let hash = hash_typed_data(&typed_data).unwrap();
    assert_eq!(hash.len(), 32);
}

/// Test invalid primary type
#[test]
fn test_eip712_invalid_primary_type() {
    let json = r#"{
        "types": {
            "EIP712Domain": [
                {"name": "name", "type": "string"}
            ],
            "Person": [
                {"name": "name", "type": "string"}
            ]
        },
        "primaryType": "NonExistent",
        "domain": {"name": "Test"},
        "message": {}
    }"#;
    
    let typed_data = TypedData::from_json(json).unwrap();
    let result = typed_data.validate();
    
    assert!(result.is_err());
    assert!(matches!(result.unwrap_err(), Eip712Error::InvalidPrimaryType(_)));
}

/// Test chain ID parsing
#[test]
fn test_chain_id_parsing() {
    // Test numeric chain ID
    let domain1 = Eip712Domain {
        chain_id: Some(serde_json::json!(1)),
        ..Default::default()
    };
    assert_eq!(domain1.chain_id_u64(), Some(1));
    
    // Test string chain ID
    let domain2 = Eip712Domain {
        chain_id: Some(serde_json::json!("137")),
        ..Default::default()
    };
    assert_eq!(domain2.chain_id_u64(), Some(137));
    
    // Test hex string chain ID
    let domain3 = Eip712Domain {
        chain_id: Some(serde_json::json!("0x89")),
        ..Default::default()
    };
    assert_eq!(domain3.chain_id_u64(), Some(137));
}

/// Test pre-image generation
#[test]
fn test_pre_image_generation() {
    let json = r#"{
        "types": {
            "EIP712Domain": [
                {"name": "name", "type": "string"},
                {"name": "chainId", "type": "uint256"}
            ],
            "Message": [
                {"name": "content", "type": "string"}
            ]
        },
        "primaryType": "Message",
        "domain": {
            "name": "Test",
            "chainId": 1
        },
        "message": {
            "content": "Hello World"
        }
    }"#;
    
    let typed_data = TypedData::from_json(json).unwrap();
    let pre_image = get_pre_image(&typed_data).unwrap();
    
    // Verify components
    assert_eq!(pre_image.domain_separator.len(), 32);
    assert_eq!(pre_image.struct_hash.len(), 32);
    assert_eq!(pre_image.final_hash.len(), 32);
    
    // Verify final hash matches direct computation
    let direct_hash = hash_typed_data(&typed_data).unwrap();
    assert_eq!(pre_image.final_hash, direct_hash);
}

/// Test signing roundtrip
#[test]
fn test_signing_roundtrip() {
    let json = r#"{
        "types": {
            "EIP712Domain": [
                {"name": "name", "type": "string"},
                {"name": "chainId", "type": "uint256"}
            ],
            "Message": [
                {"name": "content", "type": "string"}
            ]
        },
        "primaryType": "Message",
        "domain": {
            "name": "Test",
            "chainId": 1
        },
        "message": {
            "content": "Hello World"
        }
    }"#;
    
    let typed_data = TypedData::from_json(json).unwrap();
    
    // Generate a test private key
    let private_key = hex::decode(
        "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    ).unwrap();
    
    // Sign
    let signature = sign_typed_data(&typed_data, &private_key).unwrap();
    
    // Recover address
    let hash = hash_typed_data(&typed_data).unwrap();
    let recovered = recover_address(&hash, &signature).unwrap();
    
    // Verify
    let valid = verify_typed_data(&typed_data, &signature, &recovered).unwrap();
    assert!(valid);
    
    // Verify wrong address fails
    let wrong_address = "0x0000000000000000000000000000000000000000";
    let invalid = verify_typed_data(&typed_data, &signature, wrong_address).unwrap();
    assert!(!invalid);
}
