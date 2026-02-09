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
        NavigationStack {
            Form {
                Section(header: Text(mode.title)) {
                    Text(mode.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    SecureField("Passphrase", text: $password)
                        .textContentType(.password)

                    if mode.requiresConfirmation {
                        SecureField("Confirm passphrase", text: $confirmation)
                            .textContentType(.password)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.actionTitle) {
                        confirmAction()
                    }
                    .disabled(password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 360, minHeight: mode.requiresConfirmation ? 280 : 240)
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
