# Milestone 1 — Wallet Core v1 (HD + Imported Accounts + Backups) - Detailed Execution Plan

**Goal:** Real wallet foundations that won't change later.

**Timeline:** 2–4 weeks

**Status:** ✅ COMPLETED (Dec 14, 2025)

---

## 📋 Overview

Milestone 1 establishes the core wallet architecture that all subsequent features will build upon. This is the most critical milestone - any mistakes here multiply across every chain and feature.

### Key Deliverables:
1. **Wallet Data Model** - Single source of truth for HD wallets and imported accounts ✅
2. **Secure Storage Contract** - Encryption at rest, memory isolation, no secret logging ✅
3. **Backup System** - Seed phrase flows + `.hawala` encrypted export/import ✅
4. **Restore Flows** - From seed phrase or `.hawala` file ✅

### Completed Files:
- `Models/Wallet/WalletIdentity.swift` - Protocol defining wallet identity
- `Models/Wallet/HDWallet.swift` - HD wallet with deterministic ID from seed
- `Models/Wallet/HDAccount.swift` - Per-chain derived accounts
- `Models/Wallet/ImportedAccount.swift` - Standalone imported accounts
- `Models/Wallet/WalletStore.swift` - Persistence protocol
- `Security/SecureStorageProtocol.swift` - Storage contract
- `Security/KeychainSecureStorage.swift` - Keychain with biometric protection
- `Security/EncryptedFileStorage.swift` - AES-GCM file encryption
- `Security/SecureMemoryBuffer.swift` - Memory-zeroing buffer
- `Crypto/MnemonicValidator.swift` - BIP39 validation
- `Crypto/KeyDerivationService.swift` - Rust backend integration
- `Crypto/WalletManager.swift` - Central wallet coordinator
- `Crypto/BackupManager.swift` - Backup export/import
- `Views/SeedPhraseViews.swift` - Seed display + verification
- `Views/BackupViews.swift` - Backup export/import UI
- `Views/RestoreWalletFlowView.swift` - Multi-step restore flow

### Test Results:
- 22 tests passing (WalletModelTests, MnemonicValidatorTests, EncryptedFileStorageTests)

---

## 📋 Task Breakdown

### M1.1 — Wallet Data Model Design
**Objective:** Design and implement the core data structures for HD wallets and imported accounts.

**Time Estimate:** 3-4 hours

Steps:
1. Design `Wallet` protocol/base type with common properties
2. Create `HDWallet` struct:
   - `id: UUID` (deterministic from seed)
   - `name: String`
   - `createdAt: Date`
   - `accounts: [HDAccount]`
   - `derivationScheme: DerivationScheme`
3. Create `HDAccount` struct:
   - `index: Int` (account index in BIP44)
   - `chainId: String`
   - `derivationPath: String`
   - `address: String` (derived, not stored)
   - `label: String?`
4. Create `ImportedAccount` struct:
   - `id: UUID`
   - `chainId: String`
   - `address: String`
   - `label: String?`
   - `importedAt: Date`
5. Create `WalletStore` protocol for persistence abstraction
6. Add unit tests for model serialization/deserialization

Files to create:
- `swift-app/Sources/swift-app/Models/Wallet/Wallet.swift`
- `swift-app/Sources/swift-app/Models/Wallet/HDWallet.swift`
- `swift-app/Sources/swift-app/Models/Wallet/HDAccount.swift`
- `swift-app/Sources/swift-app/Models/Wallet/ImportedAccount.swift`
- `swift-app/Sources/swift-app/Models/Wallet/DerivationScheme.swift`
- `swift-app/Tests/swift-appTests/WalletModelTests.swift`

Acceptance:
- [ ] Models are Codable and can be serialized to JSON
- [ ] Deterministic ID generation from seed works
- [ ] Unit tests pass for all model operations

---

### M1.2 — Secure Storage Architecture
**Objective:** Implement encryption-at-rest for all sensitive wallet data.

**Time Estimate:** 4-6 hours

Steps:
1. Define `SecureStorageContract` protocol:
   - `save(data: Data, key: String) throws`
   - `load(key: String) throws -> Data?`
   - `delete(key: String) throws`
   - `exists(key: String) -> Bool`
2. Implement `KeychainSecureStorage`:
   - Uses macOS Keychain for seed phrases
   - Requires biometric/passcode authentication
   - kSecAttrAccessible: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
3. Implement `EncryptedFileStorage`:
   - For `.hawala` backup files
   - Uses CryptoKit for AES-GCM encryption
   - Key derivation: PBKDF2 or Argon2id from user password
4. Create `SecureMemoryBuffer`:
   - Zeroes memory on deallocation
   - No logging of contents
   - Swift `CustomStringConvertible` that redacts
5. Audit existing code for secret leaks:
   - Search for `print()` statements with keys
   - Ensure `CustomDebugStringConvertible` redacts secrets
6. Add unit tests for encryption/decryption round-trips

Files to create:
- `swift-app/Sources/swift-app/Security/SecureStorageContract.swift`
- `swift-app/Sources/swift-app/Security/KeychainSecureStorage.swift`
- `swift-app/Sources/swift-app/Security/EncryptedFileStorage.swift`
- `swift-app/Sources/swift-app/Security/SecureMemoryBuffer.swift`
- `swift-app/Tests/swift-appTests/SecureStorageTests.swift`

Acceptance:
- [ ] Seed phrases stored in Keychain with biometric protection
- [ ] File exports are AES-GCM encrypted
- [ ] Secret values are never logged (grep verification)
- [ ] Memory is zeroed after use

---

### M1.3 — BIP39 Seed Phrase Generation & Validation
**Objective:** Implement proper BIP39 mnemonic generation, validation, and seed derivation.

**Time Estimate:** 3-4 hours

Steps:
1. Create `MnemonicGenerator`:
   - Generate 12/24 word phrases (128/256 bit entropy)
   - Use `SecRandomCopyBytes` for entropy
   - BIP39 wordlist validation
2. Create `MnemonicValidator`:
   - Checksum verification
   - Wordlist membership check
   - Length validation (12/15/18/21/24 words)
3. Create `SeedDeriver`:
   - BIP39 PBKDF2 derivation (mnemonic + passphrase → seed)
   - 2048 rounds, HMAC-SHA512
4. Add test vectors from BIP39 spec
5. Ensure Rust backend integration (if using Rust for derivation)

Files to create/modify:
- `swift-app/Sources/swift-app/Crypto/MnemonicGenerator.swift`
- `swift-app/Sources/swift-app/Crypto/MnemonicValidator.swift`
- `swift-app/Sources/swift-app/Crypto/SeedDeriver.swift`
- `swift-app/Sources/swift-app/Crypto/BIP39Wordlist.swift`
- `swift-app/Tests/swift-appTests/BIP39Tests.swift`

Acceptance:
- [ ] Generated mnemonics pass checksum validation
- [ ] Test vectors from BIP39 spec pass
- [ ] Passphrase support works correctly
- [ ] Invalid mnemonics are rejected with clear error

---

### M1.4 — HD Key Derivation (BIP32/BIP44)
**Objective:** Implement hierarchical deterministic key derivation for all supported chains.

**Time Estimate:** 4-6 hours

Steps:
1. Create `HDKeyDeriver` protocol:
   - `deriveKey(seed: Data, path: String) -> DerivedKey`
   - Support hardened and non-hardened derivation
2. Implement chain-specific derivation paths:
   - Bitcoin: `m/84'/0'/0'/0/0` (Native SegWit)
   - Ethereum: `m/44'/60'/0'/0/0`
   - Solana: `m/44'/501'/0'/0'`
   - XRP: `m/44'/144'/0'/0/0`
   - Litecoin: `m/84'/2'/0'/0/0`
   - BNB/BSC: `m/44'/60'/0'/0/0` (same as ETH)
   - Cosmos: `m/44'/118'/0'/0/0`
   - Cardano: `m/1852'/1815'/0'/0/0` (Shelley era)
   - Polygon: `m/44'/60'/0'/0/0` (same as ETH)
3. Create `DerivationPath` parser and validator
4. Add deterministic test vectors for each chain
5. Integrate with Rust backend for actual derivation

Files to create/modify:
- `swift-app/Sources/swift-app/Crypto/HDKeyDeriver.swift`
- `swift-app/Sources/swift-app/Crypto/DerivationPath.swift`
- `swift-app/Sources/swift-app/Crypto/ChainDerivationConfig.swift`
- `swift-app/Tests/swift-appTests/HDDerivationTests.swift`

Acceptance:
- [ ] BIP32 derivation matches test vectors
- [ ] Each chain uses correct derivation path
- [ ] Same seed produces same addresses deterministically
- [ ] Account indices increment correctly (m/44'/60'/0'/0/0, m/44'/60'/0'/0/1, ...)

---

### M1.5 — Wallet Manager Service
**Objective:** Create the central service for wallet operations (create, load, delete, list).

**Time Estimate:** 4-5 hours

Steps:
1. Create `WalletManager` class (@MainActor, ObservableObject):
   - `createWallet(name: String, passphrase: String?) async throws -> HDWallet`
   - `loadWallet(id: UUID) async throws -> HDWallet`
   - `deleteWallet(id: UUID) async throws`
   - `listWallets() -> [WalletSummary]`
   - `importAccount(privateKey: String, chain: ChainId) async throws -> ImportedAccount`
   - `getCurrentWallet() -> HDWallet?`
2. Implement wallet switching:
   - `switchToWallet(id: UUID)`
   - Persist "current wallet" preference
3. Add wallet metadata caching (don't load full wallet until needed)
4. Implement wallet lock/unlock with biometric
5. Add published state for UI binding

Files to create/modify:
- `swift-app/Sources/swift-app/Services/WalletManager.swift`
- `swift-app/Sources/swift-app/Models/Wallet/WalletSummary.swift`
- `swift-app/Tests/swift-appTests/WalletManagerTests.swift`

Acceptance:
- [ ] Can create multiple wallets
- [ ] Wallet switching persists across app restarts
- [ ] Deleting a wallet removes all associated data
- [ ] Imported accounts are separate from HD accounts

---

### M1.6 — Seed Phrase Backup UI Flow
**Objective:** Implement the seed phrase display and confirmation flow.

**Time Estimate:** 4-5 hours

Steps:
1. Create `SeedPhraseBackupView`:
   - Security warning before showing
   - Biometric/passcode gate
   - Display all 12/24 words clearly
   - "I have written this down" confirmation
   - Copy protection (disable screenshots on iOS, warn on macOS)
2. Create `SeedPhraseConfirmationView`:
   - Quiz user on random word positions
   - "Word #3 is ___?" style verification
   - Require 3-4 correct answers before confirming
3. Create `BackupReminderManager`:
   - Track if backup is confirmed
   - Show reminder badge/alert if not backed up
   - Persist backup status per wallet
4. Update onboarding flow to include backup step
5. Add "Backup Now" option in Settings

Files to create/modify:
- `swift-app/Sources/swift-app/Views/Backup/SeedPhraseBackupView.swift`
- `swift-app/Sources/swift-app/Views/Backup/SeedPhraseConfirmationView.swift`
- `swift-app/Sources/swift-app/Views/Backup/BackupReminderBanner.swift`
- `swift-app/Sources/swift-app/Services/BackupReminderManager.swift`
- Modify: Onboarding flow

Acceptance:
- [ ] Seed phrase requires biometric to view
- [ ] User must confirm at least 3 words
- [ ] Backup reminder shows until confirmed
- [ ] Screenshots are discouraged/prevented

---

### M1.7 — .hawala Encrypted Export Format
**Objective:** Define and implement the `.hawala` encrypted backup file format.

**Time Estimate:** 4-5 hours

Steps:
1. Define `.hawala` file format specification:
   ```
   Header (32 bytes):
   - Magic bytes: "HWLA" (4 bytes)
   - Version: UInt16 (2 bytes)
   - Flags: UInt16 (2 bytes)
   - Salt: 16 bytes (for key derivation)
   - Reserved: 8 bytes
   
   Body (encrypted):
   - IV: 12 bytes (AES-GCM nonce)
   - Ciphertext: variable
   - Auth tag: 16 bytes
   
   Payload (JSON when decrypted):
   - version: string
   - wallets: [HDWallet]
   - importedAccounts: [ImportedAccount]
   - settings: optional app settings
   - metadata: creation date, app version
   ```
2. Create `HawalaFileEncoder`:
   - Password → key via Argon2id (or PBKDF2)
   - Encrypt payload with AES-256-GCM
   - Write header + encrypted body
3. Create `HawalaFileDecoder`:
   - Read and validate header
   - Derive key from password
   - Decrypt and verify auth tag
   - Parse JSON payload
4. Implement version migrations for future compatibility
5. Add integrity verification (checksum)

Files to create:
- `swift-app/Sources/swift-app/Backup/HawalaFileFormat.swift`
- `swift-app/Sources/swift-app/Backup/HawalaFileEncoder.swift`
- `swift-app/Sources/swift-app/Backup/HawalaFileDecoder.swift`
- `swift-app/Sources/swift-app/Backup/HawalaFileMigrations.swift`
- `swift-app/Tests/swift-appTests/HawalaFileTests.swift`

Acceptance:
- [ ] Export creates valid encrypted file
- [ ] Import decrypts and restores wallets
- [ ] Wrong password gives clear error (not crash)
- [ ] File versioning works for future migrations

---

### M1.8 — Export UI Flow
**Objective:** Implement the UI for exporting wallet to `.hawala` file.

**Time Estimate:** 2-3 hours

Steps:
1. Create `ExportWalletView`:
   - Select what to export (all wallets, specific wallet)
   - Password creation with strength indicator
   - Password confirmation
   - Biometric gate before export
2. Implement file save dialog:
   - Suggest filename with date
   - `.hawala` extension enforced
3. Add export progress indicator
4. Show success confirmation with file location
5. Add "Export Wallet" option in Settings

Files to create/modify:
- `swift-app/Sources/swift-app/Views/Backup/ExportWalletView.swift`
- `swift-app/Sources/swift-app/Views/Backup/PasswordStrengthIndicator.swift`
- Modify: SettingsView.swift

Acceptance:
- [ ] Password must meet minimum strength
- [ ] Export requires biometric/passcode
- [ ] File saves to user-selected location
- [ ] Success/failure feedback is clear

---

### M1.9 — Import/Restore UI Flow
**Objective:** Implement restoration from seed phrase or `.hawala` file.

**Time Estimate:** 4-5 hours

Steps:
1. Create `RestoreOptionsView`:
   - "Restore from Seed Phrase" button
   - "Restore from Backup File" button
2. Create `SeedPhraseRestoreView`:
   - 12 or 24 word input fields
   - Auto-suggest from BIP39 wordlist
   - Paste detection for full phrase
   - Optional passphrase field
   - Validation before proceeding
3. Create `FileRestoreView`:
   - File picker for `.hawala` files
   - Password input
   - Preview of contents before restore
   - Conflict resolution if wallet exists
4. Implement restore logic:
   - Verify addresses match expected
   - Show derived addresses for confirmation
   - Create wallet from restored data
5. Add restore option to onboarding

Files to create/modify:
- `swift-app/Sources/swift-app/Views/Restore/RestoreOptionsView.swift`
- `swift-app/Sources/swift-app/Views/Restore/SeedPhraseRestoreView.swift`
- `swift-app/Sources/swift-app/Views/Restore/FileRestoreView.swift`
- `swift-app/Sources/swift-app/Views/Restore/RestorePreviewView.swift`
- Modify: Onboarding flow

Acceptance:
- [ ] Seed phrase restore produces same addresses
- [ ] File restore decrypts and imports correctly
- [ ] Invalid input gives helpful error messages
- [ ] Restore flow is accessible from onboarding and settings

---

### M1.10 — Address Derivation Verification
**Objective:** Ensure all chain address derivations match expected test vectors.

**Time Estimate:** 3-4 hours

Steps:
1. Create comprehensive test vectors for each chain:
   - Use known test mnemonic
   - Record expected addresses for first 5 indices
   - Include mainnet and testnet where applicable
2. Implement address verification in restore flow:
   - Show first address during restore
   - User confirms it matches their records
3. Add "Verify Addresses" utility in Settings/Debug:
   - Shows all derived addresses
   - Allows copying for verification
4. Test edge cases:
   - Empty passphrase vs no passphrase
   - Unicode passphrases
   - Very long derivation paths

Files to create/modify:
- `swift-app/Tests/swift-appTests/AddressDerivationVectors.swift`
- `swift-app/Sources/swift-app/Views/Debug/AddressVerificationView.swift`
- Add verification step to restore flow

Acceptance:
- [ ] All test vectors pass
- [ ] Restore shows first address for confirmation
- [ ] Same mnemonic + passphrase = same addresses (deterministic)

---

### M1.11 — Wallet List UI
**Objective:** Implement UI for managing multiple wallets.

**Time Estimate:** 2-3 hours

Steps:
1. Create `WalletListView`:
   - List all HD wallets
   - Show wallet name, creation date, account count
   - Current wallet indicator
   - Imported accounts section (separate)
2. Implement wallet switching:
   - Tap to switch
   - Confirmation if pending transactions
3. Add wallet management actions:
   - Rename wallet
   - Delete wallet (with confirmation)
   - View seed phrase (gated)
4. Add "Create New Wallet" button
5. Add "Import Account" button

Files to create/modify:
- `swift-app/Sources/swift-app/Views/Wallet/WalletListView.swift`
- `swift-app/Sources/swift-app/Views/Wallet/WalletRowView.swift`
- `swift-app/Sources/swift-app/Views/Wallet/WalletActionsMenu.swift`
- Modify: Navigation/tab structure

Acceptance:
- [ ] Can see all wallets in list
- [ ] Can switch between wallets
- [ ] Can rename/delete wallets
- [ ] Imported accounts shown separately

---

### M1.12 — Integration Testing & Validation
**Objective:** Comprehensive testing of all M1 functionality.

**Time Estimate:** 3-4 hours

Steps:
1. Create end-to-end test scenarios:
   - Fresh install → create wallet → backup → verify
   - Delete app data → restore from seed → addresses match
   - Export to .hawala → reinstall → import → addresses match
   - Create wallet A, create wallet B, switch between them
   - Import private key → shows as imported account
2. Test error conditions:
   - Invalid mnemonic
   - Wrong backup password
   - Corrupted .hawala file
   - Duplicate wallet import
3. Security testing:
   - Grep logs for secrets
   - Memory dump analysis (if possible)
   - Keychain access without biometric
4. Update MILESTONE_1_PLAN.md with completion status

Files to create/modify:
- `swift-app/Tests/swift-appTests/WalletIntegrationTests.swift`
- Update: MILESTONE_1_PLAN.md

Acceptance:
- [ ] All integration tests pass
- [ ] No secrets in logs (verified)
- [ ] Error handling is user-friendly
- [ ] Backup/restore round-trip works

---

## 🚀 Execution Order

1. **M1.1 — Wallet Data Model** (foundation for everything)
2. **M1.2 — Secure Storage Architecture** (security before features)
3. **M1.3 — BIP39 Seed Phrase** (core crypto)
4. **M1.4 — HD Key Derivation** (depends on M1.3)
5. **M1.5 — Wallet Manager Service** (depends on M1.1-M1.4)
6. **M1.6 — Seed Phrase Backup UI** (depends on M1.3, M1.5)
7. **M1.7 — .hawala Export Format** (depends on M1.2)
8. **M1.8 — Export UI Flow** (depends on M1.7)
9. **M1.9 — Import/Restore UI** (depends on M1.3, M1.7)
10. **M1.10 — Address Verification** (depends on M1.4)
11. **M1.11 — Wallet List UI** (depends on M1.5)
12. **M1.12 — Integration Testing** (final validation)

---

## 📁 Files to Create (Summary)

| Category | Files |
|----------|-------|
| **Models** | `Wallet.swift`, `HDWallet.swift`, `HDAccount.swift`, `ImportedAccount.swift`, `DerivationScheme.swift`, `WalletSummary.swift` |
| **Security** | `SecureStorageContract.swift`, `KeychainSecureStorage.swift`, `EncryptedFileStorage.swift`, `SecureMemoryBuffer.swift` |
| **Crypto** | `MnemonicGenerator.swift`, `MnemonicValidator.swift`, `SeedDeriver.swift`, `BIP39Wordlist.swift`, `HDKeyDeriver.swift`, `DerivationPath.swift`, `ChainDerivationConfig.swift` |
| **Backup** | `HawalaFileFormat.swift`, `HawalaFileEncoder.swift`, `HawalaFileDecoder.swift`, `HawalaFileMigrations.swift` |
| **Views** | `SeedPhraseBackupView.swift`, `SeedPhraseConfirmationView.swift`, `BackupReminderBanner.swift`, `ExportWalletView.swift`, `PasswordStrengthIndicator.swift`, `RestoreOptionsView.swift`, `SeedPhraseRestoreView.swift`, `FileRestoreView.swift`, `RestorePreviewView.swift`, `WalletListView.swift`, `WalletRowView.swift`, `WalletActionsMenu.swift`, `AddressVerificationView.swift` |
| **Services** | `WalletManager.swift`, `BackupReminderManager.swift` |
| **Tests** | `WalletModelTests.swift`, `SecureStorageTests.swift`, `BIP39Tests.swift`, `HDDerivationTests.swift`, `WalletManagerTests.swift`, `HawalaFileTests.swift`, `AddressDerivationVectors.swift`, `WalletIntegrationTests.swift` |

---

## ⏱️ Time Estimate

| Task | Estimate |
|------|----------|
| M1.1 Wallet Data Model | 3-4 hours |
| M1.2 Secure Storage | 4-6 hours |
| M1.3 BIP39 Seed Phrase | 3-4 hours |
| M1.4 HD Key Derivation | 4-6 hours |
| M1.5 Wallet Manager | 4-5 hours |
| M1.6 Seed Backup UI | 4-5 hours |
| M1.7 .hawala Format | 4-5 hours |
| M1.8 Export UI | 2-3 hours |
| M1.9 Import/Restore UI | 4-5 hours |
| M1.10 Address Verification | 3-4 hours |
| M1.11 Wallet List UI | 2-3 hours |
| M1.12 Integration Testing | 3-4 hours |
| **Total** | **40-54 hours** (~1-2 weeks focused) |

---

## 🎯 Definition of Done

Milestone 1 is complete when:
- [ ] Fresh install → create wallet → backup confirmation required
- [ ] Restore from seed reproduces same addresses on all chains
- [ ] `.hawala` export/import round-trips and verifies integrity
- [ ] Multiple wallets can coexist and be switched between
- [ ] Imported accounts are clearly separated from HD accounts
- [ ] All secrets are encrypted at rest (Keychain + AES-GCM)
- [ ] No secrets appear in logs (verified by grep)
- [ ] All unit and integration tests pass

---

## ⚠️ Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Key derivation bugs | Critical - wrong addresses | Use established test vectors, Rust backend verification |
| Encryption implementation flaws | Critical - compromised backups | Use CryptoKit/proven libraries, no custom crypto |
| Memory leaks of secrets | High - key exposure | SecureMemoryBuffer, audit memory usage |
| Backup file corruption | Medium - data loss | Checksums, versioning, clear error messages |
| Complex passphrase edge cases | Medium - restore failures | Unicode normalization, extensive testing |

---

## 🔗 Dependencies

### External Libraries (verify before starting):
- CryptoKit (built-in)
- Security framework (Keychain)
- Argon2 implementation (if using for key derivation)

### Rust Backend:
- Verify key derivation functions are exposed
- Ensure test vectors match Swift expectations
- Check for any serialization format changes needed

---

## 🎯 Starting Point

Begin with **M1.1 — Wallet Data Model** since it defines the core types everything else depends on.
