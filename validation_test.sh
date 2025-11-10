#!/bin/bash
# Automated validation harness for wallet key material
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
TEST_OUTPUT_DIR="$PROJECT_ROOT/validation_tests"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
JSON_OUTPUT="$TEST_OUTPUT_DIR/key_material_$TIMESTAMP.json"
HUMAN_OUTPUT="$TEST_OUTPUT_DIR/human_readable_$TIMESTAMP.txt"
VALIDATION_LOG="$TEST_OUTPUT_DIR/validator_output_$TIMESTAMP.txt"
TEST_REPORT="$TEST_OUTPUT_DIR/test_report_$TIMESTAMP.txt"

mkdir -p "$TEST_OUTPUT_DIR"

echo "==========================================" | tee "$TEST_REPORT"
echo "Multi-Chain Wallet Validation" | tee -a "$TEST_REPORT"
echo "==========================================" | tee -a "$TEST_REPORT"
echo "Timestamp: $TIMESTAMP" | tee -a "$TEST_REPORT"
echo "Output directory: $TEST_OUTPUT_DIR" | tee -a "$TEST_REPORT"
echo "" | tee -a "$TEST_REPORT"

say_and_report() {
    echo "$1"
    printf '%s\n' "$1" >> "$TEST_REPORT"
}

append_section() {
    printf '%s\n' "$1" >> "$TEST_REPORT"
}

append_block() {
    printf '%s\n' "$1" >> "$TEST_REPORT"
    cat >> "$TEST_REPORT"
}

verify_builds() {
    say_and_report "Step 1: Verifying builds..."
    append_section "BUILD VERIFICATION"
    append_section "=================="

    if BUILD_OUTPUT=$(cd "$PROJECT_ROOT" && cargo build --manifest-path rust-app/Cargo.toml 2>&1); then
        say_and_report "Rust build: ✅ PASS"
        append_block "Rust build output:" <<<"$BUILD_OUTPUT"
    else
        say_and_report "Rust build: ❌ FAIL"
        append_block "Rust build output:" <<<"$BUILD_OUTPUT"
        exit 1
    fi

    if SWIFT_OUTPUT=$(cd "$PROJECT_ROOT" && swift build --package-path swift-app 2>&1); then
        say_and_report "Swift build: ✅ PASS"
        append_block "Swift build output:" <<<"$SWIFT_OUTPUT"
    else
        say_and_report "Swift build: ❌ FAIL"
        append_block "Swift build output:" <<<"$SWIFT_OUTPUT"
        exit 1
    fi

    if command -v cargo-audit >/dev/null 2>&1; then
        AUDIT_JSON="$TEST_OUTPUT_DIR/cargo_audit_$TIMESTAMP.json"
        AUDIT_ERR="$TEST_OUTPUT_DIR/cargo_audit_$TIMESTAMP.err"
        if cd "$PROJECT_ROOT/rust-app" && cargo audit --json > "$AUDIT_JSON" 2>"$AUDIT_ERR"; then
            if grep -q '"found":false' "$AUDIT_JSON"; then
                say_and_report "Security audit: ✅ PASS (0 vulnerabilities)"
                say_and_report "Security audit details: $AUDIT_JSON"
            else
                say_and_report "Security audit: ⚠️ CHECK (review $AUDIT_JSON)"
            fi
        else
            say_and_report "Security audit: ❌ FAIL (see $AUDIT_ERR)"
        fi
        append_section "cargo audit output (JSON):"
        if [ -s "$AUDIT_JSON" ]; then
            cat "$AUDIT_JSON" >> "$TEST_REPORT"
        fi
        if [ -s "$AUDIT_ERR" ]; then
            append_section "cargo audit stderr:"
            cat "$AUDIT_ERR" >> "$TEST_REPORT"
        fi
    else
        say_and_report "Security audit: ⚠️ SKIPPED (cargo-audit not installed)"
    fi

    say_and_report ""
}

generate_key_material() {
    say_and_report "Step 2: Generating key material snapshots..."

    if cd "$PROJECT_ROOT" && cargo run --manifest-path rust-app/Cargo.toml --bin rust-app -- --json > "$JSON_OUTPUT" 2>"$TEST_OUTPUT_DIR/json_err_$TIMESTAMP.txt"; then
        say_and_report "JSON export created: $JSON_OUTPUT"
    else
        say_and_report "JSON export failed (see $TEST_OUTPUT_DIR/json_err_$TIMESTAMP.txt)"
        exit 1
    fi

    if cd "$PROJECT_ROOT" && cargo run --manifest-path rust-app/Cargo.toml --bin rust-app > "$HUMAN_OUTPUT" 2>"$TEST_OUTPUT_DIR/text_err_$TIMESTAMP.txt"; then
        say_and_report "Human-readable snapshot: $HUMAN_OUTPUT"
    else
        say_and_report "Human-readable snapshot failed (see $TEST_OUTPUT_DIR/text_err_$TIMESTAMP.txt)"
        exit 1
    fi

    append_section "KEY MATERIAL (Human Readable)"
    append_section "------------------------------"
    cat "$HUMAN_OUTPUT" >> "$TEST_REPORT"
    append_section ""
}

run_wallet_validator() {
    say_and_report "Step 3: Running wallet validator..."

    if cd "$PROJECT_ROOT" && cargo run --manifest-path rust-app/Cargo.toml --bin wallet_validator -- "$JSON_OUTPUT" > "$VALIDATION_LOG" 2>&1; then
        say_and_report "Wallet validation: ✅ PASS"
    else
        say_and_report "Wallet validation: ❌ FAIL"
        say_and_report "See $VALIDATION_LOG for details"
        cat "$VALIDATION_LOG" >> "$TEST_REPORT"
        exit 1
    fi

    append_section "VALIDATOR OUTPUT"
    append_section "----------------"
    cat "$VALIDATION_LOG" >> "$TEST_REPORT"
    append_section ""
}

create_import_instructions() {
    append_section "NEXT STEPS - WALLET VALIDATION"
    append_section "=============================="
    append_section "1. Bitcoin (Electrum):"
    append_section "   - Download: https://electrum.org/"
    append_section "   - Run in testnet mode"
    append_section "   - Import WIF private key"
    append_section "   - Verify generated address matches"
    append_section ""
    append_section "2. Litecoin (Litecoin Core):"
    append_section "   - Download: https://litecoin.org/en/download"
    append_section "   - Run in testnet mode"
    append_section "   - Import WIF private key"
    append_section "   - Verify generated address matches"
    append_section ""
    append_section "3. Monero (monero-wallet-cli):"
    append_section "   - Download: https://www.getmonero.org/downloads/"
    append_section "   - Restore from spend key"
    append_section "   - Run: address"
    append_section "   - Verify primary address and view key match"
    append_section ""
    append_section "4. Solana (CLI):"
    append_section "   - Install: https://docs.solana.com/cli/install-solana-cli-tools"
    append_section "   - Import keypair"
    append_section "   - Run: solana address --keypair <file>"
    append_section "   - Verify address matches"
    append_section ""
    append_section "5. Ethereum (web3.py):"
    append_section "   - Install: pip3 install web3"
    append_section "   - Run test script (see VALIDATION_TESTING.md)"
    append_section "   - Verify address and checksum match"
    append_section ""
}

verify_builds
generate_key_material
run_wallet_validator
create_import_instructions

say_and_report "=========================================="
say_and_report "Validation complete. Consolidated report: $TEST_REPORT"
say_and_report "JSON key material: $JSON_OUTPUT"
say_and_report "Validator log: $VALIDATION_LOG"
say_and_report "=========================================="

echo "Next steps:"
echo "1. Review $TEST_REPORT"
echo "2. Follow wallet import instructions as needed"
echo "3. Archive artifacts for audit trail"
