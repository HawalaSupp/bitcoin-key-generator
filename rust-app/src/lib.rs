use bech32::{self, Variant};
use bitcoin::hashes::{Hash, hash160, sha256d};
use bitcoin::key::{CompressedPublicKey, PublicKey as BitcoinPublicKey};
use bitcoin::secp256k1::{self, PublicKey as SecpPublicKey, Secp256k1, SecretKey};
use bitcoin::{Address, Network, PrivateKey};
use bs58::Alphabet;
use curve25519_dalek::edwards::EdwardsPoint;
use curve25519_dalek::scalar::Scalar;
use ed25519_dalek::SigningKey;
use rand::RngCore;
use rand::rngs::OsRng;
use serde::{Deserialize, Serialize};
use std::convert::TryFrom;
use std::error::Error;
use tiny_keccak::{Hasher, Keccak};

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct AllKeys {
    pub bitcoin: BitcoinKeys,
    pub litecoin: LitecoinKeys,
    pub monero: MoneroKeys,
    pub solana: SolanaKeys,
    pub ethereum: EthereumKeys,
    pub bnb: BnbKeys,
    pub xrp: XrpKeys,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct BitcoinKeys {
    pub private_hex: String,
    pub private_wif: String,
    pub public_compressed_hex: String,
    pub address: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct LitecoinKeys {
    pub private_hex: String,
    pub private_wif: String,
    pub public_compressed_hex: String,
    pub address: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct MoneroKeys {
    pub private_spend_hex: String,
    pub private_view_hex: String,
    pub public_spend_hex: String,
    pub public_view_hex: String,
    pub address: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct SolanaKeys {
    pub private_seed_hex: String,
    pub private_key_base58: String,
    pub public_key_base58: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct EthereumKeys {
    pub private_hex: String,
    pub public_uncompressed_hex: String,
    pub address: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct BnbKeys {
    pub private_hex: String,
    pub public_uncompressed_hex: String,
    pub address: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct XrpKeys {
    pub private_hex: String,
    pub public_compressed_hex: String,
    pub classic_address: String,
}

pub fn generate_all_keys() -> Result<AllKeys, Box<dyn Error>> {
    let secp = Secp256k1::new();
    let mut rng = OsRng;

    let bitcoin_keys = generate_bitcoin_keys(&secp, &mut rng)?;
    let litecoin_keys = generate_litecoin_keys(&secp, &mut rng)?;
    let monero_keys = generate_monero_keys(&mut rng)?;
    let solana_keys = generate_solana_keys(&mut rng)?;
    let ethereum_keys = generate_ethereum_keys(&secp, &mut rng)?;
    let bnb_keys = generate_bnb_keys(&secp, &mut rng)?;
    let xrp_keys = generate_xrp_keys(&secp, &mut rng)?;

    Ok(AllKeys {
        bitcoin: bitcoin_keys,
        litecoin: litecoin_keys,
        monero: monero_keys,
        solana: solana_keys,
        ethereum: ethereum_keys,
        bnb: bnb_keys,
        xrp: xrp_keys,
    })
}

pub fn generate_bitcoin_keys(
    secp: &Secp256k1<secp256k1::All>,
    rng: &mut OsRng,
) -> Result<BitcoinKeys, Box<dyn Error>> {
    let mut secret_bytes = [0u8; 32];
    rng.fill_bytes(&mut secret_bytes);
    let secret_key = SecretKey::from_slice(&secret_bytes)?;

    let private_hex = hex::encode(secret_key.secret_bytes());
    let secp_public_key = SecpPublicKey::from_secret_key(secp, &secret_key);
    let public_key = BitcoinPublicKey::from(secp_public_key);
    let compressed = CompressedPublicKey::try_from(public_key.clone())?;
    let private_key = PrivateKey::new(secret_key, Network::Bitcoin);
    let address = Address::p2wpkh(&compressed, Network::Bitcoin);

    Ok(BitcoinKeys {
        private_hex,
        private_wif: private_key.to_wif(),
        public_compressed_hex: hex::encode(compressed.to_bytes()),
        address: address.to_string(),
    })
}

pub fn generate_litecoin_keys(
    secp: &Secp256k1<secp256k1::All>,
    rng: &mut OsRng,
) -> Result<LitecoinKeys, Box<dyn Error>> {
    let mut secret_bytes = [0u8; 32];
    rng.fill_bytes(&mut secret_bytes);
    let secret_key = SecretKey::from_slice(&secret_bytes)?;

    let private_hex = hex::encode(secret_key.secret_bytes());
    let secp_public_key = SecpPublicKey::from_secret_key(secp, &secret_key);
    let public_key = BitcoinPublicKey::from(secp_public_key);
    let compressed = CompressedPublicKey::try_from(public_key.clone())?;
    let compressed_bytes = compressed.to_bytes();

    let private_wif = encode_litecoin_wif(&secret_key);
    let pubkey_hash = hash160::Hash::hash(&compressed_bytes);

    let version = bech32::u5::try_from_u8(0).map_err(|e| Box::<dyn Error>::from(e))?;
    let converted = bech32::convert_bits(pubkey_hash.as_ref(), 8, 5, true)
        .map_err(|e| Box::<dyn Error>::from(e))?;
    let mut bech32_data = Vec::with_capacity(1 + converted.len());
    bech32_data.push(version);
    for value in converted {
        let u5 = bech32::u5::try_from_u8(value).map_err(|e| Box::<dyn Error>::from(e))?;
        bech32_data.push(u5);
    }
    let address = bech32::encode("ltc", bech32_data, Variant::Bech32)
        .map_err(|e| Box::<dyn Error>::from(e))?;

    Ok(LitecoinKeys {
        private_hex,
        private_wif,
        public_compressed_hex: hex::encode(compressed_bytes),
        address,
    })
}

pub fn encode_litecoin_wif(secret_key: &SecretKey) -> String {
    let mut data = Vec::with_capacity(34);
    data.push(0xB0);
    data.extend_from_slice(&secret_key.secret_bytes());
    data.push(0x01);

    let checksum = sha256d::Hash::hash(&data);
    let mut payload = data;
    payload.extend_from_slice(&checksum[..4]);

    bs58::encode(payload).into_string()
}

pub fn generate_monero_keys(rng: &mut OsRng) -> Result<MoneroKeys, Box<dyn Error>> {
    let mut spend_seed = [0u8; 32];
    rng.fill_bytes(&mut spend_seed);
    let spend_scalar = Scalar::from_bytes_mod_order(spend_seed);
    let private_spend = spend_scalar.to_bytes();

    let view_seed = keccak256(&private_spend);
    let view_scalar = Scalar::from_bytes_mod_order(view_seed);
    let private_view = view_scalar.to_bytes();

    let spend_point = EdwardsPoint::mul_base(&spend_scalar);
    let view_point = EdwardsPoint::mul_base(&view_scalar);
    let public_spend = spend_point.compress().to_bytes();
    let public_view = view_point.compress().to_bytes();

    let mut data = Vec::with_capacity(1 + 32 + 32 + 4);
    data.push(0x12);
    data.extend_from_slice(&public_spend);
    data.extend_from_slice(&public_view);
    let checksum = keccak256(&data);
    data.extend_from_slice(&checksum[..4]);

    let address = monero_base58_encode(&data);

    Ok(MoneroKeys {
        private_spend_hex: hex::encode(private_spend),
        private_view_hex: hex::encode(private_view),
        public_spend_hex: hex::encode(public_spend),
        public_view_hex: hex::encode(public_view),
        address,
    })
}

const MONERO_BASE58_ALPHABET: &[u8; 58] =
    b"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
const MONERO_BLOCK_ENCODED_LENGTH: [usize; 9] = [0, 2, 3, 5, 7, 8, 9, 10, 11];

pub fn monero_base58_encode(data: &[u8]) -> String {
    let mut result = String::new();
    let full_chunks = data.len() / 8;
    let remainder = data.len() % 8;

    for chunk_index in 0..full_chunks {
        let start = chunk_index * 8;
        let end = start + 8;
        result.push_str(&encode_monero_block(&data[start..end]));
    }

    if remainder > 0 {
        let start = full_chunks * 8;
        result.push_str(&encode_monero_block(&data[start..]));
    }

    result
}

fn encode_monero_block(block: &[u8]) -> String {
    let mut value: u64 = 0;
    for (index, byte) in block.iter().enumerate() {
        value |= (*byte as u64) << (8 * index);
    }

    let mut chars = Vec::new();
    while value > 0 {
        let remainder = (value % 58) as usize;
        value /= 58;
        chars.push(MONERO_BASE58_ALPHABET[remainder] as char);
    }

    if chars.is_empty() {
        chars.push('1');
    }

    chars.reverse();
    let target_len = MONERO_BLOCK_ENCODED_LENGTH[block.len()];
    while chars.len() < target_len {
        chars.insert(0, '1');
    }

    chars.into_iter().collect()
}

pub fn generate_solana_keys(rng: &mut OsRng) -> Result<SolanaKeys, Box<dyn Error>> {
    let mut seed = [0u8; 32];
    rng.fill_bytes(&mut seed);
    let signing_key = SigningKey::from_bytes(&seed);
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

pub fn generate_ethereum_keys(
    secp: &Secp256k1<secp256k1::All>,
    rng: &mut OsRng,
) -> Result<EthereumKeys, Box<dyn Error>> {
    let mut secret_bytes = [0u8; 32];
    rng.fill_bytes(&mut secret_bytes);
    let secret_key = SecretKey::from_slice(&secret_bytes)?;

    let private_hex = hex::encode(secret_key.secret_bytes());
    let secp_public_key = SecpPublicKey::from_secret_key(secp, &secret_key);
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

pub fn generate_bnb_keys(
    secp: &Secp256k1<secp256k1::All>,
    rng: &mut OsRng,
) -> Result<BnbKeys, Box<dyn Error>> {
    let mut secret_bytes = [0u8; 32];
    rng.fill_bytes(&mut secret_bytes);
    let secret_key = SecretKey::from_slice(&secret_bytes)?;

    let private_hex = hex::encode(secret_key.secret_bytes());
    let secp_public_key = SecpPublicKey::from_secret_key(secp, &secret_key);
    let uncompressed = secp_public_key.serialize_uncompressed();
    let public_key_bytes = &uncompressed[1..];

    let public_uncompressed_hex = hex::encode(public_key_bytes);
    let address_bytes = keccak256(public_key_bytes);
    let address = to_checksum_address(&address_bytes[12..]);

    Ok(BnbKeys {
        private_hex,
        public_uncompressed_hex,
        address,
    })
}

pub fn generate_xrp_keys(
    secp: &Secp256k1<secp256k1::All>,
    rng: &mut OsRng,
) -> Result<XrpKeys, Box<dyn Error>> {
    let mut secret_bytes = [0u8; 32];
    rng.fill_bytes(&mut secret_bytes);
    let secret_key = SecretKey::from_slice(&secret_bytes)?;

    let private_hex = hex::encode(secret_key.secret_bytes());
    let secp_public_key = SecpPublicKey::from_secret_key(secp, &secret_key);
    let compressed = secp_public_key.serialize();

    let account_id = hash160::Hash::hash(&compressed);
    let mut payload = Vec::new();
    payload.push(0x00); // mainnet account prefix
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

pub fn keccak256(data: &[u8]) -> [u8; 32] {
    let mut hasher = Keccak::v256();
    hasher.update(data);
    let mut out = [0u8; 32];
    hasher.finalize(&mut out);
    out
}

pub fn to_checksum_address(address: &[u8]) -> String {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn litecoin_wif_has_correct_prefix() {
        let secret_key = SecretKey::from_slice(&[1u8; 32]).expect("valid secret");
        let wif = encode_litecoin_wif(&secret_key);
        assert!(wif.starts_with('T'));
    }
}
