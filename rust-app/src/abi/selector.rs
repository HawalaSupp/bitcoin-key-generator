//! Function selector and event topic calculation

use sha3::{Keccak256, Digest};
use super::types::*;

/// ABI selector calculator
pub struct AbiSelector;

impl AbiSelector {
    /// Calculate function selector (first 4 bytes of keccak256(signature))
    pub fn function_selector(function: &AbiFunction) -> [u8; 4] {
        Self::selector_from_signature(&function.signature())
    }
    
    /// Calculate function selector from signature string
    pub fn selector_from_signature(signature: &str) -> [u8; 4] {
        let hash = Self::keccak256(signature.as_bytes());
        [hash[0], hash[1], hash[2], hash[3]]
    }
    
    /// Calculate event topic (keccak256(signature))
    pub fn event_topic(event: &AbiEvent) -> [u8; 32] {
        Self::keccak256(event.signature().as_bytes())
    }
    
    /// Calculate event topic from signature string
    pub fn topic_from_signature(signature: &str) -> [u8; 32] {
        Self::keccak256(signature.as_bytes())
    }
    
    /// Calculate keccak256 hash
    pub fn keccak256(data: &[u8]) -> [u8; 32] {
        let mut hasher = Keccak256::new();
        hasher.update(data);
        let result = hasher.finalize();
        let mut output = [0u8; 32];
        output.copy_from_slice(&result);
        output
    }
    
    /// Get selector as hex string (with 0x prefix)
    pub fn selector_hex(function: &AbiFunction) -> String {
        let selector = Self::function_selector(function);
        format!("0x{}", hex::encode(selector))
    }
    
    /// Get topic as hex string (with 0x prefix)
    pub fn topic_hex(event: &AbiEvent) -> String {
        let topic = Self::event_topic(event);
        format!("0x{}", hex::encode(topic))
    }
}

/// Well-known function selectors
pub struct KnownSelectors;

impl KnownSelectors {
    // ERC-20
    pub const TRANSFER: [u8; 4] = [0xa9, 0x05, 0x9c, 0xbb];           // transfer(address,uint256)
    pub const APPROVE: [u8; 4] = [0x09, 0x5e, 0xa7, 0xb3];            // approve(address,uint256)
    pub const TRANSFER_FROM: [u8; 4] = [0x23, 0xb8, 0x72, 0xdd];      // transferFrom(address,address,uint256)
    pub const BALANCE_OF: [u8; 4] = [0x70, 0xa0, 0x82, 0x31];         // balanceOf(address)
    pub const ALLOWANCE: [u8; 4] = [0xdd, 0x62, 0xed, 0x3e];          // allowance(address,address)
    pub const TOTAL_SUPPLY: [u8; 4] = [0x18, 0x16, 0x0d, 0xdd];       // totalSupply()
    pub const NAME: [u8; 4] = [0x06, 0xfd, 0xde, 0x03];               // name()
    pub const SYMBOL: [u8; 4] = [0x95, 0xd8, 0x9b, 0x41];             // symbol()
    pub const DECIMALS: [u8; 4] = [0x31, 0x3c, 0xe5, 0x67];           // decimals()
    
    // ERC-721
    pub const OWNER_OF: [u8; 4] = [0x63, 0x52, 0x21, 0x1e];           // ownerOf(uint256)
    pub const TOKEN_URI: [u8; 4] = [0xc8, 0x7b, 0x56, 0xdd];          // tokenURI(uint256)
    pub const SAFE_TRANSFER_FROM: [u8; 4] = [0x42, 0x84, 0x2e, 0x0e]; // safeTransferFrom(address,address,uint256)
    pub const GET_APPROVED: [u8; 4] = [0x08, 0x18, 0x12, 0xfc];       // getApproved(uint256)
    pub const SET_APPROVAL_FOR_ALL: [u8; 4] = [0xa2, 0x2c, 0xb4, 0x65]; // setApprovalForAll(address,bool)
    pub const IS_APPROVED_FOR_ALL: [u8; 4] = [0xe9, 0x85, 0xe9, 0xc5]; // isApprovedForAll(address,address)
    
    // ERC-1155
    pub const BALANCE_OF_BATCH: [u8; 4] = [0x4e, 0x12, 0x73, 0xf4];   // balanceOfBatch(address[],uint256[])
    pub const SAFE_TRANSFER_FROM_1155: [u8; 4] = [0xf2, 0x42, 0x43, 0x2a]; // safeTransferFrom(address,address,uint256,uint256,bytes)
    pub const SAFE_BATCH_TRANSFER_FROM: [u8; 4] = [0x2e, 0xb2, 0xc2, 0xd6]; // safeBatchTransferFrom(...)
    
    // Common
    pub const SUPPORTS_INTERFACE: [u8; 4] = [0x01, 0xff, 0xc9, 0xa7]; // supportsInterface(bytes4)
    
    /// Identify a function by its selector
    pub fn identify(selector: &[u8; 4]) -> Option<&'static str> {
        match *selector {
            Self::TRANSFER => Some("transfer(address,uint256)"),
            Self::APPROVE => Some("approve(address,uint256)"),
            Self::TRANSFER_FROM => Some("transferFrom(address,address,uint256)"),
            Self::BALANCE_OF => Some("balanceOf(address)"),
            Self::ALLOWANCE => Some("allowance(address,address)"),
            Self::TOTAL_SUPPLY => Some("totalSupply()"),
            Self::NAME => Some("name()"),
            Self::SYMBOL => Some("symbol()"),
            Self::DECIMALS => Some("decimals()"),
            Self::OWNER_OF => Some("ownerOf(uint256)"),
            Self::TOKEN_URI => Some("tokenURI(uint256)"),
            Self::SAFE_TRANSFER_FROM => Some("safeTransferFrom(address,address,uint256)"),
            Self::GET_APPROVED => Some("getApproved(uint256)"),
            Self::SET_APPROVAL_FOR_ALL => Some("setApprovalForAll(address,bool)"),
            Self::IS_APPROVED_FOR_ALL => Some("isApprovedForAll(address,address)"),
            Self::SUPPORTS_INTERFACE => Some("supportsInterface(bytes4)"),
            _ => None,
        }
    }
}

/// Well-known event topics
pub struct KnownTopics;

impl KnownTopics {
    // ERC-20 events
    pub const TRANSFER: [u8; 32] = [
        0xdd, 0xf2, 0x52, 0xad, 0x1b, 0xe2, 0xc8, 0x9b,
        0x69, 0xc2, 0xb0, 0x68, 0xfc, 0x37, 0x8d, 0xaa,
        0x95, 0x2b, 0xa7, 0xf1, 0x63, 0xc4, 0xa1, 0x16,
        0x28, 0xf5, 0x5a, 0x4d, 0xf5, 0x23, 0xb3, 0xef,
    ];
    
    pub const APPROVAL: [u8; 32] = [
        0x8c, 0x5b, 0xe1, 0xe5, 0xeb, 0xec, 0x7d, 0x5b,
        0xd1, 0x4f, 0x71, 0x42, 0x7d, 0x1e, 0x84, 0xf3,
        0xdd, 0x03, 0x14, 0xc0, 0xf7, 0xb2, 0x29, 0x1e,
        0x5b, 0x20, 0x0a, 0xc8, 0xc7, 0xc3, 0xb9, 0x25,
    ];
    
    /// Identify an event by its topic
    pub fn identify(topic: &[u8; 32]) -> Option<&'static str> {
        match *topic {
            Self::TRANSFER => Some("Transfer(address,address,uint256)"),
            Self::APPROVAL => Some("Approval(address,address,uint256)"),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_transfer_selector() {
        let selector = AbiSelector::selector_from_signature("transfer(address,uint256)");
        assert_eq!(selector, [0xa9, 0x05, 0x9c, 0xbb]);
    }
    
    #[test]
    fn test_balance_of_selector() {
        let selector = AbiSelector::selector_from_signature("balanceOf(address)");
        assert_eq!(selector, [0x70, 0xa0, 0x82, 0x31]);
    }
    
    #[test]
    fn test_approve_selector() {
        let selector = AbiSelector::selector_from_signature("approve(address,uint256)");
        assert_eq!(selector, [0x09, 0x5e, 0xa7, 0xb3]);
    }
    
    #[test]
    fn test_transfer_from_selector() {
        let selector = AbiSelector::selector_from_signature("transferFrom(address,address,uint256)");
        assert_eq!(selector, [0x23, 0xb8, 0x72, 0xdd]);
    }
    
    #[test]
    fn test_transfer_event_topic() {
        let topic = AbiSelector::topic_from_signature("Transfer(address,address,uint256)");
        assert_eq!(topic, KnownTopics::TRANSFER);
    }
    
    #[test]
    fn test_approval_event_topic() {
        let topic = AbiSelector::topic_from_signature("Approval(address,address,uint256)");
        assert_eq!(topic, KnownTopics::APPROVAL);
    }
    
    #[test]
    fn test_known_selectors() {
        assert_eq!(KnownSelectors::TRANSFER, [0xa9, 0x05, 0x9c, 0xbb]);
        assert_eq!(KnownSelectors::BALANCE_OF, [0x70, 0xa0, 0x82, 0x31]);
        assert_eq!(KnownSelectors::APPROVE, [0x09, 0x5e, 0xa7, 0xb3]);
    }
    
    #[test]
    fn test_identify_selector() {
        let identified = KnownSelectors::identify(&KnownSelectors::TRANSFER);
        assert_eq!(identified, Some("transfer(address,uint256)"));
        
        let unknown = KnownSelectors::identify(&[0x00, 0x00, 0x00, 0x00]);
        assert_eq!(unknown, None);
    }
    
    #[test]
    fn test_identify_topic() {
        let identified = KnownTopics::identify(&KnownTopics::TRANSFER);
        assert_eq!(identified, Some("Transfer(address,address,uint256)"));
    }
    
    #[test]
    fn test_keccak256() {
        // Empty string
        let hash = AbiSelector::keccak256(b"");
        let expected = hex::decode("c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470").unwrap();
        assert_eq!(&hash[..], &expected[..]);
        
        // "hello"
        let hash = AbiSelector::keccak256(b"hello");
        let expected = hex::decode("1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8").unwrap();
        assert_eq!(&hash[..], &expected[..]);
    }
    
    #[test]
    fn test_selector_hex() {
        let function = AbiFunction {
            name: "transfer".to_string(),
            inputs: vec![
                AbiParam { name: "to".to_string(), param_type: AbiType::Address, components: vec![] },
                AbiParam { name: "amount".to_string(), param_type: AbiType::Uint256, components: vec![] },
            ],
            outputs: vec![
                AbiParam { name: "".to_string(), param_type: AbiType::Bool, components: vec![] },
            ],
            state_mutability: StateMutability::Nonpayable,
            function_type: FunctionType::Function,
        };
        
        assert_eq!(AbiSelector::selector_hex(&function), "0xa9059cbb");
    }
    
    #[test]
    fn test_complex_signature() {
        // Tuple signature
        let selector = AbiSelector::selector_from_signature("foo((uint256,address),bytes32)");
        // Just verify it doesn't panic and returns 4 bytes
        assert_eq!(selector.len(), 4);
    }
}
