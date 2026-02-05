import SwiftUI

/// Sheet for unlocking the app with passcode or biometrics
struct UnlockView: View {
    let supportsBiometrics: Bool
    let biometricButtonLabel: String
    let biometricButtonIcon: String
    let onBiometricRequest: () -> Void
    let onSubmit: (String) -> String?
    let onCancel: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var passcode = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Unlock Session")
                    .font(.title3)
                    .bold()
                Text("Enter the passcode you set in Security Settings to reveal the generated key material.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                SecureField("Passcode", text: $passcode)
                    .textContentType(.password)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if supportsBiometrics {
                    Button {
                        onBiometricRequest()
                    } label: {
                        Label("Unlock with \(biometricButtonLabel)", systemImage: biometricButtonIcon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }

                HStack {
                    Button("Cancel", role: .cancel) {
                        onCancel()
                        dismiss()
                    }
                    Spacer()
                    Button("Unlock") {
                        let message = onSubmit(passcode)
                        if let message {
                            errorMessage = message
                            passcode = ""
                        } else {
                            errorMessage = nil
                            passcode = ""
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(minWidth: 360, minHeight: 220)
    }
}
