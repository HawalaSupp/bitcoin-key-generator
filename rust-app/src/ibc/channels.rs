//! IBC Channel Discovery and Management
//!
//! Provides channel information and path discovery between Cosmos chains.

use super::types::{IBCChain, IBCChannel, IBCPath, ChannelState, ChannelOrdering};
use std::collections::HashMap;
use std::sync::LazyLock;

/// Known IBC channels between chains
/// Key: (source_chain, destination_chain)
static KNOWN_CHANNELS: LazyLock<HashMap<(IBCChain, IBCChain), IBCChannel>> = LazyLock::new(|| {
    let mut channels = HashMap::new();

    // Cosmos Hub <-> Osmosis
    channels.insert(
        (IBCChain::CosmosHub, IBCChain::Osmosis),
        IBCChannel {
            channel_id: "channel-141".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-0".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-400".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );
    channels.insert(
        (IBCChain::Osmosis, IBCChain::CosmosHub),
        IBCChannel {
            channel_id: "channel-0".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-141".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-0".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );

    // Cosmos Hub <-> Juno
    channels.insert(
        (IBCChain::CosmosHub, IBCChain::Juno),
        IBCChannel {
            channel_id: "channel-207".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-1".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-525".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );
    channels.insert(
        (IBCChain::Juno, IBCChain::CosmosHub),
        IBCChannel {
            channel_id: "channel-1".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-207".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-0".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );

    // Osmosis <-> Juno
    channels.insert(
        (IBCChain::Osmosis, IBCChain::Juno),
        IBCChannel {
            channel_id: "channel-42".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-0".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-30".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );
    channels.insert(
        (IBCChain::Juno, IBCChain::Osmosis),
        IBCChannel {
            channel_id: "channel-0".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-42".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-0".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );

    // Cosmos Hub <-> Stride
    channels.insert(
        (IBCChain::CosmosHub, IBCChain::Stride),
        IBCChannel {
            channel_id: "channel-391".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-0".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-854".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );
    channels.insert(
        (IBCChain::Stride, IBCChain::CosmosHub),
        IBCChannel {
            channel_id: "channel-0".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-391".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-0".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );

    // Osmosis <-> Stride
    channels.insert(
        (IBCChain::Osmosis, IBCChain::Stride),
        IBCChannel {
            channel_id: "channel-326".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-5".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-280".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );
    channels.insert(
        (IBCChain::Stride, IBCChain::Osmosis),
        IBCChannel {
            channel_id: "channel-5".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-326".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-4".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );

    // Cosmos Hub <-> Celestia
    channels.insert(
        (IBCChain::CosmosHub, IBCChain::Celestia),
        IBCChannel {
            channel_id: "channel-617".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-0".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-902".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );
    channels.insert(
        (IBCChain::Celestia, IBCChain::CosmosHub),
        IBCChannel {
            channel_id: "channel-0".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-617".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-0".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );

    // Osmosis <-> Celestia
    channels.insert(
        (IBCChain::Osmosis, IBCChain::Celestia),
        IBCChannel {
            channel_id: "channel-6994".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-2".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-7400".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );
    channels.insert(
        (IBCChain::Celestia, IBCChain::Osmosis),
        IBCChannel {
            channel_id: "channel-2".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-6994".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-1".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );

    // Osmosis <-> Noble (USDC)
    channels.insert(
        (IBCChain::Osmosis, IBCChain::Noble),
        IBCChannel {
            channel_id: "channel-750".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-1".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-700".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );
    channels.insert(
        (IBCChain::Noble, IBCChain::Osmosis),
        IBCChannel {
            channel_id: "channel-1".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-750".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-1".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );

    // Cosmos Hub <-> Noble
    channels.insert(
        (IBCChain::CosmosHub, IBCChain::Noble),
        IBCChannel {
            channel_id: "channel-536".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-4".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-862".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );
    channels.insert(
        (IBCChain::Noble, IBCChain::CosmosHub),
        IBCChannel {
            channel_id: "channel-4".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-536".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-2".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );

    // Osmosis <-> Neutron
    channels.insert(
        (IBCChain::Osmosis, IBCChain::Neutron),
        IBCChannel {
            channel_id: "channel-874".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-10".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-800".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );
    channels.insert(
        (IBCChain::Neutron, IBCChain::Osmosis),
        IBCChannel {
            channel_id: "channel-10".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-874".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-7".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );

    // Cosmos Hub <-> Neutron
    channels.insert(
        (IBCChain::CosmosHub, IBCChain::Neutron),
        IBCChannel {
            channel_id: "channel-569".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-1".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-893".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );
    channels.insert(
        (IBCChain::Neutron, IBCChain::CosmosHub),
        IBCChannel {
            channel_id: "channel-1".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-569".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-1".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );

    // Osmosis <-> Injective
    channels.insert(
        (IBCChain::Osmosis, IBCChain::Injective),
        IBCChannel {
            channel_id: "channel-122".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-8".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-100".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );
    channels.insert(
        (IBCChain::Injective, IBCChain::Osmosis),
        IBCChannel {
            channel_id: "channel-8".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-122".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-7".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );

    // Cosmos Hub <-> Stargaze
    channels.insert(
        (IBCChain::CosmosHub, IBCChain::Stargaze),
        IBCChannel {
            channel_id: "channel-730".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-239".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-700".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );
    channels.insert(
        (IBCChain::Stargaze, IBCChain::CosmosHub),
        IBCChannel {
            channel_id: "channel-239".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-730".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-200".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );

    // Osmosis <-> Stargaze
    channels.insert(
        (IBCChain::Osmosis, IBCChain::Stargaze),
        IBCChannel {
            channel_id: "channel-75".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-0".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-52".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );
    channels.insert(
        (IBCChain::Stargaze, IBCChain::Osmosis),
        IBCChannel {
            channel_id: "channel-0".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-75".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-0".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );

    // Osmosis <-> Dymension
    channels.insert(
        (IBCChain::Osmosis, IBCChain::Dymension),
        IBCChannel {
            channel_id: "channel-19774".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-2".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-18000".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );
    channels.insert(
        (IBCChain::Dymension, IBCChain::Osmosis),
        IBCChannel {
            channel_id: "channel-2".to_string(),
            port_id: "transfer".to_string(),
            counterparty_channel_id: "channel-19774".to_string(),
            counterparty_port_id: "transfer".to_string(),
            state: ChannelState::Open,
            connection_id: "connection-2".to_string(),
            ordering: ChannelOrdering::Unordered,
            version: "ics20-1".to_string(),
        },
    );

    channels
});

/// Channel discovery and management
pub struct ChannelRegistry;

impl ChannelRegistry {
    /// Get channel between two chains
    pub fn get_channel(source: IBCChain, destination: IBCChain) -> Option<IBCChannel> {
        KNOWN_CHANNELS.get(&(source, destination)).cloned()
    }

    /// Check if a route exists between two chains
    pub fn route_exists(source: IBCChain, destination: IBCChain) -> bool {
        KNOWN_CHANNELS.contains_key(&(source, destination))
    }

    /// Get all available destinations from a source chain
    pub fn get_destinations(source: IBCChain) -> Vec<IBCChain> {
        KNOWN_CHANNELS
            .keys()
            .filter(|(src, _)| *src == source)
            .map(|(_, dest)| *dest)
            .collect()
    }

    /// Get all available sources to a destination chain
    pub fn get_sources(destination: IBCChain) -> Vec<IBCChain> {
        KNOWN_CHANNELS
            .keys()
            .filter(|(_, dest)| *dest == destination)
            .map(|(src, _)| *src)
            .collect()
    }

    /// Get the IBC path for a transfer
    pub fn get_path(source: IBCChain, destination: IBCChain, denom: &str) -> Option<IBCPath> {
        let channel = Self::get_channel(source, destination)?;
        
        // Calculate IBC denom on destination
        let path_prefix = format!("{}/{}", channel.counterparty_port_id, channel.counterparty_channel_id);
        let dest_denom = if denom.starts_with("ibc/") {
            // Already an IBC denom, need to trace further
            denom.to_string()
        } else {
            // Native denom, will become IBC denom on destination
            use super::types::IBCDenom;
            IBCDenom::new(&path_prefix, denom).ibc_denom
        };

        Some(IBCPath {
            source_chain: source,
            destination_chain: destination,
            channel,
            source_denom: denom.to_string(),
            destination_denom: dest_denom,
        })
    }

    /// Get all known channels
    pub fn all_channels() -> Vec<((IBCChain, IBCChain), IBCChannel)> {
        KNOWN_CHANNELS
            .iter()
            .map(|(k, v)| (*k, v.clone()))
            .collect()
    }

    /// Get channel count
    pub fn channel_count() -> usize {
        KNOWN_CHANNELS.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_channel() {
        let channel = ChannelRegistry::get_channel(IBCChain::CosmosHub, IBCChain::Osmosis);
        assert!(channel.is_some());
        let ch = channel.unwrap();
        assert_eq!(ch.channel_id, "channel-141");
        assert_eq!(ch.port_id, "transfer");
    }

    #[test]
    fn test_bidirectional_channels() {
        // Verify channels work in both directions
        assert!(ChannelRegistry::route_exists(IBCChain::CosmosHub, IBCChain::Osmosis));
        assert!(ChannelRegistry::route_exists(IBCChain::Osmosis, IBCChain::CosmosHub));
    }

    #[test]
    fn test_get_destinations() {
        let dests = ChannelRegistry::get_destinations(IBCChain::Osmosis);
        assert!(!dests.is_empty());
        assert!(dests.contains(&IBCChain::CosmosHub));
        assert!(dests.contains(&IBCChain::Juno));
    }

    #[test]
    fn test_get_path() {
        let path = ChannelRegistry::get_path(IBCChain::CosmosHub, IBCChain::Osmosis, "uatom");
        assert!(path.is_some());
        let p = path.unwrap();
        assert_eq!(p.source_denom, "uatom");
        assert!(p.destination_denom.starts_with("ibc/"));
    }

    #[test]
    fn test_no_channel() {
        // Test non-existent direct channel (may need multi-hop)
        let channel = ChannelRegistry::get_channel(IBCChain::Stargaze, IBCChain::Celestia);
        // This might not exist as a direct channel
        if channel.is_none() {
            assert!(!ChannelRegistry::route_exists(IBCChain::Stargaze, IBCChain::Celestia));
        }
    }

    #[test]
    fn test_channel_count() {
        let count = ChannelRegistry::channel_count();
        assert!(count >= 20, "Should have at least 20 channels defined");
    }
}
