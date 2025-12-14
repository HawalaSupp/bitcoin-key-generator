# Milestone 0 — Stabilize & Measure (Detailed Execution Plan)

**Goal:** Stop unknown regressions, make development repeatable, handle provider failures gracefully.

**Timeline:** 1–2 weeks

**Status:** ✅ COMPLETED (December 14, 2025)

---

## 📋 Task Breakdown

### M0.1 — CI Pipeline Setup ✅
**Objective:** Every PR runs build + unit tests automatically.

Steps:
1. ✅ Create `.github/workflows/swift.yml`
2. ✅ Configure macOS runner with Swift toolchain
3. ✅ Run `swift build --package-path swift-app`
4. ✅ Run `swift test --package-path swift-app`
5. ✅ Fail PR if tests fail
6. ✅ (Optional) Cache SPM dependencies to speed up builds

Acceptance:
- [x] Fresh clone + `swift test` passes
- [x] GitHub Actions badge shows green

---

### M0.2 — Logging Boundaries ✅
**Objective:** No secrets in logs; clean debug vs release separation.

Steps:
1. ✅ Audit existing `print()` statements across the codebase
2. ✅ Create a `Logger` utility with levels: `.debug`, `.info`, `.warn`, `.error`
3. ✅ Replace raw `print()` with structured logging
4. ✅ Add compile-time flag to strip `.debug` logs in Release builds
5. ✅ Grep codebase for any key/seed/private logging patterns and remove
6. ✅ Add test that verifies no secret patterns in log output

Files created/modified:
- ✅ `swift-app/Sources/swift-app/Utilities/Logger.swift` (EXISTS with secret redaction)
- ✅ Audit complete: no secret logging found

Acceptance:
- [x] No `print()` statements containing "key", "seed", "private", "wif", "hex" (sensitive)
- [x] Release builds produce minimal logs

---

### M0.3 — Provider Health State Machine ✅
**Objective:** App knows when providers are healthy/degraded/offline and communicates clearly.

Steps:
1. ✅ Define `ProviderHealthState` enum: `.healthy`, `.degraded(reason)`, `.offline`
2. ✅ Create `ProviderHealthManager` (ObservableObject) tracking each provider
3. ✅ On provider failure: update state, start retry timer
4. ✅ On provider recovery: reset to healthy
5. ✅ Expose aggregate state for UI consumption
6. ✅ Add UI banner component for degraded/offline states

Files created/modified:
- ✅ `swift-app/Sources/swift-app/Services/ProviderHealthManager.swift` (NEW)
- ✅ Banner integrated into `HawalaMainView.swift`
- ✅ Health tracking integrated into `MultiProviderAPI.swift`

Acceptance:
- [x] State transitions are logged (debug level)
- [x] UI shows banner when degraded/offline
- [x] Banner disappears when healthy again

---

### M0.4 — Offline Launch Safety ✅
**Objective:** App launches and remains usable when network is disconnected.

Steps:
1. ✅ Test app launch with network disabled (Wi-Fi off / airplane mode)
2. ✅ Identify crash points (force-unwrapped network responses, missing error handling)
3. ✅ Add guard clauses / default values for network-dependent initializers
4. ✅ Ensure cached data is displayed instead of empty/crash
5. ✅ ProviderStatusBanner shows when providers fail

Acceptance:
- [x] App launches without crash when offline
- [x] Shows cached balances/prices (or "unavailable" placeholder)
- [x] No force-unwrap crashes from network code

---

### M0.5 — Provider Settings Screen ✅
**Objective:** User can configure API keys, enable/disable networks, set fallback order.

Steps:
1. ✅ Design settings model: `ProviderSettings` (via AppStorage)
2. ✅ Create `ProviderSettingsView.swift` with:
   - ✅ API key input fields (Alchemy, etc.)
   - ✅ Network toggles (provider enabled/disabled)
   - ✅ Provider status display
3. ✅ Add navigation entry from main settings
4. ✅ Wire settings to `MultiProviderAPI` so changes take effect immediately
5. ✅ "Retry All" button for providers

Files created/modified:
- ✅ `swift-app/Sources/swift-app/Views/ProviderSettingsView.swift` (NEW)
- ✅ `swift-app/Sources/swift-app/UI/SettingsView.swift` (added navigation)

Acceptance:
- [x] Can add/change API keys
- [x] Can enable/disable specific networks
- [x] Settings persist across app restarts

---

### M0.6 — Last-Known-Good Caching ✅
**Objective:** When providers fail, show cached data instead of empty/error.

Steps:
1. ✅ Audit existing caching in `BackendSyncService` / `MultiProviderAPI`
2. ✅ Ensure prices + balances are persisted to disk (already done)
3. ✅ Add "stale" indicator when data is from cache (already implemented)
4. ✅ Define cache TTL policy (already implemented)
5. ✅ On provider failure: return cached value + mark as stale
6. ✅ UI shows subtle indicator for stale data ("Showing cached prices • updated X ago")

Files verified:
- ✅ `BackendSyncService.swift` - full caching system
- ✅ `ContentView.swift` - stale state handling

Acceptance:
- [x] Cached data loads on app launch before network completes
- [x] Stale data is visually indicated (e.g., "as of 5 min ago")
- [x] Cache survives app restart

---

### M0.7 — Friendly Error Copy ✅
**Objective:** Replace scary/technical errors with user-friendly messages.

Steps:
1. ✅ Grep for error strings: "403", "DNS", "failed", "error", "invalid"
2. ✅ Create `ErrorMessages.swift` with user-friendly copy:
   - ✅ "Market data temporarily unavailable"
   - ✅ "Unable to connect. Check your internet connection."
   - ✅ "This network is not enabled. Enable it in Settings."
3. ✅ Replace raw error messages with friendly versions
4. ✅ Add "Retry" and "Settings" actions where appropriate

Files created/modified:
- ✅ `swift-app/Sources/swift-app/Utilities/ErrorMessages.swift` (NEW)
- ✅ ProviderHealthManager has `friendlyErrorMessage()` function

Acceptance:
- [x] No raw HTTP codes or technical errors shown to users
- [x] Errors have clear next-step actions (retry, settings, etc.)

---

### M0.8 — Validate Milestone 0 Definition of Done ✅
**Objective:** Confirm all M0 acceptance criteria are met.

Checklist:
- [x] CI passes (build + unit tests) - 17 tests, 0 failures
- [x] No secrets in logs (grep verification) - Logger has automatic redaction
- [x] Offline launch works (cached data displayed)
- [x] Provider failures show friendly UI state
- [x] Provider settings screen exists and works
- [x] Cached data shown when offline
- [x] Error messages are user-friendly

---

## 🚀 Execution Order

1. **M0.2 — Logging boundaries** (foundation for debugging everything else)
2. **M0.3 — Provider health state machine** (core abstraction)
3. **M0.4 — Offline launch safety** (depends on health state)
4. **M0.6 — Last-known-good caching** (depends on health state)
5. **M0.7 — Friendly error copy** (depends on health state)
6. **M0.5 — Provider settings screen** (nice to have, can be done in parallel)
7. **M0.1 — CI pipeline** (can be done in parallel, but validates everything)
8. **M0.8 — Final validation**

---

## 📁 Files to Create (Summary)

| File | Purpose |
|------|---------|
| `Utilities/Logger.swift` | Structured logging with levels |
| `Services/ProviderHealthManager.swift` | Health state machine |
| `UI/ProviderStatusBanner.swift` | Degraded/offline banner |
| `Models/ProviderSettings.swift` | Persisted provider config |
| `UI/Settings/ProviderSettingsView.swift` | Settings screen |
| `Utilities/ErrorMessages.swift` | User-friendly error copy |
| `.github/workflows/swift.yml` | CI pipeline |

---

## ⏱️ Time Estimate

| Task | Estimate |
|------|----------|
| M0.1 CI Pipeline | 1–2 hours |
| M0.2 Logging | 2–3 hours |
| M0.3 Health State | 3–4 hours |
| M0.4 Offline Safety | 2–3 hours |
| M0.5 Settings Screen | 3–4 hours |
| M0.6 Caching | 2–3 hours |
| M0.7 Error Copy | 1–2 hours |
| M0.8 Validation | 1 hour |
| **Total** | **15–22 hours** (~2–3 days focused) |

---

## 🎯 Starting Point

Begin with **M0.2 — Logging boundaries** since it's foundational and will help debug all subsequent work.
