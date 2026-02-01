# ROADMAP-19 — QA & Edge Case Coverage

**Theme:** Quality Assurance  
**Priority:** P1 (High)  
**Target Outcome:** Comprehensive edge case handling and QA infrastructure

---

## 1) What This Fixes (Mapped to MASTER REVIEW)

- **Section 3.16 — QA & Edge Cases** — All 60 edge cases from MASTER REVIEW
- **[Critical] No Unit Tests for Crypto Operations** (Section 3.16)
- **[High] No Integration Test Suite** (Section 3.16)
- **[High] No Fuzzing for User Input** (Section 3.16)
- **[Medium] Error States Not Tested** (Section 3.16)
- **[Medium] Offline Mode Not Tested** (Section 3.16)
- **Phase 2 P2-7** — Comprehensive test coverage
- **All 60 Edge Cases** — Listed in MASTER REVIEW section 6

---

## 2) User Impact

**Before:**
- Edge cases cause crashes or undefined behavior
- No automated testing catches regressions
- Error states poorly handled

**After:**
- All 60 edge cases handled gracefully
- Automated test suite prevents regressions
- Error states tested and polished

---

## 3) Scope

**Included:**
- Unit test infrastructure
- Integration test suite
- UI test coverage
- Edge case handling (all 60)
- Fuzzing for inputs
- Offline mode testing
- Error state testing

**Not Included:**
- Load testing
- Penetration testing
- Third-party audits

---

## 4) Edge Cases Master List (from MASTER REVIEW)

### Onboarding (1-6)
1. ☐ User closes app during seed generation
2. ☐ User screenshots seed phrase (detection)
3. ☐ User imports invalid seed phrase format
4. ☐ Back button during key generation
5. ☐ Kill app during key generation
6. ☐ Passcode/confirm mismatch

### Send Flow (7-19)
7. ☐ Paste address with wrong network
8. ☐ Paste address with extra whitespace
9. ☐ Type amount with locale separator (,)
10. ☐ Amount exceeds balance
11. ☐ Amount is zero or negative
12. ☐ Price feed returns $0
13. ☐ Token price > $999,999
14. ☐ Token balance > 999,999,999
15. ☐ Transaction size exceeds block limit
16. ☐ Fee estimate expires before confirmation
17. ☐ Double-tap on confirm button
18. ☐ Network switches during send
19. ☐ User screenshots QR (malware detection)

### Swap (20-24)
20. ☐ Slippage set to 0% (tx will fail)
21. ☐ Swap pair has no liquidity
22. ☐ Token has transfer tax
23. ☐ Price impact > 10%
24. ☐ Swap quote expires before confirmation

### Approvals (25-28)
25. ☐ Contract requests unlimited approval
26. ☐ Approved contract gets exploited
27. ☐ Malicious contract disguised as known
28. ☐ Phishing WalletConnect connection

### Address Validation (29-36)
29. ☐ Paste "0x" only (incomplete address)
30. ☐ User sends to same address repeatedly
31. ☐ Contact on multiple networks
32. ☐ Transaction stuck pending for hours
33. ☐ Sanctioned/OFAC address
34. ☐ User needs tx for tax purposes
35. ☐ Address associated with rug pull
36. ☐ Token flagged as honeypot

### Swap/Bridge (37-39)
37. ☐ Swap receives less due to slippage
38. ☐ Gas price spikes during confirmation
39. ☐ Custom gas too low

### WalletConnect (40-42)
40. ☐ User approves sign without reading
41. ☐ Session connected for days (stale)
42. ☐ dApp sends rapid-fire requests

### Security (43-48)
43. ☐ User forgets passcode
44. ☐ User wants to wipe wallet remotely
45. ☐ Malicious site impersonates Uniswap
46. ☐ Passcode entry triggers duress mode
47. ☐ Clipboard address lingers
48. ☐ Biometric fails 3 times

### Wallet State (49-52)
49. ☐ Force quit during backup display
50. ☐ Deep link during swap flow
51. ☐ Window resize during transition
52. ☐ Multiple windows (if supported)

### Performance (53-55)
53. ☐ User enables high contrast mode
54. ☐ Token list with 500+ assets
55. ☐ Memory pressure causes eviction

### NFT & Other (56-60)
56. ☐ User receives spam NFT
57. ☐ NFT metadata fails to load
58. ☐ VoiceOver navigation
59. ☐ Wallet locked during receive
60. ☐ Hardcoded path doesn't exist

---

## 5) Step-by-Step Tasks

### Infrastructure Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| I1: Unit test framework | XCTest setup | Running in CI | Swift Package |
| I2: Integration test target | Separate test target | App + backend | XCTest |
| I3: UI test target | XCUITest setup | Full flows | Automation |
| I4: Code coverage | Coverage reporting | Track % | Xcode built-in |
| I5: CI integration | GitHub Actions | Run on PR | Automated |

### Test Implementation Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| T1: Crypto unit tests | Test signing, derivation | 100+ tests | Critical path |
| T2: Validation unit tests | Address, amount validation | Edge cases | Input handling |
| T3: Service unit tests | API parsing, storage | Mocked | Business logic |
| T4: ViewModel tests | State management | Observable | UI logic |
| T5: Integration tests | Full flows | Real services | End-to-end |
| T6: UI tests | User journeys | Automated | Happy paths |
| T7: Error state tests | Error handling | All error types | Resilience |
| T8: Offline tests | Network disabled | Graceful degradation | Reachability |

### Edge Case Fixes

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| E1-E6: Onboarding | Handle all 6 cases | Graceful behavior | See list above |
| E7-E19: Send Flow | Handle all 13 cases | Graceful behavior | See list above |
| E20-E24: Swap | Handle all 5 cases | Graceful behavior | See list above |
| E25-E28: Approvals | Handle all 4 cases | Graceful behavior | See list above |
| E29-E36: Address | Handle all 8 cases | Graceful behavior | See list above |
| E37-E39: Swap/Bridge | Handle all 3 cases | Graceful behavior | See list above |
| E40-E42: WalletConnect | Handle all 3 cases | Graceful behavior | See list above |
| E43-E48: Security | Handle all 6 cases | Graceful behavior | See list above |
| E49-E52: Wallet State | Handle all 4 cases | Graceful behavior | See list above |
| E53-E55: Performance | Handle all 3 cases | Graceful behavior | See list above |
| E56-E60: NFT/Other | Handle all 5 cases | Graceful behavior | See list above |

---

## 6) Acceptance Criteria

- [ ] Unit test framework established
- [ ] Integration test target created
- [ ] UI test target created
- [ ] Code coverage tracked (target: 70%+)
- [ ] CI runs tests on every PR
- [ ] All 60 edge cases have handling code
- [ ] All 60 edge cases have test coverage
- [ ] Crypto operations have 100% test coverage
- [ ] Offline mode tested and working
- [ ] Error states tested and polished
- [ ] No crashes from edge case inputs

---

## 7) Analytics / Telemetry

| Event Name | Properties | Success/Failure |
|:---|:---|:---|
| `edge_case_triggered` | `case_id`, `context` | Triggered |
| `edge_case_handled` | `case_id`, `resolution` | Success |
| `edge_case_failed` | `case_id`, `error` | Failure |
| `error_displayed` | `error_type`, `context` | Error |
| `offline_mode_entered` | - | Info |
| `offline_mode_exited` | - | Info |

---

## 8) QA Checklist

**Test Infrastructure:**
- [ ] Unit tests run locally
- [ ] Unit tests run in CI
- [ ] Integration tests run
- [ ] UI tests run
- [ ] Coverage report generated
- [ ] Coverage > 70%

**Edge Case Spot Checks (sample):**
- [ ] Paste wrong network address → error shown
- [ ] Amount > balance → "Insufficient balance"
- [ ] Zero amount → rejected
- [ ] Slippage 0% → warning shown
- [ ] Force quit during seed → resume on relaunch
- [ ] Offline → cached data + banner
- [ ] 500 tokens → scrolls smoothly
- [ ] Biometric fail x3 → passcode fallback

**Error State Checks:**
- [ ] Network error → friendly message
- [ ] API timeout → retry option
- [ ] Invalid input → inline error
- [ ] Failed transaction → explanation

---

## 9) Effort & Dependencies

**Effort:** L (5-7 days)

**Dependencies:**
- Test infrastructure setup
- All feature roadmaps (for edge cases)

**Risks:**
- Edge case fixes may touch many areas
- Test maintenance burden

**Rollout Plan:**
1. Test infrastructure (Day 1)
2. Crypto unit tests (Day 2)
3. Validation + service tests (Day 3)
4. Edge case fixes batch 1 (Day 4)
5. Edge case fixes batch 2 (Day 5)
6. Integration + UI tests (Day 6)
7. QA + coverage review (Day 7)

---

## 10) Definition of Done

- [ ] Test infrastructure complete
- [ ] Unit test coverage > 70%
- [ ] All 60 edge cases handled
- [ ] All 60 edge cases tested
- [ ] CI running tests on PRs
- [ ] Offline mode tested
- [ ] Error states polished
- [ ] No known crashes
- [ ] Analytics for edge cases
- [ ] PR reviewed and merged
