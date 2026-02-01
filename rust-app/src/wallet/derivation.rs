//! Key Derivation
//!
//! Derives keys for all supported chains from a BIP39 seed.
//!
//! SECURITY: All private key material is zeroized when no longer needed.

use bitcoin::bip32::{DerivationPath, Xpriv};
use bitcoin::hashes::{Hash, hash160, sha256d};
use bitcoin::key::{CompressedPublicKey, PublicKey as BitcoinPublicKey};
use bitcoin::secp256k1::{Secp256k1, SecretKey};
use bitcoin::{Address, Network, PrivateKey};
use bech32::{self, Variant};
use bs58::Alphabet;
use curve25519_dalek::edwards::EdwardsPoint;
use curve25519_dalek::scalar::Scalar;
use ed25519_dalek::SigningKey;
use monero::{Network as MoneroNetwork, Address as MoneroAddress, PublicKey as MoneroPublicKey};
use sha2::{Digest, Sha256};
use std::convert::TryFrom;
use std::str::FromStr;
use tiny_keccak::{Hasher, Keccak};

use crate::error::{HawalaError, HawalaResult};
use crate::types::*;
use crate::taproot_wallet::derive_taproot_address;

/// Derive all keys from a seed
/// 
/// SECURITY: The seed should be wrapped in Zeroizing by the caller
pub fn derive_all_keys(seed: &[u8]) -> HawalaResult<AllKeys> {
    let secp = Secp256k1::new();
    let master = Xpriv::new_master(Network::Bitcoin, seed)?;

    Ok(AllKeys {
        bitcoin: derive_bitcoin_keys(&secp, &master, Network::Bitcoin)?,
        bitcoin_testnet: derive_bitcoin_keys(&secp, &master, Network::Testnet)?,
        litecoin: derive_litecoin_keys(&secp, &master)?,
        monero: derive_monero_keys(seed)?,
        solana: derive_solana_keys(seed)?,
        ethereum: derive_ethereum_keys(&secp, &master)?,
        ethereum_sepolia: derive_ethereum_keys(&secp, &master)?, // Same keys, different network
        bnb: derive_bnb_keys(&secp, &master)?,
        xrp: derive_xrp_keys(&secp, &master)?,
        // New chains from wallet-core integration
        ton: derive_ton_keys(seed)?,
        aptos: derive_aptos_keys(seed)?,
        sui: derive_sui_keys(seed)?,
        polkadot: derive_polkadot_keys(seed)?,
        // Additional chains (wallet-core expansion)
        dogecoin: derive_dogecoin_keys_wrapper(seed)?,
        bitcoin_cash: derive_bitcoin_cash_keys_wrapper(seed)?,
        cosmos: derive_cosmos_keys_wrapper(seed)?,
        cardano: derive_cardano_keys_wrapper(seed)?,
        tron: derive_tron_keys_wrapper(seed)?,
        algorand: derive_algorand_keys_wrapper(seed)?,
        stellar: derive_stellar_keys_wrapper(seed)?,
        near: derive_near_keys_wrapper(seed)?,
        tezos: derive_tezos_keys_wrapper(seed)?,
        hedera: derive_hedera_keys_wrapper(seed)?,
        // Bitcoin forks
        zcash: derive_zcash_keys_wrapper(seed)?,
        dash: derive_dash_keys_wrapper(seed)?,
        ravencoin: derive_ravencoin_keys_wrapper(seed)?,
        // L1 chains
        vechain: derive_vechain_keys_wrapper(seed)?,
        filecoin: derive_filecoin_keys_wrapper(seed)?,
        harmony: derive_harmony_keys_wrapper(seed)?,
        oasis: derive_oasis_keys_wrapper(seed)?,
        internet_computer: derive_icp_keys_wrapper(seed)?,
        waves: derive_waves_keys_wrapper(seed)?,
        multiversx: derive_multiversx_keys_wrapper(seed)?,
        flow: derive_flow_keys_wrapper(seed)?,
        mina: derive_mina_keys_wrapper(seed)?,
        zilliqa: derive_zilliqa_keys_wrapper(seed)?,
        eos: derive_eos_keys_wrapper(seed)?,
        neo: derive_neo_keys_wrapper(seed)?,
        nervos: derive_nervos_keys_wrapper(seed)?,
    })
}

fn derive_bitcoin_keys(
    secp: &Secp256k1<bitcoin::secp256k1::All>,
    master: &Xpriv,
    network: Network,
) -> HawalaResult<BitcoinKeys> {
    let path = match network {
        Network::Bitcoin => DerivationPath::from_str("m/84'/0'/0'/0/0")?,
        Network::Testnet => DerivationPath::from_str("m/84'/1'/0'/0/0")?,
        _ => DerivationPath::from_str("m/84'/0'/0'/0/0")?,
    };
    
    let child = master.derive_priv(secp, &path)?;
    let secret_key = child.private_key;
    
    let private_hex = hex::encode(secret_key.secret_bytes());
    let secp_public_key = secret_key.public_key(secp);
    let public_key = BitcoinPublicKey::from(secp_public_key);
    let compressed = CompressedPublicKey::try_from(public_key)
        .map_err(|e| HawalaError::crypto_error(format!("Key compression failed: {}", e)))?;
    
    let address = Address::p2wpkh(&compressed, network);
    
    // Derive Taproot address
    let (taproot_address, x_only_pubkey) = match derive_taproot_address(&private_hex, network) {
        Ok((addr, xonly)) => (Some(addr), Some(xonly)),
        Err(_) => (None, None),
    };

    Ok(BitcoinKeys {
        private_hex,
        private_wif: PrivateKey::new(secret_key, network).to_wif(),
        public_compressed_hex: hex::encode(compressed.to_bytes()),
        address: address.to_string(),
        taproot_address,
        x_only_pubkey,
    })
}

fn derive_litecoin_keys(
    secp: &Secp256k1<bitcoin::secp256k1::All>,
    master: &Xpriv,
) -> HawalaResult<LitecoinKeys> {
    let path = DerivationPath::from_str("m/84'/2'/0'/0/0")?;
    let child = master.derive_priv(secp, &path)?;
    let secret_key = child.private_key;

    let private_hex = hex::encode(secret_key.secret_bytes());
    let secp_public_key = secret_key.public_key(secp);
    let public_key = BitcoinPublicKey::from(secp_public_key);
    let compressed = CompressedPublicKey::try_from(public_key)
        .map_err(|e| HawalaError::crypto_error(format!("Key compression failed: {}", e)))?;
    let compressed_bytes = compressed.to_bytes();

    let private_wif = encode_litecoin_wif(&secret_key);
    let pubkey_hash = hash160::Hash::hash(&compressed_bytes);

    // Bech32 encode for Litecoin
    let version = bech32::u5::try_from_u8(0)
        .map_err(|e| HawalaError::crypto_error(format!("Bech32 error: {}", e)))?;
    let converted = bech32::convert_bits(pubkey_hash.as_ref(), 8, 5, true)
        .map_err(|e| HawalaError::crypto_error(format!("Bech32 error: {}", e)))?;
    let mut bech32_data = Vec::with_capacity(1 + converted.len());
    bech32_data.push(version);
    for value in converted {
        let u5 = bech32::u5::try_from_u8(value)
            .map_err(|e| HawalaError::crypto_error(format!("Bech32 error: {}", e)))?;
        bech32_data.push(u5);
    }
    let address = bech32::encode("ltc", bech32_data, Variant::Bech32)
        .map_err(|e| HawalaError::crypto_error(format!("Bech32 error: {}", e)))?;

    Ok(LitecoinKeys {
        private_hex,
        private_wif,
        public_compressed_hex: hex::encode(compressed_bytes),
        address,
    })
}

fn derive_monero_keys(seed: &[u8]) -> HawalaResult<MoneroKeys> {
    let mut hasher = Sha256::new();
    hasher.update(seed);
    hasher.update(b"MONERO_DERIVATION");
    let result = hasher.finalize();
    
    let mut spend_seed = [0u8; 32];
    spend_seed.copy_from_slice(&result);
    
    let spend_scalar = Scalar::from_bytes_mod_order(spend_seed);
    let private_spend = spend_scalar.to_bytes();

    let view_seed = keccak256(&private_spend);
    let view_scalar = Scalar::from_bytes_mod_order(view_seed);
    let private_view = view_scalar.to_bytes();

    let spend_point = EdwardsPoint::mul_base(&spend_scalar);
    let view_point = EdwardsPoint::mul_base(&view_scalar);
    let public_spend_bytes = spend_point.compress().to_bytes();
    let public_view_bytes = view_point.compress().to_bytes();

    let public_spend_key = MoneroPublicKey::from_slice(&public_spend_bytes)
        .map_err(|e| HawalaError::crypto_error(format!("Monero key error: {}", e)))?;
    let public_view_key = MoneroPublicKey::from_slice(&public_view_bytes)
        .map_err(|e| HawalaError::crypto_error(format!("Monero key error: {}", e)))?;
    let address = MoneroAddress::standard(MoneroNetwork::Mainnet, public_spend_key, public_view_key);

    Ok(MoneroKeys {
        private_spend_hex: hex::encode(private_spend),
        private_view_hex: hex::encode(private_view),
        public_spend_hex: hex::encode(public_spend_bytes),
        public_view_hex: hex::encode(public_view_bytes),
        address: address.to_string(),
    })
}

fn derive_solana_keys(seed: &[u8]) -> HawalaResult<SolanaKeys> {
    let mut hasher = Sha256::new();
    hasher.update(seed);
    hasher.update(b"SOLANA_DERIVATION");
    let result = hasher.finalize();
    
    let signing_key = SigningKey::from_bytes(&result.into());
    let private_seed = signing_key.to_bytes();
    let public_key_bytes = signing_key.verifying_key().to_bytes();

    let mut keypair_bytes = [0u8; 64];
    keypair_bytes[..32].copy_from_slice(&private_seed);
    keypair_bytes[32..].copy_from_slice(&public_key_bytes);

    Ok(SolanaKeys {
        private_seed_hex: hex::encode(private_seed),
        private_key_base58: bs58::encode(keypair_bytes).into_string(),
        public_key_base58: bs58::encode(public_key_bytes).into_string(),
    })
}

fn derive_ethereum_keys(
    secp: &Secp256k1<bitcoin::secp256k1::All>,
    master: &Xpriv,
) -> HawalaResult<EthereumKeys> {
    let path = DerivationPath::from_str("m/44'/60'/0'/0/0")?;
    let child = master.derive_priv(secp, &path)?;
    let secret_key = child.private_key;

    let private_hex = hex::encode(secret_key.secret_bytes());
    let secp_public_key = secret_key.public_key(secp);
    let uncompressed = secp_public_key.serialize_uncompressed();
    let public_key_bytes = &uncompressed[1..];

    let public_uncompressed_hex = hex::encode(public_key_bytes);
    let address_bytes = keccak256(public_key_bytes);
    let address = to_checksum_address(&address_bytes[12..]);

    Ok(EthereumKeys {
        private_hex,
        public_uncompressed_hex,
        address,
    })
}

fn derive_bnb_keys(
    secp: &Secp256k1<bitcoin::secp256k1::All>,
    master: &Xpriv,
) -> HawalaResult<EvmKeys> {
    // BNB uses same derivation as Ethereum
    let path = DerivationPath::from_str("m/44'/60'/0'/0/0")?;
    let child = master.derive_priv(secp, &path)?;
    let secret_key = child.private_key;

    let private_hex = hex::encode(secret_key.secret_bytes());
    let secp_public_key = secret_key.public_key(secp);
    let uncompressed = secp_public_key.serialize_uncompressed();
    let public_key_bytes = &uncompressed[1..];

    let public_uncompressed_hex = hex::encode(public_key_bytes);
    let address_bytes = keccak256(public_key_bytes);
    let address = to_checksum_address(&address_bytes[12..]);

    Ok(EvmKeys {
        private_hex,
        public_uncompressed_hex,
        address,
    })
}

fn derive_xrp_keys(
    secp: &Secp256k1<bitcoin::secp256k1::All>,
    master: &Xpriv,
) -> HawalaResult<XrpKeys> {
    let path = DerivationPath::from_str("m/44'/144'/0'/0/0")?;
    let child = master.derive_priv(secp, &path)?;
    let secret_key = child.private_key;

    let private_hex = hex::encode(secret_key.secret_bytes());
    let secp_public_key = secret_key.public_key(secp);
    let compressed = secp_public_key.serialize();

    let account_id = hash160::Hash::hash(&compressed);
    let mut payload = Vec::new();
    payload.push(0x00);
    payload.extend_from_slice(account_id.as_ref());

    let checksum = sha256d::Hash::hash(&payload);
    let mut address_bytes = payload;
    address_bytes.extend_from_slice(&checksum[..4]);
    let classic_address = bs58::encode(address_bytes)
        .with_alphabet(Alphabet::RIPPLE)
        .into_string();

    Ok(XrpKeys {
        private_hex,
        public_compressed_hex: hex::encode(compressed),
        classic_address,
    })
}

// Helper functions

fn keccak256(data: &[u8]) -> [u8; 32] {
    let mut hasher = Keccak::v256();
    hasher.update(data);
    let mut out = [0u8; 32];
    hasher.finalize(&mut out);
    out
}

fn to_checksum_address(address: &[u8]) -> String {
    let lower = hex::encode(address);
    let hash = keccak256(lower.as_bytes());

    let mut result = String::from("0x");
    for (i, ch) in lower.chars().enumerate() {
        let byte = hash[i / 2];
        let nibble = if i % 2 == 0 { byte >> 4 } else { byte & 0x0f };

        if ch.is_ascii_digit() {
            result.push(ch);
        } else if nibble >= 8 {
            result.push(ch.to_ascii_uppercase());
        } else {
            result.push(ch);
        }
    }

    result
}

fn encode_litecoin_wif(secret_key: &SecretKey) -> String {
    let mut data = Vec::with_capacity(34);
    data.push(0xB0); // Litecoin mainnet WIF prefix
    data.extend_from_slice(&secret_key.secret_bytes());
    data.push(0x01); // Compressed flag

    let checksum = sha256d::Hash::hash(&data);
    let mut payload = data;
    payload.extend_from_slice(&checksum[..4]);

    bs58::encode(payload).into_string()
}

// New chain derivation functions

fn derive_ton_keys(seed: &[u8]) -> HawalaResult<TonKeys> {
    use crate::ton_wallet::TonKeyPair;
    
    let mut hasher = Sha256::new();
    hasher.update(seed);
    hasher.update(b"TON_DERIVATION");
    let result = hasher.finalize();
    
    let mut seed_bytes = [0u8; 32];
    seed_bytes.copy_from_slice(&result);
    
    let keypair = TonKeyPair::from_seed(&seed_bytes)?;
    
    Ok(TonKeys {
        private_hex: hex::encode(seed_bytes),
        public_hex: hex::encode(keypair.public_key),
        address: keypair.address.to_user_friendly(),
    })
}

fn derive_aptos_keys(seed: &[u8]) -> HawalaResult<AptosKeys> {
    use crate::aptos_wallet::AptosKeyPair;
    
    // Convert seed to 64 bytes for HD derivation
    let mut seed64 = [0u8; 64];
    seed64[..seed.len().min(64)].copy_from_slice(&seed[..seed.len().min(64)]);
    
    let keypair = AptosKeyPair::from_mnemonic_seed(&seed64, 0)?;
    
    Ok(AptosKeys {
        private_hex: hex::encode(keypair.signing_key.to_bytes()),
        public_hex: hex::encode(keypair.public_key),
        address: keypair.address.to_hex(),
    })
}

fn derive_sui_keys(seed: &[u8]) -> HawalaResult<SuiKeys> {
    use crate::sui_wallet::SuiKeyPair;
    
    // Convert seed to 64 bytes for HD derivation
    let mut seed64 = [0u8; 64];
    seed64[..seed.len().min(64)].copy_from_slice(&seed[..seed.len().min(64)]);
    
    let keypair = SuiKeyPair::from_mnemonic_seed(&seed64, 0)?;
    
    Ok(SuiKeys {
        private_hex: hex::encode(keypair.signing_key.to_bytes()),
        public_hex: hex::encode(keypair.public_key),
        address: keypair.address.to_hex(),
    })
}

fn derive_polkadot_keys(seed: &[u8]) -> HawalaResult<PolkadotKeys> {
    use crate::polkadot_wallet::{SubstrateKeyPair, Ss58Network};
    
    // Convert seed to 64 bytes for HD derivation
    let mut seed64 = [0u8; 64];
    seed64[..seed.len().min(64)].copy_from_slice(&seed[..seed.len().min(64)]);
    
    let keypair = SubstrateKeyPair::from_mnemonic_seed(&seed64, 0, Ss58Network::Polkadot)?;
    
    // Create addresses for both Polkadot and Kusama
    let kusama_addr = keypair.address_for_network(Ss58Network::Kusama);
    
    Ok(PolkadotKeys {
        private_hex: hex::encode(keypair.signing_key.to_bytes()),
        public_hex: hex::encode(keypair.public_key),
        address: keypair.address.to_ss58(),
        kusama_address: kusama_addr.to_ss58(),
    })
}

// =============================================================================
// New Chain Wrapper Functions
// =============================================================================

fn derive_dogecoin_keys_wrapper(seed: &[u8]) -> HawalaResult<DogecoinKeys> {
    let doge_keys = crate::dogecoin_wallet::derive_dogecoin_keys(seed)
        .map_err(crate::error::HawalaError::crypto_error)?;
    
    Ok(DogecoinKeys {
        private_hex: doge_keys.private_hex,
        private_wif: doge_keys.private_wif,
        public_compressed_hex: doge_keys.public_compressed_hex,
        address: doge_keys.address,
    })
}

fn derive_bitcoin_cash_keys_wrapper(seed: &[u8]) -> HawalaResult<BitcoinCashKeys> {
    let bch_keys = crate::bitcoin_cash_wallet::derive_bitcoin_cash_keys(seed)
        .map_err(crate::error::HawalaError::crypto_error)?;
    
    Ok(BitcoinCashKeys {
        private_hex: bch_keys.private_hex,
        private_wif: bch_keys.private_wif,
        public_compressed_hex: bch_keys.public_compressed_hex,
        legacy_address: bch_keys.legacy_address,
        cash_address: bch_keys.cash_address,
    })
}

fn derive_cosmos_keys_wrapper(seed: &[u8]) -> HawalaResult<CosmosKeys> {
    let cosmos = crate::cosmos_wallet::derive_cosmos_keys(seed)
        .map_err(crate::error::HawalaError::crypto_error)?;
    
    Ok(CosmosKeys {
        private_hex: cosmos.private_hex,
        public_hex: cosmos.public_hex,
        cosmos_address: cosmos.cosmos_address,
        osmosis_address: cosmos.osmosis_address,
        celestia_address: cosmos.celestia_address,
        dydx_address: cosmos.dydx_address,
        injective_address: cosmos.injective_address,
        sei_address: cosmos.sei_address,
        akash_address: cosmos.akash_address,
        kujira_address: cosmos.kujira_address,
        stride_address: cosmos.stride_address,
        secret_address: cosmos.secret_address,
        stargaze_address: cosmos.stargaze_address,
        juno_address: cosmos.juno_address,
        terra_address: cosmos.terra_address,
        neutron_address: cosmos.neutron_address,
        noble_address: cosmos.noble_address,
        axelar_address: cosmos.axelar_address,
        fetch_address: cosmos.fetch_address,
        persistence_address: cosmos.persistence_address,
        sommelier_address: cosmos.sommelier_address,
    })
}

fn derive_cardano_keys_wrapper(seed: &[u8]) -> HawalaResult<CardanoKeys> {
    let ada = crate::cardano_wallet::derive_cardano_keys(seed)
        .map_err(crate::error::HawalaError::crypto_error)?;
    
    Ok(CardanoKeys {
        private_hex: ada.private_hex,
        public_hex: ada.public_hex,
        address: ada.address,
    })
}

fn derive_tron_keys_wrapper(seed: &[u8]) -> HawalaResult<TronKeys> {
    let trx = crate::tron_wallet::derive_tron_keys(seed)
        .map_err(crate::error::HawalaError::crypto_error)?;
    
    Ok(TronKeys {
        private_hex: trx.private_hex,
        public_hex: trx.public_hex,
        address: trx.address,
    })
}

fn derive_algorand_keys_wrapper(seed: &[u8]) -> HawalaResult<AlgorandKeys> {
    let algo = crate::algorand_wallet::derive_algorand_keys(seed)
        .map_err(crate::error::HawalaError::crypto_error)?;
    
    Ok(AlgorandKeys {
        private_hex: algo.private_hex,
        public_hex: algo.public_hex,
        address: algo.address,
    })
}

fn derive_stellar_keys_wrapper(seed: &[u8]) -> HawalaResult<StellarKeys> {
    let xlm = crate::stellar_wallet::derive_stellar_keys(seed)
        .map_err(crate::error::HawalaError::crypto_error)?;
    
    Ok(StellarKeys {
        private_hex: xlm.private_hex,
        secret_key: xlm.secret_key,
        public_hex: xlm.public_hex,
        address: xlm.address,
    })
}

fn derive_near_keys_wrapper(seed: &[u8]) -> HawalaResult<NearKeys> {
    let near = crate::near_wallet::derive_near_keys(seed)
        .map_err(crate::error::HawalaError::crypto_error)?;
    
    Ok(NearKeys {
        private_hex: near.private_hex,
        public_hex: near.public_hex,
        implicit_address: near.implicit_address,
    })
}

fn derive_tezos_keys_wrapper(seed: &[u8]) -> HawalaResult<TezosKeys> {
    let xtz = crate::tezos_wallet::derive_tezos_keys(seed)
        .map_err(crate::error::HawalaError::crypto_error)?;
    
    Ok(TezosKeys {
        private_hex: xtz.private_hex,
        secret_key: xtz.secret_key,
        public_hex: xtz.public_hex,
        public_key: xtz.public_key,
        address: xtz.address,
    })
}

fn derive_hedera_keys_wrapper(seed: &[u8]) -> HawalaResult<HederaKeys> {
    let hbar = crate::hedera_wallet::derive_hedera_keys(seed)
        .map_err(crate::error::HawalaError::crypto_error)?;
    
    Ok(HederaKeys {
        private_hex: hbar.private_hex,
        public_hex: hbar.public_hex,
        public_key_der: hbar.public_key_der,
    })
}

// Bitcoin fork wrappers
fn derive_zcash_keys_wrapper(seed: &[u8]) -> HawalaResult<ZcashKeys> {
    crate::zcash_wallet::derive_zcash_keys(seed)
}

fn derive_dash_keys_wrapper(seed: &[u8]) -> HawalaResult<DashKeys> {
    crate::dash_wallet::derive_dash_keys(seed)
}

fn derive_ravencoin_keys_wrapper(seed: &[u8]) -> HawalaResult<RavencoinKeys> {
    crate::ravencoin_wallet::derive_ravencoin_keys(seed)
}

// L1 chain wrappers
fn derive_vechain_keys_wrapper(seed: &[u8]) -> HawalaResult<VechainKeys> {
    crate::vechain_wallet::derive_vechain_keys(seed)
}

fn derive_filecoin_keys_wrapper(seed: &[u8]) -> HawalaResult<FilecoinKeys> {
    crate::filecoin_wallet::derive_filecoin_keys(seed)
}

fn derive_harmony_keys_wrapper(seed: &[u8]) -> HawalaResult<HarmonyKeys> {
    crate::harmony_wallet::derive_harmony_keys(seed)
}

fn derive_oasis_keys_wrapper(seed: &[u8]) -> HawalaResult<OasisKeys> {
    crate::oasis_wallet::derive_oasis_keys(seed)
}

fn derive_icp_keys_wrapper(seed: &[u8]) -> HawalaResult<InternetComputerKeys> {
    crate::internet_computer_wallet::derive_internet_computer_keys(seed)
}

fn derive_waves_keys_wrapper(seed: &[u8]) -> HawalaResult<WavesKeys> {
    crate::waves_wallet::derive_waves_keys(seed)
}

fn derive_multiversx_keys_wrapper(seed: &[u8]) -> HawalaResult<MultiversXKeys> {
    crate::multiversx_wallet::derive_multiversx_keys(seed)
}

fn derive_flow_keys_wrapper(seed: &[u8]) -> HawalaResult<FlowKeys> {
    crate::flow_wallet::derive_flow_keys(seed)
}

fn derive_mina_keys_wrapper(seed: &[u8]) -> HawalaResult<MinaKeys> {
    crate::mina_wallet::derive_mina_keys(seed)
}

fn derive_zilliqa_keys_wrapper(seed: &[u8]) -> HawalaResult<ZilliqaKeys> {
    crate::zilliqa_wallet::derive_zilliqa_keys(seed)
}

fn derive_eos_keys_wrapper(seed: &[u8]) -> HawalaResult<EosKeys> {
    crate::eos_wallet::derive_eos_keys(seed)
}

fn derive_neo_keys_wrapper(seed: &[u8]) -> HawalaResult<NeoKeys> {
    crate::neo_wallet::derive_neo_keys(seed)
}

fn derive_nervos_keys_wrapper(seed: &[u8]) -> HawalaResult<NervosKeys> {
    crate::nervos_wallet::derive_nervos_keys(seed)
}