//! IBC Transfer Builder and Executor
//!
//! Builds MsgTransfer messages and executes IBC token transfers.

use super::types::*;
use super::channels::ChannelRegistry;
use super::client::IBCClient;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH, Duration};

/// Default timeout in minutes for IBC transfers
const DEFAULT_TIMEOUT_MINUTES: u64 = 10;

/// Maximum memo length in bytes
const MAX_MEMO_LENGTH: usize = 256;

/// IBC Transfer service
pub struct IBCTransferService {
    client: Arc<IBCClient>,
    /// Active transfers being tracked
    active_transfers: HashMap<String, IBCTransfer>,
}

impl IBCTransferService {
    /// Create a new transfer service
    pub fn new() -> Self {
        Self {
            client: Arc::new(IBCClient::new()),
            active_transfers: HashMap::new(),
        }
    }

    /// Create a new transfer service with a shared client
    pub fn with_client(client: Arc<IBCClient>) -> Self {
        Self {
            client,
            active_transfers: HashMap::new(),
        }
    }

    /// Build a MsgTransfer for an IBC transfer
    pub fn build_transfer(
        &self,
        request: &IBCTransferRequest,
    ) -> Result<MsgTransfer, IBCError> {
        // Validate request
        self.validate_request(request)?;

        // Get channel
        let channel = ChannelRegistry::get_channel(request.source_chain, request.destination_chain)
            .ok_or(IBCError::ChannelNotFound {
                source: request.source_chain,
                destination: request.destination_chain,
            })?;

        // Calculate timeout
        let timeout_minutes = request.timeout_minutes.unwrap_or(DEFAULT_TIMEOUT_MINUTES);
        let timeout_timestamp = calculate_timeout_timestamp(timeout_minutes);

        // Build memo
        let memo = request.memo.clone().unwrap_or_default();
        if memo.len() > MAX_MEMO_LENGTH {
            return Err(IBCError::MemoTooLong {
                length: memo.len(),
                max: MAX_MEMO_LENGTH,
            });
        }

        Ok(MsgTransfer {
            source_port: channel.port_id,
            source_channel: channel.channel_id,
            token: Coin {
                denom: request.denom.clone(),
                amount: request.amount.clone(),
            },
            sender: request.sender.clone(),
            receiver: request.receiver.clone(),
            timeout_height: TimeoutHeight::zero(), // Use timestamp instead
            timeout_timestamp,
            memo,
        })
    }

    /// Execute an IBC transfer
    pub async fn execute_transfer(
        &mut self,
        request: IBCTransferRequest,
    ) -> Result<IBCTransfer, IBCError> {
        // Validate addresses
        self.client.validate_address(request.source_chain, &request.sender)?;
        self.client.validate_address(request.destination_chain, &request.receiver)?;

        // Check balance
        let balance = self
            .client
            .get_balance(request.source_chain, &request.sender, &request.denom)
            .await?;
        
        if balance.parse::<u128>().unwrap_or(0) < request.amount.parse::<u128>().unwrap_or(u128::MAX) {
            return Err(IBCError::InsufficientBalance {
                denom: request.denom.clone(),
                required: request.amount.clone(),
                available: balance,
            });
        }

        // Build the transfer message
        let msg = self.build_transfer(&request)?;

        // Estimate gas
        let _fee = self.client.estimate_gas(request.source_chain, &msg).await?;

        // In production:
        // 1. Get account info (number, sequence)
        // 2. Build and sign the transaction
        // 3. Broadcast the transaction
        // 4. Wait for confirmation

        // For now, simulate broadcast
        let tx_hash = generate_tx_hash(&request);
        let transfer_id = generate_transfer_id();
        let now = current_timestamp();

        let transfer = IBCTransfer {
            id: transfer_id.clone(),
            source_chain: request.source_chain,
            destination_chain: request.destination_chain,
            channel_id: msg.source_channel.clone(),
            denom: request.denom.clone(),
            symbol: denom_to_symbol(&request.denom),
            amount: request.amount,
            sender: request.sender,
            receiver: request.receiver,
            source_tx_hash: Some(tx_hash),
            destination_tx_hash: None,
            packet_sequence: Some(1), // Would be extracted from tx events
            status: IBCTransferStatus::Pending,
            initiated_at: now,
            completed_at: None,
            timeout_timestamp: msg.timeout_timestamp,
            memo: request.memo,
            error: None,
        };

        // Track the transfer
        self.active_transfers.insert(transfer_id, transfer.clone());

        Ok(transfer)
    }

    /// Get transfer status
    pub async fn get_transfer_status(
        &mut self,
        transfer_id: &str,
    ) -> Result<IBCTransfer, IBCError> {
        let transfer = self
            .active_transfers
            .get_mut(transfer_id)
            .ok_or_else(|| IBCError::TransferTimeout {
                transfer_id: transfer_id.to_string(),
            })?;

        // Check if timed out
        let now = current_timestamp();
        if now > transfer.timeout_timestamp / 1_000_000_000 && !transfer.status.is_final() {
            transfer.status = IBCTransferStatus::Timeout;
            transfer.completed_at = Some(now);
            return Ok(transfer.clone());
        }

        // In production, query the source and destination chains for packet status
        // Simulate progress for demo
        if !transfer.status.is_final() {
            let elapsed = now - transfer.initiated_at;
            
            if elapsed > 60 {
                transfer.status = IBCTransferStatus::Completed;
                transfer.completed_at = Some(now);
                transfer.destination_tx_hash = Some(generate_tx_hash_simple());
            } else if elapsed > 45 {
                transfer.status = IBCTransferStatus::Acknowledged;
            } else if elapsed > 30 {
                transfer.status = IBCTransferStatus::PacketReceived;
            } else if elapsed > 15 {
                transfer.status = IBCTransferStatus::PacketCommitted;
            }
        }

        Ok(transfer.clone())
    }

    /// Track packet by sequence number
    pub async fn track_packet(
        &self,
        source_chain: IBCChain,
        port_id: &str,
        channel_id: &str,
        sequence: u64,
    ) -> Result<PacketStatus, IBCError> {
        // Check commitment on source chain
        let commitment = self
            .client
            .get_packet_commitment(source_chain, port_id, channel_id, sequence)
            .await?;

        if commitment.is_none() {
            return Ok(PacketStatus::NotFound);
        }

        // Get destination chain
        let dest_chain = self.find_destination_chain(source_chain, channel_id)?;

        // Check acknowledgement on destination chain
        let ack = self
            .client
            .get_packet_acknowledgement(dest_chain, port_id, channel_id, sequence)
            .await?;

        match ack {
            Some(a) if a.success => Ok(PacketStatus::Acknowledged),
            Some(_) => Ok(PacketStatus::Failed),
            None => Ok(PacketStatus::Pending),
        }
    }

    /// Get all active transfers
    pub fn get_active_transfers(&self) -> Vec<&IBCTransfer> {
        self.active_transfers
            .values()
            .filter(|t| !t.status.is_final())
            .collect()
    }

    /// Get all transfers (including completed)
    pub fn get_all_transfers(&self) -> Vec<&IBCTransfer> {
        self.active_transfers.values().collect()
    }

    /// Clear completed transfers from tracking
    pub fn clear_completed(&mut self) {
        self.active_transfers.retain(|_, t| !t.status.is_final());
    }

    /// Validate a transfer request
    fn validate_request(&self, request: &IBCTransferRequest) -> Result<(), IBCError> {
        // Validate amount
        if request.amount.parse::<u128>().is_err() || request.amount == "0" {
            return Err(IBCError::InvalidDenom {
                denom: format!("Invalid amount: {}", request.amount),
            });
        }

        // Validate denom
        if request.denom.is_empty() {
            return Err(IBCError::InvalidDenom {
                denom: "Empty denomination".to_string(),
            });
        }

        // Validate memo length
        if let Some(ref memo) = request.memo {
            if memo.len() > MAX_MEMO_LENGTH {
                return Err(IBCError::MemoTooLong {
                    length: memo.len(),
                    max: MAX_MEMO_LENGTH,
                });
            }
        }

        Ok(())
    }

    /// Find destination chain for a channel
    fn find_destination_chain(
        &self,
        source: IBCChain,
        channel_id: &str,
    ) -> Result<IBCChain, IBCError> {
        for dest in IBCChain::all() {
            if let Some(channel) = ChannelRegistry::get_channel(source, dest) {
                if channel.channel_id == channel_id {
                    return Ok(dest);
                }
            }
        }

        Err(IBCError::ChannelNotFound {
            source,
            destination: source,
        })
    }
}

impl Default for IBCTransferService {
    fn default() -> Self {
        Self::new()
    }
}

/// Packet tracking status
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PacketStatus {
    NotFound,
    Pending,
    Acknowledged,
    Failed,
    Timeout,
}

/// Calculate timeout timestamp (nanoseconds since Unix epoch)
fn calculate_timeout_timestamp(timeout_minutes: u64) -> u64 {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or(Duration::ZERO);
    
    let timeout = now + Duration::from_secs(timeout_minutes * 60);
    timeout.as_nanos() as u64
}

/// Get current timestamp in seconds
fn current_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or(Duration::ZERO)
        .as_secs()
}

/// Generate a unique transfer ID
fn generate_transfer_id() -> String {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    
    let mut hasher = DefaultHasher::new();
    current_timestamp().hash(&mut hasher);
    std::process::id().hash(&mut hasher);
    format!("ibc-{:016x}", hasher.finish())
}

/// Generate a mock transaction hash
fn generate_tx_hash(request: &IBCTransferRequest) -> String {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    
    let mut hasher = DefaultHasher::new();
    request.sender.hash(&mut hasher);
    request.receiver.hash(&mut hasher);
    request.amount.hash(&mut hasher);
    current_timestamp().hash(&mut hasher);
    format!("{:064X}", hasher.finish())
}

fn generate_tx_hash_simple() -> String {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    
    let mut hasher = DefaultHasher::new();
    current_timestamp().hash(&mut hasher);
    format!("{:064X}", hasher.finish())
}

/// Convert denom to display symbol
fn denom_to_symbol(denom: &str) -> String {
    if denom.starts_with("ibc/") {
        // Would need to trace the IBC denom
        "IBC".to_string()
    } else if denom.starts_with('u') {
        denom[1..].to_uppercase()
    } else if denom.starts_with('a') {
        denom[1..].to_uppercase()
    } else {
        denom.to_uppercase()
    }
}

/// IBC Memo builder for cross-chain actions
pub struct MemoBuilder {
    memo: serde_json::Value,
}

impl MemoBuilder {
    /// Create a new memo builder
    pub fn new() -> Self {
        Self {
            memo: serde_json::json!({}),
        }
    }

    /// Add a wasm execute message (for cross-chain contract calls)
    pub fn wasm_execute(
        mut self,
        contract: &str,
        msg: serde_json::Value,
    ) -> Self {
        self.memo["wasm"] = serde_json::json!({
            "contract": contract,
            "msg": msg
        });
        self
    }

    /// Add an Osmosis swap (Packet Forward Middleware)
    pub fn osmosis_swap(
        mut self,
        pool_id: u64,
        token_out_denom: &str,
        min_out: &str,
    ) -> Self {
        self.memo["osmosis"] = serde_json::json!({
            "swap": {
                "pool_id": pool_id,
                "token_out_denom": token_out_denom,
                "token_out_min_amount": min_out
            }
        });
        self
    }

    /// Add packet forward middleware routing
    pub fn forward(
        mut self,
        receiver: &str,
        port: &str,
        channel: &str,
    ) -> Self {
        self.memo["forward"] = serde_json::json!({
            "receiver": receiver,
            "port": port,
            "channel": channel
        });
        self
    }

    /// Build the memo string
    pub fn build(self) -> String {
        if self.memo.as_object().map(|o| o.is_empty()).unwrap_or(true) {
            String::new()
        } else {
            self.memo.to_string()
        }
    }
}

impl Default for MemoBuilder {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_build_transfer() {
        let service = IBCTransferService::new();
        
        let request = IBCTransferRequest {
            source_chain: IBCChain::CosmosHub,
            destination_chain: IBCChain::Osmosis,
            denom: "uatom".to_string(),
            amount: "1000000".to_string(),
            sender: "cosmos1abc...".to_string(),
            receiver: "osmo1xyz...".to_string(),
            memo: None,
            timeout_minutes: Some(10),
        };
        
        let msg = service.build_transfer(&request);
        assert!(msg.is_ok());
        
        let transfer = msg.unwrap();
        assert_eq!(transfer.source_port, "transfer");
        assert_eq!(transfer.source_channel, "channel-141");
        assert_eq!(transfer.token.denom, "uatom");
        assert_eq!(transfer.token.amount, "1000000");
    }

    #[test]
    fn test_build_transfer_no_channel() {
        let service = IBCTransferService::new();
        
        // Use a route that might not have a direct channel
        let request = IBCTransferRequest {
            source_chain: IBCChain::Secret,
            destination_chain: IBCChain::Celestia,
            denom: "uscrt".to_string(),
            amount: "1000000".to_string(),
            sender: "secret1abc...".to_string(),
            receiver: "celestia1xyz...".to_string(),
            memo: None,
            timeout_minutes: None,
        };
        
        let result = service.build_transfer(&request);
        // May fail if no direct channel exists
        if result.is_err() {
            assert!(matches!(result.unwrap_err(), IBCError::ChannelNotFound { .. }));
        }
    }

    #[test]
    fn test_memo_too_long() {
        let service = IBCTransferService::new();
        
        let long_memo = "x".repeat(300);
        let request = IBCTransferRequest {
            source_chain: IBCChain::CosmosHub,
            destination_chain: IBCChain::Osmosis,
            denom: "uatom".to_string(),
            amount: "1000000".to_string(),
            sender: "cosmos1abc...".to_string(),
            receiver: "osmo1xyz...".to_string(),
            memo: Some(long_memo),
            timeout_minutes: None,
        };
        
        let result = service.build_transfer(&request);
        assert!(matches!(result.unwrap_err(), IBCError::MemoTooLong { .. }));
    }

    #[test]
    fn test_timeout_calculation() {
        let timeout = calculate_timeout_timestamp(10);
        let now_ns = current_timestamp() * 1_000_000_000;
        
        // Timeout should be 10 minutes in the future (in nanoseconds)
        assert!(timeout > now_ns);
        assert!(timeout < now_ns + 15 * 60 * 1_000_000_000); // Less than 15 min
    }

    #[test]
    fn test_memo_builder() {
        let memo = MemoBuilder::new()
            .wasm_execute("osmo1contract...", serde_json::json!({"action": "swap"}))
            .build();
        
        assert!(memo.contains("wasm"));
        assert!(memo.contains("contract"));
    }

    #[test]
    fn test_memo_builder_empty() {
        let memo = MemoBuilder::new().build();
        assert!(memo.is_empty());
    }

    #[test]
    fn test_forward_memo() {
        let memo = MemoBuilder::new()
            .forward("cosmos1final...", "transfer", "channel-0")
            .build();
        
        assert!(memo.contains("forward"));
        assert!(memo.contains("channel-0"));
    }

    #[test]
    fn test_denom_to_symbol() {
        assert_eq!(denom_to_symbol("uatom"), "ATOM");
        assert_eq!(denom_to_symbol("uosmo"), "OSMO");
        assert_eq!(denom_to_symbol("aevmos"), "EVMOS");
        assert_eq!(denom_to_symbol("inj"), "INJ");
    }

    #[tokio::test]
    async fn test_execute_and_track() {
        let mut service = IBCTransferService::new();
        
        let request = IBCTransferRequest {
            source_chain: IBCChain::CosmosHub,
            destination_chain: IBCChain::Osmosis,
            denom: "uatom".to_string(),
            amount: "1000000".to_string(),
            sender: "cosmos1hsk6jryyqjfhp5dhc55tc9jtckygx0eph6dd02".to_string(),
            receiver: "osmo1hsk6jryyqjfhp5dhc55tc9jtckygx0eph6dd02".to_string(),
            memo: None,
            timeout_minutes: Some(10),
        };
        
        let transfer = service.execute_transfer(request).await;
        assert!(transfer.is_ok());
        
        let t = transfer.unwrap();
        assert_eq!(t.status, IBCTransferStatus::Pending);
        assert!(t.source_tx_hash.is_some());
        
        // Track the transfer
        let status = service.get_transfer_status(&t.id).await;
        assert!(status.is_ok());
    }

    #[test]
    fn test_packet_status() {
        assert_ne!(PacketStatus::Pending, PacketStatus::Acknowledged);
        assert_ne!(PacketStatus::Failed, PacketStatus::Timeout);
    }
}
