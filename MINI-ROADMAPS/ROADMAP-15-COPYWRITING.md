# ROADMAP-15 — Copywriting & Microcopy

**Theme:** Copywriting / UX Writing  
**Priority:** P2 (Medium)  
**Target Outcome:** Clear, consistent, human-readable copy throughout the app

---

## 1) What This Fixes (Mapped to MASTER REVIEW)

- **[High] Error Messages Are Technical/Unhelpful** (Section 3.14)
- **[Medium] Inconsistent Terminology (wallet vs. account)** (Section 3.14)
- **[Medium] No Empty State Guidance** (Section 3.14)
- **[Medium] Loading States Say "Loading..."** (Section 3.14)
- **[Low] Button Labels Not Action-Oriented** (Section 3.14)
- **[Low] Tooltips Missing Throughout** (Section 3.14)
- **Microcopy Pack** — Full section with recommended copy
- **Blueprint** — All blueprints include copy examples
- **Edge Case** — Multiple scenarios reference user confusion

---

## 2) User Impact

**Before:**
- Error messages show technical jargon
- Inconsistent wallet/account terminology
- Empty states offer no guidance
- "Loading..." provides no context

**After:**
- Human-readable error messages with actions
- Consistent terminology throughout
- Helpful empty states with CTAs
- Contextual loading messages

---

## 3) Scope

**Included:**
- Error message rewrite
- Terminology standardization
- Empty state copy with CTAs
- Loading state copy
- Button label improvements
- Tooltip additions
- Confirmation dialog copy
- Success message copy

**Not Included:**
- Full localization (L10n)
- Marketing copy
- Legal/compliance copy review

---

## 4) Step-by-Step Tasks

### Content Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| C1: Terminology glossary | Define standard terms | wallet, account, send, etc. | Single source |
| C2: Error message audit | List all error messages | Document current copy | Spreadsheet |
| C3: Error message rewrite | Human-readable versions | Include actions | From MASTER REVIEW |
| C4: Empty state audit | List all empty states | Document current | Spreadsheet |
| C5: Empty state copy | Helpful messages + CTAs | Guide next action | Friendly tone |
| C6: Loading state audit | List all loading states | Context-specific | Not "Loading..." |
| C7: Button label audit | Review all buttons | Action-oriented | Verb-first |
| C8: Tooltip content | Write tooltips | For complex features | Concise |
| C9: Confirmation dialogs | Review all confirmations | Clear consequences | Action/Cancel |
| C10: Success messages | Celebrate completions | Positive feedback | Brief |

### Engineering Tasks (Swift)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| E1: String catalog | Centralized strings | Localizable.strings | All copy extracted |
| E2: Error mapping | Map errors to user copy | Technical → human | ErrorMessages enum |
| E3: Apply error copy | Replace all error displays | New messages shown | Throughout app |
| E4: Empty state views | Create EmptyStateView | Reusable component | Icon + text + CTA |
| E5: Apply empty states | Use in all empty contexts | Consistent experience | Portfolio, NFT, etc. |
| E6: Loading messages | Context-specific loading | "Fetching balances..." | Per-view loading |
| E7: Button labels | Update button text | Action verbs | "Send ETH" not "Send" |
| E8: Add tooltips | `.help()` modifier | Hover reveals info | Complex elements |
| E9: Confirmation dialogs | Standardized dialog | Title, body, actions | ConfirmationDialog |
| E10: Success toasts | Toast component | Positive feedback | Green checkmark |

### QA Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| Q1: Error messages | Trigger various errors | Human-readable | No technical jargon |
| Q2: Empty states | View empty screens | Helpful copy + CTA | All contexts |
| Q3: Loading states | Block network | Context-specific | Not "Loading..." |
| Q4: Button labels | Review all buttons | Action-oriented | Visual audit |
| Q5: Tooltips | Hover on elements | Tooltips appear | Where appropriate |
| Q6: Terminology | Search for inconsistencies | Consistent terms | Global search |

---

## 5) Acceptance Criteria

- [ ] Terminology glossary defined and followed
- [ ] All error messages human-readable
- [ ] Error messages include actionable guidance
- [ ] All empty states have helpful copy
- [ ] Empty states include CTAs where appropriate
- [ ] Loading states are context-specific
- [ ] No generic "Loading..." anywhere
- [ ] Button labels are action-oriented (verb-first)
- [ ] Tooltips present for complex features
- [ ] Confirmation dialogs have clear consequences
- [ ] Success messages provide positive feedback
- [ ] Copy extracted to Localizable.strings

---

## 6) Microcopy Examples (from MASTER REVIEW)

### Error Messages

| Before | After |
|:---|:---|
| "Error: invalid_address" | "This doesn't look like a valid address. Check for typos and try again." |
| "Network error" | "Can't reach the network right now. Check your connection and try again." |
| "Transaction failed" | "Transaction couldn't be completed. You haven't lost any funds." |
| "Insufficient balance" | "You don't have enough ETH for this transaction (including fees)." |

### Empty States

| Context | Copy |
|:---|:---|
| Portfolio (no tokens) | "Your wallet is empty. Buy or receive crypto to get started." |
| NFT Gallery (no NFTs) | "No NFTs yet. Buy your first NFT or receive one from a friend." |
| Transaction History | "No transactions yet. Send or receive crypto to see activity here." |
| Swap History | "No swaps yet. Exchange tokens to see your swap history." |

### Loading States

| Context | Copy |
|:---|:---|
| Portfolio | "Fetching your balances..." |
| Token Prices | "Getting latest prices..." |
| Transaction History | "Loading your activity..." |
| NFT Gallery | "Loading your collection..." |

### Button Labels

| Before | After |
|:---|:---|
| "Send" | "Send ETH" or "Review Send" |
| "Confirm" | "Confirm Transaction" |
| "OK" | "Got It" or "Continue" |
| "Cancel" | "Go Back" or "Cancel Send" |

---

## 7) Analytics / Telemetry

| Event Name | Properties | Success/Failure |
|:---|:---|:---|
| `error_displayed` | `error_type`, `has_action` | Displayed |
| `error_action_tapped` | `error_type`, `action` | User engaged |
| `empty_state_cta_tapped` | `context`, `cta_action` | Success |
| `tooltip_viewed` | `element_id` | Info |

---

## 8) QA Checklist

**Manual Tests:**
- [ ] Trigger "invalid address" → human-readable message
- [ ] Disconnect network → friendly network error
- [ ] View empty portfolio → helpful message + CTA
- [ ] View empty NFT gallery → helpful message + CTA
- [ ] View empty history → helpful message + CTA
- [ ] Block network, view portfolio → "Fetching balances..."
- [ ] Check all buttons → verb-first labels
- [ ] Hover on fee selector → tooltip appears
- [ ] Confirm send → clear confirmation dialog
- [ ] Complete send → success toast appears
- [ ] Search code for "wallet" vs "account" → consistent usage

**Automated Tests:**
- [ ] Unit test: Error message mapping
- [ ] Snapshot test: Empty state views
- [ ] Lint: Localizable.strings format

---

## 9) Effort & Dependencies

**Effort:** S (2-3 days)

**Dependencies:**
- UX writer review (optional)
- MASTER REVIEW Microcopy Pack

**Risks:**
- Copy changes may need stakeholder approval
- Localization infrastructure needed for future

**Rollout Plan:**
1. Error messages + terminology (Day 1)
2. Empty states + loading states (Day 2)
3. Buttons + tooltips + QA (Day 3)

---

## 10) Definition of Done

- [ ] Terminology glossary created and followed
- [ ] All error messages rewritten
- [ ] All empty states have copy + CTAs
- [ ] All loading states context-specific
- [ ] Button labels action-oriented
- [ ] Tooltips added for complex features
- [ ] Confirmation dialogs clear
- [ ] Success messages positive
- [ ] Copy in Localizable.strings
- [ ] No technical jargon visible to users
- [ ] PR reviewed and merged
