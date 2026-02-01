//! JSON ABI parser for Solidity contracts

use serde::Deserialize;
use super::types::*;

/// Parsed contract ABI
#[derive(Debug, Clone, Default)]
pub struct ContractAbi {
    /// Contract functions
    pub functions: Vec<AbiFunction>,
    /// Contract events
    pub events: Vec<AbiEvent>,
    /// Constructor (if present)
    pub constructor: Option<AbiFunction>,
    /// Fallback function
    pub fallback: Option<AbiFunction>,
    /// Receive function
    pub receive: Option<AbiFunction>,
}

impl ContractAbi {
    /// Parse ABI from JSON string
    pub fn from_json(json: &str) -> Result<Self, AbiError> {
        let items: Vec<AbiItem> = serde_json::from_str(json)
            .map_err(|e| AbiError::InvalidAbi(format!("JSON parse error: {}", e)))?;
        
        Self::from_items(items)
    }
    
    /// Parse ABI from JSON Value
    pub fn from_json_value(value: serde_json::Value) -> Result<Self, AbiError> {
        let items: Vec<AbiItem> = serde_json::from_value(value)
            .map_err(|e| AbiError::InvalidAbi(format!("JSON parse error: {}", e)))?;
        
        Self::from_items(items)
    }
    
    /// Build ABI from parsed items
    fn from_items(items: Vec<AbiItem>) -> Result<Self, AbiError> {
        let mut abi = ContractAbi::default();
        
        for item in items {
            match item {
                AbiItem::Function(f) => {
                    abi.functions.push(Self::convert_function(f)?);
                }
                AbiItem::Event(e) => {
                    abi.events.push(Self::convert_event(e)?);
                }
                AbiItem::Constructor(c) => {
                    abi.constructor = Some(Self::convert_constructor(c)?);
                }
                AbiItem::Fallback => {
                    abi.fallback = Some(AbiFunction {
                        name: "fallback".to_string(),
                        inputs: vec![],
                        outputs: vec![],
                        state_mutability: StateMutability::Payable,
                        function_type: FunctionType::Fallback,
                    });
                }
                AbiItem::Receive => {
                    abi.receive = Some(AbiFunction {
                        name: "receive".to_string(),
                        inputs: vec![],
                        outputs: vec![],
                        state_mutability: StateMutability::Payable,
                        function_type: FunctionType::Receive,
                    });
                }
                AbiItem::Error(_) => {
                    // Errors are not yet supported, skip
                }
            }
        }
        
        Ok(abi)
    }
    
    /// Convert parsed function to AbiFunction
    fn convert_function(f: ParsedFunction) -> Result<AbiFunction, AbiError> {
        Ok(AbiFunction {
            name: f.name,
            inputs: f.inputs.into_iter()
                .map(Self::convert_param)
                .collect::<Result<Vec<_>, _>>()?,
            outputs: f.outputs.unwrap_or_default().into_iter()
                .map(Self::convert_param)
                .collect::<Result<Vec<_>, _>>()?,
            state_mutability: f.state_mutability.unwrap_or_default(),
            function_type: FunctionType::Function,
        })
    }
    
    /// Convert parsed constructor
    fn convert_constructor(c: ParsedConstructor) -> Result<AbiFunction, AbiError> {
        Ok(AbiFunction {
            name: "constructor".to_string(),
            inputs: c.inputs.into_iter()
                .map(Self::convert_param)
                .collect::<Result<Vec<_>, _>>()?,
            outputs: vec![],
            state_mutability: c.state_mutability.unwrap_or_default(),
            function_type: FunctionType::Constructor,
        })
    }
    
    /// Convert parsed event
    fn convert_event(e: ParsedEvent) -> Result<AbiEvent, AbiError> {
        Ok(AbiEvent {
            name: e.name,
            inputs: e.inputs.into_iter()
                .map(Self::convert_event_param)
                .collect::<Result<Vec<_>, _>>()?,
            anonymous: e.anonymous.unwrap_or(false),
        })
    }
    
    /// Convert parsed parameter
    fn convert_param(p: ParsedParam) -> Result<AbiParam, AbiError> {
        let components = p.components.unwrap_or_default();
        
        let param_type = if p.param_type == "tuple" {
            // For tuple types, build from components
            let types = components.iter()
                .map(|c| Self::convert_param(c.clone()).map(|p| p.param_type))
                .collect::<Result<Vec<_>, _>>()?;
            AbiType::Tuple(types)
        } else if p.param_type.starts_with("tuple[") {
            // Tuple array
            let inner_types = components.iter()
                .map(|c| Self::convert_param(c.clone()).map(|p| p.param_type))
                .collect::<Result<Vec<_>, _>>()?;
            let tuple_type = AbiType::Tuple(inner_types);
            
            // Parse array suffix
            let suffix = &p.param_type[5..]; // after "tuple"
            if suffix == "[]" {
                AbiType::Array(Box::new(tuple_type))
            } else if let Some(size_str) = suffix.strip_prefix('[').and_then(|s| s.strip_suffix(']')) {
                let size: usize = size_str.parse()
                    .map_err(|_| AbiError::InvalidType(format!("Invalid array size: {}", size_str)))?;
                AbiType::FixedArray(Box::new(tuple_type), size)
            } else {
                return Err(AbiError::InvalidType(format!("Invalid tuple array type: {}", p.param_type)));
            }
        } else {
            AbiType::from_str(&p.param_type)?
        };
        
        Ok(AbiParam {
            name: p.name.unwrap_or_default(),
            param_type,
            components: components.into_iter()
                .map(Self::convert_param)
                .collect::<Result<Vec<_>, _>>()?,
        })
    }
    
    /// Convert parsed event parameter
    fn convert_event_param(p: ParsedEventParam) -> Result<AbiEventParam, AbiError> {
        let param = Self::convert_param(ParsedParam {
            name: Some(p.name),
            param_type: p.param_type,
            components: p.components,
            indexed: Some(p.indexed),
        })?;
        
        Ok(AbiEventParam {
            param,
            indexed: p.indexed,
        })
    }
    
    /// Get a function by name
    pub fn function(&self, name: &str) -> Option<&AbiFunction> {
        self.functions.iter().find(|f| f.name == name)
    }
    
    /// Get all functions with a given name (for overloaded functions)
    pub fn functions_by_name(&self, name: &str) -> Vec<&AbiFunction> {
        self.functions.iter().filter(|f| f.name == name).collect()
    }
    
    /// Get a function by selector
    pub fn function_by_selector(&self, selector: &[u8; 4]) -> Option<&AbiFunction> {
        use super::selector::AbiSelector;
        
        self.functions.iter().find(|f| {
            AbiSelector::function_selector(f) == *selector
        })
    }
    
    /// Get an event by name
    pub fn event(&self, name: &str) -> Option<&AbiEvent> {
        self.events.iter().find(|e| e.name == name)
    }
    
    /// Get an event by topic0
    pub fn event_by_topic(&self, topic: &[u8; 32]) -> Option<&AbiEvent> {
        use super::selector::AbiSelector;
        
        self.events.iter().find(|e| {
            AbiSelector::event_topic(e) == *topic
        })
    }
}

/// Raw ABI item for parsing
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "lowercase")]
#[allow(dead_code)]
enum AbiItem {
    Function(ParsedFunction),
    Event(ParsedEvent),
    Constructor(ParsedConstructor),
    Fallback,
    Receive,
    Error(ParsedError),
}

/// Parsed function
#[derive(Debug, Clone, Deserialize)]
struct ParsedFunction {
    name: String,
    #[serde(default)]
    inputs: Vec<ParsedParam>,
    outputs: Option<Vec<ParsedParam>>,
    #[serde(rename = "stateMutability")]
    state_mutability: Option<StateMutability>,
}

/// Parsed constructor
#[derive(Debug, Clone, Deserialize)]
struct ParsedConstructor {
    #[serde(default)]
    inputs: Vec<ParsedParam>,
    #[serde(rename = "stateMutability")]
    state_mutability: Option<StateMutability>,
}

/// Parsed event
#[derive(Debug, Clone, Deserialize)]
struct ParsedEvent {
    name: String,
    #[serde(default)]
    inputs: Vec<ParsedEventParam>,
    anonymous: Option<bool>,
}

/// Parsed error
#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
struct ParsedError {
    name: String,
    #[serde(default)]
    inputs: Vec<ParsedParam>,
}

/// Parsed parameter
#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
struct ParsedParam {
    name: Option<String>,
    #[serde(rename = "type")]
    param_type: String,
    components: Option<Vec<ParsedParam>>,
    indexed: Option<bool>,
}

/// Parsed event parameter
#[derive(Debug, Clone, Deserialize)]
struct ParsedEventParam {
    name: String,
    #[serde(rename = "type")]
    param_type: String,
    indexed: bool,
    components: Option<Vec<ParsedParam>>,
}

/// Well-known contract ABIs
pub struct KnownAbis;

impl KnownAbis {
    /// ERC-20 Token Standard ABI
    pub fn erc20() -> ContractAbi {
        let json = r#"[
            {"type":"function","name":"name","inputs":[],"outputs":[{"type":"string"}],"stateMutability":"view"},
            {"type":"function","name":"symbol","inputs":[],"outputs":[{"type":"string"}],"stateMutability":"view"},
            {"type":"function","name":"decimals","inputs":[],"outputs":[{"type":"uint8"}],"stateMutability":"view"},
            {"type":"function","name":"totalSupply","inputs":[],"outputs":[{"type":"uint256"}],"stateMutability":"view"},
            {"type":"function","name":"balanceOf","inputs":[{"name":"account","type":"address"}],"outputs":[{"type":"uint256"}],"stateMutability":"view"},
            {"type":"function","name":"transfer","inputs":[{"name":"to","type":"address"},{"name":"amount","type":"uint256"}],"outputs":[{"type":"bool"}],"stateMutability":"nonpayable"},
            {"type":"function","name":"allowance","inputs":[{"name":"owner","type":"address"},{"name":"spender","type":"address"}],"outputs":[{"type":"uint256"}],"stateMutability":"view"},
            {"type":"function","name":"approve","inputs":[{"name":"spender","type":"address"},{"name":"amount","type":"uint256"}],"outputs":[{"type":"bool"}],"stateMutability":"nonpayable"},
            {"type":"function","name":"transferFrom","inputs":[{"name":"from","type":"address"},{"name":"to","type":"address"},{"name":"amount","type":"uint256"}],"outputs":[{"type":"bool"}],"stateMutability":"nonpayable"},
            {"type":"event","name":"Transfer","inputs":[{"name":"from","type":"address","indexed":true},{"name":"to","type":"address","indexed":true},{"name":"value","type":"uint256","indexed":false}]},
            {"type":"event","name":"Approval","inputs":[{"name":"owner","type":"address","indexed":true},{"name":"spender","type":"address","indexed":true},{"name":"value","type":"uint256","indexed":false}]}
        ]"#;
        ContractAbi::from_json(json).unwrap()
    }
    
    /// ERC-721 NFT Standard ABI
    pub fn erc721() -> ContractAbi {
        let json = r#"[
            {"type":"function","name":"name","inputs":[],"outputs":[{"type":"string"}],"stateMutability":"view"},
            {"type":"function","name":"symbol","inputs":[],"outputs":[{"type":"string"}],"stateMutability":"view"},
            {"type":"function","name":"tokenURI","inputs":[{"name":"tokenId","type":"uint256"}],"outputs":[{"type":"string"}],"stateMutability":"view"},
            {"type":"function","name":"balanceOf","inputs":[{"name":"owner","type":"address"}],"outputs":[{"type":"uint256"}],"stateMutability":"view"},
            {"type":"function","name":"ownerOf","inputs":[{"name":"tokenId","type":"uint256"}],"outputs":[{"type":"address"}],"stateMutability":"view"},
            {"type":"function","name":"approve","inputs":[{"name":"to","type":"address"},{"name":"tokenId","type":"uint256"}],"outputs":[],"stateMutability":"nonpayable"},
            {"type":"function","name":"getApproved","inputs":[{"name":"tokenId","type":"uint256"}],"outputs":[{"type":"address"}],"stateMutability":"view"},
            {"type":"function","name":"setApprovalForAll","inputs":[{"name":"operator","type":"address"},{"name":"approved","type":"bool"}],"outputs":[],"stateMutability":"nonpayable"},
            {"type":"function","name":"isApprovedForAll","inputs":[{"name":"owner","type":"address"},{"name":"operator","type":"address"}],"outputs":[{"type":"bool"}],"stateMutability":"view"},
            {"type":"function","name":"transferFrom","inputs":[{"name":"from","type":"address"},{"name":"to","type":"address"},{"name":"tokenId","type":"uint256"}],"outputs":[],"stateMutability":"nonpayable"},
            {"type":"function","name":"safeTransferFrom","inputs":[{"name":"from","type":"address"},{"name":"to","type":"address"},{"name":"tokenId","type":"uint256"}],"outputs":[],"stateMutability":"nonpayable"},
            {"type":"event","name":"Transfer","inputs":[{"name":"from","type":"address","indexed":true},{"name":"to","type":"address","indexed":true},{"name":"tokenId","type":"uint256","indexed":true}]},
            {"type":"event","name":"Approval","inputs":[{"name":"owner","type":"address","indexed":true},{"name":"approved","type":"address","indexed":true},{"name":"tokenId","type":"uint256","indexed":true}]},
            {"type":"event","name":"ApprovalForAll","inputs":[{"name":"owner","type":"address","indexed":true},{"name":"operator","type":"address","indexed":true},{"name":"approved","type":"bool","indexed":false}]}
        ]"#;
        ContractAbi::from_json(json).unwrap()
    }
    
    /// ERC-1155 Multi-Token Standard ABI
    pub fn erc1155() -> ContractAbi {
        let json = r#"[
            {"type":"function","name":"uri","inputs":[{"name":"id","type":"uint256"}],"outputs":[{"type":"string"}],"stateMutability":"view"},
            {"type":"function","name":"balanceOf","inputs":[{"name":"account","type":"address"},{"name":"id","type":"uint256"}],"outputs":[{"type":"uint256"}],"stateMutability":"view"},
            {"type":"function","name":"balanceOfBatch","inputs":[{"name":"accounts","type":"address[]"},{"name":"ids","type":"uint256[]"}],"outputs":[{"type":"uint256[]"}],"stateMutability":"view"},
            {"type":"function","name":"setApprovalForAll","inputs":[{"name":"operator","type":"address"},{"name":"approved","type":"bool"}],"outputs":[],"stateMutability":"nonpayable"},
            {"type":"function","name":"isApprovedForAll","inputs":[{"name":"account","type":"address"},{"name":"operator","type":"address"}],"outputs":[{"type":"bool"}],"stateMutability":"view"},
            {"type":"function","name":"safeTransferFrom","inputs":[{"name":"from","type":"address"},{"name":"to","type":"address"},{"name":"id","type":"uint256"},{"name":"amount","type":"uint256"},{"name":"data","type":"bytes"}],"outputs":[],"stateMutability":"nonpayable"},
            {"type":"function","name":"safeBatchTransferFrom","inputs":[{"name":"from","type":"address"},{"name":"to","type":"address"},{"name":"ids","type":"uint256[]"},{"name":"amounts","type":"uint256[]"},{"name":"data","type":"bytes"}],"outputs":[],"stateMutability":"nonpayable"},
            {"type":"event","name":"TransferSingle","inputs":[{"name":"operator","type":"address","indexed":true},{"name":"from","type":"address","indexed":true},{"name":"to","type":"address","indexed":true},{"name":"id","type":"uint256","indexed":false},{"name":"value","type":"uint256","indexed":false}]},
            {"type":"event","name":"TransferBatch","inputs":[{"name":"operator","type":"address","indexed":true},{"name":"from","type":"address","indexed":true},{"name":"to","type":"address","indexed":true},{"name":"ids","type":"uint256[]","indexed":false},{"name":"values","type":"uint256[]","indexed":false}]},
            {"type":"event","name":"ApprovalForAll","inputs":[{"name":"account","type":"address","indexed":true},{"name":"operator","type":"address","indexed":true},{"name":"approved","type":"bool","indexed":false}]}
        ]"#;
        ContractAbi::from_json(json).unwrap()
    }
    
    /// Uniswap V2 Router ABI (partial)
    pub fn uniswap_v2_router() -> ContractAbi {
        let json = r#"[
            {"type":"function","name":"swapExactTokensForTokens","inputs":[{"name":"amountIn","type":"uint256"},{"name":"amountOutMin","type":"uint256"},{"name":"path","type":"address[]"},{"name":"to","type":"address"},{"name":"deadline","type":"uint256"}],"outputs":[{"name":"amounts","type":"uint256[]"}],"stateMutability":"nonpayable"},
            {"type":"function","name":"swapTokensForExactTokens","inputs":[{"name":"amountOut","type":"uint256"},{"name":"amountInMax","type":"uint256"},{"name":"path","type":"address[]"},{"name":"to","type":"address"},{"name":"deadline","type":"uint256"}],"outputs":[{"name":"amounts","type":"uint256[]"}],"stateMutability":"nonpayable"},
            {"type":"function","name":"swapExactETHForTokens","inputs":[{"name":"amountOutMin","type":"uint256"},{"name":"path","type":"address[]"},{"name":"to","type":"address"},{"name":"deadline","type":"uint256"}],"outputs":[{"name":"amounts","type":"uint256[]"}],"stateMutability":"payable"},
            {"type":"function","name":"swapExactTokensForETH","inputs":[{"name":"amountIn","type":"uint256"},{"name":"amountOutMin","type":"uint256"},{"name":"path","type":"address[]"},{"name":"to","type":"address"},{"name":"deadline","type":"uint256"}],"outputs":[{"name":"amounts","type":"uint256[]"}],"stateMutability":"nonpayable"},
            {"type":"function","name":"getAmountsOut","inputs":[{"name":"amountIn","type":"uint256"},{"name":"path","type":"address[]"}],"outputs":[{"name":"amounts","type":"uint256[]"}],"stateMutability":"view"},
            {"type":"function","name":"getAmountsIn","inputs":[{"name":"amountOut","type":"uint256"},{"name":"path","type":"address[]"}],"outputs":[{"name":"amounts","type":"uint256[]"}],"stateMutability":"view"}
        ]"#;
        ContractAbi::from_json(json).unwrap()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_parse_erc20_abi() {
        let abi = KnownAbis::erc20();
        
        assert_eq!(abi.functions.len(), 9);
        assert_eq!(abi.events.len(), 2);
        
        // Check transfer function
        let transfer = abi.function("transfer").unwrap();
        assert_eq!(transfer.inputs.len(), 2);
        assert_eq!(transfer.inputs[0].param_type, AbiType::Address);
        assert_eq!(transfer.inputs[1].param_type, AbiType::Uint256);
    }
    
    #[test]
    fn test_parse_erc721_abi() {
        let abi = KnownAbis::erc721();
        
        // Check ownerOf function
        let owner_of = abi.function("ownerOf").unwrap();
        assert_eq!(owner_of.inputs.len(), 1);
        assert_eq!(owner_of.outputs.len(), 1);
        assert_eq!(owner_of.outputs[0].param_type, AbiType::Address);
    }
    
    #[test]
    fn test_parse_custom_abi() {
        let json = r#"[
            {
                "type": "function",
                "name": "myFunction",
                "inputs": [
                    {"name": "arg1", "type": "uint256"},
                    {"name": "arg2", "type": "string"}
                ],
                "outputs": [
                    {"type": "bool"}
                ],
                "stateMutability": "view"
            }
        ]"#;
        
        let abi = ContractAbi::from_json(json).unwrap();
        
        assert_eq!(abi.functions.len(), 1);
        let f = &abi.functions[0];
        assert_eq!(f.name, "myFunction");
        assert_eq!(f.inputs.len(), 2);
        assert_eq!(f.outputs.len(), 1);
        assert_eq!(f.state_mutability, StateMutability::View);
    }
    
    #[test]
    fn test_parse_tuple_type() {
        let json = r#"[
            {
                "type": "function",
                "name": "getStruct",
                "inputs": [],
                "outputs": [
                    {
                        "name": "result",
                        "type": "tuple",
                        "components": [
                            {"name": "id", "type": "uint256"},
                            {"name": "owner", "type": "address"}
                        ]
                    }
                ],
                "stateMutability": "view"
            }
        ]"#;
        
        let abi = ContractAbi::from_json(json).unwrap();
        
        let f = &abi.functions[0];
        assert_eq!(f.outputs.len(), 1);
        
        if let AbiType::Tuple(components) = &f.outputs[0].param_type {
            assert_eq!(components.len(), 2);
            assert_eq!(components[0], AbiType::Uint256);
            assert_eq!(components[1], AbiType::Address);
        } else {
            panic!("Expected tuple type");
        }
    }
    
    #[test]
    fn test_parse_event() {
        let json = r#"[
            {
                "type": "event",
                "name": "Transfer",
                "inputs": [
                    {"name": "from", "type": "address", "indexed": true},
                    {"name": "to", "type": "address", "indexed": true},
                    {"name": "value", "type": "uint256", "indexed": false}
                ]
            }
        ]"#;
        
        let abi = ContractAbi::from_json(json).unwrap();
        
        assert_eq!(abi.events.len(), 1);
        let e = &abi.events[0];
        assert_eq!(e.name, "Transfer");
        assert_eq!(e.inputs.len(), 3);
        assert!(e.inputs[0].indexed);
        assert!(e.inputs[1].indexed);
        assert!(!e.inputs[2].indexed);
    }
    
    #[test]
    fn test_function_signature() {
        let abi = KnownAbis::erc20();
        let transfer = abi.function("transfer").unwrap();
        
        assert_eq!(transfer.signature(), "transfer(address,uint256)");
    }
    
    #[test]
    fn test_function_by_selector() {
        let abi = KnownAbis::erc20();
        
        // transfer selector = 0xa9059cbb
        let selector: [u8; 4] = [0xa9, 0x05, 0x9c, 0xbb];
        let f = abi.function_by_selector(&selector).unwrap();
        
        assert_eq!(f.name, "transfer");
    }
    
    #[test]
    fn test_uniswap_abi() {
        let abi = KnownAbis::uniswap_v2_router();
        
        let swap = abi.function("swapExactTokensForTokens").unwrap();
        assert_eq!(swap.inputs.len(), 5);
        
        // Check path is address[]
        assert_eq!(swap.inputs[2].param_type, AbiType::Array(Box::new(AbiType::Address)));
    }
}
