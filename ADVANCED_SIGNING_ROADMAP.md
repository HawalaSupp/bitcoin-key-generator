# 🔐 Advanced Signing & Security - Implementation Roadmap

## Overview

This roadmap covers the complete implementation of advanced signing and security features to achieve feature parity with Trust Wallet's wallet-core. Each section includes detailed steps, code architecture, dependencies, and testing requirements.

**Estimated Total Time:** 8-12 weeks  
**Priority Level:** 🔴 High  
**Dependencies:** Rust cryptography libraries, Swift CryptoKit, hardware wallet SDKs

---

## Table of Contents

1. [EIP-712 Typed Data Signing](#1-eip-712-typed-data-signing)
2. [Message Signing (Personal Sign)](#2-message-signing-personal-sign)
3. [EIP-7702 Transactions](#3-eip-7702-transactions)
4. [External Signature Compilation](#4-external-signature-compilation)
5. [Hardware Wallet Integration](#5-hardware-wallet-integration)
6. [Schnorr Signatures (BIP340)](#6-schnorr-signatures-bip340)
7. [Multi-Curve Support](#7-multi-curve-support)

---

## 1. EIP-712 Typed Data Signing

### 1.1 Overview
EIP-712 is a standard for typed structured data hashing and signing, used extensively by dApps for secure, human-readable signing requests (e.g., Uniswap permits, OpenSea listings, Gnosis Safe transactions).

**Reference:** https://eips.ethereum.org/EIPS/eip-712

### 1.2 Implementation Steps

#### Step 1.2.1: Create Rust EIP-712 Module
**File:** `rust-app/src/eip712/mod.rs`

```
Tasks:
├── [ ] Create eip712/ directory structure
│   ├── mod.rs
│   ├── types.rs
│   ├── encoder.rs
│   ├── hasher.rs
│   └── signer.rs
```

**Substeps:**
1. Define `Eip712Domain` struct with fields:
   - `name: String`
   - `version: String`
   - `chain_id: U256`
   - `verifying_contract: Address`
   - `salt: Option<H256>`

2. Define `Eip712Message` struct:
   - `types: HashMap<String, Vec<TypedDataField>>`
   - `primary_type: String`
   - `domain: Eip712Domain`
   - `message: serde_json::Value`

3. Define `TypedDataField`:
   - `name: String`
   - `type_name: String`

#### Step 1.2.2: Implement Type Encoding
**File:** `rust-app/src/eip712/encoder.rs`

```
Tasks:
├── [ ] Implement encodeType() - generates type string
├── [ ] Implement typeHash() - keccak256 of encoded type
├── [ ] Implement encodeData() - recursive data encoding
├── [ ] Handle atomic types (uint256, address, bytes32, bool, string, bytes)
├── [ ] Handle dynamic types (bytes, string)
├── [ ] Handle reference types (structs)
├── [ ] Handle array types (fixed and dynamic)
```

**Encoding Rules:**
- `address` → `keccak256(abi.encode(value))`
- `bool` → `uint256(value ? 1 : 0)`
- `bytes` → `keccak256(value)`
- `string` → `keccak256(bytes(value))`
- `uint256/int256` → left-padded to 32 bytes
- `bytes1...bytes32` → right-padded to 32 bytes
- `struct` → `hashStruct(value)`
- `array` → `keccak256(encodeData(item1) ++ encodeData(item2) ++ ...)`

#### Step 1.2.3: Implement Domain Separator
**File:** `rust-app/src/eip712/hasher.rs`

```rust
// Pseudocode structure
pub fn domain_separator(domain: &Eip712Domain) -> H256 {
    let type_hash = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    
    keccak256(abi_encode(&[
        type_hash,
        keccak256(domain.name),
        keccak256(domain.version),
        domain.chain_id,
        domain.verifying_contract
    ]))
}
```

```
Tasks:
├── [ ] Implement domainSeparator()
├── [ ] Handle optional salt field
├── [ ] Handle missing optional fields
├── [ ] Cache domain separator for performance
```

#### Step 1.2.4: Implement Struct Hashing
**File:** `rust-app/src/eip712/hasher.rs`

```
Tasks:
├── [ ] Implement hashStruct(primaryType, data)
├── [ ] Implement recursive type dependency resolution
├── [ ] Sort types alphabetically for deterministic encoding
├── [ ] Handle nested structs
├── [ ] Handle arrays of structs
```

**Hash Formula:**
```
hashStruct(s) = keccak256(typeHash ‖ encodeData(s))
```

#### Step 1.2.5: Implement Final Message Hash
**File:** `rust-app/src/eip712/hasher.rs`

```rust
// Final EIP-712 hash
pub fn hash_typed_data(message: &Eip712Message) -> H256 {
    let domain_separator = domain_separator(&message.domain);
    let struct_hash = hash_struct(&message.primary_type, &message.message, &message.types);
    
    keccak256(&[
        b"\x19\x01",
        domain_separator.as_bytes(),
        struct_hash.as_bytes()
    ].concat())
}
```

```
Tasks:
├── [ ] Implement EIP-712 message hash with 0x1901 prefix
├── [ ] Validate message structure
├── [ ] Return preimage hash for signing
```

#### Step 1.2.6: Implement Signing
**File:** `rust-app/src/eip712/signer.rs`

```
Tasks:
├── [ ] Implement sign_typed_data(private_key, message) -> Signature
├── [ ] Support both Legacy and EIP-155 replay protection
├── [ ] Return signature in r, s, v format
├── [ ] Support recoverable signatures
├── [ ] Implement verify_typed_data(signature, message, address) -> bool
```

#### Step 1.2.7: Create FFI Bridge
**File:** `rust-app/src/ffi.rs`

```
Tasks:
├── [ ] Add eip712_hash_typed_data(json: *const c_char) -> *mut c_char
├── [ ] Add eip712_sign_typed_data(json: *const c_char, private_key: *const c_char) -> *mut c_char
├── [ ] Add eip712_verify_typed_data(json: *const c_char, signature: *const c_char, address: *const c_char) -> bool
├── [ ] Handle JSON parsing errors gracefully
├── [ ] Return proper error codes
```

#### Step 1.2.8: Swift Integration
**File:** `swift-app/Sources/swift-app/Crypto/EIP712Signer.swift`

```
Tasks:
├── [ ] Create EIP712Message Swift model
├── [ ] Create EIP712Domain Swift model
├── [ ] Implement Codable conformance for JSON serialization
├── [ ] Create EIP712Signer class with:
│   ├── [ ] hashTypedData(message: EIP712Message) -> Data
│   ├── [ ] signTypedData(message: EIP712Message, privateKey: Data) -> EIP712Signature
│   ├── [ ] verifyTypedData(message: EIP712Message, signature: EIP712Signature, address: String) -> Bool
├── [ ] Bridge to Rust FFI functions
├── [ ] Add async/await wrappers
```

#### Step 1.2.9: UI Integration
**File:** `swift-app/Sources/swift-app/Views/SignTypedDataSheet.swift`

```
Tasks:
├── [ ] Create SignTypedDataSheet view
├── [ ] Display domain information (name, version, chain)
├── [ ] Display message fields in human-readable format
├── [ ] Syntax highlight types (addresses, amounts, etc.)
├── [ ] Show "What am I signing?" breakdown
├── [ ] Add signature confirmation flow
├── [ ] Integrate with WalletConnect requests
```

### 1.3 Testing Requirements

```
Tests to implement:
├── [ ] test_eip712_encode_simple_struct
├── [ ] test_eip712_encode_nested_struct
├── [ ] test_eip712_encode_array_of_structs
├── [ ] test_eip712_domain_separator
├── [ ] test_eip712_hash_mail_example (EIP-712 reference example)
├── [ ] test_eip712_sign_and_verify
├── [ ] test_eip712_permit_message (Uniswap permit)
├── [ ] test_eip712_opensea_order
├── [ ] test_eip712_gnosis_safe_transaction
├── [ ] test_eip712_invalid_type_handling
├── [ ] test_eip712_missing_field_handling
```

### 1.4 Dependencies

**Rust:**
- `ethereum-types` (H256, U256, Address)
- `tiny-keccak` (keccak256)
- `secp256k1` (signing)
- `serde_json` (JSON parsing)

**Swift:**
- `CryptoKit` (hashing)
- Built-in `Codable`

---

## 2. Message Signing (Personal Sign)

### 2.1 Overview
Personal message signing (eth_sign, personal_sign) allows signing arbitrary messages with the standard Ethereum prefix. Used for authentication, off-chain voting, and simple signatures.

**Prefix:** `"\x19Ethereum Signed Message:\n" + message.length + message`

### 2.2 Implementation Steps

#### Step 2.2.1: Rust Message Signer Module
**File:** `rust-app/src/message_signer/mod.rs`

```
Tasks:
├── [ ] Create message_signer/ directory
│   ├── mod.rs
│   ├── ethereum.rs
│   ├── tezos.rs
│   ├── solana.rs
│   └── cosmos.rs
```

#### Step 2.2.2: Ethereum Personal Sign
**File:** `rust-app/src/message_signer/ethereum.rs`

```rust
// Pseudocode
pub fn personal_sign(message: &[u8], private_key: &[u8]) -> Signature {
    let prefix = format!("\x19Ethereum Signed Message:\n{}", message.len());
    let prefixed_message = [prefix.as_bytes(), message].concat();
    let hash = keccak256(&prefixed_message);
    sign_hash(&hash, private_key)
}
```

```
Tasks:
├── [ ] Implement personal_sign(message, private_key) -> Signature
├── [ ] Implement personal_sign_hash(message) -> H256
├── [ ] Implement verify_personal_sign(message, signature, address) -> bool
├── [ ] Implement recover_address(message, signature) -> Address
├── [ ] Support hex-encoded messages
├── [ ] Support UTF-8 messages
├── [ ] Handle EIP-155 chain ID in v value
```

#### Step 2.2.3: Tezos Message Signing
**File:** `rust-app/src/message_signer/tezos.rs`

```
Reference: https://tezostaquito.io/docs/signing/

Tasks:
├── [ ] Implement format_message(message: &str, dapp_url: &str) -> String
│   └── Format: "Tezos Signed Message: {dapp_url} {timestamp} {message}"
├── [ ] Implement input_to_payload(formatted_message: &str) -> Vec<u8>
│   └── Encode with Micheline format
├── [ ] Implement sign_message(payload: &[u8], private_key: &[u8]) -> String
│   └── Return base58 encoded signature
├── [ ] Implement verify_message(payload: &[u8], signature: &str, public_key: &str) -> bool
```

#### Step 2.2.4: Solana Message Signing
**File:** `rust-app/src/message_signer/solana.rs`

```
Tasks:
├── [ ] Implement sign_message(message: &[u8], private_key: &[u8]) -> Signature
│   └── Ed25519 signature (no prefix for Solana)
├── [ ] Implement verify_message(message: &[u8], signature: &[u8], public_key: &[u8]) -> bool
├── [ ] Support off-chain message signing for Phantom/Backpack
```

#### Step 2.2.5: Cosmos Message Signing
**File:** `rust-app/src/message_signer/cosmos.rs`

```
Tasks:
├── [ ] Implement sign_arbitrary(message: &[u8], private_key: &[u8]) -> Signature
├── [ ] Implement ADR-036 off-chain message signing
├── [ ] Support Keplr-compatible message format
```

#### Step 2.2.6: FFI Bridge Updates
**File:** `rust-app/src/ffi.rs`

```
Tasks:
├── [ ] Add eth_personal_sign(message, private_key) -> signature
├── [ ] Add eth_personal_verify(message, signature, address) -> bool
├── [ ] Add eth_personal_recover(message, signature) -> address
├── [ ] Add tezos_sign_message(message, dapp_url, private_key) -> signature
├── [ ] Add solana_sign_message(message, private_key) -> signature
├── [ ] Add cosmos_sign_arbitrary(message, private_key) -> signature
```

#### Step 2.2.7: Swift Integration
**File:** `swift-app/Sources/swift-app/Crypto/MessageSigner.swift`

```swift
// Protocol for chain-specific message signing
protocol MessageSigner {
    func signMessage(_ message: Data, privateKey: Data) throws -> Data
    func verifyMessage(_ message: Data, signature: Data, address: String) throws -> Bool
    func recoverAddress(_ message: Data, signature: Data) throws -> String
}
```

```
Tasks:
├── [ ] Create MessageSigner protocol
├── [ ] Implement EthereumMessageSigner
├── [ ] Implement TezosMessageSigner
├── [ ] Implement SolanaMessageSigner
├── [ ] Implement CosmosMessageSigner
├── [ ] Create MessageSignerFactory for chain dispatch
```

#### Step 2.2.8: UI Integration
**File:** `swift-app/Sources/swift-app/Views/SignMessageSheet.swift`

```
Tasks:
├── [ ] Create SignMessageSheet view
├── [ ] Display message content (with hex/text toggle)
├── [ ] Show signing address
├── [ ] Display chain-specific prefix
├── [ ] Add "Sign" and "Reject" buttons
├── [ ] Show signature result
├── [ ] Copy signature to clipboard option
```

### 2.3 Testing Requirements

```
Tests:
├── [ ] test_eth_personal_sign_text
├── [ ] test_eth_personal_sign_hex
├── [ ] test_eth_personal_verify_valid
├── [ ] test_eth_personal_verify_invalid
├── [ ] test_eth_personal_recover
├── [ ] test_tezos_format_message
├── [ ] test_tezos_sign_message
├── [ ] test_solana_sign_message
├── [ ] test_cosmos_adr036_sign
```

---

## 3. EIP-7702 Transactions

### 3.1 Overview
EIP-7702 allows EOAs to temporarily delegate to contract code during a transaction, enabling smart account features without permanent migration. This is the successor to EIP-3074.

**Reference:** https://eips.ethereum.org/EIPS/eip-7702

### 3.2 Implementation Steps

#### Step 3.2.1: Understand EIP-7702 Structure
```
EIP-7702 Transaction Type: 0x04

Fields:
├── chain_id
├── nonce
├── max_priority_fee_per_gas
├── max_fee_per_gas
├── gas_limit
├── destination
├── value
├── data
├── access_list
├── authorization_list  <-- NEW: List of authorizations
│   └── Authorization:
│       ├── chain_id
│       ├── address (contract to delegate to)
│       ├── nonce
│       ├── y_parity, r, s (signature)
```

#### Step 3.2.2: Create Rust EIP-7702 Module
**File:** `rust-app/src/evm/eip7702.rs`

```
Tasks:
├── [ ] Define Authorization struct
│   ├── chain_id: u64
│   ├── address: Address
│   ├── nonce: u64
│   ├── signature: Signature
├── [ ] Define TransactionEip7702 struct
├── [ ] Implement RLP encoding for Authorization
├── [ ] Implement RLP encoding for TransactionEip7702
├── [ ] Implement authorization signing
│   └── sign(keccak256(0x05 || rlp([chain_id, address, nonce])))
```

#### Step 3.2.3: Implement Authorization Signing
**File:** `rust-app/src/evm/eip7702.rs`

```rust
// Pseudocode
pub fn sign_authorization(
    chain_id: u64,
    contract_address: Address,
    nonce: u64,
    private_key: &[u8]
) -> Authorization {
    let message = rlp_encode(&(chain_id, contract_address, nonce));
    let hash = keccak256(&[&[0x05], &message].concat());
    let signature = secp256k1_sign(&hash, private_key);
    
    Authorization {
        chain_id,
        address: contract_address,
        nonce,
        signature,
    }
}
```

```
Tasks:
├── [ ] Implement sign_authorization()
├── [ ] Implement verify_authorization()
├── [ ] Implement batch authorization signing
```

#### Step 3.2.4: Implement Transaction Building
**File:** `rust-app/src/evm/eip7702.rs`

```
Tasks:
├── [ ] Implement build_eip7702_transaction()
├── [ ] Implement sign_eip7702_transaction()
├── [ ] Handle multiple authorizations
├── [ ] Implement transaction hash calculation
├── [ ] Implement RLP serialization for broadcast
```

#### Step 3.2.5: Update Ethereum Wallet
**File:** `rust-app/src/ethereum_wallet.rs`

```
Tasks:
├── [ ] Add EIP-7702 transaction type support
├── [ ] Add create_authorization() method
├── [ ] Add send_eip7702_transaction() method
├── [ ] Update transaction signing to handle type 0x04
```

#### Step 3.2.6: FFI Bridge
**File:** `rust-app/src/ffi.rs`

```
Tasks:
├── [ ] Add eip7702_create_authorization(chain_id, address, nonce, private_key) -> auth_json
├── [ ] Add eip7702_sign_transaction(tx_json, authorizations_json, private_key) -> signed_tx
├── [ ] Add eip7702_decode_authorization(auth_bytes) -> auth_json
```

#### Step 3.2.7: Swift Integration
**File:** `swift-app/Sources/swift-app/Crypto/EIP7702.swift`

```
Tasks:
├── [ ] Create Authorization struct
├── [ ] Create EIP7702Transaction struct
├── [ ] Implement authorization creation
├── [ ] Implement transaction signing
├── [ ] Integrate with TransactionBuilder
```

### 3.3 Testing Requirements

```
Tests:
├── [ ] test_eip7702_authorization_signing
├── [ ] test_eip7702_authorization_rlp_encoding
├── [ ] test_eip7702_transaction_building
├── [ ] test_eip7702_transaction_signing
├── [ ] test_eip7702_multiple_authorizations
├── [ ] test_eip7702_hash_calculation
```

---

## 4. External Signature Compilation

### 4.1 Overview
External signature compilation allows generating pre-image hashes, signing them externally (e.g., with hardware wallets), and then compiling the final transaction. This is crucial for hardware wallet support and air-gapped signing.

**Flow:**
1. Generate pre-image hash from unsigned transaction
2. Sign hash externally (hardware wallet, air-gapped device)
3. Compile signature with transaction to create signed transaction

### 4.2 Implementation Steps

#### Step 4.2.1: Create Pre-Image Hash Module
**File:** `rust-app/src/signing/preimage.rs`

```
Tasks:
├── [ ] Create preimage/ directory
│   ├── mod.rs
│   ├── bitcoin.rs
│   ├── ethereum.rs
│   ├── cosmos.rs
│   └── solana.rs
```

#### Step 4.2.2: Bitcoin Pre-Image Hashing
**File:** `rust-app/src/signing/preimage/bitcoin.rs`

```
Tasks:
├── [ ] Implement get_sighash(tx, input_index, script_code, value, sighash_type) -> H256
├── [ ] Support SIGHASH_ALL, SIGHASH_NONE, SIGHASH_SINGLE
├── [ ] Support SIGHASH_ANYONECANPAY modifier
├── [ ] Support BIP-143 (SegWit) sighash
├── [ ] Support BIP-341 (Taproot) sighash
├── [ ] Return list of hashes for multi-input transactions
```

#### Step 4.2.3: Ethereum Pre-Image Hashing
**File:** `rust-app/src/signing/preimage/ethereum.rs`

```
Tasks:
├── [ ] Implement get_transaction_hash(unsigned_tx) -> H256
├── [ ] Support Legacy transactions
├── [ ] Support EIP-2930 (access list) transactions
├── [ ] Support EIP-1559 transactions
├── [ ] Support EIP-7702 transactions
```

#### Step 4.2.4: Cosmos Pre-Image Hashing
**File:** `rust-app/src/signing/preimage/cosmos.rs`

```
Tasks:
├── [ ] Implement get_sign_doc_hash(sign_doc) -> H256
├── [ ] Support Amino encoding
├── [ ] Support Protobuf (Direct) encoding
├── [ ] Support Textual signing
```

#### Step 4.2.5: Solana Pre-Image Hashing
**File:** `rust-app/src/signing/preimage/solana.rs`

```
Tasks:
├── [ ] Implement get_message_hash(message) -> H256
├── [ ] Support legacy messages
├── [ ] Support versioned messages (v0)
├── [ ] Support off-chain messages
```

#### Step 4.2.6: Create Signature Compiler
**File:** `rust-app/src/signing/compiler.rs`

```
Tasks:
├── [ ] Implement compile_bitcoin_transaction(unsigned_tx, signatures, public_keys) -> signed_tx
├── [ ] Implement compile_ethereum_transaction(unsigned_tx, signature) -> signed_tx
├── [ ] Implement compile_cosmos_transaction(unsigned_tx, signature) -> signed_tx
├── [ ] Implement compile_solana_transaction(message, signatures) -> signed_tx
├── [ ] Validate signature matches expected public key
├── [ ] Return serialized transaction ready for broadcast
```

#### Step 4.2.7: FFI Bridge
**File:** `rust-app/src/ffi.rs`

```
Tasks:
├── [ ] Add preimage_hashes(chain, unsigned_tx_json) -> hashes_json
│   └── Returns: { hashes: [H256], public_key_hashes: [H160] }
├── [ ] Add compile_with_signatures(chain, unsigned_tx_json, signatures_json, public_keys_json) -> signed_tx_hex
├── [ ] Add validate_signature(chain, hash, signature, public_key) -> bool
```

#### Step 4.2.8: Swift Integration
**File:** `swift-app/Sources/swift-app/Crypto/ExternalSigner.swift`

```swift
// Protocol for external signing
protocol ExternalSigner {
    func getPreImageHashes(transaction: UnsignedTransaction) async throws -> [PreImageHash]
    func compileWithSignatures(transaction: UnsignedTransaction, signatures: [Signature]) async throws -> SignedTransaction
}

struct PreImageHash {
    let hash: Data
    let publicKeyHash: Data
    let inputIndex: Int?  // For UTXO chains
    let description: String  // Human-readable description
}
```

```
Tasks:
├── [ ] Create ExternalSigner protocol
├── [ ] Implement BitcoinExternalSigner
├── [ ] Implement EthereumExternalSigner
├── [ ] Implement CosmosExternalSigner
├── [ ] Implement SolanaExternalSigner
├── [ ] Create ExternalSigningFlow coordinator
```

#### Step 4.2.9: UI Integration
**File:** `swift-app/Sources/swift-app/Views/ExternalSigningSheet.swift`

```
Tasks:
├── [ ] Create ExternalSigningSheet view
├── [ ] Display hash(es) to sign as QR code
├── [ ] Accept signature input via:
│   ├── [ ] QR code scanning
│   ├── [ ] Manual hex input
│   ├── [ ] Clipboard paste
├── [ ] Validate signature format
├── [ ] Compile and broadcast transaction
├── [ ] Show transaction result
```

### 4.3 Testing Requirements

```
Tests:
├── [ ] test_bitcoin_preimage_p2pkh
├── [ ] test_bitcoin_preimage_p2wpkh
├── [ ] test_bitcoin_preimage_p2tr
├── [ ] test_bitcoin_compile_signatures
├── [ ] test_ethereum_preimage_legacy
├── [ ] test_ethereum_preimage_eip1559
├── [ ] test_ethereum_compile_signature
├── [ ] test_cosmos_preimage
├── [ ] test_solana_preimage
├── [ ] test_invalid_signature_rejection
```

---

## 5. Hardware Wallet Integration

### 5.1 Overview
Hardware wallet integration allows users to securely sign transactions using devices like Ledger and Trezor, keeping private keys offline.

**Supported Devices:**
- Ledger Nano S/X/S Plus (via USB/Bluetooth)
- Trezor Model T/One (via USB)

### 5.2 Implementation Steps

#### Step 5.2.1: Create Hardware Wallet Abstraction
**File:** `swift-app/Sources/swift-app/Services/HardwareWallet/HardwareWalletProtocol.swift`

```swift
protocol HardwareWallet {
    var name: String { get }
    var isConnected: Bool { get }
    var supportedChains: [ChainInfo] { get }
    
    func connect() async throws
    func disconnect() async throws
    func getPublicKey(path: String) async throws -> Data
    func getAddress(path: String, chain: ChainInfo, display: Bool) async throws -> String
    func signTransaction(path: String, transaction: UnsignedTransaction) async throws -> Data
    func signMessage(path: String, message: Data) async throws -> Data
    func signTypedData(path: String, typedData: EIP712Message) async throws -> Data
}
```

```
Tasks:
├── [ ] Define HardwareWallet protocol
├── [ ] Define HardwareWalletError enum
├── [ ] Define HardwareWalletConnection protocol
├── [ ] Create HardwareWalletManager class
```

#### Step 5.2.2: Ledger Integration - Transport Layer
**File:** `swift-app/Sources/swift-app/Services/HardwareWallet/Ledger/LedgerTransport.swift`

```
Tasks:
├── [ ] Implement USB transport using IOKit
├── [ ] Implement Bluetooth transport using CoreBluetooth
├── [ ] Implement HID framing protocol
├── [ ] Handle device enumeration
├── [ ] Handle connection/disconnection events
├── [ ] Implement APDU command/response handling
```

**APDU Structure:**
```
Command: CLA | INS | P1 | P2 | LC | DATA | LE
Response: DATA | SW1 | SW2
```

#### Step 5.2.3: Ledger Integration - App Protocols
**File:** `swift-app/Sources/swift-app/Services/HardwareWallet/Ledger/LedgerApps/`

```
Tasks:
├── [ ] LedgerBitcoinApp.swift
│   ├── [ ] Get public key (command 0x40)
│   ├── [ ] Get address (command 0x40 with display)
│   ├── [ ] Sign transaction (commands 0xE0, 0x44, etc.)
│   ├── [ ] Sign message (command 0xE0)
├── [ ] LedgerEthereumApp.swift
│   ├── [ ] Get public key (command 0x02)
│   ├── [ ] Sign transaction (command 0x04)
│   ├── [ ] Sign personal message (command 0x08)
│   ├── [ ] Sign EIP-712 (command 0x0C)
├── [ ] LedgerSolanaApp.swift
│   ├── [ ] Get public key
│   ├── [ ] Sign transaction
│   ├── [ ] Sign off-chain message
├── [ ] LedgerCosmosApp.swift
│   ├── [ ] Get public key
│   ├── [ ] Sign transaction (Amino/Protobuf)
```

#### Step 5.2.4: Ledger Wallet Implementation
**File:** `swift-app/Sources/swift-app/Services/HardwareWallet/Ledger/LedgerWallet.swift`

```
Tasks:
├── [ ] Implement HardwareWallet protocol
├── [ ] Handle app selection (APDU 0xB0)
├── [ ] Check app version compatibility
├── [ ] Handle user confirmation on device
├── [ ] Parse response data
├── [ ] Handle error codes (0x6985 = user rejected, etc.)
```

#### Step 5.2.5: Trezor Integration - Transport Layer
**File:** `swift-app/Sources/swift-app/Services/HardwareWallet/Trezor/TrezorTransport.swift`

```
Tasks:
├── [ ] Implement USB WebHID-like protocol
├── [ ] Implement Protobuf message encoding
├── [ ] Handle device enumeration
├── [ ] Handle session management
├── [ ] Implement message type routing
```

#### Step 5.2.6: Trezor Integration - Message Handlers
**File:** `swift-app/Sources/swift-app/Services/HardwareWallet/Trezor/TrezorMessages/`

```
Tasks:
├── [ ] Generate Swift types from trezor-common protobuf definitions
├── [ ] Implement message encoding/decoding
├── [ ] Handle message types:
│   ├── [ ] GetPublicKey / PublicKey
│   ├── [ ] GetAddress / Address
│   ├── [ ] SignTx / TxRequest / TxAck (Bitcoin)
│   ├── [ ] EthereumSignTx / EthereumTxRequest
│   ├── [ ] EthereumSignMessage / EthereumMessageSignature
│   ├── [ ] EthereumSignTypedData
│   ├── [ ] SolanaSignTx
```

#### Step 5.2.7: Trezor Wallet Implementation
**File:** `swift-app/Sources/swift-app/Services/HardwareWallet/Trezor/TrezorWallet.swift`

```
Tasks:
├── [ ] Implement HardwareWallet protocol
├── [ ] Handle Initialize / Features messages
├── [ ] Handle PIN entry (PassphraseRequest / PassphraseAck)
├── [ ] Handle button confirmation
├── [ ] Parse response messages
├── [ ] Handle error types
```

#### Step 5.2.8: Hardware Wallet Manager
**File:** `swift-app/Sources/swift-app/Services/HardwareWallet/HardwareWalletManager.swift`

```
Tasks:
├── [ ] Implement device discovery
├── [ ] Maintain list of connected devices
├── [ ] Handle device connect/disconnect events
├── [ ] Route signing requests to appropriate device
├── [ ] Cache public keys for quick address lookup
├── [ ] Persist device pairings
```

#### Step 5.2.9: UI Integration
**Files:**
- `swift-app/Sources/swift-app/Views/HardwareWallet/HardwareWalletSetupSheet.swift`
- `swift-app/Sources/swift-app/Views/HardwareWallet/HardwareWalletSigningSheet.swift`
- `swift-app/Sources/swift-app/Views/HardwareWallet/DeviceSelectionView.swift`

```
Tasks:
├── [ ] Create device pairing flow
│   ├── [ ] Device discovery screen
│   ├── [ ] Connection progress indicator
│   ├── [ ] App selection prompt
│   ├── [ ] Address verification screen
├── [ ] Create signing flow
│   ├── [ ] Transaction preview
│   ├── [ ] "Confirm on device" prompt
│   ├── [ ] Success/failure result
├── [ ] Add hardware wallet account type to wallet creation
├── [ ] Display hardware wallet icon on account cards
```

#### Step 5.2.10: Update Existing Flows
```
Tasks:
├── [ ] Update SendView to support hardware wallet signing
├── [ ] Update SwapView to support hardware wallet signing
├── [ ] Update WalletConnectService for hardware wallet requests
├── [ ] Add "Sign with Hardware Wallet" option in settings
```

### 5.3 Testing Requirements

```
Tests:
├── [ ] test_ledger_apdu_encoding
├── [ ] test_ledger_apdu_decoding
├── [ ] test_ledger_get_public_key
├── [ ] test_ledger_sign_transaction
├── [ ] test_trezor_protobuf_encoding
├── [ ] test_trezor_get_public_key
├── [ ] test_trezor_sign_transaction
├── [ ] test_hardware_wallet_manager_discovery
├── [ ] test_hardware_wallet_user_rejection_handling

Integration tests (require physical device):
├── [ ] integration_test_ledger_bitcoin_signing
├── [ ] integration_test_ledger_ethereum_signing
├── [ ] integration_test_trezor_bitcoin_signing
├── [ ] integration_test_trezor_ethereum_signing
```

### 5.4 Dependencies

**Swift:**
- `IOKit` (USB communication)
- `CoreBluetooth` (Bluetooth Low Energy)
- `SwiftProtobuf` (Trezor messages)

---

## 6. Schnorr Signatures (BIP340)

### 6.1 Overview
Schnorr signatures (BIP-340) are used for Bitcoin Taproot (BIP-341) and offer smaller signatures, batch verification, and improved security properties.

**Reference:** 
- BIP-340: https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki
- BIP-341: https://github.com/bitcoin/bips/blob/master/bip-0341.mediawiki

### 6.2 Implementation Steps

#### Step 6.2.1: Rust Schnorr Module
**File:** `rust-app/src/crypto/schnorr.rs`

```
Tasks:
├── [ ] Implement BIP-340 tagged hash
│   └── tagged_hash(tag, msg) = SHA256(SHA256(tag) || SHA256(tag) || msg)
├── [ ] Implement key generation (x-only public key)
├── [ ] Implement nonce generation (RFC 6979 + aux randomness)
├── [ ] Implement signing algorithm
├── [ ] Implement verification algorithm
├── [ ] Implement batch verification
```

**BIP-340 Signing Algorithm:**
```
sign(secret_key, message, aux_rand):
1. d' = int(secret_key)
2. P = d' * G
3. d = d' if has_even_y(P) else n - d'
4. t = xor(bytes(d), tagged_hash("BIP0340/aux", aux_rand))
5. k' = int(tagged_hash("BIP0340/nonce", t || bytes(P) || message)) mod n
6. R = k' * G
7. k = k' if has_even_y(R) else n - k'
8. e = int(tagged_hash("BIP0340/challenge", bytes(R) || bytes(P) || message)) mod n
9. sig = bytes(R) || bytes((k + e * d) mod n)
return sig
```

#### Step 6.2.2: Taproot Key Tweaking
**File:** `rust-app/src/crypto/taproot.rs`

```
Tasks:
├── [ ] Implement taproot internal key generation
├── [ ] Implement tweak hash calculation
│   └── tweak = tagged_hash("TapTweak", internal_key || merkle_root)
├── [ ] Implement key tweaking
│   └── output_key = internal_key + tweak * G
├── [ ] Implement script tree merkle root calculation
├── [ ] Implement control block construction
```

#### Step 6.2.3: Taproot Signature Generation
**File:** `rust-app/src/bitcoin/taproot_signer.rs`

```
Tasks:
├── [ ] Implement key-path spending signature
├── [ ] Implement script-path spending signature
├── [ ] Implement sighash calculation (BIP-341)
├── [ ] Support SIGHASH_DEFAULT (all inputs, all outputs)
├── [ ] Support all sighash types
├── [ ] Implement signature with aux randomness
```

#### Step 6.2.4: Update Bitcoin Wallet
**File:** `rust-app/src/bitcoin_wallet.rs`

```
Tasks:
├── [ ] Add P2TR address generation
├── [ ] Add Taproot UTXO spending
├── [ ] Add Taproot transaction building
├── [ ] Update fee estimation for witness size
├── [ ] Support Taproot in PSBT
```

#### Step 6.2.5: FFI Bridge
**File:** `rust-app/src/ffi.rs`

```
Tasks:
├── [ ] Add schnorr_sign(message, private_key, aux_rand) -> signature
├── [ ] Add schnorr_verify(message, signature, public_key) -> bool
├── [ ] Add taproot_tweak_public_key(internal_key, merkle_root) -> output_key
├── [ ] Add taproot_sign_key_spend(tx_hash, private_key) -> signature
```

#### Step 6.2.6: Swift Integration
**File:** `swift-app/Sources/swift-app/Crypto/SchnorrSigner.swift`

```
Tasks:
├── [ ] Create SchnorrSigner class
├── [ ] Implement sign(message:, privateKey:, auxRand:) -> signature
├── [ ] Implement verify(message:, signature:, publicKey:) -> Bool
├── [ ] Create TaprootSigner class
├── [ ] Integrate with Bitcoin transaction signing
```

### 6.3 Testing Requirements

```
Tests:
├── [ ] test_schnorr_sign_bip340_vectors
├── [ ] test_schnorr_verify_bip340_vectors
├── [ ] test_schnorr_batch_verify
├── [ ] test_taproot_tweak
├── [ ] test_taproot_key_spend
├── [ ] test_taproot_script_spend
├── [ ] test_taproot_sighash
```

**BIP-340 Test Vectors:** Use official test vectors from BIP-340 specification.

---

## 7. Multi-Curve Support

### 7.1 Overview
Different blockchains use different elliptic curves. Full wallet support requires implementing multiple curve types.

**Curves:**
- `secp256k1`: Bitcoin, Ethereum, BNB, etc.
- `ed25519`: Solana, Stellar, Cardano, TON, Near, Aptos, Sui
- `sr25519`: Polkadot, Kusama
- `nist256p1` (secp256r1/P-256): NEO, some hardware wallets
- `curve25519`: Key exchange

### 7.2 Implementation Steps

#### Step 7.2.1: Create Crypto Abstraction Layer
**File:** `rust-app/src/crypto/curves/mod.rs`

```rust
pub trait EllipticCurve {
    type PrivateKey;
    type PublicKey;
    type Signature;
    
    fn generate_keypair(seed: &[u8]) -> (Self::PrivateKey, Self::PublicKey);
    fn public_key_from_private(private_key: &Self::PrivateKey) -> Self::PublicKey;
    fn sign(private_key: &Self::PrivateKey, message: &[u8]) -> Self::Signature;
    fn verify(public_key: &Self::PublicKey, message: &[u8], signature: &Self::Signature) -> bool;
}
```

```
Tasks:
├── [ ] Define EllipticCurve trait
├── [ ] Define CurveType enum (Secp256k1, Ed25519, Sr25519, Secp256r1)
├── [ ] Create curve dispatcher
```

#### Step 7.2.2: secp256k1 Implementation
**File:** `rust-app/src/crypto/curves/secp256k1.rs`

```
Tasks:
├── [ ] Implement EllipticCurve trait for Secp256k1
├── [ ] Support compressed and uncompressed public keys
├── [ ] Support recoverable signatures (v, r, s)
├── [ ] Support DER signature encoding
├── [ ] Implement ECDH for shared secret derivation
```

#### Step 7.2.3: ed25519 Implementation
**File:** `rust-app/src/crypto/curves/ed25519.rs`

```
Tasks:
├── [ ] Implement EllipticCurve trait for Ed25519
├── [ ] Support standard Ed25519 (RFC 8032)
├── [ ] Support Ed25519-SHA512 variant (Cardano)
├── [ ] Support Ed25519-Blake2b variant
├── [ ] Implement key derivation (SLIP-0010)
```

#### Step 7.2.4: sr25519 Implementation
**File:** `rust-app/src/crypto/curves/sr25519.rs`

```
Tasks:
├── [ ] Implement EllipticCurve trait for Sr25519
├── [ ] Implement Ristretto255 point encoding
├── [ ] Implement VRF (Verifiable Random Function)
├── [ ] Implement hard and soft key derivation
├── [ ] Use schnorrkel library
```

#### Step 7.2.5: secp256r1 (P-256) Implementation
**File:** `rust-app/src/crypto/curves/secp256r1.rs`

```
Tasks:
├── [ ] Implement EllipticCurve trait for Secp256r1
├── [ ] Support ECDSA signing
├── [ ] Support hardware security module compatibility
├── [ ] Implement key exchange (ECDH)
```

#### Step 7.2.6: Key Derivation Updates
**File:** `rust-app/src/crypto/derivation.rs`

```
Tasks:
├── [ ] Implement BIP-32 for secp256k1
├── [ ] Implement SLIP-0010 for ed25519
├── [ ] Implement SLIP-0010 for secp256r1
├── [ ] Implement Substrate-style derivation for sr25519
├── [ ] Create unified derivation interface
```

#### Step 7.2.7: FFI Bridge
**File:** `rust-app/src/ffi.rs`

```
Tasks:
├── [ ] Add curve_generate_keypair(curve_type, seed) -> keypair_json
├── [ ] Add curve_sign(curve_type, private_key, message) -> signature
├── [ ] Add curve_verify(curve_type, public_key, message, signature) -> bool
├── [ ] Add curve_derive_child(curve_type, parent_key, path) -> child_key
```

#### Step 7.2.8: Swift Integration
**File:** `swift-app/Sources/swift-app/Crypto/CurveManager.swift`

```swift
enum CurveType {
    case secp256k1
    case ed25519
    case sr25519
    case secp256r1
}

protocol CurveSigner {
    static var curveType: CurveType { get }
    static func sign(message: Data, privateKey: Data) throws -> Data
    static func verify(message: Data, signature: Data, publicKey: Data) throws -> Bool
}
```

```
Tasks:
├── [ ] Create CurveType enum
├── [ ] Create CurveSigner protocol
├── [ ] Implement Secp256k1Signer
├── [ ] Implement Ed25519Signer
├── [ ] Implement Sr25519Signer
├── [ ] Implement Secp256r1Signer
├── [ ] Create CurveSignerFactory
```

### 7.3 Testing Requirements

```
Tests:
├── [ ] test_secp256k1_sign_verify
├── [ ] test_secp256k1_recover_public_key
├── [ ] test_ed25519_sign_verify
├── [ ] test_ed25519_solana_vectors
├── [ ] test_sr25519_sign_verify
├── [ ] test_sr25519_vrf
├── [ ] test_secp256r1_sign_verify
├── [ ] test_cross_curve_isolation
├── [ ] test_bip32_derivation
├── [ ] test_slip10_derivation
├── [ ] test_substrate_derivation
```

### 7.4 Dependencies

**Rust:**
- `secp256k1` (Bitcoin secp256k1 library)
- `ed25519-dalek` (Ed25519)
- `schnorrkel` (Sr25519/Ristretto)
- `p256` (NIST P-256/secp256r1)
- `curve25519-dalek` (Curve25519)

---

## Summary Checklist

### Phase 1: Foundation (Weeks 1-2)
- [x] Set up crypto module structure in Rust
- [x] Implement multi-curve abstraction
- [x] Implement secp256k1 and ed25519 curves
- [x] Create FFI bridge for crypto operations

### Phase 2: Message Signing (Weeks 3-4)
- [x] Implement Ethereum personal_sign
- [x] Implement EIP-712 typed data signing
- [x] Add chain-specific message signing (Tezos, Solana, Cosmos)
- [x] Create Swift integration layer

### Phase 3: External Signatures (Weeks 5-6)
- [x] Implement pre-image hash generation
- [x] Implement signature compilation
- [x] Create external signing flow
- [x] Add QR code support for air-gapped signing

### Phase 4: Hardware Wallets (Weeks 7-10)
- [x] Implement Ledger transport layer
- [x] Implement Ledger app protocols
- [x] Implement Trezor transport layer
- [x] Implement Trezor message handlers
- [x] Create hardware wallet UI flows

### Phase 5: Advanced Features (Weeks 11-12)
- [x] Implement Schnorr signatures (BIP-340)
- [x] Implement EIP-7702 transactions
- [x] Add sr25519 and secp256r1 curves
- [x] Complete testing and documentation

---

## Appendix A: Test Vectors

### EIP-712 Mail Example
```json
{
  "types": {
    "EIP712Domain": [
      {"name": "name", "type": "string"},
      {"name": "version", "type": "string"},
      {"name": "chainId", "type": "uint256"},
      {"name": "verifyingContract", "type": "address"}
    ],
    "Person": [
      {"name": "name", "type": "string"},
      {"name": "wallet", "type": "address"}
    ],
    "Mail": [
      {"name": "from", "type": "Person"},
      {"name": "to", "type": "Person"},
      {"name": "contents", "type": "string"}
    ]
  },
  "primaryType": "Mail",
  "domain": {
    "name": "Ether Mail",
    "version": "1",
    "chainId": 1,
    "verifyingContract": "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC"
  },
  "message": {
    "from": {"name": "Cow", "wallet": "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826"},
    "to": {"name": "Bob", "wallet": "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB"},
    "contents": "Hello, Bob!"
  }
}
```

**Expected Hash:** `0xbe609aee343fb3c4b28e1df9e632fca64fcfaede20f02e86244efddf30957bd2`

### BIP-340 Schnorr Test Vector #0
```
secret_key: 0x0000000000000000000000000000000000000000000000000000000000000003
public_key: 0xF9308A019258C31049344F85F89D5229B531C845836F99B08601F113BCE036F9
aux_rand:   0x0000000000000000000000000000000000000000000000000000000000000000
message:    0x0000000000000000000000000000000000000000000000000000000000000000
signature:  0xE907831F80848D1069A5371B402410364BDF1C5F8307B0084C55F1CE2DCA821525F66A4A85EA8B71E482A74F382D2CE5EBEEE8FDB2172F477DF4900D310536C0
```

---

## Appendix B: Error Codes

```swift
enum SigningError: Int, Error {
    case invalidPrivateKey = 1001
    case invalidPublicKey = 1002
    case invalidSignature = 1003
    case invalidMessage = 1004
    case signingFailed = 1005
    case verificationFailed = 1006
    case unsupportedCurve = 1007
    case unsupportedChain = 1008
    case hardwareWalletNotConnected = 2001
    case hardwareWalletUserRejected = 2002
    case hardwareWalletAppNotOpen = 2003
    case hardwareWalletTimeout = 2004
    case eip712InvalidTypes = 3001
    case eip712MissingField = 3002
    case eip712InvalidDomain = 3003
}
```

---

*Last Updated: January 18, 2026*
*Version: 1.0*
