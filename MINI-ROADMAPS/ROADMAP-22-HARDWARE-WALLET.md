# ROADMAP-22 — Hardware Wallet Integration

**Theme:** Hardware Wallet Support  
**Priority:** P2 (Medium)  
**Target Outcome:** Full Ledger and Trezor integration for maximum security

---

## 1) What This Fixes (Mapped to MASTER REVIEW)

- **[Medium] No Hardware Wallet Support** (implied in architecture)
- **Phase 2 P2-10** — Hardware wallet integration
- **Blueprint 5.6** — Wallet type options
- **Edge Case** — Verify address on device (Receive flow)

---

## 2) User Impact

**Before:**
- Only software wallet (seed on device)
- Higher risk of key compromise

**After:**
- Hardware wallet support (Ledger, Trezor)
- Keys never leave hardware device
- Maximum security for high-value holdings

---

## 3) Scope

**Included:**
- Ledger Nano X/S support (USB + Bluetooth)
- Trezor Model T/One support (USB)
- Device pairing flow
- Transaction signing via hardware
- Address verification on device
- Multi-account derivation
- Connection status indicator

**Not Included:**
- Ledger Nano S Plus (future)
- Keystone/other hardware wallets
- NFC-based hardware wallets

---

## 4) Step-by-Step Tasks

### Design Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| D1: Pairing flow | Device detection + setup | Step-by-step | USB or Bluetooth |
| D2: Device selection | Choose Ledger or Trezor | Visual icons | Clear options |
| D3: Signing prompt | "Confirm on device" | Animation/illustration | Clear instruction |
| D4: Connection indicator | Status in sidebar | Connected/Disconnected | Real-time |
| D5: Verify on device | Button in Receive | "Verify on Ledger" | Safety feature |
| D6: Error states | Device errors | User-friendly | Troubleshooting |

### Engineering Tasks (Swift)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| E1: Ledger SDK | Integrate LedgerHQ SDK | Swift compatible | SPM or Cocoapods |
| E2: Trezor SDK | Integrate TrezorConnect | Swift/JS bridge | WebView or native |
| E3: Device manager | Abstract device interface | Protocol-based | HardwareWalletManager |
| E4: USB detection | Detect USB connection | IOKit | macOS API |
| E5: Bluetooth pairing | BLE connection | CoreBluetooth | Ledger Nano X |
| E6: Device pairing UI | Step-by-step flow | Guided experience | PairingView |
| E7: Account derivation | Get accounts from device | Multiple accounts | HD derivation |
| E8: Transaction signing | Request signature | Device confirmation | Async flow |
| E9: Signing UI | "Confirm on device" | Polling for result | SigningPromptView |
| E10: Address verification | Display on device | Compare addresses | Security feature |
| E11: Connection status | Track connection state | Real-time updates | ConnectionManager |
| E12: Status indicator | UI component | Sidebar badge | Visual feedback |
| E13: Error handling | Device errors | User-friendly | Retry options |
| E14: Disconnect handling | Device disconnected | Graceful recovery | State cleanup |

### QA Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| Q1: Ledger pairing | Pair Nano X | Successful connection | Bluetooth |
| Q2: Ledger signing | Sign transaction | Confirmed on device | End-to-end |
| Q3: Trezor pairing | Pair Trezor T | Successful connection | USB |
| Q4: Trezor signing | Sign transaction | Confirmed on device | End-to-end |
| Q5: Address verify | Verify on Ledger | Address displayed | Match check |
| Q6: Disconnect | Unplug device | Status updates | Recovery |
| Q7: Multiple accounts | Derive 3 accounts | All accessible | HD path |

---

## 5) Acceptance Criteria

- [ ] Ledger Nano X pairable via Bluetooth
- [ ] Ledger Nano S pairable via USB
- [ ] Trezor Model T pairable via USB
- [ ] Trezor One pairable via USB
- [ ] Pairing flow guides user step-by-step
- [ ] Multiple accounts derivable from device
- [ ] Transactions signed on device
- [ ] "Confirm on device" UI shown during signing
- [ ] Address verification works in Receive
- [ ] Connection status visible in sidebar
- [ ] Disconnect handled gracefully
- [ ] Device errors have user-friendly messages

---

## 6) Edge Cases & Failure States

| Scenario | Detection | UX Response |
|:---|:---|:---|
| Device not found | Timeout | "Make sure device is connected and unlocked" |
| Wrong app open | Error code | "Open the [Ethereum] app on your device" |
| User rejects on device | Rejection event | "Transaction cancelled on device" |
| Device disconnected during sign | Connection lost | "Device disconnected. Reconnect to retry." |
| Bluetooth pairing failed | BLE error | "Pairing failed. Try again." |
| Device firmware outdated | Version check | "Please update your device firmware" |
| Multiple devices connected | Device count | Let user choose |

---

## 7) Analytics / Telemetry

| Event Name | Properties | Success/Failure |
|:---|:---|:---|
| `hardware_wallet_pairing_started` | `device_type` | Started |
| `hardware_wallet_paired` | `device_type`, `connection_type` | Success |
| `hardware_wallet_pairing_failed` | `device_type`, `error` | Failure |
| `hardware_wallet_signing_requested` | `device_type`, `tx_type` | Started |
| `hardware_wallet_signing_confirmed` | `device_type` | Success |
| `hardware_wallet_signing_rejected` | `device_type` | User rejected |
| `hardware_wallet_disconnected` | `device_type`, `was_expected` | Info |
| `hardware_wallet_address_verified` | `device_type` | Success |

---

## 8) QA Checklist

**Manual Tests (require hardware):**
- [ ] Pair Ledger Nano X via Bluetooth
- [ ] Pair Ledger Nano S via USB
- [ ] Pair Trezor Model T via USB
- [ ] Get accounts from device
- [ ] Send ETH → confirm on Ledger
- [ ] Send ETH → confirm on Trezor
- [ ] Reject on device → "cancelled" message
- [ ] Unplug during sign → graceful error
- [ ] Wrong app open → helpful message
- [ ] Verify address on Ledger
- [ ] Verify address on Trezor
- [ ] Connection indicator updates in real-time

**Automated Tests:**
- [ ] Unit test: Device protocol abstraction
- [ ] Unit test: Error handling logic
- [ ] Mock test: Signing flow

---

## 9) Effort & Dependencies

**Effort:** L (5-7 days)

**Dependencies:**
- Ledger SDK (ledger-hw-transport-swift)
- Trezor SDK or WebView bridge
- Physical devices for testing

**Risks:**
- SDK compatibility with latest devices
- Bluetooth reliability on macOS
- USB permissions on macOS

**Rollout Plan:**
1. Ledger SDK integration (Day 1-2)
2. Trezor SDK integration (Day 3-4)
3. Pairing + signing flows (Day 5)
4. Error handling + status (Day 6)
5. QA with real devices (Day 7)

---

## 10) Definition of Done

- [ ] Ledger Nano X/S supported
- [ ] Trezor Model T/One supported
- [ ] Pairing flows complete
- [ ] Signing works on device
- [ ] Address verification works
- [ ] Connection status visible
- [ ] Errors handled gracefully
- [ ] All edge cases covered
- [ ] Analytics events firing
- [ ] PR reviewed and merged
