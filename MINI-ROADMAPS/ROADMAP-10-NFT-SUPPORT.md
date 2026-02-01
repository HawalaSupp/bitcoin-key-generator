# ROADMAP-10 — NFT Support & Display

**Theme:** NFT Management  
**Priority:** P2 (Medium)  
**Target Outcome:** Full NFT support with gallery view, metadata display, send capability, and hidden/spam filtering

---

## 1) What This Fixes (Mapped to MASTER REVIEW)

- **[Medium] No NFT Gallery View** (Section 3.9)
- **[Medium] No NFT Metadata Display** (Section 3.9)
- **[Medium] Cannot Send NFTs from Wallet** (Section 3.9)
- **[Low] No Hidden / Spam NFT Tab** (Section 3.9)
- **[Low] No Floor Price Display** (Section 3.9)
- **Phase 2 P2-5** — NFT gallery with metadata
- **Phase 2 P2-6** — NFT send flow
- **Blueprint** — Not explicitly covered (new feature area)
- **Edge Case #56** — User receives spam NFT
- **Edge Case #57** — NFT metadata fails to load
- **Microcopy Pack** — NFT Loading, Hidden

---

## 2) User Impact

**Before:**
- No visibility into owned NFTs
- Cannot view NFT details or attributes
- Cannot send NFTs from wallet
- No way to hide spam NFTs

**After:**
- Beautiful NFT gallery view
- Full metadata and attributes display
- Send NFTs to any address
- Hide/unhide and spam filtering

---

## 3) Scope

**Included:**
- NFT gallery grid view
- NFT detail view with metadata
- NFT send flow
- Hide/unhide NFT feature
- Spam NFT tab
- Floor price display (where available)
- Multi-chain NFT support

**Not Included:**
- NFT minting
- NFT marketplace integration
- NFT trading/selling
- ENS avatar display

---

## 4) Step-by-Step Tasks

### Design Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| D1: NFT gallery grid | 2-3 column grid | Thumbnail + name | Tab in portfolio |
| D2: NFT detail modal | Full image + metadata | Scrollable | Traits, collection |
| D3: NFT send flow | Select NFT → address → confirm | Similar to token send | No amount needed |
| D4: Hide action | Context menu or swipe | "Hide NFT" | Confirmation optional |
| D5: Hidden tab | Separate tab for hidden | "Hidden (5)" | Unhide option |
| D6: Spam indicator | Badge on spam NFTs | Auto-detected | Red badge |
| D7: Floor price | Price near image | "$1,234" or "—" | OpenSea data |
| D8: Loading skeleton | Placeholder while loading | Blur/shimmer | Good UX |

### Engineering Tasks (Swift)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| E1: NFT data service | Fetch NFTs from indexer | Multi-chain support | Alchemy/Moralis API |
| E2: NFT gallery view | Grid layout | LazyVGrid | Performance optimized |
| E3: Thumbnail loading | Async image loading | Placeholder → image | AsyncImage + cache |
| E4: NFT detail view | Full screen modal | All metadata displayed | NFTDetailView |
| E5: Metadata parsing | Parse traits/attributes | Structured display | JSON parsing |
| E6: NFT send view | Address input → confirm | Transfer ERC-721/1155 | NFTSendView |
| E7: Send transaction | Build transfer tx | Sign + broadcast | Rust FFI |
| E8: Hide NFT | Store hidden list | Persisted | UserDefaults |
| E9: Hidden tab | Filter hidden from main | Separate view | Toggle visibility |
| E10: Spam detection | Check against known spam | Auto-hide | Spam list API |
| E11: Floor price fetch | OpenSea API | Display price | Cached |
| E12: Multi-chain tabs | Filter by chain | Tabs or dropdown | ETH, Polygon, etc. |
| E13: Metadata fallback | Handle missing metadata | "Metadata unavailable" | Graceful degradation |

### API Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| A1: NFT indexer | Alchemy/Moralis/OpenSea | NFT list + metadata | Multi-chain |
| A2: Floor price API | OpenSea/LooksRare | Collection floor | Cached |
| A3: Spam NFT list | Known spam collections | Block/hide | Updated regularly |

### QA Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| Q1: Gallery display | View 50+ NFTs | Grid loads smoothly | Performance |
| Q2: Detail view | Tap NFT | All metadata shown | Traits correct |
| Q3: Send NFT | Send to address | Transfer succeeds | On-chain verify |
| Q4: Hide NFT | Hide, check hidden tab | Appears in hidden | Persisted |
| Q5: Unhide NFT | Unhide | Returns to gallery | Toggle works |
| Q6: Spam auto-hide | Receive known spam | Goes to spam/hidden | Automatic |
| Q7: Floor price | View collection NFT | Price shown | Accuracy check |

---

## 5) Acceptance Criteria

- [ ] NFT gallery accessible from portfolio
- [ ] Grid displays all owned NFTs
- [ ] Tapping NFT opens detail view
- [ ] Detail view shows image, name, collection
- [ ] Detail view shows traits/attributes
- [ ] Send button on detail view
- [ ] Send flow similar to token send
- [ ] NFT transfer succeeds on-chain
- [ ] Hide option available (context menu)
- [ ] Hidden tab shows hidden NFTs
- [ ] Unhide option works
- [ ] Spam NFTs auto-detected and filtered
- [ ] Floor price displayed when available
- [ ] Multi-chain NFTs supported (ETH, Polygon, etc.)
- [ ] Metadata unavailable handled gracefully

---

## 6) Edge Cases & Failure States

| Scenario | Detection | UX Response |
|:---|:---|:---|
| Metadata fails to load | API error | "Metadata unavailable" placeholder |
| Image fails to load | Load error | Placeholder image with retry |
| No NFTs owned | Empty response | "No NFTs yet" empty state |
| Spam NFT received | Spam list check | Auto-hide + badge |
| Floor price unavailable | API null | Show "—" |
| Large collection (1000+) | Count check | Paginate / lazy load |
| Send to wrong network | Address validation | "Address not valid for this NFT's network" |
| Gas too high for send | Fee estimation | Show fee warning |

---

## 7) Analytics / Telemetry

| Event Name | Properties | Success/Failure |
|:---|:---|:---|
| `nft_gallery_opened` | `nft_count` | Success |
| `nft_detail_viewed` | `collection`, `token_id` | Success |
| `nft_send_started` | `collection`, `token_id` | Success |
| `nft_send_confirmed` | `tx_hash` | Success |
| `nft_send_failed` | `error_type` | Failure |
| `nft_hidden` | `collection`, `token_id` | Success |
| `nft_unhidden` | `collection`, `token_id` | Success |
| `nft_spam_detected` | `collection`, `token_id` | Auto |
| `nft_metadata_failed` | `token_id`, `error` | Failure |

---

## 8) QA Checklist

**Manual Tests:**
- [ ] Open NFT gallery → NFTs displayed
- [ ] Scroll gallery with 50+ NFTs → smooth
- [ ] Tap NFT → detail view opens
- [ ] Detail shows correct image
- [ ] Detail shows collection name
- [ ] Detail shows traits (if any)
- [ ] Tap send on detail → send flow starts
- [ ] Enter address → confirm → NFT sent
- [ ] Hide NFT → moves to hidden tab
- [ ] View hidden tab → hidden NFT shown
- [ ] Unhide NFT → returns to gallery
- [ ] Spam NFT → auto-filtered
- [ ] Floor price displayed (if available)
- [ ] Floor price shows "—" if unavailable
- [ ] Metadata fails → placeholder shown

**Automated Tests:**
- [ ] Unit test: NFT data parsing
- [ ] Unit test: Spam detection logic
- [ ] Unit test: Hidden list management
- [ ] Integration test: NFT indexer API
- [ ] UI test: Gallery navigation

---

## 9) Effort & Dependencies

**Effort:** M (3-4 days)

**Dependencies:**
- NFT indexer API (Alchemy/Moralis)
- Floor price API (OpenSea)
- Spam NFT list

**Risks:**
- NFT metadata is often broken/missing
- API rate limits for large collections

**Rollout Plan:**
1. Gallery view + detail (Day 1-2)
2. Send flow (Day 2)
3. Hide/unhide + spam (Day 3)
4. Floor price + QA (Day 4)

---

## 10) Definition of Done

- [ ] NFT gallery displays all NFTs
- [ ] Detail view shows metadata
- [ ] Send flow works
- [ ] Hide/unhide functional
- [ ] Spam filtering active
- [ ] Floor price displayed
- [ ] Multi-chain supported
- [ ] Edge cases handled
- [ ] Analytics events firing
- [ ] PR reviewed and merged
