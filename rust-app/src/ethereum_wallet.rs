use ethers_core::types::{Address, Eip1559TransactionRequest, U256};
use ethers_core::utils::parse_ether;
use ethers_signers::{LocalWallet, Signer};
use std::error::Error;
use std::str::FromStr;

pub async fn prepare_ethereum_transaction(
    recipient: &str,
    amount_eth: &str,
    chain_id: u64,
    sender_key_hex: &str,
) -> Result<String, Box<dyn Error>> {
    // 1. Create Wallet
    let wallet = LocalWallet::from_str(sender_key_hex)?.with_chain_id(chain_id);

    // 2. Parse Amount
    let value = parse_ether(amount_eth)?;
    let to_address = Address::from_str(recipient)?;

    // 3. Fetch Gas Params (Mocked for FFI demo, in real app we'd fetch via RPC)
    // We assume the Swift side passes current gas params or we fetch them here.
    // For simplicity, we'll fetch them here if we had an RPC client, but to keep it pure logic:
    // We'll use hardcoded reasonable defaults for the demo or fetch via reqwest if needed.
    // Let's fetch via reqwest to be "World Class"

    let (max_fee, max_priority) =
        fetch_gas_price().unwrap_or((U256::from(20_000_000_000u64), U256::from(1_500_000_000u64)));
    let nonce = fetch_nonce(&format!("{:?}", wallet.address())).unwrap_or(U256::zero());

    // 4. Build EIP-1559 Transaction
    let tx = Eip1559TransactionRequest::new()
        .to(to_address)
        .value(value)
        .gas(21000) // Standard transfer gas
        .max_fee_per_gas(max_fee)
        .max_priority_fee_per_gas(max_priority)
        .chain_id(chain_id)
        .nonce(nonce);

    // 5. Sign
    let typed_tx = tx.clone().into();
    let signature = wallet.sign_transaction(&typed_tx).await?;
    let signed_tx = tx.rlp_signed(&signature);

    Ok(hex::encode(signed_tx))
}

// Helper to fetch gas via Cloudflare (simple JSON-RPC)
fn fetch_gas_price() -> Result<(U256, U256), Box<dyn Error>> {
    let client = reqwest::blocking::Client::new();
    let payload = serde_json::json!({
        "jsonrpc": "2.0",
        "method": "eth_gasPrice",
        "params": [],
        "id": 1
    });

    let resp = client
        .post("https://cloudflare-eth.com")
        .json(&payload)
        .send()?
        .json::<serde_json::Value>()?;

    if let Some(hex) = resp["result"].as_str() {
        let gas_price = U256::from_str_radix(hex.trim_start_matches("0x"), 16)?;
        // EIP-1559 heuristic: max_fee = 2 * base_fee + priority
        // We'll just use gas_price as a proxy for base_fee for this demo
        let priority = U256::from(1_500_000_000u64); // 1.5 gwei
        let max_fee = (gas_price * 2) + priority;
        Ok((max_fee, priority))
    } else {
        Err("Failed to fetch gas".into())
    }
}

fn fetch_nonce(address: &str) -> Result<U256, Box<dyn Error>> {
    let client = reqwest::blocking::Client::new();
    let payload = serde_json::json!({
        "jsonrpc": "2.0",
        "method": "eth_getTransactionCount",
        "params": [address, "latest"],
        "id": 1
    });

    let resp = client
        .post("https://cloudflare-eth.com")
        .json(&payload)
        .send()?
        .json::<serde_json::Value>()?;

    if let Some(hex) = resp["result"].as_str() {
        let nonce = U256::from_str_radix(hex.trim_start_matches("0x"), 16)?;
        Ok(nonce)
    } else {
        Err("Failed to fetch nonce".into())
    }
}
