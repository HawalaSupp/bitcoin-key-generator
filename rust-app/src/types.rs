//! Shared types for Hawala Core
//!
//! All data structures that cross module boundaries are defined here
//! for consistent serialization and FFI compatibility.

use serde::{Deserialize, Serialize};

// =============================================================================
// Chain Types
// =============================================================================

/// Supported blockchain networks
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Chain {
    // Bitcoin & forks
    Bitcoin,
    BitcoinTestnet,
    Litecoin,
    Dogecoin,
    BitcoinCash,
    Zcash,
    Dash,
    Ravencoin,
    DigiByte,
    Firo,
    
    // Ethereum & EVM
    Ethereum,
    EthereumSepolia,
    Bnb,
    Polygon,
    Arbitrum,
    Optimism,
    Base,
    Avalanche,
    Fantom,
    Cronos,
    Gnosis,
    Celo,
    Moonbeam,
    Moonriver,
    Aurora,
    Metis,
    Boba,
    ZkSync,
    PolygonZkEvm,
    Linea,
    Scroll,
    Mantle,
    Blast,
    
    // Solana
    Solana,
    SolanaDevnet,
    
    // XRP
    Xrp,
    XrpTestnet,
    
    // Cosmos ecosystem
    Cosmos,
    Osmosis,
    Celestia,
    Dydx,
    Injective,
    Sei,
    Kava,
    Akash,
    Secret,
    Stargaze,
    Juno,
    Terra,
    Neutron,
    Noble,
    Axelar,
    Stride,
    
    // Substrate-based
    Polkadot,
    Kusama,
    Acala,
    
    // L1 chains
    Cardano,
    Tron,
    Algorand,
    Stellar,
    Near,
    Tezos,
    Hedera,
    Aptos,
    Sui,
    Ton,
    Vechain,
    Harmony,
    Oasis,
    Filecoin,
    InternetComputer,
    Waves,
    Neo,
    Eos,
    Ontology,
    Zilliqa,
    Nervos,
    MultiversX,
    Flow,
    Mina,
    
    // Privacy coins
    Monero,
}

impl Chain {
    pub fn is_evm(&self) -> bool {
        matches!(
            self,
            Chain::Ethereum
                | Chain::EthereumSepolia
                | Chain::Bnb
                | Chain::Polygon
                | Chain::Arbitrum
                | Chain::Optimism
                | Chain::Base
                | Chain::Avalanche
                | Chain::Fantom
                | Chain::Cronos
                | Chain::Gnosis
                | Chain::Celo
                | Chain::Moonbeam
                | Chain::Moonriver
                | Chain::Aurora
                | Chain::Metis
                | Chain::Boba
                | Chain::ZkSync
                | Chain::PolygonZkEvm
                | Chain::Linea
                | Chain::Scroll
                | Chain::Mantle
                | Chain::Blast
        )
    }

    pub fn is_utxo(&self) -> bool {
        matches!(
            self,
            Chain::Bitcoin 
                | Chain::BitcoinTestnet 
                | Chain::Litecoin
                | Chain::Dogecoin
                | Chain::BitcoinCash
                | Chain::Zcash
                | Chain::Dash
                | Chain::Ravencoin
                | Chain::DigiByte
                | Chain::Firo
        )
    }

    pub fn is_cosmos(&self) -> bool {
        matches!(
            self,
            Chain::Cosmos
                | Chain::Osmosis
                | Chain::Celestia
                | Chain::Dydx
                | Chain::Injective
                | Chain::Sei
                | Chain::Kava
                | Chain::Akash
                | Chain::Secret
                | Chain::Stargaze
                | Chain::Juno
                | Chain::Terra
                | Chain::Neutron
                | Chain::Noble
                | Chain::Axelar
                | Chain::Stride
        )
    }

    pub fn is_testnet(&self) -> bool {
        matches!(
            self,
            Chain::BitcoinTestnet | Chain::EthereumSepolia | Chain::SolanaDevnet | Chain::XrpTestnet
        )
    }

    pub fn chain_id(&self) -> Option<u64> {
        match self {
            Chain::Ethereum => Some(1),
            Chain::EthereumSepolia => Some(11155111),
            Chain::Bnb => Some(56),
            Chain::Polygon => Some(137),
            Chain::Arbitrum => Some(42161),
            Chain::Optimism => Some(10),
            Chain::Base => Some(8453),
            Chain::Avalanche => Some(43114),
            Chain::Fantom => Some(250),
            Chain::Cronos => Some(25),
            Chain::Gnosis => Some(100),
            Chain::Celo => Some(42220),
            Chain::Moonbeam => Some(1284),
            Chain::Moonriver => Some(1285),
            Chain::Aurora => Some(1313161554),
            Chain::Metis => Some(1088),
            Chain::Boba => Some(288),
            Chain::ZkSync => Some(324),
            Chain::PolygonZkEvm => Some(1101),
            Chain::Linea => Some(59144),
            Chain::Scroll => Some(534352),
            Chain::Mantle => Some(5000),
            Chain::Blast => Some(81457),
            Chain::Harmony => Some(1666600000),
            Chain::Vechain => Some(74),
            _ => None,
        }
    }

    pub fn symbol(&self) -> &'static str {
        match self {
            Chain::Bitcoin | Chain::BitcoinTestnet => "BTC",
            Chain::Litecoin => "LTC",
            Chain::Dogecoin => "DOGE",
            Chain::BitcoinCash => "BCH",
            Chain::Zcash => "ZEC",
            Chain::Dash => "DASH",
            Chain::Ravencoin => "RVN",
            Chain::DigiByte => "DGB",
            Chain::Firo => "FIRO",
            Chain::Ethereum | Chain::EthereumSepolia => "ETH",
            Chain::Bnb => "BNB",
            Chain::Polygon => "POL",
            Chain::Arbitrum | Chain::Optimism | Chain::Base | Chain::ZkSync 
                | Chain::PolygonZkEvm | Chain::Linea | Chain::Scroll | Chain::Blast => "ETH",
            Chain::Avalanche => "AVAX",
            Chain::Fantom => "FTM",
            Chain::Cronos => "CRO",
            Chain::Gnosis => "xDAI",
            Chain::Celo => "CELO",
            Chain::Moonbeam => "GLMR",
            Chain::Moonriver => "MOVR",
            Chain::Aurora => "ETH",
            Chain::Metis => "METIS",
            Chain::Boba => "ETH",
            Chain::Mantle => "MNT",
            Chain::Solana | Chain::SolanaDevnet => "SOL",
            Chain::Xrp | Chain::XrpTestnet => "XRP",
            Chain::Cosmos => "ATOM",
            Chain::Osmosis => "OSMO",
            Chain::Celestia => "TIA",
            Chain::Dydx => "DYDX",
            Chain::Injective => "INJ",
            Chain::Sei => "SEI",
            Chain::Kava => "KAVA",
            Chain::Akash => "AKT",
            Chain::Secret => "SCRT",
            Chain::Stargaze => "STARS",
            Chain::Juno => "JUNO",
            Chain::Terra => "LUNA",
            Chain::Neutron => "NTRN",
            Chain::Noble => "USDC",
            Chain::Axelar => "AXL",
            Chain::Stride => "STRD",
            Chain::Polkadot => "DOT",
            Chain::Kusama => "KSM",
            Chain::Acala => "ACA",
            Chain::Cardano => "ADA",
            Chain::Tron => "TRX",
            Chain::Algorand => "ALGO",
            Chain::Stellar => "XLM",
            Chain::Near => "NEAR",
            Chain::Tezos => "XTZ",
            Chain::Hedera => "HBAR",
            Chain::Aptos => "APT",
            Chain::Sui => "SUI",
            Chain::Ton => "TON",
            Chain::Vechain => "VET",
            Chain::Harmony => "ONE",
            Chain::Oasis => "ROSE",
            Chain::Filecoin => "FIL",
            Chain::InternetComputer => "ICP",
            Chain::Waves => "WAVES",
            Chain::Neo => "NEO",
            Chain::Eos => "EOS",
            Chain::Ontology => "ONT",
            Chain::Zilliqa => "ZIL",
            Chain::Nervos => "CKB",
            Chain::MultiversX => "EGLD",
            Chain::Flow => "FLOW",
            Chain::Mina => "MINA",
            Chain::Monero => "XMR",
        }
    }

    pub fn decimals(&self) -> u8 {
        match self {
            // UTXO chains (8 decimals)
            Chain::Bitcoin | Chain::BitcoinTestnet | Chain::Litecoin 
                | Chain::Dogecoin | Chain::BitcoinCash | Chain::Zcash 
                | Chain::Dash | Chain::Ravencoin | Chain::DigiByte | Chain::Firo => 8,
            
            // EVM chains (18 decimals)
            Chain::Ethereum | Chain::EthereumSepolia | Chain::Bnb | Chain::Polygon
                | Chain::Arbitrum | Chain::Optimism | Chain::Base | Chain::Avalanche
                | Chain::Fantom | Chain::Cronos | Chain::Gnosis | Chain::Celo
                | Chain::Moonbeam | Chain::Moonriver | Chain::Aurora | Chain::Metis
                | Chain::Boba | Chain::ZkSync | Chain::PolygonZkEvm | Chain::Linea
                | Chain::Scroll | Chain::Mantle | Chain::Blast
                | Chain::Vechain | Chain::Harmony | Chain::Near | Chain::MultiversX
                | Chain::Filecoin | Chain::Waves => 18,
            
            // 9 decimals
            Chain::Solana | Chain::SolanaDevnet | Chain::Ton | Chain::Oasis 
                | Chain::Sui => 9,
            
            // 6 decimals
            Chain::Xrp | Chain::XrpTestnet | Chain::Cosmos | Chain::Osmosis
                | Chain::Celestia | Chain::Dydx | Chain::Injective | Chain::Sei
                | Chain::Kava | Chain::Akash | Chain::Secret | Chain::Stargaze
                | Chain::Juno | Chain::Terra | Chain::Neutron | Chain::Noble
                | Chain::Axelar | Chain::Stride | Chain::Cardano | Chain::Algorand
                | Chain::Tezos | Chain::Tron => 6,
            
            // Other
            Chain::Stellar => 7,
            Chain::Hedera | Chain::Aptos | Chain::InternetComputer | Chain::Neo
                | Chain::Nervos => 8,
            Chain::Polkadot => 10,
            Chain::Kusama | Chain::Acala => 12,
            Chain::Monero => 12,
            Chain::Eos | Chain::Ontology => 4,
            Chain::Zilliqa => 12,
            Chain::Flow | Chain::Mina => 8,
        }
    }

    /// Required confirmations for finality
    pub fn required_confirmations(&self) -> u32 {
        match self {
            // UTXO chains need more confirmations
            Chain::Bitcoin | Chain::Litecoin | Chain::Zcash | Chain::Dash => 6,
            Chain::Dogecoin | Chain::BitcoinCash | Chain::Ravencoin 
                | Chain::DigiByte | Chain::Firo => 6,
            Chain::BitcoinTestnet => 1,
            
            // EVM L1
            Chain::Ethereum | Chain::Bnb | Chain::Polygon | Chain::Avalanche => 12,
            Chain::EthereumSepolia => 1,
            
            // EVM L2s (fast finality)
            Chain::Arbitrum | Chain::Optimism | Chain::Base | Chain::ZkSync
                | Chain::PolygonZkEvm | Chain::Linea | Chain::Scroll 
                | Chain::Mantle | Chain::Blast => 1,
            Chain::Fantom | Chain::Cronos | Chain::Gnosis | Chain::Celo
                | Chain::Moonbeam | Chain::Moonriver | Chain::Aurora 
                | Chain::Metis | Chain::Boba => 12,
            
            // Fast finality chains
            Chain::Solana | Chain::SolanaDevnet | Chain::Xrp | Chain::XrpTestnet
                | Chain::Cosmos | Chain::Osmosis | Chain::Celestia | Chain::Dydx
                | Chain::Injective | Chain::Sei | Chain::Kava | Chain::Akash
                | Chain::Secret | Chain::Stargaze | Chain::Juno | Chain::Terra
                | Chain::Neutron | Chain::Noble | Chain::Axelar | Chain::Stride
                | Chain::Polkadot | Chain::Kusama | Chain::Acala
                | Chain::Cardano | Chain::Tron | Chain::Algorand | Chain::Stellar
                | Chain::Near | Chain::Tezos | Chain::Hedera | Chain::Aptos
                | Chain::Sui | Chain::Ton | Chain::Vechain | Chain::Harmony
                | Chain::Oasis | Chain::Filecoin | Chain::InternetComputer
                | Chain::Waves | Chain::Neo | Chain::Eos | Chain::Ontology
                | Chain::Zilliqa | Chain::Nervos | Chain::MultiversX
                | Chain::Flow | Chain::Mina => 1,
            
            Chain::Monero => 10,
        }
    }
}

impl std::str::FromStr for Chain {
    type Err = String;
    
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().replace("-", "_").as_str() {
            // Bitcoin & forks
            "bitcoin" | "btc" => Ok(Chain::Bitcoin),
            "bitcoin_testnet" | "btc_testnet" => Ok(Chain::BitcoinTestnet),
            "litecoin" | "ltc" => Ok(Chain::Litecoin),
            "dogecoin" | "doge" => Ok(Chain::Dogecoin),
            "bitcoin_cash" | "bch" | "bitcoincash" => Ok(Chain::BitcoinCash),
            "zcash" | "zec" => Ok(Chain::Zcash),
            "dash" => Ok(Chain::Dash),
            "ravencoin" | "rvn" => Ok(Chain::Ravencoin),
            "digibyte" | "dgb" => Ok(Chain::DigiByte),
            "firo" => Ok(Chain::Firo),
            
            // Ethereum & EVM
            "ethereum" | "eth" => Ok(Chain::Ethereum),
            "ethereum_sepolia" | "sepolia" => Ok(Chain::EthereumSepolia),
            "bnb" | "bsc" | "binance" | "smartchain" => Ok(Chain::Bnb),
            "polygon" | "matic" | "pol" => Ok(Chain::Polygon),
            "arbitrum" | "arb" => Ok(Chain::Arbitrum),
            "optimism" | "op" => Ok(Chain::Optimism),
            "base" => Ok(Chain::Base),
            "avalanche" | "avax" => Ok(Chain::Avalanche),
            "fantom" | "ftm" => Ok(Chain::Fantom),
            "cronos" | "cro" => Ok(Chain::Cronos),
            "gnosis" | "xdai" => Ok(Chain::Gnosis),
            "celo" => Ok(Chain::Celo),
            "moonbeam" | "glmr" => Ok(Chain::Moonbeam),
            "moonriver" | "movr" => Ok(Chain::Moonriver),
            "aurora" => Ok(Chain::Aurora),
            "metis" => Ok(Chain::Metis),
            "boba" => Ok(Chain::Boba),
            "zksync" | "zksync_era" => Ok(Chain::ZkSync),
            "polygon_zkevm" | "polygonzkevm" => Ok(Chain::PolygonZkEvm),
            "linea" => Ok(Chain::Linea),
            "scroll" => Ok(Chain::Scroll),
            "mantle" | "mnt" => Ok(Chain::Mantle),
            "blast" => Ok(Chain::Blast),
            
            // Solana
            "solana" | "sol" => Ok(Chain::Solana),
            "solana_devnet" | "sol_devnet" => Ok(Chain::SolanaDevnet),
            
            // XRP
            "xrp" | "ripple" => Ok(Chain::Xrp),
            "xrp_testnet" => Ok(Chain::XrpTestnet),
            
            // Cosmos ecosystem
            "cosmos" | "atom" | "cosmoshub" => Ok(Chain::Cosmos),
            "osmosis" | "osmo" => Ok(Chain::Osmosis),
            "celestia" | "tia" => Ok(Chain::Celestia),
            "dydx" => Ok(Chain::Dydx),
            "injective" | "inj" => Ok(Chain::Injective),
            "sei" => Ok(Chain::Sei),
            "kava" => Ok(Chain::Kava),
            "akash" | "akt" => Ok(Chain::Akash),
            "secret" | "scrt" => Ok(Chain::Secret),
            "stargaze" | "stars" => Ok(Chain::Stargaze),
            "juno" => Ok(Chain::Juno),
            "terra" | "luna" => Ok(Chain::Terra),
            "neutron" | "ntrn" => Ok(Chain::Neutron),
            "noble" => Ok(Chain::Noble),
            "axelar" | "axl" => Ok(Chain::Axelar),
            "stride" | "strd" => Ok(Chain::Stride),
            
            // Substrate-based
            "polkadot" | "dot" => Ok(Chain::Polkadot),
            "kusama" | "ksm" => Ok(Chain::Kusama),
            "acala" | "aca" => Ok(Chain::Acala),
            
            // L1 chains
            "cardano" | "ada" => Ok(Chain::Cardano),
            "tron" | "trx" => Ok(Chain::Tron),
            "algorand" | "algo" => Ok(Chain::Algorand),
            "stellar" | "xlm" => Ok(Chain::Stellar),
            "near" => Ok(Chain::Near),
            "tezos" | "xtz" => Ok(Chain::Tezos),
            "hedera" | "hbar" => Ok(Chain::Hedera),
            "aptos" | "apt" => Ok(Chain::Aptos),
            "sui" => Ok(Chain::Sui),
            "ton" => Ok(Chain::Ton),
            "vechain" | "vet" => Ok(Chain::Vechain),
            "harmony" | "one" => Ok(Chain::Harmony),
            "oasis" | "rose" => Ok(Chain::Oasis),
            "filecoin" | "fil" => Ok(Chain::Filecoin),
            "internet_computer" | "icp" => Ok(Chain::InternetComputer),
            "waves" => Ok(Chain::Waves),
            "neo" => Ok(Chain::Neo),
            "eos" => Ok(Chain::Eos),
            "ontology" | "ont" => Ok(Chain::Ontology),
            "zilliqa" | "zil" => Ok(Chain::Zilliqa),
            "nervos" | "ckb" => Ok(Chain::Nervos),
            "multiversx" | "elrond" | "egld" => Ok(Chain::MultiversX),
            "flow" => Ok(Chain::Flow),
            "mina" => Ok(Chain::Mina),
            
            // Privacy coins
            "monero" | "xmr" => Ok(Chain::Monero),
            
            _ => Err(format!("Unknown chain: {}", s)),
        }
    }
}

// =============================================================================
// Wallet Types
// =============================================================================

/// Generated keys for all supported chains
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AllKeys {
    // Bitcoin & forks
    pub bitcoin: BitcoinKeys,
    pub bitcoin_testnet: BitcoinKeys,
    pub litecoin: LitecoinKeys,
    pub dogecoin: DogecoinKeys,
    pub bitcoin_cash: BitcoinCashKeys,
    pub zcash: ZcashKeys,
    pub dash: DashKeys,
    pub ravencoin: RavencoinKeys,
    
    // EVM (shared key)
    pub ethereum: EthereumKeys,
    pub ethereum_sepolia: EthereumKeys,
    pub bnb: EvmKeys,
    
    // Solana
    pub solana: SolanaKeys,
    
    // XRP
    pub xrp: XrpKeys,
    
    // Privacy
    pub monero: MoneroKeys,
    
    // Cosmos ecosystem (shared secp256k1 key)
    pub cosmos: CosmosKeys,
    
    // Substrate-based (shared ed25519 key)
    pub polkadot: PolkadotKeys,
    
    // Move-based
    pub aptos: AptosKeys,
    pub sui: SuiKeys,
    
    // Other L1s
    pub cardano: CardanoKeys,
    pub tron: TronKeys,
    pub algorand: AlgorandKeys,
    pub stellar: StellarKeys,
    pub near: NearKeys,
    pub tezos: TezosKeys,
    pub hedera: HederaKeys,
    pub ton: TonKeys,
    pub vechain: VechainKeys,
    pub harmony: HarmonyKeys,
    pub oasis: OasisKeys,
    pub filecoin: FilecoinKeys,
    pub internet_computer: InternetComputerKeys,
    pub waves: WavesKeys,
    pub multiversx: MultiversXKeys,
    pub flow: FlowKeys,
    pub mina: MinaKeys,
    pub zilliqa: ZilliqaKeys,
    pub eos: EosKeys,
    pub neo: NeoKeys,
    pub nervos: NervosKeys,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BitcoinKeys {
    pub private_hex: String,
    pub private_wif: String,
    pub public_compressed_hex: String,
    pub address: String,
    pub taproot_address: Option<String>,
    pub x_only_pubkey: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LitecoinKeys {
    pub private_hex: String,
    pub private_wif: String,
    pub public_compressed_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MoneroKeys {
    pub private_spend_hex: String,
    pub private_view_hex: String,
    pub public_spend_hex: String,
    pub public_view_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SolanaKeys {
    pub private_seed_hex: String,
    pub private_key_base58: String,
    pub public_key_base58: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EthereumKeys {
    pub private_hex: String,
    pub public_uncompressed_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvmKeys {
    pub private_hex: String,
    pub public_uncompressed_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct XrpKeys {
    pub private_hex: String,
    pub public_compressed_hex: String,
    pub classic_address: String,
}

// New chain key types from wallet-core integration

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TonKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AptosKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SuiKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PolkadotKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub address: String,
    /// Kusama address (same keypair, different network prefix)
    pub kusama_address: String,
}

// Additional chain key types (wallet-core expansion)

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DogecoinKeys {
    pub private_hex: String,
    pub private_wif: String,
    pub public_compressed_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BitcoinCashKeys {
    pub private_hex: String,
    pub private_wif: String,
    pub public_compressed_hex: String,
    pub legacy_address: String,
    pub cash_address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CosmosKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub cosmos_address: String,
    pub osmosis_address: String,
    pub celestia_address: String,
    pub dydx_address: String,
    pub injective_address: String,
    pub sei_address: String,
    pub akash_address: String,
    pub kujira_address: String,
    pub stride_address: String,
    pub secret_address: String,
    pub stargaze_address: String,
    pub juno_address: String,
    pub terra_address: String,
    pub neutron_address: String,
    pub noble_address: String,
    pub axelar_address: String,
    pub fetch_address: String,
    pub persistence_address: String,
    pub sommelier_address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CardanoKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TronKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AlgorandKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StellarKeys {
    pub private_hex: String,
    pub secret_key: String,
    pub public_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NearKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub implicit_address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TezosKeys {
    pub private_hex: String,
    pub secret_key: String,
    pub public_hex: String,
    pub public_key: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HederaKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub public_key_der: String,
}

// New additional chain key types

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZcashKeys {
    pub private_hex: String,
    pub private_wif: String,
    pub public_compressed_hex: String,
    pub transparent_address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DashKeys {
    pub private_hex: String,
    pub private_wif: String,
    pub public_compressed_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RavencoinKeys {
    pub private_hex: String,
    pub private_wif: String,
    pub public_compressed_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VechainKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FilecoinKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HarmonyKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub address: String,
    pub bech32_address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OasisKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InternetComputerKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub principal_id: String,
    pub account_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WavesKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MultiversXKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FlowKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MinaKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZilliqaKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub address: String,
    pub bech32_address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EosKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub public_key: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NeoKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub address: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NervosKeys {
    pub private_hex: String,
    pub public_hex: String,
    pub address: String,
}

/// Wallet creation response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WalletResponse {
    pub mnemonic: String,
    pub keys: AllKeys,
}

// =============================================================================
// Transaction Types
// =============================================================================

/// UTXO for Bitcoin-like chains
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Utxo {
    pub txid: String,
    pub vout: u32,
    pub value: u64,
    pub script_pubkey: Option<String>,
    pub confirmed: bool,
    pub block_height: Option<u32>,
}

/// Universal transaction request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransactionRequest {
    pub chain: Chain,
    pub from: String,
    pub to: String,
    pub amount: String,
    pub private_key: String,
    
    // UTXO chains
    pub utxos: Option<Vec<Utxo>>,
    pub fee_rate: Option<u64>,
    
    // EVM chains
    pub nonce: Option<u64>,
    pub gas_limit: Option<u64>,
    pub gas_price: Option<String>,
    pub max_fee_per_gas: Option<String>,
    pub max_priority_fee_per_gas: Option<String>,
    pub data: Option<String>,
    
    // Solana
    pub recent_blockhash: Option<String>,
    
    // XRP
    pub sequence: Option<u32>,
    pub destination_tag: Option<u32>,
}

/// Signed transaction result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignedTransaction {
    pub chain: Chain,
    pub raw_tx: String,
    pub txid: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub estimated_fee: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size_bytes: Option<u32>,
}

/// Broadcast result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BroadcastResult {
    pub chain: Chain,
    pub txid: String,
    pub success: bool,
    pub error_message: Option<String>,
    pub explorer_url: Option<String>,
}

/// Transaction status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TransactionStatus {
    Pending,
    Confirming,
    Confirmed,
    Failed,
    Dropped,
}

/// Tracked transaction info
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackedTransaction {
    pub txid: String,
    pub chain: Chain,
    pub status: TransactionStatus,
    pub confirmations: u32,
    pub required_confirmations: u32,
    pub block_height: Option<u64>,
    pub timestamp: Option<u64>,
}

// =============================================================================
// Fee Types
// =============================================================================

/// Fee level presets
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeeLevel {
    pub label: String,
    pub rate: u64,           // sat/vB for BTC, gwei for EVM
    pub estimated_minutes: u32,
}

/// Bitcoin/UTXO fee estimates
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BitcoinFeeEstimate {
    pub fastest: FeeLevel,
    pub fast: FeeLevel,
    pub medium: FeeLevel,
    pub slow: FeeLevel,
    pub minimum: FeeLevel,
}

/// Litecoin fee estimates
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LitecoinFeeEstimate {
    pub fast: FeeLevel,
    pub medium: FeeLevel,
    pub slow: FeeLevel,
    pub mempool_congestion: i64,
}

/// Ethereum/EVM fee estimates
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvmFeeEstimate {
    pub base_fee: String,
    pub priority_fee_low: String,
    pub priority_fee_medium: String,
    pub priority_fee_high: String,
    pub gas_price_legacy: String,
    pub chain_id: u64,
}

/// Solana fee estimates
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SolanaFeeEstimate {
    pub base_fee_lamports: u64,
    pub priority_fee_low: u64,
    pub priority_fee_medium: u64,
    pub priority_fee_high: u64,
}

/// XRP fee estimates
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct XrpFeeEstimate {
    pub open_ledger_fee_drops: u64,
    pub minimum_fee_drops: u64,
    pub median_fee_drops: u64,
    pub current_queue_size: i64,
}

/// Universal fee estimate response
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum FeeEstimate {
    #[serde(rename = "bitcoin")]
    Bitcoin(BitcoinFeeEstimate),
    #[serde(rename = "litecoin")]
    Litecoin(LitecoinFeeEstimate),
    #[serde(rename = "evm")]
    Evm(EvmFeeEstimate),
    #[serde(rename = "solana")]
    Solana(SolanaFeeEstimate),
    #[serde(rename = "xrp")]
    Xrp(XrpFeeEstimate),
}

/// Gas estimation result for EVM chains
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GasEstimateResult {
    pub estimated_gas: u64,
    pub recommended_gas: u64,
    pub is_estimated: bool,
    pub error_message: Option<String>,
}

/// Common EVM transaction types for gas estimation
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EvmTransactionType {
    EthTransfer,
    Erc20Transfer,
    Erc20Approval,
    NftTransfer,
    ContractInteraction,
    Swap,
}

// =============================================================================
// History Types
// =============================================================================

/// Transaction history entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransactionEntry {
    pub txid: String,
    pub chain: Chain,
    pub direction: TransactionDirection,
    pub amount: String,
    pub fee: Option<String>,
    pub from: String,
    pub to: String,
    pub timestamp: Option<u64>,
    pub block_height: Option<u64>,
    pub confirmations: u32,
    pub status: TransactionStatus,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TransactionDirection {
    Incoming,
    Outgoing,
    Self_,
}

/// History fetch request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HistoryRequest {
    pub addresses: Vec<AddressWithChain>,
    pub limit: Option<u32>,
    pub offset: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AddressWithChain {
    pub address: String,
    pub chain: Chain,
}

// =============================================================================
// Balance Types
// =============================================================================

/// Balance for a single address
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Balance {
    pub chain: Chain,
    pub address: String,
    pub balance: String,
    pub balance_raw: String,
}

/// Multi-chain balance request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BalanceRequest {
    pub addresses: Vec<AddressWithChain>,
}

/// Multi-chain balance response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BalanceResponse {
    pub balances: Vec<Balance>,
}

// =============================================================================
// API Response Wrapper
// =============================================================================

/// Standard API response wrapper for FFI
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiResponse<T> {
    pub success: bool,
    pub data: Option<T>,
    pub error: Option<crate::error::HawalaError>,
}

impl<T> ApiResponse<T> {
    pub fn ok(data: T) -> Self {
        Self {
            success: true,
            data: Some(data),
            error: None,
        }
    }

    pub fn err(error: crate::error::HawalaError) -> Self {
        Self {
            success: false,
            data: None,
            error: Some(error),
        }
    }
}

impl<T: Serialize> ApiResponse<T> {
    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| {
            r#"{"success":false,"error":{"code":"internal","message":"Serialization failed"}}"#.to_string()
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_chain_properties() {
        assert!(Chain::Ethereum.is_evm());
        assert!(!Chain::Bitcoin.is_evm());
        assert!(Chain::Bitcoin.is_utxo());
        assert_eq!(Chain::Ethereum.chain_id(), Some(1));
        assert_eq!(Chain::Bitcoin.decimals(), 8);
        assert_eq!(Chain::Ethereum.decimals(), 18);
    }

    #[test]
    fn test_api_response_serialization() {
        let response = ApiResponse::ok("test_data".to_string());
        let json = response.to_json();
        assert!(json.contains("success"));
        assert!(json.contains("test_data"));
    }
}
