//! IBC Module Integration Tests

use super::*;

#[cfg(test)]
mod integration_tests {
    use super::*;
    use types::*;
    use channels::ChannelRegistry;
    use transfer::IBCTransferService;

    #[test]
    fn test_full_ibc_transfer_flow() {
        let service = IBCTransferService::new();
        
        // Build a transfer from Cosmos Hub to Osmosis
        let request = IBCTransferRequest {
            source_chain: IBCChain::CosmosHub,
            destination_chain: IBCChain::Osmosis,
            denom: "uatom".to_string(),
            amount: "1000000".to_string(), // 1 ATOM
            sender: "cosmos1abc...".to_string(),
            receiver: "osmo1xyz...".to_string(),
            memo: Some("Hawala IBC Transfer".to_string()),
            timeout_minutes: Some(10),
        };
        
        let msg = service.build_transfer(&request).unwrap();
        
        assert_eq!(msg.source_port, "transfer");
        assert_eq!(msg.source_channel, "channel-141");
        assert_eq!(msg.token.denom, "uatom");
        assert_eq!(msg.token.amount, "1000000");
        assert!(msg.timeout_timestamp > 0);
    }

    #[test]
    fn test_multi_chain_ibc_support() {
        // Verify we have channels for major routes
        let routes = vec![
            (IBCChain::CosmosHub, IBCChain::Osmosis),
            (IBCChain::Osmosis, IBCChain::CosmosHub),
            (IBCChain::CosmosHub, IBCChain::Juno),
            (IBCChain::Osmosis, IBCChain::Juno),
            (IBCChain::CosmosHub, IBCChain::Stride),
            (IBCChain::Osmosis, IBCChain::Stride),
            (IBCChain::CosmosHub, IBCChain::Celestia),
            (IBCChain::Osmosis, IBCChain::Celestia),
            (IBCChain::Osmosis, IBCChain::Noble),
            (IBCChain::CosmosHub, IBCChain::Noble),
        ];
        
        for (source, dest) in routes {
            assert!(
                ChannelRegistry::route_exists(source, dest),
                "Route should exist: {} -> {}",
                source.display_name(),
                dest.display_name()
            );
        }
    }

    #[test]
    fn test_ibc_denom_calculation() {
        // When ATOM goes from Cosmos Hub to Osmosis
        let path = ChannelRegistry::get_path(IBCChain::CosmosHub, IBCChain::Osmosis, "uatom");
        assert!(path.is_some());
        
        let p = path.unwrap();
        assert_eq!(p.source_denom, "uatom");
        assert!(p.destination_denom.starts_with("ibc/"));
    }

    #[test]
    fn test_transfer_status_lifecycle() {
        // Test all status transitions
        let statuses = vec![
            IBCTransferStatus::Pending,
            IBCTransferStatus::PacketCommitted,
            IBCTransferStatus::PacketReceived,
            IBCTransferStatus::Acknowledged,
            IBCTransferStatus::Completed,
        ];
        
        for (i, status) in statuses.iter().enumerate() {
            if i < statuses.len() - 1 {
                assert!(!status.is_final());
            } else {
                assert!(status.is_final());
            }
        }
        
        // Test failure states
        assert!(IBCTransferStatus::Timeout.is_final());
        assert!(IBCTransferStatus::Failed.is_final());
        assert!(IBCTransferStatus::Refunded.is_final());
    }

    #[test]
    fn test_chain_configurations() {
        for chain in IBCChain::all() {
            // Every chain should have these properties
            assert!(!chain.chain_id().is_empty());
            assert!(!chain.native_denom().is_empty());
            assert!(!chain.bech32_prefix().is_empty());
            assert!(!chain.display_name().is_empty());
            assert!(chain.rpc_endpoint().starts_with("https://"));
            assert!(chain.rest_endpoint().starts_with("https://"));
        }
    }

    #[test]
    fn test_osmosis_as_hub() {
        // Osmosis is the main liquidity hub and should connect to many chains
        let destinations = ChannelRegistry::get_destinations(IBCChain::Osmosis);
        
        // Should connect to at least these major chains
        assert!(destinations.contains(&IBCChain::CosmosHub));
        assert!(destinations.contains(&IBCChain::Juno));
        assert!(destinations.contains(&IBCChain::Stride));
        assert!(destinations.contains(&IBCChain::Noble));
        
        assert!(destinations.len() >= 8, "Osmosis should have many IBC connections");
    }

    #[test]
    fn test_cosmos_hub_connections() {
        let destinations = ChannelRegistry::get_destinations(IBCChain::CosmosHub);
        
        assert!(destinations.contains(&IBCChain::Osmosis));
        assert!(destinations.len() >= 5, "Cosmos Hub should have major IBC connections");
    }

    #[test]
    fn test_noble_usdc_routes() {
        // Noble is the native USDC issuance chain
        // It should have routes to major chains
        let sources = ChannelRegistry::get_sources(IBCChain::Noble);
        
        assert!(sources.contains(&IBCChain::Osmosis));
        assert!(sources.contains(&IBCChain::CosmosHub));
    }

    #[test]
    fn test_ibc_error_types() {
        let errors: Vec<IBCError> = vec![
            IBCError::ChannelNotFound {
                source: IBCChain::CosmosHub,
                destination: IBCChain::Osmosis,
            },
            IBCError::InvalidAddress {
                address: "bad".to_string(),
                expected_prefix: "cosmos".to_string(),
            },
            IBCError::InsufficientBalance {
                denom: "uatom".to_string(),
                required: "1000000".to_string(),
                available: "500000".to_string(),
            },
            IBCError::TransferTimeout {
                transfer_id: "ibc-123".to_string(),
            },
            IBCError::MemoTooLong {
                length: 500,
                max: 256,
            },
        ];
        
        for error in errors {
            // Each error should have a meaningful display message
            let msg = error.to_string();
            assert!(!msg.is_empty());
        }
    }

    #[test]
    fn test_bidirectional_channels() {
        // All channels should work in both directions
        let all_channels = ChannelRegistry::all_channels();
        
        for ((source, dest), _channel) in &all_channels {
            // Reverse route should also exist
            let reverse = ChannelRegistry::get_channel(*dest, *source);
            assert!(
                reverse.is_some(),
                "Reverse channel should exist: {} -> {}",
                dest.display_name(),
                source.display_name()
            );
        }
    }

    #[test]
    fn test_msg_transfer_serialization() {
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
            memo: "test".to_string(),
        };
        
        // Should be serializable to JSON (for Amino/Protobuf encoding)
        let json = serde_json::to_string(&msg);
        assert!(json.is_ok());
        
        let json_str = json.unwrap();
        assert!(json_str.contains("transfer"));
        assert!(json_str.contains("uatom"));
    }

    #[tokio::test]
    async fn test_transfer_execution_flow() {
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
        
        let transfer = service.execute_transfer(request).await.unwrap();
        
        assert_eq!(transfer.source_chain, IBCChain::CosmosHub);
        assert_eq!(transfer.destination_chain, IBCChain::Osmosis);
        assert_eq!(transfer.symbol, "ATOM");
        assert_eq!(transfer.status, IBCTransferStatus::Pending);
        
        // Should be in active transfers
        let active = service.get_active_transfers();
        assert_eq!(active.len(), 1);
    }
}
