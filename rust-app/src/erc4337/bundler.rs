//! ERC-4337 Bundler Integration
//!
//! Handles communication with bundler services (Pimlico, Alchemy, Stackup).

use crate::error::{HawalaError, HawalaResult, ErrorCode};
use super::{UserOperation, UserOperationReceipt, ERC4337Chain};
use serde::{Deserialize, Serialize};
use std::time::Duration;

/// Bundler client for submitting UserOperations
pub struct BundlerClient {
    url: String,
    api_key: Option<String>,
    chain: ERC4337Chain,
}

/// RPC request structure
#[derive(Debug, Serialize)]
struct RpcRequest<T: Serialize> {
    jsonrpc: &'static str,
    method: &'static str,
    params: T,
    id: u64,
}

/// RPC response structure
#[derive(Debug, Deserialize)]
struct RpcResponse<T> {
    #[allow(dead_code)]
    jsonrpc: String,
    result: Option<T>,
    error: Option<RpcError>,
    #[allow(dead_code)]
    id: u64,
}

#[derive(Debug, Deserialize)]
struct RpcError {
    code: i64,
    message: String,
    #[allow(dead_code)]
    data: Option<serde_json::Value>,
}

impl BundlerClient {
    /// Create a new bundler client
    pub fn new(chain: ERC4337Chain) -> Self {
        Self {
            url: chain.default_bundler_url().to_string(),
            api_key: None,
            chain,
        }
    }
    
    /// Create with custom URL
    pub fn with_url(url: &str, chain: ERC4337Chain) -> Self {
        Self {
            url: url.to_string(),
            api_key: None,
            chain,
        }
    }
    
    /// Set API key
    pub fn with_api_key(mut self, api_key: &str) -> Self {
        self.api_key = Some(api_key.to_string());
        self.url = format!("{}?apikey={}", self.url, api_key);
        self
    }
    
    /// Get supported entry points
    pub fn get_supported_entry_points(&self) -> HawalaResult<Vec<String>> {
        let request = RpcRequest {
            jsonrpc: "2.0",
            method: "eth_supportedEntryPoints",
            params: (),
            id: 1,
        };
        
        let response: RpcResponse<Vec<String>> = self.send_request(&request)?;
        
        match response.result {
            Some(entry_points) => Ok(entry_points),
            None => {
                let error_msg = response.error
                    .map(|e| e.message)
                    .unwrap_or_else(|| "Unknown error".to_string());
                Err(HawalaError::new(ErrorCode::NetworkError, error_msg))
            }
        }
    }
    
    /// Estimate gas for a UserOperation
    pub fn estimate_user_operation_gas(
        &self,
        user_op: &UserOperation,
    ) -> HawalaResult<GasEstimate> {
        let request = RpcRequest {
            jsonrpc: "2.0",
            method: "eth_estimateUserOperationGas",
            params: (user_op, self.chain.entry_point()),
            id: 1,
        };
        
        let response: RpcResponse<GasEstimate> = self.send_request(&request)?;
        
        match response.result {
            Some(estimate) => Ok(estimate),
            None => {
                let error_msg = response.error
                    .map(|e| format!("{}: {}", e.code, e.message))
                    .unwrap_or_else(|| "Gas estimation failed".to_string());
                Err(HawalaError::new(ErrorCode::NetworkError, error_msg))
            }
        }
    }
    
    /// Submit a UserOperation to the bundler
    pub fn send_user_operation(
        &self,
        user_op: &UserOperation,
    ) -> HawalaResult<String> {
        let request = RpcRequest {
            jsonrpc: "2.0",
            method: "eth_sendUserOperation",
            params: (user_op, self.chain.entry_point()),
            id: 1,
        };
        
        let response: RpcResponse<String> = self.send_request(&request)?;
        
        match response.result {
            Some(user_op_hash) => Ok(user_op_hash),
            None => {
                let error_msg = response.error
                    .map(|e| format!("Bundler rejected: {}", e.message))
                    .unwrap_or_else(|| "Failed to submit UserOperation".to_string());
                Err(HawalaError::new(ErrorCode::NetworkError, error_msg))
            }
        }
    }
    
    /// Get UserOperation receipt
    pub fn get_user_operation_receipt(
        &self,
        user_op_hash: &str,
    ) -> HawalaResult<Option<UserOperationReceipt>> {
        let request = RpcRequest {
            jsonrpc: "2.0",
            method: "eth_getUserOperationReceipt",
            params: (user_op_hash,),
            id: 1,
        };
        
        let response: RpcResponse<UserOperationReceipt> = self.send_request(&request)?;
        
        Ok(response.result)
    }
    
    /// Get UserOperation by hash
    pub fn get_user_operation_by_hash(
        &self,
        user_op_hash: &str,
    ) -> HawalaResult<Option<UserOperationWithInfo>> {
        let request = RpcRequest {
            jsonrpc: "2.0",
            method: "eth_getUserOperationByHash",
            params: (user_op_hash,),
            id: 1,
        };
        
        let response: RpcResponse<UserOperationWithInfo> = self.send_request(&request)?;
        
        Ok(response.result)
    }
    
    /// Wait for UserOperation to be included
    pub fn wait_for_receipt(
        &self,
        user_op_hash: &str,
        timeout_secs: u64,
    ) -> HawalaResult<UserOperationReceipt> {
        let start = std::time::Instant::now();
        let timeout = Duration::from_secs(timeout_secs);
        
        loop {
            if start.elapsed() > timeout {
                return Err(HawalaError::new(
                    ErrorCode::Timeout,
                    format!("Timeout waiting for UserOperation {}", user_op_hash),
                ));
            }
            
            match self.get_user_operation_receipt(user_op_hash)? {
                Some(receipt) => return Ok(receipt),
                None => {
                    std::thread::sleep(Duration::from_secs(2));
                }
            }
        }
    }
    
    /// Send RPC request
    fn send_request<T: Serialize, R: for<'de> Deserialize<'de>>(
        &self,
        request: &RpcRequest<T>,
    ) -> HawalaResult<RpcResponse<R>> {
        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .map_err(|e| HawalaError::new(ErrorCode::NetworkError, format!("Client error: {}", e)))?;
        
        let response = client
            .post(&self.url)
            .json(request)
            .send()
            .map_err(|e| HawalaError::new(ErrorCode::NetworkError, format!("Request failed: {}", e)))?;
        
        if !response.status().is_success() {
            return Err(HawalaError::new(
                ErrorCode::NetworkError,
                format!("Bundler returned {}", response.status()),
            ));
        }
        
        response.json()
            .map_err(|e| HawalaError::new(ErrorCode::ParseError, format!("Invalid response: {}", e)))
    }
}

/// Gas estimate from bundler
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GasEstimate {
    pub pre_verification_gas: String,
    pub verification_gas_limit: String,
    pub call_gas_limit: String,
    #[serde(default)]
    pub paymaster_verification_gas_limit: Option<String>,
    #[serde(default)]
    pub paymaster_post_op_gas_limit: Option<String>,
}

impl GasEstimate {
    /// Parse hex values to u64
    pub fn pre_verification_gas_u64(&self) -> u64 {
        Self::parse_hex(&self.pre_verification_gas)
    }
    
    pub fn verification_gas_limit_u64(&self) -> u64 {
        Self::parse_hex(&self.verification_gas_limit)
    }
    
    pub fn call_gas_limit_u64(&self) -> u64 {
        Self::parse_hex(&self.call_gas_limit)
    }
    
    fn parse_hex(s: &str) -> u64 {
        let s = s.strip_prefix("0x").unwrap_or(s);
        u64::from_str_radix(s, 16).unwrap_or(0)
    }
}

/// UserOperation with transaction info
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UserOperationWithInfo {
    pub user_operation: UserOperation,
    pub entry_point: String,
    pub block_number: Option<String>,
    pub block_hash: Option<String>,
    pub transaction_hash: Option<String>,
}

/// Bundler status
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BundlerStatus {
    pub is_connected: bool,
    pub supported_chains: Vec<u64>,
    pub entry_points: Vec<String>,
    pub mempool_size: u64,
}

/// Bundler provider enum
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum BundlerProvider {
    Pimlico,
    Alchemy,
    Stackup,
    Biconomy,
    Custom,
}

impl BundlerProvider {
    /// Get base URL for provider
    pub fn base_url(&self, chain_id: u64) -> String {
        match self {
            Self::Pimlico => format!("https://api.pimlico.io/v2/{}/rpc", chain_id),
            Self::Alchemy => format!("https://eth-mainnet.g.alchemy.com/v2"), // needs API key
            Self::Stackup => format!("https://api.stackup.sh/v1/node/{}", chain_id),
            Self::Biconomy => format!("https://bundler.biconomy.io/api/v2/{}", chain_id),
            Self::Custom => String::new(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bundler_client_creation() {
        let client = BundlerClient::new(ERC4337Chain::Ethereum);
        assert!(client.url.contains("pimlico"));
    }

    #[test]
    fn test_gas_estimate_parsing() {
        let estimate = GasEstimate {
            pre_verification_gas: "0xc350".to_string(),
            verification_gas_limit: "0x186a0".to_string(),
            call_gas_limit: "0x30d40".to_string(),
            paymaster_verification_gas_limit: None,
            paymaster_post_op_gas_limit: None,
        };
        
        assert_eq!(estimate.pre_verification_gas_u64(), 50000);
        assert_eq!(estimate.verification_gas_limit_u64(), 100000);
        assert_eq!(estimate.call_gas_limit_u64(), 200000);
    }

    #[test]
    fn test_bundler_provider_urls() {
        let url = BundlerProvider::Pimlico.base_url(1);
        assert!(url.contains("pimlico"));
        assert!(url.contains("/1/"));
    }
}
