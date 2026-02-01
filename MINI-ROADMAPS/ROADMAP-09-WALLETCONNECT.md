# ROADMAP-09 — WalletConnect & dApp Integration

**Theme:** WalletConnect / dApp Connections  
**Priority:** P1 (High)  
**Target Outcome:** Secure, transparent dApp connections with session management and request explanation

---

## 1) What This Fixes (Mapped to MASTER REVIEW)

- **[High] WalletConnect V1 Still in Use** (Section 3.8)
- **[High] No Session Manager to Disconnect dApps** (Section 3.8)
- **[High] Signature Requests Not Human-Readable** (Section 3.8)
- **[Medium] No Allowlist / Blocklist for dApps** (Section 3.8)
- **[Medium] Connection Requests Lack Context** (Section 3.8)
- **[Low] No "What is this dApp?" Link** (Section 3.8)
- **Phase 1 P1-4** — Decode all WalletConnect signing requests
- **Phase 1 P1-12** — WalletConnect session manager
- **Blueprint 5.4** — dApp Connection Context
- **Edge Case #28** — Malicious WalletConnect from phishing site
- **Edge Case #40** — User approves sign request without reading
- **Edge Case #41** — User connected to dApp for days (session stale)
- **Edge Case #42** — dApp sends rapid-fire requests
- **Edge Case #45** — Malicious site impersonates Uniswap
- **Microcopy Pack** — WalletConnect Signing Explanation

---

## 2) User Impact

**Before:**
- WalletConnect V1 deprecated and insecure
- No way to view or disconnect active sessions
- Signing requests are opaque hex strings
- No protection against malicious dApps

**After:**
- WalletConnect V2 only (secure)
- Full session manager with disconnect
- Human-readable signing request explanations
- Allowlist/blocklist for trusted dApps

---

## 3) Scope

**Included:**
- Migrate to WalletConnect V2 only
- Session manager (view + disconnect)
- Human-readable signing request decoder
- Allowlist/blocklist management
- dApp verification display
- Request rate limiting
- Connection context display

**Not Included:**
- Deep WalletConnect Auth integration
- Multi-session per dApp
- Push notification for requests

---

## 4) Step-by-Step Tasks

### Design Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| D1: Session manager screen | List active connections | Disconnect button per dApp | Settings > Connections |
| D2: Session card | dApp name, icon, connected chains | Last activity time | Visual card |
| D3: Signing request modal | Human-readable explanation | Clear action description | "You are approving..." |
| D4: Request decoder | Translate method calls | Plain English | Function name + params |
| D5: Allowlist/blocklist | Manage trusted/blocked dApps | Add/remove UI | Two lists |
| D6: Connection modal | Enhanced connection request | dApp info + permissions | More context |
| D7: Rate limit warning | Too many requests banner | "This dApp is sending many requests" | Yellow warning |

### Engineering Tasks (Swift)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| E1: Migrate to WC V2 | Remove V1, update SDK | V2 only | WalletConnectSwift |
| E2: Session manager view | Display all sessions | From WC SDK | SessionManagerView |
| E3: Disconnect session | Terminate WC session | Remove from SDK | SDK method |
| E4: Signing decoder | Decode method signatures | ABI lookup | 4byte.directory |
| E5: Human-readable format | Format decoded data | Plain English | Template system |
| E6: EIP-712 decoder | Decode typed data | Structured display | Domain + message |
| E7: Allowlist storage | Persist trusted dApps | UserDefaults/Keychain | By domain |
| E8: Blocklist storage | Persist blocked dApps | UserDefaults/Keychain | By domain |
| E9: Auto-block check | Check against blocklist | Block request | Before modal |
| E10: Auto-allow check | Check against allowlist | Skip confirmation (optional) | User preference |
| E11: Rate limiter | Track request frequency | Warn/block if excessive | 10 req/min limit |
| E12: Enhanced connection | Show dApp info | Logo, name, description | Metadata from WC |
| E13: dApp verification | Check known dApps | Verified badge | Registry lookup |
| E14: Session cleanup | Remove stale sessions | Auto-disconnect > 7 days | Background task |

### QA Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| Q1: WC V2 connection | Connect to dApp | V2 handshake | No V1 fallback |
| Q2: Session display | View in manager | Correct info | All sessions |
| Q3: Disconnect | Disconnect session | Session removed | Both sides |
| Q4: Signing decode | Request signature | Human-readable | Complex request |
| Q5: EIP-712 | Typed data request | Structured display | NFT sale example |
| Q6: Allowlist | Add dApp, connect | Faster flow | Trusted |
| Q7: Blocklist | Block dApp, try connect | Blocked | No modal |
| Q8: Rate limit | Rapid requests | Warning shown | 10+ requests |

---

## 5) Acceptance Criteria

- [ ] WalletConnect V2 only (V1 removed)
- [ ] Session manager accessible from Settings
- [ ] All active sessions displayed with dApp info
- [ ] Disconnect button works for each session
- [ ] Signing requests decoded to human-readable format
- [ ] EIP-712 typed data structured and explained
- [ ] Allowlist for trusted dApps functional
- [ ] Blocklist for untrusted dApps functional
- [ ] Connection requests show enhanced context
- [ ] dApp verification badge displayed when known
- [ ] Rate limiting warns on excessive requests
- [ ] Stale sessions auto-cleaned after 7 days

---

## 6) Edge Cases & Failure States

| Scenario | Detection | UX Response |
|:---|:---|:---|
| V1 connection attempt | Protocol version | "This dApp uses outdated protocol" |
| Unknown method signature | ABI lookup miss | Show raw with "Advanced" toggle |
| Phishing dApp | Domain check | Red warning modal |
| Impersonation | Known dApp mismatch | "This is NOT [Uniswap]" |
| Rate limiting triggered | Request counter | "This dApp is sending too many requests" |
| Session stale > 7 days | Last activity | Auto-disconnect + notification |
| User approves blindly | Quick tap detection | Delay confirm button by 3s for complex |
| Blocklisted dApp | List check | Silent block, no modal |

---

## 7) Analytics / Telemetry

| Event Name | Properties | Success/Failure |
|:---|:---|:---|
| `wc_connection_requested` | `dapp_name`, `chains` | Success |
| `wc_connection_approved` | `dapp_name`, `session_id` | Success |
| `wc_connection_rejected` | `dapp_name`, `reason` | User choice |
| `wc_session_disconnected` | `dapp_name`, `method` (manual/auto) | Success |
| `wc_signing_requested` | `method`, `decoded` (bool) | Success |
| `wc_signing_approved` | `method`, `read_time_ms` | Success |
| `wc_signing_rejected` | `method`, `reason` | User choice |
| `wc_allowlist_added` | `domain` | Success |
| `wc_blocklist_added` | `domain` | Success |
| `wc_rate_limit_triggered` | `dapp_name`, `request_count` | Warning |
| `wc_phishing_detected` | `domain` | Block |

---

## 8) QA Checklist

**Manual Tests:**
- [ ] Connect to Uniswap via WC V2 → succeeds
- [ ] Attempt WC V1 → rejected with message
- [ ] View session manager → shows connection
- [ ] Session shows correct dApp name/icon
- [ ] Disconnect session → removed from list
- [ ] dApp shows disconnected → no activity
- [ ] Request ETH transfer → human-readable explanation
- [ ] Request token approval → shows token and amount
- [ ] Request EIP-712 sign → structured display
- [ ] Unknown method → shows raw with warning
- [ ] Add dApp to allowlist → appears in list
- [ ] Allowlisted dApp → streamlined approval
- [ ] Add dApp to blocklist → appears in list
- [ ] Blocklisted dApp → connection blocked
- [ ] Rapid requests → rate limit warning
- [ ] Leave session 7+ days → auto-disconnected

**Automated Tests:**
- [ ] Unit test: Method signature decoding
- [ ] Unit test: EIP-712 parsing
- [ ] Unit test: Rate limiting logic
- [ ] Integration test: WC V2 handshake
- [ ] UI test: Session manager flow

---

## 9) Effort & Dependencies

**Effort:** M (3-4 days)

**Dependencies:**
- WalletConnect V2 Swift SDK
- Method signature database (4byte.directory)

**Risks:**
- WC V2 SDK breaking changes
- Decoding complex/custom methods

**Rollout Plan:**
1. WC V2 migration + session manager (Day 1)
2. Signing decoder + EIP-712 (Day 2)
3. Allowlist/blocklist + rate limiting (Day 3)
4. Verification + QA (Day 4)

---

## 10) Definition of Done

- [ ] WC V2 only
- [ ] Session manager functional
- [ ] Disconnect working
- [ ] Signing requests decoded
- [ ] EIP-712 structured
- [ ] Allowlist/blocklist working
- [ ] Rate limiting active
- [ ] dApp verification displayed
- [ ] Stale session cleanup working
- [ ] Analytics events firing
- [ ] PR reviewed and merged
