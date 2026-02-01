# ROADMAP-06 — Receive Flow & Address Management

**Theme:** Receive / Address Management  
**Priority:** P1 (High)  
**Target Outcome:** Professional receive experience with QR, copy confirmation, and address verification

---

## 1) What This Fixes (Mapped to MASTER REVIEW)

- **[High] Receive QR Too Small on Large Screens** (Section 3.4)
- **[Medium] No Network Selector on Receive Screen** (Section 3.4)
- **[Medium] No "Copy" Toast Confirmation** (Section 3.4)
- **[Medium] No Address Verification Before Sharing** (Section 3.4)
- **[Low] No Share Sheet for Address** (Section 3.4)
- **Phase 1 P1-7** — Address Verification Ritual
- **Blueprint 5.3** — Ideal Receive Flow
- **Edge Case #19** — User screenshots QR; malware replaces
- **Edge Case #47** — User copies address but never pastes; clipboard lingers
- **Edge Case #59** — User requests receive address while wallet locked
- **Microcopy Pack** — Receive Address Copy

---

## 2) User Impact

**Before:**
- QR code too small for easy scanning
- Unclear which network's address is shown
- No confirmation when address is copied
- No way to verify address matches hardware wallet

**After:**
- Large, scannable QR code
- Clear network selector
- Toast confirms "Address copied"
- Address verification flow for high-security users

---

## 3) Scope

**Included:**
- Responsive QR code sizing
- Network selector on receive screen
- Copy toast confirmation
- Address verification flow (show on device)
- Native Share sheet for address
- Clipboard auto-clear option

**Not Included:**
- Payment request generation
- Invoice creation
- ENS/unstoppable domain display

---

## 4) Step-by-Step Tasks

### Design Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| D1: Large QR code | Responsive sizing for screen | Min 250pt, max 60% width | Centered |
| D2: Network selector | Dropdown/segmented control | Above QR code | Clear network name |
| D3: Copy toast | Bottom toast animation | "Address copied ✓" | 2s duration |
| D4: Verify address flow | Explain + trigger verification | For hardware wallet users | Optional flow |
| D5: Share sheet | Native macOS/iOS share | Address text shared | Standard icon |
| D6: Clipboard warning | "Clear clipboard?" prompt | After X minutes | Optional setting |

### Engineering Tasks (Swift)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| E1: Responsive QR | Size QR based on view width | Min 250pt, max 60% | GeometryReader |
| E2: Network selector | Dropdown for multi-network assets | Updates address + QR | Binding to selected |
| E3: Copy toast | Show toast on copy | Animated appearance | Custom ToastView |
| E4: Verify address | Show address on hardware wallet | Requires wallet connection | HardwareWalletService |
| E5: Share sheet | Native share extension | Text sharing | UIActivityViewController |
| E6: Clipboard timer | Optional auto-clear | After 5 min default | Background timer |
| E7: Clipboard clear prompt | Ask before clearing | User preference | Alert dialog |
| E8: Wallet locked check | Handle receive while locked | Require unlock first | Auth check |

### QA Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| Q1: QR size | Test on various screen sizes | Always scannable | Visual check |
| Q2: Network switch | Switch networks, verify address | Correct address shown | Multi-network |
| Q3: Copy toast | Copy address, verify toast | Toast appears | UX check |
| Q4: Share sheet | Share address | Native sheet works | Platform test |
| Q5: Clipboard clear | Wait 5 min, check prompt | Prompt appears | Timer test |

---

## 5) Acceptance Criteria

- [ ] QR code minimum 250pt, maximum 60% of view width
- [ ] Network selector visible for multi-network assets
- [ ] Selecting network updates address and QR
- [ ] "Address copied" toast appears on copy
- [ ] Toast auto-dismisses after 2 seconds
- [ ] "Verify on device" option for hardware wallets
- [ ] Native Share sheet accessible
- [ ] Optional clipboard auto-clear after 5 minutes
- [ ] Receive screen requires unlock if wallet locked

---

## 6) Edge Cases & Failure States

| Scenario | Detection | UX Response |
|:---|:---|:---|
| Very small screen | Geometry check | Show minimum 200pt QR |
| Single-network asset | Network count check | Hide network selector |
| Hardware wallet disconnected | Connection check | "Connect wallet to verify" |
| Wallet locked | Auth state | Prompt for unlock |
| Clipboard lingers | Timer | Prompt to clear |
| Screenshot taken | Screenshot notification | Warning about malware |

---

## 7) Analytics / Telemetry

| Event Name | Properties | Success/Failure |
|:---|:---|:---|
| `receive_opened` | `network`, `asset` | Success |
| `receive_network_changed` | `from_network`, `to_network` | Success |
| `receive_address_copied` | `network`, `asset` | Success |
| `receive_address_shared` | `method` (airdrop/messages/etc) | Success |
| `receive_address_verified` | `hardware_wallet_type` | Success |
| `clipboard_auto_cleared` | `after_minutes` | Success |
| `clipboard_clear_dismissed` | - | User choice |

---

## 8) QA Checklist

**Manual Tests:**
- [ ] QR code large on iPad/external display
- [ ] QR code appropriate on small iPhone
- [ ] Network selector appears for ETH (multi-network)
- [ ] Network selector hidden for BTC (single network)
- [ ] Switch from Mainnet to Polygon → address updates
- [ ] Tap copy → toast appears
- [ ] Toast disappears after ~2 seconds
- [ ] Tap share → native share sheet opens
- [ ] Share address via Messages/AirDrop
- [ ] Verify on device works with Ledger (if applicable)
- [ ] Enable clipboard clear, wait 5 min → prompt appears
- [ ] Open receive while locked → prompted to unlock

**Automated Tests:**
- [ ] Unit test: QR generation for various addresses
- [ ] Unit test: Network selector logic
- [ ] UI test: Copy toast appearance
- [ ] UI test: Share sheet presentation

---

## 9) Effort & Dependencies

**Effort:** S (1-2 days)

**Dependencies:**
- Hardware wallet integration (for verify flow)
- Toast component (reusable)

**Risks:**
- Hardware wallet verification varies by device

**Rollout Plan:**
1. Responsive QR + network selector (Day 1)
2. Toast + Share + clipboard clear (Day 2)

---

## 10) Definition of Done

- [ ] QR code responsive
- [ ] Network selector functional
- [ ] Copy toast working
- [ ] Share sheet accessible
- [ ] Clipboard clear option available
- [ ] Wallet lock check working
- [ ] Analytics events firing
- [ ] PR reviewed and merged
