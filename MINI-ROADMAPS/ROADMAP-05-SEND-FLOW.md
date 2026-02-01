# ROADMAP-05 — Send Flow & Transaction Safety

**Theme:** Send / Transaction Safety  
**Priority:** P0 (Emergency)  
**Target Outcome:** Zero-mistake sending with address validation, confirmation, and scam prevention

---

## 1) What This Fixes (Mapped to MASTER REVIEW)

- **[Critical] UInt64 Overflow in Transaction Preview** (Section 3.4)
- **[Critical] Clipboard Address Not Validated** (Section 3.4)
- **[Critical] Dust Attacks Show in Transaction List** (Section 3.4)
- **[High] No First-Time Address Warning** (Section 3.4)
- **[High] No "Send All" or Max Button** (Section 3.4)
- **[High] No Recent Recipients List** (Section 3.4)
- **[Medium] Amount Input Accepts Invalid Characters** (Section 3.4)
- **[Medium] No Estimated Arrival Time** (Section 3.4)
- **Top 10 Failures #2** — No First-Send Warning
- **Top 10 Failures #8** — UInt64 Overflow Not Guarded
- **Phase 0 P0-3** — First-time address warning modal
- **Phase 0 P0-7** — Validate clipboard before paste
- **Phase 0 P0-8** — Dust attack filter (< $0.01 → "Spam" tab)
- **Blueprint 5.3** — Ideal Send Flow
- **Conflict Decision** — Dust Attack Handling (hybrid: 3 tabs)
- **Edge Case #7** — User pastes address with wrong network
- **Edge Case #8** — User pastes address with extra whitespace
- **Edge Case #9** — User types amount with locale separator
- **Edge Case #10** — Amount exceeds balance
- **Edge Case #11** — Amount is zero or negative
- **Edge Case #15** — Transaction size exceeds block limit
- **Edge Case #16** — Fee estimate expires before confirmation
- **Edge Case #17** — Double-tap on confirm button
- **Edge Case #29** — User pastes "0x" only (incomplete address)
- **Microcopy Pack** — Send Flow, First Address Warning

---

## 2) User Impact

**Before:**
- UInt64 overflow can cause incorrect amounts
- Pasted addresses not validated (wrong network)
- No warning for first-time addresses (phishing risk)
- No "Max" button requires mental math
- Dust attacks clutter transaction history

**After:**
- Safe numeric handling prevents overflow
- Address validation before paste acceptance
- First-time address warning modal
- "Max" button for full balance sends
- Dust attacks filtered to "Spam" tab

---

## 3) Scope

**Included:**
- UInt64 overflow guard (use Decimal or BigInt)
- Address validation on paste (format + network)
- First-time address warning modal
- "Max" / "Send All" button
- Recent recipients list
- Amount input validation (numeric only)
- Estimated arrival time
- Double-tap prevention on confirm
- Dust attack filtering (< $0.01)

**Not Included:**
- Address book management (separate roadmap)
- Multi-recipient sends
- Scheduled/recurring sends

---

## 4) Step-by-Step Tasks

### Design Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| D1: First-time warning modal | Orange warning with checksum | Clear, not scary | Proceed / Cancel |
| D2: Max button | "Max" pill near amount input | One-tap fill | Account for fees |
| D3: Recent recipients | Horizontal scroll or dropdown | Show last 5 | Avatar + truncated address |
| D4: Validation error states | Inline error messages | Red border + text | Amount, address fields |
| D5: ETA display | Estimated arrival time | "~2 min" format | Below fee selector |
| D6: Spam tab design | Third tab in history | "Spam (12)" badge | Filterable |

### Engineering Tasks (Swift)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| E1: Fix UInt64 overflow | Use Decimal or BigInt | No overflow possible | `Decimal` type |
| E2: Address validation | Validate format + checksum | Reject invalid | Per-network rules |
| E3: Network mismatch check | Detect wrong network address | Show error | Network-specific regex |
| E4: Whitespace trim | Strip whitespace from paste | Automatic cleanup | `.trimmingCharacters` |
| E5: First-time warning | Modal for new addresses | Require acknowledgment | AddressHistoryService |
| E6: Max button | Calculate max - fees | One tap fills amount | Fee estimation first |
| E7: Recent recipients | Show last 5 addresses | Tappable to select | Persisted list |
| E8: Amount validation | Numeric input only | Block letters/symbols | `.keyboardType(.decimalPad)` |
| E9: Locale separator | Handle , and . | Convert to canonical | NumberFormatter |
| E10: Balance check | Amount ≤ balance | Show error if exceeded | Real-time validation |
| E11: Zero/negative check | Reject invalid amounts | Show error | Input validation |
| E12: ETA display | Calculate from fee + network | Show "~X min" | Network-specific logic |
| E13: Double-tap guard | Disable button after tap | Prevent duplicate tx | Button state |
| E14: Dust filter | < $0.01 → Spam tab | Hide from main list | TransactionFilter |
| E15: Transaction size check | Verify against block limit | Error if too large | Per-network limits |
| E16: Fee expiry warning | Detect stale fee estimate | Prompt to refresh | Timestamp check |

### Engineering Tasks (Rust)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| R1: Address validation API | Validate address for network | Return valid/invalid + reason | Per-chain rules |
| R2: Checksum verification | EIP-55 and equivalents | Case-sensitive validation | Existing libs |
| R3: Fee estimation | Fresh fee estimates | Return with timestamp | Provider calls |

### QA Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| Q1: Overflow test | Send 2^63 wei equivalent | No crash or wrong amount | Critical |
| Q2: Wrong network paste | Paste BTC address in ETH | Shows error | Validation |
| Q3: First-time warning | Send to new address | Warning modal appears | UX check |
| Q4: Max button | Tap Max, verify amount | Correct after fees | Math check |
| Q5: Spam filtering | Receive 0.000001 ETH | Goes to Spam tab | Filter check |

---

## 5) Acceptance Criteria

- [ ] No UInt64 overflow possible (Decimal type used)
- [ ] Pasted addresses validated for format
- [ ] Pasted addresses validated for correct network
- [ ] Whitespace automatically trimmed from paste
- [ ] First-time address shows warning modal
- [ ] Warning requires explicit acknowledgment
- [ ] "Max" button calculates balance - fees
- [ ] Recent recipients list shows last 5
- [ ] Amount input rejects non-numeric characters
- [ ] Locale separators (,) converted correctly
- [ ] Amount > balance shows error
- [ ] Zero amount shows error
- [ ] ETA displayed for transaction
- [ ] Double-tap on confirm prevented
- [ ] Dust transactions (< $0.01) filtered to Spam tab
- [ ] Spam tab accessible in transaction history
- [ ] Fee expiry prompts refresh if > 30s old

---

## 6) Edge Cases & Failure States

| Scenario | Detection | UX Response |
|:---|:---|:---|
| UInt64 overflow | Decimal range check | Use Decimal; never overflow |
| Wrong network address | Regex mismatch | "This looks like a [BTC] address" |
| Incomplete address "0x" | Length check | "Address is incomplete" |
| Extra whitespace | Trim operation | Silently clean |
| First-time address | Not in history | Warning modal |
| Amount exceeds balance | Comparison | "Insufficient balance" error |
| Zero amount | Value check | "Amount must be greater than 0" |
| Negative amount | Value check | Reject input entirely |
| Locale separator | Parse flexibility | Accept both , and . |
| Double-tap confirm | Button disable | Ignore second tap |
| Fee estimate expired | Timestamp > 30s | "Fee may have changed. Refresh?" |
| Transaction too large | Size check | "Transaction too large for network" |
| Dust transaction | Value < $0.01 | Auto-filter to Spam |

---

## 7) Analytics / Telemetry

| Event Name | Properties | Success/Failure |
|:---|:---|:---|
| `send_started` | `network`, `amount_usd` | Success |
| `address_pasted` | `valid`, `network_match` | Success/Failure |
| `first_address_warning_shown` | `address_truncated` | Success |
| `first_address_warning_acknowledged` | `proceed` (bool) | Success |
| `max_button_tapped` | `calculated_amount` | Success |
| `amount_validation_error` | `error_type` | Failure |
| `send_confirmed` | `amount_usd`, `fee_usd`, `network` | Success |
| `send_failed` | `error_type`, `network` | Failure |
| `dust_transaction_filtered` | `amount_usd`, `from_address` | Success |

---

## 8) QA Checklist

**Manual Tests:**
- [ ] Enter maximum uint64 value → no crash
- [ ] Paste ETH address in BTC field → error shown
- [ ] Paste "0x" only → "Address incomplete" error
- [ ] Paste address with spaces → spaces trimmed
- [ ] Send to new address → warning modal appears
- [ ] Acknowledge warning → proceed to confirmation
- [ ] Tap Max → amount = balance - fees
- [ ] Enter "1,5" (European locale) → parsed as 1.5
- [ ] Enter amount > balance → error shown
- [ ] Enter "0" amount → error shown
- [ ] Enter "abc" → rejected/blocked
- [ ] Verify ETA displayed
- [ ] Double-tap confirm → only 1 transaction
- [ ] Receive < $0.01 → appears in Spam tab
- [ ] Spam tab shows correct count

**Automated Tests:**
- [ ] Unit test: Decimal overflow protection
- [ ] Unit test: Address validation per network
- [ ] Unit test: Amount parsing with locales
- [ ] Unit test: Dust transaction filter
- [ ] Integration test: Full send flow

---

## 9) Effort & Dependencies

**Effort:** L (4-5 days)

**Dependencies:**
- Address validation library (per network)
- Fee estimation service

**Risks:**
- Per-network address rules are complex
- Decimal precision for very small amounts

**Rollout Plan:**
1. UInt64 → Decimal migration (Day 1)
2. Address validation + network check (Day 2)
3. First-time warning + recent recipients (Day 3)
4. Max button + amount validation (Day 4)
5. Dust filter + QA (Day 5)

---

## 10) Definition of Done

- [ ] Decimal type used (no overflow)
- [ ] Address validation comprehensive
- [ ] First-time warning working
- [ ] Max button functional
- [ ] Recent recipients displayed
- [ ] Amount input validated
- [ ] ETA displayed
- [ ] Double-tap prevented
- [ ] Dust filtering working
- [ ] All edge cases handled
- [ ] Analytics events firing
- [ ] PR reviewed and merged
