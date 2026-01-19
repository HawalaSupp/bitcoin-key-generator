//! Fee Estimator
//!
//! Fetches live fee estimates from various APIs.
//! Migrated from Swift FeeEstimationService.swift

use crate::error::{HawalaError, HawalaResult, ErrorCode};
use crate::types::*;
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;

// =============================================================================
// Public API
// =============================================================================

/// Get fee estimate for a chain
pub fn get_fee_estimate(chain: Chain) -> HawalaResult<FeeEstimate> {
    match chain {
        Chain::Bitcoin | Chain::BitcoinTestnet => get_bitcoin_fees(chain == Chain::BitcoinTestnet),
        Chain::Litecoin => get_litecoin_fees(),
        Chain::Ethereum | Chain::EthereumSepolia | Chain::Bnb | Chain::Polygon 
        | Chain::Arbitrum | Chain::Optimism | Chain::Base | Chain::Avalanche => {
            get_evm_fees(chain)
        }
        Chain::Solana | Chain::SolanaDevnet => get_solana_fees(chain == Chain::SolanaDevnet),
        Chain::Xrp | Chain::XrpTestnet => get_xrp_fees(chain == Chain::XrpTestnet),
        Chain::Monero => Err(HawalaError::new(
            ErrorCode::NotImplemented,
            "Monero fee estimation not yet supported",
        )),
        // EVM-compatible chains
        chain if chain.is_evm() => get_evm_fees(chain),
        // Default fallback
        _ => Err(HawalaError::new(
            ErrorCode::NotImplemented,
            format!("Fee estimation not yet supported for {:?}", chain),
        )),
    }
}

/// Estimate gas limit for an EVM transaction
pub fn estimate_gas_limit(
    chain_id: u64,
    from: &str,
    to: &str,
    value: &str,
    data: &str,
) -> HawalaResult<GasEstimateResult> {
    let endpoints = get_rpc_endpoints(chain_id);
    
    for endpoint in &endpoints {
        if let Ok(result) = estimate_gas_single(endpoint, from, to, value, data) {
            return Ok(result);
        }
    }
    
    // Return default for simple transfer
    Ok(GasEstimateResult {
        estimated_gas: 21000,
        recommended_gas: 25200, // 20% buffer
        is_estimated: false,
        error_message: Some("Failed to estimate, using default".to_string()),
    })
}

/// Get current gas price for an EVM chain
pub fn get_gas_price(chain_id: u64) -> HawalaResult<u64> {
    let endpoints = get_rpc_endpoints(chain_id);
    
    for endpoint in &endpoints {
        if let Ok(price) = get_gas_price_single(endpoint) {
            return Ok(price);
        }
    }
    
    Err(HawalaError::network_error("Failed to fetch gas price from all endpoints"))
}

/// Get base fee for EIP-1559 chains
pub fn get_base_fee(chain_id: u64) -> HawalaResult<u64> {
    // BSC doesn't use EIP-1559
    if chain_id == 56 {
        return Ok(3_000_000_000); // 3 Gwei
    }
    
    let endpoints = get_rpc_endpoints(chain_id);
    
    for endpoint in &endpoints {
        if let Ok(fee) = get_base_fee_single(endpoint) {
            return Ok(fee);
        }
    }
    
    Err(HawalaError::network_error("Failed to fetch base fee from all endpoints"))
}

/// Recommended gas limit for common transaction types
pub fn recommended_gas_limit(tx_type: EvmTransactionType) -> u64 {
    match tx_type {
        EvmTransactionType::EthTransfer => 21000,
        EvmTransactionType::Erc20Transfer => 65000,
        EvmTransactionType::Erc20Approval => 50000,
        EvmTransactionType::NftTransfer => 100000,
        EvmTransactionType::ContractInteraction => 150000,
        EvmTransactionType::Swap => 250000,
    }
}

// =============================================================================
// Bitcoin Fee Estimation (mempool.space)
// =============================================================================

fn get_bitcoin_fees(testnet: bool) -> HawalaResult<FeeEstimate> {
    let base_url = if testnet {
        "https://mempool.space/testnet/api"
    } else {
        "https://mempool.space/api"
    };
    
    let url = format!("{}/v1/fees/recommended", base_url);
    let client = create_client()?;
    
    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct MempoolFees {
        fastest_fee: u64,
        half_hour_fee: u64,
        hour_fee: u64,
        economy_fee: u64,
        minimum_fee: u64,
    }
    
    let response: MempoolFees = client.get(&url)
        .header("User-Agent", "HawalaApp/1.0")
        .send()
        .map_err(|e| HawalaError::network_error(format!("Mempool request failed: {}", e)))?
        .json()
        .map_err(|e| HawalaError::parse_error(format!("Failed to parse fees: {}", e)))?;
    
    Ok(FeeEstimate::Bitcoin(BitcoinFeeEstimate {
        fastest: FeeLevel {
            label: "Fastest (~10 min)".to_string(),
            rate: response.fastest_fee,
            estimated_minutes: 10,
        },
        fast: FeeLevel {
            label: "Fast (~30 min)".to_string(),
            rate: response.half_hour_fee,
            estimated_minutes: 30,
        },
        medium: FeeLevel {
            label: "Medium (~1 hour)".to_string(),
            rate: response.hour_fee,
            estimated_minutes: 60,
        },
        slow: FeeLevel {
            label: "Economy (~2 hours)".to_string(),
            rate: response.economy_fee,
            estimated_minutes: 120,
        },
        minimum: FeeLevel {
            label: "Minimum".to_string(),
            rate: response.minimum_fee,
            estimated_minutes: 1440,
        },
    }))
}

// =============================================================================
// Litecoin Fee Estimation (Blockchair)
// =============================================================================

fn get_litecoin_fees() -> HawalaResult<FeeEstimate> {
    let client = create_client()?;
    let url = "https://api.blockchair.com/litecoin/stats";
    
    #[derive(Deserialize)]
    struct BlockchairResponse {
        data: BlockchairData,
    }
    
    #[derive(Deserialize)]
    struct BlockchairData {
        suggested_transaction_fee_per_byte_sat: Option<i64>,
        mempool_transactions: Option<i64>,
    }
    
    let result = client.get(url)
        .header("User-Agent", "HawalaApp/1.0")
        .send()
        .and_then(|r| r.json::<BlockchairResponse>());
    
    let (base_fee, congestion) = match result {
        Ok(resp) => {
            let suggested = resp.data.suggested_transaction_fee_per_byte_sat.unwrap_or(10) as f64;
            let mempool = resp.data.mempool_transactions.unwrap_or(0);
            let multiplier = if mempool > 10000 { 1.5 } else if mempool > 5000 { 1.2 } else { 1.0 };
            (suggested * multiplier, mempool)
        }
        Err(_) => (10.0, 0), // Default fallback
    };
    
    Ok(FeeEstimate::Litecoin(LitecoinFeeEstimate {
        fast: FeeLevel {
            label: "Fast (~10 min)".to_string(),
            rate: (base_fee * 2.0) as u64,
            estimated_minutes: 10,
        },
        medium: FeeLevel {
            label: "Medium (~30 min)".to_string(),
            rate: base_fee as u64,
            estimated_minutes: 30,
        },
        slow: FeeLevel {
            label: "Slow (~2 hours)".to_string(),
            rate: std::cmp::max(1, (base_fee * 0.5) as u64),
            estimated_minutes: 120,
        },
        mempool_congestion: congestion,
    }))
}

// =============================================================================
// EVM Fee Estimation (RPC + Etherscan)
// =============================================================================

fn get_evm_fees(chain: Chain) -> HawalaResult<FeeEstimate> {
    let chain_id = chain.chain_id().unwrap_or(1);
    
    // Try to get live gas price first
    let gas_price = get_gas_price(chain_id).unwrap_or(30_000_000_000u64); // 30 Gwei fallback
    let base_fee = get_base_fee(chain_id).unwrap_or(gas_price / 2);
    
    // Calculate priority fees based on network
    let (priority_low, priority_med, priority_high): (u64, u64, u64) = match chain_id {
        1 | 11155111 => (1_000_000_000, 2_000_000_000, 5_000_000_000), // ETH: 1, 2, 5 Gwei
        56 => (1_000_000_000, 1_000_000_000, 2_000_000_000),           // BNB: 1, 1, 2 Gwei
        137 => (30_000_000_000, 50_000_000_000, 100_000_000_000),      // Polygon: 30, 50, 100 Gwei
        42161 | 10 | 8453 => (100_000_000, 100_000_000, 200_000_000),  // L2s: 0.1, 0.1, 0.2 Gwei
        43114 => (1_000_000_000, 2_000_000_000, 5_000_000_000),        // AVAX: 1, 2, 5 Gwei
        _ => (1_000_000_000, 2_000_000_000, 5_000_000_000),
    };
    
    Ok(FeeEstimate::Evm(EvmFeeEstimate {
        base_fee: base_fee.to_string(),
        priority_fee_low: priority_low.to_string(),
        priority_fee_medium: priority_med.to_string(),
        priority_fee_high: priority_high.to_string(),
        gas_price_legacy: gas_price.to_string(),
        chain_id,
    }))
}

fn estimate_gas_single(
    rpc_url: &str,
    from: &str,
    to: &str,
    value: &str,
    data: &str,
) -> HawalaResult<GasEstimateResult> {
    let client = create_client()?;
    
    #[derive(Serialize)]
    struct EstimateGasParams<'a> {
        from: &'a str,
        to: &'a str,
        value: &'a str,
        data: &'a str,
    }
    
    #[derive(Serialize)]
    struct RpcRequest<'a> {
        jsonrpc: &'static str,
        method: &'static str,
        params: Vec<EstimateGasParams<'a>>,
        id: u32,
    }
    
    #[derive(Deserialize)]
    struct RpcResponse {
        result: Option<String>,
        error: Option<RpcError>,
    }
    
    #[derive(Deserialize)]
    struct RpcError {
        message: String,
    }
    
    let response = client
        .post(rpc_url)
        .header("Content-Type", "application/json")
        .json(&RpcRequest {
            jsonrpc: "2.0",
            method: "eth_estimateGas",
            params: vec![EstimateGasParams { from, to, value, data }],
            id: 1,
        })
        .send()
        .map_err(|e| HawalaError::network_error(e.to_string()))?;
    
    let result: RpcResponse = response.json()
        .map_err(|e| HawalaError::parse_error(e.to_string()))?;
    
    if let Some(error) = result.error {
        return Ok(GasEstimateResult {
            estimated_gas: 21000,
            recommended_gas: 25200,
            is_estimated: false,
            error_message: Some(error.message),
        });
    }
    
    if let Some(hex_gas) = result.result {
        let gas = parse_hex_u64(&hex_gas)?;
        let buffered = (gas as f64 * 1.2) as u64;
        
        return Ok(GasEstimateResult {
            estimated_gas: gas,
            recommended_gas: buffered,
            is_estimated: true,
            error_message: None,
        });
    }
    
    Err(HawalaError::parse_error("No result in response"))
}

fn get_gas_price_single(rpc_url: &str) -> HawalaResult<u64> {
    let client = create_client()?;
    
    #[derive(Serialize)]
    struct RpcRequest {
        jsonrpc: &'static str,
        method: &'static str,
        params: Vec<()>,
        id: u32,
    }
    
    #[derive(Deserialize)]
    struct RpcResponse {
        result: Option<String>,
    }
    
    let response = client
        .post(rpc_url)
        .header("Content-Type", "application/json")
        .json(&RpcRequest {
            jsonrpc: "2.0",
            method: "eth_gasPrice",
            params: vec![],
            id: 1,
        })
        .send()
        .map_err(|e| HawalaError::network_error(e.to_string()))?;
    
    let result: RpcResponse = response.json()
        .map_err(|e| HawalaError::parse_error(e.to_string()))?;
    
    result.result
        .ok_or_else(|| HawalaError::parse_error("No gas price in response"))
        .and_then(|hex| parse_hex_u64(&hex))
}

fn get_base_fee_single(rpc_url: &str) -> HawalaResult<u64> {
    let client = create_client()?;
    
    #[derive(Serialize)]
    struct RpcRequest {
        jsonrpc: &'static str,
        method: &'static str,
        params: (&'static str, bool),
        id: u32,
    }
    
    #[derive(Deserialize)]
    struct RpcResponse {
        result: Option<BlockResult>,
    }
    
    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct BlockResult {
        base_fee_per_gas: Option<String>,
    }
    
    let response = client
        .post(rpc_url)
        .header("Content-Type", "application/json")
        .json(&RpcRequest {
            jsonrpc: "2.0",
            method: "eth_getBlockByNumber",
            params: ("latest", false),
            id: 1,
        })
        .send()
        .map_err(|e| HawalaError::network_error(e.to_string()))?;
    
    let result: RpcResponse = response.json()
        .map_err(|e| HawalaError::parse_error(e.to_string()))?;
    
    result.result
        .and_then(|b| b.base_fee_per_gas)
        .ok_or_else(|| HawalaError::parse_error("No baseFeePerGas in block"))
        .and_then(|hex| parse_hex_u64(&hex))
}

// =============================================================================
// Solana Fee Estimation
// =============================================================================

fn get_solana_fees(devnet: bool) -> HawalaResult<FeeEstimate> {
    let rpc_url = if devnet {
        "https://api.devnet.solana.com"
    } else {
        "https://api.mainnet-beta.solana.com"
    };
    
    let client = create_client()?;
    
    #[derive(Serialize)]
    struct RpcRequest {
        jsonrpc: &'static str,
        id: u32,
        method: &'static str,
        params: Vec<Vec<String>>,
    }
    
    #[derive(Deserialize)]
    struct RpcResponse {
        result: Option<Vec<PriorityFeeResult>>,
    }
    
    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct PriorityFeeResult {
        prioritization_fee: u64,
    }
    
    let result = client
        .post(rpc_url)
        .header("Content-Type", "application/json")
        .json(&RpcRequest {
            jsonrpc: "2.0",
            id: 1,
            method: "getRecentPrioritizationFees",
            params: vec![vec![]],
        })
        .send()
        .and_then(|r| r.json::<RpcResponse>());
    
    let (avg_fee, max_fee) = match result {
        Ok(resp) => {
            if let Some(fees) = resp.result {
                let values: Vec<u64> = fees.iter().map(|f| f.prioritization_fee).collect();
                let avg = if values.is_empty() { 0 } else { values.iter().sum::<u64>() / values.len() as u64 };
                let max = values.iter().max().copied().unwrap_or(0);
                (avg, max)
            } else {
                (0, 0)
            }
        }
        Err(_) => (10000, 100000), // Fallback
    };
    
    Ok(FeeEstimate::Solana(SolanaFeeEstimate {
        base_fee_lamports: 5000, // Fixed base fee
        priority_fee_low: std::cmp::max(1000, avg_fee / 2),
        priority_fee_medium: std::cmp::max(10000, avg_fee),
        priority_fee_high: std::cmp::max(100000, std::cmp::max(avg_fee * 2, max_fee)),
    }))
}

// =============================================================================
// XRP Fee Estimation
// =============================================================================

fn get_xrp_fees(testnet: bool) -> HawalaResult<FeeEstimate> {
    let rpc_url = if testnet {
        "https://s.altnet.rippletest.net:51234"
    } else {
        "https://s1.ripple.com:51234"
    };
    
    let client = create_client()?;
    
    #[derive(Serialize)]
    struct RpcRequest {
        method: &'static str,
        params: Vec<serde_json::Value>,
    }
    
    #[derive(Deserialize)]
    struct RpcResponse {
        result: Option<FeeResult>,
    }
    
    #[derive(Deserialize)]
    struct FeeResult {
        drops: Option<DropsFees>,
        current_queue_size: Option<i64>,
    }
    
    #[derive(Deserialize)]
    struct DropsFees {
        open_ledger_fee: Option<String>,
        minimum_fee: Option<String>,
        median_fee: Option<String>,
    }
    
    let result = client
        .post(rpc_url)
        .header("Content-Type", "application/json")
        .json(&RpcRequest {
            method: "fee",
            params: vec![serde_json::json!({})],
        })
        .send()
        .and_then(|r| r.json::<RpcResponse>());
    
    let (open_ledger, minimum, median, queue) = match result {
        Ok(resp) => {
            if let Some(fee_result) = resp.result {
                let drops = fee_result.drops.unwrap_or(DropsFees {
                    open_ledger_fee: Some("12".to_string()),
                    minimum_fee: Some("10".to_string()),
                    median_fee: Some("12".to_string()),
                });
                (
                    drops.open_ledger_fee.and_then(|s| s.parse().ok()).unwrap_or(12),
                    drops.minimum_fee.and_then(|s| s.parse().ok()).unwrap_or(10),
                    drops.median_fee.and_then(|s| s.parse().ok()).unwrap_or(12),
                    fee_result.current_queue_size.unwrap_or(0),
                )
            } else {
                (12, 10, 12, 0)
            }
        }
        Err(_) => (12, 10, 12, 0), // Fallback
    };
    
    Ok(FeeEstimate::Xrp(XrpFeeEstimate {
        open_ledger_fee_drops: open_ledger,
        minimum_fee_drops: minimum,
        median_fee_drops: median,
        current_queue_size: queue,
    }))
}

// =============================================================================
// Helper Functions
// =============================================================================

fn create_client() -> HawalaResult<Client> {
    Client::builder()
        .timeout(Duration::from_secs(10))
        .connect_timeout(Duration::from_secs(5))
        .build()
        .map_err(|e| HawalaError::internal(format!("Failed to create HTTP client: {}", e)))
}

fn get_rpc_endpoints(chain_id: u64) -> Vec<&'static str> {
    match chain_id {
        1 => vec![
            "https://eth.llamarpc.com",
            "https://ethereum.publicnode.com",
            "https://rpc.ankr.com/eth",
        ],
        11155111 => vec![
            "https://ethereum-sepolia-rpc.publicnode.com",
            "https://sepolia.drpc.org",
        ],
        56 => vec![
            "https://bsc-dataseed.binance.org",
            "https://bsc-dataseed1.defibit.io",
        ],
        137 => vec![
            "https://polygon-rpc.com",
            "https://rpc.ankr.com/polygon",
        ],
        42161 => vec![
            "https://arb1.arbitrum.io/rpc",
            "https://arbitrum.llamarpc.com",
        ],
        10 => vec![
            "https://mainnet.optimism.io",
            "https://optimism.llamarpc.com",
        ],
        8453 => vec![
            "https://mainnet.base.org",
            "https://base.llamarpc.com",
        ],
        43114 => vec![
            "https://api.avax.network/ext/bc/C/rpc",
            "https://avalanche.llamarpc.com",
        ],
        _ => vec!["https://eth.llamarpc.com"],
    }
}

fn parse_hex_u64(hex: &str) -> HawalaResult<u64> {
    let clean = hex.trim_start_matches("0x");
    u64::from_str_radix(clean, 16)
        .map_err(|e| HawalaError::parse_error(format!("Invalid hex: {}", e)))
}

// =============================================================================
// Fee Calculation Utilities
// =============================================================================

/// Calculate estimated Bitcoin transaction fee in satoshis
pub fn calculate_bitcoin_fee(inputs: usize, outputs: usize, sat_per_vbyte: u64) -> u64 {
    // P2WPKH: ~68 vbytes per input, ~31 vbytes per output, ~10 vbytes overhead
    let vbytes = (inputs * 68) + (outputs * 31) + 10;
    (vbytes as u64) * sat_per_vbyte
}

/// Calculate estimated Ethereum transaction fee in wei
pub fn calculate_ethereum_fee(gas_limit: u64, gas_price_wei: u64) -> u64 {
    gas_limit.saturating_mul(gas_price_wei)
}

/// Calculate estimated EIP-1559 fee in wei
pub fn calculate_eip1559_fee(gas_limit: u64, base_fee_wei: u64, priority_fee_wei: u64) -> u64 {
    gas_limit.saturating_mul(base_fee_wei.saturating_add(priority_fee_wei))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bitcoin_fee_calculation() {
        // 1 input, 2 outputs, 10 sat/vB
        let fee = calculate_bitcoin_fee(1, 2, 10);
        // (1*68) + (2*31) + 10 = 140 vbytes * 10 = 1400 sats
        assert_eq!(fee, 1400);
    }

    #[test]
    fn test_recommended_gas_limits() {
        assert_eq!(recommended_gas_limit(EvmTransactionType::EthTransfer), 21000);
        assert_eq!(recommended_gas_limit(EvmTransactionType::Erc20Transfer), 65000);
        assert_eq!(recommended_gas_limit(EvmTransactionType::Swap), 250000);
    }

    #[test]
    fn test_parse_hex() {
        assert_eq!(parse_hex_u64("0x5208").unwrap(), 21000);
        assert_eq!(parse_hex_u64("5208").unwrap(), 21000);
    }
}
