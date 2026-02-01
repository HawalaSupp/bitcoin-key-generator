# ROADMAP-20 — Analytics & Telemetry Infrastructure

**Theme:** Analytics / Instrumentation  
**Priority:** P2 (Medium)  
**Target Outcome:** Comprehensive analytics infrastructure for data-driven decisions

---

## 1) What This Fixes (Mapped to MASTER REVIEW)

- **Implicit requirement** — All roadmaps reference analytics events
- **[Medium] No User Flow Analytics** (implied throughout)
- **[Medium] No Error Tracking** (Section 3.16)
- **[Low] No Performance Monitoring** (Section 3.11)
- **Phase 2 P2-8** — Analytics infrastructure
- **All Roadmaps** — Analytics sections require infrastructure

---

## 2) User Impact

**Before:**
- No visibility into user behavior
- Issues discovered only through support
- No data for prioritization

**After:**
- Understand user flows
- Catch issues proactively
- Data-driven prioritization

---

## 3) Scope

**Included:**
- Analytics SDK integration
- Event tracking infrastructure
- User flow analytics
- Error/crash reporting
- Performance monitoring
- Privacy-compliant implementation
- Opt-out mechanism

**Not Included:**
- A/B testing infrastructure
- Advanced funnel analysis
- Marketing attribution

---

## 4) Step-by-Step Tasks

### Design Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| D1: Event taxonomy | Define all events | Naming convention | Consistent naming |
| D2: Property schema | Standard properties | Per event type | Documented |
| D3: Privacy policy | Data collection disclosure | User consent | Legal review |
| D4: Opt-out UI | Settings toggle | Clear option | "Share analytics" |

### Engineering Tasks (Swift)

| Task | Description | Expected Behavior | Implementation Notes |
|:---|:---|:---|:---|
| E1: Analytics SDK | Integrate PostHog/Mixpanel/etc. | Working SDK | Privacy-focused choice |
| E2: Analytics service | Wrapper abstraction | Single interface | AnalyticsService |
| E3: Event tracking | Track events | Queued + batched | Background send |
| E4: User properties | Set user properties | Anonymized | No PII |
| E5: Screen tracking | Auto-track screens | View lifecycle | SwiftUI onAppear |
| E6: Error tracking | Integrate Sentry/similar | Crash + error | Symbolication |
| E7: Performance metrics | Track timing | Cold start, etc. | os_signpost |
| E8: Opt-out toggle | Settings implementation | Respects preference | @AppStorage |
| E9: Opt-out enforcement | Disable all tracking | When opted out | Check before track |
| E10: Debug mode | Verbose logging | Development only | #if DEBUG |
| E11: Event validation | Validate properties | Catch issues | Debug assertions |
| E12: Batch sending | Queue events | Send periodically | Background task |
| E13: Offline handling | Queue when offline | Send when online | Reachability |

### Documentation Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| DOC1: Event catalog | All events documented | Searchable | Wiki/Notion |
| DOC2: Property dictionary | All properties | Types + meanings | Reference |
| DOC3: Implementation guide | How to add events | Code examples | Developer docs |

### QA Tasks

| Task | Description | Expected Behavior | Notes |
|:---|:---|:---|:---|
| Q1: Event firing | Trigger events | Appear in dashboard | End-to-end |
| Q2: Opt-out | Toggle off | No events sent | Privacy |
| Q3: Crash reporting | Force crash | Appears in Sentry | Symbolicated |
| Q4: Performance | View metrics | Data accurate | Timing |
| Q5: Offline queue | Go offline, use app | Events sent later | Queuing |

---

## 5) Event Categories

### Core Events (from all roadmaps)

**Onboarding:**
- `onboarding_started`
- `onboarding_completed`
- `backup_verification_completed`
- `backup_verification_skipped`

**Portfolio:**
- `portfolio_viewed`
- `portfolio_search`
- `time_range_changed`

**Send/Receive:**
- `send_started`
- `send_confirmed`
- `send_failed`
- `receive_address_copied`

**Swap:**
- `swap_started`
- `swap_confirmed`
- `swap_failed`

**WalletConnect:**
- `wc_connection_approved`
- `wc_signing_approved`
- `wc_signing_rejected`

**Security:**
- `scam_address_blocked`
- `approval_revoked`
- `phishing_detected`

**Settings:**
- `settings_opened`
- `security_score_viewed`

**Errors:**
- `error_displayed`
- `error_action_tapped`

**Performance:**
- `app_cold_start`
- `screen_render_time`

---

## 6) Acceptance Criteria

- [ ] Analytics SDK integrated
- [ ] Analytics service abstraction created
- [ ] All events from all roadmaps trackable
- [ ] User properties set (anonymized)
- [ ] Screen views auto-tracked
- [ ] Error/crash reporting working
- [ ] Performance metrics captured
- [ ] Opt-out toggle in Settings
- [ ] Opt-out fully disables tracking
- [ ] Events queued offline, sent online
- [ ] Event catalog documented
- [ ] No PII in analytics

---

## 7) Privacy Requirements

- **No PII:** Never track addresses, balances, or identifiable info
- **Anonymized IDs:** Use random device ID, not Apple ID
- **Opt-out:** Easy toggle in Settings
- **Data retention:** 12 months max
- **Compliance:** GDPR/CCPA compatible
- **Transparency:** Clear privacy policy

---

## 8) QA Checklist

**Manual Tests:**
- [ ] Install app → opt-in by default (or opt-in prompt)
- [ ] Complete onboarding → events in dashboard
- [ ] Send transaction → events tracked
- [ ] Open Settings → toggle analytics off
- [ ] Continue using → no events sent
- [ ] Toggle back on → events resume
- [ ] Force crash → appears in crash reporter
- [ ] View dashboard → data makes sense

**Automated Tests:**
- [ ] Unit test: Event validation
- [ ] Unit test: Opt-out enforcement
- [ ] Integration test: Event delivery

---

## 9) Effort & Dependencies

**Effort:** M (2-3 days)

**Dependencies:**
- Analytics service selection (PostHog recommended)
- Crash reporter selection (Sentry recommended)

**Risks:**
- Privacy regulation compliance
- SDK overhead on performance

**Rollout Plan:**
1. SDK integration + service (Day 1)
2. Core events + error tracking (Day 2)
3. Opt-out + documentation (Day 3)

---

## 10) Definition of Done

- [ ] Analytics SDK integrated
- [ ] Service abstraction working
- [ ] Core events firing
- [ ] Crash reporting working
- [ ] Performance metrics captured
- [ ] Opt-out functional
- [ ] Offline queuing works
- [ ] Event catalog documented
- [ ] No PII in analytics
- [ ] PR reviewed and merged
