#![allow(deprecated)]
use solana_sdk::{
    message::Message,
    pubkey::Pubkey,
    signature::{Keypair, Signer},
    system_instruction,
    transaction::Transaction,
};
use std::error::Error;
use std::str::FromStr;

pub fn prepare_solana_transaction(
    recipient: &str,
    amount_sol: f64,
    recent_blockhash: &str,
    sender_base58: &str,
) -> Result<String, Box<dyn Error>> {
    // 1. Parse Keys
    let sender_keypair = Keypair::from_base58_string(sender_base58);
    let recipient_pubkey = Pubkey::from_str(recipient)?;
    let blockhash = solana_sdk::hash::Hash::from_str(recent_blockhash)?;

    // 2. Convert Amount (SOL -> Lamports)
    let lamports = (amount_sol * 1_000_000_000.0) as u64;

    // 3. Create Instruction
    let instruction = system_instruction::transfer(
        &sender_keypair.pubkey(),
        &recipient_pubkey,
        lamports,
    );

    // 4. Build Transaction
    let message = Message::new(&[instruction], Some(&sender_keypair.pubkey()));
    let mut tx = Transaction::new_unsigned(message);
    
    // 5. Sign
    tx.try_sign(&[&sender_keypair], blockhash)?;

    // 6. Serialize
    let serialized = bincode::serialize(&tx)?;
    Ok(bs58::encode(serialized).into_string())
}
