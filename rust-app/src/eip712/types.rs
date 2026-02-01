//! EIP-712 Type Definitions
//!
//! Core data structures for EIP-712 typed data signing.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use zeroize::Zeroize;

/// A field in a struct type definition
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct TypedDataField {
    /// The name of the field
    pub name: String,
    /// The type of the field (e.g., "address", "uint256", "bytes32")
    #[serde(rename = "type")]
    pub type_name: String,
}

/// The EIP-712 domain separator data
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Eip712Domain {
    /// The human-readable name of the signing domain
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    
    /// The current major version of the signing domain
    #[serde(skip_serializing_if = "Option::is_none")]
    pub version: Option<String>,
    
    /// The EIP-155 chain ID
    #[serde(skip_serializing_if = "Option::is_none")]
    pub chain_id: Option<serde_json::Value>,
    
    /// The address of the contract that will verify the signature
    #[serde(skip_serializing_if = "Option::is_none")]
    pub verifying_contract: Option<String>,
    
    /// An optional disambiguating salt
    #[serde(skip_serializing_if = "Option::is_none")]
    pub salt: Option<String>,
}

impl Eip712Domain {
    /// Get the chain ID as a u64
    pub fn chain_id_u64(&self) -> Option<u64> {
        self.chain_id.as_ref().and_then(|v| {
            if let Some(n) = v.as_u64() {
                Some(n)
            } else if let Some(s) = v.as_str() {
                // Handle hex string like "0x1"
                if s.starts_with("0x") || s.starts_with("0X") {
                    u64::from_str_radix(&s[2..], 16).ok()
                } else {
                    s.parse().ok()
                }
            } else {
                None
            }
        })
    }
    
    /// Get the chain ID as a big-endian 32-byte array
    pub fn chain_id_bytes(&self) -> Option<[u8; 32]> {
        self.chain_id_u64().map(|id| {
            let mut bytes = [0u8; 32];
            bytes[24..].copy_from_slice(&id.to_be_bytes());
            bytes
        })
    }
}

/// Complete EIP-712 typed data structure
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TypedData {
    /// Type definitions (struct name -> fields)
    pub types: HashMap<String, Vec<TypedDataField>>,
    
    /// The name of the primary type being signed
    pub primary_type: String,
    
    /// The EIP-712 domain
    pub domain: Eip712Domain,
    
    /// The actual message data to sign
    pub message: serde_json::Value,
}

impl TypedData {
    /// Parse typed data from a JSON string
    pub fn from_json(json: &str) -> Result<Self, Eip712Error> {
        serde_json::from_str(json).map_err(|e| Eip712Error::InvalidJson(e.to_string()))
    }
    
    /// Serialize to JSON string
    pub fn to_json(&self) -> Result<String, Eip712Error> {
        serde_json::to_string(self).map_err(|e| Eip712Error::InvalidJson(e.to_string()))
    }
    
    /// Get the domain type fields based on which fields are present
    pub fn get_domain_type(&self) -> Vec<TypedDataField> {
        let mut fields = Vec::new();
        
        if self.domain.name.is_some() {
            fields.push(TypedDataField {
                name: "name".to_string(),
                type_name: "string".to_string(),
            });
        }
        if self.domain.version.is_some() {
            fields.push(TypedDataField {
                name: "version".to_string(),
                type_name: "string".to_string(),
            });
        }
        if self.domain.chain_id.is_some() {
            fields.push(TypedDataField {
                name: "chainId".to_string(),
                type_name: "uint256".to_string(),
            });
        }
        if self.domain.verifying_contract.is_some() {
            fields.push(TypedDataField {
                name: "verifyingContract".to_string(),
                type_name: "address".to_string(),
            });
        }
        if self.domain.salt.is_some() {
            fields.push(TypedDataField {
                name: "salt".to_string(),
                type_name: "bytes32".to_string(),
            });
        }
        
        fields
    }
    
    /// Validate the typed data structure
    pub fn validate(&self) -> Result<(), Eip712Error> {
        // Check that primary type exists in types
        if !self.types.contains_key(&self.primary_type) {
            return Err(Eip712Error::InvalidPrimaryType(self.primary_type.clone()));
        }
        
        // Validate all type references
        for (_type_name, fields) in &self.types {
            for field in fields {
                self.validate_type(&field.type_name)?;
            }
        }
        
        Ok(())
    }
    
    /// Check if a type is valid (either a built-in type or defined in types)
    fn validate_type(&self, type_name: &str) -> Result<(), Eip712Error> {
        // Handle arrays
        let base_type = if type_name.ends_with(']') {
            // Extract base type from array syntax
            let bracket_pos = type_name.find('[').ok_or_else(|| {
                Eip712Error::InvalidType(type_name.to_string())
            })?;
            &type_name[..bracket_pos]
        } else {
            type_name
        };
        
        // Check if it's a built-in type
        if is_atomic_type(base_type) || is_dynamic_type(base_type) {
            return Ok(());
        }
        
        // Check if it's a defined struct type
        if self.types.contains_key(base_type) {
            return Ok(());
        }
        
        Err(Eip712Error::InvalidType(type_name.to_string()))
    }
}

/// EIP-712 signature components
#[derive(Debug, Clone, Zeroize)]
#[zeroize(drop)]
pub struct Eip712Signature {
    /// r component (32 bytes)
    pub r: [u8; 32],
    /// s component (32 bytes)
    pub s: [u8; 32],
    /// v component (recovery id, typically 27 or 28)
    pub v: u8,
}

impl Eip712Signature {
    /// Create from raw components
    pub fn new(r: [u8; 32], s: [u8; 32], v: u8) -> Self {
        Self { r, s, v }
    }
    
    /// Create from 65-byte signature (r || s || v)
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, Eip712Error> {
        if bytes.len() != 65 {
            return Err(Eip712Error::InvalidSignature("expected 65 bytes".to_string()));
        }
        
        let mut r = [0u8; 32];
        let mut s = [0u8; 32];
        r.copy_from_slice(&bytes[0..32]);
        s.copy_from_slice(&bytes[32..64]);
        let v = bytes[64];
        
        Ok(Self { r, s, v })
    }
    
    /// Convert to 65-byte representation (r || s || v)
    pub fn to_bytes(&self) -> [u8; 65] {
        let mut bytes = [0u8; 65];
        bytes[0..32].copy_from_slice(&self.r);
        bytes[32..64].copy_from_slice(&self.s);
        bytes[64] = self.v;
        bytes
    }
    
    /// Convert to hex string
    pub fn to_hex(&self) -> String {
        format!("0x{}", hex::encode(self.to_bytes()))
    }
}

/// Errors that can occur during EIP-712 operations
#[derive(Debug, Clone, thiserror::Error)]
pub enum Eip712Error {
    #[error("Invalid JSON: {0}")]
    InvalidJson(String),
    
    #[error("Invalid type: {0}")]
    InvalidType(String),
    
    #[error("Invalid primary type: {0}")]
    InvalidPrimaryType(String),
    
    #[error("Missing field: {0}")]
    MissingField(String),
    
    #[error("Invalid value for type {type_name}: {value}")]
    InvalidValue { type_name: String, value: String },
    
    #[error("Invalid signature: {0}")]
    InvalidSignature(String),
    
    #[error("Signing error: {0}")]
    SigningError(String),
    
    #[error("Invalid address: {0}")]
    InvalidAddress(String),
    
    #[error("Encoding error: {0}")]
    EncodingError(String),
}

/// Check if a type is an atomic (fixed-size) type
pub fn is_atomic_type(type_name: &str) -> bool {
    // address
    if type_name == "address" {
        return true;
    }
    
    // bool
    if type_name == "bool" {
        return true;
    }
    
    // uintN and intN
    if (type_name.starts_with("uint") || type_name.starts_with("int")) 
        && type_name.len() > 3 
    {
        let bits: &str = if type_name.starts_with("uint") {
            &type_name[4..]
        } else {
            &type_name[3..]
        };
        if let Ok(n) = bits.parse::<u32>() {
            return n > 0 && n <= 256 && n % 8 == 0;
        }
    }
    
    // bytesN (fixed-size bytes)
    if type_name.starts_with("bytes") && type_name != "bytes" {
        let size: &str = &type_name[5..];
        if let Ok(n) = size.parse::<u32>() {
            return n > 0 && n <= 32;
        }
    }
    
    false
}

/// Check if a type is a dynamic type
pub fn is_dynamic_type(type_name: &str) -> bool {
    type_name == "bytes" || type_name == "string"
}

#[cfg(test)]
mod type_tests {
    use super::*;
    
    #[test]
    fn test_atomic_types() {
        assert!(is_atomic_type("address"));
        assert!(is_atomic_type("bool"));
        assert!(is_atomic_type("uint256"));
        assert!(is_atomic_type("uint8"));
        assert!(is_atomic_type("int256"));
        assert!(is_atomic_type("bytes32"));
        assert!(is_atomic_type("bytes1"));
        
        assert!(!is_atomic_type("string"));
        assert!(!is_atomic_type("bytes"));
        assert!(!is_atomic_type("uint"));
        assert!(!is_atomic_type("uint257"));
        assert!(!is_atomic_type("bytes33"));
    }
    
    #[test]
    fn test_dynamic_types() {
        assert!(is_dynamic_type("bytes"));
        assert!(is_dynamic_type("string"));
        
        assert!(!is_dynamic_type("bytes32"));
        assert!(!is_dynamic_type("address"));
    }
    
    #[test]
    fn test_signature_conversion() {
        let sig = Eip712Signature::new([1u8; 32], [2u8; 32], 27);
        let bytes = sig.to_bytes();
        let recovered = Eip712Signature::from_bytes(&bytes).unwrap();
        
        assert_eq!(sig.r, recovered.r);
        assert_eq!(sig.s, recovered.s);
        assert_eq!(sig.v, recovered.v);
    }
}
