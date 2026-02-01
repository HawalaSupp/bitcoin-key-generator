use bitcoin::hashes::Hash;
use bitcoin::secp256k1::{Secp256k1, SecretKey, Message, Keypair};
use bitcoin::sighash::{SighashCache, TapSighashType, Prevouts};
use bitcoin::{
    Address, Amount, Network, NetworkKind, OutPoint, ScriptBuf, Sequence, Transaction, TxIn, TxOut, Witness,
    absolute::LockTime, consensus::encode, transaction::Version,
};
use bitcoin::key::TapTweak;
use serde::Deserialize;
use std::error::Error;
use std::str::FromStr;

/// Debug logging macro that only prints in debug builds
#[cfg(debug_assertions)]
macro_rules! debug_log {
    ($($arg:tt)*) => { eprintln!($($arg)*) }
}
#[cfg(not(debug_assertions))]
macro_rules! debug_log {
    ($($arg:tt)*) => {}
}

#[derive(Debug, Deserialize)]
pub struct Utxo {
    pub txid: String,
    pub vout: u32,
    #[allow(dead_code)]
    pub status: UtxoStatus,
    pub value: u64,
}

#[derive(Debug, Deserialize)]
pub struct UtxoStatus {
    #[allow(dead_code)]
    pub confirmed: bool,
    #[allow(dead_code)]
    pub block_height: Option<u32>,
    #[allow(dead_code)]
    pub block_hash: Option<String>,
    #[allow(dead_code)]
    pub block_time: Option<u64>,
}

/// Fetch UTXOs for a Taproot address
pub fn fetch_taproot_utxos(address: &str, network: Network) -> Result<Vec<Utxo>, Box<dyn Error>> {
    use std::time::Duration;
    
    let apis: Vec<(&str, &str)> = match network {
        Network::Bitcoin => vec![
            ("https://mempool.space/api", "mempool.space"),
            ("https://blockstream.info/api", "blockstream"),
        ],
        Network::Testnet => vec![
            ("https://mempool.space/testnet/api", "mempool.space testnet"),
            ("https://blockstream.info/testnet/api", "blockstream testnet"),
        ],
        _ => return Err("Unsupported network for Taproot UTXO fetch".into()),
    };
    
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(8))
        .connect_timeout(Duration::from_secs(5))
        .build()?;
    
    let mut last_error: Option<Box<dyn Error>> = None;
    
    #[allow(unused_variables)]
    for (base_url, api_name) in apis {
        let url = format!("{}/address/{}/utxo", base_url, address);
        debug_log!("[Taproot] Fetching UTXOs from {}...", api_name);
        
        match client.get(&url).send() {
            Ok(resp) => {
                if resp.status().is_success() {
                    match resp.text() {
                        Ok(text) => {
                            match serde_json::from_str::<Vec<Utxo>>(&text) {
                                Ok(utxos) => {
                                    debug_log!("[Taproot] Found {} UTXOs from {}", utxos.len(), api_name);
                                    return Ok(utxos);
                                }
                                Err(e) => {
                                    debug_log!("[Taproot] Failed to parse response from {}: {}", api_name, e);
                                    last_error = Some(Box::new(e));
                                }
                            }
                        }
                        Err(e) => {
                            debug_log!("[Taproot] Failed to read response from {}: {}", api_name, e);
                            last_error = Some(Box::new(e));
                        }
                    }
                } else {
                    debug_log!("[Taproot] {} returned status {}", api_name, resp.status());
                    last_error = Some(format!("HTTP {}", resp.status()).into());
                }
            }
            Err(e) => {
                debug_log!("[Taproot] {} request failed: {}", api_name, e);
                last_error = Some(Box::new(e));
            }
        }
    }
    
    Err(last_error.unwrap_or_else(|| "All UTXO APIs failed".into()))
}

/// Derive Taproot (P2TR) address from a private key
pub fn derive_taproot_address(private_key_hex: &str, network: Network) -> Result<(String, String), Box<dyn Error>> {
    let secp = Secp256k1::new();
    
    // Parse private key
    let secret_bytes = hex::decode(private_key_hex)?;
    let secret_key = SecretKey::from_slice(&secret_bytes)?;
    
    // Create keypair for Taproot
    let keypair = Keypair::from_secret_key(&secp, &secret_key);
    let (x_only_pubkey, _parity) = keypair.x_only_public_key();
    
    // Create P2TR address (key-path only, no script tree)
    // The Address::p2tr function handles the internal key tweaking
    let address = Address::p2tr(&secp, x_only_pubkey, None, network);
    
    debug_log!("[Taproot] Derived P2TR address: {}", address);
    debug_log!("[Taproot] X-only pubkey: {}", hex::encode(x_only_pubkey.serialize()));
    
    Ok((address.to_string(), hex::encode(x_only_pubkey.serialize())))
}

/// Prepare a Taproot (P2TR) transaction
/// 
/// Taproot offers ~7% fee savings vs SegWit due to:
/// - Schnorr signatures (64 bytes vs 71-73 bytes for ECDSA)
/// - Single pubkey in witness (32 bytes vs 33 bytes compressed)
/// - Key-path spend has minimal overhead
pub fn prepare_taproot_transaction(
    recipient: &str,
    amount_sats: u64,
    fee_rate_sats_per_vbyte: u64,
    sender_private_key_hex: &str,
    network: Network,
    manual_utxos: Option<Vec<Utxo>>,
) -> Result<String, Box<dyn Error>> {
    let secp = Secp256k1::new();
    
    // Parse private key and derive Taproot keypair
    let secret_bytes = hex::decode(sender_private_key_hex)?;
    let secret_key = SecretKey::from_slice(&secret_bytes)?;
    let keypair = Keypair::from_secret_key(&secp, &secret_key);
    let (x_only_pubkey, _parity) = keypair.x_only_public_key();
    
    // Derive sender's Taproot address
    let sender_address = Address::p2tr(&secp, x_only_pubkey, None, network);
    debug_log!("[Taproot] Sender address: {}", sender_address);

    // Fetch UTXOs
    let (utxos, is_manual) = if let Some(u) = manual_utxos {
        debug_log!("[Taproot] Using {} manual UTXOs", u.len());
        (u, true)
    } else {
        (fetch_taproot_utxos(&sender_address.to_string(), network)?, false)
    };
    
    debug_log!("[Taproot] Available UTXOs: {}", utxos.len());
    
    if utxos.is_empty() {
        return Err("No Taproot UTXOs available. Send funds to your Taproot address first.".into());
    }

    // Select inputs
    let mut inputs: Vec<Utxo> = Vec::new();
    let mut total_input_value: u64 = 0;

    if is_manual {
        for utxo in utxos {
            debug_log!("[Taproot] Using Manual UTXO: txid={}, vout={}, value={} sats", utxo.txid, utxo.vout, utxo.value);
            total_input_value += utxo.value;
            inputs.push(utxo);
        }
    } else {
        for utxo in utxos {
            debug_log!("[Taproot] UTXO: txid={}, vout={}, value={} sats", utxo.txid, utxo.vout, utxo.value);
            total_input_value += utxo.value;
            inputs.push(utxo);
            if total_input_value >= amount_sats {
                break;
            }
        }
    }
    
    debug_log!("[Taproot] Selected {} inputs with total {} sats", inputs.len(), total_input_value);

    if inputs.is_empty() {
        return Err("No inputs selected".into());
    }

    if total_input_value < amount_sats {
        return Err(format!("Insufficient funds: have {} sats, need {} sats", total_input_value, amount_sats).into());
    }

    // Estimate fee for Taproot
    // P2TR Input: ~57.5 vbytes (vs 68 for P2WPKH) - ~15% smaller
    // P2TR Output: ~43 vbytes (vs 31 for P2WPKH - larger because of 32-byte pubkey)
    // But overall transaction is more efficient due to Schnorr
    let num_outputs = 2; // recipient + change
    let estimated_vsize = 10.5 // Base overhead
        + (inputs.len() as f64 * 57.5) // Taproot inputs
        + (num_outputs as f64 * 43.0); // Taproot outputs
    let fee = (estimated_vsize.ceil() as u64) * fee_rate_sats_per_vbyte;

    debug_log!("[Taproot] Estimated vsize: {:.1} vbytes, fee: {} sats", estimated_vsize, fee);

    if total_input_value < amount_sats + fee {
        return Err(format!(
            "Insufficient funds for amount + fee. Have {} sats, need {} sats",
            total_input_value,
            amount_sats + fee
        ).into());
    }

    // Parse recipient address
    let recipient_address = Address::from_str(recipient)?.require_network(network)?;
    let change_amount = total_input_value - amount_sats - fee;

    // Build transaction inputs
    let mut tx_inputs = Vec::new();
    for utxo in &inputs {
        tx_inputs.push(TxIn {
            previous_output: OutPoint::new(bitcoin::Txid::from_str(&utxo.txid)?, utxo.vout),
            script_sig: ScriptBuf::new(), // Taproot has empty script_sig
            sequence: Sequence::ENABLE_RBF_NO_LOCKTIME,
            witness: Witness::default(),
        });
    }

    // Build transaction outputs
    let mut tx_outputs = Vec::new();
    
    // Recipient output
    tx_outputs.push(TxOut {
        value: Amount::from_sat(amount_sats),
        script_pubkey: recipient_address.script_pubkey(),
    });
    
    // Change output (to sender's Taproot address)
    if change_amount > 546 { // Dust limit
        tx_outputs.push(TxOut {
            value: Amount::from_sat(change_amount),
            script_pubkey: sender_address.script_pubkey(),
        });
    }

    let mut tx = Transaction {
        version: Version::TWO,
        lock_time: LockTime::ZERO,
        input: tx_inputs,
        output: tx_outputs,
    };
    
    debug_log!("[Taproot] Transaction built: {} inputs, {} outputs", tx.input.len(), tx.output.len());

    // Collect prevouts for signing
    let prevouts: Vec<TxOut> = inputs.iter().map(|utxo| {
        TxOut {
            value: Amount::from_sat(utxo.value),
            script_pubkey: sender_address.script_pubkey(),
        }
    }).collect();

    // Sign inputs using Schnorr (BIP340)
    let mut sighasher = SighashCache::new(&mut tx);
    
    // Tweak the keypair for key-path spending
    let tweaked_keypair = keypair.tap_tweak(&secp, None);

    for i in 0..inputs.len() {
        // Compute taproot sighash
        let sighash = sighasher.taproot_key_spend_signature_hash(
            i,
            &Prevouts::All(&prevouts),
            TapSighashType::Default,
        )?;

        let msg = Message::from_digest_slice(sighash.as_byte_array())?;
        
        // Sign with Schnorr (no aux rand for deterministic signatures)
        let signature = secp.sign_schnorr_no_aux_rand(&msg, &tweaked_keypair.to_keypair());
        
        // Build witness (just the signature for key-path spend)
        // TapSighashType::Default doesn't require the sighash type byte
        let mut witness = Witness::new();
        witness.push(signature.serialize());
        
        // Update witness for this input - witness_mut should always succeed for valid index
        if let Some(w) = sighasher.witness_mut(i) {
            *w = witness;
        } else {
            return Err(format!("Invalid input index {} for witness", i).into());
        }
    }

    // Serialize transaction
    let raw_hex = hex::encode(encode::serialize(&tx));
    
    // Calculate actual vsize
    #[allow(unused_variables)]
    let actual_vsize = tx.vsize();
    debug_log!("[Taproot] Actual vsize: {} vbytes", actual_vsize);
    debug_log!("[Taproot] Signed transaction hex ({} chars)", raw_hex.len());
    
    Ok(raw_hex)
}

/// Prepare a Taproot transaction from WIF private key
pub fn prepare_taproot_transaction_from_wif(
    recipient: &str,
    amount_sats: u64,
    fee_rate_sats_per_vbyte: u64,
    sender_wif: &str,
    manual_utxos: Option<Vec<Utxo>>,
) -> Result<String, Box<dyn Error>> {
    // Parse WIF to get private key and network
    let private_key = bitcoin::PrivateKey::from_wif(sender_wif)?;
    let network = match private_key.network {
        NetworkKind::Main => Network::Bitcoin,
        NetworkKind::Test => Network::Testnet,
    };
    
    // Convert to hex
    let private_key_hex = hex::encode(private_key.inner.secret_bytes());
    
    prepare_taproot_transaction(
        recipient,
        amount_sats,
        fee_rate_sats_per_vbyte,
        &private_key_hex,
        network,
        manual_utxos,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_derive_taproot_address_mainnet() {
        // Test vector - should produce a bc1p... address
        let test_privkey = "0000000000000000000000000000000000000000000000000000000000000001";
        let result = derive_taproot_address(test_privkey, Network::Bitcoin);
        assert!(result.is_ok());
        let (address, _) = result.unwrap();
        assert!(address.starts_with("bc1p"), "Mainnet Taproot address should start with bc1p");
    }

    #[test]
    fn test_derive_taproot_address_testnet() {
        let test_privkey = "0000000000000000000000000000000000000000000000000000000000000001";
        let result = derive_taproot_address(test_privkey, Network::Testnet);
        assert!(result.is_ok());
        let (address, _) = result.unwrap();
        assert!(address.starts_with("tb1p"), "Testnet Taproot address should start with tb1p");
    }
}
