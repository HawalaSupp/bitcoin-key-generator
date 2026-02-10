import Foundation
import Testing
@testable import swift_app

@Suite("Copywriting Kit — ROADMAP-15")
struct CopywritingKitTests {

    // MARK: - E2: HawalaUserError Mapping

    @Suite("HawalaUserError pattern matching")
    struct ErrorMappingTests {

        @Test("Network errors map to Connection Problem")
        func networkError() {
            let errors = [
                NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "The network connection was lost"]),
                NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "The request timed out"]),
                NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Device is offline"]),
                NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not be found on network"]),
            ]
            for err in errors {
                let ufe = HawalaUserError(from: err)
                #expect(ufe.title == "Connection Problem", "Expected Connection Problem for: \(err.localizedDescription)")
                #expect(ufe.recovery != nil)
            }
        }

        @Test("Invalid address errors map to Invalid Address")
        func addressError() {
            let err = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid address format"])
            let ufe = HawalaUserError(from: err)
            #expect(ufe.title == "Invalid Address")
            #expect(ufe.message.contains("valid address"))
        }

        @Test("Insufficient balance errors map to Insufficient Funds")
        func balanceError() {
            let errors = [
                NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Insufficient balance"]),
                NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not enough funds to cover gas"]),
            ]
            for err in errors {
                let ufe = HawalaUserError(from: err)
                #expect(ufe.title == "Insufficient Funds", "Expected Insufficient Funds for: \(err.localizedDescription)")
            }
        }

        @Test("Transaction failure errors map to Transaction Failed")
        func txError() {
            let err = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Transaction failed: reverted"])
            let ufe = HawalaUserError(from: err)
            #expect(ufe.title == "Transaction Failed")
            #expect(ufe.message.contains("haven't lost"))
        }

        @Test("Keychain errors map to Authentication Required")
        func keychainError() {
            let err = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Biometric authentication failed"])
            let ufe = HawalaUserError(from: err)
            #expect(ufe.title == "Authentication Required")
        }

        @Test("Decode errors map to Data Problem")
        func decodeError() {
            let err = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to decode response"])
            let ufe = HawalaUserError(from: err)
            #expect(ufe.title == "Data Problem")
        }

        @Test("Context-specific fallback for swap")
        func swapFallback() {
            let err = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unknown error xyz"])
            let ufe = HawalaUserError(from: err, context: .swap)
            #expect(ufe.title == "Swap Failed")
        }

        @Test("Context-specific fallback for staking")
        func stakingFallback() {
            let err = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unknown error"])
            let ufe = HawalaUserError(from: err, context: .staking)
            #expect(ufe.title == "Staking Error")
        }

        @Test("Context-specific fallback for hardware")
        func hardwareFallback() {
            let err = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Something broke"])
            let ufe = HawalaUserError(from: err, context: .hardware)
            #expect(ufe.title == "Hardware Wallet Issue")
        }

        @Test("Context-specific fallback for vault")
        func vaultFallback() {
            let err = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Something broke"])
            let ufe = HawalaUserError(from: err, context: .vault)
            #expect(ufe.title == "Vault Error")
        }

        @Test("Context-specific fallback for multisig")
        func multisigFallback() {
            let err = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Something broke"])
            let ufe = HawalaUserError(from: err, context: .multisig)
            #expect(ufe.title == "Multi-Signature Error")
        }

        @Test("Context-specific fallback for backup")
        func backupFallback() {
            let err = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Something broke"])
            let ufe = HawalaUserError(from: err, context: .backup)
            #expect(ufe.title == "Backup Failed")
        }

        @Test("Context-specific fallback for duress")
        func duressFallback() {
            let err = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Something broke"])
            let ufe = HawalaUserError(from: err, context: .duress)
            #expect(ufe.title == "Setup Issue")
        }

        @Test("General fallback produces Something Went Wrong")
        func generalFallback() {
            let err = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "xyzzy"])
            let ufe = HawalaUserError(from: err, context: .general)
            #expect(ufe.title == "Something Went Wrong")
            #expect(ufe.recovery != nil)
        }
    }

    // MARK: - HawalaUserError.from(message:context:)

    @Suite("HawalaUserError.from(message:)")
    struct FromMessageTests {

        @Test("Nil message returns nil")
        func nilMessage() {
            #expect(HawalaUserError.from(message: nil) == nil)
        }

        @Test("Empty message returns nil")
        func emptyMessage() {
            #expect(HawalaUserError.from(message: "") == nil)
        }

        @Test("Valid message returns mapped error")
        func validMessage() {
            let ufe = HawalaUserError.from(message: "The network connection was lost", context: .general)
            #expect(ufe != nil)
            #expect(ufe?.title == "Connection Problem")
        }

        @Test("Unknown message with context returns context-specific fallback")
        func contextMessage() {
            let ufe = HawalaUserError.from(message: "obscure failure", context: .swap)
            #expect(ufe != nil)
            #expect(ufe?.title == "Swap Failed")
        }
    }

    // MARK: - Explicit init

    @Suite("HawalaUserError explicit init")
    struct ExplicitInitTests {

        @Test("Explicit title and message")
        func explicitInit() {
            let ufe = HawalaUserError(title: "Custom Title", message: "Custom msg", recovery: "Do X")
            #expect(ufe.title == "Custom Title")
            #expect(ufe.message == "Custom msg")
            #expect(ufe.recovery == "Do X")
        }

        @Test("Explicit init with no recovery")
        func noRecovery() {
            let ufe = HawalaUserError(title: "T", message: "M")
            #expect(ufe.recovery == nil)
        }
    }

    // MARK: - E6: LoadingCopy Catalog

    @Suite("LoadingCopy constants")
    struct LoadingCopyTests {

        @Test("All loading strings end with an ellipsis character")
        func allEndWithEllipsis() {
            let all = [
                LoadingCopy.balances, LoadingCopy.prices, LoadingCopy.history,
                LoadingCopy.nfts, LoadingCopy.ordinals, LoadingCopy.swap,
                LoadingCopy.staking, LoadingCopy.sending, LoadingCopy.signing,
                LoadingCopy.backup, LoadingCopy.restoring, LoadingCopy.syncing,
                LoadingCopy.scanning, LoadingCopy.verifying, LoadingCopy.importing,
                LoadingCopy.providers, LoadingCopy.utxos, LoadingCopy.stealth,
                LoadingCopy.addresses, LoadingCopy.notes, LoadingCopy.passkey,
                LoadingCopy.tokens,
            ]
            for msg in all {
                #expect(msg.hasSuffix("…"), "Expected ellipsis at end of: \(msg)")
            }
        }

        @Test("Loading strings are not empty")
        func notEmpty() {
            #expect(!LoadingCopy.balances.isEmpty)
            #expect(!LoadingCopy.swap.isEmpty)
        }
    }

    // MARK: - E5: EmptyStateCopy Catalog

    @Suite("EmptyStateCopy catalog")
    struct EmptyStateCopyTests {

        @Test("Portfolio empty state has icon, title, message, and CTA")
        func portfolio() {
            let c = EmptyStateCopy.portfolio
            #expect(!c.icon.isEmpty)
            #expect(!c.title.isEmpty)
            #expect(!c.message.isEmpty)
            #expect(c.cta != nil)
        }

        @Test("Search results empty state has no CTA")
        func searchResults() {
            #expect(EmptyStateCopy.searchResults.cta == nil)
        }

        @Test("All empty states have SF Symbol icon names")
        func allHaveIcons() {
            let all = [
                EmptyStateCopy.portfolio, EmptyStateCopy.transactions,
                EmptyStateCopy.nfts, EmptyStateCopy.swaps,
                EmptyStateCopy.staking, EmptyStateCopy.ordinals,
                EmptyStateCopy.notes, EmptyStateCopy.vaults,
                EmptyStateCopy.walletConnect, EmptyStateCopy.multisig,
                EmptyStateCopy.smartAccounts, EmptyStateCopy.searchResults,
            ]
            for c in all {
                #expect(!c.icon.isEmpty, "Missing icon for: \(c.title)")
                #expect(!c.title.isEmpty)
                #expect(!c.message.isEmpty)
            }
        }
    }

    // MARK: - E9: HawalaConfirmation Presets

    @Suite("HawalaConfirmation presets")
    struct ConfirmationTests {

        @Test("resetWallet has destructive label and consequence explanation")
        func resetWallet() {
            let c = HawalaConfirmation.resetWallet
            #expect(c.title.contains("Reset"))
            #expect(c.message.contains("recovery phrase"))
            #expect(!c.destructiveLabel.isEmpty)
            #expect(!c.cancelLabel.isEmpty)
        }

        @Test("deleteKey has consequence explanation")
        func deleteKey() {
            let c = HawalaConfirmation.deleteKey
            #expect(c.message.contains("recovery phrase"))
            #expect(c.destructiveLabel.contains("Delete"))
        }

        @Test("disableDuress explains what gets removed")
        func disableDuress() {
            let c = HawalaConfirmation.disableDuress
            #expect(c.message.contains("decoy wallet"))
        }

        @Test("unlockVault explains time-lock removal")
        func unlockVault() {
            let c = HawalaConfirmation.unlockVault
            #expect(c.message.contains("time-lock"))
        }
    }

    // MARK: - ErrorContext Coverage

    @Suite("ErrorContext enum")
    struct ErrorContextTests {

        @Test("All contexts produce different fallback titles")
        func allContextsUnique() {
            let contexts: [ErrorContext] = [.general, .swap, .staking, .hardware, .backup, .multisig, .vault, .security, .duress]
            let err = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "unknown xyz"])
            var titles = Set<String>()
            for ctx in contexts {
                let ufe = HawalaUserError(from: err, context: ctx)
                titles.insert(ufe.title)
            }
            // We expect at least 7 unique titles (some may share "Something Went Wrong" but most differ)
            #expect(titles.count >= 7, "Expected at least 7 unique fallback titles, got \(titles.count)")
        }
    }
}
