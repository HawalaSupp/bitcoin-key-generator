//! Solana Pre-Image Hashing
//!
//! Generates signing hashes for Solana transactions.
//! Supports Legacy and Versioned (v0) transaction formats.

use super::{PreImageHash, PreImageError, PreImageResult, SigningAlgorithm};
use serde::{Deserialize, Serialize};
use sha2::{Sha256, Digest};

/// Solana transaction version
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SolanaVersion {
    /// Legacy transaction (no version prefix)
    Legacy,
    /// Versioned transaction v0 (with address lookup tables)
    V0,
}

/// Solana public key (32 bytes)
pub type Pubkey = [u8; 32];

/// Solana account meta for instruction
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SolanaAccountMeta {
    /// Account public key
    pub pubkey: Pubkey,
    /// Is signer
    pub is_signer: bool,
    /// Is writable
    pub is_writable: bool,
}

/// Solana instruction
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SolanaInstruction {
    /// Program ID
    pub program_id: Pubkey,
    /// Account metas
    pub accounts: Vec<SolanaAccountMeta>,
    /// Instruction data
    pub data: Vec<u8>,
}

/// Address lookup table for versioned transactions
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AddressLookupTable {
    /// Lookup table account address
    pub account_key: Pubkey,
    /// Writable indexes into the table
    pub writable_indexes: Vec<u8>,
    /// Readonly indexes into the table
    pub readonly_indexes: Vec<u8>,
}

/// Unsigned Solana transaction
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UnsignedSolanaTransaction {
    /// Transaction version
    pub version: SolanaVersion,
    /// Recent blockhash (32 bytes)
    pub recent_blockhash: [u8; 32],
    /// Fee payer
    pub fee_payer: Pubkey,
    /// Instructions
    pub instructions: Vec<SolanaInstruction>,
    /// Address lookup tables (for V0 only)
    pub address_lookup_tables: Option<Vec<AddressLookupTable>>,
    /// All signers (derivation paths or identifiers)
    pub signers: Vec<SolanaSignerInfo>,
}

/// Signer information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SolanaSignerInfo {
    /// Public key
    pub pubkey: Pubkey,
    /// Derivation path
    pub derivation_path: Option<String>,
}

/// Get signing hashes for a Solana transaction
/// 
/// Solana transactions may require multiple signatures.
/// Returns one PreImageHash per signer.
pub fn get_solana_message_hash(
    tx: &UnsignedSolanaTransaction,
) -> PreImageResult<Vec<PreImageHash>> {
    // Serialize the message
    let message = serialize_message(tx)?;
    
    // SHA256 hash of the message
    let mut hasher = Sha256::new();
    hasher.update(&message);
    let result = hasher.finalize();
    
    let mut hash = [0u8; 32];
    hash.copy_from_slice(&result);
    
    // Create PreImageHash for each signer
    let mut hashes = Vec::with_capacity(tx.signers.len());
    
    for (i, signer) in tx.signers.iter().enumerate() {
        let signer_id = signer.derivation_path.clone()
            .unwrap_or_else(|| bs58::encode(&signer.pubkey).into_string());
        
        let description = format!(
            "Solana {:?} tx: {} instruction(s), signer {}",
            tx.version,
            tx.instructions.len(),
            i + 1
        );
        
        let pre_image = PreImageHash::new(hash, signer_id, SigningAlgorithm::Ed25519)
            .with_input_index(i)
            .with_description(description);
        
        hashes.push(pre_image);
    }
    
    if hashes.is_empty() {
        return Err(PreImageError::MissingField("signers".to_string()));
    }
    
    Ok(hashes)
}

/// Serialize the transaction message for signing
fn serialize_message(tx: &UnsignedSolanaTransaction) -> PreImageResult<Vec<u8>> {
    match tx.version {
        SolanaVersion::Legacy => serialize_legacy_message(tx),
        SolanaVersion::V0 => serialize_v0_message(tx),
    }
}

/// Serialize legacy transaction message
pub fn serialize_legacy_message(tx: &UnsignedSolanaTransaction) -> PreImageResult<Vec<u8>> {
    let mut message = Vec::new();
    
    // Collect all unique accounts
    let (accounts, header) = compile_accounts(tx)?;
    
    // Message header (3 bytes)
    message.push(header.num_required_signatures);
    message.push(header.num_readonly_signed_accounts);
    message.push(header.num_readonly_unsigned_accounts);
    
    // Account addresses
    write_compact_u16(accounts.len() as u16, &mut message);
    for account in &accounts {
        message.extend_from_slice(account);
    }
    
    // Recent blockhash
    message.extend_from_slice(&tx.recent_blockhash);
    
    // Instructions
    write_compact_u16(tx.instructions.len() as u16, &mut message);
    for ix in &tx.instructions {
        let program_id_idx = accounts.iter()
            .position(|a| a == &ix.program_id)
            .ok_or_else(|| PreImageError::InvalidTransaction("Program ID not in accounts".to_string()))?;
        
        message.push(program_id_idx as u8);
        
        // Account indexes
        write_compact_u16(ix.accounts.len() as u16, &mut message);
        for acc in &ix.accounts {
            let idx = accounts.iter()
                .position(|a| a == &acc.pubkey)
                .ok_or_else(|| PreImageError::InvalidTransaction("Account not found".to_string()))?;
            message.push(idx as u8);
        }
        
        // Data
        write_compact_u16(ix.data.len() as u16, &mut message);
        message.extend_from_slice(&ix.data);
    }
    
    Ok(message)
}

/// Serialize versioned (v0) transaction message
pub fn serialize_v0_message(tx: &UnsignedSolanaTransaction) -> PreImageResult<Vec<u8>> {
    let mut message = Vec::new();
    
    // Version prefix (0x80 | version)
    message.push(0x80); // v0
    
    // Collect all unique accounts (static only, not from lookup tables)
    let (accounts, header) = compile_accounts(tx)?;
    
    // Message header (3 bytes)
    message.push(header.num_required_signatures);
    message.push(header.num_readonly_signed_accounts);
    message.push(header.num_readonly_unsigned_accounts);
    
    // Static account addresses
    write_compact_u16(accounts.len() as u16, &mut message);
    for account in &accounts {
        message.extend_from_slice(account);
    }
    
    // Recent blockhash
    message.extend_from_slice(&tx.recent_blockhash);
    
    // Instructions
    write_compact_u16(tx.instructions.len() as u16, &mut message);
    for ix in &tx.instructions {
        let program_id_idx = accounts.iter()
            .position(|a| a == &ix.program_id)
            .ok_or_else(|| PreImageError::InvalidTransaction("Program ID not in accounts".to_string()))?;
        
        message.push(program_id_idx as u8);
        
        // Account indexes
        write_compact_u16(ix.accounts.len() as u16, &mut message);
        for acc in &ix.accounts {
            let idx = accounts.iter()
                .position(|a| a == &acc.pubkey)
                .ok_or_else(|| PreImageError::InvalidTransaction("Account not found".to_string()))?;
            message.push(idx as u8);
        }
        
        // Data
        write_compact_u16(ix.data.len() as u16, &mut message);
        message.extend_from_slice(&ix.data);
    }
    
    // Address lookup tables
    if let Some(tables) = &tx.address_lookup_tables {
        write_compact_u16(tables.len() as u16, &mut message);
        for table in tables {
            message.extend_from_slice(&table.account_key);
            
            write_compact_u16(table.writable_indexes.len() as u16, &mut message);
            message.extend_from_slice(&table.writable_indexes);
            
            write_compact_u16(table.readonly_indexes.len() as u16, &mut message);
            message.extend_from_slice(&table.readonly_indexes);
        }
    } else {
        write_compact_u16(0, &mut message);
    }
    
    Ok(message)
}

/// Message header
struct MessageHeader {
    num_required_signatures: u8,
    num_readonly_signed_accounts: u8,
    num_readonly_unsigned_accounts: u8,
}

/// Compile accounts from transaction
fn compile_accounts(tx: &UnsignedSolanaTransaction) -> PreImageResult<(Vec<Pubkey>, MessageHeader)> {
    use std::collections::BTreeSet;
    
    // Track accounts by their properties
    let mut writable_signers: BTreeSet<Pubkey> = BTreeSet::new();
    let mut readonly_signers: BTreeSet<Pubkey> = BTreeSet::new();
    let mut writable_non_signers: BTreeSet<Pubkey> = BTreeSet::new();
    let mut readonly_non_signers: BTreeSet<Pubkey> = BTreeSet::new();
    
    // Fee payer is always writable signer
    writable_signers.insert(tx.fee_payer);
    
    // Process all accounts from instructions
    for ix in &tx.instructions {
        // Program ID is readonly non-signer
        readonly_non_signers.insert(ix.program_id);
        
        for acc in &ix.accounts {
            if acc.is_signer {
                if acc.is_writable {
                    writable_signers.insert(acc.pubkey);
                } else {
                    readonly_signers.insert(acc.pubkey);
                }
            } else {
                if acc.is_writable {
                    writable_non_signers.insert(acc.pubkey);
                } else {
                    readonly_non_signers.insert(acc.pubkey);
                }
            }
        }
    }
    
    // Remove duplicates (higher privilege wins)
    for pk in &writable_signers {
        readonly_signers.remove(pk);
        writable_non_signers.remove(pk);
        readonly_non_signers.remove(pk);
    }
    for pk in &readonly_signers {
        writable_non_signers.remove(pk);
        readonly_non_signers.remove(pk);
    }
    for pk in &writable_non_signers {
        readonly_non_signers.remove(pk);
    }
    
    // Build account list in order:
    // 1. Writable signers (fee payer first)
    // 2. Readonly signers
    // 3. Writable non-signers
    // 4. Readonly non-signers
    let mut accounts = Vec::new();
    
    // Ensure fee payer is first
    accounts.push(tx.fee_payer);
    for pk in writable_signers {
        if pk != tx.fee_payer {
            accounts.push(pk);
        }
    }
    
    let num_writable_signers = accounts.len();
    
    for pk in readonly_signers {
        accounts.push(pk);
    }
    
    let num_signers = accounts.len();
    let num_readonly_signed = num_signers - num_writable_signers;
    
    for pk in writable_non_signers {
        accounts.push(pk);
    }
    
    let num_writable_non_signers = accounts.len() - num_signers;
    
    for pk in readonly_non_signers {
        accounts.push(pk);
    }
    
    let num_readonly_unsigned = accounts.len() - num_signers - num_writable_non_signers;
    
    let header = MessageHeader {
        num_required_signatures: num_signers as u8,
        num_readonly_signed_accounts: num_readonly_signed as u8,
        num_readonly_unsigned_accounts: num_readonly_unsigned as u8,
    };
    
    Ok((accounts, header))
}

/// Write compact-u16 encoding (Solana's variable-length integer)
fn write_compact_u16(value: u16, buf: &mut Vec<u8>) {
    if value < 0x80 {
        buf.push(value as u8);
    } else if value < 0x4000 {
        buf.push((value & 0x7f) as u8 | 0x80);
        buf.push((value >> 7) as u8);
    } else {
        buf.push((value & 0x7f) as u8 | 0x80);
        buf.push(((value >> 7) & 0x7f) as u8 | 0x80);
        buf.push((value >> 14) as u8);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    fn sample_tx() -> UnsignedSolanaTransaction {
        let fee_payer = [1u8; 32];
        let program_id = [2u8; 32];
        let account1 = [3u8; 32];
        
        UnsignedSolanaTransaction {
            version: SolanaVersion::Legacy,
            recent_blockhash: [0xab; 32],
            fee_payer,
            instructions: vec![SolanaInstruction {
                program_id,
                accounts: vec![
                    SolanaAccountMeta {
                        pubkey: fee_payer,
                        is_signer: true,
                        is_writable: true,
                    },
                    SolanaAccountMeta {
                        pubkey: account1,
                        is_signer: false,
                        is_writable: true,
                    },
                ],
                data: vec![0x01, 0x02, 0x03],
            }],
            address_lookup_tables: None,
            signers: vec![SolanaSignerInfo {
                pubkey: fee_payer,
                derivation_path: Some("m/44'/501'/0'/0'".to_string()),
            }],
        }
    }
    
    #[test]
    fn test_legacy_message_hash() {
        let tx = sample_tx();
        let result = get_solana_message_hash(&tx);
        
        assert!(result.is_ok());
        let hashes = result.unwrap();
        assert_eq!(hashes.len(), 1);
        assert_eq!(hashes[0].algorithm, SigningAlgorithm::Ed25519);
        assert!(hashes[0].description.contains("Legacy"));
    }
    
    #[test]
    fn test_v0_message_hash() {
        let mut tx = sample_tx();
        tx.version = SolanaVersion::V0;
        tx.address_lookup_tables = Some(vec![AddressLookupTable {
            account_key: [4u8; 32],
            writable_indexes: vec![0, 1],
            readonly_indexes: vec![2],
        }]);
        
        let result = get_solana_message_hash(&tx);
        assert!(result.is_ok());
        assert!(result.unwrap()[0].description.contains("V0"));
    }
    
    #[test]
    fn test_multi_signer() {
        let mut tx = sample_tx();
        tx.signers.push(SolanaSignerInfo {
            pubkey: [5u8; 32],
            derivation_path: Some("m/44'/501'/0'/1'".to_string()),
        });
        
        let result = get_solana_message_hash(&tx);
        assert!(result.is_ok());
        
        let hashes = result.unwrap();
        assert_eq!(hashes.len(), 2);
        assert_eq!(hashes[0].input_index, Some(0));
        assert_eq!(hashes[1].input_index, Some(1));
    }
    
    #[test]
    fn test_no_signers_error() {
        let mut tx = sample_tx();
        tx.signers.clear();
        
        let result = get_solana_message_hash(&tx);
        assert!(matches!(result, Err(PreImageError::MissingField(_))));
    }
    
    #[test]
    fn test_compact_u16_encoding() {
        let mut buf = Vec::new();
        
        write_compact_u16(0, &mut buf);
        assert_eq!(buf, vec![0]);
        
        buf.clear();
        write_compact_u16(127, &mut buf);
        assert_eq!(buf, vec![127]);
        
        buf.clear();
        write_compact_u16(128, &mut buf);
        assert_eq!(buf, vec![0x80, 0x01]);
        
        buf.clear();
        write_compact_u16(16383, &mut buf);
        assert_eq!(buf, vec![0xff, 0x7f]);
        
        buf.clear();
        write_compact_u16(16384, &mut buf);
        assert_eq!(buf, vec![0x80, 0x80, 0x01]);
    }
    
    #[test]
    fn test_account_compilation() {
        let tx = sample_tx();
        let (accounts, header) = compile_accounts(&tx).unwrap();
        
        // Fee payer should be first
        assert_eq!(accounts[0], tx.fee_payer);
        
        // Should have 1 signer
        assert_eq!(header.num_required_signatures, 1);
    }
    
    #[test]
    fn test_complex_transaction() {
        let fee_payer = [1u8; 32];
        let signer2 = [2u8; 32];
        let writable = [3u8; 32];
        let readonly = [4u8; 32];
        let program = [5u8; 32];
        
        let tx = UnsignedSolanaTransaction {
            version: SolanaVersion::Legacy,
            recent_blockhash: [0; 32],
            fee_payer,
            instructions: vec![SolanaInstruction {
                program_id: program,
                accounts: vec![
                    SolanaAccountMeta { pubkey: fee_payer, is_signer: true, is_writable: true },
                    SolanaAccountMeta { pubkey: signer2, is_signer: true, is_writable: false },
                    SolanaAccountMeta { pubkey: writable, is_signer: false, is_writable: true },
                    SolanaAccountMeta { pubkey: readonly, is_signer: false, is_writable: false },
                ],
                data: vec![],
            }],
            address_lookup_tables: None,
            signers: vec![
                SolanaSignerInfo { pubkey: fee_payer, derivation_path: None },
                SolanaSignerInfo { pubkey: signer2, derivation_path: None },
            ],
        };
        
        let (accounts, header) = compile_accounts(&tx).unwrap();
        
        // 2 signers total (fee_payer writable, signer2 readonly)
        assert_eq!(header.num_required_signatures, 2);
        // 1 readonly signer
        assert_eq!(header.num_readonly_signed_accounts, 1);
        // 2 readonly unsigned (readonly + program)
        assert_eq!(header.num_readonly_unsigned_accounts, 2);
        
        // Order: writable signers, readonly signers, writable non-signers, readonly non-signers
        assert_eq!(accounts[0], fee_payer);
        assert_eq!(accounts[1], signer2);
    }
}
