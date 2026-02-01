# ROADMAP-07 — Swap & Bridge Experience

**Theme:** Swap / Bridge  
**Priority:** P1 (High)  
**Target Outcome:** Transparent swap experience with accurate quotes, slippage control, and cross-chain safety

---

## 1) What This Fixes (Mapped to MASTER REVIEW)

- **[High] Swap Slippage Default Too High (1%)** (Section 3.5)
- **[High] No Rate Comparison Across DEXes** (Section 3.5)
- **[Medium] Bridge Destination Address Not Confirmed** (Section 3.5)
- **[Medium] No Price Impact Warning** (Section 3.5)
- **[Medium] "Swap" vs "Bridge" Distinction Unclear** (Section 3.5)
- **[Low] No Swap History Separate View** (Section 3.5)
- **Phase 1 P1-6** — Slippage Preset Picker
- **Phase 1 P1-13** — Route explainer for cross-chain
- **Blueprint 5.4** — Ideal Swap Experience
- **Edge Case #20** — Slippage set to 0% (tx will fail)
- **Edge Case #21** — Swap pair has no liquidity
- **Edge Case #22** — Token has transfer tax (affects output)
- **Edge Case #23** — Price impact > 10%
- **Edge Case #24** — Swap quote expires before confirmation
- **Edge Case #37** — User swaps token, receives less due to slippage
- **Conflict Decision** — Slippage Default (0.5% with smart warnings)
- **Microcopy Pack** — Swap Slippage Warning

---

## 2) User Impact

**Before:**
- Default 1% slippage costs users money
- No visibility into DEX rate comparison
- Bridge destination not verified
- High price impact not warned

**After:**
- Smart 0.5% default with presets
- Rate comparison across multiple DEXes
- Bridge destination must be confirmed
- Price impact warning for > 2% impact

---

## 3) Scope

**Included:**
- Slippage presets (0.1%, 0.5%, 1%, Custom)
- Multi-DEX rate comparison
- Price impact warning (> 2%)
- Bridge destination confirmation
- Swap vs Bridge visual distinction
- Quote expiry handling
- Swap history view

**Not Included:**
- Limit orders
- DCA (dollar cost averaging)
- Cross-chain message passing

---

## 4) Step-by-Step Tasks

### Design Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| D1: Slippage picker | 4 preset buttons + custom | 0.1% / 0.5% / 1% / Custom | Visual selection |
| D2: DEX comparison | List rates from 3+ DEXes | Best rate highlighted | "Via Uniswap" |
| D3: Price impact warning | Orange/red warning | > 2% orange, > 5% red | Show percentage |
| D4: Bridge confirmation | Destination address verify | Checkbox required | Clear distinction |
| D5: Swap vs Bridge tabs | Visual tabs | "Swap" / "Bridge" | Or toggle |
| D6: Quote expiry | Countdown + refresh | "Quote expires in 30s" | Auto-refresh option |
| D7: Swap history | Dedicated history view | Filter by swaps only | Date, amounts, rate |

### Engineering Tasks (Swift)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| E1: Slippage presets | UI for 4 presets | Bound to swap settings | UserDefaults persist |
| E2: Custom slippage | Input field for custom | Validate range (0.05-50%) | Numeric input |
| E3: Multi-DEX quotes | Parallel API calls | Return sorted by rate | Aggregator API |
| E4: DEX comparison UI | Display 3+ quotes | Tap to select route | Best highlighted |
| E5: Price impact calc | Calculate from quote | Display percentage | Formula: (spot - exec) / spot |
| E6: Price impact warning | Show warning > 2% | Orange badge/banner | Threshold configurable |
| E7: Bridge destination check | Require address confirm | Checkbox before proceed | Modal flow |
| E8: Swap/Bridge tabs | Tab UI | Toggle between modes | Segmented control |
| E9: Quote expiry timer | Countdown display | 30s default | Refresh action |
| E10: Auto-refresh quote | Refresh before expiry | Seamless update | Background fetch |
| E11: Transfer tax detection | Detect taxed tokens | Warn user | Token metadata |
| E12: Zero slippage warning | Warn if 0% set | "Transaction will likely fail" | Validation |
| E13: Swap history filter | Filter tx history | Swaps only | Transaction type |
| E14: Swap history view | Dedicated screen | From/to/rate/date | SwapHistoryView |

### API Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| A1: Multi-DEX aggregator | Call multiple DEX APIs | Return all quotes | Parallel requests |
| A2: Token tax metadata | Check for transfer tax | Return tax percentage | Token database |

### QA Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| Q1: Slippage presets | Select each preset | Correct value applied | UI check |
| Q2: Custom slippage | Enter 0.3% | Value accepted | Custom input |
| Q3: DEX comparison | View multiple quotes | All displayed correctly | Rate accuracy |
| Q4: Price impact | Swap large amount | Warning appears | > 2% impact |
| Q5: Bridge confirm | Initiate bridge | Must confirm destination | Checkbox required |
| Q6: Quote expiry | Wait 30s | Countdown + refresh | Timer accuracy |

---

## 5) Acceptance Criteria

- [ ] Slippage presets: 0.1%, 0.5%, 1%, Custom
- [ ] Default slippage is 0.5%
- [ ] Custom slippage allows 0.05% - 50% range
- [ ] 0% slippage shows "Transaction will likely fail" warning
- [ ] Multi-DEX quotes displayed (minimum 3 sources)
- [ ] Best rate highlighted
- [ ] Price impact shown for all swaps
- [ ] > 2% impact shows orange warning
- [ ] > 5% impact shows red warning
- [ ] Bridge destination requires confirmation checkbox
- [ ] Swap vs Bridge distinction clear (tabs or toggle)
- [ ] Quote expiry countdown visible (30s)
- [ ] Expired quote prompts refresh
- [ ] Transfer tax tokens show warning
- [ ] Swap history view accessible

---

## 6) Edge Cases & Failure States

| Scenario | Detection | UX Response |
|:---|:---|:---|
| 0% slippage set | Value check | "Transaction will likely fail" warning |
| No liquidity | Quote returns 0 | "No liquidity for this pair" |
| Transfer tax token | Metadata flag | "This token has a X% transfer tax" |
| Price impact > 10% | Calculation | Red warning + require acknowledgment |
| Quote expired | Timer expired | "Quote expired. Refresh for new rate." |
| DEX API timeout | Request timeout | Show available quotes; gray out failed |
| Bridge destination wrong network | Validation | "Address not valid for [network]" |
| Bridge destination is contract | Address type check | "Destination is a contract. Are you sure?" |

---

## 7) Analytics / Telemetry

| Event Name | Properties | Success/Failure |
|:---|:---|:---|
| `swap_started` | `from_token`, `to_token`, `amount_usd` | Success |
| `slippage_changed` | `from_value`, `to_value`, `preset_or_custom` | Success |
| `dex_comparison_viewed` | `dex_count`, `best_rate_dex` | Success |
| `dex_selected` | `dex_name`, `rate` | Success |
| `price_impact_warning_shown` | `impact_percentage`, `threshold` | Warning |
| `swap_confirmed` | `dex`, `slippage`, `price_impact` | Success |
| `swap_failed` | `error_type`, `dex` | Failure |
| `bridge_started` | `from_chain`, `to_chain`, `amount` | Success |
| `bridge_destination_confirmed` | `address_truncated` | Success |
| `quote_expired` | `age_seconds` | Expiry |
| `quote_refreshed` | `auto_or_manual` | Success |

---

## 8) QA Checklist

**Manual Tests:**
- [ ] Select 0.1% slippage → applied correctly
- [ ] Select 0.5% slippage → applied correctly
- [ ] Select 1% slippage → applied correctly
- [ ] Enter custom 0.3% → accepted
- [ ] Enter custom 0% → warning shown
- [ ] Enter custom 60% → rejected (out of range)
- [ ] Initiate swap → see 3+ DEX quotes
- [ ] Best rate highlighted
- [ ] Tap alternate DEX → route selected
- [ ] Large swap → price impact warning (> 2%)
- [ ] Very large swap → red warning (> 5%)
- [ ] Acknowledge high impact → proceed allowed
- [ ] Bridge flow → destination confirmation required
- [ ] Wait 30s → quote expires, refresh prompted
- [ ] Swap history → shows only swaps
- [ ] Transfer tax token → warning displayed

**Automated Tests:**
- [ ] Unit test: Slippage range validation
- [ ] Unit test: Price impact calculation
- [ ] Unit test: Quote expiry logic
- [ ] Integration test: Multi-DEX quote fetching
- [ ] UI test: Swap flow completion

---

## 9) Effort & Dependencies

**Effort:** M (3-4 days)

**Dependencies:**
- Multi-DEX aggregator API
- Token metadata service (for tax detection)

**Risks:**
- DEX API reliability varies
- Quote accuracy depends on freshness

**Rollout Plan:**
1. Slippage presets + validation (Day 1)
2. Multi-DEX comparison + price impact (Day 2)
3. Bridge confirmation + quote expiry (Day 3)
4. History view + QA (Day 4)

---

## 10) Definition of Done

- [ ] Slippage presets functional
- [ ] Default is 0.5%
- [ ] Multi-DEX comparison working
- [ ] Price impact warnings display
- [ ] Bridge destination confirmed
- [ ] Quote expiry handled
- [ ] Swap history view accessible
- [ ] Transfer tax tokens warned
- [ ] All edge cases handled
- [ ] Analytics events firing
- [ ] PR reviewed and merged
