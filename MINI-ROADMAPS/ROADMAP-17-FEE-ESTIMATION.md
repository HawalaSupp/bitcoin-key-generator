# ROADMAP-17 — Fee Estimation & Gas Management

**Theme:** Fee Management  
**Priority:** P1 (High)  
**Target Outcome:** Accurate fee estimation with clear UI, speed tiers, and custom gas options

---

## 1) What This Fixes (Mapped to MASTER REVIEW)

- **[High] Fee Estimate Stale / Not Refreshed** (Section 3.4)
- **[High] No Fee Speed Tiers (slow/medium/fast)** (Section 3.6)
- **[Medium] Custom Gas Price Not Supported** (Section 3.6)
- **[Medium] EIP-1559 Not Explained to Users** (Section 3.6)
- **[Low] Fee in USD Not Shown** (Section 3.6)
- **Phase 0 P0-11** — Refresh fee estimate before confirm
- **Phase 1 P1-15** — Fee tier picker (slow/standard/fast)
- **Blueprint 5.3** — Send Flow fee selection
- **Edge Case #16** — Fee estimate expires before confirmation
- **Edge Case #38** — Gas price spikes during confirmation
- **Edge Case #39** — User sets custom gas too low

---

## 2) User Impact

**Before:**
- Fees may be stale when confirming
- No choice of transaction speed
- Cannot customize gas price
- Fees shown only in crypto

**After:**
- Fresh fee estimates always
- Slow/Standard/Fast tiers
- Custom gas for power users
- Fees in both crypto and USD

---

## 3) Scope

**Included:**
- Fee estimation service
- Auto-refresh before confirmation
- Speed tier selector (slow/standard/fast)
- Custom gas input (advanced)
- USD conversion for fees
- EIP-1559 support with explanation
- Fee spike detection and warning

**Not Included:**
- CPFP (Child Pays for Parent)
- RBF (Replace-By-Fee) full UI
- Historical gas analytics

---

## 4) Step-by-Step Tasks

### Design Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| D1: Fee tier picker | 3 tabs or segmented control | Slow / Standard / Fast | With prices |
| D2: Custom gas input | "Advanced" expandable | Gwei input field | Power users |
| D3: Fee display | Crypto + USD | "$2.34 (0.001 ETH)" | Clear format |
| D4: EIP-1559 explainer | "What's this?" link | Educational tooltip | Optional viewing |
| D5: Fee spike warning | Orange banner | "Fees are high right now" | When > 2x normal |
| D6: Stale fee warning | "Refresh" prompt | "Fee may have changed" | > 30s old |
| D7: Low gas warning | Error state | "Transaction may fail" | Below minimum |

### Engineering Tasks (Swift)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| E1: Fee service | Fetch current fees | Slow/Standard/Fast | FeeEstimationService |
| E2: EIP-1559 support | Max fee + priority fee | Proper structure | GasEstimate model |
| E3: Legacy gas support | Gas price only | Fallback for old networks | Conditional |
| E4: Fee tier UI | Segmented control | 3 options + custom | FeeTierPicker |
| E5: Custom gas input | TextField for gwei | Validation | CustomGasView |
| E6: USD conversion | Fee × price | Real-time | Price service |
| E7: Auto-refresh | Refresh on confirm tap | Fresh estimate | Pre-confirmation |
| E8: Stale detection | Timestamp check | > 30s = stale | Fee model |
| E9: Refresh prompt | Show if stale | "Refresh for new fee" | Alert or inline |
| E10: Spike detection | Compare to history | > 2x = spike | Heuristic |
| E11: Spike warning | Banner display | "Fees are high" | Dismissible |
| E12: Low gas validation | Below network minimum | Block confirmation | Validation |
| E13: Low gas warning | Error message | "Transaction may fail" | Clear explanation |
| E14: Fee in confirmation | Show final fee | Crypto + USD | Before sign |

### Engineering Tasks (Rust)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| R1: Fee estimation API | Network-specific | Return tiers | Per-chain logic |
| R2: EIP-1559 gas calc | Base + priority | Proper estimation | Current block |

### QA Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| Q1: Fee tiers | View all 3 | Different prices | Accuracy |
| Q2: Custom gas | Enter custom value | Applied to tx | Advanced flow |
| Q3: USD display | View fee | USD shown | Conversion |
| Q4: Auto-refresh | Wait 30s, confirm | Fresh fee fetched | Timing |
| Q5: Spike warning | During high gas | Warning shown | Simulation |
| Q6: Low gas | Enter very low | Warning shown | Validation |

---

## 5) Acceptance Criteria

- [ ] Fee estimation service returns Slow/Standard/Fast
- [ ] Fee tier picker displays all 3 options
- [ ] Custom gas input available (advanced section)
- [ ] Fees displayed in crypto AND USD
- [ ] EIP-1559 supported on compatible networks
- [ ] "What's this?" explains EIP-1559 briefly
- [ ] Fee auto-refreshed before confirmation
- [ ] Stale fee (> 30s) shows refresh prompt
- [ ] Gas spike (> 2x normal) shows warning
- [ ] Custom gas below minimum shows error
- [ ] Transaction can proceed with warning acknowledged

---

## 6) Edge Cases & Failure States

| Scenario | Detection | UX Response |
|:---|:---|:---|
| Fee estimate fails | API error | Show cached or "Unable to estimate" |
| Fee > wallet balance | Balance check | "Insufficient funds for fee" |
| Gas spike | Historical comparison | "Network fees are unusually high" |
| Custom gas too low | Minimum check | "Gas price too low. Transaction may fail." |
| Custom gas too high | Sanity check | "This fee seems very high. Continue?" |
| Stale estimate | Timestamp > 30s | "Fee may have changed. Refresh?" |
| EIP-1559 not supported | Network check | Fall back to legacy gas |
| Price feed down | API error | Show crypto only, "USD unavailable" |

---

## 7) Analytics / Telemetry

| Event Name | Properties | Success/Failure |
|:---|:---|:---|
| `fee_tier_selected` | `tier` (slow/standard/fast/custom) | Success |
| `custom_gas_entered` | `gwei`, `valid` | Success/Failure |
| `fee_refreshed` | `age_before_ms`, `triggered_by` | Success |
| `fee_spike_warning` | `current_gwei`, `normal_gwei` | Warning |
| `low_gas_warning` | `entered_gwei`, `minimum_gwei` | Warning |
| `stale_fee_prompted` | `age_seconds` | Prompt |
| `stale_fee_refreshed` | - | Success |
| `eip1559_explainer_viewed` | - | Info |

---

## 8) QA Checklist

**Manual Tests:**
- [ ] Open send flow → fee tiers visible
- [ ] Select Slow → lower price shown
- [ ] Select Fast → higher price shown
- [ ] Fee shows ETH amount
- [ ] Fee shows USD amount
- [ ] Open Advanced → custom gas input
- [ ] Enter valid custom gas → applied
- [ ] Enter too low gas → warning shown
- [ ] Enter very high gas → confirmation required
- [ ] Wait 30s on confirm screen → refresh prompt
- [ ] Tap refresh → new fee fetched
- [ ] During high gas → spike warning visible
- [ ] "What's EIP-1559?" → explainer shown
- [ ] Fee > balance → insufficient funds error

**Automated Tests:**
- [ ] Unit test: Fee tier selection
- [ ] Unit test: Gas validation
- [ ] Unit test: Stale detection
- [ ] Integration test: Fee API
- [ ] UI test: Fee picker interaction

---

## 9) Effort & Dependencies

**Effort:** M (2-3 days)

**Dependencies:**
- Fee estimation API per network
- Price feed for USD conversion

**Risks:**
- Fee accuracy varies by network
- Spike detection heuristics need tuning

**Rollout Plan:**
1. Fee service + tier UI (Day 1)
2. Custom gas + USD conversion (Day 2)
3. Refresh + warnings + QA (Day 3)

---

## 10) Definition of Done

- [ ] Fee tiers functional
- [ ] Custom gas working
- [ ] USD conversion displayed
- [ ] EIP-1559 supported
- [ ] Auto-refresh before confirm
- [ ] Stale fee handling
- [ ] Spike warning
- [ ] Low gas validation
- [ ] Analytics events firing
- [ ] PR reviewed and merged
