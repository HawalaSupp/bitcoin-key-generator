//! Bridge types and data structures

use crate::types::Chain;
use serde::{Deserialize, Serialize};

/// Bridge provider enumeration
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum BridgeProvider {
    /// Wormhole - supports EVM, Solana, Cosmos, and more
    Wormhole,
    /// LayerZero - OFT and cross-chain messaging
    LayerZero,
    /// Stargate Finance - stablecoin bridging
    Stargate,
    /// Across Protocol - optimistic bridging
    Across,
    /// Hop Protocol - L2 bridging
    Hop,
    /// Synapse Protocol - cross-chain DEX bridge
    Synapse,
}

impl BridgeProvider {
    /// Get display name
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Wormhole => "Wormhole",
            Self::LayerZero => "LayerZero",
            Self::Stargate => "Stargate Finance",
            Self::Across => "Across Protocol",
            Self::Hop => "Hop Protocol",
            Self::Synapse => "Synapse Protocol",
        }
    }

    /// Get supported source chains
    pub fn supported_source_chains(&self) -> Vec<Chain> {
        match self {
            Self::Wormhole => vec![
                Chain::Ethereum,
                Chain::Bnb,
                Chain::Polygon,
                Chain::Arbitrum,
                Chain::Optimism,
                Chain::Avalanche,
                Chain::Base,
                Chain::Solana,
            ],
            Self::LayerZero => vec![
                Chain::Ethereum,
                Chain::Bnb,
                Chain::Polygon,
                Chain::Arbitrum,
                Chain::Optimism,
                Chain::Avalanche,
                Chain::Base,
                Chain::Fantom,
            ],
            Self::Stargate => vec![
                Chain::Ethereum,
                Chain::Bnb,
                Chain::Polygon,
                Chain::Arbitrum,
                Chain::Optimism,
                Chain::Avalanche,
                Chain::Base,
                Chain::Fantom,
            ],
            Self::Across => vec![
                Chain::Ethereum,
                Chain::Polygon,
                Chain::Arbitrum,
                Chain::Optimism,
                Chain::Base,
            ],
            Self::Hop => vec![
                Chain::Ethereum,
                Chain::Polygon,
                Chain::Arbitrum,
                Chain::Optimism,
                Chain::Base,
            ],
            Self::Synapse => vec![
                Chain::Ethereum,
                Chain::Bnb,
                Chain::Polygon,
                Chain::Arbitrum,
                Chain::Optimism,
                Chain::Avalanche,
                Chain::Fantom,
            ],
        }
    }

    /// Check if a route is supported
    pub fn supports_route(&self, source: Chain, destination: Chain) -> bool {
        let sources = self.supported_source_chains();
        sources.contains(&source) && sources.contains(&destination) && source != destination
    }

    /// Get average transfer time in minutes
    pub fn average_transfer_time(&self, source: Chain, destination: Chain) -> u32 {
        match self {
            Self::Wormhole => {
                // Wormhole requires finality on source chain
                match source {
                    Chain::Ethereum => 15,
                    Chain::Solana => 1,
                    _ => 5,
                }
            }
            Self::LayerZero => {
                // LayerZero is generally fast
                match (source, destination) {
                    (Chain::Ethereum, _) => 10,
                    (_, Chain::Ethereum) => 10,
                    _ => 3,
                }
            }
            Self::Stargate => 2, // Stargate is optimized for speed
            Self::Across => 2,   // Across uses optimistic verification
            Self::Hop => 5,      // Hop uses AMM model
            Self::Synapse => 5,  // Synapse similar to Hop
        }
    }
}

/// Bridge quote request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeQuoteRequest {
    /// Source chain
    pub source_chain: Chain,
    /// Destination chain
    pub destination_chain: Chain,
    /// Token address on source chain (use NATIVE for native token)
    pub token: String,
    /// Amount in smallest unit (wei, lamports, etc.)
    pub amount: String,
    /// Sender address
    pub sender: String,
    /// Recipient address (can be different from sender)
    pub recipient: String,
    /// Slippage tolerance as percentage (e.g., 0.5 for 0.5%)
    pub slippage: f64,
    /// Preferred provider (optional)
    pub provider: Option<BridgeProvider>,
}

impl BridgeQuoteRequest {
    /// Native token address constant
    pub const NATIVE: &'static str = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

    /// Check if bridging native token
    pub fn is_native_token(&self) -> bool {
        self.token.eq_ignore_ascii_case(Self::NATIVE) || 
        self.token.eq_ignore_ascii_case("native") ||
        self.token.eq_ignore_ascii_case("ETH") ||
        self.token.eq_ignore_ascii_case("BNB") ||
        self.token.eq_ignore_ascii_case("MATIC")
    }
}

/// Bridge quote from a provider
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeQuote {
    /// Quote ID for reference
    pub id: String,
    /// Bridge provider
    pub provider: BridgeProvider,
    /// Source chain
    pub source_chain: Chain,
    /// Destination chain
    pub destination_chain: Chain,
    /// Token being bridged
    pub token: String,
    /// Token symbol
    pub token_symbol: String,
    /// Amount to send
    pub amount_in: String,
    /// Amount to receive (after fees)
    pub amount_out: String,
    /// Minimum amount to receive (with slippage)
    pub amount_out_min: String,
    /// Bridge fee in token
    pub bridge_fee: String,
    /// Bridge fee in USD
    pub bridge_fee_usd: Option<f64>,
    /// Gas fee on source chain in USD
    pub source_gas_usd: Option<f64>,
    /// Gas fee on destination chain in USD
    pub destination_gas_usd: Option<f64>,
    /// Total fee in USD
    pub total_fee_usd: Option<f64>,
    /// Estimated transfer time in minutes
    pub estimated_time_minutes: u32,
    /// Exchange rate (1 source token = X destination tokens)
    pub exchange_rate: f64,
    /// Price impact percentage
    pub price_impact: Option<f64>,
    /// Quote expiration timestamp
    pub expires_at: u64,
    /// Transaction data (if available)
    pub transaction: Option<BridgeTransaction>,
}

impl BridgeQuote {
    /// Calculate effective rate after all fees
    pub fn effective_rate(&self) -> Option<f64> {
        let amount_in: f64 = self.amount_in.parse().ok()?;
        let amount_out: f64 = self.amount_out.parse().ok()?;
        if amount_in > 0.0 {
            Some(amount_out / amount_in)
        } else {
            None
        }
    }

    /// Check if quote is still valid
    pub fn is_valid(&self) -> bool {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();
        self.expires_at > now
    }
}

/// Transaction data for bridge execution
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeTransaction {
    /// Contract address to call
    pub to: String,
    /// Calldata
    pub data: String,
    /// Value to send (for native token bridges)
    pub value: String,
    /// Gas limit
    pub gas_limit: String,
    /// Gas price (legacy)
    pub gas_price: Option<String>,
    /// Max fee per gas (EIP-1559)
    pub max_fee_per_gas: Option<String>,
    /// Max priority fee per gas (EIP-1559)
    pub max_priority_fee_per_gas: Option<String>,
    /// Chain ID
    pub chain_id: u64,
}

/// Bridge transfer status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum BridgeStatus {
    /// Transaction submitted to source chain
    Pending,
    /// Transaction confirmed on source chain
    SourceConfirmed,
    /// Bridge is processing the transfer
    InTransit,
    /// Waiting for destination chain finality
    WaitingDestination,
    /// Transfer completed successfully
    Completed,
    /// Transfer failed
    Failed,
    /// Transfer refunded (timeout or error)
    Refunded,
}

impl BridgeStatus {
    /// Check if status is final
    pub fn is_final(&self) -> bool {
        matches!(self, Self::Completed | Self::Failed | Self::Refunded)
    }

    /// Get display name
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Pending => "Pending",
            Self::SourceConfirmed => "Confirmed on Source",
            Self::InTransit => "In Transit",
            Self::WaitingDestination => "Waiting for Destination",
            Self::Completed => "Completed",
            Self::Failed => "Failed",
            Self::Refunded => "Refunded",
        }
    }
}

/// Bridge transfer tracking
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeTransfer {
    /// Unique transfer ID
    pub id: String,
    /// Bridge provider
    pub provider: BridgeProvider,
    /// Source chain
    pub source_chain: Chain,
    /// Destination chain
    pub destination_chain: Chain,
    /// Token symbol
    pub token_symbol: String,
    /// Amount sent
    pub amount_in: String,
    /// Expected amount to receive
    pub amount_out: String,
    /// Source transaction hash
    pub source_tx_hash: String,
    /// Destination transaction hash (when complete)
    pub destination_tx_hash: Option<String>,
    /// Current status
    pub status: BridgeStatus,
    /// Timestamp when transfer was initiated
    pub initiated_at: u64,
    /// Timestamp when transfer completed (if applicable)
    pub completed_at: Option<u64>,
    /// Estimated completion time
    pub estimated_completion: u64,
    /// Provider-specific tracking data
    pub tracking_data: Option<serde_json::Value>,
}

impl BridgeTransfer {
    /// Check if transfer is complete
    pub fn is_complete(&self) -> bool {
        self.status == BridgeStatus::Completed
    }

    /// Get elapsed time in seconds
    pub fn elapsed_seconds(&self) -> u64 {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();
        now.saturating_sub(self.initiated_at)
    }
}

/// Aggregated bridge quotes from multiple providers
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AggregatedBridgeQuotes {
    /// All quotes
    pub quotes: Vec<BridgeQuote>,
    /// Best quote (highest amount out)
    pub best_quote: Option<BridgeQuote>,
    /// Cheapest quote (lowest fees)
    pub cheapest_quote: Option<BridgeQuote>,
    /// Fastest quote (shortest time)
    pub fastest_quote: Option<BridgeQuote>,
    /// Timestamp when quotes were fetched
    pub fetched_at: u64,
}

impl AggregatedBridgeQuotes {
    /// Sort quotes by output amount (best first)
    pub fn sorted_by_output(&self) -> Vec<BridgeQuote> {
        let mut sorted = self.quotes.clone();
        sorted.sort_by(|a, b| {
            let a_out: f64 = a.amount_out.parse().unwrap_or(0.0);
            let b_out: f64 = b.amount_out.parse().unwrap_or(0.0);
            b_out.partial_cmp(&a_out).unwrap_or(std::cmp::Ordering::Equal)
        });
        sorted
    }

    /// Sort quotes by total fee (cheapest first)
    pub fn sorted_by_fee(&self) -> Vec<BridgeQuote> {
        let mut sorted = self.quotes.clone();
        sorted.sort_by(|a, b| {
            let a_fee = a.total_fee_usd.unwrap_or(f64::MAX);
            let b_fee = b.total_fee_usd.unwrap_or(f64::MAX);
            a_fee.partial_cmp(&b_fee).unwrap_or(std::cmp::Ordering::Equal)
        });
        sorted
    }

    /// Sort quotes by time (fastest first)
    pub fn sorted_by_time(&self) -> Vec<BridgeQuote> {
        let mut sorted = self.quotes.clone();
        sorted.sort_by_key(|q| q.estimated_time_minutes);
        sorted
    }
}

/// Bridge error types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum BridgeError {
    /// Route not supported
    RouteNotSupported {
        source: Chain,
        destination: Chain,
        token: String,
    },
    /// Insufficient liquidity
    InsufficientLiquidity {
        available: String,
        requested: String,
    },
    /// Amount too small
    AmountTooSmall {
        minimum: String,
        provided: String,
    },
    /// Amount too large
    AmountTooLarge {
        maximum: String,
        provided: String,
    },
    /// Quote expired
    QuoteExpired,
    /// Provider error
    ProviderError(String),
    /// Network error
    NetworkError(String),
    /// Invalid address
    InvalidAddress(String),
}

impl std::fmt::Display for BridgeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::RouteNotSupported { source, destination, token } => {
                write!(f, "Bridge route not supported: {} {:?} → {:?}", token, source, destination)
            }
            Self::InsufficientLiquidity { available, requested } => {
                write!(f, "Insufficient liquidity: {} available, {} requested", available, requested)
            }
            Self::AmountTooSmall { minimum, provided } => {
                write!(f, "Amount too small: minimum {}, provided {}", minimum, provided)
            }
            Self::AmountTooLarge { maximum, provided } => {
                write!(f, "Amount too large: maximum {}, provided {}", maximum, provided)
            }
            Self::QuoteExpired => write!(f, "Bridge quote has expired"),
            Self::ProviderError(msg) => write!(f, "Bridge provider error: {}", msg),
            Self::NetworkError(msg) => write!(f, "Network error: {}", msg),
            Self::InvalidAddress(addr) => write!(f, "Invalid address: {}", addr),
        }
    }
}

impl std::error::Error for BridgeError {}

#[cfg(test)]
mod type_tests {
    use super::*;

    #[test]
    fn test_provider_supported_routes() {
        assert!(BridgeProvider::Wormhole.supports_route(Chain::Ethereum, Chain::Solana));
        assert!(BridgeProvider::LayerZero.supports_route(Chain::Ethereum, Chain::Arbitrum));
        assert!(BridgeProvider::Stargate.supports_route(Chain::Polygon, Chain::Optimism));
        
        // Same chain should not be supported
        assert!(!BridgeProvider::Wormhole.supports_route(Chain::Ethereum, Chain::Ethereum));
    }

    #[test]
    fn test_quote_validity() {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let valid_quote = BridgeQuote {
            id: "test".to_string(),
            provider: BridgeProvider::Wormhole,
            source_chain: Chain::Ethereum,
            destination_chain: Chain::Solana,
            token: "USDC".to_string(),
            token_symbol: "USDC".to_string(),
            amount_in: "1000000000".to_string(),
            amount_out: "999500000".to_string(),
            amount_out_min: "994500000".to_string(),
            bridge_fee: "500000".to_string(),
            bridge_fee_usd: Some(0.50),
            source_gas_usd: Some(2.0),
            destination_gas_usd: Some(0.01),
            total_fee_usd: Some(2.51),
            estimated_time_minutes: 15,
            exchange_rate: 0.9995,
            price_impact: Some(0.01),
            expires_at: now + 300,
            transaction: None,
        };

        assert!(valid_quote.is_valid());

        let expired_quote = BridgeQuote {
            expires_at: now - 100,
            ..valid_quote
        };

        assert!(!expired_quote.is_valid());
    }

    #[test]
    fn test_bridge_status() {
        assert!(!BridgeStatus::Pending.is_final());
        assert!(!BridgeStatus::InTransit.is_final());
        assert!(BridgeStatus::Completed.is_final());
        assert!(BridgeStatus::Failed.is_final());
        assert!(BridgeStatus::Refunded.is_final());
    }

    #[test]
    fn test_aggregated_quotes_sorting() {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let make_quote = |provider, amount_out: &str, fee: f64, time: u32| BridgeQuote {
            id: format!("{:?}", provider),
            provider,
            source_chain: Chain::Ethereum,
            destination_chain: Chain::Arbitrum,
            token: "USDC".to_string(),
            token_symbol: "USDC".to_string(),
            amount_in: "1000000000".to_string(),
            amount_out: amount_out.to_string(),
            amount_out_min: amount_out.to_string(),
            bridge_fee: "0".to_string(),
            bridge_fee_usd: Some(fee),
            source_gas_usd: Some(0.0),
            destination_gas_usd: Some(0.0),
            total_fee_usd: Some(fee),
            estimated_time_minutes: time,
            exchange_rate: 1.0,
            price_impact: None,
            expires_at: now + 300,
            transaction: None,
        };

        let quotes = vec![
            make_quote(BridgeProvider::Wormhole, "995000000", 5.0, 15),
            make_quote(BridgeProvider::Stargate, "998000000", 2.0, 2),
            make_quote(BridgeProvider::Across, "997000000", 1.5, 3),
        ];

        let agg = AggregatedBridgeQuotes {
            quotes: quotes.clone(),
            best_quote: Some(quotes[1].clone()), // Stargate has highest output
            cheapest_quote: Some(quotes[2].clone()), // Across has lowest fee
            fastest_quote: Some(quotes[1].clone()), // Stargate is fastest
            fetched_at: now,
        };

        let by_output = agg.sorted_by_output();
        assert_eq!(by_output[0].provider, BridgeProvider::Stargate);

        let by_fee = agg.sorted_by_fee();
        assert_eq!(by_fee[0].provider, BridgeProvider::Across);

        let by_time = agg.sorted_by_time();
        assert_eq!(by_time[0].provider, BridgeProvider::Stargate);
    }
}
