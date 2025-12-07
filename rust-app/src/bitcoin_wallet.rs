use bitcoin::hashes::Hash; // Import Hash trait for as_byte_array
use bitcoin::secp256k1::{Message, Secp256k1};
use bitcoin::sighash::{EcdsaSighashType, SighashCache};
use bitcoin::{
    Address, Amount, Network, NetworkKind, OutPoint, ScriptBuf, Sequence, Transaction, TxIn, TxOut, Witness,
    absolute::LockTime, consensus::encode, transaction::Version,
};
use serde::Deserialize;
use std::error::Error;
use std::str::FromStr;

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

pub fn fetch_utxos(address: &str, network: Network) -> Result<Vec<Utxo>, Box<dyn Error>> {
    let base_url = match network {
        Network::Bitcoin => "https://blockstream.info/api",
        Network::Testnet => "https://blockstream.info/testnet/api",
        _ => return Err("Unsupported network for UTXO fetch".into()),
    };
    let url = format!("{}/address/{}/utxo", base_url, address);
    let resp = reqwest::blocking::get(&url)?.text()?;
    let utxos: Vec<Utxo> = serde_json::from_str(&resp)?;
    Ok(utxos)
}

pub fn prepare_transaction(
    recipient: &str,
    amount_sats: u64,
    fee_rate_sats_per_vbyte: u64,
    sender_wif: &str,
) -> Result<String, Box<dyn Error>> {
    let secp = Secp256k1::new();
    let private_key = bitcoin::PrivateKey::from_wif(sender_wif)?;
    let network = match private_key.network {
        NetworkKind::Main => Network::Bitcoin,
        NetworkKind::Test => Network::Testnet,
    };
    let public_key = private_key.public_key(&secp);
    // Convert to CompressedPublicKey (P2WPKH requires compressed keys)
    let compressed_public_key = bitcoin::key::CompressedPublicKey::try_from(public_key)
        .map_err(|_| "Failed to compress public key")?;

    let sender_address = Address::p2wpkh(&compressed_public_key, network);

    // 1. Fetch UTXOs
    let utxos = fetch_utxos(&sender_address.to_string(), network)?;

    // 2. Select Inputs (Simple FIFO)
    let mut inputs = Vec::new();
    let mut total_input_value = 0;
    let target_value = amount_sats; // We'll add fee later

    for utxo in utxos {
        inputs.push(utxo);
        total_input_value += inputs.last().unwrap().value;
        if total_input_value >= target_value {
            break;
        }
    }

    if total_input_value < target_value {
        return Err("Insufficient funds".into());
    }

    // 3. Estimate Fee (Simple approximation: 1 input ~68 vbytes, 1 output ~31 vbytes, overhead ~10 vbytes)
    // P2WPKH Input: ~68 vbytes
    // P2WPKH Output: ~31 vbytes
    let estimated_size = 10 + (inputs.len() as u64 * 68) + (2 * 31); // 2 outputs (recipient + change)
    let fee = estimated_size * fee_rate_sats_per_vbyte;

    if total_input_value < target_value + fee {
        return Err(format!(
            "Insufficient funds for amount + fee. Have {}, need {}",
            total_input_value,
            target_value + fee
        )
        .into());
    }

    // 4. Build Transaction
    let recipient_address = Address::from_str(recipient)?.require_network(network)?;
    let change_address = sender_address.clone();
    let change_amount = total_input_value - target_value - fee;

    let mut tx_inputs = Vec::new();
    for utxo in &inputs {
        tx_inputs.push(TxIn {
            previous_output: OutPoint::new(bitcoin::Txid::from_str(&utxo.txid)?, utxo.vout),
            script_sig: ScriptBuf::new(), // Segwit inputs have empty script_sig
            sequence: Sequence::ENABLE_RBF_NO_LOCKTIME,
            witness: Witness::default(),
        });
    }

    let mut tx_outputs = Vec::new();
    // Recipient Output
    tx_outputs.push(TxOut {
        value: Amount::from_sat(target_value),
        script_pubkey: recipient_address.script_pubkey(),
    });
    // Change Output (if dust, maybe skip? for now keep simple)
    if change_amount > 546 {
        // Dust limit
        tx_outputs.push(TxOut {
            value: Amount::from_sat(change_amount),
            script_pubkey: change_address.script_pubkey(),
        });
    }

    let mut tx = Transaction {
        version: Version::TWO,
        lock_time: LockTime::ZERO,
        input: tx_inputs,
        output: tx_outputs,
    };

    // 5. Sign Inputs
    let mut sighasher = SighashCache::new(&mut tx);

    for (i, input) in inputs.iter().enumerate() {
        let input_amount = Amount::from_sat(input.value);
        let script_code = sender_address.script_pubkey();

        let sighash = sighasher.p2wpkh_signature_hash(
            i,
            &script_code,
            input_amount,
            EcdsaSighashType::All,
        )?;

        let msg = Message::from_digest_slice(sighash.as_byte_array())?;
        let signature = secp.sign_ecdsa(&msg, &private_key.inner);

        // Update witness
        let mut witness = Witness::new();
        // Serialize signature: DER + SighashType byte
        let mut sig_vec = signature.serialize_der().to_vec();
        sig_vec.push(EcdsaSighashType::All as u8);
        witness.push(sig_vec);
        witness.push(compressed_public_key.to_bytes());

        *sighasher.witness_mut(i).unwrap() = witness;
    }

    // 6. Serialize
    let raw_hex = hex::encode(encode::serialize(&tx));
    Ok(raw_hex)
}
