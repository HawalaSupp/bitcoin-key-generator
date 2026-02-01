# ROADMAP-18 — Transaction History & Activity

**Theme:** Transaction History  
**Priority:** P1 (High)  
**Target Outcome:** Comprehensive transaction history with filtering, details, and status tracking

---

## 1) What This Fixes (Mapped to MASTER REVIEW)

- **[High] No Transaction Filtering** (Section 3.4)
- **[Medium] Transaction Status Not Clear** (Section 3.4)
- **[Medium] No Pending Transaction View** (Section 3.4)
- **[Medium] Failed Transactions Not Explained** (Section 3.4)
- **[Low] No Export to CSV** (Section 3.4)
- **Phase 1 P1-16** — Transaction filtering (type, token, date)
- **Blueprint 5.3** — Transaction History section
- **Edge Case #32** — Transaction stuck pending for hours
- **Edge Case #34** — User needs transaction for tax purposes
- **Microcopy Pack** — Transaction Status messages

---

## 2) User Impact

**Before:**
- Cannot filter transactions
- Unclear transaction status
- Pending transactions buried
- Failed transactions unexplained

**After:**
- Filter by type, token, date range
- Clear status indicators
- Pending transactions highlighted
- Failed transactions explained with retry

---

## 3) Scope

**Included:**
- Transaction list with filters
- Type filter (send/receive/swap/approve)
- Token filter
- Date range filter
- Pending transactions section
- Status indicators (pending/confirmed/failed)
- Failed transaction explanation
- Transaction detail view
- Export to CSV

**Not Included:**
- Push notifications for confirmations
- Transaction replacement (RBF)
- Speed up transaction UI

---

## 4) Step-by-Step Tasks

### Design Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| D1: Filter bar | Type, token, date filters | Pill buttons or dropdown | Always visible |
| D2: Transaction row | Type icon, amount, status | Color-coded status | Consistent layout |
| D3: Pending section | Grouped at top | "Pending (2)" header | Yellow indicator |
| D4: Status indicators | Pending/Confirmed/Failed | Icons + color | Clear distinction |
| D5: Failed explanation | Error message | "Why?" expandable | Actionable |
| D6: Transaction detail | Full info modal | All fields | Tappable row |
| D7: Export button | "Export CSV" | In toolbar | Standard format |

### Engineering Tasks (Swift)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| E1: Transaction model | Type, status, amounts, etc. | Codable | Transaction struct |
| E2: Transaction service | Fetch from indexer | Paginated | TransactionService |
| E3: Transaction list view | Display all transactions | Virtualized | TransactionListView |
| E4: Type filter | Filter by type | Real-time | Enum: send/receive/swap/approve |
| E5: Token filter | Filter by token | Real-time | Token picker |
| E6: Date filter | Date range picker | Real-time | DatePicker |
| E7: Pending grouping | Group pending at top | Separate section | Filter + sort |
| E8: Status display | Color-coded badge | Pending/Confirmed/Failed | StatusBadge view |
| E9: Status polling | Poll pending tx | Update on confirm | Background task |
| E10: Failed detail | Show error reason | Decode revert | On-chain data |
| E11: Retry failed | Retry button | Pre-fill send | Same params |
| E12: Transaction detail | Full modal | All fields visible | TransactionDetailView |
| E13: Copy tx hash | Copy button | Toast confirmation | Standard |
| E14: Block explorer | "View on Explorer" | Open URL | Per-network |
| E15: CSV export | Generate CSV | Download file | FileExporter |
| E16: CSV format | Standard columns | Date, type, amount, etc. | RFC 4180 |

### QA Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| Q1: Filter by type | Select "Send" | Only sends shown | Filter accuracy |
| Q2: Filter by token | Select ETH | Only ETH tx shown | Token match |
| Q3: Filter by date | Select last week | Correct range | Date logic |
| Q4: Pending section | Have pending tx | Grouped at top | UI check |
| Q5: Status update | Wait for confirm | Status updates | Polling |
| Q6: Failed detail | View failed tx | Reason shown | Explanation |
| Q7: Export CSV | Export history | Valid CSV file | Format check |

---

## 5) Acceptance Criteria

- [ ] Transaction history displays all transactions
- [ ] Filter by type (send/receive/swap/approve)
- [ ] Filter by token
- [ ] Filter by date range
- [ ] Filters can combine
- [ ] Pending transactions grouped at top
- [ ] Status badges clear (pending/confirmed/failed)
- [ ] Pending transactions poll for updates
- [ ] Failed transactions show explanation
- [ ] Failed transactions have retry option
- [ ] Transaction detail view accessible
- [ ] Copy transaction hash works
- [ ] "View on Explorer" opens browser
- [ ] Export to CSV functional
- [ ] CSV includes all relevant fields

---

## 6) Edge Cases & Failure States

| Scenario | Detection | UX Response |
|:---|:---|:---|
| No transactions | Empty result | "No transactions yet" empty state |
| Filter no results | Empty after filter | "No transactions match filters" |
| Pending > 1 hour | Time check | "Transaction taking longer than usual" |
| Pending > 24 hours | Time check | "Transaction may be stuck. Learn more." |
| Failed - out of gas | Error type | "Ran out of gas. Try with higher gas limit." |
| Failed - reverted | Error type | "Contract execution failed. [Details]" |
| Failed - nonce | Error type | "Transaction replaced." |
| Indexer timeout | API error | "Unable to load history. Retry?" |

---

## 7) Analytics / Telemetry

| Event Name | Properties | Success/Failure |
|:---|:---|:---|
| `history_viewed` | `transaction_count`, `pending_count` | Success |
| `history_filtered` | `filter_type`, `filter_value` | Success |
| `transaction_detail_viewed` | `tx_type`, `status` | Success |
| `tx_hash_copied` | - | Success |
| `explorer_opened` | `network` | Success |
| `failed_tx_retry_tapped` | `original_tx_hash` | Success |
| `history_exported` | `transaction_count`, `format` | Success |
| `pending_tx_stuck_warning` | `age_hours` | Warning |

---

## 8) QA Checklist

**Manual Tests:**
- [ ] Open history → all transactions shown
- [ ] Filter by Send → only sends visible
- [ ] Filter by Receive → only receives visible
- [ ] Filter by ETH → only ETH transactions
- [ ] Filter by date → correct range
- [ ] Combine filters → works correctly
- [ ] Clear filters → all shown again
- [ ] Pending tx → appears at top with yellow badge
- [ ] Wait for confirm → status updates automatically
- [ ] View failed tx → explanation shown
- [ ] Tap retry on failed → pre-filled send
- [ ] Tap transaction row → detail view opens
- [ ] Copy hash → toast confirmation
- [ ] View on Explorer → browser opens
- [ ] Export CSV → file downloads
- [ ] Open CSV → correct format

**Automated Tests:**
- [ ] Unit test: Transaction filtering
- [ ] Unit test: CSV generation
- [ ] Unit test: Status polling logic
- [ ] Integration test: Indexer API
- [ ] UI test: Filter interaction

---

## 9) Effort & Dependencies

**Effort:** M (3-4 days)

**Dependencies:**
- Transaction indexer API
- Block explorer URLs per network

**Risks:**
- Indexer delays affect pending status
- Failed transaction decoding varies

**Rollout Plan:**
1. Transaction list + display (Day 1)
2. Filters + pending section (Day 2)
3. Detail view + failed handling (Day 3)
4. CSV export + QA (Day 4)

---

## 10) Definition of Done

- [ ] Transaction history functional
- [ ] All filters working
- [ ] Pending section visible
- [ ] Status indicators clear
- [ ] Pending tx poll for updates
- [ ] Failed tx explained
- [ ] Retry option works
- [ ] Detail view complete
- [ ] CSV export works
- [ ] Analytics events firing
- [ ] PR reviewed and merged
