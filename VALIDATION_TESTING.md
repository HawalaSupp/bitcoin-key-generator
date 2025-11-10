# Validation Testing Guide

**Purpose**: Verify that all generated keys are cryptographically correct and compatible with official wallet implementations.

**Duration**: 2-3 hours total (30 min per chain)  
**Importance**: 🔴 CRITICAL - Must complete before v1.0 release

---

## Overview

This guide walks you through validating each of the 5 supported cryptocurrencies by importing generated keys into official wallet software and verifying the addresses match.

> **Automation tip**: Run `./validation_test.sh` first. The harness now generates structured JSON (`validation_tests/key_material_*.json`) and runs the `wallet_validator` binary for deterministic cross-checks before you begin the manual wallet imports described below.

### What We're Testing

For each chain, we verify:
- ✅ Private key format is correct
- ✅ Public key derivation is correct
- ✅ Address generation matches official wallets
- ✅ Keys can be imported without errors
- ✅ Address matches between generator and wallet

---

## Pre-Requisites

Before starting, ensure you have:
- ✅ Generator built and working: `cargo run --manifest-path rust-app/Cargo.toml --bin rust-app`
- ✅ A test computer (preferably with clean OS or isolated environment)
- ✅ Network connectivity (for downloading wallets)
- ✅ 1-2 hours of free time

### Download Wallets in Advance

To save time during testing, download these wallets now:

1. **Bitcoin & Litecoin**: Electrum (Testnet)
   - Download: https://electrum.org/
   - Choose "Testnet" version

2. **Monero**: Monero GUI Wallet
   - Download: https://www.getmonero.org/downloads/

3. **Solana**: Solana CLI
   - Install: https://docs.solana.com/cli/install-solana-cli-tools

4. **Ethereum**: Use Python web3.py (already available via pip)
   - Install: `pip3 install web3`

---

## Chain-by-Chain Testing

### 1️⃣ Bitcoin (P2WPKH Bech32) - 30 minutes

#### Step 1: Generate a Bitcoin Key

```bash
cd /Users/x/Desktop/888
cargo run --manifest-path rust-app/Cargo.toml --bin rust-app 2>&1 | grep -A5 "=== Bitcoin"
```

**Example output** (note these values for testing):
```
=== Bitcoin (P2WPKH) ===
Private key (hex): 199de1c9e4e8f956b9e86cee3db535b454c4cde23e8383df593822a5e1a49343
Private key (WIF): Kx5WKxAJzhcLURwRmGWnJd5ZULtxH5H6wgBrydn6c8hpMtaKgVcw
Public key (compressed hex): 02f8946397c7a300f9fca1b330fbe8245b9689807b9d1304e15b5c57aa1d115fee
Bech32 address (P2WPKH): bc1qjvkdhpem3jn4mkgkw33dyn4pkvjtgwn0fkdcp0
```

**Copy these to a text file for reference:**
```
BITCOIN_TEST_1.txt:
- WIF: Kx5WKxAJzhcLURwRmGWnJd5ZULtxH5H6wgBrydn6c8hpMtaKgVcw
- Address: bc1qjvkdhpem3jn4mkgkw33dyn4pkvjtgwn0fkdcp0
- Expected Pubkey: 02f8946397c7a300f9fca1b330fbe8245b9689807b9d1304e15b5c57aa1d115fee
```

#### Step 2: Import into Electrum (Testnet)

1. **Start Electrum in Testnet mode**:
   ```bash
   /Applications/Electrum.app/Contents/MacOS/Electrum --testnet
   ```

2. **Create new wallet**:
   - Click "New wallet"
   - Choose "Standard wallet"
   - Select "Use a private key"

3. **Paste WIF private key**:
   - Paste: `Kx5WKxAJzhcLURwRmGWnJd5ZULtxH5H6wgBrydn6c8hpMtaKgVcw`

4. **Verify address**:
   - Electrum will display an address
   - ✅ **PASS** if it matches `bc1qjvkdhpem3jn4mkgkw33dyn4pkvjtgwn0fkdcp0`
   - ❌ **FAIL** if addresses don't match (error in key generation)

#### Step 3: Verify Public Key Derivation

In Electrum:
1. Go to **View** → **Show Public Key**
2. Check if the public key matches: `02f8946397c7a300f9fca1b330fbe8245b9689807b9d1304e15b5c57aa1d115fee`
3. ✅ **PASS** if matches
4. ❌ **FAIL** if different

#### Step 4: Sign & Verify Transaction (Optional Advanced Test)

1. In Electrum, create a transaction
2. Sign with the private key
3. Verify signature is accepted
4. ✅ **PASS** if transaction signs without error

#### Test Result
- ✅ **PASS**: Address matches, public key matches
- ❌ **FAIL**: Investigate key derivation

---

### 2️⃣ Litecoin (P2WPKH Bech32) - 30 minutes

#### Step 1: Generate a Litecoin Key

```bash
cd /Users/x/Desktop/888
cargo run --manifest-path rust-app/Cargo.toml --bin rust-app 2>&1 | grep -A5 "=== Litecoin"
```

**Example output:**
```
=== Litecoin (P2WPKH) ===
Private key (hex): a9019e155008668cbdd2ce55a5897974db124e4093c70238a77313777391cb71
Private key (WIF): T8iW9Y1D14CWXt2GKguKUeuD9rjXNA5A9ryVoSf6P6cA7jTuD3CH
Public key (compressed hex): 03e0d2111bb267f90fb97a36ba18498ac02eaac27f283cd7d5bc362c47c6164205
Bech32 address (P2WPKH): ltc1qaxk6ufcra7zqtwjr4pr735qyqpt7ze0qsdhl2l
```

#### Step 2: Import into Litecoin Core

1. **Download and install Litecoin Core**: https://litecoin.org/en/download

2. **Start Litecoin Core** (testnet):
   ```bash
   /Applications/Litecoin-Qt.app/Contents/MacOS/Litecoin-Qt -testnet
   ```

3. **Unlock wallet** (if encrypted):
   - File → Unlock Wallet → Enter passphrase

4. **Import private key**:
   - File → Sign/Verify Message (or use console)
   - Or use RPC: `importprivkey "T8iW9Y1D14CWXt2GKguKUeuD9rjXNA5A9ryVoSf6P6cA7jTuD3CH"`

5. **Verify address**:
   - Litecoin Core will derive the address from the WIF
   - ✅ **PASS** if it matches `ltc1qaxk6ufcra7zqtwjr4pr735qyqpt7ze0qsdhl2l`
   - ❌ **FAIL** if different

#### Step 3: Verify WIF Encoding

Litecoin uses prefix `0xB0` (instead of Bitcoin's `0x80`). Verify:
- ✅ **PASS** if Litecoin Core accepts the WIF
- ❌ **FAIL** if rejected or wrong address generated

#### Test Result
- ✅ **PASS**: Address matches, wallet accepts key
- ❌ **FAIL**: Check WIF encoding

---

### 3️⃣ Monero (Ed25519) - 30 minutes

#### Step 1: Generate a Monero Key Set

```bash
cd /Users/x/Desktop/888
cargo run --manifest-path rust-app/Cargo.toml --bin rust-app 2>&1 | grep -A7 "=== Monero"
```

**Example output:**
```
=== Monero ===
Private spend key (hex): f95df22597a1a57e53f01ebcc99e3bf960bf385a6336275fe00f3f0586dd120f
Private view key (hex): 9a60e85975eee493d02bb9a4510140b10e8b3034173e46fa04a8ddb780408c09
Public spend key (hex): 11965f4aa9f70a25b8f03c63866cce6022efa2a776821315d1506c0ed4c30146
Public view key (hex): 0ca8ea93d2382fd5eae436efa73d2be3a0f06142929b13cd3cf5b803709cb64c
Primary address: 2qQ58Yj8DehbXa6giABS3n4GGXpWPEfWo1J86KCb31yN8u7WRekjknh8EVSY8pxo1v4HDiaYg1pWeXYZGGvh8JeG11d8
```

#### Step 2: Create Monero Wallet from Keys

Using **Monero CLI** (monero-wallet-cli):

```bash
# Start monero-wallet-cli
monero-wallet-cli --testnet

# At prompt, select: 3 (restore from keys)
# Enter the private spend key (only this, not both):
f95df22597a1a57e53f01ebcc99e3bf960bf385a6336275fe00f3f0586dd120f

# The wallet will derive the view key automatically
# Give it a name: test-wallet-1
```

#### Step 3: Verify Primary Address

In monero-wallet-cli:
```
[wallet]: address
# Output should show:
# Primary address: 2qQ58Yj8DehbXa6giABS3n4GGXpWPEfWo1J86KCb31yN8u7WRekjknh8EVSY8pxo1v4HDiaYg1pWeXYZGGvh8JeG11d8
```

✅ **PASS** if address matches exactly  
❌ **FAIL** if different (check key derivation)

#### Step 4: Verify View Key

In monero-wallet-cli:
```
[wallet]: viewkey
# Output should match: 9a60e85975eee493d02bb9a4510140b10e8b3034173e46fa04a8ddb780408c09
```

✅ **PASS** if matches  
❌ **FAIL** if different

#### Test Result
- ✅ **PASS**: Primary address and view key both match
- ❌ **FAIL**: Check Ed25519 scalar reduction or Keccak-256 derivation

---

### 4️⃣ Solana (Ed25519) - 30 minutes

#### Step 1: Generate a Solana Key

```bash
cd /Users/x/Desktop/888
cargo run --manifest-path rust-app/Cargo.toml --bin rust-app 2>&1 | grep -A5 "=== Solana"
```

**Example output:**
```
=== Solana ===
Private seed (hex): 4d183c5feead109bbca0b8b9cfd2daa6ebe35d6fda3e52aba7913a2ef1ea196a
Private key (base58): 2YQAfkg5CKzRfosHwyyawSSWjSvZDXXmoHUixchJswAZB5ycqTcRwWRCWu9Q3Dt83gBoNzSkTCS6QFrY1dTtenU
Public key / address (base58): 69nuU4m1QEb9VtERKxqty2ZShWK83wzocUn1BbCrCFpA
```

#### Step 2: Import Keypair into Solana CLI

```bash
# Create solana config (if not already set up)
solana config set --url https://api.testnet.solana.com

# Create keypair file from our private key
# The private key (base58) is the full keypair
echo "[64, 5, ...]"  # Will need to convert base58 to array
# Or save as keypair directly using:
solana-keygen new -o ~/solana-test-key.json --force

# Then import or use the key
solana address --keypair ~/solana-test-key.json
```

#### Step 3: Verify Address

```bash
solana address --keypair ~/solana-test-key.json
# Output should match: 69nuU4m1QEb9VtERKxqty2ZShWK83wzocUn1BbCrCFpA
```

✅ **PASS** if address matches  
❌ **FAIL** if different

#### Step 4: Test Signing

```bash
# Sign a test message to verify the key works
solana-keygen verify $(solana address --keypair ~/solana-test-key.json) ~/test-message.txt ~/solana-test-key.json
```

✅ **PASS** if signature verifies  
❌ **FAIL** if verification fails

#### Test Result
- ✅ **PASS**: Address matches, signing works
- ❌ **FAIL**: Check Ed25519 implementation

---

### 5️⃣ Ethereum (secp256k1 + EIP-55) - 30 minutes

#### Step 1: Generate an Ethereum Key

```bash
cd /Users/x/Desktop/888
cargo run --manifest-path rust-app/Cargo.toml --bin rust-app 2>&1 | grep -A5 "=== Ethereum"
```

**Example output:**
```
=== Ethereum ===
Private key (hex): e1d53f00d25ea0557b353829a85bb256973ea5d89c7b49f5346c27b49abfddaa
Public key (uncompressed hex): 6fbfdce9eea7d83511bd133c456bb10952e371bf34c13db3ded45c95bef5a0e
Checksummed address: 0x7160a854BA41D4F3099C6a366bA0201f7756E719
```

#### Step 2: Verify with web3.py

```bash
# Install web3.py if not already installed
pip3 install web3

# Create a test script: test_ethereum.py
```

**test_ethereum.py:**
```python
from web3 import Web3

# Our private key
private_key = "0xe1d53f00d25ea0557b353829a85bb256973ea5d89c7b49f5346c27b49abfddaa"

# Create account from private key
account = Web3.eth.account.from_key(private_key)

# Get the address
address = account.address
expected_address = "0x7160a854BA41D4F3099C6a366bA0201f7756E719"

print(f"Generated address: {address}")
print(f"Expected address:  {expected_address}")
print(f"Match: {address.lower() == expected_address.lower()}")

# Verify checksummed format
web3 = Web3()
checksummed = web3.to_checksum_address(address)
print(f"Checksummed:       {checksummed}")
print(f"Matches expected:  {checksummed == expected_address}")
```

**Run it:**
```bash
python3 test_ethereum.py
```

**Expected output:**
```
Generated address: 0x7160a854ba41d4f3099c6a366ba0201f7756e719
Expected address:  0x7160a854BA41D4F3099C6a366bA0201f7756E719
Match: True
Checksummed:       0x7160a854BA41D4F3099C6a366bA0201f7756E719
Matches expected:  True
```

✅ **PASS** if checksummed address matches  
❌ **FAIL** if different (check Keccak-256 or EIP-55 implementation)

#### Step 3: Verify Signing (Optional)

```python
# Add to test_ethereum.py
message = "Hello, Ethereum!"
signature = account.sign_message({"raw": message.encode()})
print(f"Signature: {signature.signature.hex()}")

# Verify signature
recovered = Web3.eth.account.recover_message(
    {"raw": message.encode()},
    signature=signature.signature
)
print(f"Recovered address: {recovered}")
print(f"Signature valid: {recovered.lower() == address.lower()}")
```

✅ **PASS** if signature recovers correctly  
❌ **FAIL** if signature doesn't verify

#### Test Result
- ✅ **PASS**: Address matches, EIP-55 checksum correct, signing works
- ❌ **FAIL**: Check secp256k1 or Keccak-256 implementation

---

## Summary Table

After completing all tests, fill in this table:

| Chain | Test | Result | Notes |
|-------|------|--------|-------|
| Bitcoin | Address match | ✅/❌ | WIF import → address |
| Bitcoin | Pubkey match | ✅/❌ | Derived from WIF |
| Litecoin | Address match | ✅/❌ | LTC WIF prefix 0xB0 |
| Litecoin | Key accepts | ✅/❌ | Wallet accepts WIF |
| Monero | Primary address | ✅/❌ | Spend key → address |
| Monero | View key | ✅/❌ | Derived correctly |
| Solana | Address match | ✅/❌ | Base58 decode correct |
| Solana | Signing works | ✅/❌ | Ed25519 signing valid |
| Ethereum | Address match | ✅/❌ | Keccak-256 hash correct |
| Ethereum | EIP-55 checksum | ✅/❌ | Mixed-case encoding correct |

---

## Success Criteria

✅ **ALL TESTS PASS** = Ready for v1.0 Release

If any test fails:
1. **Identify the chain** that failed
2. **Document the error** (e.g., "address mismatch")
3. **Check the implementation** in `rust-app/src/main.rs`
4. **Fix the bug** and rebuild
5. **Re-test** that chain

---

## Troubleshooting

### Bitcoin/Litecoin

**Problem**: "Address doesn't match"
- Check WIF encoding (Bitcoin: 0x80, Litecoin: 0xB0)
- Verify hash160 calculation
- Confirm Bech32 encoding

### Monero

**Problem**: "Address doesn't match"
- Check Ed25519 scalar reduction
- Verify Keccak-256 derivation of view key
- Confirm custom base58 encoding (8-byte chunks)

### Solana

**Problem**: "Address doesn't match"
- Check Ed25519 keypair generation
- Verify base58 encoding
- Ensure no byte swapping

### Ethereum

**Problem**: "Address doesn't match"
- Check secp256k1 public key derivation (uncompressed, no 0x04 prefix)
- Verify Keccak-256 hash of public key
- Confirm EIP-55 checksum calculation

---

## Next Steps After Validation

✅ **If all tests pass**:
1. Update IMPLEMENTATION_SUMMARY.md with test results
2. Run `cargo audit` for security check
3. Set up CI/CD pipeline
4. Tag v1.0.0 and create GitHub release

❌ **If any tests fail**:
1. Review the failing implementation
2. Fix bugs in rust-app/src/main.rs
3. Re-test the fixed chain
4. Document the fix in git commit

---

## Time Estimate

- Bitcoin: 30 min
- Litecoin: 30 min
- Monero: 30 min
- Solana: 30 min
- Ethereum: 30 min
- **Total: 2.5 hours**

---

**Status**: Ready to validate  
**Start**: Run first chain test  
**Date**: November 10, 2025
