//! CPFP transaction builder
//!
//! Builds child transactions that accelerate stuck parent transactions.

use super::calculator::{AddressType, CpfpCalculator, DustLimits};
use super::types::*;

/// CPFP transaction builder
pub struct CpfpBuilder {
    /// Parent transaction info
    parent: Option<StuckTransaction>,
    /// Target fee rate (sat/vB)
    target_fee_rate: f64,
    /// Destination address
    destination: Option<String>,
    /// Destination address type
    destination_type: Option<AddressType>,
    /// Additional UTXOs for fee budget
    additional_utxos: Vec<Utxo>,
    /// Input address type (for size estimation)
    input_type: AddressType,
}

impl Default for CpfpBuilder {
    fn default() -> Self {
        Self::new()
    }
}

impl CpfpBuilder {
    pub fn new() -> Self {
        Self {
            parent: None,
            target_fee_rate: 50.0, // Default to ~next block
            destination: None,
            destination_type: None,
            additional_utxos: Vec::new(),
            input_type: AddressType::P2WPKH,
        }
    }

    /// Set the stuck parent transaction
    pub fn parent(mut self, tx: StuckTransaction) -> Self {
        self.parent = Some(tx);
        self
    }

    /// Set target fee rate in sat/vB
    pub fn target_fee_rate(mut self, rate: f64) -> Self {
        self.target_fee_rate = rate;
        self
    }

    /// Set fee rate level
    pub fn fee_level(mut self, level: FeeRateLevel) -> Self {
        self.target_fee_rate = level.typical_rate();
        self
    }

    /// Set destination address for remaining funds
    pub fn destination(mut self, address: &str) -> Self {
        self.destination = Some(address.to_string());
        self.destination_type = AddressType::from_address(address);
        self
    }

    /// Add additional UTXOs for more fee budget
    pub fn add_utxo(mut self, utxo: Utxo) -> Self {
        self.additional_utxos.push(utxo);
        self
    }

    /// Add multiple additional UTXOs
    pub fn add_utxos(mut self, utxos: Vec<Utxo>) -> Self {
        self.additional_utxos.extend(utxos);
        self
    }

    /// Set input address type for size estimation
    pub fn input_type(mut self, addr_type: AddressType) -> Self {
        self.input_type = addr_type;
        self
    }

    /// Validate the builder configuration
    fn validate(&self) -> Result<(), CpfpError> {
        let parent = self
            .parent
            .as_ref()
            .ok_or_else(|| CpfpError::InvalidParentTx("No parent transaction set".to_string()))?;

        if !parent.can_cpfp() && self.additional_utxos.is_empty() {
            return Err(CpfpError::NoSpendableOutputs);
        }

        if self.destination.is_none() {
            return Err(CpfpError::InvalidAddress(
                "No destination address set".to_string(),
            ));
        }

        if self.target_fee_rate <= 0.0 {
            return Err(CpfpError::FeeCalculationError(
                "Target fee rate must be positive".to_string(),
            ));
        }

        Ok(())
    }

    /// Calculate the CPFP transaction details without building
    pub fn calculate(&self) -> Result<CpfpCalculation, CpfpError> {
        self.validate()?;

        // Safe: validate() ensures these are Some
        let parent = self.parent.as_ref()
            .ok_or_else(|| CpfpError::InvalidParentTx("No parent transaction".to_string()))?;
        let destination = self.destination.as_ref()
            .ok_or_else(|| CpfpError::InvalidAddress("No destination address".to_string()))?;

        // Collect all inputs
        let mut all_inputs: Vec<&Utxo> = parent.spendable_outputs.iter().collect();
        all_inputs.extend(self.additional_utxos.iter());

        if all_inputs.is_empty() {
            return Err(CpfpError::NoSpendableOutputs);
        }

        // Calculate total input value
        let total_input_value: u64 = all_inputs.iter().map(|u| u.amount).sum();

        // Estimate child transaction size
        let output_type = self.destination_type.unwrap_or(AddressType::P2WPKH);
        let child_vsize =
            CpfpCalculator::estimate_child_vsize(all_inputs.len(), self.input_type, output_type);

        // Calculate required child fee
        let required_child_fee = CpfpCalculator::calculate_required_child_fee(
            parent.vsize,
            parent.fee,
            child_vsize,
            self.target_fee_rate,
        );

        // Check if we have enough funds
        let dust_limit = DustLimits::for_type(output_type);
        let min_required = required_child_fee + dust_limit;

        if total_input_value < min_required {
            return Err(CpfpError::InsufficientFunds {
                required: min_required,
                available: total_input_value,
            });
        }

        let output_amount = total_input_value - required_child_fee;

        // Calculate effective rates
        let child_fee_rate = required_child_fee as f64 / child_vsize as f64;
        let package_vsize = parent.vsize + child_vsize;
        let package_fee = parent.fee + required_child_fee;
        let package_fee_rate = package_fee as f64 / package_vsize as f64;

        Ok(CpfpCalculation {
            parent_txid: parent.txid.clone(),
            parent_vsize: parent.vsize,
            parent_fee: parent.fee,
            parent_fee_rate: parent.fee_rate,
            child_vsize,
            child_fee: required_child_fee,
            child_fee_rate,
            package_vsize,
            package_fee,
            package_fee_rate,
            input_count: all_inputs.len(),
            total_input_value,
            output_amount,
            destination: destination.clone(),
            target_fee_rate: self.target_fee_rate,
        })
    }

    /// Build the CPFP transaction
    ///
    /// Note: This returns the transaction structure. Actual signing
    /// requires the private keys and would be done by the wallet.
    pub fn build(&self) -> Result<CpfpTransactionData, CpfpError> {
        let calc = self.calculate()?;
        // Safe: calculate() calls validate() which ensures parent is Some
        let parent = self.parent.as_ref()
            .ok_or_else(|| CpfpError::InvalidParentTx("No parent transaction".to_string()))?;

        // Collect inputs
        let mut inputs: Vec<CpfpInput> = Vec::new();

        for utxo in &parent.spendable_outputs {
            inputs.push(CpfpInput {
                txid: utxo.txid.clone(),
                vout: utxo.vout,
                amount: utxo.amount,
                script_pubkey: utxo.script_pubkey.clone(),
                sequence: 0xFFFFFFFD, // Enable RBF
            });
        }

        for utxo in &self.additional_utxos {
            inputs.push(CpfpInput {
                txid: utxo.txid.clone(),
                vout: utxo.vout,
                amount: utxo.amount,
                script_pubkey: utxo.script_pubkey.clone(),
                sequence: 0xFFFFFFFD,
            });
        }

        // Create output
        let output = CpfpOutput {
            amount: calc.output_amount,
            address: calc.destination.clone(),
            script_pubkey: String::new(), // Would be derived from address
        };

        Ok(CpfpTransactionData {
            version: 2,
            inputs,
            outputs: vec![output],
            locktime: 0,
            calculation: calc,
        })
    }
}

/// Calculated CPFP transaction details
#[derive(Debug, Clone)]
pub struct CpfpCalculation {
    pub parent_txid: String,
    pub parent_vsize: u64,
    pub parent_fee: u64,
    pub parent_fee_rate: f64,
    pub child_vsize: u64,
    pub child_fee: u64,
    pub child_fee_rate: f64,
    pub package_vsize: u64,
    pub package_fee: u64,
    pub package_fee_rate: f64,
    pub input_count: usize,
    pub total_input_value: u64,
    pub output_amount: u64,
    pub destination: String,
    pub target_fee_rate: f64,
}

impl CpfpCalculation {
    /// Check if the calculation meets the target fee rate
    pub fn meets_target(&self) -> bool {
        self.package_fee_rate >= self.target_fee_rate
    }

    /// Get the fee bump factor
    pub fn fee_bump_factor(&self) -> f64 {
        if self.parent_fee_rate > 0.0 {
            self.package_fee_rate / self.parent_fee_rate
        } else {
            f64::INFINITY
        }
    }

    /// Get savings compared to creating a new transaction
    pub fn savings_vs_new_tx(&self, new_tx_vsize: u64) -> i64 {
        let new_tx_fee = (self.target_fee_rate * new_tx_vsize as f64).ceil() as i64;
        new_tx_fee - self.child_fee as i64
    }
}

/// CPFP transaction input
#[derive(Debug, Clone)]
pub struct CpfpInput {
    pub txid: String,
    pub vout: u32,
    pub amount: u64,
    pub script_pubkey: String,
    pub sequence: u32,
}

/// CPFP transaction output
#[derive(Debug, Clone)]
pub struct CpfpOutput {
    pub amount: u64,
    pub address: String,
    pub script_pubkey: String,
}

/// Complete CPFP transaction data
#[derive(Debug, Clone)]
pub struct CpfpTransactionData {
    pub version: u32,
    pub inputs: Vec<CpfpInput>,
    pub outputs: Vec<CpfpOutput>,
    pub locktime: u32,
    pub calculation: CpfpCalculation,
}

impl CpfpTransactionData {
    /// Get total input value
    pub fn total_input_value(&self) -> u64 {
        self.inputs.iter().map(|i| i.amount).sum()
    }

    /// Get total output value
    pub fn total_output_value(&self) -> u64 {
        self.outputs.iter().map(|o| o.amount).sum()
    }

    /// Get the fee (difference between inputs and outputs)
    pub fn fee(&self) -> u64 {
        self.total_input_value().saturating_sub(self.total_output_value())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_parent() -> StuckTransaction {
        let outputs = vec![
            Utxo::new("parent123", 0, 50000, "00140000000000000000000000000000000000000001"),
        ];

        StuckTransaction::new("parent123", "0100000001...", 200, 1000)
            .with_spendable_outputs(outputs)
    }

    #[test]
    fn test_builder_basic() {
        let parent = create_test_parent();

        let result = CpfpBuilder::new()
            .parent(parent)
            .target_fee_rate(50.0)
            .destination("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")
            .calculate();

        assert!(result.is_ok());
        let calc = result.unwrap();
        assert_eq!(calc.parent_txid, "parent123");
        assert!(calc.meets_target());
    }

    #[test]
    fn test_builder_with_fee_level() {
        let parent = create_test_parent();

        let result = CpfpBuilder::new()
            .parent(parent)
            .fee_level(FeeRateLevel::High)
            .destination("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")
            .calculate();

        assert!(result.is_ok());
        let calc = result.unwrap();
        assert_eq!(calc.target_fee_rate, 50.0);
    }

    #[test]
    fn test_builder_with_additional_utxos() {
        let parent = create_test_parent();

        let additional = Utxo::new("other456", 0, 100000, "0014...");

        let result = CpfpBuilder::new()
            .parent(parent)
            .target_fee_rate(100.0)
            .destination("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")
            .add_utxo(additional)
            .calculate();

        assert!(result.is_ok());
        let calc = result.unwrap();
        assert_eq!(calc.input_count, 2);
        assert_eq!(calc.total_input_value, 150000);
    }

    #[test]
    fn test_builder_no_parent() {
        let result = CpfpBuilder::new()
            .target_fee_rate(50.0)
            .destination("bc1q...")
            .calculate();

        assert!(matches!(result, Err(CpfpError::InvalidParentTx(_))));
    }

    #[test]
    fn test_builder_no_destination() {
        let parent = create_test_parent();

        let result = CpfpBuilder::new().parent(parent).target_fee_rate(50.0).calculate();

        assert!(matches!(result, Err(CpfpError::InvalidAddress(_))));
    }

    #[test]
    fn test_builder_no_spendable_outputs() {
        let parent = StuckTransaction::new("parent123", "raw", 200, 1000);

        let result = CpfpBuilder::new()
            .parent(parent)
            .target_fee_rate(50.0)
            .destination("bc1q...")
            .calculate();

        assert!(matches!(result, Err(CpfpError::NoSpendableOutputs)));
    }

    #[test]
    fn test_builder_insufficient_funds() {
        let outputs = vec![Utxo::new("parent123", 0, 1000, "script")];

        let parent = StuckTransaction::new("parent123", "raw", 200, 500)
            .with_spendable_outputs(outputs);

        let result = CpfpBuilder::new()
            .parent(parent)
            .target_fee_rate(100.0) // Very high rate
            .destination("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")
            .calculate();

        assert!(matches!(result, Err(CpfpError::InsufficientFunds { .. })));
    }

    #[test]
    fn test_build_transaction() {
        let parent = create_test_parent();

        let result = CpfpBuilder::new()
            .parent(parent)
            .target_fee_rate(50.0)
            .destination("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")
            .build();

        assert!(result.is_ok());
        let tx = result.unwrap();
        assert_eq!(tx.version, 2);
        assert_eq!(tx.inputs.len(), 1);
        assert_eq!(tx.outputs.len(), 1);
        assert!(tx.outputs[0].amount > 0);
    }

    #[test]
    fn test_calculation_methods() {
        let calc = CpfpCalculation {
            parent_txid: "test".to_string(),
            parent_vsize: 200,
            parent_fee: 1000,
            parent_fee_rate: 5.0,
            child_vsize: 109,
            child_fee: 14450,
            child_fee_rate: 132.6,
            package_vsize: 309,
            package_fee: 15450,
            package_fee_rate: 50.0,
            input_count: 1,
            total_input_value: 50000,
            output_amount: 35550,
            destination: "bc1q...".to_string(),
            target_fee_rate: 50.0,
        };

        assert!(calc.meets_target());
        assert_eq!(calc.fee_bump_factor(), 10.0); // 50 / 5
    }

    #[test]
    fn test_transaction_data() {
        let tx = CpfpTransactionData {
            version: 2,
            inputs: vec![CpfpInput {
                txid: "test".to_string(),
                vout: 0,
                amount: 50000,
                script_pubkey: "00...".to_string(),
                sequence: 0xFFFFFFFD,
            }],
            outputs: vec![CpfpOutput {
                amount: 35000,
                address: "bc1q...".to_string(),
                script_pubkey: "00...".to_string(),
            }],
            locktime: 0,
            calculation: CpfpCalculation {
                parent_txid: "".to_string(),
                parent_vsize: 0,
                parent_fee: 0,
                parent_fee_rate: 0.0,
                child_vsize: 0,
                child_fee: 0,
                child_fee_rate: 0.0,
                package_vsize: 0,
                package_fee: 0,
                package_fee_rate: 0.0,
                input_count: 0,
                total_input_value: 0,
                output_amount: 0,
                destination: "".to_string(),
                target_fee_rate: 0.0,
            },
        };

        assert_eq!(tx.total_input_value(), 50000);
        assert_eq!(tx.total_output_value(), 35000);
        assert_eq!(tx.fee(), 15000);
    }
}
