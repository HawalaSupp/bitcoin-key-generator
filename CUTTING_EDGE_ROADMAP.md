# 🚀 Hawala Cutting-Edge Feature Roadmap

**Created:** January 30, 2026  
**Objective:** Complete all partial features and implement cutting-edge wallet capabilities  
**Timeline:** 12 Weeks  
**Philosophy:** No half-implementations. Every feature is production-ready or not shipped.

---

## 📊 Executive Summary

| Category | Features | Weeks |
|----------|----------|-------|
| **Phase 1: Complete Existing Partials** | 15 features | Weeks 1-3 |
| **Phase 2: Security & Trust** | 4 features | Weeks 4-5 |
| **Phase 3: User Experience** | 5 features | Weeks 6-7 |
| **Phase 4: Cutting Edge** | 4 features | Weeks 8-11 |
| **Phase 5: Polish & QA** | Testing & hardening | Week 12 |

**Total New/Completed Features:** 28

---

## 🔴 Phase 1: Complete Existing Partial Implementations (Weeks 1-3)

These features exist in the codebase but are incomplete. Goal: 100% functional.

### 1.1 Bitcoin RBF Transaction Cancellation
**Current State:** `SpeedUpTransactionSheet.swift` exists, RBF sequence set in `BitcoinTransaction.swift`, but throws `featureInProgress`  
**Files:** `rust-app/src/bitcoin_wallet.rs`, `swift-app/Sources/swift-app/Views/SpeedUpTransactionSheet.swift`

**Rust Backend Tasks:**
```rust
// rust-app/src/tx/rbf.rs (NEW)
pub struct RBFManager;

impl RBFManager {
    /// Check if transaction is RBF-enabled (sequence < 0xfffffffe)
    pub fn is_rbf_enabled(tx: &BitcoinTransaction) -> bool;
    
    /// Create replacement transaction sending to self with higher fee
    pub fn create_cancellation_tx(
        original_txid: &str,
        original_utxos: &[UTXO],
        return_address: &str,
        new_fee_rate: u64,
        private_key: &str,
    ) -> HawalaResult<String>;
    
    /// Create fee bump transaction (same outputs, higher fee)
    pub fn create_bump_tx(
        original_txid: &str,
        original_utxos: &[UTXO],
        original_outputs: &[TxOutput],
        new_fee_rate: u64,
        private_key: &str,
    ) -> HawalaResult<String>;
}
```

**Swift Frontend Tasks:**
- [ ] Store original UTXOs when sending transaction (in pending tx storage)
- [ ] Add "Cancel Transaction" button in transaction detail view
- [ ] Implement `cancelBitcoinTransaction()` calling Rust RBF
- [ ] Show confirmation dialog with new fee estimate
- [ ] Track replacement transaction status

**FFI Functions:**
```c
const char* hawala_btc_create_cancellation(const char* json_input);
const char* hawala_btc_create_fee_bump(const char* json_input);
const char* hawala_btc_is_rbf_enabled(const char* txid);
```

**Acceptance Criteria:**
- [ ] User can cancel unconfirmed BTC transaction
- [ ] User can speed up (bump fee) unconfirmed BTC transaction
- [ ] UI shows "Cannot cancel" for non-RBF transactions
- [ ] Replacement transaction broadcasts successfully
- [ ] Original transaction becomes invalid after replacement confirms

---

### 1.2 Ethereum Transaction Cancellation
**Current State:** `speedUpEthereumTransaction()` exists but incomplete  
**Files:** `swift-app/Sources/swift-app/Views/SpeedUpTransactionSheet.swift`

**Rust Backend Tasks:**
```rust
// rust-app/src/tx/cancel.rs (NEW)
pub struct EVMCancellation;

impl EVMCancellation {
    /// Create 0-value self-send with same nonce to cancel pending tx
    pub fn create_cancellation_tx(
        from_address: &str,
        pending_nonce: u64,
        gas_price_gwei: f64,  // Must be higher than original
        chain: Chain,
    ) -> HawalaResult<UnsignedEVMTransaction>;
    
    /// Create replacement tx with higher gas (EIP-1559)
    pub fn create_speedup_tx(
        original_tx: &EVMTransaction,
        new_max_fee: u128,
        new_priority_fee: u128,
    ) -> HawalaResult<UnsignedEVMTransaction>;
}
```

**Swift Frontend Tasks:**
- [ ] Store pending transaction nonce in local DB
- [ ] Add "Cancel" and "Speed Up" buttons for pending EVM transactions
- [ ] Calculate minimum gas price for replacement (original + 10%)
- [ ] Sign and broadcast replacement transaction
- [ ] Update UI when replacement confirms

**FFI Functions:**
```c
const char* hawala_evm_create_cancellation(const char* json_input);
const char* hawala_evm_create_speedup(const char* json_input);
```

**Acceptance Criteria:**
- [ ] Cancel pending ETH transaction by sending 0 ETH to self
- [ ] Speed up pending transaction with higher gas
- [ ] Works on all EVM chains (ETH, BNB, Polygon, Arbitrum, etc.)
- [ ] Handles EIP-1559 and legacy transactions
- [ ] Shows error if transaction already confirmed

---

### 1.3 Staking - Full Implementation
**Current State:** `StakingManager.swift` and `rust-app/src/staking.rs` exist but throw `NotImplemented`  
**Chains to Support:** Solana, Cosmos, Ethereum (via Lido/RocketPool), Cardano

**Rust Backend Tasks:**
```rust
// rust-app/src/staking.rs - Complete implementation

pub struct StakingService;

impl StakingService {
    // Solana Native Staking
    pub async fn create_solana_stake_account(
        from: &str,
        validator: &str,
        amount_lamports: u64,
    ) -> HawalaResult<Vec<Instruction>>;
    
    pub async fn delegate_solana_stake(
        stake_account: &str,
        validator: &str,
    ) -> HawalaResult<Vec<Instruction>>;
    
    pub async fn deactivate_solana_stake(stake_account: &str) -> HawalaResult<Vec<Instruction>>;
    
    pub async fn withdraw_solana_stake(
        stake_account: &str,
        to: &str,
    ) -> HawalaResult<Vec<Instruction>>;
    
    // Cosmos Staking (delegate/undelegate/redelegate)
    pub async fn cosmos_delegate(
        delegator: &str,
        validator: &str,
        amount: &str,
        denom: &str,
    ) -> HawalaResult<CosmosMsg>;
    
    pub async fn cosmos_undelegate(
        delegator: &str,
        validator: &str,
        amount: &str,
    ) -> HawalaResult<CosmosMsg>;
    
    pub async fn cosmos_claim_rewards(
        delegator: &str,
        validators: &[String],
    ) -> HawalaResult<Vec<CosmosMsg>>;
    
    // Ethereum Liquid Staking (Lido)
    pub async fn lido_stake(amount_wei: &str) -> HawalaResult<EVMTransaction>;
    pub async fn lido_request_withdrawal(steth_amount: &str) -> HawalaResult<EVMTransaction>;
    
    // Fetch staking positions
    pub async fn get_staking_positions(address: &str, chain: Chain) -> HawalaResult<Vec<StakingPosition>>;
    pub async fn get_claimable_rewards(address: &str, chain: Chain) -> HawalaResult<ClaimableRewards>;
}
```

**Swift Frontend Tasks:**
- [ ] Complete `StakingView.swift` with validator selection
- [ ] Show current staking positions with rewards
- [ ] Implement stake/unstake/claim flows
- [ ] Add validator search and filtering
- [ ] Show APY and commission rates
- [ ] Display unbonding period countdown

**FFI Functions:**
```c
const char* hawala_staking_get_validators(const char* chain);
const char* hawala_staking_create_delegation(const char* json_input);
const char* hawala_staking_create_undelegation(const char* json_input);
const char* hawala_staking_claim_rewards(const char* json_input);
const char* hawala_staking_get_positions(const char* json_input);
```

**Acceptance Criteria:**
- [ ] Stake SOL to any validator
- [ ] Stake ATOM/OSMO to Cosmos validators
- [ ] Stake ETH via Lido (receive stETH)
- [ ] View all staking positions across chains
- [ ] Claim rewards with one tap
- [ ] Unstake with clear unbonding period display

---

### 1.4 Hardware Wallet Integration
**Current State:** `HardwareWalletManager.swift` has structure, signing incomplete  
**Devices:** Ledger Nano X/S Plus (Bluetooth), Trezor Model T/One (USB)

**Implementation Tasks:**

**Ledger Integration (Bluetooth):**
```swift
// HardwareWallet/LedgerManager.swift
class LedgerManager: ObservableObject {
    // Bluetooth discovery and connection
    func discoverDevices() async throws -> [LedgerDevice]
    func connect(device: LedgerDevice) async throws
    func disconnect()
    
    // App management
    func openApp(name: String) async throws  // "Bitcoin", "Ethereum", etc.
    func getAppVersion() async throws -> String
    
    // Address derivation
    func getAddress(path: String, verify: Bool) async throws -> String
    func getPublicKey(path: String) async throws -> Data
    
    // Transaction signing
    func signBitcoinTransaction(psbt: Data) async throws -> Data
    func signEthereumTransaction(rlp: Data, path: String) async throws -> (v: UInt8, r: Data, s: Data)
    func signMessage(message: Data, path: String) async throws -> Data
}
```

**Swift Frontend Tasks:**
- [ ] Bluetooth permission handling (Info.plist)
- [ ] Device discovery UI with pairing flow
- [ ] "Sign with Ledger" option in transaction confirmation
- [ ] On-device verification prompts
- [ ] Error handling for disconnects/timeouts

**Acceptance Criteria:**
- [ ] Discover and pair Ledger Nano X via Bluetooth
- [ ] Derive addresses from hardware wallet
- [ ] Sign Bitcoin transactions (PSBT)
- [ ] Sign Ethereum transactions
- [ ] Sign messages for WalletConnect
- [ ] Show clear prompts: "Confirm on your Ledger device"

---

### 1.5 Social Recovery - Full Shamir Implementation
**Current State:** `SocialRecoveryView.swift` exists with UI, no actual SSS implementation  
**Algorithm:** Shamir's Secret Sharing (SSS)

**Rust Backend Tasks:**
```rust
// rust-app/src/security/shamir.rs (NEW)
use sharks::{Share, Sharks};

pub struct ShamirRecovery;

impl ShamirRecovery {
    /// Split seed phrase into N shares, requiring M to recover
    pub fn create_shares(
        seed_phrase: &str,
        total_shares: u8,      // N (e.g., 5)
        threshold: u8,         // M (e.g., 3)
    ) -> HawalaResult<Vec<RecoveryShare>>;
    
    /// Recover seed phrase from M shares
    pub fn recover_seed(shares: &[RecoveryShare]) -> HawalaResult<String>;
    
    /// Validate a share without revealing the secret
    pub fn validate_share(share: &RecoveryShare) -> bool;
}

pub struct RecoveryShare {
    pub id: u8,
    pub data: Vec<u8>,
    pub threshold: u8,
    pub total: u8,
    pub created_at: u64,
    pub label: String,  // "Mom", "Safety Deposit Box", etc.
}
```

**Swift Frontend Tasks:**
- [ ] Guardian selection flow (choose trusted contacts)
- [ ] Share generation and QR code display
- [ ] Share distribution guidance (email, print, etc.)
- [ ] Recovery flow: collect shares from guardians
- [ ] Wallet recovery from collected shares

**FFI Functions:**
```c
const char* hawala_shamir_create_shares(const char* json_input);
const char* hawala_shamir_recover(const char* json_input);
const char* hawala_shamir_validate_share(const char* share_data);
```

**Acceptance Criteria:**
- [ ] Create 2-of-3, 3-of-5, or custom M-of-N schemes
- [ ] Export shares as QR codes or text
- [ ] Recover wallet with M shares
- [ ] Works offline (no server dependency)
- [ ] Each share is useless alone

---

### 1.6 WalletConnect v2 - Complete Implementation
**Current State:** `WalletConnectService.swift` exists with basic structure  

**Implementation Tasks:**
```swift
// Complete WalletConnectService.swift
class WalletConnectService: ObservableObject {
    // Session Management
    func pair(uri: String) async throws -> Session
    func approve(proposal: SessionProposal, accounts: [String]) async throws -> Session
    func reject(proposal: SessionProposal) async throws
    func disconnect(session: Session) async throws
    func getSessions() -> [Session]
    
    // Request Handling
    func handleRequest(_ request: Request) async throws -> AnyCodable
    
    // Supported Methods
    // - eth_sendTransaction
    // - eth_signTransaction
    // - eth_sign
    // - personal_sign
    // - eth_signTypedData_v4
    // - wallet_switchEthereumChain
    // - wallet_addEthereumChain
}
```

**Swift Frontend Tasks:**
- [ ] QR code scanner for WalletConnect URIs
- [ ] Session approval UI showing dApp info
- [ ] Transaction approval modal with simulation preview
- [ ] Message signing approval with decoded content
- [ ] Active sessions management view
- [ ] Push notifications for incoming requests

**Acceptance Criteria:**
- [ ] Scan QR from any dApp (Uniswap, OpenSea, etc.)
- [ ] Approve/reject connection requests
- [ ] Sign transactions from dApps
- [ ] Sign messages (personal_sign, eth_signTypedData_v4)
- [ ] Switch chains when dApp requests
- [ ] Disconnect sessions

---

### 1.7 EIP-712 Typed Data Signing
**Current State:** `rust-app/src/eip712/` exists but needs Swift integration

**Rust Backend (Verify Complete):**
```rust
// rust-app/src/eip712/mod.rs
pub fn sign_typed_data_v4(
    typed_data: &EIP712TypedData,
    private_key: &[u8],
) -> HawalaResult<Signature>;

pub fn hash_typed_data(typed_data: &EIP712TypedData) -> HawalaResult<[u8; 32]>;
```

**Swift Frontend Tasks:**
- [ ] Parse EIP-712 typed data from WalletConnect
- [ ] Display human-readable preview of typed data
- [ ] Highlight dangerous fields (unlimited approvals)
- [ ] Sign via Rust backend
- [ ] Return signature to dApp

**FFI Functions:**
```c
const char* hawala_eip712_sign(const char* json_input);
const char* hawala_eip712_hash(const char* typed_data_json);
```

**Acceptance Criteria:**
- [ ] Sign OpenSea listings
- [ ] Sign Uniswap Permit2 approvals
- [ ] Sign Gnosis Safe transactions
- [ ] Display typed data in readable format
- [ ] Warn on unlimited approvals

---

### 1.8 ENS/Unstoppable Domains Resolution
**Current State:** `ENSResolver.swift` exists but may be incomplete

**Implementation Tasks:**
```swift
// Complete ENSResolver.swift
class ENSResolver {
    /// Resolve ENS name to address
    func resolve(name: String) async throws -> String?
    
    /// Reverse lookup: address to ENS name
    func reverseResolve(address: String) async throws -> String?
    
    /// Get ENS avatar
    func getAvatar(name: String) async throws -> URL?
    
    /// Get ENS text records
    func getTextRecord(name: String, key: String) async throws -> String?
    
    /// Resolve Unstoppable Domains
    func resolveUnstoppable(domain: String) async throws -> String?
}
```

**Swift Frontend Tasks:**
- [ ] ENS input field in send view
- [ ] Show resolved address with confirmation
- [ ] Display ENS avatars in contacts/history
- [ ] Cache resolutions locally
- [ ] Support .eth, .crypto, .wallet, .nft domains

**Acceptance Criteria:**
- [ ] Send to vitalik.eth resolves correctly
- [ ] Show ENS name in transaction history if available
- [ ] Display ENS avatar in contact list
- [ ] Works with Unstoppable Domains

---

### 1.9 Fiat On-Ramp - Complete Integration
**Current State:** `rust-app/src/onramp/` and `swift-app/Sources/swift-app/Services/OnRamp/` exist

**Implementation Tasks:**
```swift
// Complete OnRampService.swift
class OnRampService {
    // Provider abstraction
    func getQuote(
        fiatAmount: Decimal,
        fiatCurrency: String,
        cryptoCurrency: String,
        provider: OnRampProvider
    ) async throws -> OnRampQuote
    
    func getBestQuote(
        fiatAmount: Decimal,
        fiatCurrency: String,
        cryptoCurrency: String
    ) async throws -> [OnRampQuote]  // Sorted by rate
    
    func createOrder(quote: OnRampQuote, walletAddress: String) async throws -> OnRampOrder
    
    // Supported providers
    enum OnRampProvider {
        case moonpay
        case transak
        case ramp
        case banxa
    }
}
```

**Swift Frontend Tasks:**
- [ ] Buy crypto button in wallet view
- [ ] Amount input with fiat/crypto toggle
- [ ] Provider comparison (show all quotes)
- [ ] WebView for provider checkout
- [ ] Order tracking and status updates

**Acceptance Criteria:**
- [ ] Buy BTC/ETH/SOL with credit card
- [ ] Compare rates across providers
- [ ] Complete purchase without leaving app
- [ ] Track order status to completion
- [ ] Receive crypto to wallet address

---

### 1.10 Transaction Fee Presets
**Current State:** `FeeEstimationService.swift` exists but UI needs clear presets

**Implementation Tasks:**
```swift
// FeePresetView.swift
struct FeePreset: Identifiable {
    let id: String
    let name: String          // "Slow", "Normal", "Fast", "Instant"
    let icon: String          // 🐢, 🚶, 🏃, ⚡️
    let estimatedMinutes: Int
    let feeAmount: String     // "0.00012 BTC"
    let feeFiat: String       // "≈ $4.50"
}

class FeePresetManager {
    func getPresets(for chain: Chain, txSize: Int) async throws -> [FeePreset]
    func getCustomFeeRange(for chain: Chain) -> (min: UInt64, max: UInt64)
}
```

**Swift Frontend Tasks:**
- [ ] Fee preset selector in send flow
- [ ] Show estimated confirmation time
- [ ] Display fee in crypto and fiat
- [ ] Allow custom fee for advanced users
- [ ] Show network congestion indicator

**Acceptance Criteria:**
- [ ] Clear Slow/Normal/Fast/Instant options
- [ ] Accurate time estimates
- [ ] Custom fee slider for power users
- [ ] Works for BTC, ETH, and all EVM chains

---

### 1.11 UTXO Coin Control
**Current State:** `UTXOCoinControlManager.swift` exists but needs full implementation

**Rust Backend Tasks:**
```rust
// rust-app/src/wallet/utxo.rs - Verify complete
pub struct UTXOManager;

impl UTXOManager {
    /// Fetch all UTXOs for address
    pub async fn fetch_utxos(address: &str, chain: Chain) -> HawalaResult<Vec<UTXO>>;
    
    /// Smart selection with strategies
    pub fn select_utxos(
        utxos: &[UTXO],
        target_amount: u64,
        fee_rate: u64,
        strategy: SelectionStrategy,
    ) -> HawalaResult<UTXOSelection>;
    
    /// Manual coin control
    pub fn select_specific_utxos(
        utxos: &[UTXO],
        selected_ids: &[String],
        fee_rate: u64,
    ) -> HawalaResult<UTXOSelection>;
    
    /// Label UTXOs for organization
    pub fn set_utxo_label(utxo_id: &str, label: &str) -> HawalaResult<()>;
    
    /// Freeze UTXO (exclude from auto-selection)
    pub fn freeze_utxo(utxo_id: &str, frozen: bool) -> HawalaResult<()>;
}

pub enum SelectionStrategy {
    MinimizeFee,      // Fewest UTXOs
    MaximizePrivacy,  // Many small UTXOs
    OldestFirst,      // FIFO
    LargestFirst,     // Biggest UTXOs first
}
```

**Swift Frontend Tasks:**
- [ ] UTXO list view with labels
- [ ] Manual UTXO selection in advanced send
- [ ] Freeze/unfreeze UTXOs
- [ ] UTXO labeling
- [ ] Selection strategy picker

**Acceptance Criteria:**
- [ ] View all UTXOs with amounts
- [ ] Manually select which UTXOs to spend
- [ ] Freeze UTXOs to exclude from spending
- [ ] Label UTXOs for organization
- [ ] Choose selection strategy

---

### 1.12 EVM Nonce Management
**Current State:** `EVMNonceManager.swift` exists

**Implementation Tasks:**
```swift
// Complete EVMNonceManager.swift
class EVMNonceManager {
    /// Get next available nonce (considering pending txs)
    func getNextNonce(address: String, chain: Chain) async throws -> UInt64
    
    /// Reserve nonce for pending transaction
    func reserveNonce(address: String, chain: Chain) async throws -> UInt64
    
    /// Confirm nonce was used (transaction broadcast)
    func confirmNonce(address: String, chain: Chain, nonce: UInt64)
    
    /// Release reserved nonce (transaction cancelled)
    func releaseNonce(address: String, chain: Chain, nonce: UInt64)
    
    /// Detect and report nonce gaps
    func detectGaps(address: String, chain: Chain) async throws -> [NonceGap]
    
    /// Fill nonce gap with 0-value self-send
    func fillGap(address: String, chain: Chain, nonce: UInt64) async throws
}
```

**Acceptance Criteria:**
- [ ] Never reuse nonces accidentally
- [ ] Track pending transaction nonces locally
- [ ] Detect stuck transactions due to nonce gaps
- [ ] Fill nonce gaps automatically or manually

---

### 1.13 Message Signing (personal_sign)
**Current State:** `rust-app/src/message_signer/` exists

**Rust Backend (Verify Complete):**
```rust
// rust-app/src/message_signer/mod.rs
pub fn sign_personal_message(
    message: &[u8],
    private_key: &[u8],
) -> HawalaResult<Signature>;

pub fn sign_eth_sign(
    message_hash: &[u8; 32],
    private_key: &[u8],
) -> HawalaResult<Signature>;
```

**Swift Frontend Tasks:**
- [ ] Message signing request UI from WalletConnect
- [ ] Display message in human-readable format
- [ ] Hex decode if needed
- [ ] Warn on signing raw hashes

**Acceptance Criteria:**
- [ ] Sign messages for dApp authentication
- [ ] Display message content before signing
- [ ] Support both personal_sign and eth_sign

---

### 1.14 Push Notifications
**Current State:** `NotificationManager.swift` exists with basic structure

**Implementation Tasks:**
```swift
// Complete NotificationManager.swift
class NotificationManager {
    // Local Notifications
    func scheduleTransactionConfirmed(txid: String, chain: Chain, amount: String)
    func scheduleTokenReceived(token: String, amount: String, from: String)
    func schedulePriceAlert(token: String, price: Decimal, direction: PriceDirection)
    
    // Background Polling
    func startBackgroundPolling()
    func stopBackgroundPolling()
    
    // APNs Integration (for true push when app closed)
    func registerForRemotePush() async throws -> String  // Returns device token
    func handleRemotePush(userInfo: [AnyHashable: Any])
}
```

**Swift Frontend Tasks:**
- [ ] Request notification permissions
- [ ] Background transaction status polling
- [ ] Local notification on confirmation
- [ ] Notification settings UI
- [ ] Price alert configuration

**Acceptance Criteria:**
- [ ] Get notified when transaction confirms
- [ ] Get notified when tokens received
- [ ] Works when app is in background
- [ ] Configurable notification preferences

---

### 1.15 Biometric Transaction Confirmation
**Current State:** Biometric exists for unlock, may not be per-transaction

**Implementation Tasks:**
```swift
// BiometricTransactionGuard.swift
class BiometricTransactionGuard {
    /// Require biometric for transactions above threshold
    var thresholdUSD: Decimal = 100
    
    /// Always require biometric for these actions
    var alwaysRequireFor: Set<TransactionType> = [.send, .swap, .stake]
    
    /// Authenticate before signing
    func authenticateForTransaction(_ tx: Transaction) async throws -> Bool
    
    /// Authenticate for WalletConnect signing
    func authenticateForDAppRequest(_ request: WCRequest) async throws -> Bool
}
```

**Acceptance Criteria:**
- [ ] Require Face ID/Touch ID before signing transactions
- [ ] Configurable threshold (always, > $100, > $1000)
- [ ] Apply to sends, swaps, staking, dApp requests
- [ ] Fallback to passcode if biometric fails

---

## 🟠 Phase 2: Security & Trust Features (Weeks 4-5)

### 2.1 Transaction Simulation & Preview
**Inspired by:** Rabby, Blowfish, Pocket Universe

**Rust Backend Tasks:**
```rust
// rust-app/src/security/simulation.rs (NEW)
pub struct TransactionSimulator;

impl TransactionSimulator {
    /// Simulate EVM transaction and return state changes
    pub async fn simulate_evm_transaction(
        tx: &EVMTransaction,
        chain: Chain,
    ) -> HawalaResult<SimulationResult>;
    
    /// Check transaction against known scam patterns
    pub fn analyze_risk(tx: &EVMTransaction) -> RiskAnalysis;
}

pub struct SimulationResult {
    pub success: bool,
    pub gas_used: u64,
    pub balance_changes: Vec<BalanceChange>,
    pub token_approvals: Vec<TokenApproval>,
    pub nft_transfers: Vec<NFTTransfer>,
    pub contract_interactions: Vec<ContractCall>,
    pub warnings: Vec<Warning>,
}

pub struct BalanceChange {
    pub token: String,
    pub symbol: String,
    pub amount: String,     // Signed: negative = outgoing
    pub usd_value: String,
}

pub struct Warning {
    pub severity: Severity,  // Low, Medium, High, Critical
    pub message: String,
    pub details: String,
}
```

**Integration Options:**
1. **Blowfish API** - https://blowfish.xyz (paid, most accurate)
2. **Tenderly Simulation API** - https://tenderly.co
3. **Custom eth_call** - Free but less comprehensive

**Swift Frontend Tasks:**
- [ ] Pre-sign simulation for all EVM transactions
- [ ] "What will happen" preview screen
- [ ] Balance change visualization (+/- tokens)
- [ ] Warning badges for risky transactions
- [ ] "This will drain your wallet" for drainers

**Acceptance Criteria:**
- [ ] See token balance changes before signing
- [ ] Warning for unlimited approvals
- [ ] Warning for known scam contracts
- [ ] Warning for unusual patterns
- [ ] Block obvious drainer transactions

---

### 2.2 Token Approval Manager & Batch Revoke
**Inspired by:** Rabby, Revoke.cash

**Rust Backend Tasks:**
```rust
// rust-app/src/security/approvals.rs (NEW)
pub struct ApprovalManager;

impl ApprovalManager {
    /// Fetch all ERC-20 approvals for address
    pub async fn get_approvals(
        address: &str,
        chain: Chain,
    ) -> HawalaResult<Vec<TokenApproval>>;
    
    /// Create revoke transaction (set allowance to 0)
    pub fn create_revoke_tx(
        token_address: &str,
        spender_address: &str,
    ) -> HawalaResult<EVMTransaction>;
    
    /// Create batch revoke transaction (multiple tokens)
    pub fn create_batch_revoke_tx(
        approvals: &[(String, String)],  // (token, spender)
    ) -> HawalaResult<EVMTransaction>;
}

pub struct TokenApproval {
    pub token_address: String,
    pub token_symbol: String,
    pub token_name: String,
    pub spender_address: String,
    pub spender_name: Option<String>,  // "Uniswap V3", "Unknown"
    pub allowance: String,             // Amount or "Unlimited"
    pub is_unlimited: bool,
    pub last_used: Option<u64>,
    pub risk_level: RiskLevel,
}
```

**Swift Frontend Tasks:**
- [ ] Approvals list view (Settings > Security > Approvals)
- [ ] Show spender name if known (Uniswap, OpenSea, etc.)
- [ ] Flag unlimited approvals
- [ ] One-tap revoke single approval
- [ ] Batch revoke multiple approvals
- [ ] Filter by chain, risk level

**Acceptance Criteria:**
- [ ] View all token approvals across chains
- [ ] See which contracts can spend your tokens
- [ ] Revoke individual approvals
- [ ] Batch revoke in single transaction
- [ ] Flag old/risky approvals

---

### 2.3 Phishing & Scam Detection
**Inspired by:** MetaMask Snaps, Rabby

**Rust Backend Tasks:**
```rust
// rust-app/src/security/phishing.rs (NEW)
pub struct PhishingDetector;

impl PhishingDetector {
    /// Check if address is known scammer
    pub async fn check_address(address: &str) -> HawalaResult<AddressRisk>;
    
    /// Check if domain is phishing
    pub async fn check_domain(domain: &str) -> HawalaResult<DomainRisk>;
    
    /// Update blocklists from remote
    pub async fn update_blocklists() -> HawalaResult<()>;
}

pub struct AddressRisk {
    pub address: String,
    pub is_flagged: bool,
    pub risk_type: Option<String>,  // "Scammer", "Sanctioned", "Honeypot"
    pub source: Option<String>,      // "ChainAbuse", "Etherscan", etc.
    pub reports: u32,
}
```

**Data Sources:**
- ChainAbuse API
- Etherscan labels
- Custom blocklist
- Community reports

**Swift Frontend Tasks:**
- [ ] Check recipient before sending
- [ ] Check WalletConnect dApp domains
- [ ] Warning modal for flagged addresses
- [ ] Block sends to sanctioned addresses

**Acceptance Criteria:**
- [ ] Warn before sending to known scammer
- [ ] Warn when connecting to phishing dApp
- [ ] Block transactions to OFAC sanctioned addresses
- [ ] Regularly update blocklists

---

### 2.4 Address Whitelisting
**Inspired by:** Exchange withdrawal whitelists

**Implementation Tasks:**
```swift
// AddressWhitelistManager.swift
class AddressWhitelistManager {
    /// Check if address is whitelisted
    func isWhitelisted(address: String, chain: Chain) -> Bool
    
    /// Add address to whitelist (with optional delay)
    func addToWhitelist(address: String, chain: Chain, label: String) async throws
    
    /// Remove from whitelist
    func removeFromWhitelist(address: String, chain: Chain) throws
    
    /// Whitelist settings
    var whitelistMode: WhitelistMode  // .off, .warnOnly, .blockNonWhitelisted
    var newAddressDelay: TimeInterval  // 24-48 hours before new address active
}
```

**Swift Frontend Tasks:**
- [ ] Whitelist management in settings
- [ ] Add from contacts or manual entry
- [ ] Delay period for new addresses
- [ ] Warning for non-whitelisted recipients
- [ ] Optional: block non-whitelisted sends

**Acceptance Criteria:**
- [ ] Maintain whitelist of trusted addresses
- [ ] Warn when sending to new address
- [ ] Optional 24-hour delay for new whitelist entries
- [ ] Works per-chain or globally

---

## 🟡 Phase 3: User Experience Features (Weeks 6-7)

### 3.1 L2 Balance Aggregation
**Inspired by:** Rabby, Rainbow

**Implementation Tasks:**
```swift
// L2BalanceAggregator.swift
class L2BalanceAggregator {
    /// Get total balance across all L2s
    func getTotalBalance(token: String, address: String) async throws -> AggregatedBalance
    
    /// Get breakdown by chain
    func getBalanceBreakdown(token: String, address: String) async throws -> [ChainBalance]
    
    /// Suggest best chain for transaction (lowest fees)
    func suggestChain(
        token: String,
        amount: Decimal,
        address: String
    ) async throws -> Chain
}

struct AggregatedBalance {
    let token: String
    let totalAmount: Decimal
    let totalUSD: Decimal
    let chains: [ChainBalance]
}
```

**Swift Frontend Tasks:**
- [ ] Aggregated token view (ETH across all L2s)
- [ ] Expandable breakdown by chain
- [ ] Auto-suggest cheapest chain for sends
- [ ] One-tap bridge to consolidate

**Acceptance Criteria:**
- [ ] See combined ETH balance across L1 + L2s
- [ ] Drill down to see per-chain amounts
- [ ] Smart chain selection for transactions

---

### 3.2 Payment Request Links
**Inspired by:** Venmo, Cash App

**Implementation Tasks:**
```swift
// PaymentLinkManager.swift
class PaymentLinkManager {
    /// Create shareable payment request
    func createPaymentLink(
        amount: Decimal,
        token: String,
        chain: Chain,
        recipientAddress: String,
        memo: String?
    ) -> URL
    
    /// Parse incoming payment link
    func parsePaymentLink(_ url: URL) -> PaymentRequest?
}

// Deep link format: hawala://pay?to=0x...&amount=1.5&token=ETH&chain=1&memo=Coffee
```

**Swift Frontend Tasks:**
- [ ] "Request Payment" button in receive view
- [ ] Generate shareable link/QR
- [ ] Share via Messages, WhatsApp, etc.
- [ ] Parse incoming payment links
- [ ] Pre-fill send form from link

**Acceptance Criteria:**
- [ ] Create payment request with amount
- [ ] Share via any messaging app
- [ ] Recipient taps link, Hawala opens with pre-filled send

---

### 3.3 Transaction Notes
**Current State:** `TransactionNotesManager.swift` exists

**Implementation Tasks:**
```swift
// Complete TransactionNotesManager.swift
class TransactionNotesManager {
    /// Add note to transaction
    func setNote(txid: String, note: String)
    
    /// Get note for transaction
    func getNote(txid: String) -> String?
    
    /// Search transactions by note
    func searchByNote(query: String) -> [String]  // Returns txids
    
    /// Export notes with transactions
    func exportNotesCSV() -> Data
}
```

**Swift Frontend Tasks:**
- [ ] Add note field in transaction detail
- [ ] Search transactions by note
- [ ] Display notes in history list
- [ ] Include notes in export

**Acceptance Criteria:**
- [ ] Add personal notes to any transaction
- [ ] Search history by notes
- [ ] Notes persist and sync with backup

---

### 3.4 Fiat Off-Ramp (Sell Crypto)
**Inspired by:** Phantom Cash, MoonPay

**Implementation Tasks:**
```swift
// OffRampService.swift
class OffRampService {
    /// Get sell quote
    func getSellQuote(
        cryptoAmount: Decimal,
        cryptoCurrency: String,
        fiatCurrency: String,
        provider: OffRampProvider
    ) async throws -> OffRampQuote
    
    /// Create sell order
    func createSellOrder(
        quote: OffRampQuote,
        bankAccount: BankAccount
    ) async throws -> OffRampOrder
    
    /// Track order status
    func getOrderStatus(orderId: String) async throws -> OffRampStatus
}
```

**Swift Frontend Tasks:**
- [ ] "Sell" button in wallet view
- [ ] Amount input and bank selection
- [ ] Provider integration (MoonPay Sell, Transak)
- [ ] Order tracking

**Acceptance Criteria:**
- [ ] Sell BTC/ETH to bank account
- [ ] See conversion rate and fees
- [ ] Track withdrawal to bank

---

### 3.5 Price Alerts
**Current State:** May exist partially in `NotificationManager.swift`

**Implementation Tasks:**
```swift
// PriceAlertManager.swift
class PriceAlertManager {
    /// Create price alert
    func createAlert(
        token: String,
        targetPrice: Decimal,
        direction: AlertDirection,  // .above, .below
        oneTime: Bool
    )
    
    /// Get active alerts
    func getActiveAlerts() -> [PriceAlert]
    
    /// Check alerts against current prices
    func checkAlerts(prices: [String: Decimal])
    
    /// Trigger notification for matched alert
    private func triggerAlert(_ alert: PriceAlert, currentPrice: Decimal)
}
```

**Swift Frontend Tasks:**
- [ ] Set alert from token detail view
- [ ] Manage alerts in notifications settings
- [ ] Push notification when price hit
- [ ] Alert history

**Acceptance Criteria:**
- [ ] Set "alert me when BTC > $100,000"
- [ ] Get push notification when triggered
- [ ] One-time or recurring alerts

---

## 🔵 Phase 4: Cutting-Edge Features (Weeks 8-11)

### 4.1 Passkey Authentication (WebAuthn)
**Inspired by:** Clave, Coinbase Wallet

**Implementation Tasks:**
```swift
// PasskeyManager.swift
import AuthenticationServices

class PasskeyManager: NSObject, ASAuthorizationControllerDelegate {
    /// Create passkey for wallet
    func createPasskey(walletId: String) async throws -> ASPasskeyCredential
    
    /// Authenticate with passkey
    func authenticate() async throws -> ASPasskeyCredential
    
    /// Sign data with passkey (Secure Enclave P-256)
    func sign(data: Data) async throws -> Data
    
    /// Link passkey to smart account for on-chain recovery
    func linkToSmartAccount(passkey: ASPasskeyCredential, account: String) async throws
}
```

**Integration with ERC-4337:**
- Passkey creates P-256 key in Secure Enclave
- Smart account validates WebAuthn signatures
- No seed phrase needed for signing

**Swift Frontend Tasks:**
- [ ] "Create Passkey" in wallet setup
- [ ] "Sign with Face ID" instead of entering password
- [ ] Passkey recovery flow
- [ ] Multiple device passkey sync via iCloud

**Acceptance Criteria:**
- [ ] Create wallet with passkey only (no seed phrase)
- [ ] Sign transactions with Face ID
- [ ] Recover on new device via iCloud
- [ ] Works with ERC-4337 smart accounts

---

### 4.2 ERC-4337 Smart Accounts
**Inspired by:** Safe, Alchemy Account Kit, ZeroDev

**Rust Backend Tasks:**
```rust
// rust-app/src/erc4337/mod.rs (NEW)
pub mod bundler;
pub mod paymaster;
pub mod account;
pub mod user_operation;

pub struct SmartAccountManager;

impl SmartAccountManager {
    /// Compute counterfactual smart account address
    pub fn compute_address(
        owner: &str,
        factory: &str,
        salt: &[u8; 32],
    ) -> HawalaResult<String>;
    
    /// Create UserOperation for transaction
    pub fn create_user_operation(
        sender: &str,
        call_data: &[u8],
        nonce: u64,
        chain: Chain,
    ) -> HawalaResult<UserOperation>;
    
    /// Sign UserOperation
    pub fn sign_user_operation(
        user_op: &UserOperation,
        private_key: &[u8],
        entry_point: &str,
        chain_id: u64,
    ) -> HawalaResult<SignedUserOperation>;
    
    /// Submit to bundler
    pub async fn submit_to_bundler(
        user_op: &SignedUserOperation,
        bundler_url: &str,
    ) -> HawalaResult<String>;  // Returns userOpHash
    
    /// Get UserOperation receipt
    pub async fn get_receipt(
        user_op_hash: &str,
        bundler_url: &str,
    ) -> HawalaResult<UserOperationReceipt>;
}

pub struct UserOperation {
    pub sender: String,
    pub nonce: U256,
    pub init_code: Vec<u8>,
    pub call_data: Vec<u8>,
    pub call_gas_limit: U256,
    pub verification_gas_limit: U256,
    pub pre_verification_gas: U256,
    pub max_fee_per_gas: U256,
    pub max_priority_fee_per_gas: U256,
    pub paymaster_and_data: Vec<u8>,
    pub signature: Vec<u8>,
}
```

**Bundler Integration:**
- Alchemy Bundler: `https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY`
- Pimlico: `https://api.pimlico.io/v2/`
- Stackup: `https://api.stackup.sh/v1/node/`

**Swift Frontend Tasks:**
- [ ] Smart account creation flow
- [ ] UserOperation building for transactions
- [ ] Bundler submission
- [ ] Transaction tracking via userOpHash
- [ ] Batch multiple calls in one UserOp

**Acceptance Criteria:**
- [ ] Create ERC-4337 smart account
- [ ] Send transactions via bundler
- [ ] Batch swap + stake in one signature
- [ ] Track UserOperation status

---

### 4.3 Paymaster (Gasless Transactions)
**Inspired by:** Alchemy Gas Manager, Pimlico

**Rust Backend Tasks:**
```rust
// rust-app/src/erc4337/paymaster.rs
pub struct PaymasterManager;

impl PaymasterManager {
    /// Get sponsorship for UserOperation
    pub async fn get_sponsorship(
        user_op: &UserOperation,
        paymaster_url: &str,
        policy_id: &str,
    ) -> HawalaResult<PaymasterData>;
    
    /// Check if operation is sponsorable
    pub async fn check_sponsorship(
        user_op: &UserOperation,
        paymaster_url: &str,
    ) -> HawalaResult<bool>;
}

pub struct PaymasterData {
    pub paymaster: String,
    pub paymaster_verification_gas_limit: U256,
    pub paymaster_post_op_gas_limit: U256,
    pub paymaster_data: Vec<u8>,
}
```

**Use Cases:**
- Sponsor first transaction for new users
- Sponsor specific dApp interactions
- Pay gas with ERC-20 tokens

**Swift Frontend Tasks:**
- [ ] Check for available sponsorship
- [ ] Show "Gas Sponsored" badge
- [ ] Fallback to user gas if no sponsor

**Acceptance Criteria:**
- [ ] First transaction is gasless
- [ ] Show when gas is sponsored
- [ ] Fallback to normal gas payment

---

### 4.4 Gas Account (Multi-Chain Gas Management)
**Inspired by:** Rabby Gas Account

**Implementation Tasks:**
```swift
// GasAccountManager.swift
class GasAccountManager {
    /// Total balance in gas account (in USD)
    var balance: Decimal { get }
    
    /// Deposit to gas account
    func deposit(amount: Decimal, token: String, chain: Chain) async throws
    
    /// Withdraw from gas account
    func withdraw(amount: Decimal, toAddress: String, chain: Chain) async throws
    
    /// Pay for transaction from gas account
    func payGas(
        for transaction: Transaction,
        chain: Chain
    ) async throws -> GasPayment
    
    /// Get estimated gas cost
    func estimateGasCost(
        for transaction: Transaction,
        chain: Chain
    ) async throws -> Decimal
}
```

**Architecture Options:**
1. **Paymaster-based:** Deposit to paymaster, sponsors your transactions
2. **Bridge-based:** Auto-bridge gas token to needed chain
3. **Aggregator:** Convert stablecoin deposit to gas on-demand

**Swift Frontend Tasks:**
- [ ] Gas Account balance display
- [ ] Deposit/withdraw UI
- [ ] Auto-pay toggle in settings
- [ ] Balance alerts

**Acceptance Criteria:**
- [ ] Deposit $20 stablecoins to gas account
- [ ] Pay gas on any chain from single balance
- [ ] Never need to manage gas tokens per chain

---

## 🟢 Phase 5: Polish & QA (Week 12)

### 5.1 Comprehensive Testing
- [ ] Unit tests for all new Rust functions
- [ ] Unit tests for all new Swift services
- [ ] Integration tests for complete flows
- [ ] UI tests for critical paths

### 5.2 Security Audit Preparation
- [ ] Document all cryptographic operations
- [ ] Review key storage security
- [ ] Audit transaction signing flows
- [ ] Verify no private key leakage

### 5.3 Performance Optimization
- [ ] Profile and optimize slow paths
- [ ] Reduce memory usage
- [ ] Optimize network requests
- [ ] Lazy load heavy views

### 5.4 Documentation
- [ ] Update README with new features
- [ ] API documentation for FFI functions
- [ ] User-facing help/FAQ content

---

## 📋 Dependency Graph

```
Phase 1 (Foundation)
├── RBF Cancellation → Requires UTXO tracking
├── ETH Cancellation → Requires nonce management
├── Staking → Standalone
├── Hardware Wallet → Standalone
├── Social Recovery → Requires Shamir implementation
├── WalletConnect v2 → Requires message signing
├── EIP-712 → Required by WalletConnect
├── ENS → Standalone
├── Fiat On-Ramp → Standalone
├── Fee Presets → Standalone
├── UTXO Control → Standalone
├── Nonce Management → Standalone
├── Message Signing → Standalone
├── Push Notifications → Standalone
└── Biometric Tx → Standalone

Phase 2 (Security)
├── Transaction Simulation → Requires WalletConnect
├── Token Approvals → Standalone
├── Phishing Detection → Standalone
└── Address Whitelist → Standalone

Phase 3 (UX)
├── L2 Aggregation → Standalone
├── Payment Links → Standalone
├── Transaction Notes → Standalone
├── Fiat Off-Ramp → Standalone
└── Price Alerts → Requires Push Notifications

Phase 4 (Cutting Edge)
├── Passkeys → Standalone (iOS 16+)
├── ERC-4337 → Requires new account type
├── Paymaster → Requires ERC-4337
└── Gas Account → Requires ERC-4337 + Paymaster
```

---

## ✅ Definition of Done

Every feature must meet these criteria before considered complete:

1. **Rust Backend**
   - [ ] All functions implemented (no `NotImplemented` errors)
   - [ ] Unit tests with 80%+ coverage
   - [ ] FFI functions exposed
   - [ ] Error handling complete

2. **Swift Frontend**
   - [ ] UI implemented and functional
   - [ ] Connected to Rust via FFI or CLI bridge
   - [ ] Error states handled gracefully
   - [ ] Loading states shown

3. **Integration**
   - [ ] End-to-end flow works
   - [ ] Tested on real networks (testnet or mainnet)
   - [ ] Edge cases handled

4. **Documentation**
   - [ ] Code comments for complex logic
   - [ ] API documented for FFI functions

---

## 🎯 Success Metrics

| Metric | Target |
|--------|--------|
| Features complete (no partials) | 28/28 |
| Rust unit test coverage | 80%+ |
| Swift test coverage | 60%+ |
| Zero `NotImplemented` errors | 0 |
| Zero `featureInProgress` errors | 0 |
| App crash rate | < 0.1% |
| Transaction success rate | > 99% |

---

## 📅 Weekly Schedule

| Week | Focus | Deliverables |
|------|-------|--------------|
| 1 | BTC/ETH Cancellation, Fee Presets | RBF + nonce replacement working |
| 2 | Staking, UTXO Control, Nonce Mgmt | Stake SOL/ATOM, coin control |
| 3 | Hardware Wallet, Social Recovery | Ledger signing, Shamir shares |
| 4 | Transaction Simulation | Pre-sign preview, balance changes |
| 5 | Approvals, Phishing, Whitelist | Security dashboard complete |
| 6 | WalletConnect v2, EIP-712 | Full dApp connectivity |
| 7 | L2 Aggregation, ENS, Notes | UX polish |
| 8 | Passkeys | WebAuthn authentication |
| 9-10 | ERC-4337 + Paymaster | Smart accounts + gasless |
| 11 | Gas Account | Multi-chain gas management |
| 12 | QA, Testing, Polish | Ship-ready |

---

*This roadmap prioritizes completing existing partial implementations before adding new features, ensuring a solid foundation for cutting-edge capabilities.*
