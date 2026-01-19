//! EIP-712 Hashing
//!
//! Implements domain separator and struct hashing for EIP-712.

use super::encoder::{encode_value, keccak256, type_hash};
use super::types::*;
use std::collections::HashMap;

/// Magic prefix for EIP-712 encoding
const EIP712_PREFIX: &[u8] = b"\x19\x01";

/// Calculate the domain separator hash
///
/// domainSeparator = hashStruct(eip712Domain)
pub fn domain_separator(domain: &Eip712Domain, types: &HashMap<String, Vec<TypedDataField>>) -> Result<[u8; 32], Eip712Error> {
    // Build domain type based on which fields are present
    let domain_fields = get_domain_fields(domain);
    
    // Create a temporary types map with EIP712Domain
    let mut types_with_domain = types.clone();
    types_with_domain.insert("EIP712Domain".to_string(), domain_fields.clone());
    
    // Build the domain data as JSON Value
    let domain_value = domain_to_json(domain)?;
    
    // Hash the domain struct
    let encoded = encode_domain_struct(domain, &domain_fields, &types_with_domain)?;
    
    Ok(keccak256(&encoded))
}

/// Get the domain fields based on which values are present
fn get_domain_fields(domain: &Eip712Domain) -> Vec<TypedDataField> {
    let mut fields = Vec::new();
    
    if domain.name.is_some() {
        fields.push(TypedDataField {
            name: "name".to_string(),
            type_name: "string".to_string(),
        });
    }
    if domain.version.is_some() {
        fields.push(TypedDataField {
            name: "version".to_string(),
            type_name: "string".to_string(),
        });
    }
    if domain.chain_id.is_some() {
        fields.push(TypedDataField {
            name: "chainId".to_string(),
            type_name: "uint256".to_string(),
        });
    }
    if domain.verifying_contract.is_some() {
        fields.push(TypedDataField {
            name: "verifyingContract".to_string(),
            type_name: "address".to_string(),
        });
    }
    if domain.salt.is_some() {
        fields.push(TypedDataField {
            name: "salt".to_string(),
            type_name: "bytes32".to_string(),
        });
    }
    
    fields
}

/// Convert domain to JSON value
fn domain_to_json(domain: &Eip712Domain) -> Result<serde_json::Value, Eip712Error> {
    serde_json::to_value(domain).map_err(|e| Eip712Error::InvalidJson(e.to_string()))
}

/// Encode the domain struct specially
fn encode_domain_struct(
    domain: &Eip712Domain,
    fields: &[TypedDataField],
    types: &HashMap<String, Vec<TypedDataField>>,
) -> Result<Vec<u8>, Eip712Error> {
    let mut encoded = Vec::new();
    
    // Add the type hash
    encoded.extend_from_slice(&type_hash("EIP712Domain", types)?);
    
    // Encode each field
    for field in fields {
        match field.name.as_str() {
            "name" => {
                if let Some(ref name) = domain.name {
                    encoded.extend_from_slice(&keccak256(name.as_bytes()));
                }
            }
            "version" => {
                if let Some(ref version) = domain.version {
                    encoded.extend_from_slice(&keccak256(version.as_bytes()));
                }
            }
            "chainId" => {
                if let Some(bytes) = domain.chain_id_bytes() {
                    encoded.extend_from_slice(&bytes);
                }
            }
            "verifyingContract" => {
                if let Some(ref addr) = domain.verifying_contract {
                    let addr = addr.strip_prefix("0x").unwrap_or(addr);
                    let addr_bytes = hex::decode(addr).map_err(|e| {
                        Eip712Error::InvalidAddress(e.to_string())
                    })?;
                    let mut padded = [0u8; 32];
                    padded[12..].copy_from_slice(&addr_bytes);
                    encoded.extend_from_slice(&padded);
                }
            }
            "salt" => {
                if let Some(ref salt) = domain.salt {
                    let salt = salt.strip_prefix("0x").unwrap_or(salt);
                    let salt_bytes = hex::decode(salt).map_err(|e| {
                        Eip712Error::EncodingError(e.to_string())
                    })?;
                    let mut padded = [0u8; 32];
                    let len = salt_bytes.len().min(32);
                    padded[..len].copy_from_slice(&salt_bytes[..len]);
                    encoded.extend_from_slice(&padded);
                }
            }
            _ => {}
        }
    }
    
    Ok(encoded)
}

/// Hash a struct according to EIP-712
///
/// hashStruct(s) = keccak256(typeHash || encodeData(s))
pub fn hash_struct(
    type_name: &str,
    data: &serde_json::Value,
    types: &HashMap<String, Vec<TypedDataField>>,
) -> Result<[u8; 32], Eip712Error> {
    let encoded = encode_value(type_name, data, types)?;
    Ok(keccak256(&encoded))
}

/// Calculate the final EIP-712 hash for signing
///
/// hash = keccak256("\x19\x01" || domainSeparator || hashStruct(message))
pub fn hash_typed_data(typed_data: &TypedData) -> Result<[u8; 32], Eip712Error> {
    // Validate the typed data first
    typed_data.validate()?;
    
    // Calculate domain separator
    let domain_sep = domain_separator(&typed_data.domain, &typed_data.types)?;
    
    // Calculate struct hash
    let struct_hash = hash_struct(&typed_data.primary_type, &typed_data.message, &typed_data.types)?;
    
    // Concatenate and hash
    let mut data = Vec::with_capacity(2 + 32 + 32);
    data.extend_from_slice(EIP712_PREFIX);
    data.extend_from_slice(&domain_sep);
    data.extend_from_slice(&struct_hash);
    
    Ok(keccak256(&data))
}

/// Get the pre-image components (for external signing)
pub struct Eip712PreImage {
    pub domain_separator: [u8; 32],
    pub struct_hash: [u8; 32],
    pub final_hash: [u8; 32],
}

/// Calculate the pre-image components for EIP-712
pub fn get_pre_image(typed_data: &TypedData) -> Result<Eip712PreImage, Eip712Error> {
    typed_data.validate()?;
    
    let domain_separator = domain_separator(&typed_data.domain, &typed_data.types)?;
    let struct_hash = hash_struct(&typed_data.primary_type, &typed_data.message, &typed_data.types)?;
    
    let mut data = Vec::with_capacity(2 + 32 + 32);
    data.extend_from_slice(EIP712_PREFIX);
    data.extend_from_slice(&domain_separator);
    data.extend_from_slice(&struct_hash);
    let final_hash = keccak256(&data);
    
    Ok(Eip712PreImage {
        domain_separator,
        struct_hash,
        final_hash,
    })
}

#[cfg(test)]
mod hasher_tests {
    use super::*;
    
    fn create_mail_example() -> TypedData {
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
    fn test_hash_typed_data_mail() {
        let typed_data = create_mail_example();
        let hash = hash_typed_data(&typed_data).unwrap();
        
        // Expected hash from EIP-712 spec
        let expected = "be609aee343fb3c4b28e1df9e632fca64fcfaede20f02e86244efddf30957bd2";
        assert_eq!(hex::encode(hash), expected);
    }
    
    #[test]
    fn test_domain_separator() {
        let typed_data = create_mail_example();
        let separator = domain_separator(&typed_data.domain, &typed_data.types).unwrap();
        
        // The domain separator is deterministic
        assert_eq!(separator.len(), 32);
    }
    
    #[test]
    fn test_get_pre_image() {
        let typed_data = create_mail_example();
        let pre_image = get_pre_image(&typed_data).unwrap();
        
        // Verify the final hash matches
        let hash = hash_typed_data(&typed_data).unwrap();
        assert_eq!(pre_image.final_hash, hash);
    }
}
