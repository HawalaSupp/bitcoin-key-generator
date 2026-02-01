//! IBC Client for interacting with Cosmos chains
//!
//! Provides RPC and REST API interactions for IBC transfers.

use super::types::*;
use super::channels::ChannelRegistry;
use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};

/// IBC Client for chain interactions
pub struct IBCClient {
    /// Active chain connections
    chain_clients: HashMap<IBCChain, ChainClient>,
}

/// Individual chain client
#[allow(dead_code)]
struct ChainClient {
    chain: IBCChain,
    rpc_endpoint: String,
    rest_endpoint: String,
}

impl IBCClient {
    /// Create a new IBC client
    pub fn new() -> Self {
        let mut chain_clients = HashMap::new();
        
        for chain in IBCChain::all() {
            chain_clients.insert(
                chain,
                ChainClient {
                    chain,
                    rpc_endpoint: chain.rpc_endpoint().to_string(),
                    rest_endpoint: chain.rest_endpoint().to_string(),
                },
            );
        }

        Self { chain_clients }
    }

    /// Get account balance for a specific denom
    pub async fn get_balance(
        &self,
        chain: IBCChain,
        address: &str,
        _denom: &str,
    ) -> Result<String, IBCError> {
        // Validate address
        self.validate_address(chain, address)?;
        
        // In production, call REST API: GET /cosmos/bank/v1beta1/balances/{address}/by_denom?denom={denom}
        // For now, return mock balance
        Ok("1000000000".to_string())
    }

    /// Get all balances for an address
    pub async fn get_all_balances(
        &self,
        chain: IBCChain,
        address: &str,
    ) -> Result<Vec<Coin>, IBCError> {
        self.validate_address(chain, address)?;
        
        // Mock balances
        Ok(vec![
            Coin {
                denom: chain.native_denom().to_string(),
                amount: "1000000000".to_string(),
            },
        ])
    }

    /// Get the latest block height for a chain
    pub async fn get_latest_height(&self, chain: IBCChain) -> Result<u64, IBCError> {
        let _client = self.get_client(chain)?;
        
        // In production, call RPC: GET /status
        // Mock height
        Ok(20_000_000)
    }

    /// Get account sequence and number for signing
    pub async fn get_account_info(
        &self,
        chain: IBCChain,
        address: &str,
    ) -> Result<AccountInfo, IBCError> {
        self.validate_address(chain, address)?;
        
        // In production, call REST API: GET /cosmos/auth/v1beta1/accounts/{address}
        Ok(AccountInfo {
            account_number: 12345,
            sequence: 0,
        })
    }

    /// Estimate gas for an IBC transfer
    pub async fn estimate_gas(
        &self,
        chain: IBCChain,
        msg: &MsgTransfer,
    ) -> Result<IBCFeeEstimate, IBCError> {
        let _client = self.get_client(chain)?;
        
        // Base gas for IBC transfer
        let base_gas: u64 = 200_000;
        
        // Add gas for memo
        let memo_gas = (msg.memo.len() as u64) * 10;
        
        let gas_limit = base_gas + memo_gas;
        
        // Get gas price based on chain
        let gas_price = self.get_gas_price(chain);
        
        // Calculate fee
        let fee_amount = gas_limit * gas_price.parse::<u64>().unwrap_or(1);
        
        Ok(IBCFeeEstimate {
            gas_limit,
            gas_price,
            fee_amount: fee_amount.to_string(),
            fee_denom: chain.native_denom().to_string(),
            fee_usd: Some(fee_amount as f64 / 1_000_000.0 * 10.0), // Rough estimate
        })
    }

    /// Broadcast a signed transaction
    pub async fn broadcast_tx(
        &self,
        chain: IBCChain,
        _signed_tx: &[u8],
    ) -> Result<BroadcastResult, IBCError> {
        let _client = self.get_client(chain)?;
        
        // In production, call RPC: POST /broadcast_tx_sync
        // Generate mock tx hash
        let tx_hash = format!(
            "{:064X}",
            std::collections::hash_map::DefaultHasher::new()
                .finish()
        );
        
        Ok(BroadcastResult {
            tx_hash,
            code: 0,
            log: "".to_string(),
        })
    }

    /// Query transaction by hash
    pub async fn get_tx(
        &self,
        chain: IBCChain,
        tx_hash: &str,
    ) -> Result<TxResponse, IBCError> {
        let _client = self.get_client(chain)?;
        
        // In production, call RPC: GET /tx?hash={hash}
        Ok(TxResponse {
            hash: tx_hash.to_string(),
            height: 20_000_000,
            code: 0,
            events: vec![],
            timestamp: current_timestamp(),
        })
    }

    /// Query IBC packet commitment
    pub async fn get_packet_commitment(
        &self,
        chain: IBCChain,
        port_id: &str,
        channel_id: &str,
        sequence: u64,
    ) -> Result<Option<PacketCommitment>, IBCError> {
        let _client = self.get_client(chain)?;
        
        // In production, call REST: GET /ibc/core/channel/v1/channels/{channel_id}/ports/{port_id}/packet_commitments/{sequence}
        Ok(Some(PacketCommitment {
            port_id: port_id.to_string(),
            channel_id: channel_id.to_string(),
            sequence,
            commitment: "mock_commitment".to_string(),
        }))
    }

    /// Query IBC packet acknowledgement
    pub async fn get_packet_acknowledgement(
        &self,
        chain: IBCChain,
        port_id: &str,
        channel_id: &str,
        sequence: u64,
    ) -> Result<Option<PacketAcknowledgement>, IBCError> {
        let _client = self.get_client(chain)?;
        
        // In production, call REST: GET /ibc/core/channel/v1/channels/{channel_id}/ports/{port_id}/packet_acks/{sequence}
        Ok(Some(PacketAcknowledgement {
            port_id: port_id.to_string(),
            channel_id: channel_id.to_string(),
            sequence,
            acknowledgement: "mock_ack".to_string(),
            success: true,
        }))
    }

    /// Get channel info
    pub async fn get_channel_info(
        &self,
        chain: IBCChain,
        port_id: &str,
        channel_id: &str,
    ) -> Result<IBCChannel, IBCError> {
        let _client = self.get_client(chain)?;
        
        // Use local registry first
        for dest in IBCChain::all() {
            if let Some(channel) = ChannelRegistry::get_channel(chain, dest) {
                if channel.channel_id == channel_id && channel.port_id == port_id {
                    return Ok(channel);
                }
            }
        }
        
        // In production, call REST: GET /ibc/core/channel/v1/channels/{channel_id}/ports/{port_id}
        Err(IBCError::ChannelNotFound {
            source: chain,
            destination: chain, // Unknown destination
        })
    }

    /// Validate an address for a chain
    pub fn validate_address(&self, chain: IBCChain, address: &str) -> Result<(), IBCError> {
        let prefix = chain.bech32_prefix();
        
        if !address.starts_with(prefix) {
            return Err(IBCError::InvalidAddress {
                address: address.to_string(),
                expected_prefix: prefix.to_string(),
            });
        }
        
        // Additional validation could check:
        // - Bech32 checksum
        // - Address length (usually 39-45 chars for Cosmos)
        if address.len() < 39 || address.len() > 65 {
            return Err(IBCError::InvalidAddress {
                address: address.to_string(),
                expected_prefix: prefix.to_string(),
            });
        }
        
        Ok(())
    }

    /// Get gas price for a chain
    fn get_gas_price(&self, chain: IBCChain) -> String {
        match chain {
            IBCChain::CosmosHub => "0.025".to_string(),
            IBCChain::Osmosis => "0.025".to_string(),
            IBCChain::Juno => "0.075".to_string(),
            IBCChain::Stargaze => "1.0".to_string(),
            IBCChain::Akash => "0.025".to_string(),
            IBCChain::Stride => "0.025".to_string(),
            IBCChain::Celestia => "0.002".to_string(),
            IBCChain::Dymension => "20000000000".to_string(),
            IBCChain::Neutron => "0.075".to_string(),
            IBCChain::Injective => "500000000".to_string(),
            IBCChain::Sei => "0.1".to_string(),
            IBCChain::Noble => "0.1".to_string(),
            IBCChain::Kujira => "0.00125".to_string(),
            IBCChain::Terra => "0.015".to_string(),
            IBCChain::Secret => "0.25".to_string(),
            IBCChain::Axelar => "0.007".to_string(),
            IBCChain::Evmos => "80000000000".to_string(),
            IBCChain::Persistence => "0".to_string(),
            IBCChain::Agoric => "0.03".to_string(),
            IBCChain::Crescent => "0.01".to_string(),
        }
    }

    fn get_client(&self, chain: IBCChain) -> Result<&ChainClient, IBCError> {
        self.chain_clients
            .get(&chain)
            .ok_or(IBCError::ChainUnavailable { chain })
    }
}

impl Default for IBCClient {
    fn default() -> Self {
        Self::new()
    }
}

/// Account info for signing
#[derive(Debug, Clone)]
pub struct AccountInfo {
    pub account_number: u64,
    pub sequence: u64,
}

/// Broadcast result
#[derive(Debug, Clone)]
pub struct BroadcastResult {
    pub tx_hash: String,
    pub code: u32,
    pub log: String,
}

impl BroadcastResult {
    pub fn is_success(&self) -> bool {
        self.code == 0
    }
}

/// Transaction response
#[derive(Debug, Clone)]
pub struct TxResponse {
    pub hash: String,
    pub height: u64,
    pub code: u32,
    pub events: Vec<TxEvent>,
    pub timestamp: u64,
}

impl TxResponse {
    pub fn is_success(&self) -> bool {
        self.code == 0
    }
}

/// Transaction event
#[derive(Debug, Clone)]
pub struct TxEvent {
    pub r#type: String,
    pub attributes: Vec<(String, String)>,
}

/// Packet commitment proof
#[derive(Debug, Clone)]
pub struct PacketCommitment {
    pub port_id: String,
    pub channel_id: String,
    pub sequence: u64,
    pub commitment: String,
}

/// Packet acknowledgement
#[derive(Debug, Clone)]
pub struct PacketAcknowledgement {
    pub port_id: String,
    pub channel_id: String,
    pub sequence: u64,
    pub acknowledgement: String,
    pub success: bool,
}

/// Get current timestamp in seconds
fn current_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

use std::hash::Hasher;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_client_creation() {
        let client = IBCClient::new();
        assert!(!client.chain_clients.is_empty());
    }

    #[test]
    fn test_address_validation() {
        let client = IBCClient::new();
        
        // Valid Cosmos address
        let result = client.validate_address(
            IBCChain::CosmosHub,
            "cosmos1hsk6jryyqjfhp5dhc55tc9jtckygx0eph6dd02",
        );
        assert!(result.is_ok());
        
        // Invalid prefix
        let result = client.validate_address(
            IBCChain::CosmosHub,
            "osmo1hsk6jryyqjfhp5dhc55tc9jtckygx0eph6dd02",
        );
        assert!(matches!(result, Err(IBCError::InvalidAddress { .. })));
    }

    #[test]
    fn test_gas_prices() {
        let client = IBCClient::new();
        
        let cosmos_price = client.get_gas_price(IBCChain::CosmosHub);
        assert_eq!(cosmos_price, "0.025");
        
        let osmo_price = client.get_gas_price(IBCChain::Osmosis);
        assert_eq!(osmo_price, "0.025");
    }

    #[tokio::test]
    async fn test_get_balance() {
        let client = IBCClient::new();
        
        let balance = client
            .get_balance(
                IBCChain::CosmosHub,
                "cosmos1hsk6jryyqjfhp5dhc55tc9jtckygx0eph6dd02",
                "uatom",
            )
            .await;
        
        assert!(balance.is_ok());
    }

    #[tokio::test]
    async fn test_estimate_gas() {
        let client = IBCClient::new();
        
        let msg = MsgTransfer {
            source_port: "transfer".to_string(),
            source_channel: "channel-141".to_string(),
            token: Coin {
                denom: "uatom".to_string(),
                amount: "1000000".to_string(),
            },
            sender: "cosmos1hsk6jryyqjfhp5dhc55tc9jtckygx0eph6dd02".to_string(),
            receiver: "osmo1hsk6jryyqjfhp5dhc55tc9jtckygx0eph6dd02".to_string(),
            timeout_height: TimeoutHeight::zero(),
            timeout_timestamp: 0,
            memo: "".to_string(),
        };
        
        let estimate = client.estimate_gas(IBCChain::CosmosHub, &msg).await;
        assert!(estimate.is_ok());
        
        let fee = estimate.unwrap();
        assert!(fee.gas_limit >= 200_000);
    }

    #[test]
    fn test_broadcast_result() {
        let success = BroadcastResult {
            tx_hash: "ABC123".to_string(),
            code: 0,
            log: "".to_string(),
        };
        assert!(success.is_success());
        
        let failure = BroadcastResult {
            tx_hash: "ABC123".to_string(),
            code: 1,
            log: "out of gas".to_string(),
        };
        assert!(!failure.is_success());
    }
}
