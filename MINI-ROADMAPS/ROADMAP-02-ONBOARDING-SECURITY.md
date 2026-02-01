# ROADMAP-02 — Onboarding Security & Verification

**Theme:** Onboarding / Security  
**Priority:** P0 (Emergency)  
**Target Outcome:** Users cannot skip backup verification without consequences; security education is mandatory

---

## 1) What This Fixes (Mapped to MASTER REVIEW)

- **[Critical] Quick Setup Skips All Security Education** (Section 3.1)
- **[High] iCloud Backup Offered During Phrase Screen** (Section 3.1)
- **[High] Backup Verification Can Be Skipped Without Consequence** (Section 3.1)
- **[Medium] No Time Estimate Shown for Guided Setup** (Section 3.1)
- **Top 10 Failures #7** — Backup Verification Skippable
- **Phase 0 P0-9** — Force 2-word verification in Quick onboarding
- **Master Changelog** — [Onboarding] Quick skips all education → Force 2-word verification
- **Master Changelog** — [Onboarding] iCloud during phrase display → Move to post-verification
- **Master Changelog** — [Onboarding] Backup skippable → Allow defer with limits
- **Master Changelog** — [Onboarding] No time estimate → Show "~3 minutes"
- **Conflict Decision** — Quick Onboarding Security Level (hybrid approach)
- **Blueprint 5.1** — Ideal Quick Onboarding
- **Blueprint 5.2** — Ideal Advanced Onboarding
- **Edge Case #4** — Back button during key generation
- **Edge Case #5** — Kill app during key generation
- **Edge Case #6** — Passcode/confirm mismatch
- **Edge Case #49** — User force quits during backup display
- **Microcopy Pack** — Onboarding Copy section

---

## 2) User Impact

**Before:**
- Users create wallets without understanding recovery
- Backup can be skipped entirely with no consequences
- iCloud decision during seed display causes confusion
- Unknown time commitment causes abandonment

**After:**
- All users prove minimal backup knowledge (2 words)
- Skipping backup applies sending limits + persistent banner
- iCloud decision is separate, post-verification
- Time estimates reduce anxiety and drop-off

---

## 3) Scope

**Included:**
- Quick onboarding: 2-word verification (random indices)
- "Do later" option with limits (<$100 send cap)
- Persistent "Backup required" banner if unverified
- Move iCloud backup to separate screen after verification
- Add time estimate to setup selection
- Security Score penalty for unverified backup

**Not Included:**
- Guided onboarding redesign (separate roadmap)
- Guardian/social recovery setup
- Duress mode configuration

---

## 4) Step-by-Step Tasks

### Design Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| D1: Quick verification screen | Design 2-word verification UI | Simple, non-punitive | Show word position clearly |
| D2: "Do later" confirmation | Design warning modal for skip | Clear consequences visible | Limits explained |
| D3: Unverified banner | Persistent banner for portfolio | Orange, dismissable but returns | Links to verification |
| D4: Time estimate badges | "~60s" and "~3 min" badges | On setup selection screen | Reduces anxiety |
| D5: Post-verification iCloud screen | Separate backup method selection | Clear tradeoffs explained | After verification |

### Engineering Tasks (Swift)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| E1: Add 2-word verification to Quick | Insert verification step after seed display | Random word indices; 2 attempts | Use SecureRandom for indices |
| E2: Implement "Do later" flow | Allow skip with `backupVerified = false` | Persisted to UserDefaults | Flag checked on send |
| E3: Enforce sending limits | Block sends > $100 if unverified | Show modal with "Complete backup" | Check in SendView |
| E4: Add persistent banner | Show in portfolio when unverified | Dismissable but returns on relaunch | ZStack overlay |
| E5: Move iCloud to post-verification | New screen after verification success | Options: Paper / Password Manager / iCloud | Separate concerns |
| E6: Add time estimates | Show "~60s" / "~3 min" on selection | Static text badges | Design-provided copy |
| E7: Update Security Score | Subtract 30 points if unverified | Score calculation updated | SecurityScoreService |
| E8: Handle edge cases | Back button, force quit, passcode mismatch | State machine for onboarding | Resume logic |

### Engineering Tasks (Rust)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| R1: Word verification API | `verify_seed_word(index, word) -> bool` | Fast, secure comparison | Already exists; verify |

### QA Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| Q1: Test Quick flow end-to-end | Create wallet via Quick path | Must verify 2 words | Happy path |
| Q2: Test "Do later" | Skip verification, try to send $200 | Blocked with modal | Limit enforcement |
| Q3: Test banner persistence | Dismiss banner, relaunch app | Banner returns | UserDefaults check |
| Q4: Test iCloud flow | Complete verification, choose iCloud | Works correctly | Post-verification |
| Q5: Test time estimates | Visual check on selection screen | Badges visible | Design review |
| Q6: Test Security Score | Check score with/without verification | 30 point difference | Score UI |

---

## 5) Acceptance Criteria

- [ ] Quick onboarding requires 2-word verification
- [ ] Random word indices (not fixed positions)
- [ ] "Do later" option available with clear warning
- [ ] Sending limit ($100) enforced for unverified users
- [ ] Persistent orange banner shown in portfolio if unverified
- [ ] iCloud backup is separate screen after verification
- [ ] Time estimates visible on setup selection ("~60s" / "~3 min")
- [ ] Security Score reduced by 30 points if unverified
- [ ] Force quit during seed display prompts re-verification on relaunch

---

## 6) Edge Cases & Failure States

| Scenario | Detection | UX Response |
|:---|:---|:---|
| User enters wrong word | Word mismatch | "Incorrect. Check word #X and try again." |
| User fails 3 times | Attempt counter | Offer to show seed again with biometric |
| Back button during generation | Navigation event | Cancel generation; return to selection |
| Force quit during seed display | Flag not set | Resume at seed display on relaunch |
| Passcode mismatch | Input validation | "Passcodes don't match. Try again." |
| Network offline during iCloud | Reachability check | "iCloud unavailable. Choose another option." |

---

## 7) Analytics / Telemetry

| Event Name | Properties | Success/Failure |
|:---|:---|:---|
| `onboarding_started` | `path` (quick/guided) | Always success |
| `seed_generated` | `word_count` (12/24) | Success |
| `backup_verification_started` | `path`, `indices` | Success |
| `backup_verification_completed` | `attempts`, `latency_ms` | Success |
| `backup_verification_skipped` | `reason` (user_choice) | Failure (soft) |
| `backup_method_selected` | `method` (paper/icloud/password_manager) | Success |
| `unverified_send_blocked` | `amount_usd`, `limit_usd` | Failure (expected) |

---

## 8) QA Checklist

**Manual Tests:**
- [ ] Quick path: complete 2-word verification successfully
- [ ] Quick path: fail verification, retry, succeed
- [ ] Quick path: skip with "Do later", verify banner appears
- [ ] Unverified: try to send $50 (should work)
- [ ] Unverified: try to send $150 (should block)
- [ ] Banner: dismiss, relaunch, verify it returns
- [ ] iCloud: appears after verification, not during
- [ ] Time estimates: visible on selection screen
- [ ] Security Score: reflects verification status
- [ ] Force quit during seed display: proper resume

**Automated Tests:**
- [ ] Unit test: word verification logic
- [ ] Unit test: sending limit enforcement
- [ ] Integration test: onboarding state machine
- [ ] UI test: onboarding flow completion

---

## 9) Effort & Dependencies

**Effort:** M (2-3 days)

**Dependencies:**
- None (self-contained)

**Risks:**
- May increase onboarding drop-off (mitigated by "Do later")
- Edge cases in state machine

**Rollout Plan:**
1. Implement verification + limits (Day 1)
2. Move iCloud, add estimates (Day 2)
3. QA + edge case fixes (Day 3)

---

## 10) Definition of Done

- [ ] 2-word verification required in Quick path
- [ ] "Do later" works with limits enforced
- [ ] Banner appears for unverified users
- [ ] iCloud is post-verification
- [ ] Time estimates visible
- [ ] Security Score updated
- [ ] All edge cases handled
- [ ] Analytics events firing
- [ ] PR reviewed and merged
