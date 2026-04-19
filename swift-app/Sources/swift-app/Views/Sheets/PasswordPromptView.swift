import SwiftUI

/// Password prompt for encrypted backup export/import and sensitive data access
struct PasswordPromptView: View {
    enum Mode {
        case export
        case `import`
        case privateKeyExport

        var title: String {
            switch self {
            case .export: return "Encrypt Backup"
            case .import: return "Unlock Backup"
            case .privateKeyExport: return "Export Private Keys"
            }
        }

        var actionTitle: String {
            switch self {
            case .export: return "Export"
            case .import: return "Import"
            case .privateKeyExport: return "Reveal Keys"
            }
        }

        var description: String {
            switch self {
            case .export:
                return "Choose a strong passphrase. You will need it to restore this backup later."
            case .import:
                return "Enter the passphrase that was used when this backup was created."
            case .privateKeyExport:
                return "Enter your wallet passphrase to reveal private keys. Never share these with anyone."
            }
        }

        var icon: String {
            switch self {
            case .export: return "lock.doc"
            case .import: return "lock.open.doc"
            case .privateKeyExport: return "key.viewfinder"
            }
        }

        var requiresConfirmation: Bool {
            self == .export
        }
    }

    let mode: Mode
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?

    var body: some View {
        HawalaSheetShell(title: mode.title, width: 380, height: mode.requiresConfirmation ? 380 : 340) {

            // Icon + description
            VStack(spacing: 12) {
                Image(systemName: mode.icon)
                    .font(.system(size: 28, weight: .thin))
                    .foregroundColor(Color.white.opacity(0.5))

                Text(mode.description)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            // Fields
            VStack(spacing: 12) {
                HawalaSecureField(placeholder: "Passphrase", text: $password)

                if mode.requiresConfirmation {
                    HawalaSecureField(placeholder: "Confirm passphrase", text: $confirmation)
                }

                if let errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 11))
                        Text(errorMessage)
                            .font(.system(size: 12))
                    }
                    .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23))
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .hawalaSectionCard()

            // Actions
            HStack(spacing: 12) {
                HawalaActionButton(icon: "xmark", label: "Cancel", style: .secondary) {
                    onCancel()
                    dismiss()
                }
                HawalaActionButton(icon: "checkmark", label: mode.actionTitle, style: .primary) {
                    confirmAction()
                }
            }
        }
    }

    private func confirmAction() {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else {
            errorMessage = "Use at least 8 characters."
            return
        }

        if mode.requiresConfirmation {
            let confirmTrimmed = confirmation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed == confirmTrimmed else {
                errorMessage = "Passphrases do not match."
                return
            }
        }

        errorMessage = nil
        onConfirm(trimmed)
        dismiss()
    }
}
