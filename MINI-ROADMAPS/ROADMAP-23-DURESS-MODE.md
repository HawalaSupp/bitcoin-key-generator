# ROADMAP-23 — Duress Mode & Advanced Security

**Theme:** Advanced Security Features  
**Priority:** P2 (Medium)  
**Target Outcome:** Duress mode and advanced security features for high-risk users

---

## 1) What This Fixes (Mapped to MASTER REVIEW)

- **Phase 2 P2-4** — Duress mode (decoy wallet under alternate passcode)
- **Edge Case #46** — Passcode entry triggers duress mode
- **Edge Case #43** — User forgets passcode
- **Edge Case #44** — User wants to wipe wallet remotely
- **Blueprint 5.6** — Advanced Security Settings

---

## 2) User Impact

**Before:**
- No protection against coerced access
- No decoy wallet option
- No advanced security features

**After:**
- Duress mode shows decoy wallet
- Plausible deniability under coercion
- Advanced security options for high-risk users

---

## 3) Scope

**Included:**
- Duress passcode setup
- Decoy wallet with small balance
- Plausible deniability mode
- Wipe wallet option
- Panic button (optional)
- Security audit log

**Not Included:**
- Remote wipe via iCloud
- Time-delayed transactions
- Multi-sig setup

---

## 4) Step-by-Step Tasks

### Design Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| D1: Duress setup flow | Enable duress mode | Clear explanation | Settings |
| D2: Duress passcode | Set alternate passcode | Different from main | Secure |
| D3: Decoy wallet UI | Looks like real wallet | Small balance | Indistinguishable |
| D4: Security audit log | View access attempts | Timestamps + method | Settings |
| D5: Panic button | Quick wipe option | Hidden gesture | Emergency |
| D6: Explanation screen | What is duress mode? | Educational | First-time |

### Engineering Tasks (Swift)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| E1: Duress passcode storage | Store secondary passcode | Keychain | Separate key |
| E2: Passcode branch | Check which passcode | Route to correct wallet | AuthService |
| E3: Decoy wallet | Separate wallet data | Small balance | Isolated storage |
| E4: Decoy seed | Pre-generated or user's | Plausible | Optional setup |
| E5: Duress detection | Track duress unlocks | Silent logging | AuditService |
| E6: Normal mode indicator | Subtle cue for user | Know which mode | Settings toggle |
| E7: Audit log storage | Store access events | Secure + local | AuditLog |
| E8: Audit log view | Display history | Read-only | AuditLogView |
| E9: Panic wipe | Quick wipe action | Hidden gesture | Secure erase |
| E10: Wipe confirmation | Require main passcode | Prevent accidental | Extra step |
| E11: Duress toggle | Enable/disable | Settings option | @AppStorage |
| E12: First-time education | Explain duress mode | Only once | Onboarding |

### QA Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| Q1: Setup duress | Enable duress mode | Passcode set | Happy path |
| Q2: Enter duress | Use duress passcode | Decoy wallet shown | Mode switch |
| Q3: Enter normal | Use normal passcode | Real wallet shown | Correct routing |
| Q4: Audit log | Check log | Duress access logged | Silent |
| Q5: Panic wipe | Trigger wipe | Data erased | Destructive |
| Q6: Disable duress | Turn off feature | Decoy removed | Cleanup |

---

## 5) Acceptance Criteria

- [ ] Duress mode can be enabled in Settings
- [ ] Alternate passcode can be set
- [ ] Duress passcode shows decoy wallet
- [ ] Normal passcode shows real wallet
- [ ] Decoy wallet indistinguishable from real
- [ ] Duress accesses logged in audit log
- [ ] Audit log viewable in Settings
- [ ] Panic wipe available (hidden gesture)
- [ ] Wipe requires confirmation
- [ ] First-time explanation shown

---

## 6) Edge Cases & Failure States

| Scenario | Detection | UX Response |
|:---|:---|:---|
| Duress and normal passcode same | Comparison | "Passcodes must be different" |
| Forget which is duress | User confusion | Subtle indicator option |
| Panic wipe accidental | Confirmation | Require main passcode |
| Duress mode disabled | Toggle off | Remove decoy data |
| Biometric opens which? | Setting | User chooses (or disabled in duress) |

---

## 7) Analytics / Telemetry

**Note:** Duress mode analytics must be extremely careful to not reveal usage patterns.

| Event Name | Properties | Success/Failure |
|:---|:---|:---|
| `duress_mode_enabled` | - | Success |
| `duress_mode_disabled` | - | Success |
| (No tracking of actual duress unlocks for safety) | | |

---

## 8) QA Checklist

**Manual Tests:**
- [ ] Enable duress mode in Settings
- [ ] Set duress passcode (different from main)
- [ ] Unlock with duress passcode → decoy wallet
- [ ] Decoy shows small/fake balance
- [ ] Unlock with normal passcode → real wallet
- [ ] Real wallet shows actual balance
- [ ] Check audit log → duress access logged
- [ ] Trigger panic wipe → data erased
- [ ] Panic wipe requires confirmation
- [ ] Disable duress mode → decoy removed
- [ ] Re-enable duress → setup flow again

**Security Tests:**
- [ ] Duress wallet isolated from real
- [ ] Cannot access real from duress
- [ ] Audit log cannot be deleted
- [ ] Passcodes stored securely

---

## 9) Effort & Dependencies

**Effort:** M (3-4 days)

**Dependencies:**
- Multi-wallet support (ROADMAP-21)
- Secure passcode storage

**Risks:**
- User confusion between modes
- Accidental panic wipe

**Rollout Plan:**
1. Duress passcode + routing (Day 1)
2. Decoy wallet setup (Day 2)
3. Audit log + panic wipe (Day 3)
4. QA + security review (Day 4)

---

## 10) Definition of Done

- [ ] Duress mode can be enabled
- [ ] Duress passcode works
- [ ] Decoy wallet shows correctly
- [ ] Real wallet protected
- [ ] Audit log functional
- [ ] Panic wipe works
- [ ] Confirmation required
- [ ] Security review passed
- [ ] PR reviewed and merged
