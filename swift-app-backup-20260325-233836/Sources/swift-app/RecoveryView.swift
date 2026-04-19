import SwiftUI

struct RecoveryView: View {
    @Binding var mnemonic: String
    @State private var isValid: Bool = false
    @State private var validationMessage: String = ""
    
    var onValidMnemonic: () -> Void
    var onCancel: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Restore from Recovery Phrase")
                .font(.title)
                .bold()
            
            Text("Enter your 12 or 24-word recovery phrase to restore your wallet.")
                .foregroundStyle(.secondary)
            
            TextEditor(text: $mnemonic)
                .font(.body)
                .frame(height: 120)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isValid ? Color.green : (mnemonic.isEmpty ? Color.gray.opacity(0.3) : Color.red), lineWidth: 1)
                )
                .onChange(of: mnemonic) { newValue in
                    validate(newValue)
                }
            
            if !validationMessage.isEmpty {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(isValid ? .green : .red)
            }
            
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Restore Wallet") {
                    onValidMnemonic()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .padding()
        .frame(width: 500)
    }
    
    private func validate(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            isValid = false
            validationMessage = ""
            return
        }
        
        // Basic word count check before FFI to avoid too many calls
        let wordCount = trimmed.split(separator: " ").count
        if wordCount != 12 && wordCount != 24 {
            isValid = false
            validationMessage = "Phrase must be 12 or 24 words (currently \(wordCount))"
            return
        }
        
        if RustService.shared.validateMnemonic(trimmed) {
            isValid = true
            validationMessage = "Valid recovery phrase"
        } else {
            isValid = false
            validationMessage = "Invalid recovery phrase or checksum"
        }
    }
}
