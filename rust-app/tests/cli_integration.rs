use bitcoin::hashes::{Hash, hash160, sha256d};
use bitcoin::key::{CompressedPublicKey, PublicKey as BitcoinPublicKey};
use bitcoin::secp256k1::{Secp256k1, SecretKey as SecpSecretKey};
use bitcoin::{Address, Network, PrivateKey};
use bs58::Alphabet;
use rust_app::{AllKeys, encode_litecoin_wif, keccak256, to_checksum_address};
use serde_json::Value;
use std::convert::TryInto;
use std::process::Command;

fn decode_keys_from_cli() -> AllKeys {
    let binary_path = assert_cmd::cargo::cargo_bin!("rust-app");
    let output = Command::new(binary_path)
        .arg("--json")
        .output()
        .expect("cli run succeeds");

    assert!(
        output.status.success(),
        "cli exited unsuccessfully: {:?}",
        output
    );
    let stdout = String::from_utf8(output.stdout).expect("stdout is utf8");

    // sanity check: ensure output parses as json before struct deserialization
    let _: Value = serde_json::from_str(&stdout).expect("stdout is valid json");
    serde_json::from_str(&stdout).expect("json matches AllKeys schema")
}

#[test]
fn cli_emits_consistent_key_material() {
    let keys = decode_keys_from_cli();

    // Bitcoin
    let btc_private = PrivateKey::from_wif(&keys.bitcoin.private_wif).expect("bitcoin wif valid");
    assert_eq!(
        hex::encode(btc_private.inner.secret_bytes()),
        keys.bitcoin.private_hex,
        "bitcoin hex matches wif",
    );
    let secp = Secp256k1::new();
    let btc_public = btc_private.public_key(&secp);
    let btc_compressed = CompressedPublicKey::try_from(btc_public).expect("compressed pubkey");
    assert_eq!(
        hex::encode(btc_compressed.to_bytes()),
        keys.bitcoin.public_compressed_hex,
        "bitcoin compressed matches",
    );
    let btc_address = Address::p2wpkh(&btc_compressed, Network::Bitcoin);
    assert_eq!(
        btc_address.to_string(),
        keys.bitcoin.address,
        "bitcoin address matches"
    );

    // Litecoin
    let ltc_secret_bytes = hex::decode(&keys.litecoin.private_hex).expect("litecoin private hex");
    let ltc_secret = SecpSecretKey::from_slice(&ltc_secret_bytes).expect("litecoin secret key");
    let encoded_wif = encode_litecoin_wif(&ltc_secret);
    assert_eq!(
        encoded_wif, keys.litecoin.private_wif,
        "litecoin wif encodes correctly"
    );
    let secp = Secp256k1::new();
    let ltc_public = bitcoin::secp256k1::PublicKey::from_secret_key(&secp, &ltc_secret);
    let ltc_compressed = CompressedPublicKey::try_from(BitcoinPublicKey::from(ltc_public))
        .expect("litecoin compressed public");
    assert_eq!(
        hex::encode(ltc_compressed.to_bytes()),
        keys.litecoin.public_compressed_hex,
        "litecoin compressed matches",
    );
    let pubkey_hash = hash160::Hash::hash(&ltc_compressed.to_bytes());
    let version = bech32::u5::try_from_u8(0).expect("version u5");
    let converted = bech32::convert_bits(pubkey_hash.as_ref(), 8, 5, true).expect("bech32 bits");
    let mut bech32_data = Vec::with_capacity(1 + converted.len());
    bech32_data.push(version);
    for value in converted {
        let item = bech32::u5::try_from_u8(value).expect("convert to u5");
        bech32_data.push(item);
    }
    let ltc_address = bech32::encode("ltc", bech32_data, bech32::Variant::Bech32)
        .expect("litecoin bech32 encode");
    assert_eq!(
        ltc_address, keys.litecoin.address,
        "litecoin address matches"
    );

    // Monero
    let spend_bytes = hex::decode(&keys.monero.private_spend_hex).expect("monero spend hex");
    let spend_array: [u8; 32] = spend_bytes.as_slice().try_into().expect("monero spend len");
    let view_seed = keccak256(&spend_array);
    let view_scalar = curve25519_dalek::scalar::Scalar::from_bytes_mod_order(view_seed);
    let private_view_expected = view_scalar.to_bytes();
    assert_eq!(
        hex::encode(private_view_expected),
        keys.monero.private_view_hex,
        "monero view derived from spend",
    );
    let view_bytes = hex::decode(&keys.monero.private_view_hex).expect("monero view hex");
    let view_array: [u8; 32] = view_bytes.as_slice().try_into().expect("monero view len");
    let spend_point = curve25519_dalek::edwards::EdwardsPoint::mul_base(
        &curve25519_dalek::scalar::Scalar::from_bytes_mod_order(spend_array),
    );
    let view_point = curve25519_dalek::edwards::EdwardsPoint::mul_base(
        &curve25519_dalek::scalar::Scalar::from_bytes_mod_order(view_array),
    );
    assert_eq!(
        hex::encode(spend_point.compress().to_bytes()),
        keys.monero.public_spend_hex,
        "monero spend public matches",
    );
    assert_eq!(
        hex::encode(view_point.compress().to_bytes()),
        keys.monero.public_view_hex,
        "monero view public matches",
    );
    const MONERO_ALPHABET: &str = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    let addr_len = keys.monero.address.len();
    assert!(
        (95..=106).contains(&addr_len),
        "monero address length unexpected: {}",
        addr_len
    );
    assert!(
        keys.monero
            .address
            .chars()
            .all(|c| MONERO_ALPHABET.contains(c)),
        "monero address uses only base58 alphabet"
    );

    // Solana
    let sol_seed = hex::decode(&keys.solana.private_seed_hex).expect("solana seed hex");
    let sol_seed_array: [u8; 32] = sol_seed.as_slice().try_into().expect("solana seed len");
    let sol_keypair = bs58::decode(&keys.solana.private_key_base58)
        .into_vec()
        .expect("solana keypair base58");
    assert_eq!(sol_keypair.len(), 64, "solana keypair length");
    assert_eq!(
        &sol_keypair[..32],
        sol_seed_array,
        "solana seed matches keypair"
    );
    let signing_key = ed25519_dalek::SigningKey::from_bytes(&sol_seed_array);
    let verifying = signing_key.verifying_key();
    assert_eq!(
        bs58::encode(verifying.to_bytes()).into_string(),
        keys.solana.public_key_base58,
        "solana public key matches",
    );
    assert_eq!(
        &sol_keypair[32..],
        verifying.to_bytes(),
        "solana public segment matches",
    );

    // Ethereum
    let eth_secret_bytes = hex::decode(&keys.ethereum.private_hex).expect("ethereum private hex");
    let eth_secret = SecpSecretKey::from_slice(&eth_secret_bytes).expect("ethereum secret");
    let secp = Secp256k1::new();
    let eth_public = bitcoin::secp256k1::PublicKey::from_secret_key(&secp, &eth_secret);
    let eth_uncompressed = eth_public.serialize_uncompressed();
    assert_eq!(
        hex::encode(&eth_uncompressed[1..]),
        keys.ethereum.public_uncompressed_hex,
        "ethereum public matches",
    );
    let address_bytes = keccak256(&eth_uncompressed[1..]);
    let checksummed = to_checksum_address(&address_bytes[12..]);
    assert_eq!(
        checksummed, keys.ethereum.address,
        "ethereum checksum address matches"
    );
    assert!(keys.ethereum.address.starts_with("0x"));

    // BNB
    let bnb_secret_bytes = hex::decode(&keys.bnb.private_hex).expect("bnb private hex");
    let bnb_secret = SecpSecretKey::from_slice(&bnb_secret_bytes).expect("bnb secret");
    let secp = Secp256k1::new();
    let bnb_public = bitcoin::secp256k1::PublicKey::from_secret_key(&secp, &bnb_secret);
    let bnb_uncompressed = bnb_public.serialize_uncompressed();
    assert_eq!(
        hex::encode(&bnb_uncompressed[1..]),
        keys.bnb.public_uncompressed_hex,
        "bnb public matches",
    );
    let bnb_address_bytes = keccak256(&bnb_uncompressed[1..]);
    let bnb_checksummed = to_checksum_address(&bnb_address_bytes[12..]);
    assert_eq!(
        bnb_checksummed, keys.bnb.address,
        "bnb checksum address matches"
    );
    assert!(keys.bnb.address.starts_with("0x"));

    // XRP
    let xrp_secret_bytes = hex::decode(&keys.xrp.private_hex).expect("xrp private hex");
    let xrp_secret = SecpSecretKey::from_slice(&xrp_secret_bytes).expect("xrp secret key");
    let secp = Secp256k1::new();
    let xrp_public = bitcoin::secp256k1::PublicKey::from_secret_key(&secp, &xrp_secret);
    let xrp_compressed = xrp_public.serialize();
    assert_eq!(
        hex::encode(xrp_compressed),
        keys.xrp.public_compressed_hex,
        "xrp compressed public matches",
    );
    let account_id = hash160::Hash::hash(&xrp_compressed);
    let mut payload = Vec::new();
    payload.push(0x00);
    payload.extend_from_slice(account_id.as_ref());
    let checksum = sha256d::Hash::hash(&payload);
    let mut address_bytes = payload;
    address_bytes.extend_from_slice(&checksum[..4]);
    let classic = bs58::encode(address_bytes)
        .with_alphabet(Alphabet::RIPPLE)
        .into_string();
    assert_eq!(
        classic, keys.xrp.classic_address,
        "xrp classic address matches"
    );
    assert!(keys.xrp.classic_address.starts_with('r'));
}

#[test]
fn litecoin_wif_checksum_validates() {
    let keys = decode_keys_from_cli();
    let decoded = bs58::decode(&keys.litecoin.private_wif)
        .into_vec()
        .expect("decode litecoin wif");
    assert_eq!(decoded[0], 0xB0, "litecoin wif prefix matches");
    assert_eq!(decoded[33], 0x01, "litecoin wif compression flag");
    let checksum = sha256d::Hash::hash(&decoded[..34]);
    assert_eq!(&decoded[34..], &checksum[..4], "litecoin checksum valid");
}
