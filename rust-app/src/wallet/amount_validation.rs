//! Transaction Amount Validation
//!
//! Validates transaction amounts including:
//! - Dust limits for UTXO chains
//! - Maximum values
//! - Decimal precision
//! - Gas/fee adequacy

use crate::error::{HawalaError, HawalaResult};
use crate::types::Chain;

/// Dust limits in smallest unit (satoshis, wei, etc.)
pub mod dust_limits {
    // Bitcoin dust limit (546 sats for P2PKH, 294 for P2WPKH)
    pub const BITCOIN_P2PKH: u64 = 546;
    pub const BITCOIN_P2WPKH: u64 = 294;
    pub const BITCOIN_P2TR: u64 = 330;
    
    // Litecoin (similar to Bitcoin)
    pub const LITECOIN: u64 = 546;
    
    // Ethereum - no protocol dust limit, but practical minimum
    // 21000 gas * 1 gwei = 21000 gwei = 0.000021 ETH
    pub const ETHEREUM_PRACTICAL: u64 = 21_000_000_000_000; // 0.000021 ETH in wei
    
    // Solana rent-exempt minimum
    pub const SOLANA_RENT_EXEMPT: u64 = 890_880; // lamports for basic account
    
    // XRP minimum reserve
    pub const XRP_RESERVE: u64 = 10_000_000; // 10 XRP in drops
}

/// Maximum transaction values
pub mod max_values {
    // Bitcoin max supply in satoshis
    pub const BITCOIN_MAX: u64 = 21_000_000 * 100_000_000;
    
    // Litecoin max supply in litoshis
    pub const LITECOIN_MAX: u64 = 84_000_000 * 100_000_000;
    
    // Ethereum - no fixed max, but sanity check
    pub const ETHEREUM_SANE_MAX: u128 = 1_000_000 * 1_000_000_000_000_000_000u128; // 1M ETH
    
    // Solana max lamports
    pub const SOLANA_MAX: u64 = u64::MAX;
    
    // XRP max drops
    pub const XRP_MAX: u64 = 100_000_000_000 * 1_000_000; // 100B XRP in drops
}

/// Amount validation result
#[derive(Debug, Clone)]
pub struct AmountValidation {
    pub is_valid: bool,
    pub amount_raw: u128,
    pub amount_display: String,
    pub warnings: Vec<String>,
    pub errors: Vec<String>,
}

/// Validate a transaction amount for a specific chain
pub fn validate_amount(
    amount: &str,
    chain: Chain,
    is_sending: bool,
) -> AmountValidation {
    let mut warnings = Vec::new();
    let mut errors = Vec::new();
    
    // Parse the amount
    let (amount_raw, decimals) = match parse_amount(amount, chain) {
        Ok(result) => result,
        Err(e) => {
            return AmountValidation {
                is_valid: false,
                amount_raw: 0,
                amount_display: amount.to_string(),
                warnings: vec![],
                errors: vec![e],
            };
        }
    };
    
    // Check for zero amount
    if amount_raw == 0 && is_sending {
        errors.push("Amount cannot be zero".to_string());
    }
    
    // Check dust limits for sending
    if is_sending {
        let dust_limit = get_dust_limit(chain);
        if amount_raw > 0 && (amount_raw as u64) < dust_limit {
            errors.push(format!(
                "Amount {} is below dust limit of {} {}",
                format_amount(amount_raw, decimals),
                format_amount(dust_limit as u128, decimals),
                chain.symbol()
            ));
        }
    }
    
    // Check maximum values
    let max_value = get_max_value(chain);
    if amount_raw > max_value {
        errors.push(format!(
            "Amount exceeds maximum possible value for {}",
            chain.symbol()
        ));
    }
    
    // Warn about large amounts
    let large_threshold = get_large_amount_threshold(chain);
    if amount_raw >= large_threshold {
        warnings.push("Large amount - please verify recipient address carefully".to_string());
    }
    
    // Chain-specific validation
    match chain {
        Chain::Xrp | Chain::XrpTestnet => {
            // XRP has minimum reserve requirement
            if is_sending && amount_raw < dust_limits::XRP_RESERVE as u128 {
                warnings.push("Recipient may need at least 10 XRP reserve to activate account".to_string());
            }
        }
        Chain::Solana | Chain::SolanaDevnet => {
            // Solana has rent exemption
            if amount_raw < dust_limits::SOLANA_RENT_EXEMPT as u128 {
                warnings.push("Amount may not be rent-exempt".to_string());
            }
        }
        _ => {}
    }
    
    let amount_display = format_amount(amount_raw, decimals);
    
    AmountValidation {
        is_valid: errors.is_empty(),
        amount_raw,
        amount_display,
        warnings,
        errors,
    }
}

/// Parse amount string to raw value and decimals
fn parse_amount(amount: &str, chain: Chain) -> Result<(u128, u8), String> {
    let trimmed = amount.trim();
    let decimals = get_decimals(chain);
    
    // Handle hex amounts (common for EVM)
    if trimmed.starts_with("0x") || trimmed.starts_with("0X") {
        let raw = u128::from_str_radix(trimmed.trim_start_matches("0x").trim_start_matches("0X"), 16)
            .map_err(|e| format!("Invalid hex amount: {}", e))?;
        return Ok((raw, decimals));
    }
    
    // Handle decimal amounts
    if trimmed.contains('.') {
        let parts: Vec<&str> = trimmed.split('.').collect();
        if parts.len() != 2 {
            return Err("Invalid decimal format".to_string());
        }
        
        let integer_part: u128 = parts[0].parse()
            .map_err(|e| format!("Invalid integer part: {}", e))?;
        
        let fractional_str = parts[1];
        if fractional_str.len() > decimals as usize {
            return Err(format!(
                "Too many decimal places: {} has max {} decimals",
                chain.symbol(),
                decimals
            ));
        }
        
        // Pad fractional part to full precision
        let padded = format!("{:0<width$}", fractional_str, width = decimals as usize);
        let fractional: u128 = padded.parse()
            .map_err(|e| format!("Invalid fractional part: {}", e))?;
        
        let multiplier = 10u128.pow(decimals as u32);
        let raw = integer_part
            .checked_mul(multiplier)
            .and_then(|v| v.checked_add(fractional))
            .ok_or("Amount overflow")?;
        
        Ok((raw, decimals))
    } else {
        // Integer - could be raw (satoshis/wei) or whole units
        let value: u128 = trimmed.parse()
            .map_err(|e| format!("Invalid amount: {}", e))?;
        
        // Heuristic: if the value is very large, assume it's already in smallest unit
        let multiplier = 10u128.pow(decimals as u32);
        if value >= multiplier {
            // Likely already in smallest unit
            Ok((value, decimals))
        } else {
            // Likely in display units - convert to smallest
            let raw = value.checked_mul(multiplier)
                .ok_or("Amount overflow")?;
            Ok((raw, decimals))
        }
    }
}

/// Format raw amount to display string
fn format_amount(raw: u128, decimals: u8) -> String {
    let multiplier = 10u128.pow(decimals as u32);
    let integer = raw / multiplier;
    let fractional = raw % multiplier;
    
    if fractional == 0 {
        integer.to_string()
    } else {
        let frac_str = format!("{:0>width$}", fractional, width = decimals as usize);
        let trimmed = frac_str.trim_end_matches('0');
        format!("{}.{}", integer, trimmed)
    }
}

/// Get decimal places for chain
fn get_decimals(chain: Chain) -> u8 {
    match chain {
        Chain::Bitcoin | Chain::BitcoinTestnet | Chain::Litecoin => 8,
        Chain::Ethereum | Chain::EthereumSepolia | Chain::Bnb | Chain::Polygon
        | Chain::Arbitrum | Chain::Optimism | Chain::Base | Chain::Avalanche => 18,
        Chain::Solana | Chain::SolanaDevnet => 9,
        Chain::Xrp | Chain::XrpTestnet => 6,
        Chain::Monero => 12,
        _ => chain.decimals(),
    }
}

/// Get dust limit for chain
fn get_dust_limit(chain: Chain) -> u64 {
    match chain {
        Chain::Bitcoin | Chain::BitcoinTestnet => dust_limits::BITCOIN_P2WPKH,
        Chain::Litecoin => dust_limits::LITECOIN,
        Chain::Ethereum | Chain::EthereumSepolia | Chain::Bnb | Chain::Polygon
        | Chain::Arbitrum | Chain::Optimism | Chain::Base | Chain::Avalanche => {
            dust_limits::ETHEREUM_PRACTICAL
        }
        Chain::Solana | Chain::SolanaDevnet => dust_limits::SOLANA_RENT_EXEMPT,
        Chain::Xrp | Chain::XrpTestnet => dust_limits::XRP_RESERVE,
        Chain::Monero => 1, // Monero has no dust limit
        _ => 1, // Default minimal dust limit
    }
}

/// Get maximum possible value for chain
fn get_max_value(chain: Chain) -> u128 {
    match chain {
        Chain::Bitcoin | Chain::BitcoinTestnet => max_values::BITCOIN_MAX as u128,
        Chain::Litecoin => max_values::LITECOIN_MAX as u128,
        Chain::Ethereum | Chain::EthereumSepolia | Chain::Bnb | Chain::Polygon
        | Chain::Arbitrum | Chain::Optimism | Chain::Base | Chain::Avalanche => {
            max_values::ETHEREUM_SANE_MAX
        }
        Chain::Solana | Chain::SolanaDevnet => max_values::SOLANA_MAX as u128,
        Chain::Xrp | Chain::XrpTestnet => max_values::XRP_MAX as u128,
        Chain::Monero => u128::MAX, // Monero has no fixed max
        _ => u128::MAX, // Default no max
    }
}

/// Get threshold for "large amount" warning
fn get_large_amount_threshold(chain: Chain) -> u128 {
    match chain {
        Chain::Bitcoin | Chain::BitcoinTestnet => 100_000_000, // 1 BTC
        Chain::Litecoin => 100_000_000, // 1 LTC
        Chain::Ethereum | Chain::EthereumSepolia => 1_000_000_000_000_000_000, // 1 ETH
        Chain::Bnb => 1_000_000_000_000_000_000, // 1 BNB
        Chain::Polygon | Chain::Arbitrum | Chain::Optimism | Chain::Base | Chain::Avalanche => {
            1_000_000_000_000_000_000 // 1 native token
        }
        Chain::Solana | Chain::SolanaDevnet => 1_000_000_000, // 1 SOL
        Chain::Xrp | Chain::XrpTestnet => 1_000_000_000, // 1000 XRP
        Chain::Monero => 1_000_000_000_000, // 1 XMR
        _ => 10u128.pow(chain.decimals() as u32), // 1 native token
    }
}

/// Validate gas parameters for EVM transaction
pub fn validate_gas_params(
    gas_limit: u64,
    gas_price: Option<u64>,
    max_fee_per_gas: Option<u64>,
    max_priority_fee_per_gas: Option<u64>,
    chain: Chain,
) -> HawalaResult<()> {
    // Minimum gas limit for any transaction
    const MIN_GAS_LIMIT: u64 = 21_000;
    const MAX_GAS_LIMIT: u64 = 30_000_000;
    
    if gas_limit < MIN_GAS_LIMIT {
        return Err(HawalaError::invalid_input(format!(
            "Gas limit {} is below minimum of {}",
            gas_limit, MIN_GAS_LIMIT
        )));
    }
    
    if gas_limit > MAX_GAS_LIMIT {
        return Err(HawalaError::invalid_input(format!(
            "Gas limit {} exceeds maximum of {}",
            gas_limit, MAX_GAS_LIMIT
        )));
    }
    
    // Check that we have either legacy or EIP-1559 gas params
    let has_legacy = gas_price.is_some();
    let has_eip1559 = max_fee_per_gas.is_some();
    
    if !has_legacy && !has_eip1559 {
        return Err(HawalaError::invalid_input(
            "Either gas_price (legacy) or max_fee_per_gas (EIP-1559) required"
        ));
    }
    
    // Validate EIP-1559 params
    if let (Some(max_fee), Some(priority_fee)) = (max_fee_per_gas, max_priority_fee_per_gas) {
        if priority_fee > max_fee {
            return Err(HawalaError::invalid_input(
                "max_priority_fee_per_gas cannot exceed max_fee_per_gas"
            ));
        }
    }
    
    // Chain-specific validation
    match chain {
        Chain::Bnb => {
            // BSC doesn't support EIP-1559
            if has_eip1559 && !has_legacy {
                return Err(HawalaError::invalid_input(
                    "BSC does not support EIP-1559 - use gas_price instead"
                ));
            }
        }
        _ => {}
    }
    
    Ok(())
}

/// Quick validation - returns error if amount is invalid
pub fn require_valid_amount(amount: &str, chain: Chain) -> HawalaResult<u128> {
    let validation = validate_amount(amount, chain, true);
    
    if !validation.is_valid {
        let errors = validation.errors.join("; ");
        return Err(HawalaError::invalid_input(format!(
            "Invalid amount '{}': {}",
            amount, errors
        )));
    }
    
    Ok(validation.amount_raw)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_bitcoin_amount() {
        // Decimal BTC
        let validation = validate_amount("0.001", Chain::Bitcoin, true);
        assert!(validation.is_valid);
        assert_eq!(validation.amount_raw, 100_000);
        
        // Satoshis
        let validation = validate_amount("100000", Chain::Bitcoin, true);
        assert!(validation.is_valid);
    }

    #[test]
    fn test_dust_limit() {
        // Below dust - 100 satoshis expressed as BTC decimal
        let validation = validate_amount("0.00000100", Chain::Bitcoin, true);
        assert!(!validation.is_valid);
        assert!(validation.errors.iter().any(|e| e.contains("dust")));
    }

    #[test]
    fn test_ethereum_amount() {
        // 1 ETH in wei
        let validation = validate_amount("1000000000000000000", Chain::Ethereum, true);
        assert!(validation.is_valid);
        
        // Hex format
        let validation = validate_amount("0xDE0B6B3A7640000", Chain::Ethereum, true);
        assert!(validation.is_valid);
        assert_eq!(validation.amount_raw, 1_000_000_000_000_000_000u128);
    }

    #[test]
    fn test_large_amount_warning() {
        let validation = validate_amount("10", Chain::Bitcoin, true); // 10 BTC
        assert!(validation.is_valid);
        assert!(validation.warnings.iter().any(|w| w.contains("Large amount")));
    }

    #[test]
    fn test_gas_validation() {
        // Valid legacy
        assert!(validate_gas_params(21000, Some(20_000_000_000), None, None, Chain::Ethereum).is_ok());
        
        // Valid EIP-1559
        assert!(validate_gas_params(21000, None, Some(30_000_000_000), Some(2_000_000_000), Chain::Ethereum).is_ok());
        
        // Priority > max fee (invalid)
        assert!(validate_gas_params(21000, None, Some(20_000_000_000), Some(30_000_000_000), Chain::Ethereum).is_err());
        
        // Gas limit too low
        assert!(validate_gas_params(1000, Some(20_000_000_000), None, None, Chain::Ethereum).is_err());
    }
}
