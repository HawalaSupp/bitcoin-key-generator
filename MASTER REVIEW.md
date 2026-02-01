# MASTER REVIEW.md
**Hawala Wallet — macOS Crypto Wallet**

---

## 0) Meta

**Generated from:**
1. `chatgpt 5.2 codex review.md`
2. `claude opus 4.5 review.md`
3. `gemini 3 pro review.md`
4. `gpot 5.2 review.md`

**Date:** February 1, 2026  
**Scope:** macOS crypto wallet app (Swift/SwiftUI + Rust core)  
**Review Goals:** Trust, safety, activation, retention, premium UX, macOS-native feel

---

## 1) Unified Executive Summary

### Overall Rating: **6.6/10**

### Subscores

| Category | Score | Notes |
|:---|:---:|:---|
| **Trust** | 5.5/10 | Undermined by fake data, disabled features, "Preview" banners |
| **Safety UX** | 7/10 | Good concepts (simulation, security check), but execution gaps (uint256 overflow, approval warnings) |
| **UX Clarity** | 6/10 | Mixed metaphors, modal spam, scattered features |
| **macOS-Native Feel** | 5/10 | Feels like iOS port—sheet-heavy, no context menus, no keyboard shortcuts |
| **Visual Polish** | 7/10 | Onboarding is premium; rest is inconsistent SwiftUI defaults |
| **Performance** | 5.5/10 | Heavy redraws from massive ContentView, spinners instead of skeletons |
| **Feature Completeness** | 7.5/10 | Impressive breadth (40+ chains, duress mode), but critical gaps (address book, NFTs, approvals manager) |

### This App Currently Feels Like
A finalized design mockup implemented by a genius engineer who ran out of time for architectural rigor—the bones are excellent but the flesh needs serious work.

### This App Should Feel Like
Fort Knox meets Finder—a security-first vault that feels as native as any Apple app.

---

### Top 10 Wins (Keep & Expand)

| # | Win | Why It Matters | Source |
|:--|:---|:---|:---|
| 1 | **Duress/Decoy Mode** | Genuine USP—few desktop wallets have this | All |
| 2 | **Transaction Preview + Security Check** | Shows intent to prevent blind signing | All |
| 3 | **Multi-chain Engineering** | 40+ chains with proper UTXO/EVM handling | All |
| 4 | **Broadcast Redundancy + Propagation Checks** | Solves "RPC accepted but never confirmed" pain | GPT |
| 5 | **Security Score Gamification** | Smart activation/retention design | All |
| 6 | **Practice Mode** | Reduces anxiety for first-time users | Gemini, GPT |
| 7 | **Dual Onboarding Paths** | Quick vs Guided is correct product strategy | All |
| 8 | **WalletConnect v2 Native** | Not a webview wrapper—proper implementation | All |
| 9 | **Fee Priority Selection** | Breaking down Slow/Standard/Fast is good | Codex, GPT |
| 10 | **Address Verification Flow** | Receive screen verification is a nice touch | Gemini |

---

### Top 10 Failures (Fix Immediately)

| # | Failure | Severity | Why It's Bad | Source |
|:--|:---|:---:|:---|:---|
| 1 | **ContentView.swift (11k+ lines)** | Critical | Unmaintainable god-file causing state bugs and jank | All |
| 2 | **Rust CLI Bridge (`Process()` calls)** | Critical | Hardcoded paths, sandbox-breaking, security nightmare | Gemini, GPT |
| 3 | **Hardcoded Prices** | High | Fake data destroys trust immediately | Gemini, GPT |
| 4 | **"Preview Feature" DEX in Production** | High | Screams "unfinished product" | All |
| 5 | **Disabled WalletConnect QR Scan** | High | Shipping broken buttons kills credibility | All |
| 6 | **No Address Book/Contacts** | High | Users re-type addresses = loss of funds risk | All |
| 7 | **Backup Verification Skippable** | High | Quick Setup creates false security confidence | All |
| 8 | **TransactionPreview UInt64 Overflow** | Critical | Misses unlimited approvals (MAX_UINT256) | GPT |
| 9 | **Sheet-on-Sheet Navigation** | Medium | iOS pattern, confusing on macOS | Gemini, GPT |
| 10 | **Monero View-Only Trap** | High | Users will fund and get stuck | Gemini |

---

### 5 Fastest High-ROI Improvements

| # | Task | Impact | Effort | Owner |
|:--|:---|:---|:---|:---|
| 1 | Remove/hide "Preview Feature" DEX | Trust restored | S | Both |
| 2 | Add MAX button to Send | UTXO usability | S | Eng |
| 3 | Add recent addresses to Send | Faster sending | S | Eng |
| 4 | Add privacy toggle (eye icon) on Home | Instant control | S | Eng |
| 5 | Replace hardcoded prices with real data or remove USD toggle | Trust | S | Eng |

---

### 5 Biggest Strategic Bets

| # | Bet | Impact | Effort | Notes |
|:--|:---|:---|:---|:---|
| 1 | Unify Rust integration on FFI (remove CLI bridge) | Reliability + Security | L | Ship blocker |
| 2 | Refactor ContentView into feature modules | Maintainability | XL | Technical debt elimination |
| 3 | Implement NavigationSplitView + Toolbar | macOS-native feel | L | Mac premium UX |
| 4 | Token Approval Manager | Security differentiator | L | Required for trust |
| 5 | Complete Social Recovery (Guardians) | Retention + differentiation | L | Modern self-custody |

---

## 2) Master Scorecard (Merged)

| Category | Score | What's Good | What's Bad | Key Fixes |
|:---|:---:|:---|:---|:---|
| **Onboarding** | 7/10 | Dual path (Quick/Guided), verification game, step indicator | Quick skips all education; iCloud backup during phrase screen; backup skippable | Force 1-word verification in Quick; delay iCloud to post-verification |
| **Portfolio/Home** | 6.5/10 | Large balance display, sparklines, bento grid | No privacy toggle visible; testnet mixed with mainnet; no "add token" button | Add eye icon; separate mainnet/testnet; add + button |
| **Send/Receive** | 5.5/10 | Chain selector, fee priority, QR, address validation | No address book; no recent addresses; no MAX; no share QR; hardcoded prices | Add contacts picker; add MAX; add share; use real prices |
| **Swap/Bridge** | 3/10 | Quote comparison concept exists | DEX is "Preview/simulated"—fake feature; Bridge missing entirely | Hide until real or ship fully |
| **dApps/WalletConnect** | 5/10 | Session management exists, native v2 | QR scan disabled; permissions unclear; no session expiry visible | Enable QR; show permissions + expiry; add "revoke all" |
| **Transaction Confirmations** | 7/10 | Security check view, threat assessment | UInt64 overflow misses unlimited approvals; no simulation summary visible | Use BigInt decoding; add state-change summary |
| **Scam Protection** | 6/10 | Concept of risk assessment exists | No clipboard hijack detection; no scam address database; no approval limits | Add clipboard monitoring; known scam list; default limited approvals |
| **Settings/Security Center** | 5/10 | Lots of security options exist | 2,700-line file; features scattered; no search; "Reset Wallet" too easy | Split into modules; create unified Security Center hub |
| **Performance** | 5.5/10 | Caching infrastructure exists | Heavy initial load; spinners everywhere; ContentView redraws on every state change | Lazy-load views; skeletons; isolate state |
| **macOS UI Quality** | 4.5/10 | Dark mode integration; sidebar concept correct | No context menus; no keyboard shortcuts; sheets instead of split view; iOS patterns | NavigationSplitView; Commands; context menus; toolbar |
| **Copywriting** | 6/10 | Some good warnings exist | Inconsistent tone; jargon unexplained; error messages too technical | Unified voice; microcopy rewrites; actionable errors |

---

## 3) Combined Problem Library (Deduped)

### 3.1 Onboarding

**[Critical] Quick Setup Skips All Security Education**
- **Symptoms:** User creates wallet without understanding recovery phrases
- **Why it matters:** Leads to fund loss and support burden
- **Where:** Quick onboarding path
- **Fix:** Force at least 1-word verification even in Quick mode
- **Expected result:** Users prove backup works before receiving funds
- **Effort:** S
- **Owner:** Eng
- **Source:** All reviews

**[High] iCloud Backup Offered During Phrase Screen**
- **Symptoms:** Decision paralysis during most critical step
- **Why it matters:** Drop-off or insecure storage choice
- **Where:** Recovery phrase display screen
- **Fix:** Move iCloud toggle to separate post-verification screen
- **Expected result:** Cleaner decision flow, higher completion
- **Effort:** S
- **Owner:** Eng
- **Source:** Codex, Claude

**[High] Backup Verification Can Be Skipped Without Consequence**
- **Symptoms:** User clicks "I've saved it" without actually saving
- **Why it matters:** Total fund loss when device fails
- **Where:** Backup verification step
- **Fix:** Allow deferral but enforce sending limits (<$100) + persistent banner + reminders
- **Expected result:** Users eventually verify or operate with limits
- **Effort:** M
- **Owner:** Both
- **Source:** All reviews

**[Medium] No Time Estimate Shown for Guided Setup**
- **Symptoms:** Users abandon because they don't know how long it takes
- **Why it matters:** Drop-off
- **Where:** Setup mode selection
- **Fix:** Show "This takes ~3 minutes"
- **Expected result:** Higher completion rate
- **Effort:** S
- **Owner:** Design
- **Source:** Claude

---

### 3.2 Navigation & Information Architecture

**[High] Sheet-on-Sheet Navigation Pattern**
- **Symptoms:** Closing sheets loses context; feels iOS-like
- **Why it matters:** Disorientation; not macOS-native
- **Where:** Throughout app (dozens of `showXSheet` booleans)
- **Fix:** Use `NavigationSplitView` (Sidebar → Content → Inspector); reserve sheets for wizards only
- **Expected result:** Mac-native feel; clearer mental model
- **Effort:** L
- **Owner:** Both
- **Source:** Gemini, GPT

**[High] Security Features Scattered Across App**
- **Symptoms:** Backup in Settings, Duress in Advanced, Score in Onboarding
- **Why it matters:** Broken mental model; low feature completion
- **Where:** Settings, onboarding, various sheets
- **Fix:** Create unified "Security Center" hub as sidebar item
- **Expected result:** Single destination for all security features
- **Effort:** M
- **Owner:** Both
- **Source:** GPT

**[Medium] No Keyboard Shortcuts**
- **Symptoms:** Power users can't navigate quickly
- **Why it matters:** macOS expectation; retention for pros
- **Where:** Entire app
- **Fix:** Implement `Commands` for Send (⌘N), Receive (⌘R), Search (⌘F), Settings (⌘,), Lock (⌘L)
- **Expected result:** Power user delight
- **Effort:** M
- **Owner:** Both
- **Source:** Gemini, GPT

**[Medium] No Right-Click Context Menus**
- **Symptoms:** Right-click on address/token/tx does nothing
- **Why it matters:** Fundamental macOS expectation
- **Where:** Token list, activity, addresses
- **Fix:** Add context menus: Copy / View on explorer / Label / Report scam
- **Expected result:** Feels like a native Mac app
- **Effort:** M
- **Owner:** Both
- **Source:** Gemini, GPT

---

### 3.3 Portfolio & Token Management

**[High] No Privacy Toggle Visible**
- **Symptoms:** Users must dig into Settings to hide balance
- **Why it matters:** Quick privacy control is expected
- **Where:** Portfolio/Home screen
- **Fix:** Add eye icon next to total balance
- **Expected result:** Instant privacy with one click
- **Effort:** S
- **Owner:** Eng
- **Source:** All reviews

**[High] No Spam Token Filtering**
- **Symptoms:** Users see malicious/dust tokens as legitimate
- **Why it matters:** Trust destruction; scam exposure
- **Where:** Token list
- **Fix:** Add spam detection + "Hidden/Spam" section with heuristics
- **Expected result:** Clean portfolio; scam prevention
- **Effort:** M
- **Owner:** Eng
- **Source:** All reviews

**[Medium] Testnet Assets Mixed with Mainnet**
- **Symptoms:** Confusion about real vs test funds
- **Why it matters:** Users may think test tokens are real
- **Where:** Portfolio when `showTestnets` enabled
- **Fix:** Separate "Mainnet" / "Testnet" sections or tabs
- **Expected result:** Clear separation
- **Effort:** S
- **Owner:** Eng
- **Source:** Codex, Claude

**[Medium] No "Add Token" Button Visible**
- **Symptoms:** Users can't find how to add custom tokens
- **Why it matters:** Feature discoverability
- **Where:** Token list
- **Fix:** Add floating "+" button
- **Expected result:** Easier token management
- **Effort:** S
- **Owner:** Eng
- **Source:** Claude

---

### 3.4 Send / Receive

**[Critical] No Address Book / Contacts**
- **Symptoms:** Users re-type addresses every time
- **Why it matters:** Massive friction; typo = loss of funds
- **Where:** Send flow
- **Fix:** Add ContactsStore with recent addresses + saved contacts + autocomplete
- **Expected result:** Faster, safer sending
- **Effort:** M
- **Owner:** Eng
- **Source:** All reviews

**[High] No MAX Button**
- **Symptoms:** Users can't send entire balance easily
- **Why it matters:** Required for UTXO sweep; common expectation
- **Where:** Send amount input
- **Fix:** Add MAX button that calculates `balance - estimatedMaxFee`
- **Expected result:** Proper UTXO handling
- **Effort:** S
- **Owner:** Eng
- **Source:** All reviews

**[High] No Recent Addresses**
- **Symptoms:** Repeat payments require re-entry
- **Why it matters:** Friction; error-prone
- **Where:** Send address input
- **Fix:** Store last 10 addresses per chain; show as picker
- **Expected result:** Faster repeat sends
- **Effort:** S
- **Owner:** Eng
- **Source:** All reviews

**[High] Hardcoded Prices in Receive**
- **Symptoms:** USD conversion shows fake data (btcPrice = 42500)
- **Why it matters:** Destroys trust immediately
- **Where:** ReceiveViewModern
- **Fix:** Connect to PriceService or remove USD toggle until real
- **Expected result:** Real or no financial data
- **Effort:** S
- **Owner:** Eng
- **Source:** Gemini, GPT

**[Medium] No Share QR Button**
- **Symptoms:** Users can't export/share QR image
- **Why it matters:** Common use case for payment requests
- **Where:** Receive view
- **Fix:** Add macOS share sheet for QR export
- **Expected result:** Better usability
- **Effort:** S
- **Owner:** Eng
- **Source:** Codex, Claude

**[Medium] Fee Impact Not Obvious**
- **Symptoms:** Users don't understand fee as % of transaction
- **Why it matters:** Surprises on small transactions
- **Where:** Send confirmation
- **Fix:** Show fee as % above confirm button
- **Expected result:** Informed decisions
- **Effort:** S
- **Owner:** Eng
- **Source:** Codex

---

### 3.5 Swap / Bridge

**[Critical] DEX Shows "Preview Feature / Simulated"**
- **Symptoms:** Core nav item is a mockup
- **Why it matters:** Signals unfinished product; destroys trust
- **Where:** DEXAggregatorView
- **Fix:** Hide behind dev flag OR finish real execution
- **Expected result:** No fake features in production
- **Effort:** S (hide) / L (finish)
- **Owner:** Both
- **Source:** All reviews

**[High] Bridge Missing Entirely**
- **Symptoms:** Feature gap for cross-chain users
- **Why it matters:** Competitive disadvantage
- **Where:** Navigation
- **Fix:** Add minimal bridge view OR remove from nav
- **Expected result:** Clarity about available features
- **Effort:** L (add) / S (remove)
- **Owner:** Both
- **Source:** Codex, Claude

**[High] No Slippage / Price Impact Warnings**
- **Symptoms:** Users get rekt on swaps without understanding
- **Why it matters:** Financial loss; blame on wallet
- **Where:** Swap confirmation
- **Fix:** Show price impact %; warn if slippage > 2%; block > 5% without explicit opt-in
- **Expected result:** Informed swap decisions
- **Effort:** M
- **Owner:** Both
- **Source:** All reviews

---

### 3.6 Transaction Review & Confirmations

**[Critical] UInt64 Overflow in Transaction Decoding**
- **Symptoms:** Unlimited approvals (MAX_UINT256) decoded incorrectly
- **Why it matters:** Misses #1 wallet drain vector
- **Where:** TransactionPreviewService
- **Fix:** Use BigInt/Decimal for uint256 decoding
- **Expected result:** Correct unlimited approval detection
- **Effort:** M
- **Owner:** Eng
- **Source:** GPT

**[High] No "State Change" Summary**
- **Symptoms:** Users don't understand what will change
- **Why it matters:** Blind signing despite having preview
- **Where:** Transaction confirmation
- **Fix:** Add "You give: X / You get: Y / You allow: Z" summary
- **Expected result:** Human-readable transaction impact
- **Effort:** M
- **Owner:** Both
- **Source:** GPT

**[High] Approval Warnings Not Clear Enough**
- **Symptoms:** ERC-20 approvals don't scream danger
- **Why it matters:** Wallet drain attacks
- **Where:** Approval confirmation
- **Fix:** Add prominent warning card: "This app can spend ALL your [TOKEN]" with "Approve limited amount" option
- **Expected result:** Users understand risk; can limit exposure
- **Effort:** M
- **Owner:** Both
- **Source:** All reviews

**[Medium] No Simulation Button**
- **Symptoms:** Simulation happens automatically but isn't surfaced
- **Why it matters:** Users can't trigger on-demand
- **Where:** Transaction review
- **Fix:** Add "Simulate" button showing asset changes preview
- **Expected result:** Transparency; user control
- **Effort:** M
- **Owner:** Eng
- **Source:** Claude

---

### 3.7 Scam / Risk / Phishing Defense

**[High] No Clipboard Hijack Detection**
- **Symptoms:** Attackers replace copied addresses
- **Why it matters:** Direct fund theft
- **Where:** Send flow paste
- **Fix:** Monitor clipboard timing; warn if changed <1s after copy
- **Expected result:** "Clipboard modified by another app" warning
- **Effort:** M
- **Owner:** Eng
- **Source:** All reviews

**[High] No Scam Address Database**
- **Symptoms:** Known scam addresses not flagged
- **Why it matters:** Preventable losses
- **Where:** Address validation
- **Fix:** Integrate known scam address list; warn or block
- **Expected result:** Scam addresses flagged
- **Effort:** M
- **Owner:** Eng
- **Source:** Claude

**[High] Address Poisoning Not Detected**
- **Symptoms:** Prefix/suffix match but different address
- **Why it matters:** Sophisticated attack vector
- **Where:** Address input
- **Fix:** Compare to recent addresses; highlight differences
- **Expected result:** "Looks similar but differs—check middle characters!"
- **Effort:** M
- **Owner:** Eng
- **Source:** Gemini, GPT

**[Medium] Dust Tokens Visible**
- **Symptoms:** Spam tokens with <$0.01 value shown
- **Why it matters:** Scam vectors; UI pollution
- **Where:** Token list
- **Fix:** Hide by default; show "X hidden tokens"
- **Expected result:** Clean portfolio
- **Effort:** S
- **Owner:** Eng
- **Source:** All reviews

---

### 3.8 dApps / WalletConnect / Sessions

**[Critical] QR Scan Disabled**
- **Symptoms:** "Scan QR" button is grayed out / non-functional
- **Why it matters:** Core WC feature broken; signals incomplete product
- **Where:** WalletConnectView
- **Fix:** Implement camera scanning OR remove button
- **Expected result:** No broken buttons
- **Effort:** M
- **Owner:** Eng
- **Source:** All reviews

**[High] Permissions Not Clear**
- **Symptoms:** Users don't understand what they're approving
- **Why it matters:** Over-permissioned sessions
- **Where:** Connection proposal
- **Fix:** Show chains, methods, and expiration explicitly
- **Expected result:** Informed connection decisions
- **Effort:** M
- **Owner:** Both
- **Source:** All reviews

**[High] No Session Expiry Visible**
- **Symptoms:** Users don't know when connections expire
- **Why it matters:** Long-lived risky sessions
- **Where:** Sessions list
- **Fix:** Show expiry date; add TTL management
- **Expected result:** Clearer session lifecycle
- **Effort:** S
- **Owner:** Eng
- **Source:** Claude

**[Medium] No "Revoke All" Button**
- **Symptoms:** Can't quickly disconnect all dApps
- **Why it matters:** Emergency response for compromised sessions
- **Where:** Sessions list
- **Fix:** Add "Disconnect All" button with confirmation
- **Expected result:** Quick security action
- **Effort:** S
- **Owner:** Eng
- **Source:** Claude

**[High] "Auto-accept Trusted dApps" Toggle Exists**
- **Symptoms:** Security anti-pattern enabled by default
- **Why it matters:** Amplifies phishing risk
- **Where:** Settings
- **Fix:** Remove this feature entirely
- **Expected result:** Always require approval
- **Effort:** S
- **Owner:** Eng
- **Source:** Claude

---

### 3.9 NFTs

**[Medium] NFT Gallery Missing**
- **Symptoms:** No way to view owned NFTs
- **Why it matters:** Table stakes feature in 2026
- **Where:** Navigation
- **Fix:** Add NFT gallery with grid display + hide/report options
- **Expected result:** Feature parity with competitors
- **Effort:** M
- **Owner:** Eng
- **Source:** Codex, Claude

**[Medium] Spam NFT Risk**
- **Symptoms:** Malicious NFTs with tracker images
- **Why it matters:** Privacy and scam exposure
- **Where:** NFT display
- **Fix:** Don't auto-load remote images; use "Untrusted media" placeholder
- **Expected result:** Safe NFT viewing
- **Effort:** S
- **Owner:** Eng
- **Source:** GPT

---

### 3.10 Settings / Security Center

**[Critical] SettingsView is 2,700+ Lines**
- **Symptoms:** Unmaintainable god-file
- **Why it matters:** Bugs; slow development
- **Where:** SettingsView.swift
- **Fix:** Split into feature modules (Security, Privacy, Developer, About)
- **Expected result:** Maintainable codebase
- **Effort:** L
- **Owner:** Eng
- **Source:** Codex, Claude

**[High] No Settings Search**
- **Symptoms:** Users can't find settings
- **Why it matters:** Frustration
- **Where:** Settings
- **Fix:** Add search bar with filter
- **Expected result:** Quick setting discovery
- **Effort:** M
- **Owner:** Eng
- **Source:** Codex

**[High] "Reset Wallet" Too Easy to Trigger**
- **Symptoms:** Just a confirm alert—no friction
- **Why it matters:** Accidental fund loss
- **Where:** Settings
- **Fix:** Require type-to-confirm ("delete my wallet")
- **Expected result:** Prevented accidents
- **Effort:** S
- **Owner:** Eng
- **Source:** Claude

**[Medium] No "Last Backup" Indicator**
- **Symptoms:** Users don't know if they're protected
- **Why it matters:** False security confidence
- **Where:** Settings / Security
- **Fix:** Show "Last verified backup: X days ago" badge
- **Expected result:** Backup awareness
- **Effort:** S
- **Owner:** Eng
- **Source:** Codex, Claude

---

### 3.11 Performance / Reliability

**[Critical] ContentView.swift is 11,000+ Lines**
- **Symptoms:** UI jank; random state bugs
- **Why it matters:** Users interpret bugs as "wallet stealing funds"
- **Where:** ContentView.swift
- **Fix:** Refactor into feature modules with isolated state
- **Expected result:** Stable, maintainable app
- **Effort:** XL
- **Owner:** Eng
- **Source:** All reviews

**[High] Spinners Everywhere**
- **Symptoms:** Generic ProgressView instead of branded loading
- **Why it matters:** Perceived slowness
- **Where:** Portfolio, history, send
- **Fix:** Use skeleton loading with shimmer animation
- **Expected result:** Faster perceived performance
- **Effort:** M
- **Owner:** Both
- **Source:** All reviews

**[High] Heavy Initial Load**
- **Symptoms:** App feels slow on launch
- **Why it matters:** First impression
- **Where:** App launch
- **Fix:** Lazy-load secondary views; defer heavy services
- **Expected result:** Faster time-to-interactive
- **Effort:** M
- **Owner:** Eng
- **Source:** Codex

**[Medium] No "Stale Data" Indicator**
- **Symptoms:** Users trust displayed balances without knowing freshness
- **Why it matters:** Acting on stale data
- **Where:** Portfolio, prices
- **Fix:** Add "Updated Xs ago" badge; show stale warning after threshold
- **Expected result:** Users know data freshness
- **Effort:** S
- **Owner:** Both
- **Source:** GPT

---

### 3.12 macOS-Native UX (HIG Compliance)

**[High] No Standard Toolbar**
- **Symptoms:** Custom in-view headers with buttons
- **Why it matters:** Not macOS-native
- **Where:** Most views
- **Fix:** Use `.toolbar { }` with standard items
- **Expected result:** Native Mac feel
- **Effort:** M
- **Owner:** Both
- **Source:** Gemini, GPT

**[High] No Drag & Drop**
- **Symptoms:** Can't drag address/QR out; can't drop URI in
- **Why it matters:** macOS power feature missing
- **Where:** Receive, Send
- **Fix:** Implement drag providers and drop delegates
- **Expected result:** Pro-level Mac interaction
- **Effort:** M
- **Owner:** Eng
- **Source:** GPT

**[Medium] Toggle Switches Instead of Checkboxes**
- **Symptoms:** iOS-style toggles used
- **Why it matters:** Not native to macOS
- **Where:** Settings
- **Fix:** Use checkboxes where appropriate
- **Expected result:** Mac-native controls
- **Effort:** S
- **Owner:** Both
- **Source:** Gemini

**[Medium] In-Content Close Buttons**
- **Symptoms:** Close buttons inside content area, not window chrome
- **Why it matters:** iOS pattern
- **Where:** Sheets, overlays
- **Fix:** Use standard sheet chrome or toolbar dismiss
- **Expected result:** Native window behavior
- **Effort:** S
- **Owner:** Both
- **Source:** Gemini, GPT

---

### 3.13 Visual Design / Design System

**[High] At Least 5 Different Button Styles**
- **Symptoms:** OnboardingPrimaryButton, HawalaPrimaryButton, .bordered, .borderedProminent, custom
- **Why it matters:** Frankenstein UI; unprofessional
- **Where:** Entire app
- **Fix:** Create single `HawalaButton` with variants (primary, secondary, destructive, ghost)
- **Expected result:** Visual consistency
- **Effort:** M
- **Owner:** Both
- **Source:** All reviews

**[High] System Backgrounds Used in Feature Views**
- **Symptoms:** `Color(nsColor: .windowBackgroundColor)` instead of theme colors
- **Why it matters:** Breaks visual cohesion
- **Where:** DEX, Staking, WalletConnect, Buy
- **Fix:** Use HawalaTheme.Colors everywhere
- **Expected result:** Unified aesthetic
- **Effort:** M
- **Owner:** Both
- **Source:** Claude

**[Medium] Inconsistent Icon Fill Styles**
- **Symptoms:** Mix of filled and outlined SF Symbols
- **Why it matters:** Visual noise
- **Where:** Throughout
- **Fix:** Standardize on one icon style
- **Expected result:** Polish
- **Effort:** S
- **Owner:** Design
- **Source:** Gemini

**[Medium] No Chain Logo Icons**
- **Symptoms:** Chain icons are SF Symbols, not actual logos
- **Where:** Chain selectors
- **Fix:** Use real SVG chain logos
- **Expected result:** Recognition; trust
- **Effort:** S
- **Owner:** Design
- **Source:** Claude

---

### 3.14 Copywriting / Microcopy

**[High] Jargon Unexplained**
- **Symptoms:** "MEV Protection", "Gas Sponsorship", "Stealth Addresses" without explanation
- **Why it matters:** Confusion; fear
- **Where:** Settings, transaction review
- **Fix:** Add tooltips or inline explanations
- **Expected result:** User understanding
- **Effort:** S
- **Owner:** Design
- **Source:** Claude

**[High] Error Messages Too Technical**
- **Symptoms:** "FFI returned null", "Invalid input string"
- **Why it matters:** User panic; support burden
- **Where:** Error states
- **Fix:** Map all errors to user-facing messages with retry actions
- **Expected result:** Actionable errors
- **Effort:** M
- **Owner:** Both
- **Source:** GPT

**[Medium] Inconsistent Tone**
- **Symptoms:** Onboarding = premium; Settings = cold/technical
- **Why it matters:** Jarring experience
- **Where:** Across app
- **Fix:** Establish voice guidelines; apply consistently
- **Expected result:** Unified brand feel
- **Effort:** M
- **Owner:** Design
- **Source:** Claude

---

### 3.15 Architecture (Swift + Rust Boundaries)

**[Critical] Dual Rust Integration Paths**
- **Symptoms:** RustService (FFI) AND RustCLIBridge (Process execution) both exist
- **Why it matters:** Reliability nightmare; sandbox-breaking; hardcoded paths; security hole
- **Where:** RustCLIBridge.swift
- **Fix:** Remove CLI path entirely; unify on FFI
- **Expected result:** Signing works reliably in distribution
- **Effort:** L
- **Owner:** Eng
- **Source:** Gemini, GPT

**[Critical] Hardcoded Absolute Paths**
- **Symptoms:** RustCLIBridge uses `/Users/x/Desktop/888/rust-app/target/...`
- **Why it matters:** Crashes on any other machine
- **Where:** RustCLIBridge.swift
- **Fix:** Remove or use Bundle.main paths
- **Expected result:** App works everywhere
- **Effort:** S
- **Owner:** Eng
- **Source:** Gemini, GPT

**[High] Swift/Rust Responsibility Blur**
- **Symptoms:** Logic scattered; unclear who owns what
- **Why it matters:** Bugs; maintenance difficulty
- **Where:** Architecture
- **Fix:** Clear boundary: Rust = signing, derivation, validation; Swift = UI, networking, state
- **Expected result:** Clean architecture
- **Effort:** M
- **Owner:** Eng
- **Source:** All reviews

---

### 3.16 QA / Bug Magnet List

**Onboarding Bugs:**
1. Import with extra spaces between words
2. Import with capital letters (should normalize)
3. Import with wrong checksum (should highlight wrong word)
4. Back button during key generation
5. Kill app during key generation
6. Passcode/confirm mismatch

**Send/Receive Bugs:**
7. Send max balance ETH (must account for gas)
8. Send max balance BTC (must account for UTXO dust)
9. Paste address with leading/trailing whitespace
10. QR scan garbage data
11. Fee slider at 0
12. Network disconnect during broadcast
13. Wrong decimals display for tokens

**WalletConnect Bugs:**
14. Request arrives while locked
15. Request flood (rate limiting)
16. Chain switch request handling
17. Session persistence corruption

**Duress Mode Bugs:**
18. Real history leaking in duress mode
19. Duress PIN same as real PIN
20. Mode indicator visibility

**Performance Bugs:**
21. 1000+ transactions in history
22. 500+ tokens in portfolio
23. Rapid chain switching
24. Memory leak after 100 nav pushes

**Edge Cases:**
25. ENS resolves to different address than expected
26. Address poisoning (prefix/suffix match)
27. Clipboard hijack between copy and paste
28. Quote expires during swap confirmation
29. Bridge status desync
30. RPC outage mid-transaction

---

## 4) Conflicts & Decision Log

### Conflict: FFI vs CLI for Rust Integration

**Claude says:** Move all crypto operations to Rust; use async/await with proper cancellation.
**Codex says:** Rust should do signing/validation; Swift handles networking.
**Gemini says:** Must move away from RustCLIBridge; use FFI only.
**GPT says:** Remove CLI path entirely; it's a security and distribution nightmare.

**Best Decision:** Remove RustCLIBridge (Process-based execution) completely. Unify on FFI.

**Why:** All reviews agree. CLI invocation with hardcoded paths is:
- A security hole (external binary execution)
- A distribution blocker (won't work on other machines)
- A performance bottleneck (50-100ms overhead per call)
- A sandbox violation (App Store rejection guaranteed)

**Implementation:**
1. Audit all RustCLIBridge call sites
2. Replace with RustService FFI equivalents
3. Delete RustCLIBridge.swift
4. Update build pipeline to embed Rust as static library

---

### Conflict: Quick Onboarding Security Level

**Claude says:** Force at least 1 verification word in Quick mode.
**Codex says:** Add "Verify 1 word" view in Quick flow.
**Gemini says:** In Quick mode, allow skip but set `backupVerified = false` and enforce limits.
**GPT says:** Allow deferral but apply sending limits until verified.

**Best Decision:** Hybrid approach—force 2-word verification in Quick mode, but allow "Do later" that enforces strict limits.

**Why:** Pure skip is dangerous (user never learns), but blocking completely hurts activation. Limits (e.g., no sends >$100 until verified) provide safety net.

**Implementation:**
1. Quick mode shows 2-word verification
2. "Do later" option available but clearly marked
3. If skipped: persistent banner + sending limit + Security Score penalty
4. Reminder after first deposit

---

### Conflict: macOS Navigation Pattern

**All reviews agree:** Use NavigationSplitView, not sheet-based navigation.

**No conflict—unanimous recommendation.** Sheets should be reserved for:
- Onboarding wizards
- Transaction confirmations
- Modal prompts

Everything else should use sidebar + content + optional inspector.

---

## 5) Best-in-Class macOS Wallet Blueprint

### 5.1 Ideal Quick Onboarding (Power User, <60s)

```
1. Welcome
   - Hero: "Hawala. Private, secure, native."
   - CTAs: [Create Wallet (60s)] [Import Existing]

2. Security Baseline (1 screen)
   - Toggle: Unlock with Touch ID ✓ (recommended)
   - Toggle: Require passcode on launch ✓ (recommended)
   - Link: "Advanced security setup →"

3. Generate Wallet
   - Animation: "Generating secure entropy..."
   - Result: "Wallet created. Backup required for >$100."

4. Quick Verification
   - Prompt: "Verify 2 words to secure your backup"
   - Input: Word #4 and Word #17 (random)
   - Alternative: "Do later (limits apply)"

5. Done
   - Security Score: "60% — verify backup to unlock full features"
   - CTA: [Start Using Wallet]
```

**Time:** 45-60 seconds
**Safety:** 2-word verification ensures minimal backup proof

---

### 5.2 Ideal Advanced Onboarding (Guided, Safest)

```
1. Setup Goal
   - Options: "Balanced" / "Maximum Security"

2. Storage Model (1 screen)
   - Diagram: Seed → Keychain (local) → Optional iCloud
   - Explainer: "Your seed never leaves this Mac unless you enable iCloud."

3. Generate Seed
   - Display: 24 words with "Hold to reveal" (biometric gated)
   - Warning: "Write on paper. Never screenshot."

4. Backup Method
   - Options: Paper / Password Manager / iCloud Keychain
   - If iCloud: clear tradeoff explanation

5. Verification
   - Challenge: 3 random words (adaptive difficulty)
   - Fail handling: "Try again" with hints after 2 failures

6. Guardian Setup (Optional)
   - Explainer: "Add 2-3 trusted contacts for social recovery"
   - Option: "Set up later"

7. Duress Setup (Optional, Advanced Only)
   - Explainer: "Create a decoy wallet that opens with a separate PIN"
   - Disclaimer: "No system can guarantee emergency alerts"

8. Security Score Summary
   - Visual: Score breakdown with "What this protects against" links
```

**Time:** 3-5 minutes
**Safety:** Full backup verification + optional social recovery

---

### 5.3 Ideal Transaction Confirmation Screen (macOS Layout)

```
┌──────────────────────────────────────────────────────────┐
│ Review Transaction                          [Risk: Low]  │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  ┌─────────────────────┐   ┌──────────────────────────┐  │
│  │ SUMMARY             │   │ SAFETY CHECKS            │  │
│  │                     │   │                          │  │
│  │ Action: Send        │   │ [✓] Address format valid │  │
│  │ Amount: 1.0 ETH     │   │ [!] First time recipient │  │
│  │ Network: Ethereum   │   │ [✓] Balance sufficient   │  │
│  │ To: vitalik.eth     │   │ [✓] Contract verified    │  │
│  │     0x1234...5678   │   │                          │  │
│  │                     │   │ SIMULATION               │  │
│  │ Fee: $4.50 (0.3%)   │   │ You send: 1.0 ETH        │  │
│  │     Max: $6.00      │   │ You receive: nothing     │  │
│  │                     │   │ Approvals: none          │  │
│  └─────────────────────┘   └──────────────────────────┘  │
│                                                          │
│  [Details ▼]  Contract call data...                      │
│                                                          │
├──────────────────────────────────────────────────────────┤
│      [Cancel]                    [Confirm with Touch ID] │
└──────────────────────────────────────────────────────────┘
```

**Warning Severity Colors:**
- Info (Gray): "First time interaction"
- Warn (Orange): "High fee (>10% of value)"
- Block (Red): "Malicious address—requires type-to-confirm"

---

### 5.4 Ideal Security Center

**Sidebar item: "Security"**

```
┌────────────────────────────────────────────────────┐
│ Security Center                   Score: 85/100   │
├────────────────────────────────────────────────────┤
│                                                    │
│ PROTECTION STATUS                                  │
│ ┌────────────────────────────────────────────────┐ │
│ │ [✓] Backup verified              Feb 1, 2026  │ │
│ │ [✓] Passcode enabled                          │ │
│ │ [✓] Touch ID active                           │ │
│ │ [!] Duress mode not configured   [Set up →]   │ │
│ │ [✓] Auto-lock: 5 minutes                      │ │
│ └────────────────────────────────────────────────┘ │
│                                                    │
│ CONNECTED APPS                                     │
│ ┌────────────────────────────────────────────────┐ │
│ │ 3 active sessions             [Manage →]       │ │
│ │ Last connection: Uniswap (2h ago)              │ │
│ └────────────────────────────────────────────────┘ │
│                                                    │
│ TOKEN APPROVALS                                    │
│ ┌────────────────────────────────────────────────┐ │
│ │ 5 active approvals            [Review →]       │ │
│ │ ⚠️ 2 unlimited approvals                        │ │
│ └────────────────────────────────────────────────┘ │
│                                                    │
│ ACTIONS                                            │
│ [View Seed Phrase]  [Export Backup]  [Lock Now]    │
│                                                    │
└────────────────────────────────────────────────────┘
```

---

### 5.5 Ideal Portfolio + Token Spam Handling

```
┌────────────────────────────────────────────────────┐
│ Portfolio                    Updated 5s ago   👁   │
├────────────────────────────────────────────────────┤
│                                                    │
│ TOTAL VALUE                                        │
│ $12,345.67                         +2.3% (24h)    │
│                                                    │
│ ASSETS                              [+ Add Token] │
│ ┌──────────────────────────────────────────────┐  │
│ │ Token      Balance      Value       24h      │  │
│ ├──────────────────────────────────────────────┤  │
│ │ ETH        2.5          $4,500      +1.2%    │  │
│ │ BTC        0.15         $6,000      +3.1%    │  │
│ │ USDC       1,845        $1,845      0.0%     │  │
│ └──────────────────────────────────────────────┘  │
│                                                    │
│ [3 hidden tokens]  [Show spam →]                  │
│                                                    │
└────────────────────────────────────────────────────┘

Right-click context menu on token row:
- Copy address
- View on explorer
- Hide token
- Mark as spam
- Add to watchlist
```

---

### 5.6 Ideal dApp Connection Flow

```
┌────────────────────────────────────────────────────┐
│ Connection Request                                 │
├────────────────────────────────────────────────────┤
│                                                    │
│ [Uniswap Logo]                                     │
│ app.uniswap.org                                    │
│                                                    │
│ REQUESTED PERMISSIONS                              │
│ ┌────────────────────────────────────────────────┐ │
│ │ [✓] View your wallet address                   │ │
│ │ [✓] Request transaction signatures             │ │
│ │ [ ] Sign messages                              │ │
│ └────────────────────────────────────────────────┘ │
│                                                    │
│ CHAINS                                             │
│ Ethereum Mainnet, Arbitrum, Polygon                │
│                                                    │
│ SESSION EXPIRY                                     │
│ 7 days (until Feb 8, 2026)                         │
│                                                    │
│ ⚠️ This app will be able to request transactions.  │
│    You'll always be asked to confirm.              │
│                                                    │
├────────────────────────────────────────────────────┤
│    [Reject]                           [Connect]    │
└────────────────────────────────────────────────────┘
```

---

## 6) Microcopy Master Pack (Merged + Clean)

### Onboarding Copy

| Context | Recommended Copy | Notes |
|:---|:---|:---|
| Welcome headline | "Hawala. Private, secure, native." | Short, premium |
| Create wallet CTA | "Create Wallet (60s)" | Sets expectation |
| Import CTA | "Import Existing Wallet" | Clear action |
| Self-custody explainer | "You control your keys. No company can recover your funds." | One sentence |
| Backup header | "Your Secret Recovery Phrase" | Standard term |
| Backup warning | "Write these 24 words on paper. Never screenshot. Never share." | Clear actions |
| Verification prompt | "Verify your backup by entering 2 words" | Simple instruction |
| Skip warning | "Skip for now (sending limits apply)" | Consequence visible |
| Security score | "Security Score: 60% — complete backup to unlock full features" | Gamification |

### Transaction Copy

| Context | Recommended Copy | Notes |
|:---|:---|:---|
| Send header | "Send [Token] on [Network]" | Clear action |
| Review header | "Review Transaction" | Standard |
| Broadcasting | "Broadcasting to Ethereum..." | Technical accuracy |
| Pending | "Waiting for confirmation (1 of 12 needed)" | Progress indicator |
| Success | "Transaction confirmed" | Simple |
| Failed | "Transaction rejected by network. Reason: [X]" | Actionable |

### Warning Copy

| Context | Recommended Copy | Notes |
|:---|:---|:---|
| Unlimited approval | "This app can spend ALL your [TOKEN]. Approve a limited amount instead?" | Highlight risk, offer alternative |
| Unknown contract | "Unknown contract. We can't verify what this will do." | Honest uncertainty |
| High slippage | "Slippage is 8%. You may receive much less than expected." | Quantified risk |
| First-time recipient | "First time sending to this address. Double-check it's correct." | Gentle warning |
| Clipboard warning | "Clipboard was modified by another app just now." | Specific detection |
| Scam address | "This address has been reported as a scam. Do not proceed." | Block-level |

### Error Copy

| Context | Recommended Copy | Notes |
|:---|:---|:---|
| RPC timeout | "Network timeout. Trying backup provider..." | Shows recovery |
| Insufficient funds | "Insufficient funds including fees. Reduce amount or choose lower fee." | Actionable |
| Invalid address | "This address doesn't match the selected network." | Specific reason |
| Generic error | "Something went wrong. Please try again." | Fallback |

### Empty State Copy

| Context | Recommended Copy | Notes |
|:---|:---|:---|
| No transactions | "No transactions yet. Send or receive to get started." | CTA included |
| No tokens | "No tokens found. Add a custom token or receive funds." | Options given |
| No connections | "No connected apps. Scan a WalletConnect QR to connect." | Next step |

---

## 7) Edge Cases & Failure Handling (Merged — 60 Items)

| # | Scenario | Risk | Detection | UX Response | Technical Note |
|:--|:---|:---|:---|:---|:---|
| 1 | User pastes address with whitespace | Invalid send | Trim on paste | Auto-trim; no error | String.trimmingCharacters |
| 2 | User types extra space in seed phrase | Import fails | Word count check | Split by any whitespace | Use regex split |
| 3 | User capitalizes seed words | Import fails | Case check | Normalize to lowercase | .lowercased() |
| 4 | Seed checksum invalid | Wrong word | BIP39 validation | Highlight wrong word immediately | Rust validation |
| 5 | Back button during key generation | Inconsistent state | State machine | Cancel generation; restart | Task cancellation |
| 6 | App killed during generation | Lost keys | Persistence check | Resume or restart on launch | Transaction journal |
| 7 | Biometrics fail after screen lock | Can't unlock | LAError handling | Fall back to passcode | LocalAuthentication |
| 8 | User sends max ETH | Insufficient for gas | Balance check | Calculate max = balance - maxFee | Pre-estimation |
| 9 | User sends max BTC | UTXO dust left | Dust calculation | Account for dust threshold | UTXO selection |
| 10 | ENS resolves differently than expected | Wrong recipient | Show resolved address | Display resolved + "pin" option | Cache resolution |
| 11 | ENS resolution fails | Can't send | Network error | Show error; allow retry | Timeout handling |
| 12 | Clipboard hijacked | Funds stolen | Timing detection | Warn if clipboard changed <1s | Pasteboard monitoring |
| 13 | Address poisoning | Funds stolen | History comparison | Highlight differences from known addresses | Levenshtein or prefix/suffix |
| 14 | QR contains malicious data | Various | Validation | Reject non-standard formats | Strict parsing |
| 15 | Fee slider at 0 | Stuck tx | Validation | Enforce minimum fee | Floor value |
| 16 | Network disconnect during broadcast | Unknown state | Connection check | Show "connection lost"; retry on reconnect | Reachability |
| 17 | RPC accepts but explorer doesn't see | Confusion | Propagation check | Show "propagating..." with retry | Multi-RPC query |
| 18 | Transaction stuck pending | User panic | Age check | Show "Speed Up" (RBF) option | Replace-by-fee |
| 19 | Nonce mismatch | Tx fails | Nonce tracking | Auto-manage nonce with retry | Nonce manager |
| 20 | Duplicate transaction broadcast | Double spend attempt | Idempotency | Block duplicate within window | Hash tracking |
| 21 | Swap quote expires | Failed trade | Timestamp check | Countdown timer; auto-refresh | TTL validation |
| 22 | Slippage exceeded | User gets less | Post-tx check | Warn pre-sign; show actual after | Simulation |
| 23 | Bridge status desync | User confusion | Polling | Show source of truth with refresh | Canonical status API |
| 24 | Wrong chain deposit | Lost funds | Address analysis | Network warning on receive | Chain detection |
| 25 | Token with fake symbol | Scam | Contract check | Show "unverified" badge | Token list |
| 26 | Dust token attack | Portfolio spam | Value threshold | Hide by default | Configurable threshold |
| 27 | NFT with tracker image | Privacy leak | Remote load | Placeholder; click to load | Proxy or block |
| 28 | Malicious dApp request flood | DoS | Rate detection | Rate limit; batch | Request queue |
| 29 | WalletConnect request while locked | Security | Lock state check | Queue request; unlock first | Pending queue |
| 30 | Session persistence corrupted | App crash | Decode failure | Reset sessions; re-auth | Fallback decode |
| 31 | Rust FFI returns invalid JSON | Crash | Parse failure | Fail safely with error UI | strict validation |
| 32 | Rust FFI returns null | Crash | Null check | Show "Engine error" with restart | Guard |
| 33 | Price feed returns 0 | Wrong display | Value check | Hide price or show "unavailable" | Validation |
| 34 | Price feed mismatch vs balance source | Confusion | Source tracking | Show "price source" badge | Tooltip |
| 35 | Balance API returns null | Shows $0 | Null check | Show cached + "stale" | Cache layer |
| 36 | RPC outage | App unusable | Health check | Auto-failover + status banner | Provider rotation |
| 37 | Gas limit too low | Tx fails | Estimation | Simulation must block | Pre-check |
| 38 | Contract decode fails | Blind sign | Decoder error | Show "Unknown call" + opt-in | Fallback UI |
| 39 | 1000+ transactions in history | Performance | Count check | Pagination + virtualization | LazyVStack |
| 40 | 500+ tokens in portfolio | Performance | Count check | Virtualization + spam filter | LazyVStack |
| 41 | Rapid chain switching | State bugs | Debounce | Debounce selection; preserve drafts | Timer |
| 42 | Memory leak after 100 nav pushes | Crash | Profiling | Use proper ownership; avoid captures | Instruments |
| 43 | Keychain access prompt at bad time | UX break | Timing | Defer access to action moment | Lazy access |
| 44 | Duress mode leaks real data | Security failure | State isolation | Strict mode checks | Data segregation |
| 45 | Decoy wallet shows real balance | Security failure | Mode check | Separate data stores | Isolation test |
| 46 | User sets duress PIN same as real | No protection | Comparison | Block same PIN | Validation |
| 47 | Wordlist language mismatch | Import fails | Language detection | Detect and prompt | Multi-wordlist |
| 48 | Derivation path mismatch | Empty wallet | Path scan | Scan common paths; show found funds | Multi-path |
| 49 | User force quits during backup display | Not backed up | State check | Check flag on resume; prompt | Persistence |
| 50 | iCloud restore on new device | Needs re-auth | Sync check | Re-authenticate biometrics | Local auth |
| 51 | Screen recording during seed display | Security | API check | Detect and blur | captureState |
| 52 | Fee estimator returns extreme value | Overpay | Range check | Clamp + warning | Min/max bounds |
| 53 | User sends to contract without data | Funds stuck | Address type check | Warn about contract | isContract |
| 54 | User approves unlimited to unknown | Drain risk | Amount check | Require limited unless explicit | UX gate |
| 55 | Testnet/mainnet confusion | Wrong funds | Network check | Separate UI sections | Visual separation |
| 56 | Memo/tag required but missing | Funds stuck | Chain rules | Require input for XRP/Cosmos | Validation |
| 57 | Invalid destination tag | Lost funds | Format check | Validate format pre-send | Regex |
| 58 | App update breaks binary | Can't sign | Version check | Verify Rust binary on launch | Health check |
| 59 | Localization missing | Broken UI | Key check | Fallback to English | NSLocalizedString |
| 60 | Accessibility broken | Unusable for some | VoiceOver test | Add accessibility labels | Testing |

---

## 8) Prioritized Roadmap (Unified)

### Phase 0 — Emergency Fixes (0–3 days)

| Priority | Task | Impact | Effort | Owner | Dependencies | Notes |
|:---|:---|:---|:---|:---|:---|:---|
| P0-1 | Remove Rust CLI Bridge (Process calls) | Critical | L | Eng | None | Ship blocker |
| P0-2 | Fix hardcoded paths | Critical | S | Eng | None | Crashes on all machines |
| P0-3 | Remove/hide "Preview Feature" DEX | High | S | Both | None | Trust killer |
| P0-4 | Remove hardcoded prices (ReceiveView) | High | S | Eng | PriceService | Fake data |
| P0-5 | Fix TransactionPreview UInt64 overflow | Critical | M | Eng | None | Misses unlimited approvals |
| P0-6 | Enable WalletConnect QR scan OR remove button | High | M | Eng | Camera permission | Broken button |
| P0-7 | Remove "Auto-accept Trusted dApps" toggle | Critical | S | Eng | None | Security anti-pattern |
| P0-8 | Add Monero "View Only" warning | High | S | Both | None | Fund trap |
| P0-9 | Force 2-word verification in Quick onboarding | High | S | Eng | None | Backup safety |
| P0-10 | Audit logs for sensitive data | High | S | Eng | Logger | Key exposure risk |

### Phase 1 — High ROI Improvements (1–2 weeks)

| Priority | Task | Impact | Effort | Owner | Dependencies | Notes |
|:---|:---|:---|:---|:---|:---|:---|
| P1-1 | Add Address Book / Contacts | High | M | Eng | None | Core usability |
| P1-2 | Add Recent Addresses to Send | High | S | Eng | Contacts | Faster sending |
| P1-3 | Add MAX button to Send | High | S | Eng | Fee estimation | UTXO required |
| P1-4 | Add privacy toggle (eye icon) | Medium | S | Eng | None | Quick win |
| P1-5 | Add Share QR button | Medium | S | Eng | None | Usability |
| P1-6 | Create unified Security Center hub | High | M | Both | None | Mental model |
| P1-7 | Add backup status badge | Medium | S | Both | None | Trust |
| P1-8 | Unify button components | High | M | Both | Design system | Visual consistency |
| P1-9 | Replace spinners with skeletons | Medium | M | Both | None | Perceived performance |
| P1-10 | Add keyboard shortcuts | Medium | M | Both | None | macOS delight |
| P1-11 | Add context menus | Medium | M | Both | None | macOS native |
| P1-12 | Add spam token filtering | High | M | Eng | Token list | Trust + performance |
| P1-13 | Add fee impact % display | Medium | S | Both | None | Clarity |
| P1-14 | Add stale data indicators | Medium | S | Both | Cache | Transparency |
| P1-15 | Add clipboard hijack detection | High | M | Eng | Pasteboard | Scam defense |

### Phase 2 — Best-in-Class (1–2 months)

| Priority | Task | Impact | Effort | Owner | Dependencies | Notes |
|:---|:---|:---|:---|:---|:---|:---|
| P2-1 | Refactor ContentView into modules | Critical | XL | Eng | None | Tech debt |
| P2-2 | Implement NavigationSplitView | High | L | Both | Refactor | macOS native |
| P2-3 | Add Token Approval Manager | High | L | Eng | Contract decoding | Security |
| P2-4 | Add NFT Gallery | Medium | M | Eng | API integration | Feature parity |
| P2-5 | Complete social recovery (Guardians) | High | L | Both | None | Differentiation |
| P2-6 | Add full transaction simulation | High | L | Eng | Rust | Best-in-class safety |
| P2-7 | Add multi-wallet support | Medium | L | Both | None | Power users |
| P2-8 | Complete DEX with real execution | High | L | Both | APIs | Revenue |
| P2-9 | Add Bridge functionality | Medium | L | Both | APIs | Cross-chain |
| P2-10 | Add push notifications | Medium | M | Eng | APNs | Engagement |
| P2-11 | Add transaction CSV export | Medium | S | Eng | None | Tax compliance |
| P2-12 | Add scam address database | High | M | Eng | Data source | Protection |
| P2-13 | Add offline mode | Medium | M | Eng | Cache | Resilience |
| P2-14 | Add multi-window support | Medium | L | Both | Architecture | Pro workflow |
| P2-15 | Settings search + modularization | Medium | M | Eng | None | Maintainability |

---

## 9) MASTER CHANGELOG (Everything)

### Architecture
- [Architecture] Dual Rust integration (FFI + CLI) → Remove CLI path, unify on FFI → Reliable, secure signing
- [Architecture] Hardcoded absolute paths → Remove or use Bundle.main → Works on all machines
- [Architecture] ContentView.swift (11k lines) → Refactor into feature modules → Maintainable, stable
- [Architecture] Swift/Rust boundary unclear → Define explicit API contracts → Clean separation

### macOS Native UX
- [macOS] Sheet-based navigation → NavigationSplitView + Toolbar → Native Mac feel
- [macOS] No keyboard shortcuts → Add Commands system → Power user delight
- [macOS] No context menus → Add right-click menus everywhere → Native interaction
- [macOS] No drag & drop → Implement drag providers/delegates → Pro workflow
- [macOS] iOS toggle switches → Use checkboxes where appropriate → Platform native
- [macOS] In-content close buttons → Use standard window chrome → Native appearance

### Trust & Credibility
- [Trust] "Preview Feature" DEX visible → Hide or finish → No fake features
- [Trust] Disabled QR scan button → Implement or remove → No broken UI
- [Trust] Hardcoded prices → Use PriceService or remove → Real data only
- [Trust] Monero view-only trap → Add prominent warning → Prevent fund loss
- [Trust] No version/audit info → Add to Settings → Legitimacy signals

### Onboarding
- [Onboarding] Quick skips all education → Force 2-word verification → Minimum backup proof
- [Onboarding] iCloud during phrase display → Move to post-verification → Cleaner flow
- [Onboarding] Backup skippable → Allow defer with limits → Safety net
- [Onboarding] No time estimate → Show "~3 minutes" → Set expectations

### Portfolio & Tokens
- [Portfolio] No privacy toggle → Add eye icon → Instant control
- [Portfolio] No spam filtering → Add hide/spam section → Clean UI + safety
- [Portfolio] Testnet mixed with mainnet → Separate sections → Clarity
- [Portfolio] No "add token" button → Add + button → Discoverability
- [Portfolio] No stale indicator → Add "Updated Xs ago" → Transparency

### Send & Receive
- [Send] No address book → Add contacts + recent → Core usability
- [Send] No MAX button → Add with fee calculation → UTXO support
- [Send] No recent addresses → Add picker → Faster repeat sends
- [Send] Fee impact hidden → Show as % → Informed decisions
- [Receive] Hardcoded prices → Use real or remove USD → No fake data
- [Receive] No share QR → Add share sheet → Usability

### Swap & Bridge
- [Swap] Preview/simulated → Hide or ship real → Trust
- [Swap] No slippage warning → Add at >2% → User protection
- [Bridge] Missing → Add or remove nav item → Feature clarity

### Transaction Safety
- [Safety] UInt64 overflow → Use BigInt → Catch unlimited approvals
- [Safety] No state-change summary → Add "You give/get/allow" → Human-readable
- [Safety] Approval warnings weak → Add prominent card + limited option → Drain prevention
- [Safety] No clipboard detection → Monitor timing → Hijack defense
- [Safety] No scam address DB → Integrate list → Protection
- [Safety] No address poisoning detection → Compare to history → Advanced defense

### dApps & WalletConnect
- [WalletConnect] QR scan disabled → Implement → Core feature
- [WalletConnect] Permissions unclear → Show chains/methods/expiry → Informed consent
- [WalletConnect] No session expiry visible → Show date → Lifecycle clarity
- [WalletConnect] No "revoke all" → Add button → Emergency action
- [WalletConnect] Auto-accept trusted → Remove feature → Security

### NFTs
- [NFTs] Gallery missing → Add with grid + hide/report → Feature parity
- [NFTs] Spam risk → Placeholder + click to load → Privacy/safety

### Settings & Security
- [Settings] 2,700-line file → Split into modules → Maintainability
- [Settings] No search → Add search bar → Discoverability
- [Settings] Reset too easy → Type-to-confirm → Prevent accidents
- [Security] Features scattered → Create Security Center → Single destination
- [Security] No backup indicator → Add "last verified" badge → Awareness
- [Security] Duress confusion risk → Add mode indicator → Clarity

### Performance
- [Performance] Spinners everywhere → Skeleton loading → Perceived speed
- [Performance] Heavy initial load → Lazy-load views → Faster startup
- [Performance] ContentView redraws → Isolate state → Stable UI

### Visual Design
- [Design] 5+ button styles → Single HawalaButton → Consistency
- [Design] System backgrounds → Use HawalaTheme → Visual cohesion
- [Design] Inconsistent icons → Standardize fill style → Polish
- [Design] SF Symbols for chains → Use real logos → Recognition

### Copywriting
- [Copy] Jargon unexplained → Add tooltips → Understanding
- [Copy] Errors too technical → User-facing messages → Actionable
- [Copy] Inconsistent tone → Unified voice → Brand cohesion

---

## 10) Appendix

### A) Feature Ideas Worth Exploring

1. **Hardware Wallet Quick Connect** — One-click Ledger/Trezor pairing
2. **Watch-Only Portfolio Mode** — View addresses without keys
3. **Weekly Portfolio Digest** — Email summary of holdings + performance
4. **DeFi Dashboard** — Track staking rewards, LP positions
5. **Pay by Username** — Social payment layer on top of addresses
6. **Price Alerts** — Push when tokens hit thresholds
7. **Tax Report Export** — Pre-formatted for TurboTax/Koinly
8. **QR Payment Requests** — Generate payment URIs with amount pre-filled
9. **Recurring Payments** — Scheduled sends (with approval flow)
10. **Mobile Companion App** — Linked read-only or approval-required

### B) Metrics to Track

**Activation:**
- Time to wallet creation
- Backup verification completion rate
- First deposit rate (within 24h)
- First send rate (within 7d)

**Retention:**
- D7, D30, D90 retention
- Monthly active transactors
- Session frequency

**Safety:**
- Scam warning dismiss rate
- Unlimited approval acceptance rate
- Clipboard warning trigger rate
- Failed transaction rate

**Performance:**
- App launch time
- Transaction confirmation latency
- RPC failure rate
- Crash rate

### C) A/B Tests to Run

1. Quick vs Guided as default onboarding path
2. 1-word vs 2-word vs 3-word verification
3. Skeleton vs spinner loading
4. Inline vs modal transaction confirmation
5. Privacy toggle: eye icon vs menu item
6. Approval default: limited vs unlimited (with warning)

### D) Analytics Events List

**Activation Events:**
- `onboarding_started`
- `onboarding_path_selected` (quick/guided)
- `seed_generated`
- `seed_revealed`
- `backup_verification_started`
- `backup_verification_completed`
- `backup_verification_skipped`
- `passcode_set`
- `biometrics_enabled`
- `wallet_created`
- `first_deposit`
- `first_send`

**Safety Events:**
- `scam_warning_shown`
- `scam_warning_dismissed`
- `unlimited_approval_shown`
- `unlimited_approval_edited`
- `unlimited_approval_accepted`
- `clipboard_warning_shown`
- `address_mismatch_detected`
- `transaction_simulation_run`

**Engagement Events:**
- `send_started`
- `send_completed`
- `receive_address_copied`
- `swap_started`
- `swap_completed`
- `dapp_connected`
- `dapp_disconnected`
- `settings_opened`
- `security_center_opened`

---

**End of MASTER REVIEW.md**

*Compiled from: chatgpt 5.2 codex review.md, claude opus 4.5 review.md, gemini 3 pro review.md, gpot 5.2 review.md*
*Date: February 1, 2026*
