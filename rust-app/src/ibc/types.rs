//! IBC Types and Data Structures
//!
//! Core types for IBC transfers including chains, channels, denominations, and messages.

use serde::{Deserialize, Serialize};

/// Supported Cosmos SDK chains for IBC
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum IBCChain {
    CosmosHub,
    Osmosis,
    Juno,
    Stargaze,
    Akash,
    Stride,
    Celestia,
    Dymension,
    Neutron,
    Injective,
    Sei,
    Noble,
    Kujira,
    Terra,
    Secret,
    Axelar,
    Evmos,
    Persistence,
    Agoric,
    Crescent,
}

impl IBCChain {
    /// Get the chain ID
    pub fn chain_id(&self) -> &'static str {
        match self {
            IBCChain::CosmosHub => "cosmoshub-4",
            IBCChain::Osmosis => "osmosis-1",
            IBCChain::Juno => "juno-1",
            IBCChain::Stargaze => "stargaze-1",
            IBCChain::Akash => "akashnet-2",
            IBCChain::Stride => "stride-1",
            IBCChain::Celestia => "celestia",
            IBCChain::Dymension => "dymension_1100-1",
            IBCChain::Neutron => "neutron-1",
            IBCChain::Injective => "injective-1",
            IBCChain::Sei => "pacific-1",
            IBCChain::Noble => "noble-1",
            IBCChain::Kujira => "kaiyo-1",
            IBCChain::Terra => "phoenix-1",
            IBCChain::Secret => "secret-4",
            IBCChain::Axelar => "axelar-dojo-1",
            IBCChain::Evmos => "evmos_9001-2",
            IBCChain::Persistence => "core-1",
            IBCChain::Agoric => "agoric-3",
            IBCChain::Crescent => "crescent-1",
        }
    }

    /// Get the native denomination
    pub fn native_denom(&self) -> &'static str {
        match self {
            IBCChain::CosmosHub => "uatom",
            IBCChain::Osmosis => "uosmo",
            IBCChain::Juno => "ujuno",
            IBCChain::Stargaze => "ustars",
            IBCChain::Akash => "uakt",
            IBCChain::Stride => "ustrd",
            IBCChain::Celestia => "utia",
            IBCChain::Dymension => "adym",
            IBCChain::Neutron => "untrn",
            IBCChain::Injective => "inj",
            IBCChain::Sei => "usei",
            IBCChain::Noble => "uusdc",
            IBCChain::Kujira => "ukuji",
            IBCChain::Terra => "uluna",
            IBCChain::Secret => "uscrt",
            IBCChain::Axelar => "uaxl",
            IBCChain::Evmos => "aevmos",
            IBCChain::Persistence => "uxprt",
            IBCChain::Agoric => "ubld",
            IBCChain::Crescent => "ucre",
        }
    }

    /// Get display name
    pub fn display_name(&self) -> &'static str {
        match self {
            IBCChain::CosmosHub => "Cosmos Hub",
            IBCChain::Osmosis => "Osmosis",
            IBCChain::Juno => "Juno",
            IBCChain::Stargaze => "Stargaze",
            IBCChain::Akash => "Akash",
            IBCChain::Stride => "Stride",
            IBCChain::Celestia => "Celestia",
            IBCChain::Dymension => "Dymension",
            IBCChain::Neutron => "Neutron",
            IBCChain::Injective => "Injective",
            IBCChain::Sei => "Sei",
            IBCChain::Noble => "Noble",
            IBCChain::Kujira => "Kujira",
            IBCChain::Terra => "Terra",
            IBCChain::Secret => "Secret Network",
            IBCChain::Axelar => "Axelar",
            IBCChain::Evmos => "Evmos",
            IBCChain::Persistence => "Persistence",
            IBCChain::Agoric => "Agoric",
            IBCChain::Crescent => "Crescent",
        }
    }

    /// Get Bech32 address prefix
    pub fn bech32_prefix(&self) -> &'static str {
        match self {
            IBCChain::CosmosHub => "cosmos",
            IBCChain::Osmosis => "osmo",
            IBCChain::Juno => "juno",
            IBCChain::Stargaze => "stars",
            IBCChain::Akash => "akash",
            IBCChain::Stride => "stride",
            IBCChain::Celestia => "celestia",
            IBCChain::Dymension => "dym",
            IBCChain::Neutron => "neutron",
            IBCChain::Injective => "inj",
            IBCChain::Sei => "sei",
            IBCChain::Noble => "noble",
            IBCChain::Kujira => "kujira",
            IBCChain::Terra => "terra",
            IBCChain::Secret => "secret",
            IBCChain::Axelar => "axelar",
            IBCChain::Evmos => "evmos",
            IBCChain::Persistence => "persistence",
            IBCChain::Agoric => "agoric",
            IBCChain::Crescent => "cre",
        }
    }

    /// Get RPC endpoint
    pub fn rpc_endpoint(&self) -> &'static str {
        match self {
            IBCChain::CosmosHub => "https://cosmos-rpc.polkachu.com",
            IBCChain::Osmosis => "https://osmosis-rpc.polkachu.com",
            IBCChain::Juno => "https://juno-rpc.polkachu.com",
            IBCChain::Stargaze => "https://stargaze-rpc.polkachu.com",
            IBCChain::Akash => "https://akash-rpc.polkachu.com",
            IBCChain::Stride => "https://stride-rpc.polkachu.com",
            IBCChain::Celestia => "https://celestia-rpc.polkachu.com",
            IBCChain::Dymension => "https://dymension-rpc.polkachu.com",
            IBCChain::Neutron => "https://neutron-rpc.polkachu.com",
            IBCChain::Injective => "https://injective-rpc.polkachu.com",
            IBCChain::Sei => "https://sei-rpc.polkachu.com",
            IBCChain::Noble => "https://noble-rpc.polkachu.com",
            IBCChain::Kujira => "https://kujira-rpc.polkachu.com",
            IBCChain::Terra => "https://terra-rpc.polkachu.com",
            IBCChain::Secret => "https://secret-rpc.polkachu.com",
            IBCChain::Axelar => "https://axelar-rpc.polkachu.com",
            IBCChain::Evmos => "https://evmos-rpc.polkachu.com",
            IBCChain::Persistence => "https://persistence-rpc.polkachu.com",
            IBCChain::Agoric => "https://agoric-rpc.polkachu.com",
            IBCChain::Crescent => "https://crescent-rpc.polkachu.com",
        }
    }

    /// Get REST API endpoint
    pub fn rest_endpoint(&self) -> &'static str {
        match self {
            IBCChain::CosmosHub => "https://cosmos-api.polkachu.com",
            IBCChain::Osmosis => "https://osmosis-api.polkachu.com",
            IBCChain::Juno => "https://juno-api.polkachu.com",
            IBCChain::Stargaze => "https://stargaze-api.polkachu.com",
            IBCChain::Akash => "https://akash-api.polkachu.com",
            IBCChain::Stride => "https://stride-api.polkachu.com",
            IBCChain::Celestia => "https://celestia-api.polkachu.com",
            IBCChain::Dymension => "https://dymension-api.polkachu.com",
            IBCChain::Neutron => "https://neutron-api.polkachu.com",
            IBCChain::Injective => "https://injective-api.polkachu.com",
            IBCChain::Sei => "https://sei-api.polkachu.com",
            IBCChain::Noble => "https://noble-api.polkachu.com",
            IBCChain::Kujira => "https://kujira-api.polkachu.com",
            IBCChain::Terra => "https://terra-api.polkachu.com",
            IBCChain::Secret => "https://secret-api.polkachu.com",
            IBCChain::Axelar => "https://axelar-api.polkachu.com",
            IBCChain::Evmos => "https://evmos-api.polkachu.com",
            IBCChain::Persistence => "https://persistence-api.polkachu.com",
            IBCChain::Agoric => "https://agoric-api.polkachu.com",
            IBCChain::Crescent => "https://crescent-api.polkachu.com",
        }
    }

    /// Get all supported chains
    pub fn all() -> Vec<IBCChain> {
        vec![
            IBCChain::CosmosHub,
            IBCChain::Osmosis,
            IBCChain::Juno,
            IBCChain::Stargaze,
            IBCChain::Akash,
            IBCChain::Stride,
            IBCChain::Celestia,
            IBCChain::Dymension,
            IBCChain::Neutron,
            IBCChain::Injective,
            IBCChain::Sei,
            IBCChain::Noble,
            IBCChain::Kujira,
            IBCChain::Terra,
            IBCChain::Secret,
            IBCChain::Axelar,
            IBCChain::Evmos,
            IBCChain::Persistence,
            IBCChain::Agoric,
            IBCChain::Crescent,
        ]
    }
}

/// IBC Channel information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IBCChannel {
    /// Source channel ID (e.g., "channel-0")
    pub channel_id: String,
    /// Source port ID (usually "transfer")
    pub port_id: String,
    /// Counterparty channel ID
    pub counterparty_channel_id: String,
    /// Counterparty port ID
    pub counterparty_port_id: String,
    /// Channel state
    pub state: ChannelState,
    /// Connection ID
    pub connection_id: String,
    /// Ordering (UNORDERED for transfer)
    pub ordering: ChannelOrdering,
    /// Version
    pub version: String,
}

/// IBC Channel state
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ChannelState {
    Init,
    TryOpen,
    Open,
    Closed,
}

/// IBC Channel ordering
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ChannelOrdering {
    Ordered,
    Unordered,
}

/// IBC Path representing a route between chains
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IBCPath {
    pub source_chain: IBCChain,
    pub destination_chain: IBCChain,
    pub channel: IBCChannel,
    /// Token denom on source chain
    pub source_denom: String,
    /// Token denom on destination chain (IBC denom)
    pub destination_denom: String,
}

/// IBC Token denomination
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IBCDenom {
    /// Full IBC denom (e.g., "ibc/27394FB092D2ECCD56123C74F36E4C1F926001CEADA9CA97EA622B25F41E5EB2")
    pub ibc_denom: String,
    /// Base denom (e.g., "uatom")
    pub base_denom: String,
    /// Path trace (e.g., "transfer/channel-0")
    pub path: String,
    /// Human-readable name
    pub display_name: String,
    /// Decimals
    pub decimals: u8,
}

impl IBCDenom {
    /// Create a new IBC denom from path and base
    pub fn new(path: &str, base_denom: &str) -> Self {
        let hash_input = format!("{}/{}", path, base_denom);
        let hash = sha256_hex(&hash_input);
        
        Self {
            ibc_denom: format!("ibc/{}", hash.to_uppercase()),
            base_denom: base_denom.to_string(),
            path: path.to_string(),
            display_name: base_denom.trim_start_matches('u').to_uppercase(),
            decimals: 6,
        }
    }

    /// Check if this is a native denom (not IBC)
    pub fn is_native(&self) -> bool {
        !self.ibc_denom.starts_with("ibc/")
    }
}

/// Simple SHA256 hex implementation for IBC denom calculation
fn sha256_hex(input: &str) -> String {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    
    // Simplified hash for demo - in production use proper SHA256
    let mut hasher = DefaultHasher::new();
    input.hash(&mut hasher);
    let hash = hasher.finish();
    format!("{:016X}{:016X}{:016X}{:016X}", hash, hash.rotate_left(16), hash.rotate_left(32), hash.rotate_left(48))
}

/// MsgTransfer - IBC token transfer message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MsgTransfer {
    /// Source port (usually "transfer")
    pub source_port: String,
    /// Source channel
    pub source_channel: String,
    /// Token being transferred
    pub token: Coin,
    /// Sender address on source chain
    pub sender: String,
    /// Receiver address on destination chain
    pub receiver: String,
    /// Timeout height (0 if using timestamp)
    pub timeout_height: TimeoutHeight,
    /// Timeout timestamp in nanoseconds
    pub timeout_timestamp: u64,
    /// Optional memo field for cross-chain actions
    pub memo: String,
}

/// Coin representation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Coin {
    pub denom: String,
    pub amount: String,
}

/// Timeout height for IBC transfer
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimeoutHeight {
    pub revision_number: u64,
    pub revision_height: u64,
}

impl TimeoutHeight {
    pub fn zero() -> Self {
        Self {
            revision_number: 0,
            revision_height: 0,
        }
    }

    pub fn new(revision_number: u64, revision_height: u64) -> Self {
        Self {
            revision_number,
            revision_height,
        }
    }
}

/// IBC Transfer status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum IBCTransferStatus {
    /// Transaction submitted to source chain
    Pending,
    /// Packet committed on source chain
    PacketCommitted,
    /// Packet received on destination chain
    PacketReceived,
    /// Acknowledgement received (success)
    Acknowledged,
    /// Transfer completed successfully
    Completed,
    /// Transfer timed out
    Timeout,
    /// Transfer failed with error
    Failed,
    /// Refund processed after timeout
    Refunded,
}

impl IBCTransferStatus {
    pub fn is_final(&self) -> bool {
        matches!(
            self,
            IBCTransferStatus::Completed
                | IBCTransferStatus::Timeout
                | IBCTransferStatus::Failed
                | IBCTransferStatus::Refunded
        )
    }

    pub fn display_name(&self) -> &'static str {
        match self {
            IBCTransferStatus::Pending => "Pending",
            IBCTransferStatus::PacketCommitted => "Committed",
            IBCTransferStatus::PacketReceived => "Received",
            IBCTransferStatus::Acknowledged => "Acknowledged",
            IBCTransferStatus::Completed => "Completed",
            IBCTransferStatus::Timeout => "Timed Out",
            IBCTransferStatus::Failed => "Failed",
            IBCTransferStatus::Refunded => "Refunded",
        }
    }
}

/// IBC Transfer record
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IBCTransfer {
    /// Unique transfer ID
    pub id: String,
    /// Source chain
    pub source_chain: IBCChain,
    /// Destination chain
    pub destination_chain: IBCChain,
    /// Channel used
    pub channel_id: String,
    /// Token denomination
    pub denom: String,
    /// Token symbol for display
    pub symbol: String,
    /// Amount transferred
    pub amount: String,
    /// Sender address
    pub sender: String,
    /// Receiver address
    pub receiver: String,
    /// Source transaction hash
    pub source_tx_hash: Option<String>,
    /// Destination transaction hash
    pub destination_tx_hash: Option<String>,
    /// Packet sequence number
    pub packet_sequence: Option<u64>,
    /// Transfer status
    pub status: IBCTransferStatus,
    /// Timestamp when initiated
    pub initiated_at: u64,
    /// Timestamp when completed
    pub completed_at: Option<u64>,
    /// Timeout timestamp
    pub timeout_timestamp: u64,
    /// Optional memo
    pub memo: Option<String>,
    /// Error message if failed
    pub error: Option<String>,
}

/// IBC Transfer request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IBCTransferRequest {
    pub source_chain: IBCChain,
    pub destination_chain: IBCChain,
    pub denom: String,
    pub amount: String,
    pub sender: String,
    pub receiver: String,
    pub memo: Option<String>,
    /// Custom timeout in minutes (default: 10)
    pub timeout_minutes: Option<u64>,
}

/// IBC Transfer fee estimate
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IBCFeeEstimate {
    pub gas_limit: u64,
    pub gas_price: String,
    pub fee_amount: String,
    pub fee_denom: String,
    pub fee_usd: Option<f64>,
}

/// IBC Error types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum IBCError {
    ChannelNotFound {
        source: IBCChain,
        destination: IBCChain,
    },
    InvalidAddress {
        address: String,
        expected_prefix: String,
    },
    InsufficientBalance {
        denom: String,
        required: String,
        available: String,
    },
    TransferTimeout {
        transfer_id: String,
    },
    PacketError {
        sequence: u64,
        error: String,
    },
    ChainUnavailable {
        chain: IBCChain,
    },
    InvalidDenom {
        denom: String,
    },
    MemoTooLong {
        length: usize,
        max: usize,
    },
}

impl std::fmt::Display for IBCError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            IBCError::ChannelNotFound { source, destination } => {
                write!(f, "No IBC channel found between {} and {}", source.display_name(), destination.display_name())
            }
            IBCError::InvalidAddress { address, expected_prefix } => {
                write!(f, "Invalid address '{}', expected prefix '{}'", address, expected_prefix)
            }
            IBCError::InsufficientBalance { denom, required, available } => {
                write!(f, "Insufficient balance: need {} {}, have {}", required, denom, available)
            }
            IBCError::TransferTimeout { transfer_id } => {
                write!(f, "Transfer {} timed out", transfer_id)
            }
            IBCError::PacketError { sequence, error } => {
                write!(f, "Packet {} error: {}", sequence, error)
            }
            IBCError::ChainUnavailable { chain } => {
                write!(f, "Chain {} is unavailable", chain.display_name())
            }
            IBCError::InvalidDenom { denom } => {
                write!(f, "Invalid denomination: {}", denom)
            }
            IBCError::MemoTooLong { length, max } => {
                write!(f, "Memo too long: {} bytes (max {})", length, max)
            }
        }
    }
}

impl std::error::Error for IBCError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_chain_properties() {
        assert_eq!(IBCChain::CosmosHub.chain_id(), "cosmoshub-4");
        assert_eq!(IBCChain::Osmosis.native_denom(), "uosmo");
        assert_eq!(IBCChain::Juno.bech32_prefix(), "juno");
        assert_eq!(IBCChain::Celestia.display_name(), "Celestia");
    }

    #[test]
    fn test_all_chains() {
        let chains = IBCChain::all();
        assert_eq!(chains.len(), 20);
        assert!(chains.contains(&IBCChain::CosmosHub));
        assert!(chains.contains(&IBCChain::Osmosis));
    }

    #[test]
    fn test_ibc_denom() {
        let denom = IBCDenom::new("transfer/channel-0", "uatom");
        assert!(denom.ibc_denom.starts_with("ibc/"));
        assert_eq!(denom.base_denom, "uatom");
        assert_eq!(denom.display_name, "ATOM");
        assert_eq!(denom.decimals, 6);
    }

    #[test]
    fn test_timeout_height() {
        let zero = TimeoutHeight::zero();
        assert_eq!(zero.revision_number, 0);
        assert_eq!(zero.revision_height, 0);

        let height = TimeoutHeight::new(4, 1000000);
        assert_eq!(height.revision_number, 4);
        assert_eq!(height.revision_height, 1000000);
    }

    #[test]
    fn test_transfer_status() {
        assert!(!IBCTransferStatus::Pending.is_final());
        assert!(!IBCTransferStatus::PacketCommitted.is_final());
        assert!(IBCTransferStatus::Completed.is_final());
        assert!(IBCTransferStatus::Timeout.is_final());
        assert!(IBCTransferStatus::Refunded.is_final());
    }

    #[test]
    fn test_ibc_error_display() {
        let err = IBCError::ChannelNotFound {
            source: IBCChain::CosmosHub,
            destination: IBCChain::Osmosis,
        };
        let msg = err.to_string();
        assert!(msg.contains("Cosmos Hub"));
        assert!(msg.contains("Osmosis"));
    }

    #[test]
    fn test_msg_transfer() {
        let msg = MsgTransfer {
            source_port: "transfer".to_string(),
            source_channel: "channel-0".to_string(),
            token: Coin {
                denom: "uatom".to_string(),
                amount: "1000000".to_string(),
            },
            sender: "cosmos1...".to_string(),
            receiver: "osmo1...".to_string(),
            timeout_height: TimeoutHeight::zero(),
            timeout_timestamp: 1705000000000000000,
            memo: "".to_string(),
        };
        
        assert_eq!(msg.source_port, "transfer");
        assert_eq!(msg.token.denom, "uatom");
    }
}
