//! CPFP fee calculator
//!
//! Calculates the required child transaction fee to achieve a target
//! package fee rate for the parent + child combination.

use super::types::*;

/// Transaction size constants (in virtual bytes)
pub struct TxSizeConstants;

impl TxSizeConstants {
    /// Base transaction overhead (version, locktime, etc.)
    pub const TX_OVERHEAD: u64 = 10;

    /// P2WPKH input size (native SegWit)
    pub const P2WPKH_INPUT: u64 = 68;

    /// P2PKH input size (legacy)
    pub const P2PKH_INPUT: u64 = 148;

    /// P2SH-P2WPKH input size (wrapped SegWit)
    pub const P2SH_P2WPKH_INPUT: u64 = 91;

    /// P2TR input size (Taproot)
    pub const P2TR_INPUT: u64 = 58;

    /// P2WPKH output size
    pub const P2WPKH_OUTPUT: u64 = 31;

    /// P2PKH output size
    pub const P2PKH_OUTPUT: u64 = 34;

    /// P2SH output size
    pub const P2SH_OUTPUT: u64 = 32;

    /// P2TR output size
    pub const P2TR_OUTPUT: u64 = 43;

    /// P2WSH output size
    pub const P2WSH_OUTPUT: u64 = 43;
}

/// Address type for size estimation
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AddressType {
    /// Legacy P2PKH (1...)
    P2PKH,
    /// Legacy P2SH (3...)
    P2SH,
    /// Native SegWit P2WPKH (bc1q...)
    P2WPKH,
    /// Native SegWit P2WSH (bc1q... longer)
    P2WSH,
    /// Taproot P2TR (bc1p...)
    P2TR,
}

impl AddressType {
    /// Detect address type from address string
    pub fn from_address(address: &str) -> Option<Self> {
        if address.starts_with("bc1p") || address.starts_with("tb1p") {
            Some(AddressType::P2TR)
        } else if address.starts_with("bc1q") || address.starts_with("tb1q") {
            // P2WPKH is 42 chars, P2WSH is 62 chars
            if address.len() <= 44 {
                Some(AddressType::P2WPKH)
            } else {
                Some(AddressType::P2WSH)
            }
        } else if address.starts_with('3') || address.starts_with('2') {
            Some(AddressType::P2SH)
        } else if address.starts_with('1') || address.starts_with('m') || address.starts_with('n')
        {
            Some(AddressType::P2PKH)
        } else {
            None
        }
    }

    /// Get input size for this address type
    pub fn input_size(&self) -> u64 {
        match self {
            AddressType::P2PKH => TxSizeConstants::P2PKH_INPUT,
            AddressType::P2SH => TxSizeConstants::P2SH_P2WPKH_INPUT,
            AddressType::P2WPKH => TxSizeConstants::P2WPKH_INPUT,
            AddressType::P2WSH => 105, // Approximate
            AddressType::P2TR => TxSizeConstants::P2TR_INPUT,
        }
    }

    /// Get output size for this address type
    pub fn output_size(&self) -> u64 {
        match self {
            AddressType::P2PKH => TxSizeConstants::P2PKH_OUTPUT,
            AddressType::P2SH => TxSizeConstants::P2SH_OUTPUT,
            AddressType::P2WPKH => TxSizeConstants::P2WPKH_OUTPUT,
            AddressType::P2WSH => TxSizeConstants::P2WSH_OUTPUT,
            AddressType::P2TR => TxSizeConstants::P2TR_OUTPUT,
        }
    }
}

/// CPFP fee calculator
pub struct CpfpCalculator;

impl CpfpCalculator {
    /// Calculate the required child fee to achieve target package fee rate
    ///
    /// Formula: child_fee = (target_rate * (parent_vsize + child_vsize)) - parent_fee
    pub fn calculate_required_child_fee(
        parent_vsize: u64,
        parent_fee: u64,
        child_vsize: u64,
        target_fee_rate: f64,
    ) -> u64 {
        let package_vsize = parent_vsize + child_vsize;
        let target_package_fee = (target_fee_rate * package_vsize as f64).ceil() as u64;

        // Child fee must cover the deficit
        if target_package_fee > parent_fee {
            target_package_fee - parent_fee
        } else {
            // Parent already meets target, minimal fee for child
            (target_fee_rate * child_vsize as f64).ceil() as u64
        }
    }

    /// Estimate child transaction size
    pub fn estimate_child_vsize(
        input_count: usize,
        input_type: AddressType,
        output_type: AddressType,
    ) -> u64 {
        let input_size = input_type.input_size() * input_count as u64;
        let output_size = output_type.output_size();

        TxSizeConstants::TX_OVERHEAD + input_size + output_size
    }

    /// Calculate if CPFP is economically viable
    pub fn is_cpfp_viable(
        parent_vsize: u64,
        parent_fee: u64,
        child_vsize: u64,
        available_value: u64,
        target_fee_rate: f64,
        dust_limit: u64,
    ) -> Result<CpfpViability, CpfpError> {
        let required_child_fee =
            Self::calculate_required_child_fee(parent_vsize, parent_fee, child_vsize, target_fee_rate);

        let output_after_fee = if available_value > required_child_fee {
            available_value - required_child_fee
        } else {
            0
        };

        if available_value < required_child_fee {
            return Err(CpfpError::InsufficientFunds {
                required: required_child_fee,
                available: available_value,
            });
        }

        if output_after_fee < dust_limit {
            return Err(CpfpError::InsufficientFunds {
                required: required_child_fee + dust_limit,
                available: available_value,
            });
        }

        Ok(CpfpViability {
            is_viable: true,
            required_child_fee,
            output_amount: output_after_fee,
            effective_package_rate: Self::calculate_package_fee_rate(
                parent_vsize,
                parent_fee,
                child_vsize,
                required_child_fee,
            ),
        })
    }

    /// Calculate the effective package fee rate
    pub fn calculate_package_fee_rate(
        parent_vsize: u64,
        parent_fee: u64,
        child_vsize: u64,
        child_fee: u64,
    ) -> f64 {
        let package_vsize = parent_vsize + child_vsize;
        let package_fee = parent_fee + child_fee;

        if package_vsize > 0 {
            package_fee as f64 / package_vsize as f64
        } else {
            0.0
        }
    }

    /// Calculate fee bump percentage needed
    pub fn fee_bump_percentage(current_rate: f64, target_rate: f64) -> f64 {
        if current_rate > 0.0 {
            ((target_rate - current_rate) / current_rate) * 100.0
        } else {
            f64::INFINITY
        }
    }

    /// Suggest minimum fee rate bump (typically 1 sat/vB minimum increment)
    pub fn minimum_bump_rate(current_rate: f64) -> f64 {
        // Bitcoin Core requires at least 1 sat/vB increment for RBF
        // CPFP should also use a meaningful bump
        (current_rate + 1.0).max(1.0)
    }
}

/// Result of CPFP viability check
#[derive(Debug, Clone)]
pub struct CpfpViability {
    pub is_viable: bool,
    pub required_child_fee: u64,
    pub output_amount: u64,
    pub effective_package_rate: f64,
}

/// Standard Bitcoin dust limits
pub struct DustLimits;

impl DustLimits {
    /// P2PKH dust limit
    pub const P2PKH: u64 = 546;

    /// P2WPKH dust limit
    pub const P2WPKH: u64 = 294;

    /// P2TR dust limit
    pub const P2TR: u64 = 330;

    /// P2SH dust limit
    pub const P2SH: u64 = 540;

    /// Get dust limit for address type
    pub fn for_type(addr_type: AddressType) -> u64 {
        match addr_type {
            AddressType::P2PKH => Self::P2PKH,
            AddressType::P2SH => Self::P2SH,
            AddressType::P2WPKH => Self::P2WPKH,
            AddressType::P2WSH => Self::P2WPKH, // Same as P2WPKH
            AddressType::P2TR => Self::P2TR,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_address_type_detection() {
        // Mainnet
        assert_eq!(
            AddressType::from_address("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"),
            Some(AddressType::P2PKH)
        );
        assert_eq!(
            AddressType::from_address("3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy"),
            Some(AddressType::P2SH)
        );
        assert_eq!(
            AddressType::from_address("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"),
            Some(AddressType::P2WPKH)
        );
        assert_eq!(
            AddressType::from_address("bc1p5d7rjq7g6rdk2yhzks9smlaqtedr4dekq08ge8ztwac72sfr9rusxg3297"),
            Some(AddressType::P2TR)
        );

        // Testnet
        assert_eq!(
            AddressType::from_address("tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx"),
            Some(AddressType::P2WPKH)
        );
    }

    #[test]
    fn test_input_output_sizes() {
        assert_eq!(AddressType::P2WPKH.input_size(), 68);
        assert_eq!(AddressType::P2PKH.input_size(), 148);
        assert_eq!(AddressType::P2TR.input_size(), 58);

        assert_eq!(AddressType::P2WPKH.output_size(), 31);
        assert_eq!(AddressType::P2TR.output_size(), 43);
    }

    #[test]
    fn test_calculate_required_child_fee() {
        // Parent: 200 vB, 1000 sat fee (5 sat/vB)
        // Child: 150 vB
        // Target: 50 sat/vB
        // Package: 350 vB, needs 17500 sat total
        // Child needs: 17500 - 1000 = 16500 sat

        let child_fee = CpfpCalculator::calculate_required_child_fee(200, 1000, 150, 50.0);
        assert_eq!(child_fee, 16500);
    }

    #[test]
    fn test_calculate_required_child_fee_parent_sufficient() {
        // Parent already at target rate
        // Parent: 100 vB, 5000 sat fee (50 sat/vB)
        // Target: 50 sat/vB
        // Child only needs minimal fee

        let child_fee = CpfpCalculator::calculate_required_child_fee(100, 5000, 100, 50.0);
        // Package needs 10000, parent has 5000, so child needs 5000
        assert_eq!(child_fee, 5000);
    }

    #[test]
    fn test_estimate_child_vsize() {
        // 1 P2WPKH input, 1 P2WPKH output
        let vsize = CpfpCalculator::estimate_child_vsize(1, AddressType::P2WPKH, AddressType::P2WPKH);
        assert_eq!(vsize, 10 + 68 + 31); // 109 vB

        // 2 P2TR inputs, 1 P2TR output
        let vsize = CpfpCalculator::estimate_child_vsize(2, AddressType::P2TR, AddressType::P2TR);
        assert_eq!(vsize, 10 + (58 * 2) + 43); // 169 vB
    }

    #[test]
    fn test_cpfp_viability_success() {
        let result = CpfpCalculator::is_cpfp_viable(
            200,    // parent vsize
            1000,   // parent fee
            109,    // child vsize
            20000,  // available value
            50.0,   // target rate
            294,    // dust limit
        );

        assert!(result.is_ok());
        let viability = result.unwrap();
        assert!(viability.is_viable);
        assert!(viability.output_amount > 0);
    }

    #[test]
    fn test_cpfp_viability_insufficient_funds() {
        let result = CpfpCalculator::is_cpfp_viable(
            200,   // parent vsize
            1000,  // parent fee
            109,   // child vsize
            1000,  // only 1000 sats available (not enough)
            50.0,  // target rate
            294,   // dust limit
        );

        assert!(matches!(result, Err(CpfpError::InsufficientFunds { .. })));
    }

    #[test]
    fn test_package_fee_rate() {
        let rate = CpfpCalculator::calculate_package_fee_rate(200, 1000, 100, 4000);
        // (1000 + 4000) / (200 + 100) = 5000 / 300 = 16.67
        assert!((rate - 16.67).abs() < 0.1);
    }

    #[test]
    fn test_fee_bump_percentage() {
        let bump = CpfpCalculator::fee_bump_percentage(10.0, 50.0);
        assert_eq!(bump, 400.0); // 400% increase
    }

    #[test]
    fn test_minimum_bump_rate() {
        assert_eq!(CpfpCalculator::minimum_bump_rate(5.0), 6.0);
        assert_eq!(CpfpCalculator::minimum_bump_rate(0.5), 1.5);
    }

    #[test]
    fn test_dust_limits() {
        assert_eq!(DustLimits::P2WPKH, 294);
        assert_eq!(DustLimits::P2TR, 330);
        assert_eq!(DustLimits::for_type(AddressType::P2WPKH), 294);
    }
}
