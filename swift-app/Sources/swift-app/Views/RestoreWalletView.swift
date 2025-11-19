import SwiftUI

struct RestoreWalletView: View {
    @Binding var isPresented: Bool
    var onRestore: (String) async -> Void
    
    @State private var mnemonicText: String = ""
    @State private var errorMessage: String?
    @State private var isRestoring = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Restore Wallet")
                .font(.headline)
                .padding(.top)
            
            Text("Enter your 12 or 24-word recovery phrase to restore your wallet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            TextEditor(text: $mnemonicText)
                .font(.body)
                .frame(height: 120)
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal)
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            
            HStack(spacing: 16) {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Button {
                    Task {
                        await validateAndRestore()
                    }
                } label: {
                    if isRestoring {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Restore")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(mnemonicText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRestoring)
            }
            .padding(.bottom)
        }
        .frame(width: 500)
        .padding()
    }
    
    private func validateAndRestore() async {
        let cleanMnemonic = mnemonicText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
        
        let wordCount = cleanMnemonic.split(separator: " ").count
        
        guard wordCount == 12 || wordCount == 24 else {
            errorMessage = "Invalid word count: \(wordCount). Please enter 12 or 24 words."
            return
        }
        
        isRestoring = true
        errorMessage = nil
        
        await onRestore(cleanMnemonic)
        
        isRestoring = false
        isPresented = false
    }
}
