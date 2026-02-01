//! CPFP integration tests

#[cfg(test)]
mod integration_tests {
    use crate::cpfp::*;

    #[test]
    fn test_full_cpfp_workflow() {
        // 1. Create a stuck transaction
        let stuck_outputs = vec![
            Utxo::new(
                "abc123def456abc123def456abc123def456abc123def456abc123def456abc123",
                0,
                100000,
                "0014abcdef1234567890abcdef1234567890abcdef12",
            )
            .with_address("bc1q...")
            .with_confirmations(0),
        ];

        let stuck_tx = StuckTransaction::new(
            "abc123def456abc123def456abc123def456abc123def456abc123def456abc123",
            "01000000...",
            250,  // 250 vB
            1250, // 5 sat/vB - very low fee
        )
        .with_spendable_outputs(stuck_outputs)
        .with_first_seen(1700000000);

        assert!(stuck_tx.can_cpfp());
        assert_eq!(stuck_tx.fee_rate, 5.0);
        assert!(stuck_tx.is_incoming == false);

        // 2. Calculate CPFP transaction
        let result = CpfpBuilder::new()
            .parent(stuck_tx)
            .fee_level(FeeRateLevel::High) // 50 sat/vB
            .destination("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")
            .input_type(AddressType::P2WPKH)
            .calculate();

        assert!(result.is_ok());
        let calc = result.unwrap();

        // Verify calculation
        assert!(calc.package_fee_rate >= 50.0);
        assert!(calc.child_fee > 0);
        assert!(calc.output_amount > 0);
        assert!(calc.meets_target());
    }

    #[test]
    fn test_cpfp_with_multiple_outputs() {
        let outputs = vec![
            Utxo::new("txid1", 0, 50000, "script1"),
            Utxo::new("txid1", 1, 30000, "script2"),
            Utxo::new("txid1", 2, 20000, "script3"),
        ];

        let stuck = StuckTransaction::new("txid1", "raw", 300, 600)
            .with_spendable_outputs(outputs);

        assert_eq!(stuck.spendable_value(), 100000);

        let result = CpfpBuilder::new()
            .parent(stuck)
            .target_fee_rate(30.0)
            .destination("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")
            .calculate();

        assert!(result.is_ok());
        let calc = result.unwrap();
        assert_eq!(calc.input_count, 3);
    }

    #[test]
    fn test_cpfp_with_additional_funding() {
        // Parent with small output
        let parent_output = vec![Utxo::new("parent", 0, 5000, "script")];
        let stuck = StuckTransaction::new("parent", "raw", 200, 1000)
            .with_spendable_outputs(parent_output);

        // Need more funds - add additional UTXO
        let additional = Utxo::new("funding", 0, 100000, "script2");

        let result = CpfpBuilder::new()
            .parent(stuck)
            .target_fee_rate(100.0) // High target
            .destination("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")
            .add_utxo(additional)
            .calculate();

        assert!(result.is_ok());
        let calc = result.unwrap();
        assert_eq!(calc.input_count, 2);
        assert_eq!(calc.total_input_value, 105000);
    }

    #[test]
    fn test_fee_rate_levels() {
        let outputs = vec![Utxo::new("tx", 0, 500000, "script")];
        let stuck = StuckTransaction::new("tx", "raw", 200, 400)
            .with_spendable_outputs(outputs);

        // Test each fee level
        for level in [
            FeeRateLevel::High,
            FeeRateLevel::Medium,
            FeeRateLevel::Low,
            FeeRateLevel::Economy,
        ] {
            let result = CpfpBuilder::new()
                .parent(stuck.clone())
                .fee_level(level)
                .destination("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")
                .calculate();

            assert!(result.is_ok());
            let calc = result.unwrap();
            assert!(calc.package_fee_rate >= level.typical_rate() - 0.1);
        }
    }

    #[test]
    fn test_address_type_detection() {
        // All valid Bitcoin address types
        let addresses = vec![
            ("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa", AddressType::P2PKH),
            ("3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy", AddressType::P2SH),
            (
                "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
                AddressType::P2WPKH,
            ),
            (
                "bc1p5d7rjq7g6rdk2yhzks9smlaqtedr4dekq08ge8ztwac72sfr9rusxg3297",
                AddressType::P2TR,
            ),
        ];

        for (addr, expected_type) in addresses {
            let detected = AddressType::from_address(addr);
            assert_eq!(detected, Some(expected_type), "Failed for {}", addr);
        }
    }

    #[test]
    fn test_dust_limit_enforcement() {
        // Very small output that would be below dust
        let outputs = vec![Utxo::new("tx", 0, 400, "script")]; // Only 400 sats
        let stuck = StuckTransaction::new("tx", "raw", 100, 50)
            .with_spendable_outputs(outputs);

        let result = CpfpBuilder::new()
            .parent(stuck)
            .target_fee_rate(1.0) // Even at 1 sat/vB
            .destination("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")
            .calculate();

        // Should fail because output would be below dust after fee
        assert!(matches!(result, Err(CpfpError::InsufficientFunds { .. })));
    }

    #[test]
    fn test_calculator_edge_cases() {
        // Parent with 0 fee
        let child_fee = CpfpCalculator::calculate_required_child_fee(100, 0, 100, 10.0);
        assert_eq!(child_fee, 2000); // Full package fee

        // Very large parent
        let child_fee = CpfpCalculator::calculate_required_child_fee(10000, 50000, 100, 10.0);
        // Package needs 101000, parent has 50000, child needs 51000
        assert_eq!(child_fee, 51000);
    }

    #[test]
    fn test_transaction_size_estimation() {
        // Single input, single output (common case)
        let size = CpfpCalculator::estimate_child_vsize(1, AddressType::P2WPKH, AddressType::P2WPKH);
        assert!(size > 100 && size < 150);

        // Multiple inputs
        let size = CpfpCalculator::estimate_child_vsize(5, AddressType::P2WPKH, AddressType::P2WPKH);
        assert!(size > 300);

        // Taproot (smaller)
        let size = CpfpCalculator::estimate_child_vsize(1, AddressType::P2TR, AddressType::P2TR);
        assert!(size < 120);
    }

    #[test]
    fn test_build_complete_transaction() {
        let outputs = vec![Utxo::new("parent", 0, 100000, "0014abc...")];
        let stuck = StuckTransaction::new("parent", "raw", 200, 1000)
            .with_spendable_outputs(outputs);

        let tx_data = CpfpBuilder::new()
            .parent(stuck)
            .target_fee_rate(50.0)
            .destination("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")
            .build()
            .unwrap();

        // Verify transaction structure
        assert_eq!(tx_data.version, 2);
        assert_eq!(tx_data.inputs.len(), 1);
        assert_eq!(tx_data.outputs.len(), 1);
        assert_eq!(tx_data.locktime, 0);

        // Verify input
        assert_eq!(tx_data.inputs[0].txid, "parent");
        assert_eq!(tx_data.inputs[0].vout, 0);
        assert_eq!(tx_data.inputs[0].amount, 100000);
        assert_eq!(tx_data.inputs[0].sequence, 0xFFFFFFFD); // RBF enabled

        // Verify output
        assert!(tx_data.outputs[0].amount > 0);
        assert!(tx_data.outputs[0].amount < 100000); // Less than input (fee taken)

        // Verify fee
        let fee = tx_data.fee();
        assert!(fee > 0);
        assert_eq!(fee, 100000 - tx_data.outputs[0].amount);
    }

    #[test]
    fn test_fee_bump_percentage() {
        let bump = CpfpCalculator::fee_bump_percentage(5.0, 50.0);
        assert_eq!(bump, 900.0); // 900% increase

        let bump = CpfpCalculator::fee_bump_percentage(25.0, 50.0);
        assert_eq!(bump, 100.0); // 100% increase (double)
    }

    #[test]
    fn test_outpoint_format() {
        let utxo = Utxo::new("abc123", 2, 10000, "script");
        assert_eq!(utxo.outpoint(), "abc123:2");
    }

    #[test]
    fn test_cpfp_error_types() {
        let errors = vec![
            CpfpError::NoSpendableOutputs,
            CpfpError::InsufficientFunds {
                required: 10000,
                available: 5000,
            },
            CpfpError::InvalidParentTx("test".to_string()),
            CpfpError::InvalidAddress("bad".to_string()),
            CpfpError::FeeCalculationError("math".to_string()),
            CpfpError::TransactionBuildError("build".to_string()),
            CpfpError::AlreadyConfirmed,
        ];

        for err in errors {
            let msg = err.to_string();
            assert!(!msg.is_empty());
        }
    }
}
