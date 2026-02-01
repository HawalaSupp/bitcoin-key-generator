//! Wormhole bridge integration
//!
//! Wormhole is a cross-chain messaging protocol that enables token transfers
//! across multiple chains including EVM, Solana, and Cosmos ecosystems.

use crate::error::{HawalaError, HawalaResult};
use crate::types::Chain;
use super::types::*;

/// Wormhole API endpoints
#[allow(dead_code)]
const WORMHOLE_API_BASE: &str = "https://api.wormholescan.io/api/v1";

/// Wormhole chain IDs (different from EVM chain IDs)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WormholeChainId {
    Solana = 1,
    Ethereum = 2,
    Terra = 3,
    Bsc = 4,
    Polygon = 5,
    Avalanche = 6,
    Oasis = 7,
    Algorand = 8,
    Aurora = 9,
    Fantom = 10,
    Karura = 11,
    Acala = 12,
    Klaytn = 13,
    Celo = 14,
    Near = 15,
    Moonbeam = 16,
    Neon = 17,
    Terra2 = 18,
    Injective = 19,
    Osmosis = 20,
    Sui = 21,
    Aptos = 22,
    Arbitrum = 23,
    Optimism = 24,
    Gnosis = 25,
    Pythnet = 26,
    Xpla = 28,
    Base = 30,
    Sei = 32,
    Scroll = 34,
    Blast = 36,
}

impl WormholeChainId {
    /// Convert from our Chain type to Wormhole chain ID
    pub fn from_chain(chain: Chain) -> Option<Self> {
        match chain {
            Chain::Ethereum => Some(Self::Ethereum),
            Chain::Bnb => Some(Self::Bsc),
            Chain::Polygon => Some(Self::Polygon),
            Chain::Arbitrum => Some(Self::Arbitrum),
            Chain::Optimism => Some(Self::Optimism),
            Chain::Avalanche => Some(Self::Avalanche),
            Chain::Base => Some(Self::Base),
            Chain::Fantom => Some(Self::Fantom),
            Chain::Solana => Some(Self::Solana),
            Chain::Sui => Some(Self::Sui),
            Chain::Aptos => Some(Self::Aptos),
            Chain::Osmosis => Some(Self::Osmosis),
            Chain::Injective => Some(Self::Injective),
            Chain::Sei => Some(Self::Sei),
            _ => None,
        }
    }

    /// Get numeric value
    pub fn value(&self) -> u16 {
        *self as u16
    }
}

/// Wormhole token bridge addresses by chain
pub struct WormholeAddresses;

impl WormholeAddresses {
    /// Get Token Bridge address for a chain
    pub fn token_bridge(chain: Chain) -> Option<&'static str> {
        match chain {
            Chain::Ethereum => Some("0x3ee18B2214AFF97000D974cf647E7C347E8fa585"),
            Chain::Bnb => Some("0xB6F6D86a8f9879A9c87f643768d9efc38c1Da6E7"),
            Chain::Polygon => Some("0x5a58505a96D1dbf8dF91cB21B54419FC36e93fdE"),
            Chain::Arbitrum => Some("0x0b2402144Bb366A632D14B83F244D2e0e21bD39c"),
            Chain::Optimism => Some("0x1D68124e65faFC907325e3EDbF8c4d84499DAa8b"),
            Chain::Avalanche => Some("0x0e082F06FF657D94310cB8cE8B0D9a04541d8052"),
            Chain::Base => Some("0x8d2de8d2f73F1F4cAB472AC9A881C9b123C79627"),
            Chain::Fantom => Some("0x7C9Fc5741288cDFdD83CeB07f3ea7e22618D79D2"),
            _ => None,
        }
    }

    /// Get Core Bridge (wormhole) address for a chain
    pub fn core_bridge(chain: Chain) -> Option<&'static str> {
        match chain {
            Chain::Ethereum => Some("0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B"),
            Chain::Bnb => Some("0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B"),
            Chain::Polygon => Some("0x7A4B5a56256163F07b2C80A7cA55aBE66c4ec4d7"),
            Chain::Arbitrum => Some("0xa5f208e072434bC67592E4C49C1B991BA79BCA46"),
            Chain::Optimism => Some("0xEe91C335eab126dF5fDB3797EA9d6aD93aeC9722"),
            Chain::Avalanche => Some("0x54a8e5f9c4CbA08F9943965859F6c34eAF03E26c"),
            Chain::Base => Some("0xbebdb6C8ddC678FfA9f8748f85C815C556Dd8ac6"),
            Chain::Fantom => Some("0x126783A6Cb203a3E35344528B26ca3a0489a1485"),
            _ => None,
        }
    }

    /// Get NFT Bridge address for a chain
    pub fn nft_bridge(chain: Chain) -> Option<&'static str> {
        match chain {
            Chain::Ethereum => Some("0x6FFd7EdE62328b3Af38FCD61461Bbfc52F5651fE"),
            Chain::Bnb => Some("0x5a58505a96D1dbf8dF91cB21B54419FC36e93fdE"),
            Chain::Polygon => Some("0x90BBd86a6Fe93D3bc3ed6335935447E75fAb7fCf"),
            Chain::Arbitrum => Some("0x3dD14D553cFD986EAC8e3bddF629d82073e188c8"),
            Chain::Avalanche => Some("0xf7B6737Ca9c4e08aE573F75A97B73D7a813f5De5"),
            _ => None,
        }
    }
}

/// Wormhole bridge client
#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct WormholeClient {
    /// API key (optional for public endpoints)
    api_key: Option<String>,
}

impl WormholeClient {
    /// Create new Wormhole client
    pub fn new(api_key: Option<String>) -> Self {
        Self { api_key }
    }

    /// Check if a route is supported
    pub fn is_route_supported(source: Chain, destination: Chain) -> bool {
        WormholeChainId::from_chain(source).is_some() && 
        WormholeChainId::from_chain(destination).is_some() &&
        source != destination
    }

    /// Get a bridge quote
    pub fn get_quote(&self, request: &BridgeQuoteRequest) -> HawalaResult<BridgeQuote> {
        let source_id = WormholeChainId::from_chain(request.source_chain)
            .ok_or_else(|| HawalaError::invalid_input(format!(
                "Source chain {:?} not supported by Wormhole", request.source_chain
            )))?;

        let dest_id = WormholeChainId::from_chain(request.destination_chain)
            .ok_or_else(|| HawalaError::invalid_input(format!(
                "Destination chain {:?} not supported by Wormhole", request.destination_chain
            )))?;

        // For now, return a mock quote
        // In production, this would call the Wormhole SDK or API
        let amount_in: u128 = request.amount.parse().unwrap_or(0);
        
        // Wormhole typically has very low fees (0.01-0.1%)
        let bridge_fee = amount_in / 10000; // 0.01%
        let amount_out = amount_in - bridge_fee;
        let slippage_amount = (amount_out as f64 * request.slippage / 100.0) as u128;
        let amount_out_min = amount_out - slippage_amount;

        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let estimated_time = BridgeProvider::Wormhole.average_transfer_time(
            request.source_chain,
            request.destination_chain,
        );

        Ok(BridgeQuote {
            id: format!("wormhole-{}-{}", now, source_id.value()),
            provider: BridgeProvider::Wormhole,
            source_chain: request.source_chain,
            destination_chain: request.destination_chain,
            token: request.token.clone(),
            token_symbol: self.get_token_symbol(&request.token),
            amount_in: request.amount.clone(),
            amount_out: amount_out.to_string(),
            amount_out_min: amount_out_min.to_string(),
            bridge_fee: bridge_fee.to_string(),
            bridge_fee_usd: Some(self.estimate_fee_usd(bridge_fee, &request.token)),
            source_gas_usd: Some(self.estimate_gas_usd(request.source_chain)),
            destination_gas_usd: Some(self.estimate_gas_usd(request.destination_chain)),
            total_fee_usd: Some(
                self.estimate_fee_usd(bridge_fee, &request.token) +
                self.estimate_gas_usd(request.source_chain) +
                self.estimate_gas_usd(request.destination_chain)
            ),
            estimated_time_minutes: estimated_time,
            exchange_rate: amount_out as f64 / amount_in as f64,
            price_impact: Some(0.01), // Wormhole has minimal price impact
            expires_at: now + 300, // 5 minutes
            transaction: Some(self.build_transaction(request, source_id, dest_id)?),
        })
    }

    /// Build bridge transaction
    fn build_transaction(
        &self,
        request: &BridgeQuoteRequest,
        _source_id: WormholeChainId,
        dest_id: WormholeChainId,
    ) -> HawalaResult<BridgeTransaction> {
        let token_bridge = WormholeAddresses::token_bridge(request.source_chain)
            .ok_or_else(|| HawalaError::invalid_input(
                "Token bridge not available for source chain".to_string()
            ))?;

        let chain_id = request.source_chain.chain_id().unwrap_or(1);

        // Build mock transaction data
        // In production, this would encode the actual Wormhole bridge call
        let calldata = format!(
            "0x{}{}{}{}",
            "c0200f33", // transferTokens function selector
            format!("{:064x}", dest_id.value()), // recipient chain
            self.pad_address(&request.recipient), // recipient address (32 bytes)
            self.pad_amount(&request.amount), // amount (32 bytes)
        );

        Ok(BridgeTransaction {
            to: token_bridge.to_string(),
            data: calldata,
            value: if request.is_native_token() { request.amount.clone() } else { "0".to_string() },
            gas_limit: "300000".to_string(),
            gas_price: None,
            max_fee_per_gas: Some("50000000000".to_string()), // 50 gwei
            max_priority_fee_per_gas: Some("2000000000".to_string()), // 2 gwei
            chain_id,
        })
    }

    /// Track a VAA (Verified Action Approval)
    pub fn track_vaa(&self, tx_hash: &str, source_chain: Chain) -> HawalaResult<BridgeTransfer> {
        let source_id = WormholeChainId::from_chain(source_chain)
            .ok_or_else(|| HawalaError::invalid_input(format!(
                "Chain {:?} not supported", source_chain
            )))?;

        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        // Mock transfer tracking
        // In production, this would query Wormhole API for VAA status
        Ok(BridgeTransfer {
            id: format!("wh-{}", tx_hash),
            provider: BridgeProvider::Wormhole,
            source_chain,
            destination_chain: Chain::Solana, // Placeholder
            token_symbol: "USDC".to_string(),
            amount_in: "1000000".to_string(),
            amount_out: "999900".to_string(),
            source_tx_hash: tx_hash.to_string(),
            destination_tx_hash: None,
            status: BridgeStatus::InTransit,
            initiated_at: now - 300,
            completed_at: None,
            estimated_completion: now + 600,
            tracking_data: Some(serde_json::json!({
                "emitter_chain": source_id.value(),
                "vaa_status": "pending",
            })),
        })
    }

    /// Get VAA by transaction hash
    pub fn get_vaa(&self, _tx_hash: &str, _source_chain: Chain) -> HawalaResult<String> {
        // Mock VAA retrieval
        // In production, this would fetch the actual VAA bytes
        Ok(format!("0x{}", "00".repeat(100)))
    }

    // Helper methods

    fn get_token_symbol(&self, token: &str) -> String {
        if token.eq_ignore_ascii_case(BridgeQuoteRequest::NATIVE) {
            "ETH".to_string()
        } else {
            // In production, look up token symbol from address
            "TOKEN".to_string()
        }
    }

    fn estimate_fee_usd(&self, fee_amount: u128, _token: &str) -> f64 {
        // Mock USD conversion
        // In production, use price oracle
        (fee_amount as f64) / 1e18 * 2500.0 // Assuming ETH price
    }

    fn estimate_gas_usd(&self, chain: Chain) -> f64 {
        match chain {
            Chain::Ethereum => 10.0,
            Chain::Bnb => 0.50,
            Chain::Polygon => 0.10,
            Chain::Arbitrum => 0.50,
            Chain::Optimism => 0.30,
            Chain::Avalanche => 0.50,
            Chain::Base => 0.20,
            Chain::Solana => 0.01,
            _ => 1.0,
        }
    }

    fn pad_address(&self, address: &str) -> String {
        let addr = address.trim_start_matches("0x");
        format!("{:0>64}", addr)
    }

    fn pad_amount(&self, amount: &str) -> String {
        let val: u128 = amount.parse().unwrap_or(0);
        format!("{:064x}", val)
    }
}

/// Supported token list for Wormhole
pub struct WormholeTokens;

impl WormholeTokens {
    /// USDC wrapped addresses by chain
    pub fn usdc(chain: Chain) -> Option<&'static str> {
        match chain {
            Chain::Ethereum => Some("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"),
            Chain::Bnb => Some("0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d"),
            Chain::Polygon => Some("0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174"),
            Chain::Arbitrum => Some("0xaf88d065e77c8cC2239327C5EDb3A432268e5831"),
            Chain::Optimism => Some("0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85"),
            Chain::Avalanche => Some("0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E"),
            Chain::Base => Some("0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"),
            _ => None,
        }
    }

    /// WETH wrapped addresses by chain
    pub fn weth(chain: Chain) -> Option<&'static str> {
        match chain {
            Chain::Ethereum => Some("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"),
            Chain::Arbitrum => Some("0x82aF49447D8a07e3bd95BD0d56f35241523fBab1"),
            Chain::Optimism => Some("0x4200000000000000000000000000000000000006"),
            Chain::Base => Some("0x4200000000000000000000000000000000000006"),
            Chain::Polygon => Some("0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619"),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_wormhole_chain_ids() {
        assert_eq!(WormholeChainId::from_chain(Chain::Ethereum), Some(WormholeChainId::Ethereum));
        assert_eq!(WormholeChainId::from_chain(Chain::Solana), Some(WormholeChainId::Solana));
        assert_eq!(WormholeChainId::from_chain(Chain::Arbitrum), Some(WormholeChainId::Arbitrum));
        assert!(WormholeChainId::from_chain(Chain::Bitcoin).is_none());
    }

    #[test]
    fn test_route_support() {
        assert!(WormholeClient::is_route_supported(Chain::Ethereum, Chain::Solana));
        assert!(WormholeClient::is_route_supported(Chain::Polygon, Chain::Arbitrum));
        assert!(!WormholeClient::is_route_supported(Chain::Bitcoin, Chain::Ethereum));
        assert!(!WormholeClient::is_route_supported(Chain::Ethereum, Chain::Ethereum));
    }

    #[test]
    fn test_get_quote() {
        let client = WormholeClient::new(None);
        let request = BridgeQuoteRequest {
            source_chain: Chain::Ethereum,
            destination_chain: Chain::Arbitrum,
            token: BridgeQuoteRequest::NATIVE.to_string(),
            amount: "1000000000000000000".to_string(), // 1 ETH
            sender: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
            recipient: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
            slippage: 0.5,
            provider: Some(BridgeProvider::Wormhole),
        };

        let quote = client.get_quote(&request).unwrap();
        assert_eq!(quote.provider, BridgeProvider::Wormhole);
        assert_eq!(quote.source_chain, Chain::Ethereum);
        assert_eq!(quote.destination_chain, Chain::Arbitrum);
        assert!(quote.transaction.is_some());
        assert!(quote.is_valid());
    }

    #[test]
    fn test_token_addresses() {
        assert!(WormholeTokens::usdc(Chain::Ethereum).is_some());
        assert!(WormholeTokens::weth(Chain::Arbitrum).is_some());
        assert!(WormholeTokens::usdc(Chain::Bitcoin).is_none());
    }

    #[test]
    fn test_bridge_addresses() {
        assert!(WormholeAddresses::token_bridge(Chain::Ethereum).is_some());
        assert!(WormholeAddresses::core_bridge(Chain::Polygon).is_some());
        assert!(WormholeAddresses::token_bridge(Chain::Bitcoin).is_none());
    }
}
