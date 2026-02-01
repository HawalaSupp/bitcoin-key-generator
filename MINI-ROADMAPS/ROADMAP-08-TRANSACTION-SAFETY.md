# ROADMAP-08 — Transaction Safety & Scam Protection

**Theme:** Transaction Safety / Scam Prevention  
**Priority:** P0 (Emergency)  
**Target Outcome:** Comprehensive scam protection with address screening, approval management, and simulation

---

## 1) What This Fixes (Mapped to MASTER REVIEW)

- **[Critical] No Address Screening Against Scam Database** (Section 3.6)
- **[Critical] Unlimited Approvals Default** (Section 3.6)
- **[Critical] No Approval Manager to Revoke** (Section 3.6)
- **[High] No Transaction Simulation Preview** (Section 3.6)
- **[High] Phishing Detector Disabled in Code** (Section 3.7)
- **[High] Unverified Contracts Not Flagged** (Section 3.7)
- **[Medium] Suspicious Transaction Patterns Not Detected** (Section 3.7)
- **[Medium] No "Honeypot" Token Detection** (Section 3.7)
- **Top 10 Failures #1** — No Address Screening
- **Top 10 Failures #3** — Approval Manager Missing
- **Phase 0 P0-6** — Address screening API integration
- **Phase 0 P0-10** — Re-enable PhishingDetector.swift
- **Phase 1 P1-1** — Approval manager (list + revoke)
- **Phase 2 P2-1** — Transaction simulation preview
- **Phase 2 P2-2** — Honeypot token detection
- **Blueprint 5.5** — Ideal Approval Manager
- **Edge Case #25** — Contract requests unlimited approval
- **Edge Case #26** — User approves contract then it gets exploited
- **Edge Case #27** — Malicious contract disguised as known protocol
- **Edge Case #28** — User connects to phishing WalletConnect
- **Edge Case #33** — Sanctioned/OFAC address detection
- **Edge Case #35** — Address previously associated with rug pull
- **Edge Case #36** — Token flagged as honeypot
- **Edge Case #45** — Malicious site impersonates Uniswap
- **Microcopy Pack** — Approval Warning, Scam Alert

---

## 2) User Impact

**Before:**
- No warning when sending to known scam addresses
- Unlimited token approvals drain wallets
- No way to view or revoke approvals
- Phishing detector disabled
- No transaction simulation

**After:**
- Scam address blocked with warning
- Approval defaults to exact amount
- Full approval manager with revoke
- Phishing detector active
- Transaction simulation shows expected outcome

---

## 3) Scope

**Included:**
- Address screening API integration
- Scam address blocking with warning modal
- Exact amount approval default
- Approval manager (view + revoke)
- Re-enable PhishingDetector.swift
- Contract verification display
- Honeypot token detection
- Transaction simulation preview
- Sanctioned address check

**Not Included:**
- Smart contract audit integration
- Insurance coverage
- Recovery services

---

## 4) Step-by-Step Tasks

### Design Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| D1: Scam warning modal | Red blocking modal | Clear warning text | "Known Scam Address" |
| D2: Approval amount picker | Exact / Unlimited toggle | Exact default | Show amounts |
| D3: Approval manager screen | List of approvals | Revoke button per item | Accessible from Settings |
| D4: Verification badges | Verified ✓ / Unverified ⚠ | On contracts | Etherscan data |
| D5: Honeypot warning | Orange warning | "Token may be untradable" | Block or warn |
| D6: Simulation preview | Before/after balances | Clear diff display | Green/red changes |
| D7: Phishing site warning | Red modal | "Suspicious site" | WalletConnect context |

### Engineering Tasks (Swift)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| E1: Address screening API | Call screening service | Return risk level | Chainalysis/similar |
| E2: Scam address modal | Block tx + show warning | Require "I understand" | Red modal |
| E3: Exact approval default | Default to exact amount | Override available | SwapService |
| E4: Approval manager view | List all approvals | Fetch from chain | ApprovalManagerView |
| E5: Revoke approval tx | Generate revoke tx | Send to chain | Standard ERC-20 revoke |
| E6: Re-enable phishing | Uncomment/fix detector | Active on WalletConnect | PhishingDetector.swift |
| E7: Contract verification | Check Etherscan verified | Display badge | API call |
| E8: Unverified warning | Show warning for unverified | Interstitial | Before tx confirm |
| E9: Honeypot detection | API check for honeypot | Block or warn | GoPlus/similar API |
| E10: Transaction simulation | Call simulation API | Display expected result | Tenderly/Blowfish |
| E11: Simulation UI | Before/after balances | Color-coded diff | SimulationPreviewView |
| E12: Sanctioned address | Check against OFAC list | Block completely | Compliance requirement |
| E13: Suspicious pattern detect | Analyze tx patterns | Warn on anomalies | Heuristics |

### API Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| A1: Address screening | Integrate Chainalysis/GoPlus | Risk score response | Real-time |
| A2: Contract verification | Etherscan API | Verified status | Cached |
| A3: Honeypot detection | GoPlus Security API | Honeypot flag | Real-time |
| A4: Transaction simulation | Tenderly/Blowfish API | State diff | Pre-sign |

### QA Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| Q1: Scam address | Send to known scam | Blocked with modal | Test address |
| Q2: Approval default | Initiate swap | Exact amount default | Not unlimited |
| Q3: Approval manager | View approvals | All shown correctly | Multi-chain |
| Q4: Revoke approval | Revoke an approval | Tx sent, removed | End-to-end |
| Q5: Phishing detector | Connect suspicious dApp | Warning shown | WalletConnect |
| Q6: Honeypot token | Add known honeypot | Warning displayed | Test token |
| Q7: Simulation | Preview swap tx | Before/after shown | Accurate values |

---

## 5) Acceptance Criteria

- [ ] Address screening API integrated
- [ ] Known scam addresses blocked with warning modal
- [ ] Warning requires acknowledgment to proceed
- [ ] Approval defaults to exact amount (not unlimited)
- [ ] "Unlimited" option available but warned
- [ ] Approval manager lists all active approvals
- [ ] Revoke button functional for each approval
- [ ] Revoke transaction sent and confirmed
- [ ] PhishingDetector.swift re-enabled and active
- [ ] Unverified contracts show warning badge
- [ ] Honeypot tokens detected and warned
- [ ] Transaction simulation shows before/after balances
- [ ] Sanctioned addresses completely blocked
- [ ] Suspicious patterns trigger warning

---

## 6) Edge Cases & Failure States

| Scenario | Detection | UX Response |
|:---|:---|:---|
| Known scam address | Screening API | Block + red modal |
| Unlimited approval request | Approval amount check | Default to exact; warn if unlimited |
| Contract unverified | Etherscan API | Orange badge + interstitial |
| Phishing WalletConnect | Domain check | Red modal, block connection |
| Honeypot token | GoPlus API | Orange warning + block swap |
| Simulation fails | API error | "Simulation unavailable. Proceed?" |
| Sanctioned address | OFAC list | Completely blocked, no override |
| Screening API timeout | Request timeout | Proceed with warning "Unable to verify" |
| Impersonation contract | Similarity check | "This contract is not [Uniswap]" |

---

## 7) Analytics / Telemetry

| Event Name | Properties | Success/Failure |
|:---|:---|:---|
| `address_screened` | `address_truncated`, `risk_level` | Success |
| `scam_address_blocked` | `address_truncated`, `user_proceeded` | Warning |
| `approval_requested` | `token`, `spender`, `amount_type` (exact/unlimited) | Success |
| `approval_unlimited_warned` | `token`, `spender` | Warning |
| `approval_manager_opened` | `approval_count` | Success |
| `approval_revoked` | `token`, `spender`, `tx_hash` | Success |
| `phishing_detected` | `domain`, `blocked` | Warning |
| `contract_unverified_warning` | `contract_address` | Warning |
| `honeypot_detected` | `token_address`, `blocked` | Warning |
| `simulation_completed` | `expected_balance_change` | Success |
| `simulation_failed` | `error_type` | Failure |
| `sanctioned_address_blocked` | `address_truncated` | Block |

---

## 8) QA Checklist

**Manual Tests:**
- [ ] Send to known scam address → blocked
- [ ] Acknowledge scam warning → allowed (if implemented)
- [ ] Initiate swap → approval is exact amount
- [ ] Toggle to unlimited → warning shown
- [ ] Open approval manager → see all approvals
- [ ] Revoke approval → transaction sent
- [ ] After revoke → approval removed from list
- [ ] Connect to phishing dApp → warning shown
- [ ] Interact with unverified contract → warning shown
- [ ] Add honeypot token → warning displayed
- [ ] Preview transaction → simulation shown
- [ ] Simulation shows correct balance changes
- [ ] Sanctioned address → completely blocked

**Automated Tests:**
- [ ] Unit test: Address screening logic
- [ ] Unit test: Approval amount handling
- [ ] Unit test: Phishing domain detection
- [ ] Integration test: Simulation API
- [ ] UI test: Approval manager flow

---

## 9) Effort & Dependencies

**Effort:** L (5-6 days)

**Dependencies:**
- Address screening API (Chainalysis/GoPlus)
- Transaction simulation API (Tenderly/Blowfish)
- Etherscan verification API

**Risks:**
- API costs for screening services
- Simulation accuracy for complex transactions

**Rollout Plan:**
1. Address screening + scam modal (Day 1)
2. Approval defaults + warnings (Day 2)
3. Approval manager + revoke (Day 3)
4. Re-enable phishing detector (Day 4)
5. Simulation preview + honeypot (Day 5)
6. QA + edge cases (Day 6)

---

## 10) Definition of Done

- [ ] Address screening integrated
- [ ] Scam addresses blocked
- [ ] Exact approval default
- [ ] Approval manager functional
- [ ] Revoke working
- [ ] Phishing detector active
- [ ] Contract verification displayed
- [ ] Honeypot detection working
- [ ] Simulation preview functional
- [ ] Sanctioned addresses blocked
- [ ] Analytics events firing
- [ ] PR reviewed and merged
