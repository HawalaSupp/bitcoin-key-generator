import SwiftUI

/// Settings view for configuring duress/decoy wallet
struct DuressSettingsView: View {
    @ObservedObject private var duressManager = DuressManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var showSetupSheet = false
    @State private var showChangePasscodeSheet = false
    @State private var showDisableConfirmation = false
    @State private var showPanicWipeConfirmation = false
    @State private var errorMessage: String?
    
    var body: some View {
        Form {
            // MARK: - Status Section
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Duress Protection")
                            .font(.headline)
                        Text(duressManager.isDuressEnabled ? "Active" : "Not Configured")
                            .font(.caption)
                            .foregroundColor(duressManager.isDuressEnabled ? .green : .secondary)
                    }
                    
                    Spacer()
                    
                    if duressManager.isDuressEnabled {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "shield.slash")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Label("Status", systemImage: "shield.lefthalf.filled")
            }
            
            // MARK: - What is Duress Mode
            Section {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        infoRow(icon: "eye.slash", title: "Decoy Wallet", description: "A separate wallet with its own funds that opens when you enter the decoy passcode.")
                        
                        infoRow(icon: "lock.shield", title: "Plausible Deniability", description: "No way to detect the real wallet exists when in decoy mode.")
                        
                        infoRow(icon: "hand.raised", title: "Coercion Protection", description: "Under duress, enter the decoy passcode to show the decoy wallet instead.")
                        
                        infoRow(icon: "exclamationmark.triangle", title: "Important", description: "Keep small amounts in your decoy wallet to make it believable.")
                    }
                    .padding(.vertical, 8)
                } label: {
                    Label("What is Duress Mode?", systemImage: "questionmark.circle")
                }
            }
            
            // MARK: - Setup/Configuration
            Section {
                if !duressManager.isDuressEnabled {
                    Button(action: { showSetupSheet = true }) {
                        Label("Set Up Decoy Wallet", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: { showChangePasscodeSheet = true }) {
                        Label("Change Decoy Passcode", systemImage: "key")
                    }
                    
                    Button(role: .destructive, action: { showDisableConfirmation = true }) {
                        Label("Disable Duress Protection", systemImage: "trash")
                    }
                }
            } header: {
                Label("Configuration", systemImage: "gearshape")
            }
            
            // MARK: - Emergency Actions (only when enabled)
            if duressManager.isDuressEnabled {
                Section {
                    Button(role: .destructive, action: { showPanicWipeConfirmation = true }) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("Emergency Wipe")
                            Spacer()
                            Text("Destroys real wallet")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .disabled(!duressManager.isInDecoyMode)
                } header: {
                    Label("Emergency", systemImage: "exclamationmark.octagon")
                } footer: {
                    Text("Emergency wipe is only available when in decoy mode. This permanently destroys the real wallet.")
                        .foregroundColor(.red)
                }
            }
            
            // MARK: - Tips
            Section {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        tipRow(text: "Use a passcode you can remember under stress")
                        tipRow(text: "Keep a believable amount in your decoy wallet")
                        tipRow(text: "Practice switching between wallets")
                        tipRow(text: "The decoy passcode should be similar but different")
                        tipRow(text: "Never reveal that duress mode exists")
                    }
                    .padding(.vertical, 8)
                } label: {
                    Label("Tips", systemImage: "lightbulb")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Duress Protection")
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Disable Duress Protection?", isPresented: $showDisableConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Disable", role: .destructive) {
                duressManager.disableDuress()
            }
        } message: {
            Text("This will remove the decoy wallet and its passcode. You can set it up again later.")
        }
        .alert("Emergency Wipe", isPresented: $showPanicWipeConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("WIPE REAL WALLET", role: .destructive) {
                duressManager.panicWipeRealWallet()
            }
        } message: {
            Text("⚠️ THIS CANNOT BE UNDONE ⚠️\n\nThis will permanently destroy your real wallet. Only use this in extreme emergency situations.")
        }
        .sheet(isPresented: $showSetupSheet) {
            DuressSetupSheet(onComplete: { showSetupSheet = false })
        }
        .sheet(isPresented: $showChangePasscodeSheet) {
            DuressChangePasscodeSheet(onComplete: { showChangePasscodeSheet = false })
        }
    }
    
    @ViewBuilder
    private func infoRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func tipRow(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Setup Sheet

struct DuressSetupSheet: View {
    let onComplete: () -> Void
    
    @ObservedObject private var duressManager = DuressManager.shared
    @AppStorage("hawala.passcodeHash") private var realPasscodeHash: String?
    
    @State private var passcode = ""
    @State private var confirmPasscode = ""
    @State private var errorMessage: String?
    @State private var step = 1
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Progress indicator
                HStack(spacing: 8) {
                    ForEach(1...3, id: \.self) { i in
                        Circle()
                            .fill(i <= step ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                
                Spacer()
                
                switch step {
                case 1:
                    introView
                case 2:
                    passcodeEntryView
                case 3:
                    confirmationView
                default:
                    EmptyView()
                }
                
                Spacer()
                
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .padding()
            .frame(width: 400, height: 450)
            .navigationTitle("Set Up Decoy Wallet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private var introView: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Duress Protection")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Create a decoy wallet that opens with a separate passcode. Use it to protect your real funds under coercion.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Continue") {
                withAnimation { step = 2 }
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var passcodeEntryView: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            
            Text("Create Decoy Passcode")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Enter a passcode for your decoy wallet. This must be different from your real passcode.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            SecureField("Decoy Passcode", text: $passcode)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
            
            SecureField("Confirm Passcode", text: $confirmPasscode)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
            
            Button("Set Passcode") {
                validateAndProceed()
            }
            .buttonStyle(.borderedProminent)
            .disabled(passcode.isEmpty || passcode != confirmPasscode)
        }
    }
    
    private var confirmationView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("Decoy Wallet Created!")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Your decoy wallet is now active. Enter your decoy passcode at unlock to access it.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 8) {
                Label("Remember to add some funds to make it believable", systemImage: "exclamationmark.triangle")
                Label("Never reveal that you have a decoy wallet", systemImage: "eye.slash")
            }
            .font(.caption)
            .foregroundColor(.orange)
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
            
            Button("Done") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private func validateAndProceed() {
        errorMessage = nil
        
        guard passcode == confirmPasscode else {
            errorMessage = "Passcodes don't match"
            return
        }
        
        guard passcode.count >= 4 else {
            errorMessage = "Passcode must be at least 4 characters"
            return
        }
        
        do {
            try duressManager.setupDecoyWallet(passcode: passcode, realPasscodeHash: realPasscodeHash)
            withAnimation { step = 3 }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Change Passcode Sheet

struct DuressChangePasscodeSheet: View {
    let onComplete: () -> Void
    
    @ObservedObject private var duressManager = DuressManager.shared
    @AppStorage("hawala.passcodeHash") private var realPasscodeHash: String?
    
    @State private var oldPasscode = ""
    @State private var newPasscode = ""
    @State private var confirmPasscode = ""
    @State private var errorMessage: String?
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Current Decoy Passcode", text: $oldPasscode)
                } header: {
                    Text("Current Passcode")
                }
                
                Section {
                    SecureField("New Decoy Passcode", text: $newPasscode)
                    SecureField("Confirm New Passcode", text: $confirmPasscode)
                } header: {
                    Text("New Passcode")
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
                
                Section {
                    Button("Change Passcode") {
                        changePasscode()
                    }
                    .disabled(oldPasscode.isEmpty || newPasscode.isEmpty || newPasscode != confirmPasscode)
                }
            }
            .formStyle(.grouped)
            .frame(width: 350, height: 350)
            .navigationTitle("Change Decoy Passcode")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func changePasscode() {
        errorMessage = nil
        
        guard newPasscode == confirmPasscode else {
            errorMessage = "New passcodes don't match"
            return
        }
        
        do {
            try duressManager.changeDecoyPasscode(oldPasscode: oldPasscode, newPasscode: newPasscode, realPasscodeHash: realPasscodeHash)
            onComplete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    NavigationStack {
        DuressSettingsView()
    }
    .frame(width: 500, height: 700)
}
#endif
#endif
#endif
