import SwiftUI

/// Comprehensive security settings including passcode, biometrics, and advanced features
struct SecuritySettingsView: View {
    let hasPasscode: Bool
    let onSetPasscode: (String) -> Void
    let onRemovePasscode: () -> Void
    let biometricState: BiometricState
    @Binding var biometricEnabled: Bool
    @Binding var biometricForSends: Bool
    @Binding var biometricForKeyReveal: Bool
    @Binding var autoLockSelection: AutoLockIntervalOption
    let onBiometricRequest: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var passcode = ""
    @State private var confirmPasscode = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Session Lock")) {
                    if hasPasscode {
                        Text("A passcode is currently required to unlock key material. You can remove it below or set a new one.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            onRemovePasscode()
                            dismiss()
                        } label: {
                            Label("Remove Passcode", systemImage: "lock.open")
                        }
                    } else {
                        Text("Add a passcode to require unlocking before any key data is shown. This clears keys when the app goes to the background.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(header: Text("Set New Passcode")) {
                    SecureField("New passcode", text: $passcode)
                        .textContentType(.password)
                    SecureField("Confirm passcode", text: $confirmPasscode)
                        .textContentType(.password)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button {
                        validateAndSave()
                    } label: {
                        Label("Save Passcode", systemImage: "lock")
                    }
                    .disabled(passcode.isEmpty || confirmPasscode.isEmpty)
                }

                Section(header: Text("Biometric Unlock")) {
                    Text(biometricState.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if biometricState.supportsUnlock {
                        Toggle(isOn: $biometricEnabled) {
                            Label("Enable \(biometricLabel)", systemImage: biometricIcon)
                        }
                        .disabled(!hasPasscode)

                        if !hasPasscode {
                            Text("Set a passcode to turn on biometrics.")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        } else if biometricEnabled {
                            Button {
                                onBiometricRequest()
                            } label: {
                                Label("Test \(biometricLabel)", systemImage: "hand.raised.fill")
                            }
                        }
                    }
                }
                
                if BiometricAuthHelper.isBiometricAvailable {
                    Section(header: Text("Biometric Protection")) {
                        Toggle(isOn: $biometricForSends) {
                            Label("Require for Sends", systemImage: "paperplane.fill")
                        }
                        
                        Toggle(isOn: $biometricForKeyReveal) {
                            Label("Require for Key Reveal", systemImage: "key.fill")
                        }
                        
                        Text("When enabled, \(biometricLabel) will be required before sending funds or viewing private keys.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(header: Text("Auto-Lock Timer")) {
                    Picker("Auto-lock after", selection: $autoLockSelection) {
                        ForEach(AutoLockIntervalOption.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .disabled(!hasPasscode)

                    Text(autoLockSelection.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !hasPasscode {
                        Text("Auto-lock requires a passcode so there's something to lock to.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                
                // Duress Protection Section
                Section(header: Text("Duress Protection")) {
                    DuressProtectionRow(hasPasscode: hasPasscode)
                }
                
                // Inheritance Protocol Section
                Section(header: Text("Inheritance Protocol")) {
                    InheritanceProtocolRow()
                }
                
                // Geographic Security Section
                Section(header: Text("Location Security")) {
                    GeographicSecurityRow()
                }
                
                // Social Recovery Section
                Section(header: Text("Social Recovery")) {
                    SocialRecoveryRow()
                }
            }
            .navigationTitle("Security Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(width: 420, height: 750)
    }

    private func validateAndSave() {
        let trimmed = passcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else {
            errorMessage = "Choose at least 6 characters."
            return
        }
        guard trimmed == confirmPasscode.trimmingCharacters(in: .whitespacesAndNewlines) else {
            errorMessage = "Passcodes do not match."
            return
        }
        errorMessage = nil
        onSetPasscode(trimmed)
        dismiss()
    }

    private var biometricLabel: String {
        if case .available(let kind) = biometricState {
            return kind.displayName
        }
        return "Biometrics"
    }

    private var biometricIcon: String {
        if case .available(let kind) = biometricState {
            return kind.iconName
        }
        return "lock.circle"
    }
}

// MARK: - Duress Protection Row

struct DuressProtectionRow: View {
    let hasPasscode: Bool
    @StateObject private var duressManager = DuressWalletManager.shared
    @State private var showDuressSetup = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: duressManager.isConfigured ? "shield.checkered" : "exclamationmark.shield")
                    .foregroundColor(duressManager.isConfigured ? .green : .orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Duress PIN")
                        .font(.body)
                    
                    Text(duressManager.isConfigured ? "Protected with decoy wallet" : "Not configured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(duressManager.isConfigured ? "Manage" : "Set Up") {
                    showDuressSetup = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasPasscode)
            }
            
            if !hasPasscode {
                Text("Set a passcode first to enable duress protection.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else {
                Text("Create a secondary PIN that opens a decoy wallet with minimal funds. Use in coercion scenarios for plausible deniability.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            
            // Show duress mode indicator (only visible in real mode)
            if duressManager.isInDuressMode {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("Currently in duress mode")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.top, 4)
            }
        }
        .sheet(isPresented: $showDuressSetup) {
            DuressSetupView()
        }
    }
}

// MARK: - Inheritance Protocol Row

struct InheritanceProtocolRow: View {
    @StateObject private var manager = DeadMansSwitchManager.shared
    @State private var showInheritanceSetup = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: manager.isConfigured ? "person.2.badge.gearshape.fill" : "person.2.badge.gearshape")
                    .foregroundColor(manager.isConfigured ? .green : .blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dead Man's Switch")
                        .font(.body)
                    
                    if manager.isConfigured {
                        Text("\(manager.daysUntilTrigger ?? 0) days until trigger")
                            .font(.caption)
                            .foregroundColor(manager.warningLevel == .critical ? .red : 
                                           manager.warningLevel == .warning ? .orange : .secondary)
                    } else {
                        Text("Not configured")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if manager.isConfigured && manager.warningLevel != .none {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(manager.warningLevel == .critical ? .red : .orange)
                }
                
                Button(manager.isConfigured ? "Manage" : "Set Up") {
                    showInheritanceSetup = true
                }
                .buttonStyle(.borderedProminent)
            }
            
            Text("Automatically transfer funds to designated heirs after a period of inactivity. Trustless inheritance using blockchain timelocks.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showInheritanceSetup) {
            DeadMansSwitchView()
        }
    }
}

// MARK: - Geographic Security Row

struct GeographicSecurityRow: View {
    @StateObject private var manager = GeographicSecurityManager.shared
    @State private var showGeoSecurity = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: manager.isEnabled ? "location.shield.fill" : "location.slash")
                    .font(.title2)
                    .foregroundStyle(manager.isEnabled ? .blue : .secondary)
                
                VStack(alignment: .leading) {
                    Text("Geographic Security")
                        .font(.headline)
                    
                    if manager.travelModeActive {
                        Text("Travel Mode Active")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if manager.isEnabled {
                        Text("\(manager.trustedZones.count) trusted zone(s)")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("Location protection disabled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button(manager.isEnabled ? "Manage" : "Enable") {
                    showGeoSecurity = true
                }
                .buttonStyle(.borderedProminent)
            }
            
            Text("Restrict wallet access based on geographic location. Set trusted zones, enable travel mode, and add location-based transaction limits.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showGeoSecurity) {
            GeographicSecurityView()
        }
    }
}

// MARK: - Social Recovery Row

struct SocialRecoveryRow: View {
    @StateObject private var multisigManager = MultisigManager.shared
    @State private var showSocialRecovery = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.3.fill")
                    .font(.title2)
                    .foregroundStyle(.purple)
                
                VStack(alignment: .leading) {
                    Text("Social Recovery")
                        .font(.headline)
                    
                    if !multisigManager.wallets.isEmpty {
                        Text("\(multisigManager.wallets.count) multisig wallet(s)")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("No multisig wallets configured")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button("Configure") {
                    showSocialRecovery = true
                }
                .buttonStyle(.borderedProminent)
            }
            
            Text("Use trusted guardians to help recover your wallet if you lose access. Add friends, family, or hardware keys as recovery partners.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showSocialRecovery) {
            SocialRecoveryView()
        }
    }
}
