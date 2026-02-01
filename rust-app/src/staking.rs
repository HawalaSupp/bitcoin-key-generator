//! Staking Module
//!
//! Unified staking interface for Proof-of-Stake chains.
//! Supports delegation, unbonding, rewards claims, and validator info.

use crate::error::{HawalaError, HawalaResult, ErrorCode};
use crate::types::Chain;
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;

// =============================================================================
// Staking Types
// =============================================================================

/// Staking information for an address
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StakingInfo {
    pub chain: Chain,
    pub address: String,
    pub staked_amount: String,
    pub staked_raw: String,
    pub available_rewards: String,
    pub unbonding_amount: String,
    pub unbonding_completion: Option<u64>, // Unix timestamp
    pub delegations: Vec<Delegation>,
}

/// A single delegation to a validator
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Delegation {
    pub validator_address: String,
    pub validator_name: Option<String>,
    pub amount: String,
    pub rewards: String,
    pub shares: Option<String>,
}

/// Validator information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidatorInfo {
    pub address: String,
    pub name: String,
    pub description: Option<String>,
    pub website: Option<String>,
    pub commission: f64, // 0.0 to 1.0
    pub voting_power: String,
    pub status: ValidatorStatus,
    pub apr: Option<f64>,
    pub uptime: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ValidatorStatus {
    Active,
    Inactive,
    Jailed,
    Unbonding,
}

/// Staking transaction request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StakeRequest {
    pub chain: Chain,
    pub delegator_address: String,
    pub validator_address: String,
    pub amount: String,
    pub action: StakeAction,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum StakeAction {
    Delegate,
    Undelegate,
    Redelegate { new_validator: String },
    ClaimRewards,
    Compound,
}

// =============================================================================
// Public API
// =============================================================================

/// Get staking info for an address
pub fn get_staking_info(address: &str, chain: Chain) -> HawalaResult<StakingInfo> {
    match chain {
        Chain::Cosmos | Chain::Osmosis | Chain::Celestia | Chain::Kava
        | Chain::Akash | Chain::Stargaze | Chain::Juno | Chain::Neutron
        | Chain::Stride | Chain::Axelar | Chain::Injective | Chain::Sei => {
            get_cosmos_staking_info(address, chain)
        }
        Chain::Polkadot | Chain::Kusama => {
            get_substrate_staking_info(address, chain)
        }
        Chain::Solana | Chain::SolanaDevnet => {
            get_solana_staking_info(address, chain)
        }
        Chain::Ethereum | Chain::EthereumSepolia => {
            get_ethereum_staking_info(address, chain)
        }
        Chain::Cardano => {
            get_cardano_staking_info(address)
        }
        Chain::Near => {
            get_near_staking_info(address)
        }
        Chain::Tezos => {
            get_tezos_staking_info(address)
        }
        _ => Err(HawalaError::new(
            ErrorCode::NotImplemented,
            format!("Staking not supported for {:?}", chain),
        )),
    }
}

/// Get list of validators for a chain
pub fn get_validators(chain: Chain, limit: usize) -> HawalaResult<Vec<ValidatorInfo>> {
    match chain {
        Chain::Cosmos | Chain::Osmosis | Chain::Celestia => {
            get_cosmos_validators(chain, limit)
        }
        Chain::Polkadot | Chain::Kusama => {
            get_substrate_validators(chain, limit)
        }
        Chain::Solana | Chain::SolanaDevnet => {
            get_solana_validators(chain, limit)
        }
        _ => Err(HawalaError::new(
            ErrorCode::NotImplemented,
            format!("Validator list not supported for {:?}", chain),
        )),
    }
}

/// Prepare a staking transaction
pub fn prepare_stake_transaction(request: &StakeRequest) -> HawalaResult<String> {
    match request.chain {
        Chain::Cosmos | Chain::Osmosis => {
            prepare_cosmos_stake_tx(request)
        }
        Chain::Solana | Chain::SolanaDevnet => {
            prepare_solana_stake_tx(request)
        }
        _ => Err(HawalaError::new(
            ErrorCode::NotImplemented,
            format!("Staking transactions not supported for {:?}", request.chain),
        )),
    }
}

// =============================================================================
// Cosmos Staking
// =============================================================================

fn get_cosmos_staking_info(address: &str, chain: Chain) -> HawalaResult<StakingInfo> {
    let api_url = get_cosmos_api_url(chain);
    let client = create_client()?;
    
    // Get delegations
    let delegations_url = format!("{}/cosmos/staking/v1beta1/delegations/{}", api_url, address);
    let delegations = fetch_cosmos_delegations(&client, &delegations_url)?;
    
    // Get rewards
    let rewards_url = format!("{}/cosmos/distribution/v1beta1/delegators/{}/rewards", api_url, address);
    let rewards = fetch_cosmos_rewards(&client, &rewards_url)?;
    
    // Get unbonding
    let unbonding_url = format!("{}/cosmos/staking/v1beta1/delegators/{}/unbonding_delegations", api_url, address);
    let (unbonding_amount, unbonding_completion) = fetch_cosmos_unbonding(&client, &unbonding_url)?;
    
    // Calculate totals
    let total_staked: u128 = delegations.iter()
        .map(|d| d.amount.parse::<u128>().unwrap_or(0))
        .sum();
    
    let decimals = chain.decimals() as u32;
    let divisor = 10u128.pow(decimals);
    
    Ok(StakingInfo {
        chain,
        address: address.to_string(),
        staked_amount: format!("{:.6}", total_staked as f64 / divisor as f64),
        staked_raw: total_staked.to_string(),
        available_rewards: rewards,
        unbonding_amount,
        unbonding_completion,
        delegations,
    })
}

fn get_cosmos_api_url(chain: Chain) -> &'static str {
    match chain {
        Chain::Cosmos => "https://cosmos-rest.publicnode.com",
        Chain::Osmosis => "https://osmosis-rest.publicnode.com",
        Chain::Celestia => "https://celestia-rest.publicnode.com",
        Chain::Kava => "https://kava-rest.publicnode.com",
        Chain::Akash => "https://akash-rest.publicnode.com",
        Chain::Stargaze => "https://stargaze-rest.publicnode.com",
        Chain::Juno => "https://juno-rest.publicnode.com",
        Chain::Injective => "https://injective-rest.publicnode.com",
        Chain::Sei => "https://sei-rest.publicnode.com",
        Chain::Neutron => "https://neutron-rest.publicnode.com",
        Chain::Stride => "https://stride-rest.publicnode.com",
        Chain::Axelar => "https://axelar-rest.publicnode.com",
        _ => "https://cosmos-rest.publicnode.com",
    }
}

fn fetch_cosmos_delegations(client: &Client, url: &str) -> HawalaResult<Vec<Delegation>> {
    let resp: serde_json::Value = client.get(url)
        .timeout(Duration::from_secs(10))
        .send()
        .map_err(|e| HawalaError::network_error(e.to_string()))?
        .json()
        .map_err(|e| HawalaError::parse_error(e.to_string()))?;
    
    let delegation_responses = resp["delegation_responses"].as_array()
        .ok_or_else(|| HawalaError::parse_error("Missing delegation_responses"))?;
    
    let mut delegations = Vec::new();
    
    for d in delegation_responses {
        let delegation = &d["delegation"];
        let balance = &d["balance"];
        
        delegations.push(Delegation {
            validator_address: delegation["validator_address"].as_str().unwrap_or("").to_string(),
            validator_name: None,
            amount: balance["amount"].as_str().unwrap_or("0").to_string(),
            rewards: "0".to_string(),
            shares: delegation["shares"].as_str().map(|s| s.to_string()),
        });
    }
    
    Ok(delegations)
}

fn fetch_cosmos_rewards(client: &Client, url: &str) -> HawalaResult<String> {
    let resp: serde_json::Value = client.get(url)
        .timeout(Duration::from_secs(10))
        .send()
        .map_err(|e| HawalaError::network_error(e.to_string()))?
        .json()
        .map_err(|e| HawalaError::parse_error(e.to_string()))?;
    
    let total = resp["total"].as_array();
    if let Some(totals) = total {
        if let Some(first) = totals.first() {
            return Ok(first["amount"].as_str().unwrap_or("0").to_string());
        }
    }
    
    Ok("0".to_string())
}

fn fetch_cosmos_unbonding(client: &Client, url: &str) -> HawalaResult<(String, Option<u64>)> {
    let resp: serde_json::Value = client.get(url)
        .timeout(Duration::from_secs(10))
        .send()
        .map_err(|e| HawalaError::network_error(e.to_string()))?
        .json()
        .map_err(|e| HawalaError::parse_error(e.to_string()))?;
    
    let unbonding_responses = resp["unbonding_responses"].as_array();
    
    if let Some(responses) = unbonding_responses {
        let mut total_unbonding: u128 = 0;
        let earliest_completion: Option<u64> = None;
        
        for response in responses {
            if let Some(entries) = response["entries"].as_array() {
                for entry in entries {
                    if let Some(balance) = entry["balance"].as_str() {
                        total_unbonding += balance.parse::<u128>().unwrap_or(0);
                    }
                    // Parse completion time
                    if let Some(_completion_time) = entry["completion_time"].as_str() {
                        // Parse ISO 8601 timestamp (simplified)
                        // In production, use chrono or time crate
                    }
                }
            }
        }
        
        return Ok((total_unbonding.to_string(), earliest_completion));
    }
    
    Ok(("0".to_string(), None))
}

fn get_cosmos_validators(chain: Chain, limit: usize) -> HawalaResult<Vec<ValidatorInfo>> {
    let api_url = get_cosmos_api_url(chain);
    let client = create_client()?;
    
    let url = format!("{}/cosmos/staking/v1beta1/validators?status=BOND_STATUS_BONDED&pagination.limit={}", 
        api_url, limit);
    
    let resp: serde_json::Value = client.get(&url)
        .timeout(Duration::from_secs(15))
        .send()
        .map_err(|e| HawalaError::network_error(e.to_string()))?
        .json()
        .map_err(|e| HawalaError::parse_error(e.to_string()))?;
    
    let validators = resp["validators"].as_array()
        .ok_or_else(|| HawalaError::parse_error("Missing validators"))?;
    
    let mut result = Vec::new();
    
    for v in validators {
        let description = &v["description"];
        let commission = &v["commission"]["commission_rates"];
        
        let commission_rate = commission["rate"].as_str()
            .and_then(|r| r.parse::<f64>().ok())
            .unwrap_or(0.0);
        
        result.push(ValidatorInfo {
            address: v["operator_address"].as_str().unwrap_or("").to_string(),
            name: description["moniker"].as_str().unwrap_or("Unknown").to_string(),
            description: description["details"].as_str().map(|s| s.to_string()),
            website: description["website"].as_str().map(|s| s.to_string()),
            commission: commission_rate,
            voting_power: v["tokens"].as_str().unwrap_or("0").to_string(),
            status: ValidatorStatus::Active,
            apr: None,
            uptime: None,
        });
    }
    
    Ok(result)
}

fn prepare_cosmos_stake_tx(request: &StakeRequest) -> HawalaResult<String> {
    // Build Cosmos SDK MsgDelegate
    let msg = match &request.action {
        StakeAction::Delegate => {
            serde_json::json!({
                "@type": "/cosmos.staking.v1beta1.MsgDelegate",
                "delegator_address": request.delegator_address,
                "validator_address": request.validator_address,
                "amount": {
                    "denom": "uatom", // Would be dynamic based on chain
                    "amount": request.amount
                }
            })
        }
        StakeAction::Undelegate => {
            serde_json::json!({
                "@type": "/cosmos.staking.v1beta1.MsgUndelegate",
                "delegator_address": request.delegator_address,
                "validator_address": request.validator_address,
                "amount": {
                    "denom": "uatom",
                    "amount": request.amount
                }
            })
        }
        StakeAction::ClaimRewards => {
            serde_json::json!({
                "@type": "/cosmos.distribution.v1beta1.MsgWithdrawDelegatorReward",
                "delegator_address": request.delegator_address,
                "validator_address": request.validator_address
            })
        }
        _ => {
            return Err(HawalaError::new(
                ErrorCode::NotImplemented,
                "Stake action not yet implemented",
            ));
        }
    };
    
    Ok(msg.to_string())
}

// =============================================================================
// Substrate Staking (Polkadot/Kusama)
// =============================================================================

fn get_substrate_staking_info(address: &str, chain: Chain) -> HawalaResult<StakingInfo> {
    // Substrate uses nomination pools and direct staking
    Ok(StakingInfo {
        chain,
        address: address.to_string(),
        staked_amount: "0".to_string(),
        staked_raw: "0".to_string(),
        available_rewards: "0".to_string(),
        unbonding_amount: "0".to_string(),
        unbonding_completion: None,
        delegations: vec![],
    })
}

fn get_substrate_validators(_chain: Chain, _limit: usize) -> HawalaResult<Vec<ValidatorInfo>> {
    // Would query Substrate RPC for validator info
    Ok(vec![])
}

// =============================================================================
// Solana Staking
// =============================================================================

fn get_solana_staking_info(address: &str, chain: Chain) -> HawalaResult<StakingInfo> {
    let rpc_url = if chain == Chain::SolanaDevnet {
        "https://api.devnet.solana.com"
    } else {
        "https://api.mainnet-beta.solana.com"
    };
    
    let client = create_client()?;
    
    // Query stake accounts owned by this address
    let payload = serde_json::json!({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "getProgramAccounts",
        "params": [
            "Stake11111111111111111111111111111111111111",
            {
                "encoding": "jsonParsed",
                "filters": [
                    {
                        "memcmp": {
                            "offset": 12,  // Staker authority offset
                            "bytes": address
                        }
                    }
                ]
            }
        ]
    });
    
    let resp: serde_json::Value = client.post(rpc_url)
        .json(&payload)
        .timeout(Duration::from_secs(15))
        .send()
        .map_err(|e| HawalaError::network_error(e.to_string()))?
        .json()
        .map_err(|e| HawalaError::parse_error(e.to_string()))?;
    
    let mut delegations = Vec::new();
    let mut total_staked: u64 = 0;
    let total_rewards: u64 = 0;
    
    if let Some(accounts) = resp["result"].as_array() {
        for account in accounts {
            let pubkey = account["pubkey"].as_str().unwrap_or("");
            let parsed = &account["account"]["data"]["parsed"]["info"];
            
            // Get stake info
            let stake = &parsed["stake"];
            let delegation = &stake["delegation"];
            
            if let Some(lamports_str) = delegation["stake"].as_str() {
                if let Ok(lamports) = lamports_str.parse::<u64>() {
                    total_staked += lamports;
                    
                    let validator = delegation["voter"].as_str().unwrap_or("").to_string();
                    let warmup_lamports = delegation["warmupLamports"].as_str()
                        .and_then(|s| s.parse::<u64>().ok())
                        .unwrap_or(0);
                    
                    // Rewards are implicitly in the stake balance growth
                    // For accurate rewards, would need to track initial stake
                    
                    delegations.push(Delegation {
                        validator_address: validator.clone(),
                        validator_name: None, // Would need separate lookup
                        amount: lamports.to_string(),
                        rewards: warmup_lamports.to_string(),
                        shares: Some(pubkey.to_string()), // Store stake account address
                    });
                }
            }
        }
    }
    
    let decimals = 9u32; // Solana has 9 decimals
    let divisor = 10u64.pow(decimals);
    
    Ok(StakingInfo {
        chain,
        address: address.to_string(),
        staked_amount: format!("{:.9}", total_staked as f64 / divisor as f64),
        staked_raw: total_staked.to_string(),
        available_rewards: format!("{:.9}", total_rewards as f64 / divisor as f64),
        unbonding_amount: "0".to_string(), // Would need separate query for deactivating stakes
        unbonding_completion: None,
        delegations,
    })
}

fn get_solana_validators(chain: Chain, limit: usize) -> HawalaResult<Vec<ValidatorInfo>> {
    let rpc_url = if chain == Chain::SolanaDevnet {
        "https://api.devnet.solana.com"
    } else {
        "https://api.mainnet-beta.solana.com"
    };
    
    let client = create_client()?;
    
    let payload = serde_json::json!({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "getVoteAccounts"
    });
    
    let resp: serde_json::Value = client.post(rpc_url)
        .json(&payload)
        .timeout(Duration::from_secs(15))
        .send()
        .map_err(|e| HawalaError::network_error(e.to_string()))?
        .json()
        .map_err(|e| HawalaError::parse_error(e.to_string()))?;
    
    let current = resp["result"]["current"].as_array();
    
    if let Some(validators) = current {
        let mut result = Vec::new();
        
        for v in validators.iter().take(limit) {
            result.push(ValidatorInfo {
                address: v["votePubkey"].as_str().unwrap_or("").to_string(),
                name: v["nodePubkey"].as_str().unwrap_or("Unknown").to_string(),
                description: None,
                website: None,
                commission: v["commission"].as_f64().unwrap_or(0.0) / 100.0,
                voting_power: v["activatedStake"].as_u64().unwrap_or(0).to_string(),
                status: ValidatorStatus::Active,
                apr: None,
                uptime: None,
            });
        }
        
        return Ok(result);
    }
    
    Ok(vec![])
}

#[allow(deprecated)]
fn prepare_solana_stake_tx(request: &StakeRequest) -> HawalaResult<String> {
    use solana_sdk::{
        stake::instruction as stake_instruction,
        stake::state::{Authorized, Lockup},
        system_instruction,
        pubkey::Pubkey,
        signature::{Keypair, Signer},
    };
    use std::str::FromStr;
    
    // Parse addresses
    let delegator = Pubkey::from_str(&request.delegator_address)
        .map_err(|e| HawalaError::invalid_input(format!("Invalid delegator address: {}", e)))?;
    let validator = Pubkey::from_str(&request.validator_address)
        .map_err(|e| HawalaError::invalid_input(format!("Invalid validator address: {}", e)))?;
    
    // Parse amount as lamports
    let lamports: u64 = request.amount.parse()
        .map_err(|e| HawalaError::invalid_input(format!("Invalid amount: {}", e)))?;
    
    match &request.action {
        StakeAction::Delegate => {
            // Generate a new stake account keypair
            let stake_account = Keypair::new();
            let stake_pubkey = stake_account.pubkey();
            
            // Minimum stake account rent exemption (~2,282,880 lamports)
            let rent_exempt_reserve: u64 = 2_282_880;
            let total_lamports = lamports + rent_exempt_reserve;
            
            // Build instructions:
            // 1. Create stake account
            // 2. Initialize stake account with staker authority
            // 3. Delegate to validator
            
            let _create_account_ix = system_instruction::create_account(
                &delegator,
                &stake_pubkey,
                total_lamports,
                200, // Stake account size
                &solana_sdk::stake::program::id(),
            );
            
            let authorized = Authorized {
                staker: delegator,
                withdrawer: delegator,
            };
            
            let _initialize_ix = stake_instruction::initialize(
                &stake_pubkey,
                &authorized,
                &Lockup::default(),
            );
            
            let _delegate_ix = stake_instruction::delegate_stake(
                &stake_pubkey,
                &delegator,
                &validator,
            );
            
            // Return as JSON with instruction data for frontend to sign
            let instructions = serde_json::json!({
                "type": "solana_stake",
                "action": "delegate",
                "stake_account": stake_pubkey.to_string(),
                "stake_account_secret": bs58::encode(stake_account.to_bytes()).into_string(),
                "validator": request.validator_address,
                "lamports": lamports,
                "rent_exempt_reserve": rent_exempt_reserve,
                "total_lamports": total_lamports,
                "instructions": [
                    {
                        "program": "system",
                        "type": "create_account",
                        "from": request.delegator_address,
                        "to": stake_pubkey.to_string(),
                        "lamports": total_lamports,
                        "space": 200,
                        "owner": "Stake11111111111111111111111111111111111111"
                    },
                    {
                        "program": "stake",
                        "type": "initialize",
                        "stake_account": stake_pubkey.to_string(),
                        "staker": request.delegator_address,
                        "withdrawer": request.delegator_address,
                    },
                    {
                        "program": "stake",
                        "type": "delegate_stake",
                        "stake_account": stake_pubkey.to_string(),
                        "vote_account": request.validator_address,
                        "stake_authority": request.delegator_address,
                    }
                ]
            });
            
            Ok(instructions.to_string())
        }
        StakeAction::Undelegate => {
            // Deactivate stake - requires stake account address (passed as validator_address field)
            let stake_account = Pubkey::from_str(&request.validator_address)
                .map_err(|e| HawalaError::invalid_input(format!("Invalid stake account: {}", e)))?;
            
            let _deactivate_ix = stake_instruction::deactivate_stake(
                &stake_account,
                &delegator,
            );
            
            let instructions = serde_json::json!({
                "type": "solana_stake",
                "action": "deactivate",
                "stake_account": request.validator_address,
                "stake_authority": request.delegator_address,
                "instructions": [{
                    "program": "stake",
                    "type": "deactivate_stake",
                    "stake_account": request.validator_address,
                    "stake_authority": request.delegator_address,
                }]
            });
            
            Ok(instructions.to_string())
        }
        StakeAction::ClaimRewards => {
            // For Solana, rewards auto-compound. "Claiming" means withdrawing.
            // The stake account address is passed in validator_address
            let stake_account = Pubkey::from_str(&request.validator_address)
                .map_err(|e| HawalaError::invalid_input(format!("Invalid stake account: {}", e)))?;
            
            let _withdraw_ix = stake_instruction::withdraw(
                &stake_account,
                &delegator,  // Withdrawer
                &delegator,  // Recipient
                lamports,
                None,        // No custodian
            );
            
            let instructions = serde_json::json!({
                "type": "solana_stake",
                "action": "withdraw",
                "stake_account": request.validator_address,
                "recipient": request.delegator_address,
                "lamports": lamports,
                "instructions": [{
                    "program": "stake",
                    "type": "withdraw",
                    "stake_account": request.validator_address,
                    "withdrawer": request.delegator_address,
                    "recipient": request.delegator_address,
                    "lamports": lamports,
                }]
            });
            
            Ok(instructions.to_string())
        }
        StakeAction::Compound => {
            // Solana staking auto-compounds, nothing to do
            Ok(serde_json::json!({
                "type": "solana_stake",
                "action": "compound",
                "message": "Solana staking rewards auto-compound. No action needed."
            }).to_string())
        }
        StakeAction::Redelegate { new_validator } => {
            // Solana doesn't have native redelegate - must deactivate, wait, then redelegate
            let _new_validator_pk = Pubkey::from_str(new_validator)
                .map_err(|e| HawalaError::invalid_input(format!("Invalid new validator: {}", e)))?;
            
            let instructions = serde_json::json!({
                "type": "solana_stake",
                "action": "redelegate",
                "stake_account": request.validator_address,
                "old_validator": validator.to_string(),
                "new_validator": new_validator,
                "message": "Solana requires deactivation (~2 epochs) before redelegation. Use deactivate first."
            });
            
            Ok(instructions.to_string())
        }
    }
}

// =============================================================================
// Other Chains
// =============================================================================

fn get_ethereum_staking_info(address: &str, chain: Chain) -> HawalaResult<StakingInfo> {
    // ETH 2.0 staking info (would query beacon chain)
    Ok(StakingInfo {
        chain,
        address: address.to_string(),
        staked_amount: "0".to_string(),
        staked_raw: "0".to_string(),
        available_rewards: "0".to_string(),
        unbonding_amount: "0".to_string(),
        unbonding_completion: None,
        delegations: vec![],
    })
}

fn get_cardano_staking_info(address: &str) -> HawalaResult<StakingInfo> {
    Ok(StakingInfo {
        chain: Chain::Cardano,
        address: address.to_string(),
        staked_amount: "0".to_string(),
        staked_raw: "0".to_string(),
        available_rewards: "0".to_string(),
        unbonding_amount: "0".to_string(),
        unbonding_completion: None,
        delegations: vec![],
    })
}

fn get_near_staking_info(address: &str) -> HawalaResult<StakingInfo> {
    Ok(StakingInfo {
        chain: Chain::Near,
        address: address.to_string(),
        staked_amount: "0".to_string(),
        staked_raw: "0".to_string(),
        available_rewards: "0".to_string(),
        unbonding_amount: "0".to_string(),
        unbonding_completion: None,
        delegations: vec![],
    })
}

fn get_tezos_staking_info(address: &str) -> HawalaResult<StakingInfo> {
    Ok(StakingInfo {
        chain: Chain::Tezos,
        address: address.to_string(),
        staked_amount: "0".to_string(),
        staked_raw: "0".to_string(),
        available_rewards: "0".to_string(),
        unbonding_amount: "0".to_string(),
        unbonding_completion: None,
        delegations: vec![],
    })
}

// =============================================================================
// Helpers
// =============================================================================

fn create_client() -> HawalaResult<Client> {
    Client::builder()
        .timeout(Duration::from_secs(15))
        .connect_timeout(Duration::from_secs(10))
        .build()
        .map_err(|e| HawalaError::internal(format!("Failed to create client: {}", e)))
}
