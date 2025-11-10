use bitcoin::hashes::{Hash, hash160};
use bitcoin::key::{CompressedPublicKey, PublicKey as BitcoinPublicKey};
use bitcoin::secp256k1::{PublicKey as SecpPublicKey, Secp256k1, SecretKey};
use bitcoin::{Address, Network, PrivateKey};
use curve25519_dalek::edwards::EdwardsPoint;
use curve25519_dalek::scalar::Scalar;
use ed25519_dalek::SigningKey;
use rust_app::{
    AllKeys, BitcoinKeys, EthereumKeys, LitecoinKeys, MoneroKeys, SolanaKeys, encode_litecoin_wif,
    keccak256, monero_base58_encode, to_checksum_address,
};
use std::convert::TryFrom;
use std::env;
use std::error::Error;
use std::fs;
use std::io::{self, Read};

struct ValidationResult {
    name: &'static str,
    success: bool,
    message: String,
}

fn main() -> Result<(), Box<dyn Error>> {
    let args: Vec<String> = env::args().collect();
    let payload = if let Some(path) = args.get(1) {
        fs::read_to_string(path)?
    } else {
        let mut buffer = String::new();
        io::stdin().read_to_string(&mut buffer)?;
        buffer
    };

    let keys: AllKeys = serde_json::from_str(&payload)?;

    let mut results = Vec::new();
    results.push(run_validation("Bitcoin", || {
        validate_bitcoin(&keys.bitcoin)
    }));
    results.push(run_validation("Litecoin", || {
        validate_litecoin(&keys.litecoin)
    }));
    results.push(run_validation("Monero", || validate_monero(&keys.monero)));
    results.push(run_validation("Solana", || validate_solana(&keys.solana)));
    results.push(run_validation("Ethereum", || {
        validate_ethereum(&keys.ethereum)
    }));

    println!("================ Wallet Validation ================");
    for result in &results {
        let status = if result.success {
            "✅ PASS"
        } else {
            "❌ FAIL"
        };
        println!("{:<10} {}", result.name, status);
        if !result.success {
            println!("    {}", result.message);
        }
    }

    let overall_success = results.iter().all(|r| r.success);
    println!("===================================================");
    if overall_success {
        println!("Overall status: ✅ All derived wallets verified");
        Ok(())
    } else {
        println!("Overall status: ❌ Validation failed");
        Err("wallet validation failed".into())
    }
}

fn run_validation<F>(name: &'static str, f: F) -> ValidationResult
where
    F: FnOnce() -> Result<(), String>,
{
    match f() {
        Ok(_) => ValidationResult {
            name,
            success: true,
            message: String::new(),
        },
        Err(err) => ValidationResult {
            name,
            success: false,
            message: err,
        },
    }
}

fn validate_bitcoin(keys: &BitcoinKeys) -> Result<(), String> {
    let secret_bytes = hex::decode(&keys.private_hex).map_err(|e| e.to_string())?;
    let expected_wif = PrivateKey::new(
        SecretKey::from_slice(&secret_bytes).map_err(|e| e.to_string())?,
        Network::Bitcoin,
    )
    .to_wif();
    if expected_wif != keys.private_wif {
        return Err("WIF encoding mismatch".to_string());
    }

    let parsed = PrivateKey::from_wif(&keys.private_wif).map_err(|e| e.to_string())?;
    if parsed.network != Network::Bitcoin.into() {
        return Err("WIF network prefix is not Bitcoin mainnet".to_string());
    }

    let secp = Secp256k1::new();
    let secret_key = SecretKey::from_slice(&secret_bytes).map_err(|e| e.to_string())?;
    let public_key = BitcoinPublicKey::from(SecpPublicKey::from_secret_key(&secp, &secret_key));
    let compressed = CompressedPublicKey::try_from(public_key).map_err(|e| e.to_string())?;
    let compressed_hex = hex::encode(compressed.to_bytes());
    if compressed_hex != keys.public_compressed_hex {
        return Err("Compressed public key does not match private key".to_string());
    }

    let address = Address::p2wpkh(&compressed, Network::Bitcoin).to_string();
    if address != keys.address {
        return Err("Bech32 address mismatch".to_string());
    }

    Ok(())
}

fn validate_litecoin(keys: &LitecoinKeys) -> Result<(), String> {
    let secret_bytes = hex::decode(&keys.private_hex).map_err(|e| e.to_string())?;
    let secret_key = SecretKey::from_slice(&secret_bytes).map_err(|e| e.to_string())?;

    let expected_wif = encode_litecoin_wif(&secret_key);
    if expected_wif != keys.private_wif {
        return Err("Litecoin WIF encoding mismatch".to_string());
    }

    let secp = Secp256k1::new();
    let public_key = BitcoinPublicKey::from(SecpPublicKey::from_secret_key(&secp, &secret_key));
    let compressed = CompressedPublicKey::try_from(public_key).map_err(|e| e.to_string())?;
    let compressed_bytes = compressed.to_bytes();
    let compressed_hex = hex::encode(&compressed_bytes);
    if compressed_hex != keys.public_compressed_hex {
        return Err("Litecoin compressed public key mismatch".to_string());
    }

    let pubkey_hash = hash160::Hash::hash(&compressed_bytes);
    let converted =
        bech32::convert_bits(pubkey_hash.as_ref(), 8, 5, true).map_err(|e| e.to_string())?;
    let mut bech32_data = Vec::with_capacity(1 + converted.len());
    bech32_data.push(bech32::u5::try_from_u8(0).map_err(|e| e.to_string())?);
    for value in converted {
        bech32_data.push(bech32::u5::try_from_u8(value).map_err(|e| e.to_string())?);
    }
    let address =
        bech32::encode("ltc", bech32_data, bech32::Variant::Bech32).map_err(|e| e.to_string())?;
    if address != keys.address {
        return Err("Litecoin Bech32 address mismatch".to_string());
    }

    Ok(())
}

fn validate_monero(keys: &MoneroKeys) -> Result<(), String> {
    let private_spend = hex::decode(&keys.private_spend_hex).map_err(|e| e.to_string())?;
    let private_view = hex::decode(&keys.private_view_hex).map_err(|e| e.to_string())?;
    if private_spend.len() != 32 || private_view.len() != 32 {
        return Err("Monero private keys must be 32 bytes".to_string());
    }

    if hex::decode(&keys.public_spend_hex)
        .map(|bytes| bytes.len())
        .unwrap_or_default()
        != 32
    {
        return Err("Monero public spend key must be 32 bytes".to_string());
    }

    if hex::decode(&keys.public_view_hex)
        .map(|bytes| bytes.len())
        .unwrap_or_default()
        != 32
    {
        return Err("Monero public view key must be 32 bytes".to_string());
    }

    let mut spend_array = [0u8; 32];
    spend_array.copy_from_slice(&private_spend);
    let spend_scalar = Scalar::from_bytes_mod_order(spend_array);

    let computed_view_seed = keccak256(&spend_scalar.to_bytes());
    let computed_view_scalar = Scalar::from_bytes_mod_order(computed_view_seed);
    let expected_private_view = computed_view_scalar.to_bytes();
    if hex::encode(expected_private_view) != keys.private_view_hex {
        return Err("Monero private view key does not match keccak(spend)".to_string());
    }

    let mut view_array = [0u8; 32];
    view_array.copy_from_slice(&private_view);
    let view_scalar = Scalar::from_bytes_mod_order(view_array);

    let computed_public_spend = EdwardsPoint::mul_base(&spend_scalar).compress().to_bytes();
    if hex::encode(computed_public_spend) != keys.public_spend_hex {
        return Err("Monero public spend key mismatch".to_string());
    }

    let computed_public_view = EdwardsPoint::mul_base(&view_scalar).compress().to_bytes();
    if hex::encode(computed_public_view) != keys.public_view_hex {
        return Err("Monero public view key mismatch".to_string());
    }

    let mut data = Vec::with_capacity(1 + 32 + 32 + 4);
    data.push(0x12);
    data.extend_from_slice(&computed_public_spend);
    data.extend_from_slice(&computed_public_view);
    let checksum = keccak256(&data);
    data.extend_from_slice(&checksum[..4]);
    let expected_address = monero_base58_encode(&data);

    if expected_address != keys.address {
        return Err("Monero primary address mismatch".to_string());
    }

    Ok(())
}

fn validate_solana(keys: &SolanaKeys) -> Result<(), String> {
    let seed_bytes = hex::decode(&keys.private_seed_hex).map_err(|e| e.to_string())?;
    if seed_bytes.len() != 32 {
        return Err("Solana seed must be 32 bytes".to_string());
    }

    let mut seed_array = [0u8; 32];
    seed_array.copy_from_slice(&seed_bytes);
    let signing_key = SigningKey::from_bytes(&seed_array);
    let public_key_bytes = signing_key.verifying_key().to_bytes();

    let keypair_bytes = bs58::decode(&keys.private_key_base58)
        .into_vec()
        .map_err(|e| e.to_string())?;
    if keypair_bytes.len() != 64 {
        return Err("Solana keypair must be 64 bytes".to_string());
    }
    if keypair_bytes[..32] != seed_bytes {
        return Err("Solana keypair does not embed the seed".to_string());
    }
    if keypair_bytes[32..] != public_key_bytes {
        return Err("Solana keypair public bytes mismatch".to_string());
    }

    let expected_pubkey_base58 = bs58::encode(public_key_bytes).into_string();
    if expected_pubkey_base58 != keys.public_key_base58 {
        return Err("Solana public key base58 mismatch".to_string());
    }

    Ok(())
}

fn validate_ethereum(keys: &EthereumKeys) -> Result<(), String> {
    let secret_bytes = hex::decode(&keys.private_hex).map_err(|e| e.to_string())?;
    let secret_key = SecretKey::from_slice(&secret_bytes).map_err(|e| e.to_string())?;

    let secp = Secp256k1::new();
    let secp_public = SecpPublicKey::from_secret_key(&secp, &secret_key);
    let uncompressed = secp_public.serialize_uncompressed();
    let public_bytes = &uncompressed[1..];
    let public_hex = hex::encode(public_bytes);
    if public_hex != keys.public_uncompressed_hex {
        return Err("Ethereum uncompressed public key mismatch".to_string());
    }

    let address_bytes = keccak256(public_bytes);
    let expected_address = to_checksum_address(&address_bytes[12..]);
    if expected_address != keys.address {
        return Err("Ethereum checksum address mismatch".to_string());
    }

    Ok(())
}
