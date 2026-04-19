import SwiftUI

/// Security notice that users must acknowledge before generating keys
struct SecurityNoticeView: View {
    let onAcknowledge: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Handle generated keys securely", systemImage: "lock.shield")
                        .font(.title2)
                        .bold()

                    Text("This tool produces private keys, recovery secrets, and wallet addresses. Treat everything shown in the app as confidential. Anyone with access to these keys can spend the associated funds.")

                    Text("Best practices")
                        .font(.headline)

                    bulletPoint("Never screenshot or share keys in plain text.")
                    bulletPoint("Store backups encrypted and offline whenever possible.")
                    bulletPoint("Clear key material before stepping away from the device.")
                    bulletPoint("Consider using hardware wallets for long-term storage.")

                    Divider()

                    Text("By tapping 'I Understand', you acknowledge the security implications and accept responsibility for safeguarding any generated keys.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Security Notice")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("I Understand") {
                        onAcknowledge()
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 500, height: 600)
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.callout)
            Text(text)
        }
        .font(.body)
    }
}
