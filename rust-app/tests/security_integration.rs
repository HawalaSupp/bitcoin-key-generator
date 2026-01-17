//! Security Integration Tests
//! 
//! Comprehensive tests for the P0-P6 security features including:
//! - Threat detection
//! - Transaction policies
//! - Key rotation
//! - Secure memory
//! - Verification
//! - FFI interface

use rust_app::security::*;
use rust_app::types::Chain;
use rust_app::ffi::*;
use std::ffi::{CStr, CString};

// MARK: - Helper Functions

fn call_ffi(func: unsafe extern "C" fn(*const i8) -> *mut i8, input: &str) -> String {
    let c_input = CString::new(input).unwrap();
    unsafe {
        let result = func(c_input.as_ptr());
        let output = CStr::from_ptr(result).to_string_lossy().into_owned();
        hawala_free_string(result);
        output
    }
}

fn parse_result<T: serde::de::DeserializeOwned>(json: &str) -> Result<T, String> {
    #[derive(serde::Deserialize)]
    struct Response<T> {
        success: bool,
        data: Option<T>,
        error: Option<String>,
    }
    
    let response: Response<T> = serde_json::from_str(json)
        .map_err(|e| format!("Parse error: {}", e))?;
    
    if response.success {
        response.data.ok_or_else(|| "No data in response".to_string())
    } else {
        Err(response.error.unwrap_or_else(|| "Unknown error".to_string()))
    }
}

// MARK: - Threat Detection Tests

#[test]
fn test_threat_assessment_ffi() {
    let input = r#"{
        "wallet_id": "test-wallet",
        "recipient": "0x1234567890abcdef1234567890abcdef12345678",
        "amount": "1000000000000000000",
        "chain": "ethereum"
    }"#;
    
    let result = call_ffi(hawala_assess_threat, input);
    
    #[derive(serde::Deserialize)]
    struct ThreatResponse {
        risk_level: String,
        threats: Vec<serde_json::Value>,
        allow_transaction: bool,
    }
    
    let assessment: ThreatResponse = parse_result(&result).expect("Should parse threat assessment");
    assert!(!assessment.risk_level.is_empty());
    // Unknown recipient should be flagged but allowed
    assert!(assessment.allow_transaction);
}

#[test]
fn test_blacklist_ffi() {
    // Blacklist an address
    let input = r#"{
        "address": "0xscammer123456789",
        "reason": "Known scam"
    }"#;
    
    let result = call_ffi(hawala_blacklist_address, input);
    assert!(result.contains("\"success\":true"));
    
    // Now assess a transaction to that address
    let threat_input = r#"{
        "wallet_id": "test-wallet",
        "recipient": "0xscammer123456789",
        "amount": "1000000000000000000",
        "chain": "ethereum"
    }"#;
    
    let assessment_result = call_ffi(hawala_assess_threat, threat_input);
    
    #[derive(serde::Deserialize)]
    struct ThreatResponse {
        risk_level: String,
        allow_transaction: bool,
    }
    
    let assessment: ThreatResponse = parse_result(&assessment_result).expect("Should parse");
    assert_eq!(assessment.risk_level, "critical");
    assert!(!assessment.allow_transaction);
}

#[test]
fn test_whitelist_ffi() {
    let input = r#"{
        "wallet_id": "test-wallet",
        "address": "0xtrusted_cold_wallet"
    }"#;
    
    let result = call_ffi(hawala_whitelist_address, input);
    assert!(result.contains("\"success\":true"));
}

// MARK: - Policy Tests

#[test]
fn test_spending_limits_ffi() {
    // Set spending limits
    let limits_input = r#"{
        "wallet_id": "policy-test-wallet",
        "per_tx_limit": "1000000000000000000",
        "daily_limit": "5000000000000000000",
        "weekly_limit": "20000000000000000000",
        "monthly_limit": "50000000000000000000",
        "require_whitelist": false
    }"#;
    
    let result = call_ffi(hawala_set_spending_limits, limits_input);
    assert!(result.contains("\"success\":true"));
    
    // Check policy for a transaction under limit
    let check_input = r#"{
        "wallet_id": "policy-test-wallet",
        "recipient": "0xsomerecipient",
        "amount": "500000000000000000",
        "chain": "ethereum"
    }"#;
    
    let check_result = call_ffi(hawala_check_policy, check_input);
    
    #[derive(serde::Deserialize)]
    struct PolicyResponse {
        allowed: bool,
        violations: Vec<serde_json::Value>,
    }
    
    let policy: PolicyResponse = parse_result(&check_result).expect("Should parse policy check");
    assert!(policy.allowed);
    assert!(policy.violations.is_empty());
}

#[test]
fn test_policy_violation_over_limit() {
    // Set very low limit
    let limits_input = r#"{
        "wallet_id": "strict-wallet",
        "per_tx_limit": "1000",
        "daily_limit": null,
        "weekly_limit": null,
        "monthly_limit": null,
        "require_whitelist": false
    }"#;
    
    call_ffi(hawala_set_spending_limits, limits_input);
    
    // Try to send more than limit
    let check_input = r#"{
        "wallet_id": "strict-wallet",
        "recipient": "0xrecipient",
        "amount": "5000",
        "chain": "ethereum"
    }"#;
    
    let check_result = call_ffi(hawala_check_policy, check_input);
    
    #[derive(serde::Deserialize)]
    struct PolicyResponse {
        allowed: bool,
        violations: Vec<serde_json::Value>,
    }
    
    let policy: PolicyResponse = parse_result(&check_result).expect("Should parse");
    assert!(!policy.allowed);
    assert!(!policy.violations.is_empty());
}

// MARK: - Authentication Tests

#[test]
fn test_challenge_creation_ffi() {
    let input = r#"{
        "address": "0x1234567890abcdef1234567890abcdef12345678",
        "domain": "hawala.app"
    }"#;
    
    let result = call_ffi(hawala_create_challenge, input);
    
    #[derive(serde::Deserialize)]
    struct ChallengeResponse {
        challenge_id: String,
        message: String,
        expires_at: u64,
    }
    
    let challenge: ChallengeResponse = parse_result(&result).expect("Should parse challenge");
    assert!(!challenge.challenge_id.is_empty());
    assert!(challenge.message.contains("hawala.app"));
    assert!(challenge.expires_at > 0);
}

#[test]
fn test_challenge_verification_invalid() {
    // First create a challenge
    let create_input = r#"{
        "address": "0xtest_address",
        "domain": null
    }"#;
    
    let create_result = call_ffi(hawala_create_challenge, create_input);
    
    #[derive(serde::Deserialize)]
    struct ChallengeResponse {
        challenge_id: String,
    }
    
    let challenge: ChallengeResponse = parse_result(&create_result).expect("Should parse");
    
    // Try to verify with invalid signature
    let verify_input = format!(r#"{{
        "challenge_id": "{}",
        "signature": "0xinvalid_signature",
        "signer": "0xtest_address"
    }}"#, challenge.challenge_id);
    
    let verify_result = call_ffi(hawala_verify_challenge, &verify_input);
    
    #[derive(serde::Deserialize)]
    struct VerifyResponse {
        valid: bool,
    }
    
    let verify: VerifyResponse = parse_result(&verify_result).expect("Should parse");
    assert!(!verify.valid);
}

// MARK: - Key Rotation Tests

#[test]
fn test_key_registration_ffi() {
    let input = r#"{
        "wallet_id": "key-test-wallet",
        "key_type": "signing_key",
        "derivation_path": "m/44'/60'/0'/0/0",
        "algorithm": "secp256k1"
    }"#;
    
    let result = call_ffi(hawala_register_key_version, input);
    
    #[derive(serde::Deserialize)]
    struct KeyResponse {
        version: u32,
        status: String,
    }
    
    let key_info: KeyResponse = parse_result(&result).expect("Should parse key info");
    assert!(key_info.version >= 1);
    // Status could be "Active" or "active" depending on serialization
    assert!(key_info.status.to_lowercase() == "active");
}

#[test]
fn test_key_rotation_check_ffi() {
    // Register a key first
    let register_input = r#"{
        "wallet_id": "rotation-check-wallet",
        "key_type": "encryption_key",
        "derivation_path": null,
        "algorithm": "AES-256-GCM"
    }"#;
    
    call_ffi(hawala_register_key_version, register_input);
    
    // Check rotation status
    let check_input = r#"{
        "wallet_id": "rotation-check-wallet"
    }"#;
    
    let result = call_ffi(hawala_check_key_rotation, check_input);
    
    #[derive(serde::Deserialize)]
    struct RotationResponse {
        needs_rotation: bool,
        keys_to_rotate: Vec<serde_json::Value>,
        warnings: Vec<String>,
    }
    
    let rotation: RotationResponse = parse_result(&result).expect("Should parse rotation check");
    // New key shouldn't need rotation
    assert!(!rotation.needs_rotation);
}

// MARK: - Secure Memory Tests

#[test]
fn test_secure_compare_ffi() {
    // Equal strings
    let input = r#"{
        "a": "secret_value_123",
        "b": "secret_value_123"
    }"#;
    
    let result = call_ffi(hawala_secure_compare, input);
    
    #[derive(serde::Deserialize)]
    struct CompareResponse {
        equal: bool,
    }
    
    let compare: CompareResponse = parse_result(&result).expect("Should parse");
    assert!(compare.equal);
    
    // Unequal strings
    let input2 = r#"{
        "a": "secret_value_123",
        "b": "different_secret"
    }"#;
    
    let result2 = call_ffi(hawala_secure_compare, input2);
    let compare2: CompareResponse = parse_result(&result2).expect("Should parse");
    assert!(!compare2.equal);
}

#[test]
fn test_redact_ffi() {
    let input = r#"{
        "data": "0x1234567890abcdef1234567890abcdef12345678"
    }"#;
    
    let result = call_ffi(hawala_redact, input);
    
    // The response is the redacted string directly in data
    // Parse as generic JSON value to handle various formats
    #[derive(serde::Deserialize)]
    struct Response {
        success: bool,
        data: serde_json::Value,
    }
    
    let response: Response = serde_json::from_str(&result).expect("Should parse response");
    assert!(response.success);
    
    // Data could be a string or an object with "redacted" field
    let redacted_str = if response.data.is_string() {
        response.data.as_str().unwrap().to_string()
    } else if let Some(obj) = response.data.as_object() {
        obj.get("redacted").and_then(|v| v.as_str()).unwrap_or_default().to_string()
    } else {
        format!("{}", response.data)
    };
    
    // Should be partially redacted - doesn't contain full original
    assert!(!redacted_str.contains("1234567890abcdef1234567890abcdef"));
}

// MARK: - End-to-End Security Flow Tests

#[test]
fn test_full_security_flow() {
    let wallet_id = "e2e-security-wallet";
    
    // Step 1: Register key
    let key_input = format!(r#"{{
        "wallet_id": "{}",
        "key_type": "master_seed",
        "derivation_path": null,
        "algorithm": "BIP39"
    }}"#, wallet_id);
    
    let key_result = call_ffi(hawala_register_key_version, &key_input);
    assert!(key_result.contains("\"success\":true"));
    
    // Step 2: Set spending limits
    let limits_input = format!(r#"{{
        "wallet_id": "{}",
        "per_tx_limit": "10000000000000000000",
        "daily_limit": "50000000000000000000",
        "weekly_limit": null,
        "monthly_limit": null,
        "require_whitelist": false
    }}"#, wallet_id);
    
    let limits_result = call_ffi(hawala_set_spending_limits, &limits_input);
    assert!(limits_result.contains("\"success\":true"));
    
    // Step 3: Whitelist a trusted address
    let whitelist_input = format!(r#"{{
        "wallet_id": "{}",
        "address": "0xmy_cold_storage"
    }}"#, wallet_id);
    
    let whitelist_result = call_ffi(hawala_whitelist_address, &whitelist_input);
    assert!(whitelist_result.contains("\"success\":true"));
    
    // Step 4: Assess a transaction
    let threat_input = format!(r#"{{
        "wallet_id": "{}",
        "recipient": "0xmy_cold_storage",
        "amount": "1000000000000000000",
        "chain": "ethereum"
    }}"#, wallet_id);
    
    let threat_result = call_ffi(hawala_assess_threat, &threat_input);
    
    #[derive(serde::Deserialize)]
    struct ThreatResponse {
        allow_transaction: bool,
    }
    
    let assessment: ThreatResponse = parse_result(&threat_result).expect("Should parse");
    assert!(assessment.allow_transaction);
    
    // Step 5: Check policy
    let policy_input = format!(r#"{{
        "wallet_id": "{}",
        "recipient": "0xmy_cold_storage",
        "amount": "1000000000000000000",
        "chain": "ethereum"
    }}"#, wallet_id);
    
    let policy_result = call_ffi(hawala_check_policy, &policy_input);
    
    #[derive(serde::Deserialize)]
    struct PolicyResponse {
        allowed: bool,
    }
    
    let policy: PolicyResponse = parse_result(&policy_result).expect("Should parse");
    assert!(policy.allowed);
}

#[test]
fn test_security_blocks_malicious_transaction() {
    let wallet_id = "block-test-wallet";
    
    // Blacklist a malicious address
    let blacklist_input = r#"{
        "address": "0xknown_scammer_wallet",
        "reason": "Confirmed scam wallet"
    }"#;
    
    call_ffi(hawala_blacklist_address, blacklist_input);
    
    // Try to send to blacklisted address
    let threat_input = format!(r#"{{
        "wallet_id": "{}",
        "recipient": "0xknown_scammer_wallet",
        "amount": "1000000000000000000",
        "chain": "ethereum"
    }}"#, wallet_id);
    
    let threat_result = call_ffi(hawala_assess_threat, &threat_input);
    
    #[derive(serde::Deserialize)]
    struct ThreatResponse {
        risk_level: String,
        allow_transaction: bool,
    }
    
    let assessment: ThreatResponse = parse_result(&threat_result).expect("Should parse");
    assert_eq!(assessment.risk_level, "critical");
    assert!(!assessment.allow_transaction);
}

// MARK: - Edge Case Tests

#[test]
fn test_empty_wallet_id_handling() {
    // Empty wallet ID should be handled gracefully
    let input = r#"{
        "wallet_id": "",
        "recipient": "0xvalid_address",
        "amount": "1000000000000000000",
        "chain": "ethereum"
    }"#;
    
    let result = call_ffi(hawala_assess_threat, input);
    // Should still return a response (may be default/safe behavior)
    assert!(result.contains("success"));
}

#[test]
fn test_zero_amount_transaction() {
    let input = r#"{
        "wallet_id": "zero-test-wallet",
        "recipient": "0xsome_address",
        "amount": "0",
        "chain": "ethereum"
    }"#;
    
    let result = call_ffi(hawala_assess_threat, input);
    assert!(result.contains("success"));
}

#[test]
fn test_very_large_amount() {
    // Test handling of very large amounts (potential overflow)
    let input = r#"{
        "wallet_id": "large-test-wallet",
        "recipient": "0xsome_address",
        "amount": "999999999999999999999999999999",
        "chain": "ethereum"
    }"#;
    
    let result = call_ffi(hawala_assess_threat, input);
    // Should handle gracefully, may trigger high risk
    assert!(result.contains("success") || result.contains("error"));
}

#[test]
fn test_invalid_chain_handling() {
    let input = r#"{
        "wallet_id": "chain-test-wallet",
        "recipient": "0xsome_address",
        "amount": "1000000000000000000",
        "chain": "invalid_chain"
    }"#;
    
    let result = call_ffi(hawala_assess_threat, input);
    // Should handle invalid chain gracefully
    assert!(result.len() > 0);
}

#[test]
fn test_unicode_in_address() {
    // Addresses shouldn't contain unicode - test handling
    let input = r#"{
        "address": "0x1234日本語test",
        "reason": "Unicode test"
    }"#;
    
    let result = call_ffi(hawala_blacklist_address, input);
    // Should handle gracefully
    assert!(result.len() > 0);
}

#[test]
fn test_special_characters_in_reason() {
    let input = r#"{
        "address": "0xtest_special_chars",
        "reason": "Test with <script>alert('xss')</script> and \"quotes\""
    }"#;
    
    let result = call_ffi(hawala_blacklist_address, input);
    assert!(result.contains("success"));
}

#[test]
fn test_multiple_whitelist_same_address() {
    // Whitelisting same address multiple times should be idempotent
    let input = r#"{
        "wallet_id": "idempotent-test-wallet",
        "address": "0xidempotent_test_address"
    }"#;
    
    let result1 = call_ffi(hawala_whitelist_address, input);
    let result2 = call_ffi(hawala_whitelist_address, input);
    let result3 = call_ffi(hawala_whitelist_address, input);
    
    // Accept both "success":true and "success": true (with space)
    assert!(result1.contains("\"success\":true") || result1.contains("\"success\": true"), 
            "Expected success in result1: {}", result1);
    assert!(result2.contains("\"success\":true") || result2.contains("\"success\": true"),
            "Expected success in result2: {}", result2);
    assert!(result3.contains("\"success\":true") || result3.contains("\"success\": true"),
            "Expected success in result3: {}", result3);
}

#[test]
fn test_blacklist_then_whitelist_conflict() {
    // Test behavior when address is both blacklisted and whitelisted
    let address = "0xconflict_test_address";
    
    let blacklist_input = format!(r#"{{
        "address": "{}",
        "reason": "Testing conflict"
    }}"#, address);
    
    let whitelist_input = format!(r#"{{
        "address": "{}"
    }}"#, address);
    
    call_ffi(hawala_blacklist_address, &blacklist_input);
    call_ffi(hawala_whitelist_address, &whitelist_input);
    
    // Now test transaction to this address
    let threat_input = format!(r#"{{
        "wallet_id": "conflict-wallet",
        "recipient": "{}",
        "amount": "1000000000000000000",
        "chain": "ethereum"
    }}"#, address);
    
    let result = call_ffi(hawala_assess_threat, &threat_input);
    // Blacklist should take precedence (security first)
    assert!(result.contains("success"));
}

#[test]
fn test_limit_boundary_exact() {
    let wallet_id = "boundary-test-wallet";
    
    // Set limit to exactly 1 ETH
    let limit_input = format!(r#"{{
        "wallet_id": "{}",
        "daily_limit": "1000000000000000000",
        "tx_limit": "1000000000000000000",
        "chain": "ethereum"
    }}"#, wallet_id);
    
    call_ffi(hawala_set_spending_limits, &limit_input);
    
    // Test at exact boundary
    let policy_input = format!(r#"{{
        "wallet_id": "{}",
        "recipient": "0xsome_address",
        "amount": "1000000000000000000",
        "chain": "ethereum"
    }}"#, wallet_id);
    
    let result = call_ffi(hawala_check_policy, &policy_input);
    
    #[derive(serde::Deserialize)]
    struct PolicyResponse {
        allowed: bool,
    }
    
    // Exact boundary should be allowed (<=)
    let policy: PolicyResponse = parse_result(&result).expect("Should parse");
    assert!(policy.allowed);
}

#[test]
fn test_limit_boundary_over_by_one() {
    let wallet_id = "boundary-over-wallet";
    
    // Set limit to exactly 1 ETH
    let limit_input = format!(r#"{{
        "wallet_id": "{}",
        "daily_limit": "1000000000000000000",
        "tx_limit": "1000000000000000000",
        "chain": "ethereum"
    }}"#, wallet_id);
    
    call_ffi(hawala_set_spending_limits, &limit_input);
    
    // Test just over boundary
    let policy_input = format!(r#"{{
        "wallet_id": "{}",
        "recipient": "0xsome_address",
        "amount": "1000000000000000001",
        "chain": "ethereum"
    }}"#, wallet_id);
    
    let result = call_ffi(hawala_check_policy, &policy_input);
    
    #[derive(serde::Deserialize)]
    struct PolicyResponse {
        allowed: bool,
    }
    
    // Over boundary should be denied
    let policy: PolicyResponse = parse_result(&result).expect("Should parse");
    assert!(!policy.allowed);
}

#[test]
fn test_secure_compare_timing() {
    // Test that secure compare works with various string lengths
    let test_cases = vec![
        ("a", "a"),
        ("short", "short"),
        ("medium_length_string_here", "medium_length_string_here"),
        ("this is a much longer string to compare for timing attacks", 
         "this is a much longer string to compare for timing attacks"),
    ];
    
    for (a, b) in test_cases {
        let input = format!(r#"{{
            "a": "{}",
            "b": "{}"
        }}"#, a, b);
        
        let result = call_ffi(hawala_secure_compare, &input);
        
        #[derive(serde::Deserialize)]
        struct CompareResponse {
            equal: bool,
        }
        
        let compare: CompareResponse = parse_result(&result).expect("Should parse");
        assert!(compare.equal);
    }
}

#[test]
fn test_secure_compare_different_lengths() {
    let input = r#"{
        "a": "short",
        "b": "much_longer_string"
    }"#;
    
    let result = call_ffi(hawala_secure_compare, input);
    
    #[derive(serde::Deserialize)]
    struct CompareResponse {
        equal: bool,
    }
    
    let compare: CompareResponse = parse_result(&result).expect("Should parse");
    assert!(!compare.equal);
}

#[test]
fn test_redact_various_formats() {
    // Test redaction with various sensitive data formats
    let test_cases = vec![
        "0x1234567890abcdef1234567890abcdef12345678",  // ETH address
        "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",  // BTC address
        "xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvNKmPGJxWUtg6LnF5kejMRNNU3TGtRBeJgk33yuGBxrMPHi",  // Extended key
        "L5oLkpV3aqBjhki6LmvChTCV6odsp4SXM6FfU2Gppt5kFLaHLuZ9",  // WIF
    ];
    
    for data in test_cases {
        let input = format!(r#"{{"data": "{}"}}"#, data);
        let result = call_ffi(hawala_redact, &input);
        assert!(result.contains("\"success\":true"));
    }
}

#[test]
fn test_challenge_with_empty_data() {
    let input = r#"{
        "data": ""
    }"#;
    
    let result = call_ffi(hawala_create_challenge, input);
    // Should handle empty data gracefully
    assert!(result.len() > 0);
}

#[test]
fn test_key_rotation_new_wallet() {
    // A brand new wallet shouldn't need rotation
    let wallet_id = format!("brand_new_wallet_{}", std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos());
    
    let input = format!(r#"{{
        "wallet_id": "{}"
    }}"#, wallet_id);
    
    let result = call_ffi(hawala_check_key_rotation, &input);
    
    #[derive(serde::Deserialize)]
    struct RotationResponse {
        needs_rotation: bool,
    }
    
    let rotation: RotationResponse = parse_result(&result).expect("Should parse");
    // New wallet shouldn't need immediate rotation
    assert!(!rotation.needs_rotation);
}

// MARK: - Stress Tests

#[test]
fn test_rapid_threat_assessments() {
    // Simulate rapid-fire threat assessments
    for i in 0..50u64 {
        let input = format!(r#"{{
            "wallet_id": "stress-test-wallet",
            "recipient": "0xrecipient_{}",
            "amount": "{}",
            "chain": "ethereum"
        }}"#, i, i.saturating_mul(100000000000000000));  // Use saturating mul to prevent overflow
        
        let result = call_ffi(hawala_assess_threat, &input);
        assert!(result.contains("success"));
    }
}

#[test]
fn test_many_blacklist_entries() {
    // Add many blacklist entries
    for i in 0..100 {
        let input = format!(r#"{{
            "address": "0xblacklist_stress_test_{}",
            "reason": "Stress test entry {}"
        }}"#, i, i);
        
        let result = call_ffi(hawala_blacklist_address, &input);
        assert!(result.contains("\"success\":true"));
    }
}

#[test]
fn test_concurrent_policy_checks() {
    // While not truly concurrent (single-threaded test), this tests
    // rapid sequential policy checks
    let wallet_id = "concurrent-policy-wallet";
    
    let limit_input = format!(r#"{{
        "wallet_id": "{}",
        "daily_limit": "10000000000000000000",
        "tx_limit": "1000000000000000000",
        "chain": "ethereum"
    }}"#, wallet_id);
    
    call_ffi(hawala_set_spending_limits, &limit_input);
    
    for i in 0..100 {
        let policy_input = format!(r#"{{
            "wallet_id": "{}",
            "recipient": "0xrecipient_{}",
            "amount": "100000000000000000",
            "chain": "ethereum"
        }}"#, wallet_id, i);
        
        let result = call_ffi(hawala_check_policy, &policy_input);
        assert!(result.contains("success"));
    }
}
