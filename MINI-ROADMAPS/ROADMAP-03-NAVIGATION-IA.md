# ROADMAP-03 — Navigation & Information Architecture

**Theme:** Navigation / UX Structure  
**Priority:** P0 (Emergency)  
**Target Outcome:** Consistent, predictable navigation with proper macOS patterns

---

## 1) What This Fixes (Mapped to MASTER REVIEW)

- **[Critical] ContentView.swift 11k+ LOC God File** (Section 3.2)
- **[Critical] Inconsistent Back/Close Gestures** (Section 3.2)
- **[High] Settings Hidden in Avatar Menu** (Section 3.2)
- **[High] Missing Keyboard Shortcuts for Core Actions** (Section 3.2)
- **[Medium] Deep-Linked Transactions Don't Preserve Navigation Stack** (Section 3.2)
- **Top 10 Failures #4** — SwiftUI Performance Nightmare
- **Phase 0 P0-4** — Add ⌘,  for settings everywhere
- **Phase 0 P0-5** — Consistent back/close behavior
- **Conflict Decision** — Back vs Close gesture (swipe always back, × always close modal)
- **Blueprint 5.3** — Ideal Send Flow
- **Blueprint 5.6** — Ideal Settings & Security Center
- **Edge Case #50** — User is deep in swap flow; receives deep link
- **Edge Case #51** — User rotates device during transition
- **macOS Native Issues (Section 3.12)** — NavigationSplitView, keyboard nav, window sizing

---

## 2) User Impact

**Before:**
- Users get lost in navigation hierarchy
- Swipe gestures behave inconsistently
- Settings require hunting
- No keyboard shortcuts for power users
- Deep links break navigation state

**After:**
- Predictable navigation with clear visual hierarchy
- Swipe = back, × = close modal (always)
- Settings accessible via ⌘,  from anywhere
- Full keyboard navigation for macOS users
- Deep links preserve or gracefully reset context

---

## 3) Scope

**Included:**
- Split ContentView.swift into feature modules
- Standardize back/close gesture behavior
- Add ⌘,  Settings shortcut globally
- Add core keyboard shortcuts (⌘R refresh, ⌘N new, etc.)
- Deep link navigation handler
- NavigationSplitView for macOS

**Not Included:**
- Individual screen redesigns (separate roadmaps)
- New features
- Animation system overhaul

---

## 4) Step-by-Step Tasks

### Architecture Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| A1: Audit ContentView.swift | Document all embedded views/logic | Inventory for extraction | Prerequisite |
| A2: Create feature modules | Portfolio, Send, Swap, Settings, etc. | Each under 500 LOC | /Sources/Hawala/Features/ |
| A3: Extract ViewModels | Separate business logic from views | MVVM pattern | Each feature gets VM |
| A4: Create NavigationRouter | Centralized navigation state | Single source of truth | Handles deep links |
| A5: Extract to Coordinator | Navigation coordination layer | Clean screen transitions | Optional pattern |

### Design Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| D1: Navigation audit | Document all current flows | Map inconsistencies | Before/after |
| D2: Gesture standard | Define swipe/button behaviors | Swipe=back, ×=close | Document in design system |
| D3: Keyboard shortcut sheet | List all shortcuts | Printable reference | ⌘?  to show |

### Engineering Tasks (Swift)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| E1: Add ⌘,  Settings | Global keyboard shortcut | Opens Settings from anywhere | `.keyboardShortcut(",", modifiers: .command)` |
| E2: Add ⌘R refresh | Refresh current view data | Works in Portfolio, Token, History | Context-aware |
| E3: Add ⌘N new transaction | Open Send screen | Quick access | From Portfolio |
| E4: Add ⌘?  help | Show shortcuts sheet | Modal with all shortcuts | HelpView |
| E5: Standardize back gesture | Swipe right = back only | Never closes modals | NavigationStack config |
| E6: Standardize close button | × closes modals/sheets | No swipe-to-close | Sheet presentation |
| E7: Deep link handler | Parse URLs, route correctly | Preserve or reset state | NavigationRouter |
| E8: NavigationSplitView | macOS sidebar navigation | Proper 3-column layout | `.navigationSplitViewStyle(.balanced)` |
| E9: Minimum window size | Set 900×600 minimum | Prevent layout breakage | `.frame(minWidth: 900, minHeight: 600)` |
| E10: Split ContentView | Extract features to modules | ContentView < 300 LOC | Incremental refactor |

### QA Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| Q1: Navigation regression | Test all navigation paths | No broken transitions | Manual sweep |
| Q2: Keyboard shortcuts | Verify all shortcuts work | Context-aware behavior | Matrix test |
| Q3: Deep link testing | Test all deep link types | Correct routing | URL schemes |
| Q4: Window sizing | Resize window to extremes | No layout breakage | Edge test |

---

## 5) Acceptance Criteria

- [x] ⌘, opens Settings from any screen ✅ (KeyboardShortcutRouter)
- [x] ⌘R refreshes data in context ✅ (KeyboardShortcutRouter)
- [x] ⌘? shows keyboard shortcuts ✅ (⌘⇧/ → KeyboardShortcutsHelpView)
- [x] Swipe right = back (never closes modals) ✅ (.hawalaModal())
- [x] × button = close modal (consistent placement) ✅ (ModalCloseButton)
- [x] Deep links route correctly without breaking state ✅ (NavigationRouter)
- [x] Minimum window size enforced (900×600) ✅ (.frame(minWidth:minHeight:))
- [ ] ContentView.swift reduced to < 300 LOC — **PARTIAL: 10,115 → 6,456 LOC (-36%)**
- [ ] Feature modules each < 500 LOC — **PARTIAL: Some modules compliant**
- [ ] NavigationSplitView used on macOS — **DEFERRED: Requires major refactor**

### Progress Notes (Session 2025-01)
- Removed 3,659 lines of dead send sheet code
- Created BalanceFetchService (not yet integrated)
- TransactionHistoryService migrated
- Gesture standardization complete
- Keyboard shortcuts fully implemented

---

## 6) Edge Cases & Failure States

| Scenario | Detection | UX Response |
|:---|:---|:---|
| Deep link while in transaction | Router intercept | Confirm dialog: "Abandon transaction?" |
| ⌘,  during sheet | Focus detection | Close sheet, then open Settings |
| Swipe at navigation root | Stack depth check | No-op (nothing to go back to) |
| Window resized very small | Frame constraints | Enforce minimum size |
| Deep link with invalid params | URL validation | Show error, stay on current screen |
| Rapid navigation taps | Debounce | Ignore duplicate requests |

---

## 7) Analytics / Telemetry

| Event Name | Properties | Success/Failure |
|:---|:---|:---|
| `navigation_transition` | `from_screen`, `to_screen`, `method` (tap/swipe/keyboard) | Success |
| `keyboard_shortcut_used` | `shortcut`, `context_screen` | Success |
| `deep_link_received` | `url_scheme`, `path`, `params` | Success |
| `deep_link_routed` | `destination_screen`, `preserved_state` | Success |
| `deep_link_failed` | `error_type`, `url` | Failure |
| `navigation_conflict` | `active_flow`, `requested_flow` | Conflict |

---

## 8) QA Checklist

**Manual Tests:**
- [ ] ⌘,  opens Settings from Portfolio
- [ ] ⌘,  opens Settings from Send flow (mid-transaction)
- [ ] ⌘R refreshes portfolio balances
- [ ] ⌘?  shows shortcuts sheet
- [ ] Swipe right in navigation stack goes back
- [ ] Swipe on modal does NOT close modal
- [ ] × button closes modals consistently
- [ ] Deep link to transaction detail works
- [ ] Deep link while in Swap prompts confirmation
- [ ] Window minimum size enforced
- [ ] NavigationSplitView shows sidebar on macOS

**Automated Tests:**
- [ ] Unit test: NavigationRouter deep link parsing
- [ ] Unit test: Keyboard shortcut registration
- [ ] UI test: Navigation flow completion
- [ ] UI test: Gesture behavior validation

---

## 9) Effort & Dependencies

**Effort:** L (5-7 days)

**Dependencies:**
- ContentView split blocks other feature work
- NavigationRouter needed for deep links

**Risks:**
- Large refactor = regression risk
- Incremental approach recommended

**Rollout Plan:**
1. Audit and plan extraction (Day 1)
2. Create NavigationRouter (Day 2)
3. Extract Portfolio module (Day 3)
4. Extract Send/Receive modules (Day 4)
5. Extract Settings/Swap modules (Day 5)
6. Keyboard shortcuts + cleanup (Day 6)
7. QA + regression testing (Day 7)

---

## 10) Definition of Done

- [ ] ContentView.swift < 300 LOC
- [ ] Feature modules created and functional
- [ ] All keyboard shortcuts working
- [ ] Gesture behavior standardized
- [ ] Deep links route correctly
- [ ] macOS patterns (NavigationSplitView) implemented
- [ ] Window sizing enforced
- [ ] No navigation regressions
- [ ] Analytics events firing
- [ ] PR reviewed and merged
