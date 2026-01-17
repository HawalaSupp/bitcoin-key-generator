//! Shared types for Hawala Core
//!
//! All data structures that cross module boundaries are defined here
//! for consistent serialization and FFI compatibility.

use serde::{Deserialize, Serialize};

// =============================================================================
// Chain Types
// =============================================================================

/// Supported blockchain networks
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Chain {
    Bitcoin,
    BitcoinTestnet,
    Litecoin,
    Ethereum,
    EthereumSepolia,
    Bnb,
    Polygon,
    Arbitrum,
    Optimism,
    Base,
    Avalanche,
    Solana,
    SolanaDevnet,
    Xrp,
    XrpTestnet,
    Monero,
}

impl Chain {
    pub fn is_evm(&self) -> bool {
        matches!(
            self,
            Chain::Ethereum
                | Chain::EthereumSepolia
                | Chain::Bnb
                | Chain::Polygon
                | Chain::Arbitrum
                | Chain::Optimism
                | Chain::Base
                | Chain::Avalanche
        )
    }

    pub fn is_utxo(&self) -> bool {
        matches!(
            self,
            Chain::Bitcoin | Chain::BitcoinTestnet | Chain::Litecoin
        )
    }

    pub fn is_testnet(&self) -> bool {
        matches!(
            self,
            Chain::BitcoinTestnet | Chain::EthereumSepolia | Chain::SolanaDevnet | Chain::XrpTestnet
        )
    }

    pub fn chain_id(&self) -> Option<u64> {
        match self {
            Chain::Ethereum => Some(1),
            Chain::EthereumSepolia => Some(11155111),
            Chain::Bnb => Some(56),
            Chain::Polygon => Some(137),
            Chain::Arbitrum => Some(42161),
            Chain::Optimism => Some(10),
            Chain::Base => Some(8453),
            Chain::Avalanche => Some(43114),
            _ => None,
        }
    }

    pub fn symbol(&self) -> &'static str {
        match self {
            Chain::Bitcoin | Chain::BitcoinTestnet => "BTC",
            Chain::Litecoin => "LTC",
            Chain::Ethereum | Chain::EthereumSepolia => "ETH",
            Chain::Bnb => "BNB",
            Chain::Polygon => "MATIC",
            Chain::Arbitrum => "ETH",
            Chain::Optimism => "ETH",
            Chain::Base => "ETH",
            Chain::Avalanche => "AVAX",
            Chain::Solana | Chain::SolanaDevnet => "SOL",
            Chain::Xrp | Chain::XrpTestnet => "XRP",
            Chain::Monero => "XMR",
        }
    }

    pub fn decimals(&self) -> u8 {
        match self {
            Chain::Bitcoin | Chain::BitcoinTestnet | Chain::Litecoin => 8,
            Chain::Ethereum
            | Chain::EthereumSepolia
            | Chain::Bnb
            | Chain::Polygon
            | Chain::Arbitrum
            | Chain::Optimism
            | Chain::Base
            | Chain::Avalanche => 18,
            Chain::Solana | Chain::SolanaDevnet => 9,
            Chain::Xrp | Chain::XrpTestnet => 6,
            Chain::Monero => 12,
        }
    }

    /// Required confirmations for finality
    pub fn required_confirmations(&self) -> u32 {
        match self {
            Chain::Bitcoin | Chain::Litecoin => 6,
            Chain::BitcoinTestnet => 1,
            Chain::Ethereum | Chain::Bnb | Chain::Polygon => 12,
            Chain::EthereumSepolia => 1,
            Chain::Arbitrum | Chain::Optimism | Chain::Base | Chain::Avalanche => 1,
            Chain::Solana | Chain::SolanaDevnet => 1,
            Chain::Xrp | Chain::XrpTestnet => 1,
            Chain::Monero => 10,
        }
    }
}

impl std::str::FromStr for Chain {
    type Err = String;
    
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().replace("-", "_").as_str() {
            "bitcoin" | "btc" => Ok(Chain::Bitcoin),
            "bitcoin_testnet" | "btc_testnet" => Ok(Chain::BitcoinTestnet),
            "litecoin" | "ltc" => Ok(Chain::Litecoin),
            "ethereum" | "eth" => Ok(Chain::Ethereum),
            "ethereum_sepolia" | "sepolia" => Ok(Chain::EthereumSepolia),
            "bnb" | "bsc" | "binance" => Ok(Chain::Bnb),
            "polygon" | "matic" => Ok(Chain::Polygon),
            "arbitrum" | "arb" => Ok(Chain::Arbitrum),
            "optimism" | "op" => Ok(Chain::Optimism),
            "base" => Ok(Chain::Base),
            "avalanche" | "avax" => Ok(Chain::Avalanche),
            "solana" | "sol" => Ok(Chain::Solana),
            "solana_devnet" | "sol_devnet" => Ok(Chain::SolanaDevnet),
            "xrp" | "ripple" => Ok(Chain::Xrp),
            "xrp_testnet" => Ok(Chain::XrpTestnet),
            "monero" | "xmr" => Ok(Chain::Monero),
            _ => Err(format!("Unknown chain: {}", s)),
        }
    }
}

// =============================================================================
// Wallet Types
// =============================================================================

/// Generated keys for all supported chains
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AllKeys {
    pub bitcoin: BitcoinKeys,
    pub bitcoin_testnet: BitcoinKeys,
    pub litecoin: LitecoinKeys,
    pub monero: MoneroKeys,
    pub solana: SolanaKeys,
    pub ethereum: EthereumKeys,
    pub ethereum_sepolia: EthereumKeys,
    pub bnb: EvmKeys,
    pub xrp: XrpKeys,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BitcoinKeys {
    pub private_hex: String,
    pub private_wif: String,
    pub public_compressed_hex: String,
    pub address: String,
    pub taproot_address: Option<String>,
    pub x_only_pubkey: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LitecoinKeys {
    pub private_hex: String,
    pub private_wif: String,
    pub public_compressed_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MoneroKeys {
    pub private_spend_hex: String,
    pub private_view_hex: String,
    pub public_spend_hex: String,
    pub public_view_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SolanaKeys {
    pub private_seed_hex: String,
    pub private_key_base58: String,
    pub public_key_base58: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EthereumKeys {
    pub private_hex: String,
    pub public_uncompressed_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvmKeys {
    pub private_hex: String,
    pub public_uncompressed_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct XrpKeys {
    pub private_hex: String,
    pub public_compressed_hex: String,
    pub classic_address: String,
}

/// Wallet creation response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WalletResponse {
    pub mnemonic: String,
    pub keys: AllKeys,
}

// =============================================================================
// Transaction Types
// =============================================================================

/// UTXO for Bitcoin-like chains
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Utxo {
    pub txid: String,
    pub vout: u32,
    pub value: u64,
    pub script_pubkey: Option<String>,
    pub confirmed: bool,
    pub block_height: Option<u32>,
}

/// Universal transaction request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransactionRequest {
    pub chain: Chain,
    pub from: String,
    pub to: String,
    pub amount: String,
    pub private_key: String,
    
    // UTXO chains
    pub utxos: Option<Vec<Utxo>>,
    pub fee_rate: Option<u64>,
    
    // EVM chains
    pub nonce: Option<u64>,
    pub gas_limit: Option<u64>,
    pub gas_price: Option<String>,
    pub max_fee_per_gas: Option<String>,
    pub max_priority_fee_per_gas: Option<String>,
    pub data: Option<String>,
    
    // Solana
    pub recent_blockhash: Option<String>,
    
    // XRP
    pub sequence: Option<u32>,
    pub destination_tag: Option<u32>,
}

/// Signed transaction result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignedTransaction {
    pub chain: Chain,
    pub raw_tx: String,
    pub txid: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub estimated_fee: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size_bytes: Option<u32>,
}

/// Broadcast result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BroadcastResult {
    pub chain: Chain,
    pub txid: String,
    pub success: bool,
    pub error_message: Option<String>,
    pub explorer_url: Option<String>,
}

/// Transaction status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TransactionStatus {
    Pending,
    Confirming,
    Confirmed,
    Failed,
    Dropped,
}

/// Tracked transaction info
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackedTransaction {
    pub txid: String,
    pub chain: Chain,
    pub status: TransactionStatus,
    pub confirmations: u32,
    pub required_confirmations: u32,
    pub block_height: Option<u64>,
    pub timestamp: Option<u64>,
}

// =============================================================================
// Fee Types
// =============================================================================

/// Fee level presets
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeeLevel {
    pub label: String,
    pub rate: u64,           // sat/vB for BTC, gwei for EVM
    pub estimated_minutes: u32,
}

/// Bitcoin/UTXO fee estimates
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BitcoinFeeEstimate {
    pub fastest: FeeLevel,
    pub fast: FeeLevel,
    pub medium: FeeLevel,
    pub slow: FeeLevel,
    pub minimum: FeeLevel,
}

/// Litecoin fee estimates
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LitecoinFeeEstimate {
    pub fast: FeeLevel,
    pub medium: FeeLevel,
    pub slow: FeeLevel,
    pub mempool_congestion: i64,
}

/// Ethereum/EVM fee estimates
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvmFeeEstimate {
    pub base_fee: String,
    pub priority_fee_low: String,
    pub priority_fee_medium: String,
    pub priority_fee_high: String,
    pub gas_price_legacy: String,
    pub chain_id: u64,
}

/// Solana fee estimates
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SolanaFeeEstimate {
    pub base_fee_lamports: u64,
    pub priority_fee_low: u64,
    pub priority_fee_medium: u64,
    pub priority_fee_high: u64,
}

/// XRP fee estimates
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct XrpFeeEstimate {
    pub open_ledger_fee_drops: u64,
    pub minimum_fee_drops: u64,
    pub median_fee_drops: u64,
    pub current_queue_size: i64,
}

/// Universal fee estimate response
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum FeeEstimate {
    #[serde(rename = "bitcoin")]
    Bitcoin(BitcoinFeeEstimate),
    #[serde(rename = "litecoin")]
    Litecoin(LitecoinFeeEstimate),
    #[serde(rename = "evm")]
    Evm(EvmFeeEstimate),
    #[serde(rename = "solana")]
    Solana(SolanaFeeEstimate),
    #[serde(rename = "xrp")]
    Xrp(XrpFeeEstimate),
}

/// Gas estimation result for EVM chains
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GasEstimateResult {
    pub estimated_gas: u64,
    pub recommended_gas: u64,
    pub is_estimated: bool,
    pub error_message: Option<String>,
}

/// Common EVM transaction types for gas estimation
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EvmTransactionType {
    EthTransfer,
    Erc20Transfer,
    Erc20Approval,
    NftTransfer,
    ContractInteraction,
    Swap,
}

// =============================================================================
// History Types
// =============================================================================

/// Transaction history entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransactionEntry {
    pub txid: String,
    pub chain: Chain,
    pub direction: TransactionDirection,
    pub amount: String,
    pub fee: Option<String>,
    pub from: String,
    pub to: String,
    pub timestamp: Option<u64>,
    pub block_height: Option<u64>,
    pub confirmations: u32,
    pub status: TransactionStatus,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TransactionDirection {
    Incoming,
    Outgoing,
    Self_,
}

/// History fetch request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HistoryRequest {
    pub addresses: Vec<AddressWithChain>,
    pub limit: Option<u32>,
    pub offset: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AddressWithChain {
    pub address: String,
    pub chain: Chain,
}

// =============================================================================
// Balance Types
// =============================================================================

/// Balance for a single address
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Balance {
    pub chain: Chain,
    pub address: String,
    pub balance: String,
    pub balance_raw: String,
}

/// Multi-chain balance request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BalanceRequest {
    pub addresses: Vec<AddressWithChain>,
}

/// Multi-chain balance response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BalanceResponse {
    pub balances: Vec<Balance>,
}

// =============================================================================
// API Response Wrapper
// =============================================================================

/// Standard API response wrapper for FFI
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiResponse<T> {
    pub success: bool,
    pub data: Option<T>,
    pub error: Option<crate::error::HawalaError>,
}

impl<T> ApiResponse<T> {
    pub fn ok(data: T) -> Self {
        Self {
            success: true,
            data: Some(data),
            error: None,
        }
    }

    pub fn err(error: crate::error::HawalaError) -> Self {
        Self {
            success: false,
            data: None,
            error: Some(error),
        }
    }
}

impl<T: Serialize> ApiResponse<T> {
    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| {
            r#"{"success":false,"error":{"code":"internal","message":"Serialization failed"}}"#.to_string()
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_chain_properties() {
        assert!(Chain::Ethereum.is_evm());
        assert!(!Chain::Bitcoin.is_evm());
        assert!(Chain::Bitcoin.is_utxo());
        assert_eq!(Chain::Ethereum.chain_id(), Some(1));
        assert_eq!(Chain::Bitcoin.decimals(), 8);
        assert_eq!(Chain::Ethereum.decimals(), 18);
    }

    #[test]
    fn test_api_response_serialization() {
        let response = ApiResponse::ok("test_data".to_string());
        let json = response.to_json();
        assert!(json.contains("success"));
        assert!(json.contains("test_data"));
    }
}
