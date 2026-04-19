import SwiftUI

/// Sheet for importing a private key for a specific chain — Hawala glass design
struct ImportPrivateKeySheet: View {
    let onImport: (String, String) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var privateKeyInput = ""
    @State private var selectedChain = "bitcoin"
    @State private var errorMessage: String?

    private let supportedChains = [
        ("bitcoin", "Bitcoin (WIF)", "bc1..."),
        ("bitcoin-testnet", "Bitcoin Testnet (WIF)", "tb1..."),
        ("ethereum", "Ethereum (Hex)", "0x..."),
        ("litecoin", "Litecoin (WIF)", "ltc1..."),
    ]

    var body: some View {
        HawalaSheetShell(title: "Import Private Key", width: 460, height: 480) {

            // Warning
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11))
                Text("Only import private keys you trust. Never share them.")
                    .font(.system(size: 11))
            }
            .foregroundColor(Color(red: 1, green: 0.84, blue: 0.04).opacity(0.7))
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color(red: 1, green: 0.84, blue: 0.04).opacity(0.06))
            .cornerRadius(8)

            // Chain selector + Key input
            VStack(spacing: 14) {
                HawalaOverlaySectionHeader(icon: "link", title: "Chain")

                HStack(spacing: 8) {
                    ForEach(supportedChains, id: \.0) { chain in
                        Button(action: { selectedChain = chain.0 }) {
                            Text(chain.1.components(separatedBy: " ").first ?? chain.1)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(selectedChain == chain.0
                                    ? Color.white.opacity(0.5)
                                    : .white.opacity(0.4))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selectedChain == chain.0
                                    ? Color.white.opacity(0.15)
                                    : Color.white.opacity(0.04))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(selectedChain == chain.0
                                            ? Color.white.opacity(0.3)
                                            : Color.white.opacity(0.06), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let format = supportedChains.first(where: { $0.0 == selectedChain })?.2 {
                    HawalaInfoRow(icon: "info.circle", text: "Format: \(format)", color: .white.opacity(0.3))
                }

                // Key text area
                TextEditor(text: $privateKeyInput)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80, maxHeight: 120)
                    .padding(12)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )

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

            // Supported formats
            VStack(spacing: 6) {
                HawalaOverlaySectionHeader(icon: "doc.text", title: "Supported Formats")
                HawalaInfoRow(icon: "bitcoinsign.circle", text: "Bitcoin/Litecoin: WIF (starts with K, L, or 5)", color: .white.opacity(0.35))
                HawalaInfoRow(icon: "number", text: "Ethereum: 64 hex characters (with or without 0x)", color: .white.opacity(0.35))
            }
            .hawalaSectionCard()

            // Actions
            HStack(spacing: 12) {
                HawalaActionButton(icon: "xmark", label: "Cancel", style: .secondary) {
                    onCancel()
                    dismiss()
                }
                HawalaActionButton(icon: "square.and.arrow.down", label: "Import", style: .primary) {
                    importAction()
                }
            }
        }
    }

    private func importAction() {
        let trimmed = privateKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            errorMessage = "Private key cannot be empty"
            return
        }

        if selectedChain == "bitcoin" || selectedChain == "bitcoin-testnet" || selectedChain == "litecoin" {
            guard trimmed.count >= 51 && trimmed.count <= 52 else {
                errorMessage = "Invalid WIF format. Should be 51-52 characters."
                return
            }
            let firstChar = trimmed.prefix(1)
            guard firstChar == "K" || firstChar == "L" || firstChar == "5" else {
                errorMessage = "Invalid WIF format. Should start with K, L, or 5."
                return
            }
        } else if selectedChain == "ethereum" {
            var hexString = trimmed
            if hexString.hasPrefix("0x") {
                hexString = String(hexString.dropFirst(2))
            }
            guard hexString.count == 64 else {
                errorMessage = "Invalid Ethereum private key. Should be 64 hex characters."
                return
            }
            guard hexString.allSatisfy({ $0.isHexDigit }) else {
                errorMessage = "Invalid hex characters in private key."
                return
            }
        }

        errorMessage = nil
        onImport(trimmed, selectedChain)
        dismiss()
    }
}
