# Milestone 4: Privacy Mode + Duress Mode

**Goal:** User-controlled privacy that's real, not cosmetic.

## Overview

M4 adds two key privacy features:
1. **Global Privacy Mode** - Hide sensitive data from prying eyes
2. **Duress/Decoy Wallet** - A separate "fake" wallet for coercion scenarios

---

## M4.1 Global Privacy Mode

### Features
- [ ] **Balance Hiding** - Replace balances with "••••" or tap-to-reveal
- [ ] **Screenshot Prevention** - Disable screenshots on sensitive screens (where OS allows)
- [ ] **Field Redaction** - Blur/hide addresses, transaction amounts, seed phrases
- [ ] **Price Fetch Pause** - Option to stop calling price APIs (reduces tracking surface)
- [ ] **Quick Toggle** - Easy access from toolbar or shake gesture

### Implementation

```swift
// PrivacyManager.swift
@MainActor
class PrivacyManager: ObservableObject {
    @AppStorage("privacyModeEnabled") var isPrivacyModeEnabled = false
    @AppStorage("hideBalances") var hideBalances = true
    @AppStorage("disableScreenshots") var disableScreenshots = true
    @AppStorage("pausePriceFetching") var pausePriceFetching = false
    
    func togglePrivacyMode() {
        isPrivacyModeEnabled.toggle()
    }
}
```

### UI Changes
- Add privacy toggle in Settings
- Add quick-access privacy button in toolbar (eye icon)
- Modify all balance displays to respect privacy mode
- Add blur overlay for sensitive views

---

## M4.2 Duress / Decoy Wallet

### Concept
When under duress (robbery, coercion), user enters a **secondary passcode** that opens a **decoy wallet** with minimal or fake funds. The real wallet remains hidden.

### Features
- [ ] **Separate Decoy Database** - Completely isolated wallet storage
- [ ] **Alternate Passcode** - Different PIN/password triggers decoy mode
- [ ] **No "Fake" Indicators** - Decoy looks identical to real wallet
- [ ] **Safe Recovery Story** - Clear UX for safely exiting duress mode
- [ ] **Plausible Deniability** - No way to detect real wallet exists from decoy

### Implementation

```swift
// DuressManager.swift
@MainActor
class DuressManager: ObservableObject {
    enum WalletMode {
        case real
        case decoy
    }
    
    @Published private(set) var currentMode: WalletMode = .real
    
    // Separate Keychain items for decoy
    private let decoyKeychainPrefix = "hawala.decoy."
    
    func authenticate(passcode: String) -> WalletMode {
        if passcode == getDecoyPasscode() {
            return .decoy
        } else if passcode == getRealPasscode() {
            return .real
        }
        return .real // Default
    }
}
```

### Security Requirements
1. Decoy wallet has its OWN seed phrase (generated separately)
2. Real wallet keys are NEVER accessible when in decoy mode
3. No UI element hints at "fake" or "decoy" status
4. Panic wipe: Option to destroy real wallet from decoy mode (with confirmation)

---

## M4.3 UI/UX for Privacy Features

### Settings Screen Additions
```
Privacy & Security
├── Privacy Mode
│   ├── Enable Privacy Mode [Toggle]
│   ├── Hide Balances [Toggle]
│   ├── Disable Screenshots [Toggle]
│   └── Pause Price Fetching [Toggle]
├── Duress Protection
│   ├── Enable Decoy Wallet [Toggle]
│   ├── Set Decoy Passcode [Button]
│   ├── Configure Decoy Wallet [Button]
│   └── Test Duress Mode [Button]
└── Emergency
    ├── Quick Panic Button [Toggle to show]
    └── Emergency Wipe (requires 2FA)
```

---

## Task Breakdown

### M4.1 Tasks
1. Create `PrivacyManager` service
2. Add `PrivacySettingsView`
3. Create `RedactedText` view modifier
4. Update `PortfolioDashboardView` for balance hiding
5. Update `WalletDetailView` for balance hiding
6. Add privacy toggle to toolbar
7. Implement screenshot prevention (NSWindow flags)

### M4.2 Tasks
1. Create `DuressManager` service
2. Create separate Keychain storage for decoy
3. Update `AuthenticationView` to route to correct wallet
4. Create `DecoySetupView` for initial configuration
5. Implement decoy wallet seed generation
6. Add duress mode indicator (internal only, for debugging)
7. Test: Verify real wallet inaccessible from decoy

### M4.3 Tasks
1. Create `PrivacySecuritySettingsView`
2. Add settings navigation
3. Create onboarding for duress feature
4. Add "Test Duress Mode" flow

---

## Acceptance Criteria

### Privacy Mode
- [ ] Toggling privacy mode immediately hides all balances
- [ ] No balance values visible in any UI snapshot
- [ ] Screenshots blocked on macOS (where supported)
- [ ] Price API calls stopped when paused

### Duress Mode
- [ ] Decoy passcode opens decoy wallet
- [ ] Real passcode opens real wallet
- [ ] No UI indicates which mode is active
- [ ] Decoy cannot access real wallet seed/keys
- [ ] Recovery documentation clear and accurate

---

## Timeline Estimate
- M4.1 Privacy Mode: 1-2 days
- M4.2 Duress Wallet: 2-3 days
- M4.3 UI/Settings: 1 day
- Testing & Polish: 1 day

**Total: ~5-7 days**

---

## Status

| Task | Status | Notes |
|------|--------|-------|
| M4.1 PrivacyManager | ✅ Complete | Full implementation with AppStorage |
| M4.1 Balance Hiding | ✅ Complete | Integrated into HawalaMainView |
| M4.1 Screenshot Prevention | ✅ Complete | Notification-based approach |
| M4.1 Privacy Settings UI | ✅ Complete | Full settings view with tips |
| M4.2 DuressManager | ✅ Complete | Separate Keychain storage |
| M4.2 Decoy Keychain | ✅ Complete | Isolated from real wallet |
| M4.2 Decoy Setup Flow | ✅ Complete | Step-by-step wizard |
| M4.2 Panic Wipe | ✅ Complete | Emergency feature (decoy mode only) |
| M4.3 Settings UI | ✅ Complete | Integrated into app settings |

## Implementation Summary

### Files Created
- `Sources/swift-app/Privacy/PrivacyManager.swift` - Core privacy management
- `Sources/swift-app/Privacy/DuressManager.swift` - Decoy wallet management  
- `Sources/swift-app/Views/PrivacySettingsView.swift` - Privacy settings UI
- `Sources/swift-app/Views/DuressSettingsView.swift` - Duress configuration UI

### Files Modified
- `Sources/swift-app/UI/HawalaMainView.swift` - Privacy-aware balance display
- `Sources/swift-app/ContentView.swift` - Added privacy button to settings
