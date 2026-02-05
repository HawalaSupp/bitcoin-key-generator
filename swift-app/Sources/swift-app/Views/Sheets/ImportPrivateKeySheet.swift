import SwiftUI

/// Sheet for importing a private key for a specific chain
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
        NavigationStack {
            Form {
                Section(header: Text("Import Private Key")) {
                    Text("⚠️ Only import private keys you trust. Never share your private keys with anyone.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    
                    Picker("Chain", selection: $selectedChain) {
                        ForEach(supportedChains, id: \.0) { chain in
                            Text(chain.1).tag(chain.0)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Private Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if let format = supportedChains.first(where: { $0.0 == selectedChain })?.2 {
                            Text("Format: \(format)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        
                        TextEditor(text: $privateKeyInput)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 100)
                            .border(Color.secondary.opacity(0.3))
                    }
                    
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                
                Section {
                    Text("Supported formats:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("• Bitcoin/Litecoin: WIF format (starts with K, L, or 5)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    
                    Text("• Ethereum: 64 hex characters (with or without 0x)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .navigationTitle("Import Private Key")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        importAction()
                    }
                    .disabled(privateKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
    }
    
    private func importAction() {
        let trimmed = privateKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            errorMessage = "Private key cannot be empty"
            return
        }
        
        // Basic validation
        if selectedChain == "bitcoin" || selectedChain == "bitcoin-testnet" || selectedChain == "litecoin" {
            // WIF format validation
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
