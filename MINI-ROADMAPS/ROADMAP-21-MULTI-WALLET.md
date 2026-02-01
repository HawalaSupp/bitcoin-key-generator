# ROADMAP-21 — Multi-Wallet & Account Management

**Theme:** Multi-Wallet Support  
**Priority:** P2 (Medium)  
**Target Outcome:** Support for multiple wallets and accounts with easy switching

---

## 1) What This Fixes (Mapped to MASTER REVIEW)

- **[High] No Multi-Wallet Support** (implied in architecture)
- **[Medium] Account Switching Unclear** (Section 3.2)
- **Phase 2 P2-9** — Multi-wallet management
- **Blueprint 5.6** — Account management in sidebar
- **Edge Case #52** — Multiple windows with different wallets

---

## 2) User Impact

**Before:**
- Single wallet only
- Cannot segment holdings
- No hardware wallet + software wallet together

**After:**
- Multiple wallets supported
- Easy wallet switching
- Hardware + software wallets together
- Per-wallet settings

---

## 3) Scope

**Included:**
- Multiple wallet creation
- Wallet switching UI
- Per-wallet data isolation
- Wallet renaming
- Wallet deletion with confirmation
- Aggregate portfolio view (optional)
- Import additional wallets

**Not Included:**
- Hardware wallet integration (separate)
- Cross-device wallet sync
- Wallet backup to cloud

---

## 4) Step-by-Step Tasks

### Design Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| D1: Wallet switcher | Sidebar or dropdown | Quick switch | Always accessible |
| D2: Add wallet modal | Create or import | Options clear | Modal flow |
| D3: Wallet card | Name, balance, icon | Visual identity | Per-wallet |
| D4: Aggregate toggle | "All Wallets" option | Combined view | Optional |
| D5: Wallet settings | Per-wallet options | Name, delete | Contextual |
| D6: Delete confirmation | Dangerous action modal | "Delete Wallet" | Requires backup ack |

### Engineering Tasks (Swift)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| E1: Wallet model | Wallet struct | ID, name, type | Identifiable |
| E2: Multi-wallet storage | Store multiple wallets | Keychain per-wallet | WalletStore |
| E3: Wallet service | CRUD operations | Create, read, update, delete | WalletService |
| E4: Active wallet | Track current wallet | Global state | @AppStorage or Environment |
| E5: Wallet switcher UI | Sidebar list | Tap to switch | WalletSwitcher |
| E6: Context switch | Load wallet data | Refresh on switch | Clear and reload |
| E7: Add wallet flow | Create or import | Same as onboarding | Reuse flows |
| E8: Wallet rename | Edit name | Persisted | Inline edit |
| E9: Wallet delete | Remove wallet | Confirmation required | Destructive |
| E10: Delete safeguards | Require backup ack | "I have backed up" | Checkbox |
| E11: Data isolation | Per-wallet storage | Separate namespaces | Prefixed keys |
| E12: Aggregate view | Combine all balances | Optional toggle | AggregatePortfolio |
| E13: Per-wallet settings | Separate settings | Some settings global | SettingsService |

### QA Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| Q1: Add wallet | Create new | Appears in switcher | Happy path |
| Q2: Switch wallet | Tap to switch | Data changes | Context switch |
| Q3: Import wallet | Import seed | New wallet created | Import flow |
| Q4: Rename wallet | Change name | Updated everywhere | Persistence |
| Q5: Delete wallet | Delete with confirm | Removed from list | Destructive |
| Q6: Aggregate view | Enable toggle | All balances combined | Math correct |

---

## 5) Acceptance Criteria

- [ ] Can create additional wallets
- [ ] Can import additional wallets
- [ ] Wallet switcher visible in sidebar
- [ ] Switching wallets updates all data
- [ ] Each wallet has isolated storage
- [ ] Can rename wallets
- [ ] Can delete wallets with confirmation
- [ ] Deletion requires backup acknowledgment
- [ ] Aggregate portfolio view available
- [ ] Active wallet persists across launches

---

## 6) Edge Cases & Failure States

| Scenario | Detection | UX Response |
|:---|:---|:---|
| Delete last wallet | Count check | Prevent or create new |
| Switch during transaction | Active flow check | "Complete transaction first" |
| Duplicate wallet name | Name check | Allow (show address suffix) |
| Import same wallet twice | Address match | "This wallet already exists" |
| Multiple windows | Window check | Each can show different wallet |

---

## 7) Analytics / Telemetry

| Event Name | Properties | Success/Failure |
|:---|:---|:---|
| `wallet_created` | `wallet_count`, `type` (new/import) | Success |
| `wallet_switched` | `from_index`, `to_index` | Success |
| `wallet_renamed` | - | Success |
| `wallet_deleted` | `wallet_count_after` | Success |
| `aggregate_view_toggled` | `enabled` | Success |

---

## 8) QA Checklist

**Manual Tests:**
- [ ] Create second wallet → appears in switcher
- [ ] Import wallet via seed → appears in switcher
- [ ] Switch to second wallet → data updates
- [ ] First wallet data → still intact when switched back
- [ ] Rename wallet → name updates in switcher
- [ ] Delete wallet → requires confirmation
- [ ] Delete → requires "I have backed up" checkbox
- [ ] Delete → wallet removed from list
- [ ] Aggregate view → shows combined balance
- [ ] Aggregate → individual breakdowns visible
- [ ] Relaunch app → correct wallet active

**Automated Tests:**
- [ ] Unit test: Wallet CRUD operations
- [ ] Unit test: Data isolation
- [ ] Unit test: Aggregate calculation
- [ ] Integration test: Wallet switching
- [ ] UI test: Switcher interaction

---

## 9) Effort & Dependencies

**Effort:** M (3-4 days)

**Dependencies:**
- Keychain multi-wallet support
- Data isolation patterns

**Risks:**
- Data leakage between wallets
- Migration from single-wallet

**Rollout Plan:**
1. Wallet model + storage (Day 1)
2. Switcher UI + context switch (Day 2)
3. Add/delete flows (Day 3)
4. Aggregate view + QA (Day 4)

---

## 10) Definition of Done

- [ ] Multiple wallets supported
- [ ] Wallet switcher functional
- [ ] Data isolated per wallet
- [ ] Add wallet works
- [ ] Delete wallet works (with safeguards)
- [ ] Rename works
- [ ] Aggregate view works
- [ ] Active wallet persists
- [ ] Analytics events firing
- [ ] PR reviewed and merged
