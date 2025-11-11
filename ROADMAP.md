# Hawala 2.0 – Development Roadmap

## Current Status
**Version:** 0.9.0-beta  
**Last Updated:** November 11, 2025

Multi-chain key generator with live balance/price tracking now complete. Native Ethereum RPC integration for ERC-20 stablecoins (USDT, USDC, DAI) verified working. All 10 supported chains render with balances and prices.

---

## Phase 1: Stability & Polish (Immediate – 1-2 weeks)

### 1.1 Error Handling & Recovery
- [ ] Add retry logic for failed RPC calls (exponential backoff)
- [ ] Graceful fallback when APIs are temporarily unavailable
- [ ] User-facing error messages with actionable guidance
- [ ] Network connectivity detection before attempting calls

### 1.2 UI/UX Refinements
- [ ] Add loading skeleton states instead of generic "Loading…"
- [ ] Improve card transition animations
- [ ] Add copy-to-clipboard feedback for price/balance tiles
- [ ] Dark mode support for macOS
- [ ] Responsive layout for smaller displays

### 1.3 Performance Optimization
- [ ] Cache price snapshots to reduce API calls (5-10 minute TTL)
- [ ] Lazy-load chain details only when card is selected
- [ ] Optimize Decimal arithmetic for large balance numbers
- [ ] Profile and reduce memory footprint of StateManager

### 1.4 Accessibility
- [ ] Add VoiceOver support for screen readers
- [ ] Keyboard navigation shortcuts (Tab, Enter, Escape)
- [ ] High contrast mode for visibility
- [ ] WCAG 2.1 AA compliance audit

---

## Phase 2: Security & Data Protection (1-3 weeks)

### 2.1 Encryption at Rest
- [ ] Encrypted backup format (AES-GCM with PBKDF2 key derivation)
- [ ] Secure key material storage in macOS Keychain
- [ ] Automatic backup on key generation with recovery passphrase
- [ ] Import functionality for encrypted backups

### 2.2 Session Security
- [ ] Implement 30-minute inactivity auto-lock
- [ ] Biometric unlock (Touch ID/Face ID on compatible Macs)
- [ ] Screen blur when app moves to background
- [ ] Clear sensitive data from memory on lock

### 2.3 Security Audit
- [ ] Run `cargo audit` and resolve any findings
- [ ] Dependency vulnerability scanning (OWASP)
- [ ] Code review with focus on crypto operations
- [ ] Penetration testing on key export/import flows

### 2.4 Privacy Policy & Terms
- [ ] No telemetry or tracking (verify no hidden calls)
- [ ] Clear privacy documentation
- [ ] GDPR/CCPA compliance review
- [ ] Terms of service for app

---

## Phase 3: Multi-Chain Expansion (2-4 weeks)

### 3.1 Additional Blockchain Support
- [ ] Dogecoin (DOGE)
- [ ] Ripple XRP balance tracking improvements
- [ ] Cardano (ADA)
- [ ] Polkadot (DOT)
- [ ] Cosmos (ATOM)

### 3.2 Additional Token Standards
- [ ] BEP-20 tokens on BSC
- [ ] SPL tokens on Solana
- [ ] TRC-20 tokens on TRON
- [ ] Polygon (MATIC) network support

### 3.3 RPC Reliability
- [ ] Fallback to multiple RPC endpoints
- [ ] Load balancer for PublicNode/Ankr/Alchemy
- [ ] Rate limiting to avoid hitting free tier limits
- [ ] Self-hosted RPC node option for advanced users

---

## Phase 4: Testing & Quality (2-3 weeks)

### 4.1 Unit Testing
- [ ] Key generation correctness against known test vectors
- [ ] Address derivation validation (BIP32/BIP44)
- [ ] Decimal/BigInt arithmetic edge cases
- [ ] Encryption/decryption roundtrip tests

### 4.2 Integration Testing
- [ ] End-to-end balance fetch for each supported chain
- [ ] Mock RPC responses for offline testing
- [ ] Backup/restore cycle validation
- [ ] Onboarding flow completeness

### 4.3 E2E Testing
- [ ] Automated UI tests with XCTest
- [ ] Screenshot capture for regression detection
- [ ] Performance benchmarks (build time, launch time, memory)
- [ ] Continuous integration on GitHub Actions

### 4.4 Manual Testing Checklist
- [ ] Test on macOS 13, 14, 15 (multiple versions)
- [ ] Verify on M1/M2/Intel architectures
- [ ] Network failover scenarios (wifi → cellular)
- [ ] Long-running sessions (24+ hours uptime)

---

## Phase 5: Marketplace & Distribution (1-2 weeks)

### 5.1 App Store Preparation
- [ ] Create AppStore developer account and certificates
- [ ] Build notarization for macOS distribution
- [ ] Write AppStore description & screenshot gallery
- [ ] Verify sandbox security requirements
- [ ] Price tier decision (free vs. paid)

### 5.2 Alternative Distribution
- [ ] GitHub releases with signed DMG packages
- [ ] Homebrew formula for easy installation
- [ ] Direct website download with checksum verification
- [ ] Auto-update mechanism (Sparkle framework)

### 5.3 Documentation for End Users
- [ ] Quick start guide (5-minute setup)
- [ ] Video tutorials (key generation, backup, restore)
- [ ] FAQ with common issues & troubleshooting
- [ ] Security best practices guide

---

## Phase 6: Advanced Features (Optional – 3-6 weeks)

### 6.1 Transaction Signing
- [ ] Sign Bitcoin transactions (P2WPKH)
- [ ] Sign Ethereum transactions (EIP-191)
- [ ] Batch transaction signing UI
- [ ] Hardware wallet integration (Ledger/Trezor fallback)

### 6.2 Portfolio Analytics
- [ ] Net worth tracking across all chains
- [ ] Historical price charts (24h, 7d, 30d, 1y)
- [ ] Portfolio allocation pie chart
- [ ] Gain/loss calculation with cost-basis tracking

### 6.3 Custom RPC Configuration
- [ ] User can specify custom RPC endpoints
- [ ] Save multiple RPC profiles
- [ ] Test connectivity before saving
- [ ] Failover to public RPC if custom fails

### 6.4 Hardware Security Module Integration
- [ ] YubiKey support for key storage
- [ ] Secure enclave integration (Apple)
- [ ] Cold storage export (paper wallet format)
- [ ] QR code generation for offline transfers

---

## Phase 7: Community & Ecosystem (Ongoing)

### 7.1 Open Source
- [ ] Complete codebase audit & cleanup
- [ ] Add comprehensive inline documentation
- [ ] Create CONTRIBUTING.md for external developers
- [ ] Set up issue templates & discussion boards

### 7.2 Community Engagement
- [ ] Launch Discord/Telegram community channels
- [ ] Host monthly security/feature webinars
- [ ] Bug bounty program (HackerOne)
- [ ] Contributor recognition & credits

### 7.3 Partnerships
- [ ] Integration with other wallet projects
- [ ] Educational institution partnerships
- [ ] Exchange integrations (price feeds)
- [ ] Hardware wallet manufacturer outreach

---

## Dependency Monitoring (Ongoing)

- [ ] Weekly `cargo audit` runs in CI/CD
- [ ] Monthly dependency update reviews
- [ ] Security advisory subscription
- [ ] Rust & Swift toolchain updates

---

## Success Metrics

| Metric | Target |
|--------|--------|
| App Store rating | 4.5+ stars |
| User downloads (6 months) | 10,000+ |
| Zero critical security issues | 100% |
| Key generation correctness | 100% validated |
| App launch time | < 2 seconds |
| Memory footprint | < 100 MB |
| API call success rate | > 99.5% |
| User satisfaction NPS | > 50 |

---

## Timeline Summary

| Phase | Duration | Target Release |
|-------|----------|-----------------|
| Phase 1 (Stability) | 1-2 weeks | Week of Nov 18 |
| Phase 2 (Security) | 1-3 weeks | Week of Dec 2 |
| Phase 3 (Expansion) | 2-4 weeks | Week of Dec 16 |
| Phase 4 (Testing) | 2-3 weeks | Week of Jan 6 |
| Phase 5 (Distribution) | 1-2 weeks | Week of Jan 20 |
| **v1.0.0 Launch** | — | **Early February 2026** |
| Phase 6+ (Advanced) | 3-6+ weeks | Q1 2026 onwards |

---

## Risk Mitigation

| Risk | Likelihood | Mitigation |
|------|------------|-----------|
| RPC rate limiting | High | Implement fallback endpoints + caching |
| Crypto library vulnerabilities | Low | Regular audits + dependency scanning |
| macOS API changes | Low | Test on multiple OS versions early |
| User adoption friction | Medium | Invest heavily in onboarding UX |
| Regulatory uncertainty | Medium | Legal review, compliance documentation |

---

## Notes

- **Prioritization:** Phases 1–2 must complete before v1.0. Phases 3–5 follow naturally.
- **Resources:** Estimate 2–3 full-time developers or 6–9 months solo effort.
- **Feedback Loop:** Incorporate user feedback after Phase 1 release candidate.
- **Documentation:** Keep all docs in sync with code; automate where possible.

---

## Quick Wins (Can Do Today)

1. ✅ ERC-20 balance display for USDT/USDC/DAI
2. ✅ Fixed $1.00 price for stablecoins
3. **TODO:** Add error message banner when RPC calls fail
4. **TODO:** Implement 10-second retry for timeouts
5. **TODO:** Add dark mode toggle in toolbar

---

*For questions or updates to this roadmap, contact the dev team.*
