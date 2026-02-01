# ROADMAP-11 — Settings & Security Center

**Theme:** Settings / Security Configuration  
**Priority:** P1 (High)  
**Target Outcome:** Centralized security dashboard with clear settings, backup status, and advanced options

---

## 1) What This Fixes (Mapped to MASTER REVIEW)

- **[High] Settings Hidden in Avatar Menu** (Section 3.10)
- **[High] No Security Score or Dashboard** (Section 3.10)
- **[Medium] Auto-Lock Timer Not Configurable** (Section 3.10)
- **[Medium] No Export Private Key Flow** (Section 3.10)
- **[Medium] Advanced Settings Empty** (Section 3.10)
- **[Low] No "About" Section with Version Info** (Section 3.10)
- **Phase 1 P1-5** — Security Score dashboard
- **Phase 2 P2-4** — Duress mode (decoy wallet under alternate passcode)
- **Blueprint 5.6** — Ideal Settings & Security Center
- **Edge Case #43** — User forgets passcode
- **Edge Case #44** — User wants to wipe wallet remotely
- **Edge Case #46** — Passcode entry triggers duress mode
- **Edge Case #48** — Biometric fails 3 times
- **Microcopy Pack** — Security Settings

---

## 2) User Impact

**Before:**
- Settings buried in avatar menu
- No visibility into security posture
- Cannot configure auto-lock
- No way to export private keys

**After:**
- Settings accessible via ⌘,
- Security Score shows overall health
- Configurable auto-lock timer
- Secure private key export flow

---

## 3) Scope

**Included:**
- Dedicated Settings screen
- Security Score dashboard
- Auto-lock timer configuration
- Private key export flow
- View recovery phrase flow
- About section with version info
- Advanced settings with RPC config

**Not Included:**
- Remote wipe (future)
- Duress mode full implementation (P2 roadmap)
- Hardware wallet pairing settings

---

## 4) Step-by-Step Tasks

### Design Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| D1: Settings navigation | macOS sidebar or list | Grouped sections | General, Security, Advanced |
| D2: Security Score card | Score out of 100 | Breakdown visible | Color-coded (green/yellow/red) |
| D3: Score factors | List of factors | Each shows status | ✓ or ⚠ per item |
| D4: Auto-lock picker | Dropdown or stepper | 1/5/15/30 min + Custom | Persisted |
| D5: Export key flow | Multi-step modal | Password + warning + reveal | Scary design |
| D6: View phrase flow | Similar to export | Biometric + reveal | Grid layout |
| D7: About section | Version, build, links | Legal, support | Standard format |
| D8: Advanced settings | RPC endpoints, etc. | For power users | Developer mode |

### Engineering Tasks (Swift)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| E1: Settings view | Dedicated screen | Grouped settings | SettingsView |
| E2: Settings navigation | ⌘,  shortcut | Opens Settings | Global shortcut |
| E3: Security Score calc | Calculate from factors | Score 0-100 | SecurityScoreService |
| E4: Score factors | Check each security item | Return status | Backup, passcode, etc. |
| E5: Score UI | Display score + breakdown | Color-coded | SecurityScoreView |
| E6: Auto-lock timer | Configurable setting | Persisted | @AppStorage |
| E7: Auto-lock enforcement | Lock after timer | Background monitoring | AppLifecycle |
| E8: Export private key | Secure flow | Password required | KeychainExport |
| E9: Export warnings | Multiple confirmations | "This is dangerous" | Multi-step |
| E10: View recovery phrase | Biometric + display | Grid of words | SecurePhraseView |
| E11: Phrase blur/reveal | Blur until tap | Privacy protection | Blur modifier |
| E12: About section | Version, build info | Bundle info | Static display |
| E13: Advanced settings | RPC, developer mode | Power user options | AdvancedSettingsView |
| E14: Passcode change | Change passcode flow | Verify old, set new | AuthService |
| E15: Biometric toggle | Enable/disable | Persisted | LAContext |

### QA Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| Q1: Settings access | ⌘,  shortcut | Opens Settings | From anywhere |
| Q2: Security Score | View score | Correct calculation | Factor verification |
| Q3: Auto-lock | Set 1 min, wait | App locks | Timer accuracy |
| Q4: Export key | Complete flow | Key revealed | Secure |
| Q5: View phrase | Complete flow | Phrase shown | Biometric check |
| Q6: About section | View about | Version correct | Info.plist |
| Q7: Advanced settings | Toggle options | Changes applied | Persistence |

---

## 5) Acceptance Criteria

- [ ] Settings accessible via ⌘,  from anywhere
- [ ] Settings organized in logical groups
- [ ] Security Score displayed (0-100)
- [ ] Score breakdown shows each factor
- [ ] Factors include: backup verified, passcode set, biometric enabled
- [ ] Auto-lock timer configurable (1/5/15/30 min)
- [ ] Auto-lock enforced correctly
- [ ] Export private key requires password confirmation
- [ ] Export shows multiple warnings
- [ ] View recovery phrase requires biometric
- [ ] Phrase displayed in grid, blurred by default
- [ ] About section shows version and build
- [ ] Advanced settings includes RPC configuration

---

## 6) Edge Cases & Failure States

| Scenario | Detection | UX Response |
|:---|:---|:---|
| User forgets passcode | Failed attempts | "Use recovery phrase to reset" |
| Biometric fails 3 times | Failure counter | Fall back to passcode |
| Biometric not available | LAContext check | Hide biometric toggle |
| Export key cancelled mid-flow | Navigation event | No export occurs |
| Auto-lock while in transaction | Lock trigger | Require unlock to continue |
| Settings ⌘,  during sheet | Sheet check | Close sheet first, then open |
| Invalid RPC URL | URL validation | "Invalid endpoint URL" |

---

## 7) Analytics / Telemetry

| Event Name | Properties | Success/Failure |
|:---|:---|:---|
| `settings_opened` | `source` (shortcut/menu) | Success |
| `security_score_viewed` | `score`, `factors_count` | Success |
| `auto_lock_changed` | `from_minutes`, `to_minutes` | Success |
| `private_key_export_started` | - | Started |
| `private_key_export_completed` | - | Success |
| `private_key_export_cancelled` | `step_cancelled_at` | Cancelled |
| `recovery_phrase_viewed` | - | Success |
| `passcode_changed` | - | Success |
| `biometric_toggled` | `enabled` (bool) | Success |
| `about_viewed` | - | Success |

---

## 8) QA Checklist

**Manual Tests:**
- [ ] ⌘,  opens Settings from Portfolio
- [ ] ⌘,  opens Settings from Send flow
- [ ] Settings shows grouped sections
- [ ] Security Score displays correctly
- [ ] Score breakdown shows factors
- [ ] Low security → yellow/red score
- [ ] High security → green score
- [ ] Auto-lock timer dropdown works
- [ ] Set to 1 min, background app, wait → locks
- [ ] Export private key shows warnings
- [ ] Complete export → key revealed
- [ ] Cancel export → nothing revealed
- [ ] View recovery phrase → biometric prompt
- [ ] Phrase displayed in 3x4 grid
- [ ] Phrase blurred by default
- [ ] Tap to reveal works
- [ ] About shows correct version
- [ ] Advanced settings RPC configurable
- [ ] Biometric toggle works

**Automated Tests:**
- [ ] Unit test: Security Score calculation
- [ ] Unit test: Auto-lock timer logic
- [ ] Unit test: RPC URL validation
- [ ] Integration test: Keychain export
- [ ] UI test: Settings navigation

---

## 9) Effort & Dependencies

**Effort:** M (3-4 days)

**Dependencies:**
- Keychain access for export
- LAContext for biometrics

**Risks:**
- Security-sensitive features require careful implementation
- Auto-lock must not interrupt transactions

**Rollout Plan:**
1. Settings view + navigation (Day 1)
2. Security Score + auto-lock (Day 2)
3. Export key + view phrase (Day 3)
4. About + advanced + QA (Day 4)

---

## 10) Definition of Done

- [ ] Settings accessible via ⌘,
- [ ] Security Score working
- [ ] Auto-lock configurable and enforced
- [ ] Export private key secure flow complete
- [ ] View recovery phrase working
- [ ] About section displays version
- [ ] Advanced settings functional
- [ ] All edge cases handled
- [ ] Analytics events firing
- [ ] PR reviewed and merged
