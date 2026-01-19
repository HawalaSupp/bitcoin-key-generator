//! EIP-712 Type Encoding
//!
//! Implements the encoding rules for EIP-712 typed data.

use super::types::*;
use std::collections::{HashMap, HashSet};
use tiny_keccak::{Hasher, Keccak};

/// Encode a type string for a struct type
/// Format: "TypeName(type1 name1,type2 name2,...)"
pub fn encode_type(
    type_name: &str,
    types: &HashMap<String, Vec<TypedDataField>>,
) -> Result<String, Eip712Error> {
    let fields = types.get(type_name).ok_or_else(|| {
        Eip712Error::InvalidType(type_name.to_string())
    })?;
    
    // Get all dependencies, sorted alphabetically
    let dependencies = find_type_dependencies(type_name, types);
    
    // Build the type string: primary type first, then dependencies alphabetically
    let mut result = format_type_string(type_name, fields);
    
    let mut sorted_deps: Vec<_> = dependencies.into_iter()
        .filter(|dep| dep != type_name)
        .collect();
    sorted_deps.sort();
    
    for dep in sorted_deps {
        if let Some(dep_fields) = types.get(&dep) {
            result.push_str(&format_type_string(&dep, dep_fields));
        }
    }
    
    Ok(result)
}

/// Format a single type string
fn format_type_string(type_name: &str, fields: &[TypedDataField]) -> String {
    let field_strs: Vec<String> = fields
        .iter()
        .map(|f| format!("{} {}", f.type_name, f.name))
        .collect();
    
    format!("{}({})", type_name, field_strs.join(","))
}

/// Find all type dependencies (including nested structs)
pub fn find_type_dependencies(
    type_name: &str,
    types: &HashMap<String, Vec<TypedDataField>>,
) -> HashSet<String> {
    let mut dependencies = HashSet::new();
    let mut to_visit = vec![type_name.to_string()];
    
    while let Some(current) = to_visit.pop() {
        if dependencies.contains(&current) {
            continue;
        }
        
        if let Some(fields) = types.get(&current) {
            dependencies.insert(current.clone());
            
            for field in fields {
                let base_type = get_base_type(&field.type_name);
                if types.contains_key(base_type) && !dependencies.contains(base_type) {
                    to_visit.push(base_type.to_string());
                }
            }
        }
    }
    
    dependencies
}

/// Get the base type from a potentially array type
/// e.g., "Person[]" -> "Person", "uint256[10]" -> "uint256"
pub fn get_base_type(type_name: &str) -> &str {
    if let Some(bracket_pos) = type_name.find('[') {
        &type_name[..bracket_pos]
    } else {
        type_name
    }
}

/// Calculate the type hash for a struct type
/// typeHash = keccak256(encodeType(typeOf(s)))
pub fn type_hash(
    type_name: &str,
    types: &HashMap<String, Vec<TypedDataField>>,
) -> Result<[u8; 32], Eip712Error> {
    let encoded = encode_type(type_name, types)?;
    Ok(keccak256(encoded.as_bytes()))
}

/// Encode a value according to its type
pub fn encode_value(
    type_name: &str,
    value: &serde_json::Value,
    types: &HashMap<String, Vec<TypedDataField>>,
) -> Result<Vec<u8>, Eip712Error> {
    let base_type = get_base_type(type_name);
    
    // Check if it's an array type
    if type_name.contains('[') {
        return encode_array(type_name, value, types);
    }
    
    // Dynamic types
    if base_type == "bytes" {
        return encode_bytes(value);
    }
    if base_type == "string" {
        return encode_string(value);
    }
    
    // Struct types (referenced types)
    if types.contains_key(base_type) {
        return encode_struct(base_type, value, types);
    }
    
    // Atomic types
    encode_atomic(type_name, value)
}

/// Encode a struct value
fn encode_struct(
    type_name: &str,
    value: &serde_json::Value,
    types: &HashMap<String, Vec<TypedDataField>>,
) -> Result<Vec<u8>, Eip712Error> {
    let obj = value.as_object().ok_or_else(|| {
        Eip712Error::InvalidValue {
            type_name: type_name.to_string(),
            value: value.to_string(),
        }
    })?;
    
    let fields = types.get(type_name).ok_or_else(|| {
        Eip712Error::InvalidType(type_name.to_string())
    })?;
    
    let mut encoded = Vec::new();
    
    // First, add the type hash
    encoded.extend_from_slice(&type_hash(type_name, types)?);
    
    // Then encode each field
    for field in fields {
        let field_value = obj.get(&field.name).ok_or_else(|| {
            Eip712Error::MissingField(format!("{}.{}", type_name, field.name))
        })?;
        
        let encoded_field = encode_value(&field.type_name, field_value, types)?;
        
        // For struct references, we encode the hash
        if types.contains_key(get_base_type(&field.type_name)) || field.type_name.contains('[') {
            encoded.extend_from_slice(&keccak256(&encoded_field));
        } else if field.type_name == "bytes" || field.type_name == "string" {
            // Dynamic types are hashed
            encoded.extend_from_slice(&keccak256(&encoded_field));
        } else {
            encoded.extend(encoded_field);
        }
    }
    
    Ok(encoded)
}

/// Encode an array value
fn encode_array(
    type_name: &str,
    value: &serde_json::Value,
    types: &HashMap<String, Vec<TypedDataField>>,
) -> Result<Vec<u8>, Eip712Error> {
    let arr = value.as_array().ok_or_else(|| {
        Eip712Error::InvalidValue {
            type_name: type_name.to_string(),
            value: value.to_string(),
        }
    })?;
    
    // Get the element type
    let bracket_pos = type_name.find('[').ok_or_else(|| {
        Eip712Error::InvalidType(type_name.to_string())
    })?;
    let element_type = &type_name[..bracket_pos];
    
    let mut encoded = Vec::new();
    
    for item in arr {
        let item_encoded = encode_value(element_type, item, types)?;
        
        // For structs and dynamic types, we include the hash
        if types.contains_key(element_type) {
            encoded.extend_from_slice(&keccak256(&item_encoded));
        } else if element_type == "bytes" || element_type == "string" {
            encoded.extend_from_slice(&keccak256(&item_encoded));
        } else {
            encoded.extend(item_encoded);
        }
    }
    
    Ok(encoded)
}

/// Encode an atomic (fixed-size) value
fn encode_atomic(type_name: &str, value: &serde_json::Value) -> Result<Vec<u8>, Eip712Error> {
    let mut result = [0u8; 32];
    
    // address - 20 bytes, left-padded to 32
    if type_name == "address" {
        let addr = value.as_str().ok_or_else(|| {
            Eip712Error::InvalidValue {
                type_name: type_name.to_string(),
                value: value.to_string(),
            }
        })?;
        let addr_bytes = parse_address(addr)?;
        result[12..].copy_from_slice(&addr_bytes);
        return Ok(result.to_vec());
    }
    
    // bool
    if type_name == "bool" {
        let b = value.as_bool().ok_or_else(|| {
            Eip712Error::InvalidValue {
                type_name: type_name.to_string(),
                value: value.to_string(),
            }
        })?;
        result[31] = if b { 1 } else { 0 };
        return Ok(result.to_vec());
    }
    
    // uintN
    if type_name.starts_with("uint") {
        let bytes = parse_uint(value)?;
        result[32 - bytes.len()..].copy_from_slice(&bytes);
        return Ok(result.to_vec());
    }
    
    // intN (handled same as uint for encoding, sign extension handled separately)
    if type_name.starts_with("int") {
        let bytes = parse_int(value)?;
        // Sign extend if negative
        if bytes[0] & 0x80 != 0 {
            result = [0xff; 32];
        }
        result[32 - bytes.len()..].copy_from_slice(&bytes);
        return Ok(result.to_vec());
    }
    
    // bytesN (fixed-size bytes, right-padded)
    if type_name.starts_with("bytes") && type_name != "bytes" {
        let size: usize = type_name[5..].parse().map_err(|_| {
            Eip712Error::InvalidType(type_name.to_string())
        })?;
        
        let hex_str = value.as_str().ok_or_else(|| {
            Eip712Error::InvalidValue {
                type_name: type_name.to_string(),
                value: value.to_string(),
            }
        })?;
        
        let bytes = parse_hex(hex_str)?;
        if bytes.len() > size {
            return Err(Eip712Error::InvalidValue {
                type_name: type_name.to_string(),
                value: format!("bytes too long: {} > {}", bytes.len(), size),
            });
        }
        
        // Right-pad to 32 bytes
        result[..bytes.len()].copy_from_slice(&bytes);
        return Ok(result.to_vec());
    }
    
    Err(Eip712Error::InvalidType(type_name.to_string()))
}

/// Encode dynamic bytes
fn encode_bytes(value: &serde_json::Value) -> Result<Vec<u8>, Eip712Error> {
    let hex_str = value.as_str().ok_or_else(|| {
        Eip712Error::InvalidValue {
            type_name: "bytes".to_string(),
            value: value.to_string(),
        }
    })?;
    
    parse_hex(hex_str)
}

/// Encode a string value
fn encode_string(value: &serde_json::Value) -> Result<Vec<u8>, Eip712Error> {
    let s = value.as_str().ok_or_else(|| {
        Eip712Error::InvalidValue {
            type_name: "string".to_string(),
            value: value.to_string(),
        }
    })?;
    
    Ok(s.as_bytes().to_vec())
}

/// Parse an Ethereum address
fn parse_address(addr: &str) -> Result<[u8; 20], Eip712Error> {
    let addr = addr.strip_prefix("0x").unwrap_or(addr);
    
    if addr.len() != 40 {
        return Err(Eip712Error::InvalidAddress(format!(
            "invalid length: expected 40 hex chars, got {}",
            addr.len()
        )));
    }
    
    let bytes = hex::decode(addr).map_err(|e| {
        Eip712Error::InvalidAddress(format!("invalid hex: {}", e))
    })?;
    
    let mut result = [0u8; 20];
    result.copy_from_slice(&bytes);
    Ok(result)
}

/// Parse a uint value (supports decimal string, hex string, or number)
fn parse_uint(value: &serde_json::Value) -> Result<Vec<u8>, Eip712Error> {
    match value {
        serde_json::Value::Number(n) => {
            if let Some(u) = n.as_u64() {
                return Ok(u.to_be_bytes().to_vec());
            }
            if let Some(i) = n.as_i64() {
                if i >= 0 {
                    return Ok((i as u64).to_be_bytes().to_vec());
                }
            }
            // For very large numbers, try to parse as string
            Ok(parse_big_uint(&n.to_string())?)
        }
        serde_json::Value::String(s) => {
            if s.starts_with("0x") || s.starts_with("0X") {
                parse_hex(s)
            } else {
                parse_big_uint(s)
            }
        }
        _ => Err(Eip712Error::InvalidValue {
            type_name: "uint256".to_string(),
            value: value.to_string(),
        }),
    }
}

/// Parse a signed int value
fn parse_int(value: &serde_json::Value) -> Result<Vec<u8>, Eip712Error> {
    // For simplicity, handle same as uint for now
    // Full implementation would handle negative values properly
    parse_uint(value)
}

/// Parse a big unsigned integer from decimal string
fn parse_big_uint(s: &str) -> Result<Vec<u8>, Eip712Error> {
    // Simple implementation using u128 for now
    // For full EIP-712 support, would need arbitrary precision
    let n: u128 = s.parse().map_err(|_| {
        Eip712Error::InvalidValue {
            type_name: "uint256".to_string(),
            value: s.to_string(),
        }
    })?;
    
    // Convert to big-endian bytes, trimming leading zeros
    let bytes = n.to_be_bytes();
    let start = bytes.iter().position(|&b| b != 0).unwrap_or(15);
    Ok(bytes[start..].to_vec())
}

/// Parse a hex string (with or without 0x prefix)
fn parse_hex(s: &str) -> Result<Vec<u8>, Eip712Error> {
    let s = s.strip_prefix("0x").unwrap_or(s);
    let s = s.strip_prefix("0X").unwrap_or(s);
    
    hex::decode(s).map_err(|e| {
        Eip712Error::EncodingError(format!("invalid hex: {}", e))
    })
}

/// Compute keccak256 hash
pub fn keccak256(data: &[u8]) -> [u8; 32] {
    let mut hasher = Keccak::v256();
    let mut output = [0u8; 32];
    hasher.update(data);
    hasher.finalize(&mut output);
    output
}

#[cfg(test)]
mod encoder_tests {
    use super::*;
    
    #[test]
    fn test_encode_type_simple() {
        let mut types = HashMap::new();
        types.insert("Person".to_string(), vec![
            TypedDataField { name: "name".to_string(), type_name: "string".to_string() },
            TypedDataField { name: "wallet".to_string(), type_name: "address".to_string() },
        ]);
        
        let encoded = encode_type("Person", &types).unwrap();
        assert_eq!(encoded, "Person(string name,address wallet)");
    }
    
    #[test]
    fn test_encode_type_with_dependencies() {
        let mut types = HashMap::new();
        types.insert("Mail".to_string(), vec![
            TypedDataField { name: "from".to_string(), type_name: "Person".to_string() },
            TypedDataField { name: "to".to_string(), type_name: "Person".to_string() },
            TypedDataField { name: "contents".to_string(), type_name: "string".to_string() },
        ]);
        types.insert("Person".to_string(), vec![
            TypedDataField { name: "name".to_string(), type_name: "string".to_string() },
            TypedDataField { name: "wallet".to_string(), type_name: "address".to_string() },
        ]);
        
        let encoded = encode_type("Mail", &types).unwrap();
        assert_eq!(encoded, "Mail(Person from,Person to,string contents)Person(string name,address wallet)");
    }
    
    #[test]
    fn test_parse_address() {
        let addr = parse_address("0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826").unwrap();
        assert_eq!(addr.len(), 20);
        assert_eq!(addr[0], 0xCD);
    }
    
    #[test]
    fn test_keccak256() {
        let hash = keccak256(b"hello");
        assert_eq!(
            hex::encode(hash),
            "1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8"
        );
    }
    
    #[test]
    fn test_get_base_type() {
        assert_eq!(get_base_type("Person[]"), "Person");
        assert_eq!(get_base_type("uint256[10]"), "uint256");
        assert_eq!(get_base_type("address"), "address");
    }
}
