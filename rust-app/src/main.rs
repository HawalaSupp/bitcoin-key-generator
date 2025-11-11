use rust_app::{AllKeys, generate_all_keys};
use std::env;
use std::error::Error;

fn main() -> Result<(), Box<dyn Error>> {
    let args: Vec<String> = env::args().collect();
    let keys = generate_all_keys()?;

    if args.iter().any(|arg| arg == "--json") {
        println!("{}", serde_json::to_string_pretty(&keys)?);
    } else {
        print_human_readable(&keys);
    }

    Ok(())
}

fn print_human_readable(keys: &AllKeys) {
    println!("=== Bitcoin (P2WPKH) ===");
    println!("Private key (hex): {}", keys.bitcoin.private_hex);
    println!("Private key (WIF): {}", keys.bitcoin.private_wif);
    println!(
        "Public key (compressed hex): {}",
        keys.bitcoin.public_compressed_hex
    );
    println!("Bech32 address (P2WPKH): {}", keys.bitcoin.address);
    println!();

    println!("=== Bitcoin Testnet (P2WPKH) ===");
    println!("Private key (hex): {}", keys.bitcoin_testnet.private_hex);
    println!("Private key (WIF): {}", keys.bitcoin_testnet.private_wif);
    println!(
        "Public key (compressed hex): {}",
        keys.bitcoin_testnet.public_compressed_hex
    );
    println!(
        "Bech32 address (P2WPKH): {}",
        keys.bitcoin_testnet.address
    );
    println!();

    println!("=== Litecoin (P2WPKH) ===");
    println!("Private key (hex): {}", keys.litecoin.private_hex);
    println!("Private key (WIF): {}", keys.litecoin.private_wif);
    println!(
        "Public key (compressed hex): {}",
        keys.litecoin.public_compressed_hex
    );
    println!("Bech32 address (P2WPKH): {}", keys.litecoin.address);
    println!();

    println!("=== Monero ===");
    println!("Private spend key (hex): {}", keys.monero.private_spend_hex);
    println!("Private view key (hex): {}", keys.monero.private_view_hex);
    println!("Public spend key (hex): {}", keys.monero.public_spend_hex);
    println!("Public view key (hex): {}", keys.monero.public_view_hex);
    println!("Primary address: {}", keys.monero.address);
    println!();

    println!("=== Solana ===");
    println!("Private seed (hex): {}", keys.solana.private_seed_hex);
    println!("Private key (base58): {}", keys.solana.private_key_base58);
    println!(
        "Public key / address (base58): {}",
        keys.solana.public_key_base58
    );
    println!();

    println!("=== Ethereum ===");
    println!("Private key (hex): {}", keys.ethereum.private_hex);
    println!(
        "Public key (uncompressed hex): {}",
        keys.ethereum.public_uncompressed_hex
    );
    println!("Checksummed address: {}", keys.ethereum.address);
    println!();

    println!("=== Ethereum Sepolia ===");
    println!("Private key (hex): {}", keys.ethereum_sepolia.private_hex);
    println!(
        "Public key (uncompressed hex): {}",
        keys.ethereum_sepolia.public_uncompressed_hex
    );
    println!("Checksummed address: {}", keys.ethereum_sepolia.address);
    println!();

    println!("=== BNB Smart Chain ===");
    println!("Private key (hex): {}", keys.bnb.private_hex);
    println!(
        "Public key (uncompressed hex): {}",
        keys.bnb.public_uncompressed_hex
    );
    println!("Checksummed address: {}", keys.bnb.address);
    println!();

    println!("=== XRP ===");
    println!("Private key (hex): {}", keys.xrp.private_hex);
    println!(
        "Public key (compressed hex): {}",
        keys.xrp.public_compressed_hex
    );
    println!("Classic address: {}", keys.xrp.classic_address);
}
