# Hawala Key Lifecycle

## Entropy And Creation

Wallet entropy is generated in Rust. Swift must treat generated key material as sensitive display or storage data only, never as a logging or analytics field.

## Recovery Phrase

The mnemonic is shown only during wallet creation, restore, backup, or explicit key reveal flows. It must not enter logs, crash reports, analytics properties, screenshots, or debug bundles. Backup verification must happen before the app encourages meaningful deposits.

## Storage

Secrets belong in Keychain or encrypted Hawala backup files. Local caches may store balances, prices, transaction history, labels, and non-secret metadata only. Any migration that touches secrets must be backward-compatible and tested against old storage formats.

## Signing

Rust owns cryptographic signing. Swift may collect user intent, build review models, and call FFI, but private keys and signing payloads must stay out of production logs. Signing flows require local authentication before irreversible actions.

## Export And Backup

Private key reveal, seed reveal, and backup export require local authentication. Encrypted backups must use authenticated encryption, versioned file structure, and clear error handling for wrong passwords or corrupted files.

## Destruction

Factory wipe must remove Keychain secrets, local wallet metadata, pending sensitive state, and decrypted backup buffers. Decrypted memory should be held for the shortest practical time and zeroized where the underlying type supports it.

## Diagnostics

Diagnostics may include app version, OS version, feature flags, chain IDs, provider category, and sanitized error category. They must not include mnemonics, seeds, private keys, passcodes, raw backup data, API keys, or full request/response payloads.
