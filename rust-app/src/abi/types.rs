//! ABI type definitions for Solidity/EVM contracts

use std::fmt;
use serde::{Deserialize, Serialize};

/// All possible Solidity types
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AbiType {
    // Unsigned integers
    Uint8,
    Uint16,
    Uint32,
    Uint64,
    Uint128,
    Uint256,
    
    // Signed integers
    Int8,
    Int16,
    Int32,
    Int64,
    Int128,
    Int256,
    
    // Address (20 bytes)
    Address,
    
    // Boolean
    Bool,
    
    // Fixed-size bytes (bytes1 through bytes32)
    Bytes1,
    Bytes2,
    Bytes3,
    Bytes4,
    Bytes8,
    Bytes16,
    Bytes20,
    Bytes32,
    FixedBytes(usize), // bytes1-bytes32
    
    // Dynamic bytes
    Bytes,
    
    // Dynamic string
    String,
    
    // Dynamic array T[]
    Array(Box<AbiType>),
    
    // Fixed-size array T[N]
    FixedArray(Box<AbiType>, usize),
    
    // Tuple (struct)
    Tuple(Vec<AbiType>),
}

impl AbiType {
    /// Check if the type is dynamic (requires offset encoding)
    pub fn is_dynamic(&self) -> bool {
        match self {
            AbiType::Bytes | AbiType::String | AbiType::Array(_) => true,
            AbiType::FixedArray(inner, _) => inner.is_dynamic(),
            AbiType::Tuple(components) => components.iter().any(|t| t.is_dynamic()),
            _ => false,
        }
    }
    
    /// Get the size in bytes for static types (32 for most)
    pub fn head_size(&self) -> usize {
        match self {
            AbiType::Tuple(components) if !self.is_dynamic() => {
                components.iter().map(|t| t.head_size()).sum()
            }
            AbiType::FixedArray(inner, size) if !self.is_dynamic() => {
                inner.head_size() * size
            }
            _ => 32, // All other types use 32 bytes in head
        }
    }
    
    /// Parse type from string representation
    pub fn from_str(s: &str) -> Result<Self, AbiError> {
        let s = s.trim();
        
        // Handle arrays first
        if s.ends_with("[]") {
            let inner = Self::from_str(&s[..s.len() - 2])?;
            return Ok(AbiType::Array(Box::new(inner)));
        }
        
        // Fixed array T[N]
        if let Some(idx) = s.rfind('[') {
            if s.ends_with(']') {
                let inner_str = &s[..idx];
                let size_str = &s[idx + 1..s.len() - 1];
                let size: usize = size_str.parse()
                    .map_err(|_| AbiError::InvalidType(format!("Invalid array size: {}", size_str)))?;
                let inner = Self::from_str(inner_str)?;
                return Ok(AbiType::FixedArray(Box::new(inner), size));
            }
        }
        
        // Handle tuples
        if s.starts_with('(') && s.ends_with(')') {
            let inner = &s[1..s.len() - 1];
            if inner.is_empty() {
                return Ok(AbiType::Tuple(vec![]));
            }
            let components = Self::parse_tuple_components(inner)?;
            return Ok(AbiType::Tuple(components));
        }
        
        // Basic types
        match s {
            "uint8" => Ok(AbiType::Uint8),
            "uint16" => Ok(AbiType::Uint16),
            "uint32" => Ok(AbiType::Uint32),
            "uint64" => Ok(AbiType::Uint64),
            "uint128" => Ok(AbiType::Uint128),
            "uint256" | "uint" => Ok(AbiType::Uint256),
            
            "int8" => Ok(AbiType::Int8),
            "int16" => Ok(AbiType::Int16),
            "int32" => Ok(AbiType::Int32),
            "int64" => Ok(AbiType::Int64),
            "int128" => Ok(AbiType::Int128),
            "int256" | "int" => Ok(AbiType::Int256),
            
            "address" => Ok(AbiType::Address),
            "bool" => Ok(AbiType::Bool),
            
            "bytes1" => Ok(AbiType::Bytes1),
            "bytes2" => Ok(AbiType::Bytes2),
            "bytes3" => Ok(AbiType::Bytes3),
            "bytes4" => Ok(AbiType::Bytes4),
            "bytes8" => Ok(AbiType::Bytes8),
            "bytes16" => Ok(AbiType::Bytes16),
            "bytes20" => Ok(AbiType::Bytes20),
            "bytes32" => Ok(AbiType::Bytes32),
            
            "bytes" => Ok(AbiType::Bytes),
            "string" => Ok(AbiType::String),
            
            s if s.starts_with("bytes") => {
                let size_str = &s[5..];
                let size: usize = size_str.parse()
                    .map_err(|_| AbiError::InvalidType(format!("Invalid bytes size: {}", size_str)))?;
                if size == 0 || size > 32 {
                    return Err(AbiError::InvalidType(format!("bytes size must be 1-32: {}", size)));
                }
                Ok(AbiType::FixedBytes(size))
            }
            
            s if s.starts_with("uint") => {
                let size_str = &s[4..];
                let bits: usize = size_str.parse()
                    .map_err(|_| AbiError::InvalidType(format!("Invalid uint size: {}", size_str)))?;
                match bits {
                    8 => Ok(AbiType::Uint8),
                    16 => Ok(AbiType::Uint16),
                    32 => Ok(AbiType::Uint32),
                    64 => Ok(AbiType::Uint64),
                    128 => Ok(AbiType::Uint128),
                    256 => Ok(AbiType::Uint256),
                    _ => Err(AbiError::InvalidType(format!("Unsupported uint size: {}", bits))),
                }
            }
            
            s if s.starts_with("int") => {
                let size_str = &s[3..];
                let bits: usize = size_str.parse()
                    .map_err(|_| AbiError::InvalidType(format!("Invalid int size: {}", size_str)))?;
                match bits {
                    8 => Ok(AbiType::Int8),
                    16 => Ok(AbiType::Int16),
                    32 => Ok(AbiType::Int32),
                    64 => Ok(AbiType::Int64),
                    128 => Ok(AbiType::Int128),
                    256 => Ok(AbiType::Int256),
                    _ => Err(AbiError::InvalidType(format!("Unsupported int size: {}", bits))),
                }
            }
            
            _ => Err(AbiError::InvalidType(format!("Unknown type: {}", s))),
        }
    }
    
    /// Parse tuple components handling nested parentheses
    fn parse_tuple_components(s: &str) -> Result<Vec<AbiType>, AbiError> {
        let mut components = Vec::new();
        let mut current = String::new();
        let mut depth = 0;
        
        for c in s.chars() {
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
                    if !current.trim().is_empty() {
                        components.push(Self::from_str(current.trim())?);
                    }
                    current.clear();
                }
                _ => current.push(c),
            }
        }
        
        if !current.trim().is_empty() {
            components.push(Self::from_str(current.trim())?);
        }
        
        Ok(components)
    }
    
    /// Get the canonical type string for signature calculation
    pub fn canonical_type(&self) -> String {
        match self {
            AbiType::Uint8 => "uint8".to_string(),
            AbiType::Uint16 => "uint16".to_string(),
            AbiType::Uint32 => "uint32".to_string(),
            AbiType::Uint64 => "uint64".to_string(),
            AbiType::Uint128 => "uint128".to_string(),
            AbiType::Uint256 => "uint256".to_string(),
            
            AbiType::Int8 => "int8".to_string(),
            AbiType::Int16 => "int16".to_string(),
            AbiType::Int32 => "int32".to_string(),
            AbiType::Int64 => "int64".to_string(),
            AbiType::Int128 => "int128".to_string(),
            AbiType::Int256 => "int256".to_string(),
            
            AbiType::Address => "address".to_string(),
            AbiType::Bool => "bool".to_string(),
            
            AbiType::Bytes1 => "bytes1".to_string(),
            AbiType::Bytes2 => "bytes2".to_string(),
            AbiType::Bytes3 => "bytes3".to_string(),
            AbiType::Bytes4 => "bytes4".to_string(),
            AbiType::Bytes8 => "bytes8".to_string(),
            AbiType::Bytes16 => "bytes16".to_string(),
            AbiType::Bytes20 => "bytes20".to_string(),
            AbiType::Bytes32 => "bytes32".to_string(),
            AbiType::FixedBytes(size) => format!("bytes{}", size),
            
            AbiType::Bytes => "bytes".to_string(),
            AbiType::String => "string".to_string(),
            
            AbiType::Array(inner) => format!("{}[]", inner.canonical_type()),
            AbiType::FixedArray(inner, size) => format!("{}[{}]", inner.canonical_type(), size),
            AbiType::Tuple(components) => {
                let inner = components.iter()
                    .map(|t| t.canonical_type())
                    .collect::<Vec<_>>()
                    .join(",");
                format!("({})", inner)
            }
        }
    }
}

impl fmt::Display for AbiType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.canonical_type())
    }
}

/// ABI value - runtime representation of Solidity values
#[derive(Debug, Clone, PartialEq)]
pub enum AbiValue {
    // Unsigned integers (stored as U256 internally)
    Uint(U256),
    
    // Signed integers (stored as I256 internally)  
    Int(I256),
    
    // Address (20 bytes)
    Address([u8; 20]),
    
    // Boolean
    Bool(bool),
    
    // Fixed-size bytes
    FixedBytes(Vec<u8>),
    
    // Dynamic bytes
    Bytes(Vec<u8>),
    
    // Dynamic string
    String(String),
    
    // Array (dynamic or fixed)
    Array(Vec<AbiValue>),
    
    // Tuple (struct)
    Tuple(Vec<AbiValue>),
}

impl AbiValue {
    /// Create a Uint256 value from a u64
    pub fn uint256(value: u64) -> Self {
        AbiValue::Uint(U256::from(value))
    }
    
    /// Create a Uint256 value from a string (decimal or hex)
    pub fn uint256_from_str(s: &str) -> Result<Self, AbiError> {
        let value = if s.starts_with("0x") || s.starts_with("0X") {
            U256::from_hex(&s[2..])
        } else {
            U256::from_dec(s)
        }?;
        Ok(AbiValue::Uint(value))
    }
    
    /// Create an Address value from a hex string
    pub fn address_from_str(s: &str) -> Result<Self, AbiError> {
        let s = s.strip_prefix("0x").unwrap_or(s);
        if s.len() != 40 {
            return Err(AbiError::InvalidValue("Address must be 20 bytes".to_string()));
        }
        let bytes = hex::decode(s)
            .map_err(|_| AbiError::InvalidValue("Invalid hex in address".to_string()))?;
        let mut addr = [0u8; 20];
        addr.copy_from_slice(&bytes);
        Ok(AbiValue::Address(addr))
    }
    
    /// Create bytes value from hex string
    pub fn bytes_from_hex(s: &str) -> Result<Self, AbiError> {
        let s = s.strip_prefix("0x").unwrap_or(s);
        let bytes = hex::decode(s)
            .map_err(|_| AbiError::InvalidValue("Invalid hex".to_string()))?;
        Ok(AbiValue::Bytes(bytes))
    }
    
    /// Get the type of this value
    pub fn get_type(&self) -> AbiType {
        match self {
            AbiValue::Uint(_) => AbiType::Uint256,
            AbiValue::Int(_) => AbiType::Int256,
            AbiValue::Address(_) => AbiType::Address,
            AbiValue::Bool(_) => AbiType::Bool,
            AbiValue::FixedBytes(b) => AbiType::FixedBytes(b.len()),
            AbiValue::Bytes(_) => AbiType::Bytes,
            AbiValue::String(_) => AbiType::String,
            AbiValue::Array(values) => {
                if values.is_empty() {
                    AbiType::Array(Box::new(AbiType::Uint256))
                } else {
                    AbiType::Array(Box::new(values[0].get_type()))
                }
            }
            AbiValue::Tuple(values) => {
                AbiType::Tuple(values.iter().map(|v| v.get_type()).collect())
            }
        }
    }
}

/// 256-bit unsigned integer
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct U256(pub [u64; 4]);

impl U256 {
    pub const ZERO: U256 = U256([0, 0, 0, 0]);
    pub const ONE: U256 = U256([1, 0, 0, 0]);
    pub const MAX: U256 = U256([u64::MAX, u64::MAX, u64::MAX, u64::MAX]);
    
    /// Create from u64
    pub fn from(value: u64) -> Self {
        U256([value, 0, 0, 0])
    }
    
    /// Create from u128
    pub fn from_u128(value: u128) -> Self {
        U256([value as u64, (value >> 64) as u64, 0, 0])
    }
    
    /// Create from bytes (big-endian)
    pub fn from_be_bytes(bytes: &[u8]) -> Self {
        let mut padded = [0u8; 32];
        let start = 32 - bytes.len().min(32);
        padded[start..].copy_from_slice(&bytes[..bytes.len().min(32)]);
        
        let mut result = [0u64; 4];
        for i in 0..4 {
            let offset = (3 - i) * 8;
            result[i] = u64::from_be_bytes(padded[offset..offset + 8].try_into().unwrap());
        }
        U256(result)
    }
    
    /// Convert to bytes (big-endian, 32 bytes)
    pub fn to_be_bytes(&self) -> [u8; 32] {
        let mut bytes = [0u8; 32];
        for i in 0..4 {
            let offset = (3 - i) * 8;
            bytes[offset..offset + 8].copy_from_slice(&self.0[i].to_be_bytes());
        }
        bytes
    }
    
    /// Parse from hex string (without 0x prefix)
    pub fn from_hex(s: &str) -> Result<Self, AbiError> {
        let bytes = hex::decode(s)
            .map_err(|_| AbiError::InvalidValue("Invalid hex".to_string()))?;
        Ok(Self::from_be_bytes(&bytes))
    }
    
    /// Parse from decimal string
    pub fn from_dec(s: &str) -> Result<Self, AbiError> {
        let mut result = U256::ZERO;
        for c in s.chars() {
            if !c.is_ascii_digit() {
                return Err(AbiError::InvalidValue(format!("Invalid decimal digit: {}", c)));
            }
            result = result.checked_mul_u64(10)
                .ok_or_else(|| AbiError::Overflow)?;
            result = result.checked_add(U256::from(c.to_digit(10).unwrap() as u64))
                .ok_or_else(|| AbiError::Overflow)?;
        }
        Ok(result)
    }
    
    /// Checked addition
    pub fn checked_add(&self, other: U256) -> Option<U256> {
        let mut result = [0u64; 4];
        let mut carry = 0u64;
        
        for i in 0..4 {
            let (sum1, c1) = self.0[i].overflowing_add(other.0[i]);
            let (sum2, c2) = sum1.overflowing_add(carry);
            result[i] = sum2;
            carry = (c1 as u64) + (c2 as u64);
        }
        
        if carry != 0 {
            None
        } else {
            Some(U256(result))
        }
    }
    
    /// Checked multiplication by u64
    pub fn checked_mul_u64(&self, other: u64) -> Option<U256> {
        let mut result = [0u64; 4];
        let mut carry = 0u128;
        
        for i in 0..4 {
            let prod = (self.0[i] as u128) * (other as u128) + carry;
            result[i] = prod as u64;
            carry = prod >> 64;
        }
        
        if carry != 0 {
            None
        } else {
            Some(U256(result))
        }
    }
    
    /// Check if zero
    pub fn is_zero(&self) -> bool {
        self.0 == [0, 0, 0, 0]
    }
    
    /// Get as u64 (truncates)
    pub fn as_u64(&self) -> u64 {
        self.0[0]
    }
    
    /// Get as u128 (truncates)
    pub fn as_u128(&self) -> u128 {
        (self.0[1] as u128) << 64 | (self.0[0] as u128)
    }
    
    /// To hex string
    pub fn to_hex(&self) -> String {
        hex::encode(self.to_be_bytes())
    }
}

/// 256-bit signed integer
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct I256(pub U256, pub bool); // (abs value, is_negative)

impl I256 {
    pub const ZERO: I256 = I256(U256::ZERO, false);
    
    /// Create from i64
    pub fn from(value: i64) -> Self {
        if value >= 0 {
            I256(U256::from(value as u64), false)
        } else {
            I256(U256::from((-value) as u64), true)
        }
    }
    
    /// Create from i128
    pub fn from_i128(value: i128) -> Self {
        if value >= 0 {
            I256(U256::from_u128(value as u128), false)
        } else {
            I256(U256::from_u128((-value) as u128), true)
        }
    }
    
    /// Convert to bytes (big-endian, two's complement, 32 bytes)
    pub fn to_be_bytes(&self) -> [u8; 32] {
        if !self.1 {
            // Positive or zero
            self.0.to_be_bytes()
        } else {
            // Negative: two's complement
            let mut bytes = self.0.to_be_bytes();
            // Invert all bits
            for b in &mut bytes {
                *b = !*b;
            }
            // Add 1
            let mut carry = 1u8;
            for i in (0..32).rev() {
                let (sum, c) = bytes[i].overflowing_add(carry);
                bytes[i] = sum;
                carry = c as u8;
                if carry == 0 {
                    break;
                }
            }
            bytes
        }
    }
    
    /// Create from bytes (big-endian, two's complement)
    pub fn from_be_bytes(bytes: &[u8]) -> Self {
        if bytes.is_empty() {
            return I256::ZERO;
        }
        
        // Check if negative (high bit set)
        let is_negative = bytes[0] & 0x80 != 0;
        
        if !is_negative {
            I256(U256::from_be_bytes(bytes), false)
        } else {
            // Two's complement: invert and add 1
            let mut inverted = bytes.to_vec();
            for b in &mut inverted {
                *b = !*b;
            }
            // Add 1
            let mut carry = 1u8;
            for i in (0..inverted.len()).rev() {
                let (sum, c) = inverted[i].overflowing_add(carry);
                inverted[i] = sum;
                carry = c as u8;
                if carry == 0 {
                    break;
                }
            }
            I256(U256::from_be_bytes(&inverted), true)
        }
    }
}

/// ABI function definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AbiFunction {
    /// Function name
    pub name: String,
    /// Input parameters
    pub inputs: Vec<AbiParam>,
    /// Output parameters
    pub outputs: Vec<AbiParam>,
    /// State mutability
    #[serde(default)]
    pub state_mutability: StateMutability,
    /// Function type (function, constructor, fallback, receive)
    #[serde(default, rename = "type")]
    pub function_type: FunctionType,
}

impl AbiFunction {
    /// Get the function signature for selector calculation
    pub fn signature(&self) -> String {
        let params = self.inputs
            .iter()
            .map(|p| p.param_type.canonical_type())
            .collect::<Vec<_>>()
            .join(",");
        format!("{}({})", self.name, params)
    }
}

/// ABI event definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AbiEvent {
    /// Event name
    pub name: String,
    /// Event parameters
    pub inputs: Vec<AbiEventParam>,
    /// Is anonymous event
    #[serde(default)]
    pub anonymous: bool,
}

impl AbiEvent {
    /// Get the event signature for topic calculation
    pub fn signature(&self) -> String {
        let params = self.inputs
            .iter()
            .map(|p| p.param.param_type.canonical_type())
            .collect::<Vec<_>>()
            .join(",");
        format!("{}({})", self.name, params)
    }
}

/// ABI parameter
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AbiParam {
    /// Parameter name (can be empty)
    #[serde(default)]
    pub name: String,
    /// Parameter type
    #[serde(rename = "type", deserialize_with = "deserialize_abi_type")]
    pub param_type: AbiType,
    /// Tuple components (for tuple types)
    #[serde(default)]
    pub components: Vec<AbiParam>,
}

/// ABI event parameter
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AbiEventParam {
    /// Base parameter
    #[serde(flatten)]
    pub param: AbiParam,
    /// Whether the parameter is indexed
    #[serde(default)]
    pub indexed: bool,
}

/// State mutability
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum StateMutability {
    #[default]
    Nonpayable,
    Payable,
    View,
    Pure,
}

/// Function type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum FunctionType {
    #[default]
    Function,
    Constructor,
    Fallback,
    Receive,
}

/// Custom deserializer for AbiType from string
fn deserialize_abi_type<'de, D>(deserializer: D) -> Result<AbiType, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    AbiType::from_str(&s).map_err(serde::de::Error::custom)
}

/// ABI errors
#[derive(Debug, Clone)]
pub enum AbiError {
    /// Invalid type specification
    InvalidType(String),
    /// Invalid value for type
    InvalidValue(String),
    /// Encoding error
    EncodingError(String),
    /// Decoding error
    DecodingError(String),
    /// Type mismatch
    TypeMismatch { expected: String, got: String },
    /// Overflow
    Overflow,
    /// Invalid ABI JSON
    InvalidAbi(String),
    /// Function not found
    FunctionNotFound(String),
    /// Event not found
    EventNotFound(String),
}

impl fmt::Display for AbiError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            AbiError::InvalidType(s) => write!(f, "Invalid type: {}", s),
            AbiError::InvalidValue(s) => write!(f, "Invalid value: {}", s),
            AbiError::EncodingError(s) => write!(f, "Encoding error: {}", s),
            AbiError::DecodingError(s) => write!(f, "Decoding error: {}", s),
            AbiError::TypeMismatch { expected, got } => {
                write!(f, "Type mismatch: expected {}, got {}", expected, got)
            }
            AbiError::Overflow => write!(f, "Numeric overflow"),
            AbiError::InvalidAbi(s) => write!(f, "Invalid ABI: {}", s),
            AbiError::FunctionNotFound(s) => write!(f, "Function not found: {}", s),
            AbiError::EventNotFound(s) => write!(f, "Event not found: {}", s),
        }
    }
}

impl std::error::Error for AbiError {}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_abi_type_from_str() {
        assert_eq!(AbiType::from_str("uint256").unwrap(), AbiType::Uint256);
        assert_eq!(AbiType::from_str("uint").unwrap(), AbiType::Uint256);
        assert_eq!(AbiType::from_str("int256").unwrap(), AbiType::Int256);
        assert_eq!(AbiType::from_str("address").unwrap(), AbiType::Address);
        assert_eq!(AbiType::from_str("bool").unwrap(), AbiType::Bool);
        assert_eq!(AbiType::from_str("bytes32").unwrap(), AbiType::Bytes32);
        assert_eq!(AbiType::from_str("bytes").unwrap(), AbiType::Bytes);
        assert_eq!(AbiType::from_str("string").unwrap(), AbiType::String);
    }
    
    #[test]
    fn test_abi_type_arrays() {
        assert_eq!(
            AbiType::from_str("uint256[]").unwrap(),
            AbiType::Array(Box::new(AbiType::Uint256))
        );
        assert_eq!(
            AbiType::from_str("address[5]").unwrap(),
            AbiType::FixedArray(Box::new(AbiType::Address), 5)
        );
    }
    
    #[test]
    fn test_abi_type_tuple() {
        let tuple = AbiType::from_str("(uint256,address,bool)").unwrap();
        assert_eq!(
            tuple,
            AbiType::Tuple(vec![AbiType::Uint256, AbiType::Address, AbiType::Bool])
        );
    }
    
    #[test]
    fn test_abi_type_is_dynamic() {
        assert!(!AbiType::Uint256.is_dynamic());
        assert!(!AbiType::Address.is_dynamic());
        assert!(!AbiType::Bool.is_dynamic());
        assert!(!AbiType::Bytes32.is_dynamic());
        
        assert!(AbiType::Bytes.is_dynamic());
        assert!(AbiType::String.is_dynamic());
        assert!(AbiType::Array(Box::new(AbiType::Uint256)).is_dynamic());
        
        assert!(!AbiType::FixedArray(Box::new(AbiType::Uint256), 5).is_dynamic());
        assert!(AbiType::FixedArray(Box::new(AbiType::String), 5).is_dynamic());
    }
    
    #[test]
    fn test_u256_from_dec() {
        let value = U256::from_dec("12345").unwrap();
        assert_eq!(value.as_u64(), 12345);
    }
    
    #[test]
    fn test_u256_from_hex() {
        let value = U256::from_hex("ff").unwrap();
        assert_eq!(value.as_u64(), 255);
    }
    
    #[test]
    fn test_u256_to_be_bytes() {
        let value = U256::from(256);
        let bytes = value.to_be_bytes();
        assert_eq!(bytes[30], 1);
        assert_eq!(bytes[31], 0);
    }
    
    #[test]
    fn test_abi_value_address() {
        let addr = AbiValue::address_from_str("0x1234567890123456789012345678901234567890").unwrap();
        if let AbiValue::Address(bytes) = addr {
            assert_eq!(bytes[0], 0x12);
            assert_eq!(bytes[19], 0x90);
        } else {
            panic!("Expected Address");
        }
    }
    
    #[test]
    fn test_canonical_type() {
        assert_eq!(AbiType::Uint256.canonical_type(), "uint256");
        assert_eq!(AbiType::Array(Box::new(AbiType::Address)).canonical_type(), "address[]");
        assert_eq!(
            AbiType::Tuple(vec![AbiType::Uint256, AbiType::Bool]).canonical_type(),
            "(uint256,bool)"
        );
    }
}
