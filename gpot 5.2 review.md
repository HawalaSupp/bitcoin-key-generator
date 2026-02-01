# gpot 5.2 review (macOS) — Hawala Wallet
**Date:** February 1, 2026
**Role stack:** Principal Product Designer (fintech/crypto) • Senior macOS Engineer (SwiftUI/AppKit) • Rust wallet-core engineer • Security/trust UX specialist • QA lead • Growth/activation PM
**Platform:** macOS
**Tech:** Swift (UI/app) + Rust (core/signing/chain logic)

---

## 1) EXECUTIVE SUMMARY (HIGH SIGNAL)

**Overall rating:** 6.8/10

**Subscores:**
- Trust: 6.5/10
- UX clarity: 6/10
- Safety UX: 7/10
- Visual polish: 7.2/10
- Performance: 6.2/10
- Feature completeness: 8/10
- macOS-native feel: 5.8/10

**3 things that are excellent (and why)**
1. **Transaction preview / risk framing exists at all** (TransactionPreviewSheet + TransactionPreviewService): most wallet clones ship blind signing; you’re at least trying to humanize risk.
2. **Security-first ambition is real, not marketing** (duress/decoy, security score, practice mode hooks): this is the right category bet.
3. **Broadcast redundancy + propagation checks** (TransactionBroadcaster): you’re already solving real-world “RPC accepted but explorer never sees it” pain.

**3 things that are unacceptable (and why)**
1. **Two Rust integration paths (FFI + external CLI process) living side-by-side** (RustService vs RustCLIBridge): this is a reliability and security nightmare on macOS (sandbox, pathing, updates, code signing, attack surface).
2. **Key/seed security messaging vs actual UX default doesn’t match** (onboarding lets users skip verification; iCloud backup is implied but not clearly audited): you cannot ship a “security-first” wallet that makes unsafe choices easy.
3. **Architecture risk is extreme** (ContentView is massive and stateful): this will cause “random” bugs that users interpret as theft. In wallets, perceived unreliability = churn.

**Biggest reason users will churn**
- They won’t trust the app under stress: too many advanced features + too many flows, and the Mac experience feels like a SwiftUI demo app with a premium skin.

**Biggest reason users will recommend it**
- Duress/decoy + strong transaction warnings: it feels like someone finally built an “opsec wallet” that normal people can try.

**Biggest “silent killer” issue we might not notice**
- **RustCLI execution path** (hardcoded absolute paths + Process execution + separate binary build) will break in production distribution and will fail in ways that look like “signing is broken / funds stuck”. It’s silent until you ship outside your dev machine.

---

## 2) MACOS-NATIVE QUALITY AUDIT (CRITICAL)

This app is currently **~60% Mac-native** and **~40% “iOS patterns stretched onto a Mac window”**.

### What’s currently non-native
- **NavigationStack-heavy layouts** for screens that should be **split view + inspector** on macOS.
- **Custom headers with close buttons** inside content (e.g., ReceiveViewModern) instead of a toolbar/standard sheet chrome.
- **Sheets used as feature navigation** (dozens of `showXSheet` booleans): on macOS, this reads as “modal spam.”
- **No pervasive keyboard strategy**: crypto wallets on Mac live/die on shortcuts (copy address, open send, toggle sidebar, focus search).
- **No right-click context menus** for addresses, txids, tokens, sessions, etc.
- **Hover/focus states are inconsistent** (WalletConnectView has hover, many others won’t).
- **QR scanning disabled** in WalletConnectView (“Scan QR” is disabled): this reads as broken product, not “coming soon.”

### What to change to feel premium on macOS
- **Move to `NavigationSplitView` for primary IA** (Sidebar → Content → optional Inspector).
- **Use toolbar items** for global actions: Send, Receive, Swap, Search, Settings, Lock.
- **Replace most feature sheets** with:
  - secondary windows (Send, Receive, WalletConnect)
  - popovers for small actions
  - inspectors for details (token details, tx details, risk breakdown)
- **Command system**: implement `Commands` (menu items) + `KeyboardShortcut`.
- **Context menus** everywhere: right-click on address/token/tx → Copy / View on explorer / Label / Add to contacts / Report scam.
- **Drag & drop**:
  - Drop an address/URI onto the app → opens send/connect flows.
  - Drag txid/address out as text.
- **Multi-window**:
  - Portfolio window
  - Send window (per-chain)
  - WalletConnect sessions window
  - Security Center window

### Exact UI patterns to use instead
- **Sidebar:** `NavigationSplitView` with groups:
  - Portfolio
  - Activity
  - Swap
  - Bridge
  - dApps (WalletConnect)
  - Security Center
  - Settings
- **Inspector panel:** token details, tx details, risk details (`.inspector` style behavior).
- **Sheets only for wizards** (onboarding, backup, recovery) and confirmation prompts.
- **Popovers** for small “copy/label” actions.
- **Tables** (`Table`) for activity/history, token list, sessions.

---

## 3) TRUST & SECURITY PERCEPTION TEARDOWN

### Does it look legit or sketchy?
- Mostly legit. Visual skin is strong.
- But the product leaks “prototype” through disabled features (WalletConnect scan), “preview” banners (DEX), and scattered advanced options.

### Does it feel “bank-grade” or “random crypto app”?
- It *wants* to be bank-grade, but the app behaves like a power-user toolkit.
- Bank-grade = fewer choices, clearer defaults, and more “explain then act.”

### Are warnings credible or annoying?
- You’re closer to credible than annoying.
- The risk model is currently incomplete (EVM-only preview, simplistic decoding). Users will quickly find false negatives.

### Is self-custody explained clearly?
- Partially. You have education screens.
- But the presence of iCloud backup + duress + guardians creates a contradictory mental model unless you unify it: “What exactly is stored where?”

### Does the app overpromise safety?
- Yes, in two places:
  1) **Duress “silent alert” concept** (if implemented) can never be “guaranteed.” Any UI implying guaranteed protection is dangerous.
  2) **Seed backup verification** is easy to skip; the app’s “security vibe” overpromises vs user behavior.

### Trust builders (keep)
- Transaction Preview sheet with risk badge.
- Propagation check approach for EVM broadcast.
- Explicit separation of Quick vs Guided onboarding.

### Trust killers (fix immediately)
- Disabled UX in core flows (WalletConnect QR button disabled).
- “Preview Feature” DEX view visible in production nav.
- Any feature that can cause false safety confidence (duress alerts, “backup done” without strong verification).

### Missing trust signals (add)
- A **Security Center dashboard**: current lock state, backup status, duress configured, trusted contacts, connected dApps, last keychain access.
- **Clear storage disclosures**:
  - “Seed stored in Keychain (this Mac only)”
  - “iCloud Keychain backup: ON/OFF”
  - “Passcode protects local unlock; it does not replace the seed.”
- **Signed build identity** visible in Settings (version, build hash, update channel).

### “Fear moments” where users will freeze
- First time they see “Unlimited Token Approval”.
- First time a tx says “Pending” for more than 2 minutes.
- When they switch chains and balances differ or disappear.
- When a WalletConnect request arrives with unreadable call data.

---

## 4) ONBOARDING REVIEW (EXTREMELY DETAILED)

You need two onboarding modes, but they must converge into one consistent security model.

### 4A) Quick onboarding (experienced users)

**Unnecessary steps (remove or defer)**
- Persona selection for quick path (optional). Power users don’t want personality quizzes.
- Long self-custody education slides. Replace with a single “You are responsible. Learn more” inline disclosure.

**Missing steps (must add)**
- Immediate **lock/biometric gating** confirmation: user must understand what is protected by what.
- “Confirm network environment” for first wallet: mainnet/testnet guardrails.

**Speed blockers**
- Any forced reading.
- Any multi-screen “explainers” not tied to an action.

**Confusing jargon**
- “Guardian”, “duress”, “practice mode” without “what it does for me.”

**Bad defaults**
- Allowing backup verification “skip” too easily.

#### Redesigned quick flow (screen-by-screen)
**Target:** under 60 seconds to usable wallet.
1) **Welcome**
   - CTA: “Create wallet (60s)” and “Import existing”.
2) **Security baseline choice (1 screen)**
   - Toggle: “Unlock with Touch ID” (recommended)
   - Toggle: “Require passcode on launch” (recommended)
   - Link: “Advanced security setup”
3) **Create wallet**
   - Generate seed.
   - Show: “You can fund now, but backup is required before sending >$X.”
4) **Backup: fast verification**
   - 2 random words (not fixed positions).
   - No skip; allow “Do later” but apply limits until verified.
5) **Done**
   - Show Security Score: “60% — verify backup to remove limits.”

#### Microcopy suggestions (quick)
- “Create wallet in ~60 seconds”
- “Back up now (recommended)”
- “Do later (limits apply)”

**Optional vs required**
- Required: seed creation/import, baseline lock.
- Optional: guardians/duress/advanced settings.

### 4B) Advanced onboarding (guided + safest setup)

**Cognitive load problems**
- Too many advanced concepts stacked: seed → guardians → practice → passcode → biometrics.

**Anxiety triggers**
- Heavy “threat language” too early. Advanced path should feel calm, not paranoid.

**Backup/recovery confusion**
- The presence of iCloud backup alongside self-custody education needs crystal clarity.

**Verification friction**
- Verification must be meaningful but not punitive.

#### Redesigned advanced flow (screen-by-screen)
1) **Choose setup goal**
   - “Safest possible” vs “Balanced”
2) **Explain storage model (1 screen)**
   - Bullet diagram: Seed → Keychain (local) + optional iCloud backup.
3) **Create seed**
   - Display with “Reveal” gated by biometrics.
4) **Backup method selection**
   - Paper / password manager / iCloud Keychain backup.
   - If iCloud: explain tradeoff plainly.
5) **Verification (non-punitive)**
   - 3 random words; adaptive difficulty.
   - If fail twice: offer “Practice Mode” mini drill.
6) **Guardian / recovery**
   - Add 2–3 trusted contacts (can defer).
7) **Duress setup (optional, advanced)**
   - Explicit disclaimer: “No system can guarantee emergency alerts.”
8) **Security Score summary**
   - Show exactly what is enabled and what risk remains.

#### “Security Setup Score” concept
Keep it, but make it truthful:
- Score reflects actual protections enabled.
- Items must link to a “What this protects against” explanation.

#### Backup verification that doesn’t feel like punishment
- Give users a reason: “This is the difference between recovery and total loss.”
- Provide a progress meter and a “Try again” that doesn’t shame.

#### Scam education in micro-doses
- Place one micro-warning at the moment of relevance:
  - On Receive: “Only send on this network.”
  - On dApp connect: “Never approve unlimited allowances to unknown apps.”

### 4C) macOS onboarding-specific improvements
- **First-run window experience:** onboarding should be a centered, fixed-size wizard window (not a giant resizable canvas).
- **Permission prompts timing:** request biometrics only when user tries to enable it or reveal the seed.
- **Wizard vs stepper:** use a stepper in the left sidebar of the wizard (“Welcome → Backup → Security → Done”).
- **Support “I’ll do this later” safely:** allow deferral but enforce:
  - sending limits
  - persistent Security Center badge
  - reminders after first deposit

---

## 5) INFORMATION ARCHITECTURE & NAVIGATION

### Where users get lost
- Too many feature entrypoints; unclear what is “core wallet” vs “advanced lab.”
- Modals/sheets create disorientation (closing loses context).

### Where the mental model breaks
- “Security” appears in onboarding, settings, duress, score — but not as one coherent system.

### Recommended sidebar map
- **Portfolio**
- **Activity**
- **Send / Receive** (or one “Transfer” section with sub-actions)
- **Swap**
- **Bridge**
- **dApps**
- **Security Center**
- **Settings**

### Naming fixes
- “Security Center” (not “Security Policies” + “Advanced Security” scattered)
- “Contacts” = Address Book
- “dApps” = WalletConnect

### Alternative IA layout A (simple)
- Portfolio
- Transfer
- Activity
- dApps
- Security
- Settings

### Alternative IA layout B (pro)
- Portfolio
- Tokens
- Activity
- Swap
- Bridge
- dApps
- Security
- Advanced (power features)
- Settings

---

## 6) CORE FLOWS TEARDOWN (SCREEN-BY-SCREEN)

### Portfolio / Home dashboard
**What works**
- Strong visual identity and theming.

**What fails**
- Likely overloaded with metrics and features; users need “total value, change, top assets, quick actions.”

**Users misunderstand**
- What’s “synced” vs “estimated” vs “stale.”

**Loss-of-funds UX risks**
- Acting on stale prices/balances; wrong-chain confusion.

**Exact redesign**
- Add “Data freshness” badge (Updated 12s ago / Stale).
- 3 primary CTAs in toolbar: Send, Receive, Swap.
- Token list in a `Table` with sortable columns.

**Must-have edge cases**
- Offline mode
- Partial provider outage
- Huge token list (spam)

### Token list + token details
**What works**
- You have caches and services; foundation exists.

**What fails**
- Spam tokens will destroy trust and performance.

**Redesign**
- Default: hide unknown/spam; show “X hidden tokens” expander.
- Token details: show verified badge + contract address + copy + explorer.

### Receive flow (ReceiveViewModern)
**What works**
- Network pills, QR, copy toast, address verification overlay is a good instinct.

**What fails**
- BTC address format selector exists but may not actually change the receive address (needs to be true, not cosmetic).
- USD conversion uses hardcoded prices (btcPrice/ethPrice/ltcPrice). That’s unacceptable for a real product.

**Users misunderstand**
- They will assume any “Receive” address accepts any token.

**Loss-of-funds risks**
- Wrong-chain deposit.

**Exact redesign suggestions**
- For every chain: show “Network: X” with a “Only send X on this network” warning.
- Add “Copy as URI” for chains that support it (bitcoin:, ethereum:).
- Replace hardcoded prices with your price service or remove USD toggle until real.

**Edge cases**
- Memo/tag required (XRP destination tag; SOL memo; etc.)

### Send flow (SendView)
**What works**
- Address validation concept exists.
- Fee estimator + fee warnings exist.
- Security check sheet exists.

**What fails**
- Chain enum defined inside SendView file is a smell (logic+UI mixed).
- Too many fields exposed (gas price, nonce, fee rate) for normal users.

**Users misunderstand**
- Fee controls and confirmation steps.

**Loss-of-funds risks**
- Wrong chain
- Incorrect decimals
- Overpaying gas

**Exact redesign**
- Default send form:
  - To: address/ENS
  - Amount
  - Fee: Slow/Standard/Fast with estimates
  - Advanced disclosure reveals nonce/gas/utxo.
- Always show “You are sending on: Ethereum Mainnet” as a pill.

**Edge cases**
- ENS resolves to new address (show resolved + allow “pin”).
- Address poisoning (show warnings when prefix/suffix matches known address but differs).

### Swap flow (DEXAggregatorView)
**What works**
- Quote comparison concept.

**What fails**
- It is explicitly a simulated preview feature but still present as a core nav item.

**Exact redesign**
- If not real, remove from main nav.
- If real, must include:
  - token approvals
  - slippage + price impact
  - route transparency
  - simulation + risk warnings

### Bridge flow
**What fails**
- Bridges require extreme trust UX: finality, delays, refund paths.

**Must-have**
- Status timeline, “funds locked / minted,” refund options.

### NFTs
- If you show NFTs, you must handle spam NFTs and malicious metadata.

### Activity / history
**What works**
- Services exist.

**What fails**
- Needs a `Table` with filters, search, copy txid, open in explorer.

### Address book / contacts
- Must ship. Copy/paste addresses is a loss-of-funds generator.

### dApp connections / WalletConnect
**What works**
- Sessions list with disconnect.

**What fails**
- QR scan disabled.
- Session requests need a best-in-class confirmation.

### Settings + Security Center
- Security must not be scattered. Users need one place.

### Multi-account / multi-wallet switching
- Must be explicit. Avoid hidden state and magic.

### Fiat on-ramp/off-ramp
- If present, must include compliance-level clarity (fees, KYC, settlement).

### Notifications + alerts (macOS style)
- Must use Notification Center patterns and a clear preference panel.

---

## 7) TRANSACTION REVIEW QUALITY (THIS MUST BE HARSH)

Your transaction confirmation is **promising but not yet best-in-class**.

### What’s missing / broken (harsh)
- **Human-readable summary is incomplete**: EVM decode is shallow and can mislead.
- **Unlimited approvals detection is unreliable**: TransactionPreviewService decodes `uint256` into `UInt64` → overflow risk; it will miss common max uint approvals.
- **No “what changes” diff**: users need “You give permission to spend: X” and “You will receive: Y”.
- **No consistent safe defaults** enforced.

### Redesigned transaction confirmation layout (macOS)
**Left column (summary):**
- Action type: Send / Swap / Approve / Connect
- Asset + amount
- Network
- Recipient identity (name/verified/scam flags)

**Right column (details + risk):**
- Fee breakdown
- Risk score + top 3 warnings
- Expandable decoded call data
- Simulation results

**Bottom bar:**
- Primary: Confirm (with Touch ID if enabled)
- Secondary: Cancel
- Tertiary: “Advanced details”

### Exact warning copy examples
- Unlimited approval:
  - Title: “This app can spend ALL your USDC”
  - Body: “Unlimited approvals are the #1 way wallets get drained. Approve a limited amount unless you fully trust this dApp.”
  - CTA: “Approve limited amount…”
- Unknown contract:
  - “Unknown contract interaction”
  - “We can’t verify what this contract will do. Proceed only if you trust the source.”

### Safe defaults rules
- Approvals: default to limited approvals.
- Slippage: default 0.5% for stable pairs, 1% for volatile; block > 5% unless user types confirmation.
- Gas: choose “Standard” by default; allow “Fast” with visible cost delta.

---

## 8) SAFETY SYSTEMS & SCAM DEFENSE (REAL WORLD)

### Threats + defenses (UX + technical)

**Phishing addresses / address poisoning**
- Mechanism: detect prefix/suffix collisions vs known addresses.
- UX: “Looks similar to a saved address” warning with highlight differences.
- Block vs warn: warn by default; block only for confirmed scam list.

**Clipboard hijacking**
- Mechanism: re-read clipboard after paste; detect changes; require confirmation.
- UX: “Clipboard changed recently” badge.

**Token dust attacks / spam tokens**
- Mechanism: classify tokens with heuristics + known lists.
- UX: hide by default; show “Hidden tokens” section.

**Malicious NFT / spam NFT**
- Mechanism: do not auto-load remote images; proxy or block.
- UX: “Untrusted media” placeholder with click-to-load.

**Fake support scams**
- UX: persistent banner in Settings: “We will NEVER DM you.”

**Wrong chain deposits**
- UX: receive screen must scream the network.
- Tech: if you can detect deposit on wrong chain, surface a recovery path.

**Fake token symbols**
- UX: verified badges and show contract address always.

**Malicious dApps requesting approvals**
- UX: show domain, chain, requested methods, and spending scope.

**Blind signing**
- Block any approval that cannot be decoded unless user opts into “Blind sign mode.”

**Bridge risk & finality**
- UX: show “Funds locked until…” and “Refund conditions”.

---

## 9) UI DESIGN & VISUAL POLISH (MAC PREMIUM STANDARD)

### What looks expensive
- Dark theme + silk backgrounds.
- Consistent card styling (hawalaCard) in some flows.

### What looks cheap
- iOS-like pill buttons and stacked cards where macOS expects tables and split views.
- Too many icons with inconsistent fill styles.

### Exact UI changes (component-level)
- Use `Table` for tokens/activity/sessions.
- Use a global `Toolbar` with consistent CTAs.
- Adopt two density modes: Comfortable / Compact.
- Replace in-content close buttons with standard sheet toolbars.

### Design system fixes list
- Single source of truth for:
  - Primary/secondary/destructive button styles
  - Form field styles
  - Inline warnings vs blocking alerts
  - Typography scale for macOS

---

## 10) COPYWRITING & MICROCOPY (REWRITE LIKE A PRO)

### 20 microcopy rewrites (best candidates)
1. “Preview Feature” → “Beta: Swaps are disabled in this build.”
2. “Connecting…” → “Connecting to WalletConnect relay…”
3. “Invalid input string” → “Something went wrong. Please try again.”
4. “FFI returned null” → “Crypto engine error. Please restart the app.”
5. “Unlimited Token Approval” → “This app can spend ALL your tokens.”
6. “ETH Transfer to Contract” → “You’re sending ETH into a contract call.”
7. “No project ID configured” → “WalletConnect isn’t configured yet. Add a Project ID in Settings.”
8. “Scan QR (disabled)” → “Scan QR (coming next build)” (or remove button).
9. “User rejected” → “You rejected this request.”
10. “Invalid seed phrase format” → “Recovery phrase doesn’t match the wordlist.”
11. “No seed found” → “No wallet backup found on this Mac.”
12. “Backup failed” → “iCloud backup failed. Your wallet is still safe locally.”
13. “Restore failed” → “Couldn’t restore. Check your phrase and try again.”
14. “Network” label → “Network (must match sender)”
15. “Address Format” → “Bitcoin address type”
16. “Copy” toast → “Copied address”
17. “Done” → “Close” (in utility windows)
18. “Remove duress protection” → “Turn off duress protection”
19. “Decoy wallet” → “Secondary profile” (less sensational)
20. “Risk: Medium” → “Risk: Medium — review warnings”

### Warning templates
- High-risk approval:
  - Title: “High risk: unlimited spending permission”
  - Body: “This can allow a dApp to drain your funds. Approve a limited amount unless you fully trust it.”
  - Actions: “Approve limited amount… / Approve unlimited / Cancel”

- Suspicious token:
  - “This token appears unverified or spam. It’s hidden by default.”

- Bridge risk:
  - “Bridges can fail. Funds may be delayed or unrecoverable depending on the bridge. Proceed only if you accept this risk.”

- Slippage too high:
  - “Slippage is set to 8%. You may receive much less than expected.”

- Unknown contract interaction:
  - “We can’t decode this contract call. Treat as blind signing.”

### Confirmation templates
- Send:
  - “Send {amount} {asset} on {network} to {recipient}?”
- Swap:
  - “Swap {from} → {to}. You’ll receive at least {minOut}.”
- Connect dApp:
  - “Allow {dApp} to view your address and request transactions?”

### Error message templates (actionable)
- “RPC timeout. Try again or switch provider in Settings.”
- “Insufficient funds including fees. Reduce amount or choose a lower fee.”

---

## 11) PERFORMANCE & RELIABILITY REVIEW (MACOS REALITY)

### Critique
- SwiftUI with giant state graphs will stutter; your massive stateful root view increases redraw risk.
- Many network calls (prices, balances, history) must be staged to avoid UI blocking.

### Deliver: specific improvements
- Use skeletons for portfolio/token list, not spinners.
- Cache per-chain balances with timestamps and show stale indicators.
- Make providers observable and switchable.
- Ensure all heavy work is `Task`/async and never blocks the main actor.

### Where to use optimistic UI
- After broadcasting: show pending tx immediately in Activity.

### How Rust core should expose async APIs safely
- Prefer FFI functions that are pure and fast.
- For networked operations, Swift should orchestrate network; Rust should build/sign/validate.

---

## 12) ARCHITECTURE REVIEW (SWIFT + RUST BOUNDARIES)

### Practical architecture advice

**Responsibility split (recommended)**
- Rust: key derivation, tx building/signing, address validation, deterministic decoding.
- Swift: storage orchestration, UI state, networking, caching, OS integrations.

**Stop doing this**
- Running an external Rust binary from the app (`RustCLIBridge` + `Process`) for signing.
  - It will break distribution and creates a huge attack surface.

**API shape Swift ↔ Rust (example)**
- `rust_build_tx(chain, inputs) -> { unsigned_tx, metadata }`
- `rust_sign_tx(chain, unsigned_tx, keyRef) -> { signed_tx }`
- `rust_decode_tx(chain, signed_tx) -> { human_readable_summary, risks }`

**Error mapping**
- Rust errors should be stable enums mapped to Swift errors with user-facing messages.

**Logging (privacy-safe)**
- Never log seeds, private keys, full addresses by default.

**Analytics events design**
- Track funnel and safety events without storing sensitive data.

**Test strategy**
- Rust: unit tests for signing, decoding, address validation.
- Swift: UI tests for onboarding and send confirmation.
- End-to-end: build → sign → broadcast (mock network) → show pending.

### Recommended module breakdown
- Swift:
  - `AppShell` (window/commands)
  - `Portfolio` (balances/prices)
  - `Transfer` (send/receive)
  - `SecurityCenter` (backup, duress, passcode)
  - `DApps` (WalletConnect)
  - `Infrastructure` (providers, cache)
- Rust:
  - `core-keys`
  - `core-tx`
  - `core-validate`

---

## 13) QA / BUG MAGNET LIST (HOW THIS APP WILL BREAK)

At least 30 realistic failure points (each includes detection + graceful UX handling):

1. Chain switch resets fields incorrectly → detect via UI tests; preserve drafts per chain.
2. ENS resolves intermittently → show “last resolved” + retry.
3. Address validation races → debounce and show stable state.
4. Clipboard hijack after paste → warn if clipboard changes.
5. Wrong decimals display → unit tests for formatting.
6. Rounding errors for fiat conversion → consistent rounding rules.
7. Price feed mismatch vs balance source → show “price source” and stale badge.
8. Balance API returns null → show cached + “stale” not 0.
9. RPC outage → automatic failover + provider health UI.
10. Broadcast succeeds but explorer doesn’t show → your propagation check helps; surface “still propagating.”
11. Pending tx stuck forever → show “rebroadcast / replace-by-fee” actions.
12. Fee estimator returns extreme values → clamp + warning.
13. Gas limit too low → simulation/estimation must block.
14. Nonce mismatch → automatic nonce manager + retry.
15. Duplicate tx broadcast → idempotency guard.
16. Swap quote expires → countdown + auto-refresh.
17. Bridge status desync → poll + show source of truth.
18. Wallet import wrong word count → immediate validation.
19. Wallet import wordlist language mismatch → detect language and prompt.
20. Keychain access prompts at bad times → defer access, only on action.
21. Biometric fails after sleep → fallback to passcode.
22. Duress mode state leak → ensure mode indicator and data isolation.
23. “Decoy wallet” accidentally shows real balances → test mode isolation.
24. WalletConnect request arrives while locked → queue and require unlock.
25. WalletConnect request flood → rate limit and batch.
26. Contract decoding fails → force “blind sign mode” toggle.
27. Token list spam causes UI freeze → virtualized lists and pagination.
28. NFT metadata loads remote trackers → block remote loads.
29. Session persistence corrupts → resilient decoding + reset.
30. Rust FFI returns invalid JSON → strict validation + fail safely.

---

## 14) PRIORITIZED IMPROVEMENT ROADMAP (MUST BE HUGE)

### Tier 0: Emergency Fixes (must ship ASAP) — 10+ items
1) Problem: Rust signing depends on external CLI path → Fix: remove Process-based signing, unify on FFI → Impact: reliability + security massive → Effort: L → Owner: Eng → Notes: shipping blocker.
2) Problem: WalletConnect QR scan disabled → Fix: implement scan or remove entrypoint → Impact: trust/activation → Effort: M → Owner: Both → Notes: “broken button” kills credibility.
3) Problem: Transaction preview uint256 decode overflow → Fix: use BigInt/Decimal decoding; detect max approvals correctly → Impact: safety → Effort: M → Owner: Eng → Notes: current warnings miss the common drain case.
4) Problem: Hardcoded/placeholder pricing in Receive → Fix: remove USD toggle until real data → Impact: trust → Effort: S → Owner: Eng.
5) Problem: Preview DEX visible in production → Fix: hide behind dev flag or remove → Impact: trust → Effort: S → Owner: Both.
6) Problem: Security Center is fragmented → Fix: create single Security Center hub → Impact: clarity → Effort: M → Owner: Both.
7) Problem: Users can skip meaningful backup verification → Fix: allow deferral but enforce limits + persistent reminders → Impact: loss prevention → Effort: M → Owner: Both.
8) Problem: Keychain/seed operations may log in debug → Fix: audit logs and redact; add structured logger → Impact: security → Effort: S → Owner: Eng.
9) Problem: macOS UI uses too many sheets for navigation → Fix: implement NavigationSplitView + toolbar; reduce modals → Impact: macOS-native feel → Effort: L → Owner: Both.
10) Problem: Address book not first-class → Fix: ship contacts as core flow with autocomplete → Impact: loss prevention + retention → Effort: M → Owner: Both.

### Tier 1: High ROI Improvements (1–2 weeks) — 15+ items
1) Problem: No consistent keyboard shortcuts → Fix: add Commands + shortcuts (Send, Receive, Search, Copy) → Impact: macOS delight → Effort: M → Owner: Both.
2) Problem: History UX not table-first → Fix: Table with search/filter/context menu → Impact: trust/support reduction → Effort: M → Owner: Both.
3) Problem: Provider health opaque → Fix: provider status view + auto failover indicators → Impact: reliability perception → Effort: M → Owner: Eng.
4) Problem: Stale data confusing → Fix: “last updated” badges and stale states everywhere → Impact: clarity → Effort: S → Owner: Both.
5) Problem: Token spam risk → Fix: spam filtering + hidden tokens UI → Impact: trust/performance → Effort: M → Owner: Both.
6) Problem: WalletConnect request confirmation weak → Fix: macOS confirmation panel with decoded call + risk warnings → Impact: safety → Effort: M → Owner: Both.
7) Problem: Wrong-chain deposits → Fix: network warnings + chain detection hints; recovery guidance → Impact: loss prevention → Effort: M → Owner: Both.
8) Problem: No “drafts” for send → Fix: per-chain send drafts persist locally → Impact: conversion → Effort: S → Owner: Eng.
9) Problem: Fee UX too technical → Fix: default fee presets with time/cost estimates → Impact: clarity → Effort: M → Owner: Both.
10) Problem: Duress mode user confusion → Fix: subtle duress indicator + mode isolation tests → Impact: safety trust → Effort: M → Owner: Both.
11) Problem: Seed backup model unclear → Fix: storage disclosure UI + copy improvements → Impact: trust → Effort: S → Owner: Both.
12) Problem: Too many advanced features visible → Fix: “Advanced” section and progressive disclosure → Impact: clarity → Effort: S → Owner: Both.
13) Problem: Loading states spinners → Fix: skeletons for lists/cards → Impact: perceived performance → Effort: M → Owner: Both.
14) Problem: No offline mode messaging → Fix: offline banner + cached mode UI → Impact: trust → Effort: S → Owner: Both.
15) Problem: Error messages too low-level → Fix: user-facing error mapping + retry actions → Impact: support reduction → Effort: M → Owner: Both.

### Tier 2: Best-in-Class Upgrades (1–2 months) — 10+ items
1) Problem: Self-custody still seed-centric → Fix: robust social recovery (guardians) with clear UX → Impact: retention + differentiation → Effort: L → Owner: Both.
2) Problem: Approvals management missing → Fix: token approvals dashboard + revoke flows → Impact: safety → Effort: L → Owner: Both.
3) Problem: Advanced simulation limited to EVM decode → Fix: full tx simulation pipeline and risk scoring → Impact: trust → Effort: L → Owner: Eng.
4) Problem: Multi-wallet identity weak → Fix: multi-profile system with separate vaults → Impact: pro adoption → Effort: L → Owner: Both.
5) Problem: Bridge trust UX incomplete → Fix: best-in-class bridge timeline + refund education → Impact: safety → Effort: L → Owner: Both.
6) Problem: macOS pro workflows missing → Fix: multi-window workspace + inspector panels → Impact: delight → Effort: L → Owner: Both.
7) Problem: Privacy posture not explicit → Fix: privacy center + provider routing controls (Tor optional) → Impact: differentiation → Effort: M → Owner: Both.
8) Problem: Watch-only onboarding not polished → Fix: “Portfolio-only mode” with easy upgrade → Impact: activation → Effort: M → Owner: Both.
9) Problem: Continuous security monitoring missing → Fix: scam address feeds + heuristics updates → Impact: safety → Effort: M → Owner: Eng.
10) Problem: Distribution trust gap → Fix: signed updates + release notes integrity checks → Impact: trust → Effort: M → Owner: Eng.

---

## 15) FINAL MASTER CHANGELOG (EVERYTHING)

MASTER CHANGELOG
[Architecture] Dual Rust integration (FFI + CLI) → Remove CLI path, unify on FFI → Signing becomes reliable, shippable, and safer
[macOS Shell] Modal sheet sprawl → NavigationSplitView + toolbar + inspector → App feels like a real Mac product
[WalletConnect] Disabled QR scan button → Implement scanning or remove UI → Users stop assuming the product is broken
[WalletConnect] Weak request confirmation → Add decoded call + risk summary + safe defaults → Users understand and trust approvals
[Transaction Preview] uint256 decoded as UInt64 → Use BigInt-safe decoding → Unlimited approvals detected correctly
[Transaction Preview] No “state change” explanation → Add “You give / You get / You allow” summary → Fewer blind confirms
[Send] Advanced fields exposed by default → Hide behind Advanced disclosure → Lower cognitive load, fewer mistakes
[Send] Chain model mixed into view file → Move chain models to shared module → Cleaner code, fewer regressions
[Receive] Hardcoded USD prices → Use real price service or remove toggle → No fake financial data
[Receive] Weak wrong-network guardrails → Add network warnings + URI copy → Fewer wrong-chain deposits
[Security] Backup verification skippable without consequence → Allow deferral but enforce limits + reminders → Reduced catastrophic loss
[Security] Security features scattered → Single Security Center hub → Clear mental model and higher completion
[Security] Logs may leak sensitive info in debug → Redact + structured logger → Lower key exposure risk
[Duress] Mode confusion risk → Subtle duress indicator + strict data isolation → Users don’t misinterpret decoy state
[Portfolio] No freshness indicators → Add “Updated/stale” badges → Users trust displayed balances
[Activity] Non-table UI for history → Use Table with search/filter/context menu → Best-in-class macOS scanning
[Spam] Token/NFT spam not contained → Default hide unverified + safe media loading → App stays fast and trusted
[Performance] Spinner-heavy loading → Skeleton loading + caching → Perceived performance improves
[Providers] Outages feel like app bugs → Provider health UI + auto failover → Reliability perception improves
[UX System] Inconsistent components → Unified design system rules → Higher polish and consistency
[macOS UX] Missing shortcuts/commands → Add Commands + keyboard shortcuts → Power users love it, retention rises

---

## What I need from you to make this 10x more accurate
- 6–10 screenshots of Portfolio, Send, Receive, Activity, Security Center, WalletConnect request approval.
- Your target audience split (beginner vs DeFi vs power-opsec) and which is primary.
- Any metrics: onboarding completion, funded wallet rate, first send rate, crash logs.
- Current sidebar/nav structure screenshot (if any).
- Your distribution plan (sandboxed App Store vs notarized direct download).
- The duress “silent alert” implementation details (if real): endpoints, failure behavior, privacy.
- The exact list of chains/tokens you intend to support at launch.
