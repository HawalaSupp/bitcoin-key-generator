//! THORChain Cross-Chain Swap Implementation
//!
//! Provides native cross-chain swaps via THORChain protocol.
//! Based on THORChain docs: https://docs.thorchain.org/
//!
//! Supports swaps between:
//! - Bitcoin (BTC)
//! - Ethereum (ETH)
//! - BNB Chain (BNB)
//! - Dogecoin (DOGE)
//! - Litecoin (LTC)
//! - Bitcoin Cash (BCH)
//! - Cosmos (ATOM)
//! - Avalanche (AVAX)
//! - And more...

use serde::{Deserialize, Serialize};

use crate::error::HawalaResult;

/// THORChain supported chains
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum ThorChain {
    Thor,       // Native RUNE
    Bitcoin,
    Ethereum,
    BinanceChain,
    Dogecoin,
    Litecoin,
    BitcoinCash,
    Cosmos,
    Avalanche,
    BscChain,
}

impl ThorChain {
    /// Get chain identifier string
    pub fn chain_id(&self) -> &'static str {
        match self {
            Self::Thor => "THOR",
            Self::Bitcoin => "BTC",
            Self::Ethereum => "ETH",
            Self::BinanceChain => "BNB",
            Self::Dogecoin => "DOGE",
            Self::Litecoin => "LTC",
            Self::BitcoinCash => "BCH",
            Self::Cosmos => "GAIA",
            Self::Avalanche => "AVAX",
            Self::BscChain => "BSC",
        }
    }

    /// Get native asset identifier
    pub fn native_asset(&self) -> ThorAsset {
        ThorAsset {
            chain: *self,
            symbol: self.native_symbol().to_string(),
            ticker: self.native_ticker().to_string(),
            contract: None,
        }
    }

    fn native_symbol(&self) -> &'static str {
        match self {
            Self::Thor => "RUNE",
            Self::Bitcoin => "BTC",
            Self::Ethereum => "ETH",
            Self::BinanceChain => "BNB",
            Self::Dogecoin => "DOGE",
            Self::Litecoin => "LTC",
            Self::BitcoinCash => "BCH",
            Self::Cosmos => "ATOM",
            Self::Avalanche => "AVAX",
            Self::BscChain => "BNB",
        }
    }

    fn native_ticker(&self) -> &'static str {
        self.native_symbol()
    }

    /// Get decimals for native asset
    pub fn decimals(&self) -> u8 {
        match self {
            Self::Thor => 8,
            Self::Bitcoin => 8,
            Self::Ethereum => 18,
            Self::BinanceChain => 8,
            Self::Dogecoin => 8,
            Self::Litecoin => 8,
            Self::BitcoinCash => 8,
            Self::Cosmos => 6,
            Self::Avalanche => 18,
            Self::BscChain => 18,
        }
    }
}

/// THORChain asset (chain + symbol + optional contract)
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ThorAsset {
    pub chain: ThorChain,
    pub symbol: String,
    pub ticker: String,
    pub contract: Option<String>,
}

impl ThorAsset {
    /// Create a native asset
    pub fn native(chain: ThorChain) -> Self {
        chain.native_asset()
    }

    /// Create an ERC-20 token asset
    pub fn erc20(contract: &str, symbol: &str) -> Self {
        Self {
            chain: ThorChain::Ethereum,
            symbol: format!("{}-{}", symbol, &contract[..6]),
            ticker: symbol.to_string(),
            contract: Some(contract.to_string()),
        }
    }

    /// Get asset string for memo
    pub fn to_asset_string(&self) -> String {
        match &self.contract {
            Some(contract) => format!("{}.{}-{}", self.chain.chain_id(), self.symbol, contract),
            None => format!("{}.{}", self.chain.chain_id(), self.symbol),
        }
    }
}

/// Common ERC-20 tokens on THORChain
pub mod tokens {
    use super::*;

    pub fn usdc() -> ThorAsset {
        ThorAsset::erc20("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", "USDC")
    }

    pub fn usdt() -> ThorAsset {
        ThorAsset::erc20("0xdAC17F958D2ee523a2206206994597C13D831ec7", "USDT")
    }

    pub fn wbtc() -> ThorAsset {
        ThorAsset::erc20("0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599", "WBTC")
    }

    pub fn dai() -> ThorAsset {
        ThorAsset::erc20("0x6B175474E89094C44Da98b954EesadFD691D3636", "DAI")
    }
}

/// Swap quote from THORChain
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SwapQuote {
    /// Expected output amount (in base units)
    pub expected_amount_out: u128,
    /// Minimum output (with slippage)
    pub minimum_amount_out: u128,
    /// Fees breakdown
    pub fees: SwapFees,
    /// Inbound address (vault)
    pub inbound_address: String,
    /// Router address (for EVM chains)
    pub router: Option<String>,
    /// Expiry timestamp
    pub expiry: u64,
    /// Swap memo to include
    pub memo: String,
    /// Estimated time in seconds
    pub estimated_time: u32,
}

/// Swap fees breakdown
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SwapFees {
    /// Network fee (gas)
    pub gas: u128,
    /// Affiliate fee
    pub affiliate: u128,
    /// Outbound fee
    pub outbound: u128,
    /// Liquidity fee (slippage)
    pub liquidity: u128,
    /// Total fees in USD
    pub total_usd: f64,
}

/// Swap request parameters
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SwapRequest {
    /// Source asset
    pub from_asset: ThorAsset,
    /// Destination asset
    pub to_asset: ThorAsset,
    /// Source address
    pub from_address: String,
    /// Destination address
    pub to_address: String,
    /// Amount to swap (in base units)
    pub amount: u128,
    /// Slippage tolerance (basis points, e.g., 100 = 1%)
    pub slippage_bps: u32,
    /// Affiliate address (optional)
    pub affiliate: Option<String>,
    /// Affiliate fee (basis points)
    pub affiliate_bps: u32,
    /// Streaming swap interval (0 for instant)
    pub streaming_interval: u32,
    /// Streaming swap quantity
    pub streaming_quantity: u32,
}

impl SwapRequest {
    /// Create a simple swap request
    pub fn new(
        from_asset: ThorAsset,
        to_asset: ThorAsset,
        from_address: &str,
        to_address: &str,
        amount: u128,
    ) -> Self {
        Self {
            from_asset,
            to_asset,
            from_address: from_address.to_string(),
            to_address: to_address.to_string(),
            amount,
            slippage_bps: 300, // 3% default slippage
            affiliate: None,
            affiliate_bps: 0,
            streaming_interval: 0,
            streaming_quantity: 0,
        }
    }

    /// Set slippage tolerance
    pub fn with_slippage(mut self, bps: u32) -> Self {
        self.slippage_bps = bps;
        self
    }

    /// Set affiliate
    pub fn with_affiliate(mut self, address: &str, bps: u32) -> Self {
        self.affiliate = Some(address.to_string());
        self.affiliate_bps = bps;
        self
    }

    /// Enable streaming swap
    pub fn with_streaming(mut self, interval: u32, quantity: u32) -> Self {
        self.streaming_interval = interval;
        self.streaming_quantity = quantity;
        self
    }

    /// Build the swap memo
    pub fn build_memo(&self, limit: u128) -> String {
        let mut memo = format!(
            "=:{}:{}:{}",
            self.to_asset.to_asset_string(),
            self.to_address,
            limit
        );

        // Add affiliate
        if let Some(ref affiliate) = self.affiliate {
            memo.push_str(&format!(":{}:{}", affiliate, self.affiliate_bps));
        }

        // Add streaming parameters
        if self.streaming_interval > 0 {
            memo.push_str(&format!("/{}/{}", self.streaming_interval, self.streaming_quantity));
        }

        memo
    }
}

/// THORChain swap executor
pub struct ThorSwap {
    /// THORNode API endpoint
    pub api_url: String,
    /// Midgard API endpoint
    pub midgard_url: String,
}

impl ThorSwap {
    /// Create with default mainnet endpoints
    pub fn mainnet() -> Self {
        Self {
            api_url: "https://thornode.ninerealms.com".to_string(),
            midgard_url: "https://midgard.ninerealms.com".to_string(),
        }
    }

    /// Create with stagenet endpoints
    pub fn stagenet() -> Self {
        Self {
            api_url: "https://stagenet-thornode.ninerealms.com".to_string(),
            midgard_url: "https://stagenet-midgard.ninerealms.com".to_string(),
        }
    }

    /// Get swap quote (requires network call - returns mock for now)
    /// In production, this would call /thorchain/quote/swap
    pub fn get_quote(&self, request: &SwapRequest) -> HawalaResult<SwapQuote> {
        // Calculate mock quote (in production, call API)
        let estimated_out = calculate_estimated_output(
            &request.from_asset,
            &request.to_asset,
            request.amount,
        );

        let minimum_out = estimated_out * (10000 - request.slippage_bps as u128) / 10000;

        let memo = request.build_memo(minimum_out);

        Ok(SwapQuote {
            expected_amount_out: estimated_out,
            minimum_amount_out: minimum_out,
            fees: SwapFees {
                gas: estimated_out / 200,      // ~0.5% mock
                affiliate: if request.affiliate_bps > 0 {
                    estimated_out * request.affiliate_bps as u128 / 10000
                } else {
                    0
                },
                outbound: estimated_out / 500, // ~0.2% mock
                liquidity: estimated_out / 100, // ~1% mock
                total_usd: 5.0, // Mock value
            },
            inbound_address: get_mock_vault(&request.from_asset.chain),
            router: get_router(&request.from_asset.chain),
            expiry: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs() + 900, // 15 min expiry
            memo,
            estimated_time: estimate_swap_time(&request.from_asset.chain, &request.to_asset.chain),
        })
    }

    /// Get inbound addresses for a chain
    pub async fn get_inbound_address(&self, chain: ThorChain) -> HawalaResult<String> {
        // In production, call /thorchain/inbound_addresses
        Ok(get_mock_vault(&chain))
    }

    /// Get supported pools
    pub async fn get_pools(&self) -> HawalaResult<Vec<ThorPool>> {
        // Mock pools - in production, call /thorchain/pools
        Ok(vec![
            ThorPool {
                asset: ThorAsset::native(ThorChain::Bitcoin),
                status: PoolStatus::Available,
                balance_rune: 100_000_000_000,
                balance_asset: 5_000_000_000,
                pool_apy: 8.5,
            },
            ThorPool {
                asset: ThorAsset::native(ThorChain::Ethereum),
                status: PoolStatus::Available,
                balance_rune: 80_000_000_000,
                balance_asset: 25_000_000_000_000_000_000_000u128,
                pool_apy: 12.3,
            },
        ])
    }
}

/// THORChain pool info
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ThorPool {
    pub asset: ThorAsset,
    pub status: PoolStatus,
    pub balance_rune: u128,
    pub balance_asset: u128,
    pub pool_apy: f64,
}

/// Pool status
#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum PoolStatus {
    Available,
    Staged,
    Suspended,
}

/// Build a swap transaction for Bitcoin -> X
pub fn build_btc_swap_tx(
    request: &SwapRequest,
    quote: &SwapQuote,
    _utxos: Vec<UtxoInput>,
) -> HawalaResult<SwapTransaction> {
    // For Bitcoin, we send to the vault address with OP_RETURN memo
    Ok(SwapTransaction {
        chain: ThorChain::Bitcoin,
        to_address: quote.inbound_address.clone(),
        amount: request.amount,
        memo: Some(quote.memo.clone()),
        data: None,
        router: None,
    })
}

/// Build a swap transaction for Ethereum -> X
pub fn build_eth_swap_tx(
    request: &SwapRequest,
    quote: &SwapQuote,
) -> HawalaResult<SwapTransaction> {
    // For Ethereum, we call the router contract's deposit() function
    // with the memo encoded in the data field
    let data = encode_router_deposit(&quote.memo, request.amount)?;

    Ok(SwapTransaction {
        chain: ThorChain::Ethereum,
        to_address: quote.router.clone().unwrap_or(quote.inbound_address.clone()),
        amount: request.amount,
        memo: None, // Included in data
        data: Some(data),
        router: quote.router.clone(),
    })
}

/// UTXO input for swap transactions
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct UtxoInput {
    pub txid: String,
    pub vout: u32,
    pub value: u64,
    pub script: Vec<u8>,
}

/// Prepared swap transaction
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SwapTransaction {
    pub chain: ThorChain,
    pub to_address: String,
    pub amount: u128,
    pub memo: Option<String>,
    pub data: Option<Vec<u8>>,
    pub router: Option<String>,
}

// Helper functions

fn calculate_estimated_output(from: &ThorAsset, to: &ThorAsset, amount: u128) -> u128 {
    // Mock calculation - in production, use pool depths
    // This is a placeholder that assumes ~equivalent value
    let from_decimals = from.chain.decimals();
    let to_decimals = to.chain.decimals();

    // Adjust for decimals difference
    if to_decimals > from_decimals {
        amount * 10u128.pow((to_decimals - from_decimals) as u32)
    } else {
        amount / 10u128.pow((from_decimals - to_decimals) as u32)
    }
}

fn get_mock_vault(chain: &ThorChain) -> String {
    // Mock vault addresses - in production, fetch from API
    match chain {
        ThorChain::Bitcoin => "bc1qvault...".to_string(),
        ThorChain::Ethereum => "0x1234567890abcdef1234567890abcdef12345678".to_string(),
        ThorChain::Dogecoin => "D1234567890abcdef...".to_string(),
        ThorChain::Litecoin => "ltc1qvault...".to_string(),
        _ => "vault_address".to_string(),
    }
}

fn get_router(chain: &ThorChain) -> Option<String> {
    // Router is only used for EVM chains
    match chain {
        ThorChain::Ethereum => Some("0x3624525075b88B24ecc29CE226b0CEc1fFcB6976".to_string()),
        ThorChain::Avalanche => Some("0x8F66c4AE756BEbC49Ec8B81966DD8bba9f127549".to_string()),
        ThorChain::BscChain => Some("0xb30eC53F98ff5947EDe720D32aC2da7e52A5f56b".to_string()),
        _ => None,
    }
}

fn estimate_swap_time(from: &ThorChain, to: &ThorChain) -> u32 {
    // Estimated time in seconds based on chain finality
    let from_time = match from {
        ThorChain::Bitcoin => 600,  // ~10 min (1 conf)
        ThorChain::Ethereum => 180, // ~3 min
        ThorChain::Dogecoin => 60,  // ~1 min
        _ => 60,
    };

    let to_time = match to {
        ThorChain::Bitcoin => 600,
        ThorChain::Ethereum => 180,
        ThorChain::Dogecoin => 60,
        _ => 60,
    };

    (from_time + to_time) as u32
}

fn encode_router_deposit(memo: &str, amount: u128) -> HawalaResult<Vec<u8>> {
    // Encode deposit(address,address,uint256,string) function call
    // Function selector: 0x574da717
    let mut data = Vec::new();

    // Function selector
    data.extend_from_slice(&[0x57, 0x4d, 0xa7, 0x17]);

    // Vault address (32 bytes, padded)
    data.extend_from_slice(&[0u8; 32]);

    // Asset address (32 bytes, 0x0 for native)
    data.extend_from_slice(&[0u8; 32]);

    // Amount (32 bytes)
    let amount_bytes = amount.to_be_bytes();
    data.extend_from_slice(&[0u8; 16]); // Padding for u256
    data.extend_from_slice(&amount_bytes);

    // Memo offset (32 bytes)
    let memo_offset = 128u64.to_be_bytes();
    data.extend_from_slice(&[0u8; 24]);
    data.extend_from_slice(&memo_offset);

    // Memo length
    let memo_len = memo.len() as u64;
    data.extend_from_slice(&[0u8; 24]);
    data.extend_from_slice(&memo_len.to_be_bytes());

    // Memo data (padded to 32 bytes)
    data.extend_from_slice(memo.as_bytes());
    let padding = (32 - (memo.len() % 32)) % 32;
    data.extend_from_slice(&vec![0u8; padding]);

    Ok(data)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_asset_string() {
        let btc = ThorAsset::native(ThorChain::Bitcoin);
        assert_eq!(btc.to_asset_string(), "BTC.BTC");

        let eth = ThorAsset::native(ThorChain::Ethereum);
        assert_eq!(eth.to_asset_string(), "ETH.ETH");
    }

    #[test]
    fn test_swap_memo() {
        let request = SwapRequest::new(
            ThorAsset::native(ThorChain::Bitcoin),
            ThorAsset::native(ThorChain::Ethereum),
            "bc1qsender...",
            "0xrecipient...",
            100_000_000, // 1 BTC
        );

        let memo = request.build_memo(1_000_000_000_000_000_000); // 1 ETH minimum
        assert!(memo.starts_with("=:ETH.ETH:"));
    }

    #[test]
    fn test_swap_quote() {
        let swap = ThorSwap::mainnet();
        let request = SwapRequest::new(
            ThorAsset::native(ThorChain::Bitcoin),
            ThorAsset::native(ThorChain::Ethereum),
            "bc1qsender...",
            "0xrecipient...",
            100_000_000,
        );

        let quote = swap.get_quote(&request).unwrap();
        assert!(quote.expected_amount_out > 0);
        assert!(!quote.inbound_address.is_empty());
    }
}
