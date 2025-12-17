use ethers_core::types::{Address, TransactionRequest, Eip1559TransactionRequest, U256};
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
    gas_price_wei: Option<String>,
    max_fee_per_gas_wei: Option<String>,
    max_priority_fee_per_gas_wei: Option<String>,
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

    let data = if data_hex.starts_with("0x") {
        hex::decode(data_hex.trim_start_matches("0x"))?
    } else {
        hex::decode(data_hex)?
    };

    // 3. Build Transaction
    let typed_tx: ethers_core::types::transaction::eip2718::TypedTransaction = if let Some(max_fee) = max_fee_per_gas_wei {
        // EIP-1559
        let max_fee_per_gas = if max_fee.starts_with("0x") {
            U256::from_str_radix(max_fee.trim_start_matches("0x"), 16)?
        } else {
            U256::from_dec_str(&max_fee)?
        };

        let max_priority_fee_per_gas = if let Some(priority) = max_priority_fee_per_gas_wei {
            if priority.starts_with("0x") {
                U256::from_str_radix(priority.trim_start_matches("0x"), 16)?
            } else {
                U256::from_dec_str(&priority)?
            }
        } else {
            U256::zero()
        };

        Eip1559TransactionRequest::new()
            .to(to_address)
            .value(value)
            .gas(gas_limit)
            .max_fee_per_gas(max_fee_per_gas)
            .max_priority_fee_per_gas(max_priority_fee_per_gas)
            .chain_id(chain_id)
            .nonce(nonce)
            .data(data)
            .into()
    } else {
        // Legacy
        let gas_price_str = gas_price_wei.ok_or("Missing gas_price for legacy transaction")?;
        let gas_price = if gas_price_str.starts_with("0x") {
            U256::from_str_radix(gas_price_str.trim_start_matches("0x"), 16)?
        } else {
            U256::from_dec_str(&gas_price_str)?
        };

        TransactionRequest::new()
            .to(to_address)
            .value(value)
            .gas(gas_limit)
            .gas_price(gas_price)
            .chain_id(chain_id)
            .nonce(nonce)
            .data(data)
            .into()
    };

    // 4. Sign
    let signature = wallet.sign_transaction(&typed_tx).await?;
    let signed_tx = typed_tx.rlp_signed(&signature);

    Ok(format!("0x{}", hex::encode(signed_tx)))
}


