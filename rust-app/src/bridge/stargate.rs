//! Stargate Finance bridge integration
//!
//! Stargate is a composable liquidity protocol that enables cross-chain
//! native asset transfers with unified liquidity pools.

use crate::error::{HawalaError, HawalaResult};
use crate::types::Chain;
use super::types::*;

/// Stargate pool IDs
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(non_camel_case_types)]
pub enum StargatePoolId {
    USDC = 1,
    USDT = 2,
    DAI = 3,
    FRAX = 7,
    USDD = 11,
    ETH = 13,
    sUSD = 14,
    LUSD = 15,
    MAI = 16,
    METIS = 17,
    metisUSDT = 19,
}

impl StargatePoolId {
    /// Get pool ID for a token symbol
    pub fn from_symbol(symbol: &str) -> Option<Self> {
        match symbol.to_uppercase().as_str() {
            "USDC" => Some(Self::USDC),
            "USDT" => Some(Self::USDT),
            "DAI" => Some(Self::DAI),
            "FRAX" => Some(Self::FRAX),
            "ETH" | "WETH" | "SGETH" => Some(Self::ETH),
            "SUSD" => Some(Self::sUSD),
            "LUSD" => Some(Self::LUSD),
            "MAI" | "MIMATIC" => Some(Self::MAI),
            _ => None,
        }
    }

    /// Get pool ID value
    pub fn id(&self) -> u16 {
        *self as u16
    }
}

/// Stargate chain IDs (same as LayerZero)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StargateChainId {
    Ethereum = 101,
    BnbChain = 102,
    Avalanche = 106,
    Polygon = 109,
    Arbitrum = 110,
    Optimism = 111,
    Fantom = 112,
    Base = 184,
    Linea = 183,
    Kava = 177,
    Scroll = 214,
    Mantle = 181,
}

impl StargateChainId {
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
            _ => None,
        }
    }

    /// Get chain ID value
    pub fn id(&self) -> u16 {
        *self as u16
    }
}

/// Stargate router addresses
pub struct StargateAddresses;

impl StargateAddresses {
    /// Get Router address for a chain
    pub fn router(chain: Chain) -> Option<&'static str> {
        match chain {
            Chain::Ethereum => Some("0x8731d54E9D02c286767d56ac03e8037C07e01e98"),
            Chain::Bnb => Some("0x4a364f8c717cAAD9A442737Eb7b8A55cc6cf18D8"),
            Chain::Polygon => Some("0x45A01E4e04F14f7A4a6702c74187c5F6222033cd"),
            Chain::Arbitrum => Some("0x53Bf833A5d6c4ddA888F69c22C88C9f356a41614"),
            Chain::Optimism => Some("0xB0D502E938ed5f4df2E681fE6E419ff29631d62b"),
            Chain::Avalanche => Some("0x45A01E4e04F14f7A4a6702c74187c5F6222033cd"),
            Chain::Base => Some("0x45f1A95A4D3f3836523F5c83673c797f4d4d263B"),
            Chain::Fantom => Some("0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6"),
            _ => None,
        }
    }

    /// Get Router ETH address for native ETH bridging
    pub fn router_eth(chain: Chain) -> Option<&'static str> {
        match chain {
            Chain::Ethereum => Some("0x150f94B44927F078737562f0fcF3C95c01Cc2376"),
            Chain::Arbitrum => Some("0xbf22f0f184bCcbeA268dF387a49fF5238dD23E40"),
            Chain::Optimism => Some("0xB49c4e680174E331CB0A7fF3Ab58afC9738d5F8b"),
            Chain::Base => Some("0x50B6EbC2103BbfE15B0E06E45fB8F0C3e3F6Bbb0"),
            _ => None,
        }
    }

    /// Get Factory address for a chain
    pub fn factory(chain: Chain) -> Option<&'static str> {
        match chain {
            Chain::Ethereum => Some("0x06D538690AF257Da524f25D0CD52fD85b1c2173E"),
            Chain::Arbitrum => Some("0x55bDb4164D28FBaF0898e0eF14a589ac09Ac9970"),
            Chain::Optimism => Some("0xE3B53AF74a4BF62Ae5511055290838050bf764Df"),
            _ => None,
        }
    }
}

/// Stargate bridge client
#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct StargateClient {
    /// API endpoint for quotes
    api_endpoint: String,
}

impl StargateClient {
    /// Create new Stargate client
    pub fn new() -> Self {
        Self {
            api_endpoint: "https://api.stargate.finance".to_string(),
        }
    }

    /// Check if route is supported
    pub fn is_route_supported(source: Chain, destination: Chain, token: &str) -> bool {
        // Stargate only supports specific tokens
        let pool_id = StargatePoolId::from_symbol(token);
        
        StargateChainId::from_chain(source).is_some() &&
        StargateChainId::from_chain(destination).is_some() &&
        pool_id.is_some() &&
        source != destination
    }

    /// Get supported tokens for bridging
    pub fn supported_tokens() -> Vec<&'static str> {
        vec!["USDC", "USDT", "DAI", "ETH", "FRAX", "LUSD", "MAI"]
    }

    /// Get a bridge quote
    pub fn get_quote(&self, request: &BridgeQuoteRequest) -> HawalaResult<BridgeQuote> {
        let source_id = StargateChainId::from_chain(request.source_chain)
            .ok_or_else(|| HawalaError::invalid_input(format!(
                "Source chain {:?} not supported by Stargate", request.source_chain
            )))?;

        let dest_id = StargateChainId::from_chain(request.destination_chain)
            .ok_or_else(|| HawalaError::invalid_input(format!(
                "Destination chain {:?} not supported by Stargate", request.destination_chain
            )))?;

        let token_symbol = self.get_token_symbol(&request.token);
        let _pool_id = StargatePoolId::from_symbol(&token_symbol)
            .ok_or_else(|| HawalaError::invalid_input(format!(
                "Token {} not supported by Stargate", token_symbol
            )))?;

        let amount_in: u128 = request.amount.parse().unwrap_or(0);
        
        // Stargate fees: ~0.06% protocol fee + gas
        let protocol_fee_bps = 6; // 0.06%
        let protocol_fee = amount_in * protocol_fee_bps / 10000;
        
        // Equilibrium fee depends on pool balance (can be 0 or even negative/bonus)
        // For simplicity, assume 0 equilibrium fee
        let equilibrium_fee = 0u128;
        
        let total_fee = protocol_fee + equilibrium_fee;
        let amount_out = amount_in - total_fee;
        let slippage_amount = (amount_out as f64 * request.slippage / 100.0) as u128;
        let amount_out_min = amount_out - slippage_amount;

        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let estimated_time = BridgeProvider::Stargate.average_transfer_time(
            request.source_chain,
            request.destination_chain,
        );

        let lz_fee = self.estimate_lz_fee(request.source_chain, request.destination_chain);
        let gas_usd = self.estimate_gas_usd(request.source_chain);

        Ok(BridgeQuote {
            id: format!("stargate-{}-{}", now, source_id.id()),
            provider: BridgeProvider::Stargate,
            source_chain: request.source_chain,
            destination_chain: request.destination_chain,
            token: request.token.clone(),
            token_symbol,
            amount_in: request.amount.clone(),
            amount_out: amount_out.to_string(),
            amount_out_min: amount_out_min.to_string(),
            bridge_fee: total_fee.to_string(),
            bridge_fee_usd: Some(self.token_to_usd(total_fee, &request.token)),
            source_gas_usd: Some(gas_usd + self.wei_to_usd(lz_fee, request.source_chain)),
            destination_gas_usd: Some(0.0), // Covered by LZ fee
            total_fee_usd: Some(
                self.token_to_usd(total_fee, &request.token) +
                gas_usd +
                self.wei_to_usd(lz_fee, request.source_chain)
            ),
            estimated_time_minutes: estimated_time,
            exchange_rate: amount_out as f64 / amount_in as f64,
            price_impact: Some(protocol_fee_bps as f64 / 100.0),
            expires_at: now + 300,
            transaction: Some(self.build_swap_transaction(request, source_id, dest_id)?),
        })
    }

    /// Build swap transaction
    fn build_swap_transaction(
        &self,
        request: &BridgeQuoteRequest,
        _source_id: StargateChainId,
        dest_id: StargateChainId,
    ) -> HawalaResult<BridgeTransaction> {
        let token_symbol = self.get_token_symbol(&request.token);
        let is_native_eth = token_symbol.eq_ignore_ascii_case("ETH");
        
        let router = if is_native_eth {
            StargateAddresses::router_eth(request.source_chain)
        } else {
            StargateAddresses::router(request.source_chain)
        }.ok_or_else(|| HawalaError::invalid_input(
            "Router not available for source chain".to_string()
        ))?;

        let chain_id = request.source_chain.chain_id().unwrap_or(1);
        let lz_fee = self.estimate_lz_fee(request.source_chain, request.destination_chain);

        let pool_id = StargatePoolId::from_symbol(&token_symbol)
            .map(|p| p.id())
            .unwrap_or(1);

        // Build swap calldata
        // function swap(uint16 _dstChainId, uint256 _srcPoolId, uint256 _dstPoolId, 
        //               address _refundAddress, uint256 _amountLD, uint256 _minAmountLD, ...)
        let calldata = format!(
            "0x{}{}{}{}{}{}{}",
            "9fbf10fc", // swap function selector
            format!("{:064x}", dest_id.id() as u64), // destination chain id
            format!("{:064x}", pool_id as u64), // source pool id
            format!("{:064x}", pool_id as u64), // destination pool id (same for same token)
            self.pad_address(&request.sender), // refund address
            self.pad_amount(&request.amount), // amount
            self.pad_amount(&self.calculate_min_amount(&request.amount, request.slippage)), // min amount
        );

        Ok(BridgeTransaction {
            to: router.to_string(),
            data: calldata,
            value: if is_native_eth { 
                (request.amount.parse::<u128>().unwrap_or(0) + lz_fee).to_string()
            } else { 
                lz_fee.to_string()
            },
            gas_limit: "500000".to_string(),
            gas_price: None,
            max_fee_per_gas: Some("50000000000".to_string()),
            max_priority_fee_per_gas: Some("2000000000".to_string()),
            chain_id,
        })
    }

    /// Estimate LayerZero messaging fee
    fn estimate_lz_fee(&self, source: Chain, destination: Chain) -> u128 {
        // Similar to LayerZero, varies by route
        match (source, destination) {
            (Chain::Ethereum, _) => 3_000_000_000_000_000, // ~0.003 ETH
            (_, Chain::Ethereum) => 8_000_000_000_000_000, // ~0.008 ETH
            (Chain::Arbitrum, _) | (_, Chain::Arbitrum) => 300_000_000_000_000,
            (Chain::Optimism, _) | (_, Chain::Optimism) => 300_000_000_000_000,
            (Chain::Base, _) | (_, Chain::Base) => 200_000_000_000_000,
            _ => 500_000_000_000_000,
        }
    }

    /// Track a Stargate transfer
    pub fn track_transfer(&self, tx_hash: &str, source_chain: Chain) -> HawalaResult<BridgeTransfer> {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        Ok(BridgeTransfer {
            id: format!("sg-{}", tx_hash),
            provider: BridgeProvider::Stargate,
            source_chain,
            destination_chain: Chain::Arbitrum, // Placeholder
            token_symbol: "USDC".to_string(),
            amount_in: "1000000".to_string(),
            amount_out: "999400".to_string(), // After 0.06% fee
            source_tx_hash: tx_hash.to_string(),
            destination_tx_hash: None,
            status: BridgeStatus::InTransit,
            initiated_at: now - 60,
            completed_at: None,
            estimated_completion: now + 60, // Stargate is fast
            tracking_data: Some(serde_json::json!({
                "stargate_status": "pending",
            })),
        })
    }

    // Helper methods

    fn get_token_symbol(&self, token: &str) -> String {
        if token.eq_ignore_ascii_case(BridgeQuoteRequest::NATIVE) {
            "ETH".to_string()
        } else if token.len() <= 10 {
            token.to_uppercase()
        } else {
            // Try to identify by address
            "USDC".to_string() // Default
        }
    }

    fn token_to_usd(&self, amount: u128, token: &str) -> f64 {
        let symbol = self.get_token_symbol(token);
        let decimals: u32 = match symbol.as_str() {
            "USDC" | "USDT" => 6,
            "DAI" | "ETH" | "FRAX" | "LUSD" => 18,
            _ => 18,
        };
        let price = match symbol.as_str() {
            "USDC" | "USDT" | "DAI" | "FRAX" | "LUSD" => 1.0,
            "ETH" => 2500.0,
            _ => 1.0,
        };
        (amount as f64 / 10f64.powi(decimals as i32)) * price
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
            Chain::Ethereum => 12.0,
            Chain::Bnb => 0.40,
            Chain::Polygon => 0.08,
            Chain::Arbitrum => 0.50,
            Chain::Optimism => 0.30,
            Chain::Avalanche => 0.50,
            Chain::Base => 0.20,
            Chain::Fantom => 0.08,
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

    fn calculate_min_amount(&self, amount: &str, slippage: f64) -> String {
        let val: u128 = amount.parse().unwrap_or(0);
        let min = val - (val as f64 * slippage / 100.0) as u128;
        min.to_string()
    }
}

impl Default for StargateClient {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_chain_ids() {
        assert_eq!(StargateChainId::from_chain(Chain::Ethereum), Some(StargateChainId::Ethereum));
        assert_eq!(StargateChainId::from_chain(Chain::Arbitrum), Some(StargateChainId::Arbitrum));
        assert!(StargateChainId::from_chain(Chain::Bitcoin).is_none());
    }

    #[test]
    fn test_pool_ids() {
        assert_eq!(StargatePoolId::from_symbol("USDC"), Some(StargatePoolId::USDC));
        assert_eq!(StargatePoolId::from_symbol("eth"), Some(StargatePoolId::ETH));
        assert_eq!(StargatePoolId::from_symbol("DAI"), Some(StargatePoolId::DAI));
        assert!(StargatePoolId::from_symbol("BTC").is_none());
    }

    #[test]
    fn test_route_support() {
        assert!(StargateClient::is_route_supported(Chain::Ethereum, Chain::Arbitrum, "USDC"));
        assert!(StargateClient::is_route_supported(Chain::Polygon, Chain::Optimism, "usdt"));
        assert!(!StargateClient::is_route_supported(Chain::Ethereum, Chain::Arbitrum, "BTC"));
        assert!(!StargateClient::is_route_supported(Chain::Bitcoin, Chain::Ethereum, "USDC"));
    }

    #[test]
    fn test_get_quote() {
        let client = StargateClient::new();
        let request = BridgeQuoteRequest {
            source_chain: Chain::Ethereum,
            destination_chain: Chain::Arbitrum,
            token: "USDC".to_string(),
            amount: "1000000000".to_string(), // 1000 USDC (6 decimals)
            sender: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
            recipient: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb2".to_string(),
            slippage: 0.5,
            provider: Some(BridgeProvider::Stargate),
        };

        let quote = client.get_quote(&request).unwrap();
        assert_eq!(quote.provider, BridgeProvider::Stargate);
        assert!(quote.transaction.is_some());
        
        // Check fee calculation (0.06%)
        let amount_in: u128 = quote.amount_in.parse().unwrap();
        let amount_out: u128 = quote.amount_out.parse().unwrap();
        let fee_percent = ((amount_in - amount_out) as f64 / amount_in as f64) * 100.0;
        assert!(fee_percent < 0.1); // Should be around 0.06%
    }

    #[test]
    fn test_router_addresses() {
        assert!(StargateAddresses::router(Chain::Ethereum).is_some());
        assert!(StargateAddresses::router(Chain::Arbitrum).is_some());
        assert!(StargateAddresses::router_eth(Chain::Ethereum).is_some());
        assert!(StargateAddresses::router(Chain::Bitcoin).is_none());
    }

    #[test]
    fn test_supported_tokens() {
        let tokens = StargateClient::supported_tokens();
        assert!(tokens.contains(&"USDC"));
        assert!(tokens.contains(&"ETH"));
        assert!(!tokens.contains(&"BTC"));
    }
}
