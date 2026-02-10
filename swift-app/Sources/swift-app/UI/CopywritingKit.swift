import SwiftUI

// MARK: - ROADMAP-15: Copywriting & Microcopy Kit
// Centralised error mapping, loading messages, and dialog helpers.

// ─────────────────────────────────────────────
// MARK: - E2: User-Facing Error Mapping
// ─────────────────────────────────────────────

/// Wraps any underlying error with a human-readable title, body and optional
/// recovery action. Every `.alert("Error")` in the app should migrate to
/// `.hawalaErrorAlert(…)` which pulls copy from this type.
struct HawalaUserError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let recovery: String?

    /// Create from a raw `Error`, mapping common cases to friendly copy.
    init(from error: Error, context: ErrorContext = .general) {
        let desc = error.localizedDescription.lowercased()

        // Network / connectivity
        if desc.contains("network") || desc.contains("connection")
            || desc.contains("timed out") || desc.contains("offline")
            || desc.contains("could not be found") || desc.contains("not connected") {
            self.title = "Connection Problem"
            self.message = "Can't reach the network right now."
            self.recovery = "Check your connection and try again."
            return
        }

        // Address validation
        if desc.contains("invalid address") || desc.contains("address") && desc.contains("invalid") {
            self.title = "Invalid Address"
            self.message = "This doesn't look like a valid address."
            self.recovery = "Check for typos and try again."
            return
        }

        // Insufficient balance / funds
        if desc.contains("insufficient") || desc.contains("not enough") || desc.contains("balance") && desc.contains("low") {
            self.title = "Insufficient Funds"
            self.message = "You don't have enough funds for this transaction (including fees)."
            self.recovery = "Reduce the amount or add more funds."
            return
        }

        // Transaction failure
        if desc.contains("transaction failed") || desc.contains("tx failed") || desc.contains("reverted") {
            self.title = "Transaction Failed"
            self.message = "The transaction couldn't be completed. You haven't lost any funds."
            self.recovery = "Review the details and try again."
            return
        }

        // Keychain / auth
        if desc.contains("keychain") || desc.contains("biometric") || desc.contains("authentication") {
            self.title = "Authentication Required"
            self.message = "We couldn't verify your identity."
            self.recovery = "Try again or use your passcode."
            return
        }

        // Decoding / parsing
        if desc.contains("decode") || desc.contains("parse") || desc.contains("unexpected format") {
            self.title = "Data Problem"
            self.message = "Something went wrong reading data."
            self.recovery = "Try again. If the problem persists, contact support."
            return
        }

        // Context-specific fallback
        switch context {
        case .swap:
            self.title = "Swap Failed"
            self.message = "We couldn't complete the swap."
            self.recovery = "Check your balance and try again."
        case .staking:
            self.title = "Staking Error"
            self.message = "Something went wrong with staking."
            self.recovery = "Verify your stake amount and try again."
        case .hardware:
            self.title = "Hardware Wallet Issue"
            self.message = "Communication with the hardware wallet failed."
            self.recovery = "Reconnect your device and try again."
        case .backup:
            self.title = "Backup Failed"
            self.message = "We couldn't complete the backup."
            self.recovery = "Make sure you have enough storage and try again."
        case .multisig:
            self.title = "Multi-Signature Error"
            self.message = "Something went wrong with the multi-sig operation."
            self.recovery = "Verify all signers are available and try again."
        case .vault:
            self.title = "Vault Error"
            self.message = "Something went wrong with the time-locked vault."
            self.recovery = "Check vault parameters and try again."
        case .security:
            self.title = "Security Alert"
            self.message = error.localizedDescription
            self.recovery = "Review your security settings."
        case .duress:
            self.title = "Setup Issue"
            self.message = "Something went wrong during setup."
            self.recovery = "Try again from the beginning."
        case .general:
            self.title = "Something Went Wrong"
            self.message = "An unexpected error occurred."
            self.recovery = "Try again. If the problem persists, contact support."
        }
    }

    /// Create with explicit copy (for non-Error strings).
    init(title: String, message: String, recovery: String? = nil) {
        self.title = title
        self.message = message
        self.recovery = recovery
    }

    /// Convert a raw errorMessage string into a HawalaUserError.
    static func from(message: String?, context: ErrorContext = .general) -> HawalaUserError? {
        guard let msg = message, !msg.isEmpty else { return nil }
        // Wrap the string in an NSError so the pattern-matching works
        let wrapped = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: msg])
        return HawalaUserError(from: wrapped, context: context)
    }
}

/// Categorises where an error occurred so the fallback copy is relevant.
enum ErrorContext {
    case general, swap, staking, hardware, backup, multisig, vault, security, duress
}

// ─────────────────────────────────────────────
// MARK: - E3: Hawala Error Alert Modifier
// ─────────────────────────────────────────────

/// Drop-in replacement for `.alert("Error", …) { Button("OK") … }`.
/// Shows human-readable title + body + recovery suggestion.
struct HawalaErrorAlertModifier: ViewModifier {
    @Binding var error: HawalaUserError?

    func body(content: Content) -> some View {
        content
            .alert(
                error?.title ?? "Something Went Wrong",
                isPresented: Binding(
                    get: { error != nil },
                    set: { if !$0 { error = nil } }
                )
            ) {
                Button("Dismiss") { error = nil }
            } message: {
                if let err = error {
                    VStack {
                        Text(err.message)
                        if let recovery = err.recovery {
                            Text(recovery)
                        }
                    }
                }
            }
    }
}

extension View {
    /// Replaces bare `.alert("Error")` patterns with human-readable copy.
    func hawalaErrorAlert(_ error: Binding<HawalaUserError?>) -> some View {
        modifier(HawalaErrorAlertModifier(error: error))
    }
}

// ─────────────────────────────────────────────
// MARK: - E6: Contextual Loading View
// ─────────────────────────────────────────────

/// A themed loading spinner with a context-specific message.
/// Replaces bare `ProgressView()` throughout the app.
struct HawalaLoadingView: View {
    let message: String

    init(_ message: String = "Loading…") {
        self.message = message
    }

    var body: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(0.9)

            Text(message)
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

// ─────────────────────────────────────────────
// MARK: - E6: Loading Message Catalog
// ─────────────────────────────────────────────

/// Context-specific loading messages replacing generic "Loading…"
enum LoadingCopy {
    static let balances      = "Fetching your balances…"
    static let prices        = "Getting latest prices…"
    static let history       = "Loading your activity…"
    static let nfts          = "Loading your collection…"
    static let ordinals      = "Scanning for inscriptions…"
    static let swap          = "Finding best rates…"
    static let staking       = "Loading validators…"
    static let sending       = "Preparing transaction…"
    static let signing       = "Signing transaction…"
    static let backup        = "Preparing backup…"
    static let restoring     = "Restoring your wallet…"
    static let syncing       = "Syncing with network…"
    static let scanning      = "Scanning for devices…"
    static let verifying     = "Verifying address…"
    static let importing     = "Importing wallet…"
    static let providers     = "Checking providers…"
    static let utxos         = "Loading coin selection…"
    static let stealth       = "Scanning stealth payments…"
    static let addresses     = "Analyzing address…"
    static let notes         = "Loading transaction notes…"
    static let passkey       = "Verifying identity…"
    static let tokens        = "Searching for token…"
}

// ─────────────────────────────────────────────
// MARK: - E5: Empty State Copy Catalog
// ─────────────────────────────────────────────

/// Consistent empty state copy with CTAs, used by EmptyStateView / HawalaEmptyState.
enum EmptyStateCopy {
    struct Content {
        let icon: String
        let title: String
        let message: String
        let cta: String?
    }

    static let portfolio = Content(
        icon: "wallet.bifold",
        title: "Your Wallet Is Empty",
        message: "Buy or receive crypto to get started.",
        cta: "Receive Crypto"
    )

    static let transactions = Content(
        icon: "clock.arrow.circlepath",
        title: "No Activity Yet",
        message: "Send or receive crypto to see your transaction history here.",
        cta: nil
    )

    static let nfts = Content(
        icon: "photo.on.rectangle.angled",
        title: "No NFTs Yet",
        message: "Buy your first NFT or receive one from a friend.",
        cta: nil
    )

    static let swaps = Content(
        icon: "arrow.triangle.swap",
        title: "No Swaps Yet",
        message: "Exchange tokens to see your swap history here.",
        cta: "Start a Swap"
    )

    static let staking = Content(
        icon: "chart.bar.fill",
        title: "Nothing Staked Yet",
        message: "Stake your tokens to earn rewards.",
        cta: "Explore Validators"
    )

    static let ordinals = Content(
        icon: "bitcoinsign.circle",
        title: "No Inscriptions Found",
        message: "Your Bitcoin ordinals and inscriptions will appear here.",
        cta: nil
    )

    static let notes = Content(
        icon: "note.text",
        title: "No Notes Yet",
        message: "Add notes to your transactions for easy reference.",
        cta: nil
    )

    static let vaults = Content(
        icon: "lock.shield",
        title: "No Vaults Yet",
        message: "Create a time-locked vault to protect your funds.",
        cta: "Create Vault"
    )

    static let walletConnect = Content(
        icon: "link.circle",
        title: "No Connected dApps",
        message: "Scan a WalletConnect QR code to connect to a dApp.",
        cta: "Connect dApp"
    )

    static let multisig = Content(
        icon: "person.2.circle",
        title: "No Multi-Sig Wallets",
        message: "Set up a multi-signature wallet for shared custody.",
        cta: "Create Multi-Sig"
    )

    static let smartAccounts = Content(
        icon: "cpu",
        title: "No Smart Accounts",
        message: "Create a smart account for advanced features like gas sponsorship.",
        cta: "Create Smart Account"
    )

    static let searchResults = Content(
        icon: "magnifyingglass",
        title: "No Results",
        message: "Try a different search term.",
        cta: nil
    )
}

// ─────────────────────────────────────────────
// MARK: - E9: Confirmation Dialog Helper
// ─────────────────────────────────────────────

/// Standard confirmation dialog with consequence explanation.
struct HawalaConfirmation {
    let title: String
    let message: String
    let destructiveLabel: String
    let cancelLabel: String

    static let resetWallet = HawalaConfirmation(
        title: "Reset Wallet?",
        message: "This will delete all wallet data from this device. Make sure you have your recovery phrase backed up — without it, your funds will be permanently lost.",
        destructiveLabel: "Reset Everything",
        cancelLabel: "Keep Wallet"
    )

    static let deleteKey = HawalaConfirmation(
        title: "Delete Key Pair?",
        message: "This key pair will be permanently removed from this device. Make sure you have the recovery phrase backed up before proceeding.",
        destructiveLabel: "Delete Key Pair",
        cancelLabel: "Keep Key"
    )

    static let disableDuress = HawalaConfirmation(
        title: "Disable Duress Protection?",
        message: "The decoy wallet and its passcode will be removed. You can set it up again later.",
        destructiveLabel: "Disable Protection",
        cancelLabel: "Keep Enabled"
    )

    static let unlockVault = HawalaConfirmation(
        title: "Unlock This Vault?",
        message: "Once unlocked, the time-lock protection will be removed and funds will become immediately accessible.",
        destructiveLabel: "Unlock Vault",
        cancelLabel: "Keep Locked"
    )
}
