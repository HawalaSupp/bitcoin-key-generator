use bitcoin::key::{CompressedPublicKey, PublicKey as BitcoinPublicKey};
use bitcoin::secp256k1::{Secp256k1, SecretKey, PublicKey as SecpPublicKey};
use bitcoin::{Address, Network, PrivateKey};
use rand::rngs::OsRng;
use rand::RngCore;
use std::error::Error;
use std::convert::TryFrom;

fn main() -> Result<(), Box<dyn Error>> {
    // Use the operating system RNG for cryptographic strength randomness
    let secp = Secp256k1::new();
    let mut rng = OsRng;

    // Generate a fresh random 32-byte secret key
    let mut secret_bytes = [0u8; 32];
    rng.fill_bytes(&mut secret_bytes);
    let secret_key = SecretKey::from_slice(&secret_bytes)?;

    // Capture a hex representation before the key is moved
    let secret_hex = hex::encode(secret_key.secret_bytes());

    // Derive the corresponding compressed public key
    let secp_public_key = SecpPublicKey::from_secret_key(&secp, &secret_key);
    let public_key = BitcoinPublicKey::from(secp_public_key);
    let compressed = CompressedPublicKey::try_from(public_key.clone())?;

    // Wrap the secret key as a Bitcoin private key for WIF export
    let private_key = PrivateKey::new(secret_key, Network::Bitcoin);

    // Generate a Bech32 SegWit address from the compressed key
    let address = Address::p2wpkh(&compressed, Network::Bitcoin);

    println!("Private key (hex): {}", secret_hex);
    println!("Private key (WIF): {}", private_key.to_wif());
    println!(
        "Public key (compressed hex): {}",
        hex::encode(compressed.to_bytes())
    );
    println!("Bech32 address (P2WPKH): {}", address);

    Ok(())
}
