//! ERC-4337 Paymaster Integration
//!
//! Enables gasless transactions by sponsoring UserOperations.

use crate::error::{HawalaError, HawalaResult, ErrorCode};
use super::{UserOperation, ERC4337Chain};
use serde::{Deserialize, Serialize};
use std::time::Duration;

/// Paymaster manager for sponsoring transactions
pub struct PaymasterManager {
    provider: PaymasterProvider,
    api_key: Option<String>,
}

/// Supported paymaster providers
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PaymasterProvider {
    /// Pimlico verifying paymaster
    Pimlico,
    /// Alchemy Gas Manager
    Alchemy,
    /// Stackup paymaster
    Stackup,
    /// ZeroDev paymaster
    ZeroDev,
    /// Custom paymaster
    Custom,
}

impl PaymasterManager {
    /// Create a new paymaster manager
    pub fn new(provider: PaymasterProvider) -> Self {
        Self {
            provider,
            api_key: None,
        }
    }
    
    /// Set API key
    pub fn with_api_key(mut self, api_key: &str) -> Self {
        self.api_key = Some(api_key.to_string());
        self
    }
    
    /// Check if a UserOperation can be sponsored
    pub fn check_sponsorship(
        &self,
        user_op: &UserOperation,
        chain: ERC4337Chain,
    ) -> HawalaResult<SponsorshipResult> {
        let url = self.get_url(chain)?;
        
        let request = SponsorshipRequest {
            jsonrpc: "2.0",
            method: "pm_sponsorUserOperation",
            params: SponsorParams {
                user_operation: user_op.clone(),
                entry_point: chain.entry_point().to_string(),
                context: SponsorContext::default(),
            },
            id: 1,
        };
        
        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(15))
            .build()
            .map_err(|e| HawalaError::new(ErrorCode::NetworkError, format!("Client error: {}", e)))?;
        
        let response = client
            .post(&url)
            .json(&request)
            .send()
            .map_err(|e| HawalaError::new(ErrorCode::NetworkError, format!("Request failed: {}", e)))?;
        
        if !response.status().is_success() {
            return Ok(SponsorshipResult {
                is_sponsored: false,
                paymaster: None,
                paymaster_data: None,
                reason: Some(format!("Paymaster returned {}", response.status())),
            });
        }
        
        let result: SponsorshipResponse = response.json()
            .map_err(|e| HawalaError::new(ErrorCode::ParseError, format!("Invalid response: {}", e)))?;
        
        match result.result {
            Some(data) => Ok(SponsorshipResult {
                is_sponsored: true,
                paymaster: Some(data.paymaster),
                paymaster_data: Some(PaymasterData {
                    paymaster_verification_gas_limit: data.paymaster_verification_gas_limit,
                    paymaster_post_op_gas_limit: data.paymaster_post_op_gas_limit,
                    paymaster_data: data.paymaster_data,
                }),
                reason: None,
            }),
            None => Ok(SponsorshipResult {
                is_sponsored: false,
                paymaster: None,
                paymaster_data: None,
                reason: result.error.map(|e| e.message),
            }),
        }
    }
    
    /// Sponsor a UserOperation (returns modified UserOp with paymaster data)
    pub fn sponsor_user_operation(
        &self,
        mut user_op: UserOperation,
        chain: ERC4337Chain,
    ) -> HawalaResult<UserOperation> {
        let result = self.check_sponsorship(&user_op, chain)?;
        
        if !result.is_sponsored {
            return Err(HawalaError::new(
                ErrorCode::InvalidInput,
                result.reason.unwrap_or_else(|| "Sponsorship denied".to_string()),
            ));
        }
        
        if let Some(paymaster) = result.paymaster {
            user_op.paymaster = Some(paymaster);
        }
        
        if let Some(data) = result.paymaster_data {
            user_op.paymaster_verification_gas_limit = Some(data.paymaster_verification_gas_limit);
            user_op.paymaster_post_op_gas_limit = Some(data.paymaster_post_op_gas_limit);
            user_op.paymaster_data = Some(data.paymaster_data);
        }
        
        Ok(user_op)
    }
    
    /// Get ERC-20 token paymaster quote
    pub fn get_token_paymaster_quote(
        &self,
        user_op: &UserOperation,
        token: &str,
        chain: ERC4337Chain,
    ) -> HawalaResult<TokenPaymasterQuote> {
        // Token paymaster allows paying gas with ERC-20 tokens
        let url = self.get_url(chain)?;
        
        #[derive(Serialize)]
        struct TokenQuoteRequest<'a> {
            jsonrpc: &'static str,
            method: &'static str,
            params: TokenQuoteParams<'a>,
            id: u64,
        }
        
        #[derive(Serialize)]
        #[serde(rename_all = "camelCase")]
        struct TokenQuoteParams<'a> {
            user_operation: &'a UserOperation,
            entry_point: String,
            token: String,
        }
        
        let request = TokenQuoteRequest {
            jsonrpc: "2.0",
            method: "pm_getTokenPaymasterQuote",
            params: TokenQuoteParams {
                user_operation: user_op,
                entry_point: chain.entry_point().to_string(),
                token: token.to_string(),
            },
            id: 1,
        };
        
        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(15))
            .build()
            .map_err(|e| HawalaError::new(ErrorCode::NetworkError, format!("Client error: {}", e)))?;
        
        let response = client
            .post(&url)
            .json(&request)
            .send()
            .map_err(|e| HawalaError::new(ErrorCode::NetworkError, format!("Request failed: {}", e)))?;
        
        if !response.status().is_success() {
            return Err(HawalaError::new(
                ErrorCode::NetworkError,
                format!("Token paymaster returned {}", response.status()),
            ));
        }
        
        #[derive(Deserialize)]
        struct TokenQuoteResponse {
            result: Option<TokenPaymasterQuote>,
            error: Option<RpcError>,
        }
        
        let result: TokenQuoteResponse = response.json()
            .map_err(|e| HawalaError::new(ErrorCode::ParseError, format!("Invalid response: {}", e)))?;
        
        result.result.ok_or_else(|| {
            HawalaError::new(
                ErrorCode::NetworkError,
                result.error.map(|e| e.message).unwrap_or_else(|| "Quote failed".to_string()),
            )
        })
    }
    
    /// Get paymaster URL for chain
    fn get_url(&self, chain: ERC4337Chain) -> HawalaResult<String> {
        let api_key = self.api_key.as_ref()
            .ok_or_else(|| HawalaError::new(ErrorCode::InvalidInput, "API key required"))?;
        
        Ok(match self.provider {
            PaymasterProvider::Pimlico => {
                format!("https://api.pimlico.io/v2/{}/rpc?apikey={}", chain.chain_id(), api_key)
            }
            PaymasterProvider::Alchemy => {
                format!("https://eth-mainnet.g.alchemy.com/v2/{}", api_key)
            }
            PaymasterProvider::Stackup => {
                format!("https://api.stackup.sh/v1/paymaster/{}?apiKey={}", chain.chain_id(), api_key)
            }
            PaymasterProvider::ZeroDev => {
                format!("https://rpc.zerodev.app/api/v2/paymaster/{}?projectId={}", chain.chain_id(), api_key)
            }
            PaymasterProvider::Custom => {
                return Err(HawalaError::new(
                    ErrorCode::InvalidInput,
                    "Custom paymaster requires explicit URL",
                ));
            }
        })
    }
}

/// Sponsorship check result
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SponsorshipResult {
    pub is_sponsored: bool,
    pub paymaster: Option<String>,
    pub paymaster_data: Option<PaymasterData>,
    pub reason: Option<String>,
}

/// Paymaster data to include in UserOperation
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PaymasterData {
    pub paymaster_verification_gas_limit: String,
    pub paymaster_post_op_gas_limit: String,
    pub paymaster_data: String,
}

/// Token paymaster quote
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TokenPaymasterQuote {
    pub token: String,
    pub token_symbol: String,
    pub token_decimals: u8,
    pub amount: String,
    pub amount_usd: f64,
    pub exchange_rate: String,
    pub paymaster: String,
    pub paymaster_data: PaymasterData,
}

// Internal types for RPC communication
#[derive(Serialize)]
struct SponsorshipRequest {
    jsonrpc: &'static str,
    method: &'static str,
    params: SponsorParams,
    id: u64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SponsorParams {
    user_operation: UserOperation,
    entry_point: String,
    context: SponsorContext,
}

#[derive(Serialize, Default)]
struct SponsorContext {
    #[serde(skip_serializing_if = "Option::is_none")]
    policy_id: Option<String>,
}

#[derive(Deserialize)]
struct SponsorshipResponse {
    result: Option<SponsorshipData>,
    error: Option<RpcError>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SponsorshipData {
    paymaster: String,
    paymaster_verification_gas_limit: String,
    paymaster_post_op_gas_limit: String,
    paymaster_data: String,
}

#[derive(Deserialize)]
struct RpcError {
    #[allow(dead_code)]
    code: i64,
    message: String,
}

/// Sponsorship policy for limiting sponsored transactions
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SponsorshipPolicy {
    pub policy_id: String,
    pub name: String,
    pub max_gas_per_tx: u64,
    pub max_tx_per_user: u64,
    pub daily_limit_usd: f64,
    pub allowed_chains: Vec<u64>,
    pub allowed_contracts: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_paymaster_manager_creation() {
        let manager = PaymasterManager::new(PaymasterProvider::Pimlico)
            .with_api_key("test_key");
        
        assert_eq!(manager.provider, PaymasterProvider::Pimlico);
        assert!(manager.api_key.is_some());
    }

    #[test]
    fn test_sponsorship_result() {
        let result = SponsorshipResult {
            is_sponsored: true,
            paymaster: Some("0x1234...".to_string()),
            paymaster_data: None,
            reason: None,
        };
        
        assert!(result.is_sponsored);
    }
}
