use clap::{Parser, Subcommand};
use rust_app::{AllKeys, create_new_wallet, generate_keys_from_seed};
use std::error::Error;
use bip39::Mnemonic;

#[derive(Parser)]
#[command(name = "hawala-cli")]
#[command(about = "Hawala Wallet CLI Backend", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Generate a new wallet or recover from mnemonic
    GenKeys {
        /// Optional mnemonic phrase to recover from
        #[arg(long)]
        mnemonic: Option<String>,
        /// Output as JSON
        #[arg(long)]
        json: bool,
    },
    /// Sign a Bitcoin transaction
    SignBtc {
        #[arg(long)]
        recipient: String,
        #[arg(long)]
        amount_sats: u64,
        #[arg(long)]
        fee_rate: u64,
        #[arg(long)]
        sender_wif: String,
        #[arg(long)]
        utxos: Option<String>, // JSON string of UTXOs
    },
    /// Sign an Ethereum transaction
    SignEth {
        #[arg(long)]
        recipient: String,
        #[arg(long)]
        amount_wei: String,
        #[arg(long)]
        chain_id: u64,
        #[arg(long)]
        sender_key: String,
        #[arg(long)]
        nonce: u64,
        #[arg(long)]
        gas_limit: u64,
        #[arg(long)]
        gas_price: Option<String>,
        #[arg(long)]
        max_fee_per_gas: Option<String>,
        #[arg(long)]
        max_priority_fee_per_gas: Option<String>,
        #[arg(long, default_value = "")]
        data: String,
    },
    /// Sign a Solana transaction
    SignSol {
        #[arg(long)]
        recipient: String,
        #[arg(long)]
        amount_sol: f64,
        #[arg(long)]
        recent_blockhash: String,
        #[arg(long)]
        sender_base58: String,
    },
    /// Sign a Monero transaction (Validation Only)
    SignXmr {
        #[arg(long)]
        recipient: String,
        #[arg(long)]
        amount_xmr: f64,
        #[arg(long)]
        sender_spend_hex: String,
        #[arg(long)]
        sender_view_hex: String,
    },
    /// Sign an XRP transaction
    SignXrp {
        #[arg(long)]
        recipient: String,
        #[arg(long)]
        amount_drops: u64,
        #[arg(long)]
        sender_seed_hex: String,
        #[arg(long)]
        sequence: u32,
        #[arg(long)]
        destination_tag: Option<u32>,
    },
    /// Sign a Litecoin transaction
    SignLtc {
        #[arg(long)]
        recipient: String,
        #[arg(long)]
        amount_lits: u64,
        #[arg(long)]
        fee_rate: u64,
        #[arg(long)]
        sender_wif: String,
        #[arg(long)]
        sender_address: String,
        #[arg(long)]
        utxos: Option<String>, // JSON string of UTXOs
    },
}

fn main() -> Result<(), Box<dyn Error>> {
    let cli = Cli::parse();

    match &cli.command {
        Commands::GenKeys { mnemonic, json } => {
            handle_gen_keys(mnemonic.as_deref(), *json)?;
        }
        Commands::SignBtc { recipient, amount_sats, fee_rate, sender_wif, utxos } => {
             let manual_utxos = if let Some(json) = utxos {
                 Some(serde_json::from_str::<Vec<rust_app::bitcoin_wallet::Utxo>>(json)?)
             } else {
                 None
             };
             let tx_hex = rust_app::bitcoin_wallet::prepare_transaction(recipient, *amount_sats, *fee_rate, sender_wif, manual_utxos)?;
             println!("{}", tx_hex);
        }
        Commands::SignEth { recipient, amount_wei, chain_id, sender_key, nonce, gas_limit, gas_price, max_fee_per_gas, max_priority_fee_per_gas, data } => {
             let rt = tokio::runtime::Runtime::new()?;
             let tx_hex = rt.block_on(rust_app::ethereum_wallet::prepare_ethereum_transaction(
                 recipient, amount_wei, *chain_id, sender_key, *nonce, *gas_limit, gas_price.clone(), max_fee_per_gas.clone(), max_priority_fee_per_gas.clone(), data
             ))?;
             println!("{}", tx_hex);
        }
        Commands::SignSol { recipient, amount_sol, recent_blockhash, sender_base58 } => {
            let tx_base58 = rust_app::solana_wallet::prepare_solana_transaction(
                recipient, *amount_sol, recent_blockhash, sender_base58
            )?;
            println!("{}", tx_base58);
        }
        Commands::SignXmr { recipient, amount_xmr, sender_spend_hex, sender_view_hex } => {
            let tx_hex = rust_app::monero_wallet::prepare_monero_transaction(
                recipient, *amount_xmr, sender_spend_hex, sender_view_hex
            )?;
            println!("{}", tx_hex);
        }
        Commands::SignXrp { recipient, amount_drops, sender_seed_hex, sequence, destination_tag } => {
            let tx_hex = rust_app::xrp_wallet::prepare_xrp_transaction(
                recipient, *amount_drops, sender_seed_hex, *sequence, *destination_tag
            )?;
            println!("{}", tx_hex);
        }
        Commands::SignLtc { recipient, amount_lits, fee_rate, sender_wif, sender_address, utxos } => {
            let manual_utxos = if let Some(json) = utxos {
                Some(serde_json::from_str::<Vec<rust_app::litecoin_wallet::LitecoinUtxo>>(json)?)
            } else {
                None
            };
            let tx_hex = rust_app::litecoin_wallet::prepare_litecoin_transaction(
                recipient, *amount_lits, *fee_rate, sender_wif, sender_address, manual_utxos
            )?;
            println!("{}", tx_hex);
        }
    }

    Ok(())
}

fn handle_gen_keys(mnemonic_arg: Option<&str>, json: bool) -> Result<(), Box<dyn Error>> {
    let (mnemonic_str, keys) = if let Some(phrase) = mnemonic_arg {
        let mnemonic = Mnemonic::parse(phrase)?;
        let seed = mnemonic.to_seed("");
        let keys = generate_keys_from_seed(&seed)?;
        (phrase.to_string(), keys)
    } else {
        create_new_wallet()?
    };

    if json {
        println!("{{ \"mnemonic\": \"{}\", \"keys\": {} }}", mnemonic_str, serde_json::to_string(&keys)?);
    } else {
        println!("=== Mnemonic ===");
        println!("{}", mnemonic_str);
        println!();
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
