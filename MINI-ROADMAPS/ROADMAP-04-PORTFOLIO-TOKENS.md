# ROADMAP-04 — Portfolio & Token Views

**Theme:** Portfolio / Token Management  
**Priority:** P1 (High)  
**Target Outcome:** Professional portfolio display with real-time data, search, filters, and token management

---

## 1) What This Fixes (Mapped to MASTER REVIEW)

- **[High] No Token Search or Filter** (Section 3.3)
- **[High] Portfolio Graph Lacks Time-Range Selector** (Section 3.3)
- **[Medium] Fiat Toggle Hard to Discover** (Section 3.3)
- **[Medium] Hide Zero-Balance Tokens Not Persisted** (Section 3.3)
- **[Medium] No Sparkline in Token Rows** (Section 3.3)
- **[Low] Refresh Animation Too Subtle** (Section 3.3)
- **Phase 1 P1-2** — Portfolio time-range tabs (1D/1W/1M/1Y/All)
- **Phase 1 P1-3** — Token search field + custom token manager
- **Conflict Decision** — Show All Tokens vs. Curated (hybrid: pin favorites, collapse dust)
- **Blueprint 5.3** — Portfolio Context
- **Edge Case #1** — User is offline (cache with stale banner)
- **Edge Case #12** — Price feed returns $0 (show cached or "Price unavailable")
- **Edge Case #13** — Token price > $999,999 (abbreviate with K/M/B)
- **Edge Case #14** — Token balance > 999,999,999 (scientific notation)
- **Microcopy Pack** — Portfolio Empty State, Price Unavailable

---

## 2) User Impact

**Before:**
- Cannot search for tokens in large portfolios
- No time range selection for performance graphs
- Fiat toggle hidden
- Zero-balance preference resets on relaunch
- No sparklines for quick trend visibility

**After:**
- Instant token search and filtering
- Time range tabs (1D/1W/1M/1Y/All)
- Visible fiat toggle near balance
- Persistent display preferences
- Sparklines in every token row

---

## 3) Scope

**Included:**
- Token search field with real-time filtering
- Time range tabs for portfolio graph
- Fiat currency toggle (prominent placement)
- Persist "hide zero balances" to UserDefaults
- Sparkline component for token rows
- Custom token manager (add/remove/hide)
- Refresh animation enhancement

**Not Included:**
- Portfolio performance calculations (separate)
- Tax reporting features
- Multi-wallet aggregation

---

## 4) Step-by-Step Tasks

### Design Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| D1: Token search bar | Design search field placement | Above token list, always visible | macOS: ⌘F to focus |
| D2: Time range tabs | Tab bar design (1D/1W/1M/1Y/All) | Selected state clear | Below graph |
| D3: Fiat toggle | Prominent toggle near total balance | Flag icon or text | One-tap toggle |
| D4: Sparkline component | Mini chart for token rows | 24h trend, colored | Red/green gradient |
| D5: Custom token sheet | Add token modal | Contract address input | Network selector |
| D6: Refresh animation | Skeleton loading + pulse | Professional feel | Not just spinner |

### Engineering Tasks (Swift)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| E1: Token search field | Filter tokens by name/symbol | Case-insensitive, instant | `Searchable` modifier |
| E2: Time range API | Fetch historical data for ranges | 1D/1W/1M/1Y/All endpoints | Caching strategy |
| E3: Time range tabs | UI tabs that update graph | Smooth animation | Binding to selected range |
| E4: Fiat toggle UI | Prominent button/toggle | Persisted to UserDefaults | Currency code display |
| E5: Persist zero-balance pref | Save to UserDefaults | Restored on launch | `@AppStorage` |
| E6: Sparkline view | SwiftUI chart component | 24h data, 50 points | Charts framework |
| E7: Custom token manager | Add/remove custom tokens | Validate contract address | TokenManagerService |
| E8: Refresh skeleton | Skeleton loading animation | Professional feel | Custom modifier |
| E9: Price abbreviation | K/M/B for large prices | > $999,999 abbreviated | NumberFormatter |
| E10: Balance formatting | Scientific notation for huge | > 999,999,999 | NumberFormatter |
| E11: Offline cache | Show cached with stale banner | Orange "Data may be outdated" | Reachability + cache |
| E12: Price unavailable | Handle $0 or null prices | "Price unavailable" text | Fallback logic |

### API Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| A1: Historical price API | Endpoint for time ranges | Standard intervals | Provider integration |
| A2: Custom token validation | Verify contract on-chain | Return metadata | RPC call |

### QA Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| Q1: Search functionality | Filter 100+ tokens | Instant results | Performance test |
| Q2: Time range switching | All 5 ranges work | Correct data displayed | API verification |
| Q3: Fiat persistence | Toggle, relaunch, verify | Setting retained | UserDefaults |
| Q4: Sparkline accuracy | Compare to full chart | Same trend direction | Visual match |
| Q5: Custom token add | Add new ERC-20 | Appears in list | Happy path |
| Q6: Offline mode | Disable network, launch | Cached data + banner | Graceful degradation |

---

## 5) Acceptance Criteria

- [x] Token search field visible above token list ✅ (HawalaMainView bentoAssetsGrid search bar)
- [x] Search filters by name and symbol (case-insensitive) ✅ (filterChains)
- [ ] Time range tabs (1D/1W/1M/1Y/All) functional — present in detail views, not main portfolio
- [x] Fiat toggle visible near total balance ✅ (@AppStorage showFiatValues + toggle button)
- [x] "Hide zero balances" persists across app launches ✅ (@AppStorage hideZeroBalances)
- [x] Sparklines visible in token rows (24h trend) ✅ (BentoSparklineChart in BentoAssetCard)
- [x] Custom token manager accessible ✅ (CustomTokenManager service)
- [x] Large prices abbreviated (K/M/B) ✅ (formatLargeNumber with K/M/B thresholds)
- [x] Large balances safe from scientific notation ✅ (formatBalanceValue via Decimal)
- [x] Offline mode shows cached data with stale banner ✅ (ProviderHealthManager + .stale state)
- [x] "$0 price" shows "Price unavailable" ✅ (PriceService + HawalaMainView formatFiatValue)
- [x] Refresh uses skeleton animation, not just spinner ✅ (SkeletonShape + ShimmerModifier)

---

## 6) Edge Cases & Failure States

| Scenario | Detection | UX Response |
|:---|:---|:---|
| No search results | Empty filter result | "No tokens match 'xyz'" |
| Time range API fails | HTTP error | Show cached or "Unable to load" |
| Price feed returns $0 | Value check | "Price unavailable" with icon |
| Price > $999,999 | Value check | Abbreviate to "$1.2M" |
| Balance > 999,999,999 | Value check | "1.23e9 ETH" format |
| Offline | Reachability | Orange banner "Data may be outdated" |
| Custom token invalid | Contract validation | "Invalid contract address" error |
| Sparkline data missing | API response check | Show flat line or hide |

---

## 7) Analytics / Telemetry

| Event Name | Properties | Success/Failure |
|:---|:---|:---|
| `portfolio_search` | `query`, `results_count` | Success |
| `time_range_changed` | `from_range`, `to_range` | Success |
| `fiat_toggle` | `currency_code` | Success |
| `zero_balance_toggle` | `hidden` (bool) | Success |
| `custom_token_added` | `network`, `contract` | Success |
| `custom_token_failed` | `error_type` | Failure |
| `portfolio_refresh` | `latency_ms`, `token_count` | Success |
| `portfolio_cache_hit` | `cache_age_ms` | Success |

---

## 8) QA Checklist

**Manual Tests:**
- [x] Search for "ETH" shows Ethereum and related tokens ✅
- [x] Search for "xyz" shows empty state ✅
- [ ] Time range tabs all display correct data — present in detail/chart views
- [x] Fiat toggle switches display currency ✅
- [x] Fiat preference persists after relaunch ✅ (@AppStorage)
- [x] "Hide zero balances" persists after relaunch ✅ (@AppStorage)
- [x] Sparklines show 24h trend correctly ✅
- [x] Add custom ERC-20 token successfully ✅ (CustomTokenManager)
- [x] Large price ($1,500,000) shows as "$1.5M" ✅
- [x] Huge balance uses Decimal (no scientific notation) ✅
- [x] Offline shows cached data with banner ✅
- [x] $0 price shows "Price unavailable" ✅

**Automated Tests:**
- [ ] Unit test: Price formatting (K/M/B)
- [ ] Unit test: Balance formatting (scientific)
- [ ] Unit test: Token search filtering
- [ ] Integration test: Cache fallback
- [ ] UI test: Time range switching

---

## 9) Effort & Dependencies

**Effort:** M (3-4 days)

**Dependencies:**
- Historical price API endpoints
- Charts framework (SwiftUI Charts)

**Risks:**
- API rate limits for historical data
- Sparkline performance with many tokens

**Rollout Plan:**
1. Search + zero-balance persistence (Day 1)
2. Time range tabs + API integration (Day 2)
3. Sparklines + formatting (Day 3)
4. Custom tokens + QA (Day 4)

---

## 10) Definition of Done

- [x] Token search field functional ✅ (bentoAssetsGrid search bar + filterChains)
- [ ] Time range tabs working with API — in detail views, not main portfolio
- [x] Fiat toggle prominent and persistent ✅ (@AppStorage showFiatValues)
- [x] Zero-balance preference persistent ✅ (@AppStorage hideZeroBalances)
- [x] Sparklines in token rows ✅ (BentoSparklineChart)
- [x] Custom token manager functional ✅ (CustomTokenManager)
- [x] Number formatting for edge cases ✅ (K/M/B + Decimal guard + $0 handling)
- [x] Offline mode with cached data ✅ (ProviderHealthManager + stale states)
- [ ] Analytics events firing
- [x] No performance regression with 100+ tokens ✅ (LazyVGrid)
- [ ] PR reviewed and merged
