//! CPFP types and data structures

use serde::{Deserialize, Serialize};

/// A Bitcoin UTXO (Unspent Transaction Output)
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Utxo {
    /// Transaction ID
    pub txid: String,
    /// Output index
    pub vout: u32,
    /// Amount in satoshis
    pub amount: u64,
    /// ScriptPubKey (hex)
    pub script_pubkey: String,
    /// Address (optional)
    pub address: Option<String>,
    /// Number of confirmations
    pub confirmations: u32,
}

impl Utxo {
    pub fn new(txid: &str, vout: u32, amount: u64, script_pubkey: &str) -> Self {
        Self {
            txid: txid.to_string(),
            vout,
            amount,
            script_pubkey: script_pubkey.to_string(),
            address: None,
            confirmations: 0,
        }
    }

    pub fn with_address(mut self, address: &str) -> Self {
        self.address = Some(address.to_string());
        self
    }

    pub fn with_confirmations(mut self, confirmations: u32) -> Self {
        self.confirmations = confirmations;
        self
    }

    /// Check if this UTXO is unconfirmed
    pub fn is_unconfirmed(&self) -> bool {
        self.confirmations == 0
    }

    /// Get the outpoint string (txid:vout)
    pub fn outpoint(&self) -> String {
        format!("{}:{}", self.txid, self.vout)
    }
}

/// Information about a stuck (unconfirmed) transaction
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StuckTransaction {
    /// Transaction ID
    pub txid: String,
    /// Raw transaction hex
    pub raw_tx: String,
    /// Transaction size in virtual bytes (vbytes)
    pub vsize: u64,
    /// Current fee in satoshis
    pub fee: u64,
    /// Current fee rate (sat/vB)
    pub fee_rate: f64,
    /// Outputs from this transaction that we can spend
    pub spendable_outputs: Vec<Utxo>,
    /// Time first seen (Unix timestamp)
    pub first_seen: u64,
    /// Whether this is an incoming or outgoing transaction
    pub is_incoming: bool,
}

impl StuckTransaction {
    pub fn new(txid: &str, raw_tx: &str, vsize: u64, fee: u64) -> Self {
        let fee_rate = if vsize > 0 {
            fee as f64 / vsize as f64
        } else {
            0.0
        };

        Self {
            txid: txid.to_string(),
            raw_tx: raw_tx.to_string(),
            vsize,
            fee,
            fee_rate,
            spendable_outputs: Vec::new(),
            first_seen: 0,
            is_incoming: false,
        }
    }

    pub fn with_spendable_outputs(mut self, outputs: Vec<Utxo>) -> Self {
        self.spendable_outputs = outputs;
        self
    }

    pub fn with_first_seen(mut self, timestamp: u64) -> Self {
        self.first_seen = timestamp;
        self
    }

    /// Get total value of spendable outputs
    pub fn spendable_value(&self) -> u64 {
        self.spendable_outputs.iter().map(|u| u.amount).sum()
    }

    /// Check if we can create a CPFP transaction
    pub fn can_cpfp(&self) -> bool {
        !self.spendable_outputs.is_empty()
    }
}

/// CPFP transaction request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CpfpRequest {
    /// The stuck transaction to accelerate
    pub parent_txid: String,
    /// UTXOs from the parent transaction to spend
    pub parent_outputs: Vec<Utxo>,
    /// Target fee rate for the package (sat/vB)
    pub target_fee_rate: f64,
    /// Destination address for remaining funds
    pub destination_address: String,
    /// Optional: additional UTXOs to add more fee budget
    pub additional_utxos: Vec<Utxo>,
}

impl CpfpRequest {
    pub fn new(parent_txid: &str, target_fee_rate: f64, destination: &str) -> Self {
        Self {
            parent_txid: parent_txid.to_string(),
            parent_outputs: Vec::new(),
            target_fee_rate,
            destination_address: destination.to_string(),
            additional_utxos: Vec::new(),
        }
    }

    pub fn with_parent_outputs(mut self, outputs: Vec<Utxo>) -> Self {
        self.parent_outputs = outputs;
        self
    }

    pub fn with_additional_utxos(mut self, utxos: Vec<Utxo>) -> Self {
        self.additional_utxos = utxos;
        self
    }

    /// Get total input value
    pub fn total_input_value(&self) -> u64 {
        let parent_value: u64 = self.parent_outputs.iter().map(|u| u.amount).sum();
        let additional_value: u64 = self.additional_utxos.iter().map(|u| u.amount).sum();
        parent_value + additional_value
    }

    /// Get number of inputs
    pub fn input_count(&self) -> usize {
        self.parent_outputs.len() + self.additional_utxos.len()
    }
}

/// CPFP transaction result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CpfpTransaction {
    /// Child transaction ID
    pub txid: String,
    /// Raw transaction hex
    pub raw_tx: String,
    /// Child transaction size (vbytes)
    pub child_vsize: u64,
    /// Child transaction fee
    pub child_fee: u64,
    /// Child fee rate
    pub child_fee_rate: f64,
    /// Package (parent + child) total vsize
    pub package_vsize: u64,
    /// Package total fee
    pub package_fee: u64,
    /// Effective package fee rate
    pub package_fee_rate: f64,
    /// Amount sent to destination
    pub output_amount: u64,
}

impl CpfpTransaction {
    /// Calculate the effective fee rate for the package
    pub fn effective_fee_rate(&self) -> f64 {
        if self.package_vsize > 0 {
            self.package_fee as f64 / self.package_vsize as f64
        } else {
            0.0
        }
    }

    /// Check if the package meets the target fee rate
    pub fn meets_target(&self, target_rate: f64) -> bool {
        self.effective_fee_rate() >= target_rate
    }
}

/// Fee rate recommendation levels
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum FeeRateLevel {
    /// Next block (~10 min)
    High,
    /// ~30 minutes
    Medium,
    /// ~1 hour
    Low,
    /// Economy (no time guarantee)
    Economy,
    /// Custom rate
    Custom,
}

impl FeeRateLevel {
    /// Get typical fee rate for this level (sat/vB)
    /// These are example values; real values should come from a fee estimator
    pub fn typical_rate(&self) -> f64 {
        match self {
            FeeRateLevel::High => 50.0,
            FeeRateLevel::Medium => 25.0,
            FeeRateLevel::Low => 10.0,
            FeeRateLevel::Economy => 5.0,
            FeeRateLevel::Custom => 1.0,
        }
    }

    /// Get estimated confirmation time in minutes
    pub fn estimated_time(&self) -> u32 {
        match self {
            FeeRateLevel::High => 10,
            FeeRateLevel::Medium => 30,
            FeeRateLevel::Low => 60,
            FeeRateLevel::Economy => 360,
            FeeRateLevel::Custom => 0,
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            FeeRateLevel::High => "High Priority",
            FeeRateLevel::Medium => "Medium Priority",
            FeeRateLevel::Low => "Low Priority",
            FeeRateLevel::Economy => "Economy",
            FeeRateLevel::Custom => "Custom",
        }
    }
}

/// Error types for CPFP operations
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum CpfpError {
    /// No spendable outputs in parent transaction
    NoSpendableOutputs,
    /// Insufficient funds to pay required fee
    InsufficientFunds { required: u64, available: u64 },
    /// Invalid parent transaction
    InvalidParentTx(String),
    /// Invalid address
    InvalidAddress(String),
    /// Fee calculation error
    FeeCalculationError(String),
    /// Transaction building error
    TransactionBuildError(String),
    /// Parent transaction already confirmed
    AlreadyConfirmed,
}

impl std::fmt::Display for CpfpError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CpfpError::NoSpendableOutputs => {
                write!(f, "No spendable outputs in parent transaction")
            }
            CpfpError::InsufficientFunds { required, available } => {
                write!(
                    f,
                    "Insufficient funds: need {} sats, have {} sats",
                    required, available
                )
            }
            CpfpError::InvalidParentTx(msg) => write!(f, "Invalid parent transaction: {}", msg),
            CpfpError::InvalidAddress(addr) => write!(f, "Invalid address: {}", addr),
            CpfpError::FeeCalculationError(msg) => write!(f, "Fee calculation error: {}", msg),
            CpfpError::TransactionBuildError(msg) => {
                write!(f, "Transaction build error: {}", msg)
            }
            CpfpError::AlreadyConfirmed => write!(f, "Parent transaction is already confirmed"),
        }
    }
}

impl std::error::Error for CpfpError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_utxo_creation() {
        let utxo = Utxo::new(
            "abc123",
            0,
            100000,
            "76a914..."
        )
        .with_address("1A1zP1...")
        .with_confirmations(0);

        assert_eq!(utxo.txid, "abc123");
        assert_eq!(utxo.vout, 0);
        assert_eq!(utxo.amount, 100000);
        assert!(utxo.is_unconfirmed());
        assert_eq!(utxo.outpoint(), "abc123:0");
    }

    #[test]
    fn test_stuck_transaction() {
        let stuck = StuckTransaction::new(
            "txid123",
            "0100000001...",
            200,
            1000
        );

        assert_eq!(stuck.txid, "txid123");
        assert_eq!(stuck.vsize, 200);
        assert_eq!(stuck.fee, 1000);
        assert_eq!(stuck.fee_rate, 5.0); // 1000 / 200
        assert!(!stuck.can_cpfp()); // No spendable outputs yet
    }

    #[test]
    fn test_stuck_transaction_with_outputs() {
        let outputs = vec![
            Utxo::new("txid123", 0, 50000, "script1"),
            Utxo::new("txid123", 1, 30000, "script2"),
        ];

        let stuck = StuckTransaction::new("txid123", "raw", 200, 1000)
            .with_spendable_outputs(outputs);

        assert!(stuck.can_cpfp());
        assert_eq!(stuck.spendable_value(), 80000);
    }

    #[test]
    fn test_cpfp_request() {
        let request = CpfpRequest::new("parent123", 50.0, "bc1q...")
            .with_parent_outputs(vec![
                Utxo::new("parent123", 0, 100000, "script"),
            ])
            .with_additional_utxos(vec![
                Utxo::new("other456", 0, 50000, "script2"),
            ]);

        assert_eq!(request.total_input_value(), 150000);
        assert_eq!(request.input_count(), 2);
    }

    #[test]
    fn test_cpfp_transaction() {
        let cpfp = CpfpTransaction {
            txid: "child123".to_string(),
            raw_tx: "0100...".to_string(),
            child_vsize: 150,
            child_fee: 15000,
            child_fee_rate: 100.0,
            package_vsize: 350,
            package_fee: 16000,
            package_fee_rate: 45.7,
            output_amount: 84000,
        };

        assert!(cpfp.meets_target(40.0));
        assert!(!cpfp.meets_target(50.0));
    }

    #[test]
    fn test_fee_rate_levels() {
        assert_eq!(FeeRateLevel::High.typical_rate(), 50.0);
        assert_eq!(FeeRateLevel::Medium.estimated_time(), 30);
        assert_eq!(FeeRateLevel::Economy.name(), "Economy");
    }

    #[test]
    fn test_cpfp_error_display() {
        let err = CpfpError::InsufficientFunds {
            required: 10000,
            available: 5000,
        };
        assert!(err.to_string().contains("10000"));
        assert!(err.to_string().contains("5000"));
    }
}
