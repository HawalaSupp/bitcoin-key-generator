#!/bin/bash
# Security scanning script for Hawala

set -e

echo "======================================="
echo "  Hawala Security Scanning Suite"
echo "======================================="
echo ""

REPORT_DIR="./validation_tests"
mkdir -p "$REPORT_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="$REPORT_DIR/security_scan_$TIMESTAMP.txt"

echo "Generating security scan report: $REPORT_FILE"
echo ""

{
    echo "Security Scan Report"
    echo "Generated: $(date)"
    echo "======================================="
    echo ""

    # 1. Cargo Audit
    echo "## Dependency Vulnerability Scan (cargo audit)"
    echo "----------------------------------------------"
    cd rust-app
    cargo audit 2>&1 || true
    echo ""

    # 2. Clippy Security Lints
    echo "## Static Analysis (cargo clippy)"
    echo "----------------------------------------------"
    cargo clippy --all-targets --all-features 2>&1 | head -100 || true
    echo ""

    # 3. Test Summary
    echo "## Test Coverage Summary"
    echo "----------------------------------------------"
    echo "Rust Unit Tests:"
    cargo test 2>&1 | tail -5 || true
    echo ""
    echo "Security Integration Tests:"
    cargo test --test security_integration 2>&1 | tail -5 || true
    cd ..
    echo ""

    # 4. Swift Build Check
    echo "## Swift Build Status"
    echo "----------------------------------------------"
    cd swift-app
    swift build 2>&1 | tail -10 || true
    cd ..
    echo ""

    # 5. Summary
    echo "## Scan Summary"
    echo "----------------------------------------------"
    echo "Scan completed at: $(date)"
    echo ""
    echo "KNOWN ISSUES:"
    echo "- curve25519-dalek v3.2.0: Timing variability (transitive dep via solana-sdk)"
    echo "- rustls-pemfile v1.0.4: Unmaintained (transitive dep via reqwest)"  
    echo "- atty v0.2.14: Potential unaligned read (low risk)"
    echo ""
    echo "RECOMMENDATIONS:"
    echo "1. Monitor solana-sdk updates for curve25519-dalek fix"
    echo "2. Consider reqwest update when compatible version available"
    echo "3. These are transitive dependencies - direct upgrade not possible"
    echo ""

} | tee "$REPORT_FILE"

echo ""
echo "======================================="
echo "  Scan complete! Report saved to:"
echo "  $REPORT_FILE"
echo "======================================="
