# Exodus vs Hawala: Mobile Requirements

This file covers everything Hawala needs in order to close the mobile gap against Exodus.

Current baseline:
- Hawala is currently packaged as a macOS app in this workspace.
- Some backup behavior is explicitly macOS-only.
- Mobile is not a packaging exercise; it requires product, platform, UX, security, and operations work.

## 1. Product Decision

You need to decide the initial mobile scope.

Recommended path:
- ship iPhone first
- defer Android until the shared model, security, and wallet flows are stable

Why:
- the current codebase is Swift-heavy and will transfer more naturally to iOS than to Android
- this reduces the first mobile launch risk

## 2. Shared Architecture Extraction

Before building mobile UI, Hawala needs a cleaner shared core.

Work needed:
- extract reusable wallet domain logic from macOS-specific views
- keep Rust crypto/signing shared where possible
- isolate platform-specific concerns such as AppKit, desktop overlays, file dialogs, and desktop-only USB assumptions
- define shared service boundaries for send, receive, swap, bridge, staking, WalletConnect, alerts, contacts, and settings

## 3. iOS-Specific App Surface

You need to build real mobile screens, not just shrink desktop overlays.

Work needed:
- mobile onboarding
- mobile wallet home and portfolio
- send, receive, scan, contacts, transaction review, and activity
- swap, bridge, staking, price alerts, settings, and backup/recovery
- phone-sized navigation and bottom-sheet patterns
- safe one-handed ergonomics and touch-friendly layouts

## 4. Security for Mobile

Mobile security needs explicit design.

Work needed:
- Face ID / Touch ID unlock flows
- secure key storage and recovery-state handling
- passkey flows adapted for iPhone UX
- screenshot/privacy protections where appropriate
- clipboard handling and address-safety protections
- deep-link validation and malicious app-link hardening
- jailbreak / compromised-device strategy if you want one

## 5. Mobile WalletConnect and dApp Connectivity

Exodus' web3 positioning requires Hawala mobile to handle dApp connectivity cleanly.

Work needed:
- mobile WalletConnect pairing and session approval UX
- universal-link and QR-based pairing flows
- background/resume-safe session management
- per-dApp permission review and revocation UI

## 6. Push Notifications and Background Behavior

Desktop local notifications are not enough for mobile parity.

Work needed:
- APNs integration
- push notifications for transaction status, price alerts, staking events, and security alerts
- background refresh strategy for balances and key non-sensitive state
- notification permission flows and settings management

## 7. Backup and Recovery for Mobile

The mobile product needs recovery behavior designed for mobile realities.

Work needed:
- iPhone-safe recovery phrase flows
- iCloud Keychain and backup behavior reviewed for mobile use
- recovery verification UX on small screens
- safe export/import behavior without relying on macOS-only file flows
- migration and restore strategy between desktop and mobile

## 8. Mobile Buy / Sell / Swap / Bridge / Staking Parity

If Hawala launches mobile, these features need coherent mobile-native execution.

Work needed:
- mobile-native buy/sell redirects or embedded provider flows
- swap and bridge review screens optimized for phone use
- staking position management on mobile
- robust interruption recovery after app switching to external payment/KYC flows

## 9. Mobile Hardware and Sensor Use

Mobile changes the available hardware surface.

Work needed:
- camera-first QR scanning and import flows
- share sheet support for payment requests, addresses, and transactions
- universal links and deep links for hawala links and partner redirects
- clipboard monitoring rules that respect privacy and platform policy

## 10. State Sync Between Desktop and Mobile

This is one of the biggest product gaps relative to Exodus-style continuity.

Work needed:
- decide what syncs and what never syncs
- sync non-secret state such as contacts, hidden tokens, alerts, preferences, watchlists, recent dApps, and UI settings
- separate recovery/secret material from convenience sync data
- add migration logic so users can move between macOS and mobile without confusion

## 11. Mobile Testing and Release

Mobile requires a full release program.

Work needed:
- TestFlight pipeline
- device matrix testing across current and older iPhones
- crash reporting and diagnostics
- battery/performance testing
- offline and interrupted-session testing
- app review preparation and privacy labels

## 12. Mobile Feature Parity Checklist

At minimum, mobile should reach parity on:
- wallet creation and import
- unlock and passkeys
- send, receive, and QR scan
- transaction review and warnings
- transaction history
- contacts
- WalletConnect
- buy and sell
- swap and bridge
- price alerts and notifications
- backup and recovery
- settings and security controls

## 13. Recommended Mobile Rollout Plan

Phase 1:
- extract shared core
- ship iPhone wallet fundamentals only

Phase 2:
- add WalletConnect, alerts, and recovery polish

Phase 3:
- add buy/sell, swap, bridge, and staking parity

Phase 4:
- add cross-device continuity and broader ecosystem integration

## What Not to Do

Avoid these mistakes:
- do not port desktop overlays directly without redesign
- do not launch mobile before the provider-backed flows are production-ready
- do not promise desktop-mobile sync before the security model is explicitly defined
- do not mix secret sync and convenience sync without hard rules
