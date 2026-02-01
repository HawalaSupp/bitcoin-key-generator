use bitcoin::hashes::Hash;
use bitcoin::secp256k1::{Message, Secp256k1, SecretKey};
use bitcoin::sighash::{EcdsaSighashType, SighashCache};
use bitcoin::{
    Amount, OutPoint, ScriptBuf, Sequence, Transaction, TxIn, TxOut, Witness,
    absolute::LockTime, consensus::encode, transaction::Version,
};
use serde::Deserialize;
use std::error::Error;

/// Debug logging macro that only prints in debug builds
#[cfg(debug_assertions)]
macro_rules! debug_log {
    ($($arg:tt)*) => { eprintln!($($arg)*) }
}
#[cfg(not(debug_assertions))]
macro_rules! debug_log {
    ($($arg:tt)*) => {}
}

// MARK: - Litecoin UTXO Models

#[derive(Debug, Deserialize, Clone)]
pub struct LitecoinUtxo {
    #[serde(alias = "txid")]
    pub transaction_hash: String,
    #[serde(alias = "vout")]
    pub index: u32,
    pub value: u64,
    #[allow(dead_code)]
    pub script_hex: Option<String>,
    #[allow(dead_code)]
    pub block_id: Option<i64>,
}

/// Fetch UTXOs for a Litecoin address via Blockchair API
pub fn fetch_litecoin_utxos(address: &str) -> Result<Vec<LitecoinUtxo>, Box<dyn Error>> {
    use std::time::Duration;
    
    let url = format!(
        "https://api.blockchair.com/litecoin/dashboards/address/{}?limit=100",
        address
    );
    
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(10))
        .connect_timeout(Duration::from_secs(5))
        .build()?;
    
    debug_log!("Fetching Litecoin UTXOs from Blockchair...");
    
    let resp = client
        .get(&url)
        .header("User-Agent", "HawalaApp/1.0")
        .send()?;
    
    if !resp.status().is_success() {
        return Err(format!("Blockchair API returned status {}", resp.status()).into());
    }
    
    let json: serde_json::Value = resp.json()?;
    
    let utxos = json["data"][address]["utxo"]
        .as_array()
        .ok_or("Failed to parse UTXO array")?
        .iter()
        .filter_map(|u| {
            Some(LitecoinUtxo {
                transaction_hash: u["transaction_hash"].as_str()?.to_string(),
                index: u["index"].as_u64()? as u32,
                value: u["value"].as_u64()?,
                script_hex: u["script_hex"].as_str().map(|s| s.to_string()),
                block_id: u["block_id"].as_i64(),
            })
        })
        .collect::<Vec<_>>();
    
    debug_log!("Found {} Litecoin UTXOs", utxos.len());
    Ok(utxos)
}

/// Prepare and sign a Litecoin transaction
/// 
/// Litecoin uses the same transaction format as Bitcoin, but with different:
/// - Address prefixes (ltc1 for mainnet bech32)
/// - WIF prefix (0xB0 instead of 0x80)
/// - Version bytes
pub fn prepare_litecoin_transaction(
    recipient: &str,
    amount_lits: u64,
    fee_rate_sats_per_vbyte: u64,
    sender_wif: &str,
    sender_address: &str,
    manual_utxos: Option<Vec<LitecoinUtxo>>,
) -> Result<String, Box<dyn Error>> {
    let secp = Secp256k1::new();
    
    // Decode Litecoin WIF (0xB0 prefix for mainnet)
    let (secret_key, compressed) = decode_litecoin_wif(sender_wif)?;
    
    // Derive public key
    let public_key = bitcoin::secp256k1::PublicKey::from_secret_key(&secp, &secret_key);
    let pubkey_bytes = if compressed {
        public_key.serialize().to_vec()
    } else {
        public_key.serialize_uncompressed().to_vec()
    };
    
    // Compute pubkey hash (HASH160 = RIPEMD160(SHA256(pubkey)))
    let pubkey_hash = bitcoin::hashes::hash160::Hash::hash(&pubkey_bytes);
    
    // 1. Fetch UTXOs (or use manual)
    let utxos = if let Some(u) = manual_utxos {
        debug_log!("Using {} manually provided UTXOs", u.len());
        u
    } else {
        fetch_litecoin_utxos(sender_address)?
    };

    if utxos.is_empty() {
        return Err("No UTXOs found".into());
    }
    
    if utxos.is_empty() {
        return Err("No UTXOs available for this address".into());
    }
    
    // 2. Select Inputs (largest first for better coin selection)
    let mut sorted_utxos = utxos;
    sorted_utxos.sort_by(|a, b| b.value.cmp(&a.value));
    
    let mut inputs: Vec<LitecoinUtxo> = Vec::new();
    let mut total_input_value: u64 = 0;
    let target_value = amount_lits;
    
    for utxo in sorted_utxos {
        debug_log!("UTXO: txid={}, vout={}, value={} lits", utxo.transaction_hash, utxo.index, utxo.value);
        total_input_value += utxo.value;
        inputs.push(utxo);
        if total_input_value >= target_value {
            break;
        }
    }
    
    debug_log!("Selected {} inputs with total {} lits (1 lit = 1 satoshi)", inputs.len(), total_input_value);
    
    if total_input_value < target_value {
        return Err(format!("Insufficient funds: have {} lits, need {} lits", total_input_value, target_value).into());
    }
    
    // 3. Estimate Fee
    // P2WPKH Input: ~68 vbytes, P2WPKH Output: ~31 vbytes
    let estimated_size = 10 + (inputs.len() as u64 * 68) + (2 * 31);
    let fee = estimated_size * fee_rate_sats_per_vbyte;
    
    if total_input_value < target_value + fee {
        return Err(format!(
            "Insufficient funds for amount + fee. Have {}, need {}",
            total_input_value, target_value + fee
        ).into());
    }
    
    // 4. Build Transaction
    let change_amount = total_input_value - target_value - fee;
    
    // Decode recipient address (Litecoin bech32)
    let recipient_script = decode_litecoin_address(recipient)?;
    let sender_script = decode_litecoin_address(sender_address)?;
    
    let mut tx_inputs = Vec::new();
    for utxo in &inputs {
        tx_inputs.push(TxIn {
            previous_output: OutPoint::new(
                bitcoin::Txid::from_str(&utxo.transaction_hash)?,
                utxo.index
            ),
            script_sig: ScriptBuf::new(),
            sequence: Sequence::ENABLE_RBF_NO_LOCKTIME,
            witness: Witness::default(),
        });
    }
    
    let mut tx_outputs = Vec::new();
    // Recipient output
    tx_outputs.push(TxOut {
        value: Amount::from_sat(target_value),
        script_pubkey: recipient_script,
    });
    // Change output (if above dust)
    if change_amount > 5460 {  // Litecoin dust limit (slightly higher than BTC)
        tx_outputs.push(TxOut {
            value: Amount::from_sat(change_amount),
            script_pubkey: sender_script,
        });
    }
    
    let mut tx = Transaction {
        version: Version::TWO,
        lock_time: LockTime::ZERO,
        input: tx_inputs,
        output: tx_outputs,
    };
    
    debug_log!("Litecoin transaction built: {} inputs, {} outputs", tx.input.len(), tx.output.len());
    
    // 5. Sign each input
    for (i, utxo) in inputs.iter().enumerate() {
        // Use WPubkeyHash which expects hash160 (RIPEMD160(SHA256))
        let wpkh = bitcoin::WPubkeyHash::from_raw_hash(pubkey_hash);
        let witness_script = ScriptBuf::new_p2wpkh(&wpkh);
        
        let mut sighash_cache = SighashCache::new(&tx);
        let sighash = sighash_cache.p2wpkh_signature_hash(
            i,
            &witness_script,
            Amount::from_sat(utxo.value),
            EcdsaSighashType::All,
        )?;
        
        let msg = Message::from_digest(sighash.to_byte_array());
        let sig = secp.sign_ecdsa(&msg, &secret_key);
        
        // Serialize signature with SIGHASH_ALL byte
        let mut sig_bytes = sig.serialize_der().to_vec();
        sig_bytes.push(EcdsaSighashType::All.to_u32() as u8);
        
        // Build witness
        tx.input[i].witness = Witness::from_slice(&[
            &sig_bytes,
            &pubkey_bytes,
        ]);
    }
    
    // 6. Serialize and return hex
    let tx_bytes = encode::serialize(&tx);
    let tx_hex = hex::encode(&tx_bytes);
    
    debug_log!("Signed Litecoin transaction: {} bytes", tx_bytes.len());
    
    Ok(tx_hex)
}

/// Decode a Litecoin WIF private key (0xB0 prefix for mainnet)
fn decode_litecoin_wif(wif: &str) -> Result<(SecretKey, bool), Box<dyn Error>> {
    // Base58Check decode
    let decoded = bs58::decode(wif).into_vec()?;
    
    if decoded.len() < 5 {
        return Err("Invalid WIF length".into());
    }
    
    // Verify checksum
    let payload = &decoded[..decoded.len() - 4];
    let checksum = &decoded[decoded.len() - 4..];
    
    use bitcoin::hashes::sha256;
    let hash1 = sha256::Hash::hash(payload);
    let hash2 = sha256::Hash::hash(hash1.as_byte_array());
    let computed_checksum = &hash2.as_byte_array()[..4];
    
    if checksum != computed_checksum {
        return Err("Invalid WIF checksum".into());
    }
    
    // Check prefix (0xB0 for Litecoin mainnet, 0xEF for testnet)
    let prefix = payload[0];
    if prefix != 0xB0 && prefix != 0xEF {
        return Err(format!("Invalid Litecoin WIF prefix: 0x{:02X}", prefix).into());
    }
    
    // Extract secret key
    let compressed = payload.len() == 34 && payload[33] == 0x01;
    let key_bytes = if compressed {
        &payload[1..33]
    } else {
        &payload[1..]
    };
    
    let secret_key = SecretKey::from_slice(key_bytes)?;
    Ok((secret_key, compressed))
}

/// Decode a Litecoin bech32 address to script pubkey
fn decode_litecoin_address(address: &str) -> Result<ScriptBuf, Box<dyn Error>> {
    use bech32::{self, FromBase32};
    
    let address_lower = address.to_lowercase();
    
    // Check for Litecoin bech32 prefix
    if address_lower.starts_with("ltc1") || address_lower.starts_with("tltc1") {
        // Bech32 address
        let (hrp, data, _variant) = bech32::decode(&address_lower)?;
        
        if hrp != "ltc" && hrp != "tltc" {
            return Err(format!("Invalid Litecoin address HRP: {}", hrp).into());
        }
        
        if data.is_empty() {
            return Err("Empty bech32 data".into());
        }
        
        let version = data[0].to_u8();
        let program = Vec::<u8>::from_base32(&data[1..])?;
        
        if version == 0 && program.len() == 20 {
            // P2WPKH
            Ok(ScriptBuf::new_p2wpkh(&bitcoin::WPubkeyHash::from_slice(&program)?))
        } else if version == 0 && program.len() == 32 {
            // P2WSH
            Ok(ScriptBuf::new_p2wsh(&bitcoin::WScriptHash::from_slice(&program)?))
        } else {
            Err(format!("Unsupported witness version {} or program length {}", version, program.len()).into())
        }
    } else if address.starts_with("L") || address.starts_with("M") || address.starts_with("m") || address.starts_with("n") {
        // Legacy P2PKH or P2SH address (base58)
        let decoded = bs58::decode(address).into_vec()?;
        
        if decoded.len() < 5 {
            return Err("Invalid legacy address length".into());
        }
        
        let version = decoded[0];
        let hash = &decoded[1..decoded.len() - 4];
        
        // Litecoin: P2PKH prefix 0x30 (mainnet), P2SH prefix 0x32 (mainnet), 0x3A (M-address)
        // Testnet: P2PKH 0x6F, P2SH 0xC4
        if version == 0x30 || version == 0x6F {
            // P2PKH
            Ok(ScriptBuf::new_p2pkh(&bitcoin::PubkeyHash::from_slice(hash)?))
        } else if version == 0x32 || version == 0x3A || version == 0xC4 {
            // P2SH (M-address)
            Ok(ScriptBuf::new_p2sh(&bitcoin::ScriptHash::from_slice(hash)?))
        } else {
            Err(format!("Unknown Litecoin address version: 0x{:02X}", version).into())
        }
    } else {
        Err(format!("Unrecognized Litecoin address format: {}", address).into())
    }
}

use std::str::FromStr;

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_decode_litecoin_wif() {
        // Note: WIF decoding is tested via the actual transaction flow
        // This test verifies the structure is correct
        // A proper test would need a valid Litecoin WIF key
        // For now, we test that invalid WIFs are rejected
        let invalid_wif = "invalid_wif_string";
        assert!(decode_litecoin_wif(invalid_wif).is_err(), "Should reject invalid WIF");
    }
    
    #[test]
    fn test_decode_litecoin_bech32_address() {
        // Example Litecoin bech32 address
        let address = "ltc1qw508d6qejxtdg4y5r3zarvary0c5xw7kgmn4n9";
        let result = decode_litecoin_address(address);
        assert!(result.is_ok(), "Should decode valid bech32 address");
    }
}
