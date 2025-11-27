use std::error::Error;

pub fn fetch_bitcoin_balance(address: &str) -> Result<String, Box<dyn Error>> {
    // Using blockstream.info API for demo purposes
    let url = format!("https://blockstream.info/api/address/{}", address);
    let resp = reqwest::blocking::get(&url)?.text()?;

    // Parse JSON response (simplified)
    // Expected structure: {"chain_stats": {"funded_txo_sum": 123, "spent_txo_sum": 0}, ...}
    let json: serde_json::Value = serde_json::from_str(&resp)?;
    let funded = json["chain_stats"]["funded_txo_sum"].as_i64().unwrap_or(0);
    let spent = json["chain_stats"]["spent_txo_sum"].as_i64().unwrap_or(0);
    let balance_sats = funded - spent;

    // Convert sats to BTC string
    let balance_btc = balance_sats as f64 / 100_000_000.0;
    Ok(format!("{:.8}", balance_btc))
}

pub fn fetch_ethereum_balance(address: &str) -> Result<String, Box<dyn Error>> {
    // Using a public RPC endpoint (Cloudflare)
    let client = reqwest::blocking::Client::new();
    let payload = serde_json::json!({
        "jsonrpc": "2.0",
        "method": "eth_getBalance",
        "params": [address, "latest"],
        "id": 1
    });

    let resp = client
        .post("https://cloudflare-eth.com")
        .json(&payload)
        .send()?
        .json::<serde_json::Value>()?;

    if let Some(hex_bal) = resp["result"].as_str() {
        let balance_wei = u128::from_str_radix(hex_bal.trim_start_matches("0x"), 16)?;
        let balance_eth = balance_wei as f64 / 1_000_000_000_000_000_000.0;
        Ok(format!("{:.4}", balance_eth))
    } else {
        Err("Failed to parse Ethereum balance".into())
    }
}
