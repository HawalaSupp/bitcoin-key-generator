//! LayerZero bridge integration
//!
//! LayerZero is an omnichain interoperability protocol that enables
//! cross-chain messaging and token transfers via OFT (Omnichain Fungible Token).

use crate::error::{HawalaError, HawalaResult};
use crate::types::Chain;
use super::types::*;

/// LayerZero endpoint IDs
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(non_camel_case_types)]
pub enum LayerZeroEndpointId {
    Ethereum = 101,
    BnbChain = 102,
    Avalanche = 106,
    Polygon = 109,
    Arbitrum = 110,
    Optimism = 111,
    Fantom = 112,
    Swimmer = 114,
    Dfk = 115,
    Harmony = 116,
    Dexalot = 118,
    Celo = 125,
    Moonbeam = 126,
    Fuse = 138,
    Gnosis = 145,
    Klaytn = 150,
    Metis = 151,
    CoreDao = 153,
    Canto = 159,
    zkSync = 165,
    Tenet = 173,
    Astar = 210,
    zkEvm = 158,
    Linea = 183,
    Base = 184,
    Scroll = 214,
    Mantle = 181,
    Blast = 243,
}

impl LayerZeroEndpointId {
    /// Convert from our Chain type
    pub fn from_chain(chain: Chain) -> Option<Self> {
        match chain {
            Chain::Ethereum => Some(Self::Ethereum),
            Chain::Bnb => Some(Self::BnbChain),
            Chain::Polygon => Some(Self::Polygon),
            Chain::Arbitrum => Some(Self::Arbitrum),
            Chain::Optimism => Some(Self::Optimism),
            Chain::Avalanche => Some(Self::Avalanche),
            Chain::Base => Some(Self::Base),
            Chain::Fantom => Some(Self::Fantom),
            // Add more chains as supported
            _ => None,
        }
    }

    /// Get numeric endpoint ID
    pub fn id(&self) -> u16 {
        *self as u16
    }
}

/// LayerZero endpoint addresses
pub struct LayerZeroEndpoints;

impl LayerZeroEndpoints {
    /// Get LayerZero endpoint address for a chain
    pub fn endpoint(chain: Chain) -> Option<&'static str> {
        match chain {
            Chain::Ethereum => Some("0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675"),
            Chain::Bnb => Some("0x3c2269811836af69497E5F486A85D7316753cf62"),
            Chain::Polygon => Some("0x3c2269811836af69497E5F486A85D7316753cf62"),
            Chain::Arbitrum => Some("0x3c2269811836af69497E5F486A85D7316753cf62"),
            Chain::Optimism => Some("0x3c2269811836af69497E5F486A85D7316753cf62"),
            Chain::Avalanche => Some("0x3c2269811836af69497E5F486A85D7316753cf62"),
            Chain::Base => Some("0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7"),
            Chain::Fantom => Some("0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7"),
            _ => None,
        }
    }

    /// Get Ultra Light Node (ULN) address for a chain
    pub fn uln(chain: Chain) -> Option<&'static str> {
        match chain {
            Chain::Ethereum => Some("0x4D73AdB72bC3DD368966edD0f0b2148401A178E2"),
            Chain::Bnb => Some("0x4D73AdB72bC3DD368966edD0f0b2148401A178E2"),
            Chain::Polygon => Some("0x4D73AdB72bC3DD368966edD0f0b2148401A178E2"),
            Chain::Arbitrum => Some("0x4D73AdB72bC3DD368966edD0f0b2148401A178E2"),
            Chain::Optimism => Some("0x4D73AdB72bC3DD368966edD0f0b2148401A178E2"),
            Chain::Avalanche => Some("0x4D73AdB72bC3DD368966edD0f0b2148401A178E2"),
            _ => None,
        }
    }
}

/// LayerZero bridge client
#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct LayerZeroClient {
    /// API key for enhanced rate limits
    api_key: Option<String>,
}

impl LayerZeroClient {
    /// Create new LayerZero client
    pub fn new(api_key: Option<String>) -> Self {
        Self { api_key }
    }

    /// Check if a route is supported
    pub fn is_route_supported(source: Chain, destination: Chain) -> bool {
        LayerZeroEndpointId::from_chain(source).is_some() &&
        LayerZeroEndpointId::from_chain(destination).is_some() &&
        source != destination
    }

    /// Get supported chains
    pub fn supported_chains() -> Vec<Chain> {
        vec![
            Chain::Ethereum,
            Chain::Bnb,
            Chain::Polygon,
            Chain::Arbitrum,
            Chain::Optimism,
            Chain::Avalanche,
            Chain::Base,
            Chain::Fantom,
        ]
    }

    /// Get a bridge quote for OFT transfer
    pub fn get_quote(&self, request: &BridgeQuoteRequest) -> HawalaResult<BridgeQuote> {
        let source_id = LayerZeroEndpointId::from_chain(request.source_chain)
            .ok_or_else(|| HawalaError::invalid_input(format!(
                "Source chain {:?} not supported by LayerZero", request.source_chain
            )))?;

        let dest_id = LayerZeroEndpointId::from_chain(request.destination_chain)
            .ok_or_else(|| HawalaError::invalid_input(format!(
                "Destination chain {:?} not supported by LayerZero", request.destination_chain
            )))?;

        let amount_in: u128 = request.amount.parse().unwrap_or(0);
        
        // LayerZero OFT typically has minimal fees (gas only)
        // The actual bridge fee is just the destination gas payment
        let bridge_fee = self.estimate_messaging_fee(request.source_chain, request.destination_chain);
        let amount_out = amount_in; // OFT is 1:1
        let slippage_amount = (amount_out as f64 * request.slippage / 100.0) as u128;
        let amount_out_min = amount_out - slippage_amount;

        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let estimated_time = BridgeProvider::LayerZero.average_transfer_time(
            request.source_chain,
            request.destination_chain,
        );

        Ok(BridgeQuote {
            id: format!("lz-{}-{}", now, source_id.id()),
            provider: BridgeProvider::LayerZero,
            source_chain: request.source_chain,
            destination_chain: request.destination_chain,
            token: request.token.clone(),
            token_symbol: self.get_token_symbol(&request.token),
            amount_in: request.amount.clone(),
            amount_out: amount_out.to_string(),
            amount_out_min: amount_out_min.to_string(),
            bridge_fee: bridge_fee.to_string(),
            bridge_fee_usd: Some(self.wei_to_usd(bridge_fee, request.source_chain)),
            source_gas_usd: Some(self.estimate_gas_usd(request.source_chain)),
            destination_gas_usd: Some(0.0), // Prepaid in bridge fee
            total_fee_usd: Some(
                self.wei_to_usd(bridge_fee, request.source_chain) +
                self.estimate_gas_usd(request.source_chain)
            ),
            estimated_time_minutes: estimated_time,
            exchange_rate: 1.0, // OFT is always 1:1
            price_impact: Some(0.0), // No price impact for OFT
            expires_at: now + 300,
            transaction: Some(self.build_oft_transaction(request, source_id, dest_id)?),
        })
    }

    /// Estimate messaging fee for cross-chain message
    fn estimate_messaging_fee(&self, source: Chain, destination: Chain) -> u128 {
        // Base fee varies by route
        // These are approximate values in wei
        match (source, destination) {
            (Chain::Ethereum, _) => 5_000_000_000_000_000, // ~0.005 ETH
            (_, Chain::Ethereum) => 10_000_000_000_000_000, // ~0.01 ETH (more expensive to ETH)
            (Chain::Arbitrum, _) | (_, Chain::Arbitrum) => 500_000_000_000_000, // ~0.0005 ETH
            (Chain::Optimism, _) | (_, Chain::Optimism) => 500_000_000_000_000,
            (Chain::Base, _) | (_, Chain::Base) => 300_000_000_000_000,
            (Chain::Polygon, _) | (_, Chain::Polygon) => 1_000_000_000_000_000_000, // 1 MATIC
            (Chain::Bnb, _) | (_, Chain::Bnb) => 5_000_000_000_000_000, // 0.005 BNB
            _ => 1_000_000_000_000_000, // Default ~0.001 ETH
        }
    }

    /// Build OFT transfer transaction
    fn build_oft_transaction(
        &self,
        request: &BridgeQuoteRequest,
        _source_id: LayerZeroEndpointId,
        dest_id: LayerZeroEndpointId,
    ) -> HawalaResult<BridgeTransaction> {
        let chain_id = request.source_chain.chain_id().unwrap_or(1);
        let messaging_fee = self.estimate_messaging_fee(request.source_chain, request.destination_chain);

        // Build sendFrom calldata for OFT
        // function sendFrom(address _from, uint16 _dstChainId, bytes32 _toAddress, uint _amount, ...)
        let calldata = format!(
            "0x{}{}{}{}{}",
            "51905636", // sendFrom function selector
            self.pad_address(&request.sender), // from address
            format!("{:064x}", dest_id.id() as u64), // destination chain id
            self.pad_address(&request.recipient), // recipient as bytes32
            self.pad_amount(&request.amount), // amount
        );

        Ok(BridgeTransaction {
            to: request.token.clone(), // OFT contract is the token itself
            data: calldata,
            value: messaging_fee.to_string(), // Native token for messaging fee
            gas_limit: "250000".to_string(),
            gas_price: None,
            max_fee_per_gas: Some("50000000000".to_string()),
            max_priority_fee_per_gas: Some("2000000000".to_string()),
            chain_id,
        })
    }

    /// Track a LayerZero message
    pub fn track_message(&self, tx_hash: &str, source_chain: Chain) -> HawalaResult<BridgeTransfer> {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        // Mock transfer tracking
        // In production, this would query LayerZero Scan API
        Ok(BridgeTransfer {
            id: format!("lz-{}", tx_hash),
            provider: BridgeProvider::LayerZero,
            source_chain,
            destination_chain: Chain::Arbitrum, // Placeholder
            token_symbol: "USDC".to_string(),
            amount_in: "1000000".to_string(),
            amount_out: "1000000".to_string(),
            source_tx_hash: tx_hash.to_string(),
            destination_tx_hash: None,
            status: BridgeStatus::InTransit,
            initiated_at: now - 120,
            completed_at: None,
            estimated_completion: now + 180,
            tracking_data: Some(serde_json::json!({
                "lz_status": "INFLIGHT",
                "src_chain_id": LayerZeroEndpointId::from_chain(source_chain).map(|e| e.id()),
            })),
        })
    }

    // Helper methods

    fn get_token_symbol(&self, token: &str) -> String {
        if token.eq_ignore_ascii_case(BridgeQuoteRequest::NATIVE) {
            "ETH".to_string()
        } else {
            "TOKEN".to_string()
        }
    }

    fn wei_to_usd(&self, wei: u128, chain: Chain) -> f64 {
        let native_price = match chain {
            Chain::Ethereum | Chain::Arbitrum | Chain::Optimism | Chain::Base => 2500.0,
            Chain::Bnb => 300.0,
            Chain::Polygon => 0.80,
            Chain::Avalanche => 35.0,
            Chain::Fantom => 0.50,
            _ => 1.0,
        };
        (wei as f64 / 1e18) * native_price
    }

    fn estimate_gas_usd(&self, chain: Chain) -> f64 {
        match chain {
            Chain::Ethereum => 8.0,
            Chain::Bnb => 0.30,
            Chain::Polygon => 0.05,
            Chain::Arbitrum => 0.40,
            Chain::Optimism => 0.25,
            Chain::Avalanche => 0.40,
            Chain::Base => 0.15,
            Chain::Fantom => 0.05,
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

/// Common OFT tokens on LayerZero
pub struct LayerZeroTokens;

impl LayerZeroTokens {
    /// USDC.e (bridged USDC via LayerZero)
    pub fn usdc_e(chain: Chain) -> Option<&'static str> {
        match chain {
            Chain::Ethereum => Some("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"),
            Chain::Arbitrum => Some("0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8"),
            Chain::Optimism => Some("0x7F5c764cBc14f9669B88837ca1490cCa17c31607"),
            Chain::Avalanche => Some("0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664"),
            Chain::Polygon => Some("0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174"),
            _ => None,
        }
    }

    /// STG (Stargate Token) - native OFT
    pub fn stg(chain: Chain) -> Option<&'static str> {
        match chain {
            Chain::Ethereum => Some("0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6"),
            Chain::Bnb => Some("0xB0D502E938ed5f4df2E681fE6E419ff29631d62b"),
            Chain::Polygon => Some("0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590"),
            Chain::Arbitrum => Some("0x6694340fc020c5E6B96567843da2df01b2CE1eb6"),
            Chain::Optimism => Some("0x296F55F8Fb28E498B858d0BcDA06D955B2Cb3f97"),
            Chain::Avalanche => Some("0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590"),
            Chain::Base => Some("0xE3B53AF74a4BF62Ae5511055290838050bf764Df"),
            Chain::Fantom => Some("0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590"),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_endpoint_ids() {
        assert_eq!(LayerZeroEndpointId::from_chain(Chain::Ethereum), Some(LayerZeroEndpointId::Ethereum));
        assert_eq!(LayerZeroEndpointId::from_chain(Chain::Arbitrum), Some(LayerZeroEndpointId::Arbitrum));
        assert_eq!(LayerZeroEndpointId::from_chain(Chain::Base), Some(LayerZeroEndpointId::Base));
        assert!(LayerZeroEndpointId::from_chain(Chain::Bitcoin).is_none());
    }

    #[test]
    fn test_route_support() {
        assert!(LayerZeroClient::is_route_supported(Chain::Ethereum, Chain::Arbitrum));
        assert!(LayerZeroClient::is_route_supported(Chain::Polygon, Chain::Optimism));
        assert!(!LayerZeroClient::is_route_supported(Chain::Bitcoin, Chain::Ethereum));
        assert!(!LayerZeroClient::is_route_supported(Chain::Ethereum, Chain::Ethereum));
    }

    #[test]
    fn test_get_quote() {
        let client = LayerZeroClient::new(None);
        let request = BridgeQuoteRequest {
            source_chain: Chain::Ethereum,
            destination_chain: Chain::Arbitrum,
            token: "0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6".to_string(), // STG
            amount: "1000000000000000000".to_string(), // 1 token
            sender: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
            recipient: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
            slippage: 0.5,
            provider: Some(BridgeProvider::LayerZero),
        };

        let quote = client.get_quote(&request).unwrap();
        assert_eq!(quote.provider, BridgeProvider::LayerZero);
        assert_eq!(quote.exchange_rate, 1.0); // OFT is 1:1
        assert!(quote.transaction.is_some());
    }

    #[test]
    fn test_endpoints() {
        assert!(LayerZeroEndpoints::endpoint(Chain::Ethereum).is_some());
        assert!(LayerZeroEndpoints::endpoint(Chain::Base).is_some());
        assert!(LayerZeroEndpoints::endpoint(Chain::Bitcoin).is_none());
    }

    #[test]
    fn test_supported_chains() {
        let chains = LayerZeroClient::supported_chains();
        assert!(chains.contains(&Chain::Ethereum));
        assert!(chains.contains(&Chain::Arbitrum));
        assert!(!chains.contains(&Chain::Bitcoin));
    }
}
