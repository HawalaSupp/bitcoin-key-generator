# ROADMAP-XX: ContentView MVVM Refactor

> **Objective:** Reduce ContentView.swift from 6,456 LOC to < 300 LOC through systematic MVVM extraction  
> **Estimated Effort:** 8-12 days (solo developer)  
> **Risk Level:** Medium-High (touches core app functionality)  
> **Priority:** Post-Launch / Technical Debt

---

## Executive Summary

ContentView.swift has grown into a monolithic 6,456-line file containing:
- **120 state variables** (`@State`, `@AppStorage`, `@StateObject`, `@Binding`)
- **140+ functions** (business logic, API calls, formatting, navigation)
- **35+ sheets** (`.sheet` modifiers)
- **15+ inline view components** (ChainCard, TransactionHistoryRow, etc.)
- **Deeply coupled concerns** (UI, networking, security, persistence)

This roadmap provides a safe, incremental extraction strategy that preserves all existing functionality while dramatically improving maintainability.

---

## Current State Analysis

### File Breakdown by Concern

| Concern | Approx. LOC | % of Total |
|---------|-------------|------------|
| State declarations | 150 | 2.3% |
| Main body & sheets | 650 | 10.1% |
| Inline View structs | 1,800 | 27.9% |
| Balance fetching | 1,200 | 18.6% |
| Price fetching | 600 | 9.3% |
| Wallet operations | 800 | 12.4% |
| Security/Auth | 500 | 7.7% |
| Helper functions | 400 | 6.2% |
| Formatting utilities | 350 | 5.4% |

### Critical Dependencies Identified

```
ContentView
├── AllKeys (wallet key data)
├── ChainInfo[] (chain metadata)
├── balanceStates: [String: ChainBalanceState]
├── priceStates: [String: ChainPriceState]
├── historyEntries: [HawalaTransactionEntry]
├── pendingTransactions: [PendingTransaction]
├── sparklineCache: SparklineCache (singleton)
├── assetCache: AssetCache (singleton)
├── transactionHistoryService: TransactionHistoryService (singleton)
├── Security state (passcode, biometrics, auto-lock)
├── UI state (sheets, navigation, onboarding)
└── Formatting/helpers (crypto amounts, fiat conversion)
```

---

## Target Architecture

```
Sources/swift-app/
├── App/
│   └── KeyGeneratorApp.swift (entry point, commands)
│
├── ContentView.swift (~250 LOC - thin shell)
│
├── ViewModels/
│   ├── WalletViewModel.swift (keys, generation, import/export)
│   ├── BalanceViewModel.swift (balance fetching, caching)
│   ├── PriceViewModel.swift (price fetching, FX rates)
│   ├── HistoryViewModel.swift (transaction history)
│   ├── SecurityViewModel.swift (passcode, biometrics, auto-lock)
│   └── SettingsViewModel.swift (preferences, currency, language)
│
├── Views/
│   ├── Dashboard/
│   │   ├── DashboardView.swift (replaces contentArea)
│   │   ├── PortfolioHeaderView.swift
│   │   ├── ChainGridView.swift
│   │   └── ChainCardView.swift (extracted from inline)
│   │
│   ├── Transactions/
│   │   ├── TransactionHistorySectionView.swift
│   │   ├── TransactionRowView.swift
│   │   ├── PendingTransactionRowView.swift
│   │   └── HistoryFilterBarView.swift
│   │
│   ├── Security/
│   │   ├── SecurityPromptView.swift (extracted)
│   │   ├── LockedStateView.swift (extracted)
│   │   ├── UnlockView.swift (extracted)
│   │   └── SecuritySettingsView.swift (extracted)
│   │
│   ├── Settings/
│   │   ├── SettingsPanelView.swift (extracted)
│   │   └── PasswordPromptView.swift (extracted)
│   │
│   ├── Sheets/
│   │   ├── SendAssetPickerSheet.swift (extracted)
│   │   ├── SeedPhraseSheet.swift (extracted)
│   │   ├── AllPrivateKeysSheet.swift (extracted)
│   │   ├── ChainDetailSheet.swift (extracted)
│   │   ├── ImportPrivateKeySheet.swift (extracted)
│   │   └── SecurityNoticeView.swift (extracted)
│   │
│   └── Shared/
│       ├── NoKeysPlaceholderView.swift
│       ├── CopyFeedbackBanner.swift
│       └── PrivacyBlurOverlay.swift
│
├── Services/ (already exists - enhance)
│   ├── BalanceFetchService.swift (use existing)
│   └── PriceService.swift (extract from ContentView)
│
└── Models/ (already exists)
```

---

## Phase 1: Extract Inline Views (Days 1-3)

**Goal:** Move all private struct views out of ContentView to dedicated files.

### Task 1.1: Security Views Extraction

**Files to create:**

1. **`Views/Security/SecurityPromptView.swift`** (~40 LOC)
   - Extract `SecurityPromptView` struct
   - No state dependencies, pure presentation
   - Callback: `onReview: () -> Void`

2. **`Views/Security/LockedStateView.swift`** (~35 LOC)
   - Extract `LockedStateView` struct
   - Callback: `onUnlock: () -> Void`

3. **`Views/Security/UnlockView.swift`** (~80 LOC)
   - Extract `UnlockView` struct
   - Dependencies: `supportsBiometrics`, callbacks
   - ⚠️ Contains `@State` - keep internal

4. **`Views/Security/SecuritySettingsView.swift`** (~350 LOC)
   - Already large, but self-contained
   - Dependencies: bindings for biometric settings
   - Contains nested views: `DuressProtectionRow`, `InheritanceProtocolRow`, etc.
   - ⚠️ Test all security flows after extraction

**Migration pattern:**
```swift
// BEFORE (in ContentView.swift)
private struct SecurityPromptView: View { ... }

// AFTER (in Views/Security/SecurityPromptView.swift)
import SwiftUI

struct SecurityPromptView: View {
    let onReview: () -> Void
    
    var body: some View { ... }
}

// In ContentView.swift, just:
// import is automatic within same target
```

**Verification checklist:**
- [ ] Security notice flow works
- [ ] Unlock sheet appears correctly
- [ ] Biometric toggle functions
- [ ] Auto-lock still triggers
- [ ] All security settings save properly

---

### Task 1.2: Settings Views Extraction

**Files to create:**

1. **`Views/Settings/SettingsPanelView.swift`** (~200 LOC)
   - Extract `SettingsPanelView` struct
   - Dependencies: `selectedCurrency`, `onCurrencyChanged`, callbacks
   - Contains internal sections, keep together

2. **`Views/Sheets/PasswordPromptView.swift`** (~120 LOC)
   - Extract `PasswordPromptView` struct
   - Mode enum: `.export` / `.import`
   - Callbacks: `onConfirm`, `onCancel`

**Verification checklist:**
- [ ] Settings panel opens from gear icon
- [ ] Currency picker changes work
- [ ] Language selection works
- [ ] Sound/haptic toggles work
- [ ] Export password flow works
- [ ] Import password flow works

---

### Task 1.3: Wallet Sheets Extraction

**Files to create:**

1. **`Views/Sheets/SendAssetPickerSheet.swift`** (~150 LOC)
   - Extract `SendAssetPickerSheet` struct
   - Dependencies: `chains: [ChainInfo]`, callbacks
   - Search/filter state is internal

2. **`Views/Sheets/SeedPhraseSheet.swift`** (~100 LOC)
   - Extract `SeedPhraseSheet` struct
   - Internal state for word count, regeneration
   - Callback: `onCopy`

3. **`Views/Sheets/AllPrivateKeysSheet.swift`** (~100 LOC)
   - Extract `AllPrivateKeysSheet` struct
   - Dependencies: `chains: [ChainInfo]`, `onCopy`

4. **`Views/Sheets/ChainDetailSheet.swift`** (~250 LOC)
   - Extract `ChainDetailSheet` struct
   - Complex dependencies - needs careful handling
   - Contains QR code, receive section, balance/price summaries

5. **`Views/Sheets/ImportPrivateKeySheet.swift`** (~150 LOC)
   - Extract `ImportPrivateKeySheet` struct
   - Self-contained with validation logic

6. **`Views/Sheets/SecurityNoticeView.swift`** (~80 LOC)
   - Extract `SecurityNoticeView` struct
   - Callback: `onAcknowledge`

**Verification checklist:**
- [ ] Send picker shows all eligible chains
- [ ] Batch send option works
- [ ] Seed phrase generation works
- [ ] All private keys display correctly
- [ ] Chain detail shows balance/price
- [ ] Receive QR code generates
- [ ] Import private key validation works
- [ ] Security notice acknowledgment persists

---

### Task 1.4: Transaction Views Extraction

**Files to create:**

1. **`Views/Transactions/TransactionHistoryRowView.swift`** (~250 LOC)
   - Extract `TransactionHistoryRow` struct
   - Complex with expandable details, notes
   - Internal state: `isHovered`, `isExpanded`, `noteText`

2. **`Views/Transactions/PendingTransactionRowView.swift`** (~120 LOC)
   - Extract `PendingTransactionRow` struct
   - Dependencies: transaction data, callbacks

3. **`Views/Transactions/HistoryFilterBarView.swift`** (~150 LOC)
   - Extract `historyFilterBar` computed property
   - Convert to proper View struct
   - Dependencies: bindings for search/filters

**Verification checklist:**
- [ ] Transaction history displays correctly
- [ ] Row expansion works (details, notes)
- [ ] Copy tx hash works
- [ ] Explorer link opens
- [ ] Pending transactions show
- [ ] Speed up/cancel buttons work
- [ ] Filter by chain works
- [ ] Filter by type works
- [ ] Search works
- [ ] Clear filters works

---

### Task 1.5: Dashboard Views Extraction

**Files to create:**

1. **`Views/Dashboard/ChainCardView.swift`** (~200 LOC)
   - Extract `ChainCard` struct
   - Dependencies: chain, balanceState, priceState, sparklineData
   - Contains skeleton loading states

2. **`Views/Dashboard/PortfolioHeaderView.swift`** (~100 LOC)
   - Extract `portfolioHeader` computed property
   - Convert to View struct
   - Dependencies: total balance display, refresh callback

3. **`Views/Dashboard/ActionButtonsRowView.swift`** (~100 LOC)
   - Extract `actionButtonsRow` / `actionButtonsContent`
   - Convert to View struct
   - Callbacks: send, receive, view keys, export, seed phrase, history

4. **`Views/Shared/NoKeysPlaceholderView.swift`** (~30 LOC)
   - Extract `NoKeysPlaceholderView` struct
   - Pure presentation, no dependencies

5. **`Views/Shared/PrivacyBlurOverlay.swift`** (~50 LOC)
   - Extract `PrivacyBlurOverlay` struct
   - Contains macOS-specific blur

**Verification checklist:**
- [ ] Chain cards display correctly
- [ ] Balance/price states show properly
- [ ] Sparklines render
- [ ] Skeleton loading animates
- [ ] Portfolio total calculates
- [ ] All action buttons work
- [ ] Privacy blur appears on background

---

### Phase 1 Exit Criteria

After Phase 1 completion:
- ContentView.swift should be ~2,500 LOC (down from 6,456)
- All extracted views compile independently
- All UI interactions work identically
- No visual regressions

**Test command:**
```bash
swift build --package-path swift-app && swift run swift-app
```

---

## Phase 2: Create ViewModels (Days 4-6)

**Goal:** Extract all business logic and state management into dedicated ViewModels.

### Task 2.1: WalletViewModel

**File:** `ViewModels/WalletViewModel.swift`

**State to migrate:**
```swift
@MainActor
class WalletViewModel: ObservableObject {
    // From ContentView
    @Published var keys: AllKeys?
    @Published var rawJSON: String = ""
    @Published var isGenerating = false
    @Published var errorMessage: String?
    
    // Dependencies
    private let rustService = RustService.shared
    
    // Methods to migrate
    func generateKeys() async { ... }           // runGenerator()
    func loadKeysFromKeychain() { ... }         // loadKeysFromKeychain()
    func saveKeysToKeychain() { ... }           // from runGenerator()
    func clearKeys() { ... }                    // clearSensitiveData()
    
    // Import/Export
    func performEncryptedExport(password: String) { ... }
    func performEncryptedImport(data: Data, password: String) { ... }
    func importPrivateKey(_ key: String, chain: String) async { ... }
}
```

**ContentView changes:**
```swift
struct ContentView: View {
    @StateObject private var walletVM = WalletViewModel()
    
    // Remove: keys, rawJSON, isGenerating, errorMessage
    // Access via: walletVM.keys, walletVM.isGenerating, etc.
}
```

**Critical verification:**
- [ ] Key generation works
- [ ] Keys persist across app restarts
- [ ] Import encrypted backup works
- [ ] Export encrypted backup works
- [ ] Keys clear on background/lock

---

### Task 2.2: BalanceViewModel

**File:** `ViewModels/BalanceViewModel.swift`

**Note:** `BalanceFetchService.swift` already exists (599 LOC). Integrate with it.

**State to migrate:**
```swift
@MainActor
class BalanceViewModel: ObservableObject {
    @Published var balanceStates: [String: ChainBalanceState] = [:]
    @Published var cachedBalances: [String: CachedBalance] = [:]
    
    private var balanceBackoff: [String: BackoffTracker] = [:]
    private var balanceFetchTasks: [String: Task<Void, Never>] = [:]
    
    private let assetCache = AssetCache.shared
    private let balanceService = BalanceFetchService.shared // Use existing service
    
    // Methods to migrate from ContentView
    func startBalanceFetch(for keys: AllKeys) { ... }
    func cancelAllFetches() { ... }
    func refreshAllBalances() { ... }
    
    // These call into BalanceFetchService:
    // - fetchBitcoinBalance()
    // - fetchLitecoinBalance()
    // - fetchEthereumBalance()
    // - fetchSolanaBalance()
    // - fetchXrpBalance()
    // - fetchBnbBalance()
    // - fetchERC20Balance()
}
```

**BalanceFetchService integration:**
The existing `BalanceFetchService` has the balance fetching logic. BalanceViewModel should:
1. Own the `@Published` state
2. Delegate actual fetching to BalanceFetchService
3. Handle backoff/retry logic
4. Update caches

**Verification:**
- [ ] Bitcoin balance fetches
- [ ] Litecoin balance fetches
- [ ] Ethereum balance fetches (Alchemy + fallback)
- [ ] Solana balance fetches
- [ ] XRP balance fetches (multiple providers)
- [ ] BNB balance fetches
- [ ] ERC-20 token balances fetch
- [ ] Stale/error states display correctly
- [ ] Refresh updates all balances
- [ ] Caching persists across sessions

---

### Task 2.3: PriceViewModel

**File:** `ViewModels/PriceViewModel.swift`

**State to migrate:**
```swift
@MainActor
class PriceViewModel: ObservableObject {
    @Published var priceStates: [String: ChainPriceState] = [:]
    @Published var fxRates: [String: Double] = [:]
    
    private var cachedPrices: [String: CachedPrice] = [:]
    private var priceBackoffTracker = BackoffTracker()
    private var priceUpdateTask: Task<Void, Never>?
    private var fxRatesFetchTask: Task<Void, Never>?
    
    let sparklineCache = SparklineCache.shared // Expose for views
    private let assetCache = AssetCache.shared
    
    // Configuration
    private let pollingInterval: TimeInterval = 120
    var coingeckoAPIKey: String? = nil
    
    // Methods to migrate
    func startPriceUpdates() { ... }
    func stopPriceUpdates() { ... }
    func fetchPriceSnapshot() async throws -> [String: Double] { ... }
    func fetchFXRates() async throws { ... }
    
    // Formatting
    func formatFiatAmount(_ amount: Double) -> String { ... }
    func formatCryptoAmount(_ amount: Double, symbol: String) -> String { ... }
}
```

**Verification:**
- [ ] Prices update on app launch
- [ ] Price polling continues in background
- [ ] Rate limiting handled gracefully
- [ ] FX rates fetch for currency conversion
- [ ] Currency switching updates displays
- [ ] Sparklines load and display
- [ ] Price formatting respects user currency

---

### Task 2.4: HistoryViewModel

**File:** `ViewModels/HistoryViewModel.swift`

**State to migrate:**
```swift
@MainActor
class HistoryViewModel: ObservableObject {
    @Published var historyEntries: [HawalaTransactionEntry] = []
    @Published var isLoading = false
    @Published var error: String?
    
    // Filtering
    @Published var searchText = ""
    @Published var filterChain: String?
    @Published var filterType: String?
    
    // Pending transactions
    @Published var pendingTransactions: [PendingTransactionManager.PendingTransaction] = []
    
    private var historyFetchTask: Task<Void, Never>?
    private var pendingTxRefreshTask: Task<Void, Never>?
    
    private let historyService = TransactionHistoryService.shared
    
    var filteredEntries: [HawalaTransactionEntry] { ... }
    var uniqueChains: [String] { ... }
    var hasActiveFilters: Bool { ... }
    
    // Methods
    func refreshHistory(for keys: AllKeys, force: Bool) { ... }
    func clearFilters() { ... }
    func exportAsCSV() -> String { ... }
    
    // Pending
    func startPendingRefresh() { ... }
    func trackTransaction(_ result: TransactionBroadcastResult) { ... }
}
```

**Verification:**
- [ ] History loads on key generation
- [ ] History refreshes manually
- [ ] Filtering by chain works
- [ ] Filtering by type works
- [ ] Search works
- [ ] Pending transactions track
- [ ] Pending status updates
- [ ] CSV export generates correctly

---

### Task 2.5: SecurityViewModel

**File:** `ViewModels/SecurityViewModel.swift`

**State to migrate:**
```swift
@MainActor
class SecurityViewModel: ObservableObject {
    // Passcode
    @AppStorage("hawala.passcodeHash") private var storedPasscodeHash: String?
    @Published var isUnlocked = false
    
    // Biometrics
    @AppStorage("hawala.biometricUnlockEnabled") private var biometricUnlockEnabled = false
    @AppStorage("hawala.biometricForSends") var biometricForSends = true
    @AppStorage("hawala.biometricForKeyReveal") var biometricForKeyReveal = true
    @Published var biometricState: BiometricState = .unknown
    
    // Auto-lock
    @AppStorage("hawala.autoLockInterval") private var storedAutoLockInterval: Double = 300
    @Published var lastActivityTimestamp = Date()
    private var autoLockTask: Task<Void, Never>?
    
    // Privacy
    @Published var showPrivacyBlur = false
    
    #if canImport(AppKit)
    private var activityMonitor: UserActivityMonitor?
    #endif
    
    var canAccessSensitiveData: Bool { ... }
    var hasPasscode: Bool { ... }
    
    // Methods
    func setPasscode(_ passcode: String) { ... }
    func removePasscode() { ... }
    func unlock(with passcode: String) -> Bool { ... }
    func lock() { ... }
    func recordActivity() { ... }
    func refreshBiometricAvailability() { ... }
    func attemptBiometricUnlock(reason: String) { ... }
    func handleScenePhase(_ phase: ScenePhase) { ... }
}
```

**Verification:**
- [ ] Passcode set/remove works
- [ ] Unlock validates passcode
- [ ] Biometric unlock works (Touch ID/Face ID)
- [ ] Auto-lock triggers after interval
- [ ] Activity tracking resets timer
- [ ] Privacy blur shows on inactive
- [ ] Keys clear on background

---

### Task 2.6: SettingsViewModel

**File:** `ViewModels/SettingsViewModel.swift`

**State to migrate:**
```swift
@MainActor
class SettingsViewModel: ObservableObject {
    @AppStorage("hawala.appearanceMode") var storedAppearanceMode = "system"
    @AppStorage("hawala.selectedFiatCurrency") var storedFiatCurrency = "USD"
    @AppStorage("hawala.onboardingCompleted") var onboardingCompleted = false
    @AppStorage("hawala.securityAcknowledged") var hasAcknowledgedSecurityNotice = false
    
    var appearanceMode: AppearanceMode { ... }
    var selectedFiatCurrency: FiatCurrency { ... }
    
    // Callbacks for when settings change
    var onCurrencyChange: (() -> Void)?
    var onAppearanceChange: (() -> Void)?
    
    func updateAppearanceMode(_ mode: AppearanceMode) { ... }
    func completeOnboarding() { ... }
    func acknowledgeSecurityNotice() { ... }
}
```

**Verification:**
- [ ] Appearance mode changes persist
- [ ] Currency selection persists
- [ ] Onboarding state persists
- [ ] Security notice state persists

---

### Phase 2 Exit Criteria

After Phase 2 completion:
- ContentView.swift should be ~800-1,000 LOC
- All ViewModels are `@MainActor` and thread-safe
- State is accessed via ViewModels, not directly in ContentView
- All business logic is testable in isolation

---

## Phase 3: Wire Up & Thin ContentView (Days 7-8)

**Goal:** Connect ViewModels to ContentView, remove remaining logic.

### Task 3.1: ContentView Restructure

Final ContentView structure:

```swift
import SwiftUI

struct ContentView: View {
    // MARK: - ViewModels
    @StateObject private var walletVM = WalletViewModel()
    @StateObject private var balanceVM = BalanceViewModel()
    @StateObject private var priceVM = PriceViewModel()
    @StateObject private var historyVM = HistoryViewModel()
    @StateObject private var securityVM = SecurityViewModel()
    @StateObject private var settingsVM = SettingsViewModel()
    
    // MARK: - UI State (sheet presentation only)
    @State private var showSplashScreen = true
    @State private var selectedChain: ChainInfo?
    @State private var activeSheet: SheetType?
    
    // MARK: - Environment
    @Environment(\.scenePhase) private var scenePhase
    
    enum SheetType: Identifiable {
        case settings, security, securityNotice, unlock
        case sendPicker, receive, allKeys, seedPhrase
        case exportPassword, importPassword, importPrivateKey
        case transactionHistory, transactionDetail(HawalaTransactionEntry)
        case speedUp(PendingTransactionManager.PendingTransaction)
        case cancel(PendingTransactionManager.PendingTransaction)
        // ... all other sheets
        
        var id: String { ... }
    }
    
    var body: some View {
        ZStack {
            if showSplashScreen {
                HawalaSplashView(isShowingSplash: $showSplashScreen)
            }
            
            mainContent
                .opacity(showSplashScreen ? 0 : 1)
        }
        .animation(.easeInOut(duration: 0.3), value: showSplashScreen)
        .preferredColorScheme(settingsVM.appearanceMode.colorScheme)
        .onChange(of: scenePhase) { securityVM.handleScenePhase($0) }
        .onAppear(perform: onAppLaunch)
        .sheet(item: $activeSheet) { sheetContent($0) }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        if !settingsVM.onboardingCompleted {
            OnboardingFlowView { result in
                handleOnboardingComplete(result)
            }
        } else if !securityVM.canAccessSensitiveData {
            if !settingsVM.hasAcknowledgedSecurityNotice {
                SecurityPromptView { activeSheet = .securityNotice }
            } else {
                LockedStateView { activeSheet = .unlock }
            }
        } else {
            DashboardView(
                walletVM: walletVM,
                balanceVM: balanceVM,
                priceVM: priceVM,
                historyVM: historyVM,
                selectedChain: $selectedChain,
                onOpenSheet: { activeSheet = $0 }
            )
        }
    }
    
    @ViewBuilder
    private func sheetContent(_ sheet: SheetType) -> some View {
        switch sheet {
        case .settings:
            SettingsPanelView(vm: settingsVM, ...)
        case .sendPicker:
            SendAssetPickerSheet(chains: walletVM.sendEligibleChains, ...)
        // ... all sheets
        }
    }
    
    private func onAppLaunch() {
        securityVM.refreshBiometricAvailability()
        walletVM.loadKeysFromKeychain()
        
        if let keys = walletVM.keys {
            balanceVM.startBalanceFetch(for: keys)
            priceVM.startPriceUpdates()
            historyVM.refreshHistory(for: keys, force: false)
        }
    }
    
    private func handleOnboardingComplete(_ result: WalletCreationResult) {
        Task {
            await walletVM.generateKeys()
            settingsVM.completeOnboarding()
            
            if let keys = walletVM.keys {
                balanceVM.startBalanceFetch(for: keys)
                priceVM.startPriceUpdates()
                historyVM.refreshHistory(for: keys, force: true)
            }
        }
    }
}
```

---

### Task 3.2: Create DashboardView

**File:** `Views/Dashboard/DashboardView.swift`

```swift
struct DashboardView: View {
    @ObservedObject var walletVM: WalletViewModel
    @ObservedObject var balanceVM: BalanceViewModel
    @ObservedObject var priceVM: PriceViewModel
    @ObservedObject var historyVM: HistoryViewModel
    
    @Binding var selectedChain: ChainInfo?
    let onOpenSheet: (ContentView.SheetType) -> Void
    
    var body: some View {
        ZStack {
            if selectedChain == nil {
                HawalaMainView(
                    keys: walletVM.keys,
                    balanceStates: balanceVM.balanceStates,
                    priceStates: priceVM.priceStates,
                    sparklineCache: priceVM.sparklineCache,
                    // ... bindings
                )
            } else if let chain = selectedChain {
                HawalaAssetDetailView(chain: chain, ...)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}
```

---

### Task 3.3: Update HawalaMainView Dependencies

HawalaMainView currently takes 30+ parameters. Convert to ViewModels:

```swift
// BEFORE
struct HawalaMainView: View {
    @Binding var keys: AllKeys?
    @Binding var selectedChain: ChainInfo?
    @Binding var balanceStates: [String: ChainBalanceState]
    @Binding var priceStates: [String: ChainPriceState]
    @ObservedObject var sparklineCache: SparklineCache
    @Binding var showSendPicker: Bool
    @Binding var showReceiveSheet: Bool
    // ... 20+ more
}

// AFTER
struct HawalaMainView: View {
    @ObservedObject var walletVM: WalletViewModel
    @ObservedObject var balanceVM: BalanceViewModel
    @ObservedObject var priceVM: PriceViewModel
    
    @Binding var selectedChain: ChainInfo?
    let onAction: (DashboardAction) -> Void
    
    enum DashboardAction {
        case openSend, openReceive, openSettings
        case openHistory, openKeys, openSeedPhrase
        case refreshBalances, refreshHistory
        // ...
    }
}
```

---

### Phase 3 Exit Criteria

After Phase 3:
- ContentView.swift < 300 LOC
- All sheets consolidated into single `.sheet(item:)` pattern
- All business logic in ViewModels
- UI is declarative and reactive

---

## Phase 4: Testing & Cleanup (Days 9-10)

### Task 4.1: Unit Tests for ViewModels

Create test files:

```
Tests/ViewModelTests/
├── WalletViewModelTests.swift
├── BalanceViewModelTests.swift
├── PriceViewModelTests.swift
├── HistoryViewModelTests.swift
├── SecurityViewModelTests.swift
└── SettingsViewModelTests.swift
```

Example test structure:

```swift
@MainActor
final class WalletViewModelTests: XCTestCase {
    var sut: WalletViewModel!
    
    override func setUp() {
        sut = WalletViewModel()
    }
    
    func test_generateKeys_setsIsGenerating() async {
        XCTAssertFalse(sut.isGenerating)
        
        let task = Task { await sut.generateKeys() }
        
        // Brief delay to check loading state
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(sut.isGenerating)
        
        await task.value
        XCTAssertFalse(sut.isGenerating)
    }
    
    func test_generateKeys_producesValidKeys() async {
        await sut.generateKeys()
        
        XCTAssertNotNil(sut.keys)
        XCTAssertFalse(sut.keys!.bitcoin.address.isEmpty)
        XCTAssertFalse(sut.keys!.ethereum.address.isEmpty)
    }
}
```

### Task 4.2: Integration Tests

Test full user flows:

```swift
@MainActor
final class WalletFlowTests: XCTestCase {
    func test_fullKeyGenerationFlow() async throws {
        let walletVM = WalletViewModel()
        let balanceVM = BalanceViewModel()
        let priceVM = PriceViewModel()
        
        // Generate keys
        await walletVM.generateKeys()
        XCTAssertNotNil(walletVM.keys)
        
        // Start balance fetch
        balanceVM.startBalanceFetch(for: walletVM.keys!)
        
        // Wait for at least one balance
        try await Task.sleep(nanoseconds: 3_000_000_000)
        XCTAssertFalse(balanceVM.balanceStates.isEmpty)
    }
}
```

### Task 4.3: Remove Dead Code

After extraction, search for:
- Unused private functions
- Commented-out code blocks
- TODO/FIXME markers that are resolved
- Duplicate helper functions

```bash
# Find potential dead code
grep -rn "private func" swift-app/Sources/ | wc -l
grep -rn "// TODO\|// FIXME\|// HACK" swift-app/Sources/
```

### Task 4.4: Documentation

Add documentation comments to all ViewModels:

```swift
/// Manages wallet key generation, storage, and import/export operations.
///
/// This ViewModel handles all cryptographic key material lifecycle:
/// - Key generation via Rust FFI
/// - Secure storage in Keychain
/// - Encrypted backup export/import
/// - Private key import for individual chains
///
/// ## Thread Safety
/// All public methods are MainActor-isolated for safe UI access.
///
/// ## Usage
/// ```swift
/// @StateObject private var walletVM = WalletViewModel()
///
/// Button("Generate") {
///     Task { await walletVM.generateKeys() }
/// }
/// .disabled(walletVM.isGenerating)
/// ```
@MainActor
class WalletViewModel: ObservableObject { ... }
```

---

## Risk Mitigation

### High-Risk Areas

| Area | Risk | Mitigation |
|------|------|------------|
| Security state | Breaking passcode/unlock flow | Test every security path before/after |
| Balance fetching | Race conditions, task cancellation | Use structured concurrency, test cancellation |
| Sheet presentation | Multiple sheets conflicting | Use single `.sheet(item:)` pattern |
| Keychain access | Data loss | Never modify keychain storage logic |
| Price polling | Memory leaks from tasks | Proper task cancellation in deinit |

### Rollback Strategy

1. **Before each phase:** Create a git branch
   ```bash
   git checkout -b mvvm-phase-1
   ```

2. **After each task:** Commit with descriptive message
   ```bash
   git commit -m "Phase 1.2: Extract SettingsPanelView and PasswordPromptView"
   ```

3. **If broken:** Cherry-pick working commits to new branch

### Feature Flags (Optional)

For extra safety, use compile-time flags:

```swift
#if MVVM_REFACTOR
@StateObject private var walletVM = WalletViewModel()
// New code
#else
@State private var keys: AllKeys?
// Old code
#endif
```

---

## Success Metrics

| Metric | Before | Target | Notes |
|--------|--------|--------|-------|
| ContentView LOC | 6,456 | < 300 | 95% reduction |
| State variables in ContentView | 120 | < 10 | Just sheet presentation |
| Functions in ContentView | 140 | < 10 | Lifecycle handlers only |
| Inline private structs | 15 | 0 | All extracted |
| ViewModel test coverage | 0% | > 80% | New tests |
| Build time impact | baseline | < +5% | Monitor Xcode build |

---

## Post-Refactor Benefits

1. **Testability:** ViewModels are unit-testable without UI
2. **Maintainability:** Changes isolated to specific files
3. **Readability:** ContentView is a clear entry point
4. **Performance:** Potential for lazy loading, better SwiftUI diffing
5. **Team scalability:** Multiple developers can work in parallel
6. **SwiftUI best practices:** Proper separation of concerns

---

## Appendix A: Complete File List

### Files to Create (New)

```
ViewModels/
├── WalletViewModel.swift
├── BalanceViewModel.swift
├── PriceViewModel.swift
├── HistoryViewModel.swift
├── SecurityViewModel.swift
└── SettingsViewModel.swift

Views/Dashboard/
├── DashboardView.swift
├── PortfolioHeaderView.swift
├── ChainGridView.swift
├── ChainCardView.swift
└── ActionButtonsRowView.swift

Views/Transactions/
├── TransactionHistorySectionView.swift
├── TransactionRowView.swift
├── PendingTransactionRowView.swift
└── HistoryFilterBarView.swift

Views/Security/
├── SecurityPromptView.swift
├── LockedStateView.swift
├── UnlockView.swift
└── SecuritySettingsView.swift

Views/Settings/
└── SettingsPanelView.swift

Views/Sheets/
├── SendAssetPickerSheet.swift
├── SeedPhraseSheet.swift
├── AllPrivateKeysSheet.swift
├── ChainDetailSheet.swift
├── ImportPrivateKeySheet.swift
├── SecurityNoticeView.swift
└── PasswordPromptView.swift

Views/Shared/
├── NoKeysPlaceholderView.swift
├── CopyFeedbackBanner.swift
└── PrivacyBlurOverlay.swift

Tests/ViewModelTests/
├── WalletViewModelTests.swift
├── BalanceViewModelTests.swift
├── PriceViewModelTests.swift
├── HistoryViewModelTests.swift
├── SecurityViewModelTests.swift
└── SettingsViewModelTests.swift
```

### Files to Modify

```
ContentView.swift (major reduction)
HawalaMainView.swift (parameter simplification)
HawalaAssetDetailView.swift (ViewModel integration)
```

---

## Appendix B: State Variable Mapping

| Current Location | Target ViewModel | Property Name |
|-----------------|------------------|---------------|
| `keys: AllKeys?` | WalletViewModel | `keys` |
| `rawJSON: String` | WalletViewModel | `rawJSON` |
| `isGenerating: Bool` | WalletViewModel | `isGenerating` |
| `errorMessage: String?` | WalletViewModel | `errorMessage` |
| `balanceStates` | BalanceViewModel | `balanceStates` |
| `cachedBalances` | BalanceViewModel | `cachedBalances` |
| `balanceBackoff` | BalanceViewModel | (internal) |
| `balanceFetchTasks` | BalanceViewModel | (internal) |
| `priceStates` | PriceViewModel | `priceStates` |
| `cachedPrices` | PriceViewModel | (internal) |
| `priceBackoffTracker` | PriceViewModel | (internal) |
| `priceUpdateTask` | PriceViewModel | (internal) |
| `fxRates` | PriceViewModel | `fxRates` |
| `historyEntries` | HistoryViewModel | `historyEntries` |
| `isHistoryLoading` | HistoryViewModel | `isLoading` |
| `historyError` | HistoryViewModel | `error` |
| `historySearchText` | HistoryViewModel | `searchText` |
| `historyFilterChain` | HistoryViewModel | `filterChain` |
| `historyFilterType` | HistoryViewModel | `filterType` |
| `pendingTransactions` | HistoryViewModel | `pendingTransactions` |
| `storedPasscodeHash` | SecurityViewModel | (internal) |
| `isUnlocked` | SecurityViewModel | `isUnlocked` |
| `biometricUnlockEnabled` | SecurityViewModel | (internal) |
| `biometricForSends` | SecurityViewModel | `biometricForSends` |
| `biometricForKeyReveal` | SecurityViewModel | `biometricForKeyReveal` |
| `biometricState` | SecurityViewModel | `biometricState` |
| `lastActivityTimestamp` | SecurityViewModel | (internal) |
| `autoLockTask` | SecurityViewModel | (internal) |
| `showPrivacyBlur` | SecurityViewModel | `showPrivacyBlur` |
| `storedAppearanceMode` | SettingsViewModel | (internal) |
| `storedFiatCurrency` | SettingsViewModel | (internal) |
| `onboardingCompleted` | SettingsViewModel | `onboardingCompleted` |
| `hasAcknowledgedSecurityNotice` | SettingsViewModel | `hasAcknowledgedSecurityNotice` |

---

## Appendix C: Sheet Consolidation

### Current (35+ individual @State booleans)

```swift
@State private var showSettingsPanel = false
@State private var showSecuritySettings = false
@State private var showSecurityNotice = false
@State private var showUnlockSheet = false
@State private var showAllPrivateKeysSheet = false
@State private var showReceiveSheet = false
@State private var showSendPicker = false
@State private var showSeedPhraseSheet = false
@State private var showTransactionHistorySheet = false
@State private var showContactsSheet = false
@State private var showStakingSheet = false
@State private var showNotificationsSheet = false
// ... 20+ more
```

### Target (Single enum with associated values)

```swift
enum SheetType: Identifiable {
    case settings
    case security
    case securityNotice
    case unlock
    case allKeys
    case receive
    case sendPicker
    case send(ChainInfo)
    case seedPhrase
    case transactionHistory
    case transactionDetail(HawalaTransactionEntry)
    case speedUp(PendingTransactionManager.PendingTransaction)
    case cancel(PendingTransactionManager.PendingTransaction)
    case contacts
    case staking
    case notifications
    case multisig
    case hardwareWallet
    case watchOnly
    case walletConnect
    case l2Aggregator
    case paymentLinks
    case transactionNotes
    case sellCrypto
    case priceAlerts
    case smartAccount
    case gasAccount
    case passkeyAuth
    case gaslessTx
    case batchTransaction
    case exportPassword
    case importPassword
    case importPrivateKey
    case keyboardShortcutsHelp
    
    var id: String {
        switch self {
        case .settings: return "settings"
        case .transactionDetail(let tx): return "tx-\(tx.id)"
        case .send(let chain): return "send-\(chain.id)"
        // ...
        }
    }
}

@State private var activeSheet: SheetType?

.sheet(item: $activeSheet) { sheet in
    switch sheet {
    case .settings:
        SettingsPanelView(...)
    case .send(let chain):
        SendView(initialChain: chain, ...)
    // ...
    }
}
```

---

## Definition of Done

- [ ] ContentView.swift < 300 LOC
- [ ] All 6 ViewModels created and tested
- [ ] All inline views extracted to separate files
- [ ] All sheets use single `.sheet(item:)` pattern
- [ ] All existing functionality works identically
- [ ] Unit test coverage > 80% for ViewModels
- [ ] Build time within 5% of baseline
- [ ] No new SwiftUI warnings
- [ ] Documentation added for all public APIs
- [ ] Code reviewed by at least one other developer
- [ ] Performance profiled (no regressions)

---

**Document Version:** 1.0  
**Created:** 2026-02-05  
**Last Updated:** 2026-02-05  
**Author:** GitHub Copilot
