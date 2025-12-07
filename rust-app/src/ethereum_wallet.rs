use ethers_core::types::{Address, TransactionRequest, U256};
use ethers_signers::{LocalWallet, Signer};
use std::error::Error;
use std::str::FromStr;

pub async fn prepare_ethereum_transaction(
    recipient: &str,
    amount_wei: &str,
    chain_id: u64,
    sender_key_hex: &str,
    nonce: u64,
    gas_limit: u64,
    gas_price_wei: &str,
    data_hex: &str,
) -> Result<String, Box<dyn Error>> {
    // 1. Create Wallet
    let wallet = LocalWallet::from_str(sender_key_hex)?.with_chain_id(chain_id);

    // 2. Parse Params
    // Handle both hex (0x...) and decimal strings
    let value = if amount_wei.starts_with("0x") {
        U256::from_str_radix(amount_wei.trim_start_matches("0x"), 16)?
    } else {
        U256::from_dec_str(amount_wei)?
    };
    
    let to_address = Address::from_str(recipient)?;
    
    let gas_price = if gas_price_wei.starts_with("0x") {
        U256::from_str_radix(gas_price_wei.trim_start_matches("0x"), 16)?
    } else {
        U256::from_dec_str(gas_price_wei)?
    };

    let data = if data_hex.starts_with("0x") {
        hex::decode(data_hex.trim_start_matches("0x"))?
    } else {
        hex::decode(data_hex)?
    };

    // 3. Build Legacy Transaction (EIP-155)
    let tx = TransactionRequest::new()
        .to(to_address)
        .value(value)
        .gas(gas_limit)
        .gas_price(gas_price)
        .chain_id(chain_id)
        .nonce(nonce)
        .data(data);

    // 4. Sign
    let typed_tx: ethers_core::types::transaction::eip2718::TypedTransaction = tx.into();
    let signature = wallet.sign_transaction(&typed_tx).await?;
    let signed_tx = typed_tx.rlp_signed(&signature);

    Ok(format!("0x{}", hex::encode(signed_tx)))
}


