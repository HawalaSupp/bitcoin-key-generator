use std::error::Error;
use xrpl::wallet::Wallet;
use xrpl::models::transactions::payment::Payment;
use xrpl::models::XRPAmount;
use xrpl::core::binarycodec::encode;
use xrpl::transaction::sign;
use std::borrow::Cow;

pub fn prepare_xrp_transaction(
    recipient: &str,
    amount_drops: u64,
    sender_seed_hex: &str,
    sequence: u32,
) -> Result<String, Box<dyn Error>> {
    // 1. Create Wallet from seed
    let wallet = Wallet::new(sender_seed_hex, sequence as u64)
        .map_err(|e| format!("Wallet creation error: {:?}", e))?;

    // 2. Convert to owned strings to satisfy lifetime requirements
    let account_owned: Cow<'static, str> = Cow::Owned(wallet.classic_address.clone());
    let recipient_owned: Cow<'static, str> = Cow::Owned(recipient.to_string());
    let amount_str = amount_drops.to_string();
    let amount_xrp: XRPAmount<'static> = XRPAmount::from(amount_str.leak() as &'static str);
    let fee_xrp: XRPAmount<'static> = XRPAmount::from("12");

    // 3. Build Payment transaction using proper constructor
    // Payment::new(account, account_txn_id, fee, flags, last_ledger_sequence,
    //              memos, sequence, signers, source_tag, ticket_sequence,
    //              amount, destination, deliver_min, destination_tag, 
    //              invoice_id, paths, send_max)
    let mut payment = Payment::new(
        account_owned,                                        // account
        None,                                                 // account_txn_id
        Some(fee_xrp),                                        // fee (12 drops)
        None,                                                 // flags
        None,                                                 // last_ledger_sequence
        None,                                                 // memos
        Some(sequence),                                       // sequence
        None,                                                 // signers
        None,                                                 // source_tag
        None,                                                 // ticket_sequence
        amount_xrp.into(),                                    // amount
        recipient_owned,                                      // destination
        None,                                                 // deliver_min
        None,                                                 // destination_tag
        None,                                                 // invoice_id
        None,                                                 // paths
        None,                                                 // send_max
    );

    // 4. Sign the transaction (mutates payment in place)
    sign(&mut payment, &wallet, false)
        .map_err(|e| format!("Signing error: {:?}", e))?;

    // 5. Serialize signed transaction to blob (hex)
    let signed_blob = encode(&payment)
        .map_err(|e| format!("Encoding error: {:?}", e))?;

    Ok(signed_blob)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_xrp_transaction_signing() {
        // Test with a known XRP seed (testnet seed format)
        let test_seed = "sEdTLQkHAWpdS7FDk7EvuS7Mz8aSMRh";
        let recipient = "rPT1Sjq2YGrBMTttX4GZHjKu9dyfzbpAYe";
        let amount_drops = 1_000_000; // 1 XRP = 1,000,000 drops
        let sequence = 1;

        let result = prepare_xrp_transaction(recipient, amount_drops, test_seed, sequence);
        
        assert!(result.is_ok(), "XRP transaction signing failed: {:?}", result.err());
        
        let signed_blob = result.unwrap();
        
        // Verify the blob is valid hex and has reasonable length
        assert!(!signed_blob.is_empty(), "Signed blob should not be empty");
        assert!(signed_blob.len() > 100, "Signed blob seems too short");
        
        // Verify it's valid uppercase hex (XRPL format)
        assert!(signed_blob.chars().all(|c| c.is_ascii_hexdigit()), 
            "Signed blob should be valid hex");
        
        println!("✅ XRP signed transaction blob: {}...", &signed_blob[..64.min(signed_blob.len())]);
    }

    #[test]
    fn test_xrp_transaction_different_amounts() {
        let test_seed = "sEdTLQkHAWpdS7FDk7EvuS7Mz8aSMRh";
        let recipient = "rPT1Sjq2YGrBMTttX4GZHjKu9dyfzbpAYe";
        
        // Test with different amounts
        let amounts = vec![12, 1_000_000, 100_000_000, 1_000_000_000];
        
        for (seq, amount) in amounts.iter().enumerate() {
            let result = prepare_xrp_transaction(recipient, *amount, test_seed, (seq + 1) as u32);
            assert!(result.is_ok(), "Failed for amount {}: {:?}", amount, result.err());
        }
    }
}
