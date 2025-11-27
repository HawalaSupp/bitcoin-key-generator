use serde::{Deserialize, Serialize};
use std::error::Error;

#[derive(Debug, Serialize, Deserialize)]
pub struct TransactionHistoryItem {
    pub txid: String,
    pub amount_sats: i64, // Positive for receive, negative for send
    pub confirmed: bool,
    pub timestamp: Option<u64>,
    pub height: Option<u64>,
}

#[derive(Deserialize)]
struct EsploraTx {
    txid: String,
    status: EsploraStatus,
    vin: Vec<EsploraVin>,
    vout: Vec<EsploraVout>,
}

#[derive(Deserialize)]
struct EsploraStatus {
    confirmed: bool,
    block_time: Option<u64>,
    block_height: Option<u64>,
}

#[derive(Deserialize)]
struct EsploraVin {
    prevout: Option<EsploraVout>,
}

#[derive(Deserialize)]
struct EsploraVout {
    scriptpubkey_address: Option<String>,
    value: u64,
}

pub fn fetch_bitcoin_history(address: &str) -> Result<Vec<TransactionHistoryItem>, Box<dyn Error>> {
    // Use testnet API if address starts with 'tb1' or 'm' or 'n' (simplified check)
    // For now, let's assume mainnet unless we want to pass network as arg.
    // Actually, let's try to detect or just use mainnet for now, but the user might be on testnet.
    // The user's address in previous logs was 'tb1...', so they are using Testnet.
    
    let base_url = if address.starts_with("tb1") || address.starts_with("m") || address.starts_with("n") || address.starts_with("2") {
        "https://blockstream.info/testnet/api"
    } else {
        "https://blockstream.info/api"
    };

    let url = format!("{}/address/{}/txs", base_url, address);
    let resp = reqwest::blocking::get(&url)?.json::<Vec<EsploraTx>>()?;

    let mut history = Vec::new();

    for tx in resp {
        let mut net_sats: i64 = 0;

        // Check inputs (spending)
        for input in &tx.vin {
            if let Some(prevout) = &input.prevout {
                if let Some(addr) = &prevout.scriptpubkey_address {
                    if addr == address {
                        net_sats -= prevout.value as i64;
                    }
                }
            }
        }

        // Check outputs (receiving)
        for output in &tx.vout {
            if let Some(addr) = &output.scriptpubkey_address {
                if addr == address {
                    net_sats += output.value as i64;
                }
            }
        }

        history.push(TransactionHistoryItem {
            txid: tx.txid,
            amount_sats: net_sats,
            confirmed: tx.status.confirmed,
            timestamp: tx.status.block_time,
            height: tx.status.block_height,
        });
    }

    Ok(history)
}
