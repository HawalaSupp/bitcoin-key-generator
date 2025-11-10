# Validation Testing Checklist

**Purpose**: Track validation test results for all 5 chains  
**Date Started**: November 10, 2025  
**Target**: 100% pass rate before v1.0 release

---

## Pre-Validation Setup

- [ ] **Read** VALIDATION_TESTING.md
- [ ] **Download** all required wallets (in advance to save time)
- [ ] **Set aside** 2-3 hours for testing
- [ ] **Use** isolated/test computer if possible
- [ ] **Have** test files ready for copy/paste

### Required Downloads

- [ ] Electrum (Testnet): https://electrum.org/
- [ ] Litecoin Core (Testnet): https://litecoin.org/en/download
- [ ] Monero GUI Wallet: https://www.getmonero.org/downloads/
- [ ] Solana CLI: https://docs.solana.com/cli/install-solana-cli-tools
- [ ] Python web3: `pip3 install web3`

---

## 1️⃣ Bitcoin Validation

### Test Case 1: Basic Address Derivation

**Test Steps:**
- [ ] Run generator: `cargo run --manifest-path rust-app/Cargo.toml --bin rust-app`
- [ ] Copy Bitcoin WIF private key
- [ ] Import into Electrum (testnet mode)
- [ ] Verify Electrum generates matching address

**Test Data:**

| Item | Value | Status |
|------|-------|--------|
| Private Key (hex) | __________ | ⬜ |
| Private Key (WIF) | __________ | ⬜ |
| Expected Address | __________ | ⬜ |
| Electrum Address | __________ | ⬜ |
| Match? | YES / NO | ⬜ |

**Result:**
- [ ] ✅ PASS - Addresses match
- [ ] ❌ FAIL - Investigate derivation

**Notes:**
```
_________________________________________________
_________________________________________________
```

---

### Test Case 2: Public Key Verification

**Test Steps:**
- [ ] In Electrum, view "Show Public Key"
- [ ] Copy the public key from Electrum
- [ ] Compare with our generated public key

**Test Data:**

| Item | Value | Status |
|------|-------|--------|
| Our Public Key | __________ | ⬜ |
| Electrum Public Key | __________ | ⬜ |
| Match? | YES / NO | ⬜ |

**Result:**
- [ ] ✅ PASS - Public keys match
- [ ] ❌ FAIL - Check derivation algorithm

**Notes:**
```
_________________________________________________
_________________________________________________
```

---

### Test Case 3: Transaction Signing (Optional)

**Test Steps:**
- [ ] Create a dummy transaction in Electrum
- [ ] Sign with imported private key
- [ ] Verify signature is accepted

**Result:**
- [ ] ✅ PASS - Signing works
- [ ] ❌ FAIL - Key format issue
- [ ] ⏭️ SKIP - Not critical

---

## 2️⃣ Litecoin Validation

### Test Case 1: Basic Address Derivation

**Test Steps:**
- [ ] Run generator: `cargo run --manifest-path rust-app/Cargo.toml --bin rust-app`
- [ ] Copy Litecoin WIF private key (should start with 'T')
- [ ] Import into Litecoin Core (testnet mode)
- [ ] Verify Litecoin Core generates matching address

**Test Data:**

| Item | Value | Status |
|------|-------|--------|
| Private Key (hex) | __________ | ⬜ |
| Private Key (WIF) | __________ | ⬜ |
| Expected Address (ltc1...) | __________ | ⬜ |
| Litecoin Core Address | __________ | ⬜ |
| Match? | YES / NO | ⬜ |

**Result:**
- [ ] ✅ PASS - Addresses match
- [ ] ❌ FAIL - Check WIF encoding (should use 0xB0 prefix)

**Notes:**
```
_________________________________________________
_________________________________________________
```

---

### Test Case 2: WIF Prefix Verification

**Test Steps:**
- [ ] Our Litecoin WIF should start with 'T' or 'cU' or 'cT'
- [ ] This is the Litecoin-specific prefix
- [ ] Verify Litecoin Core accepts it without errors

**Result:**
- [ ] ✅ PASS - Correct prefix, accepted
- [ ] ❌ FAIL - Wrong prefix or rejected

**Notes:**
```
_________________________________________________
_________________________________________________
```

---

## 3️⃣ Monero Validation

### Test Case 1: Wallet Creation from Spend Key

**Test Steps:**
- [ ] Run generator: `cargo run --manifest-path rust-app/Cargo.toml --bin rust-app`
- [ ] Copy private spend key (hex)
- [ ] Run: `monero-wallet-cli --testnet`
- [ ] Restore from keys, enter spend key
- [ ] Run command: `address`

**Test Data:**

| Item | Value | Status |
|------|-------|--------|
| Private Spend Key | __________ | ⬜ |
| Private View Key (expected) | __________ | ⬜ |
| Expected Primary Address | __________ | ⬜ |
| Wallet Primary Address | __________ | ⬜ |
| Match? | YES / NO | ⬜ |

**Result:**
- [ ] ✅ PASS - Primary address matches
- [ ] ❌ FAIL - Check Ed25519 or Keccak-256 implementation

**Notes:**
```
_________________________________________________
_________________________________________________
```

---

### Test Case 2: View Key Verification

**Test Steps:**
- [ ] In monero-wallet-cli, run: `viewkey`
- [ ] Copy the private view key shown
- [ ] Compare with our expected view key

**Test Data:**

| Item | Value | Status |
|------|-------|--------|
| Our View Key (expected) | __________ | ⬜ |
| Wallet View Key | __________ | ⬜ |
| Match? | YES / NO | ⬜ |

**Result:**
- [ ] ✅ PASS - View key matches (derived correctly from spend key)
- [ ] ❌ FAIL - Check Keccak-256 derivation

**Notes:**
```
_________________________________________________
_________________________________________________
```

---

### Test Case 3: Public Keys Verification

**Test Steps:**
- [ ] In monero-wallet-cli, run: `rescan_bc` (to rebuild)
- [ ] Verify wallet scans blocks correctly
- [ ] Compare public spend/view keys with our output

**Result:**
- [ ] ✅ PASS - Keys scan blocks correctly
- [ ] ❌ FAIL - Public key derivation issue
- [ ] ⏭️ SKIP - Not critical

---

## 4️⃣ Solana Validation

### Test Case 1: Address Derivation

**Test Steps:**
- [ ] Run generator: `cargo run --manifest-path rust-app/Cargo.toml --bin rust-app`
- [ ] Copy private seed (hex)
- [ ] Copy expected address (base58)
- [ ] Run: `solana-keygen new -o test-key.json`
- [ ] Import our keypair and verify address

**Test Data:**

| Item | Value | Status |
|------|-------|--------|
| Private Seed (hex) | __________ | ⬜ |
| Expected Address (base58) | __________ | ⬜ |
| Solana CLI Address | __________ | ⬜ |
| Match? | YES / NO | ⬜ |

**Result:**
- [ ] ✅ PASS - Addresses match
- [ ] ❌ FAIL - Check Ed25519 or base58 encoding

**Notes:**
```
_________________________________________________
_________________________________________________
```

---

### Test Case 2: Signing Test

**Test Steps:**
- [ ] Create a test message file
- [ ] Sign with our keypair: `solana-keygen verify [pubkey] test-message.txt test-key.json`
- [ ] Verify signature succeeds

**Result:**
- [ ] ✅ PASS - Signing works
- [ ] ❌ FAIL - Ed25519 implementation issue
- [ ] ⏭️ SKIP - Not critical

---

## 5️⃣ Ethereum Validation

### Test Case 1: Address Derivation

**Test Steps:**
- [ ] Run generator: `cargo run --manifest-path rust-app/Cargo.toml --bin rust-app`
- [ ] Copy private key (hex)
- [ ] Run: `python3 validate_ethereum.py <private_key>`
- [ ] Compare with expected address

**Test Data:**

| Item | Value | Status |
|------|-------|--------|
| Private Key (hex) | __________ | ⬜ |
| Expected Address | __________ | ⬜ |
| Web3.py Address | __________ | ⬜ |
| Match? | YES / NO | ⬜ |

**Result:**
- [ ] ✅ PASS - Addresses match
- [ ] ❌ FAIL - Check secp256k1 or Keccak-256

**Notes:**
```
_________________________________________________
_________________________________________________
```

---

### Test Case 2: EIP-55 Checksum Verification

**Test Steps:**
- [ ] Verify our address is in proper EIP-55 format (mixed case)
- [ ] Compare with web3.py checksummed address
- [ ] Verify they match exactly

**Test Data:**

| Item | Value | Status |
|------|-------|--------|
| Our Checksummed Address | __________ | ⬜ |
| Web3.py Checksummed | __________ | ⬜ |
| Match? | YES / NO | ⬜ |

**Result:**
- [ ] ✅ PASS - Checksum correct
- [ ] ❌ FAIL - Check EIP-55 implementation

**Notes:**
```
_________________________________________________
_________________________________________________
```

---

### Test Case 3: Signing Test

**Test Steps:**
- [ ] Use web3.py to sign a message with our private key
- [ ] Verify signature recovers to our address

**Result:**
- [ ] ✅ PASS - Signing and recovery works
- [ ] ❌ FAIL - secp256k1 issue
- [ ] ⏭️ SKIP - Not critical

---

## 📊 Summary Results

| Chain | Test 1 | Test 2 | Test 3 | Overall |
|-------|--------|--------|--------|---------|
| Bitcoin | ⬜ | ⬜ | ⬜ | ⬜ |
| Litecoin | ⬜ | ⬜ | ⬜ | ⬜ |
| Monero | ⬜ | ⬜ | ⬜ | ⬜ |
| Solana | ⬜ | ⬜ | ⬜ | ⬜ |
| Ethereum | ⬜ | ⬜ | ⬜ | ⬜ |

**Legend:**
- ⬜ Not tested
- ✅ PASS
- ❌ FAIL
- ⏭️ SKIP

---

## 🎯 Final Status

### Pre-Release Checklist

- [ ] Bitcoin: ✅ PASS all tests
- [ ] Litecoin: ✅ PASS all tests
- [ ] Monero: ✅ PASS all tests
- [ ] Solana: ✅ PASS all tests
- [ ] Ethereum: ✅ PASS all tests

### Sign-Off

**All tests passed?**
- [ ] YES - Proceed to security audit
- [ ] NO - See troubleshooting section in VALIDATION_TESTING.md

**Tested by:** ______________________________

**Date completed:** ______________________________

**Notes:**
```
_________________________________________________
_________________________________________________
_________________________________________________
```

---

## 🔧 Troubleshooting Quick Links

### Bitcoin Issues
- Address doesn't match? → Check hash160 calculation
- WIF not accepted? → Verify prefix (0x80)
- See: VALIDATION_TESTING.md → "Troubleshooting" → "Bitcoin/Litecoin"

### Litecoin Issues
- Address doesn't match? → Check WIF prefix (0xB0)
- Wallet rejects key? → Verify Litecoin-specific encoding
- See: VALIDATION_TESTING.md → "Troubleshooting" → "Bitcoin/Litecoin"

### Monero Issues
- Address mismatch? → Check Ed25519 scalar reduction
- View key wrong? → Check Keccak-256 derivation
- See: VALIDATION_TESTING.md → "Troubleshooting" → "Monero"

### Solana Issues
- Address doesn't match? → Check Ed25519 implementation
- Can't sign? → Check keypair format
- See: VALIDATION_TESTING.md → "Troubleshooting" → "Solana"

### Ethereum Issues
- Address doesn't match? → Check Keccak-256 hash
- Checksum wrong? → Check EIP-55 implementation
- See: VALIDATION_TESTING.md → "Troubleshooting" → "Ethereum"

---

**Status**: Testing in progress  
**Last Updated**: November 10, 2025  
**Next**: Complete all tests and proceed to security audit
