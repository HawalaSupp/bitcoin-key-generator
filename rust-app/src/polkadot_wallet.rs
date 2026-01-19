//! Polkadot/Substrate Wallet Implementation
//!
//! Provides address generation and transaction signing for Polkadot ecosystem chains.
//! Based on SS58 address format: https://docs.substrate.io/reference/address-formats/
//!
//! Supports:
//! - Polkadot (DOT)
//! - Kusama (KSM)
//! - Generic Substrate chains
//! - Balance transfers
//! - Staking operations

use ed25519_dalek::{SigningKey, VerifyingKey, Signer, Signature};
use blake2::{Blake2b512, Digest};
use serde::{Deserialize, Serialize};
use std::fmt;

use crate::error::{HawalaError, HawalaResult};

/// SS58 address prefix for different networks
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u16)]
pub enum Ss58Network {
    Polkadot = 0,
    Kusama = 2,
    Substrate = 42,  // Generic substrate / Westend
    Acala = 10,
    Moonbeam = 1284,
    Astar = 5,
}

impl Ss58Network {
    pub fn from_prefix(prefix: u16) -> Option<Self> {
        match prefix {
            0 => Some(Self::Polkadot),
            2 => Some(Self::Kusama),
            42 => Some(Self::Substrate),
            10 => Some(Self::Acala),
            5 => Some(Self::Astar),
            _ => None,
        }
    }

    pub fn symbol(&self) -> &'static str {
        match self {
            Self::Polkadot => "DOT",
            Self::Kusama => "KSM",
            Self::Substrate => "UNIT",
            Self::Acala => "ACA",
            Self::Moonbeam => "GLMR",
            Self::Astar => "ASTR",
        }
    }

    pub fn decimals(&self) -> u8 {
        match self {
            Self::Polkadot => 10,
            Self::Kusama => 12,
            _ => 12,
        }
    }
}

/// SS58 encoded address
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SubstrateAddress {
    /// Raw 32-byte public key
    pub public_key: [u8; 32],
    /// Network prefix
    pub network: Ss58Network,
}

impl SubstrateAddress {
    /// Create from public key
    pub fn new(public_key: [u8; 32], network: Ss58Network) -> Self {
        Self { public_key, network }
    }

    /// Parse from SS58 encoded string
    pub fn from_string(s: &str) -> HawalaResult<Self> {
        let bytes = bs58::decode(s)
            .into_vec()
            .map_err(|e| HawalaError::invalid_input(format!("Invalid base58: {}", e)))?;

        if bytes.len() < 35 {
            return Err(HawalaError::invalid_input("Address too short"));
        }

        // Determine prefix length and extract prefix
        let (prefix, prefix_len) = if bytes[0] < 64 {
            (bytes[0] as u16, 1)
        } else if bytes[0] < 128 {
            // Two-byte prefix
            let lower = (bytes[0] & 0x3f) as u16;
            let upper = (bytes[1] as u16) << 6;
            (lower | upper, 2)
        } else {
            return Err(HawalaError::invalid_input("Invalid prefix"));
        };

        // Extract public key (32 bytes after prefix)
        let pk_start = prefix_len;
        let pk_end = pk_start + 32;

        if bytes.len() < pk_end + 2 {
            return Err(HawalaError::invalid_input("Invalid address length"));
        }

        let mut public_key = [0u8; 32];
        public_key.copy_from_slice(&bytes[pk_start..pk_end]);

        // Verify checksum
        let checksum = &bytes[pk_end..pk_end + 2];
        let computed_checksum = compute_ss58_checksum(&bytes[0..pk_end]);
        
        if checksum != computed_checksum {
            return Err(HawalaError::invalid_input("Invalid checksum"));
        }

        let network = Ss58Network::from_prefix(prefix)
            .unwrap_or(Ss58Network::Substrate);

        Ok(Self { public_key, network })
    }

    /// Encode to SS58 string
    pub fn to_ss58(&self) -> String {
        let prefix = self.network as u16;
        
        let mut data = Vec::with_capacity(35);

        // Add prefix
        if prefix < 64 {
            data.push(prefix as u8);
        } else {
            // Two-byte prefix
            data.push(((prefix & 0x003f) | 0x0040) as u8);
            data.push((prefix >> 6) as u8);
        }

        // Add public key
        data.extend_from_slice(&self.public_key);

        // Add checksum
        let checksum = compute_ss58_checksum(&data);
        data.extend_from_slice(&checksum);

        bs58::encode(data).into_string()
    }

    /// Convert to a different network
    pub fn with_network(mut self, network: Ss58Network) -> Self {
        self.network = network;
        self
    }
}

impl fmt::Display for SubstrateAddress {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.to_ss58())
    }
}

/// Compute SS58 checksum (first 2 bytes of Blake2b-512)
fn compute_ss58_checksum(data: &[u8]) -> [u8; 2] {
    const SS58_PREFIX: &[u8] = b"SS58PRE";

    let mut hasher = Blake2b512::new();
    hasher.update(SS58_PREFIX);
    hasher.update(data);
    let hash = hasher.finalize();

    [hash[0], hash[1]]
}

/// Substrate key pair
#[derive(Clone)]
pub struct SubstrateKeyPair {
    pub signing_key: SigningKey,
    pub public_key: [u8; 32],
    pub address: SubstrateAddress,
}

impl SubstrateKeyPair {
    /// Create from seed bytes (32 bytes)
    pub fn from_seed(seed: &[u8; 32], network: Ss58Network) -> HawalaResult<Self> {
        let signing_key = SigningKey::from_bytes(seed);
        let verifying_key: VerifyingKey = (&signing_key).into();
        let public_key = verifying_key.to_bytes();
        let address = SubstrateAddress::new(public_key, network);

        Ok(Self {
            signing_key,
            public_key,
            address,
        })
    }

    /// Create from HD derivation
    /// Polkadot uses m/44'/354'/0'/0'/0' (BIP44 coin type 354)
    pub fn from_mnemonic_seed(seed: &[u8; 64], account: u32, network: Ss58Network) -> HawalaResult<Self> {
        let mut hasher = Blake2b512::new();
        hasher.update(seed);
        hasher.update(b"substrate");
        hasher.update((network as u16).to_be_bytes());
        hasher.update(account.to_be_bytes());
        let hash = hasher.finalize();

        let mut derived = [0u8; 32];
        derived.copy_from_slice(&hash[0..32]);

        Self::from_seed(&derived, network)
    }

    /// Get address for a different network (same keypair)
    pub fn address_for_network(&self, network: Ss58Network) -> SubstrateAddress {
        SubstrateAddress::new(self.public_key, network)
    }

    /// Sign a message
    pub fn sign(&self, message: &[u8]) -> [u8; 64] {
        let signature: Signature = self.signing_key.sign(message);
        signature.to_bytes()
    }
}

/// Substrate extrinsic (transaction) types
#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum SubstrateCall {
    /// Balances.transfer
    BalancesTransfer {
        dest: SubstrateAddress,
        value: u128,
    },
    /// Balances.transferKeepAlive (keeps account alive)
    BalancesTransferKeepAlive {
        dest: SubstrateAddress,
        value: u128,
    },
    /// Staking.bond
    StakingBond {
        controller: SubstrateAddress,
        value: u128,
        payee: RewardDestination,
    },
    /// Staking.nominate
    StakingNominate {
        targets: Vec<SubstrateAddress>,
    },
    /// Staking.unbond
    StakingUnbond {
        value: u128,
    },
    /// System.remark
    SystemRemark {
        remark: Vec<u8>,
    },
}

/// Staking reward destination
#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum RewardDestination {
    Staked,
    Stash,
    Controller,
    Account(SubstrateAddress),
    None,
}

/// Substrate extrinsic (transaction)
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SubstrateExtrinsic {
    /// Call to execute
    pub call: SubstrateCall,
    /// Account nonce
    pub nonce: u32,
    /// Tip (for priority)
    pub tip: u128,
    /// Block hash for mortality
    pub era: ExtrinsicEra,
    /// Genesis hash (for chain identification)
    pub genesis_hash: [u8; 32],
    /// Block hash (for mortality check)
    pub block_hash: [u8; 32],
    /// Spec version
    pub spec_version: u32,
    /// Transaction version
    pub tx_version: u32,
}

/// Extrinsic mortality
#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum ExtrinsicEra {
    /// Immortal transaction
    Immortal,
    /// Mortal transaction (valid for period after block)
    Mortal {
        period: u64,
        phase: u64,
    },
}

impl ExtrinsicEra {
    /// Create a mortal era (default: 64 blocks)
    pub fn mortal(current_block: u64, period: u64) -> Self {
        let period = period.next_power_of_two().clamp(4, 65536);
        let phase = current_block % period;
        Self::Mortal { period, phase }
    }

    /// Encode to bytes
    pub fn encode(&self) -> Vec<u8> {
        match self {
            Self::Immortal => vec![0x00],
            Self::Mortal { period, phase } => {
                let quantize_factor = (*period >> 12).max(1);
                let quantized_phase = phase / quantize_factor;
                let period_log2 = period.trailing_zeros() as u16;
                let encoded = (quantized_phase as u16) << 4 | (period_log2 - 1).min(15);
                encoded.to_le_bytes().to_vec()
            }
        }
    }
}

impl SubstrateExtrinsic {
    /// Create a simple balance transfer
    pub fn transfer(
        dest: SubstrateAddress,
        value: u128,
        nonce: u32,
        genesis_hash: [u8; 32],
        spec_version: u32,
        tx_version: u32,
    ) -> Self {
        Self {
            call: SubstrateCall::BalancesTransfer { dest, value },
            nonce,
            tip: 0,
            era: ExtrinsicEra::Immortal, // Simple case
            genesis_hash,
            block_hash: genesis_hash, // Same for immortal
            spec_version,
            tx_version,
        }
    }

    /// Build the payload for signing
    pub fn build_signing_payload(&self) -> Vec<u8> {
        let mut payload = Vec::new();

        // Call data
        payload.extend_from_slice(&self.encode_call());

        // Era
        payload.extend_from_slice(&self.era.encode());

        // Nonce (compact encoded)
        payload.extend_from_slice(&compact_encode(self.nonce as u128));

        // Tip (compact encoded)
        payload.extend_from_slice(&compact_encode(self.tip));

        // Spec version
        payload.extend_from_slice(&self.spec_version.to_le_bytes());

        // Tx version
        payload.extend_from_slice(&self.tx_version.to_le_bytes());

        // Genesis hash
        payload.extend_from_slice(&self.genesis_hash);

        // Block hash (for mortality)
        payload.extend_from_slice(&self.block_hash);

        // If payload > 256 bytes, hash it
        if payload.len() > 256 {
            let mut hasher = Blake2b512::new();
            hasher.update(&payload);
            let hash = hasher.finalize();
            hash[0..32].to_vec()
        } else {
            payload
        }
    }

    /// Encode the call data
    fn encode_call(&self) -> Vec<u8> {
        let mut data = Vec::new();

        match &self.call {
            SubstrateCall::BalancesTransfer { dest, value } => {
                // Pallet index (Balances = 4 on Polkadot)
                data.push(4);
                // Call index (transfer = 0)
                data.push(0);
                // MultiAddress::Id variant
                data.push(0);
                // Destination public key
                data.extend_from_slice(&dest.public_key);
                // Value (compact)
                data.extend_from_slice(&compact_encode(*value));
            }
            SubstrateCall::BalancesTransferKeepAlive { dest, value } => {
                data.push(4);
                data.push(3); // transferKeepAlive
                data.push(0);
                data.extend_from_slice(&dest.public_key);
                data.extend_from_slice(&compact_encode(*value));
            }
            SubstrateCall::StakingBond { controller, value, payee } => {
                // Staking pallet = 6 on Polkadot
                data.push(6);
                data.push(0); // bond
                data.push(0); // MultiAddress::Id
                data.extend_from_slice(&controller.public_key);
                data.extend_from_slice(&compact_encode(*value));
                
                // Payee
                match payee {
                    RewardDestination::Staked => data.push(0),
                    RewardDestination::Stash => data.push(1),
                    RewardDestination::Controller => data.push(2),
                    RewardDestination::Account(addr) => {
                        data.push(3);
                        data.extend_from_slice(&addr.public_key);
                    }
                    RewardDestination::None => data.push(4),
                }
            }
            SubstrateCall::StakingNominate { targets } => {
                data.push(6);
                data.push(5); // nominate
                
                // Vector of targets
                data.extend_from_slice(&compact_encode(targets.len() as u128));
                for target in targets {
                    data.push(0); // MultiAddress::Id
                    data.extend_from_slice(&target.public_key);
                }
            }
            SubstrateCall::StakingUnbond { value } => {
                data.push(6);
                data.push(2); // unbond
                data.extend_from_slice(&compact_encode(*value));
            }
            SubstrateCall::SystemRemark { remark } => {
                data.push(0); // System pallet
                data.push(0); // remark
                data.extend_from_slice(&compact_encode(remark.len() as u128));
                data.extend_from_slice(remark);
            }
        }

        data
    }

    /// Sign the extrinsic
    pub fn sign(&self, key_pair: &SubstrateKeyPair) -> HawalaResult<SignedExtrinsic> {
        let payload = self.build_signing_payload();
        let signature = key_pair.sign(&payload);

        Ok(SignedExtrinsic {
            extrinsic: self.clone(),
            signature,
            signer: key_pair.address.clone(),
        })
    }
}

/// Signed extrinsic
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SignedExtrinsic {
    pub extrinsic: SubstrateExtrinsic,
    #[serde(with = "crate::serde_bytes::hex64")]
    pub signature: [u8; 64],
    pub signer: SubstrateAddress,
}

impl SignedExtrinsic {
    /// Encode for submission
    pub fn encode(&self) -> Vec<u8> {
        let mut data = Vec::new();

        // Signature type (0x84 = signed, 0x04 = unsigned)
        data.push(0x84);

        // Signer (MultiAddress::Id)
        data.push(0x00);
        data.extend_from_slice(&self.signer.public_key);

        // Signature type (0x00 = Ed25519)
        data.push(0x00);
        data.extend_from_slice(&self.signature);

        // Era
        data.extend_from_slice(&self.extrinsic.era.encode());

        // Nonce
        data.extend_from_slice(&compact_encode(self.extrinsic.nonce as u128));

        // Tip
        data.extend_from_slice(&compact_encode(self.extrinsic.tip));

        // Call
        data.extend_from_slice(&self.extrinsic.encode_call());

        // Prefix with length
        let len_encoded = compact_encode(data.len() as u128);
        let mut result = len_encoded;
        result.extend_from_slice(&data);

        result
    }

    /// Convert to hex for submission
    pub fn to_hex(&self) -> String {
        format!("0x{}", hex::encode(self.encode()))
    }
}

/// SCALE compact encoding
fn compact_encode(value: u128) -> Vec<u8> {
    if value < 0x40 {
        vec![(value << 2) as u8]
    } else if value < 0x4000 {
        let v = (value << 2) | 0x01;
        (v as u16).to_le_bytes().to_vec()
    } else if value < 0x40000000 {
        let v = (value << 2) | 0x02;
        (v as u32).to_le_bytes().to_vec()
    } else {
        // Big integer mode
        let bytes_needed = ((128 - value.leading_zeros()) + 7) / 8;
        let mut result = vec![((bytes_needed - 4) << 2 | 0x03) as u8];
        for i in 0..bytes_needed {
            result.push((value >> (8 * i)) as u8);
        }
        result
    }
}

/// Validate a Substrate address
pub fn validate_address(address: &str) -> bool {
    SubstrateAddress::from_string(address).is_ok()
}

/// Get Polkadot address from seed
pub fn get_polkadot_address(seed: &[u8; 64], account: u32) -> HawalaResult<String> {
    let key_pair = SubstrateKeyPair::from_mnemonic_seed(seed, account, Ss58Network::Polkadot)?;
    Ok(key_pair.address.to_string())
}

/// Get Kusama address from seed
pub fn get_kusama_address(seed: &[u8; 64], account: u32) -> HawalaResult<String> {
    let key_pair = SubstrateKeyPair::from_mnemonic_seed(seed, account, Ss58Network::Kusama)?;
    Ok(key_pair.address.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ss58_checksum() {
        let data = [0u8; 33];
        let checksum = compute_ss58_checksum(&data);
        assert_eq!(checksum.len(), 2);
    }

    #[test]
    fn test_compact_encoding() {
        assert_eq!(compact_encode(0), vec![0x00]);
        assert_eq!(compact_encode(1), vec![0x04]);
        assert_eq!(compact_encode(63), vec![0xfc]);
        assert_eq!(compact_encode(64), vec![0x01, 0x01]);
    }

    #[test]
    fn test_address_roundtrip() {
        let pk = [1u8; 32];
        let addr = SubstrateAddress::new(pk, Ss58Network::Polkadot);
        let ss58 = addr.to_ss58();
        let parsed = SubstrateAddress::from_string(&ss58).unwrap();
        assert_eq!(addr.public_key, parsed.public_key);
    }
}
