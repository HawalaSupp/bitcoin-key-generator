import SwiftUI

// MARK: - Duress Setup View

/// Comprehensive UI for setting up duress PIN and decoy wallet
struct DuressSetupView: View {
    @StateObject private var duressManager = DuressWalletManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentStep: SetupStep = .intro
    @State private var duressPin = ""
    @State private var confirmPin = ""
    @State private var realPin = ""
    @State private var showRealPinField = false
    @State private var config = DecoyWalletConfig()
    @State private var emergencyContact = EmergencyContact()
    @State private var silentAlertEnabled = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @State private var showDeleteConfirmation = false
    
    enum SetupStep: Int, CaseIterable {
        case intro
        case setPin
        case decoyWallet
        case silentAlert
        case review
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            // Progress
            progressIndicator
            
            // Content
            ScrollView {
                VStack(spacing: 24) {
                    switch currentStep {
                    case .intro:
                        introContent
                    case .setPin:
                        setPinContent
                    case .decoyWallet:
                        decoyWalletContent
                    case .silentAlert:
                        silentAlertContent
                    case .review:
                        reviewContent
                    }
                }
                .padding(24)
            }
            
            // Navigation buttons
            navigationButtons
        }
        .frame(minWidth: 500, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Setup Issue", isPresented: .constant(errorMessage != nil)) {
            Button("Dismiss") { errorMessage = nil }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .sheet(isPresented: $showSuccess) {
            successSheet
        }
        .alert("Remove Duress Protection", isPresented: $showDeleteConfirmation) {
            SecureField("Enter your real PIN", text: $realPin)
            Button("Cancel", role: .cancel) { realPin = "" }
            Button("Remove", role: .destructive) {
                if duressManager.removeDuressPin(realPin: realPin) {
                    dismiss()
                } else {
                    errorMessage = "Invalid PIN"
                }
                realPin = ""
            }
        } message: {
            Text("This will remove the duress PIN and decoy wallet. Enter your real PIN to confirm.")
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Duress Protection")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(stepTitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if duressManager.isConfigured {
                Button(action: { showDeleteConfirmation = true }) {
                    Label("Remove", systemImage: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var stepTitle: String {
        switch currentStep {
        case .intro: return "Understanding plausible deniability"
        case .setPin: return "Step 1 of 4"
        case .decoyWallet: return "Step 2 of 4"
        case .silentAlert: return "Step 3 of 4"
        case .review: return "Step 4 of 4"
        }
    }
    
    // MARK: - Progress Indicator
    
    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(Array(SetupStep.allCases.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Capsule()
                        .fill(index <= currentStep.rawValue ? Color.blue : Color.gray.opacity(0.3))
                        .frame(height: 3)
                }
                
                Circle()
                    .fill(index <= currentStep.rawValue ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .overlay {
                        if index < currentStep.rawValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
    
    // MARK: - Intro Content
    
    private var introContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Warning Banner
            HStack(spacing: 16) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Advanced Security Feature")
                        .font(.headline)
                    Text("This feature provides protection in coercion scenarios")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
            
            // What is Duress PIN
            VStack(alignment: .leading, spacing: 12) {
                Label("What is a Duress PIN?", systemImage: "questionmark.circle")
                    .font(.headline)
                
                Text("A duress PIN is a secondary unlock code that, when entered, opens a decoy wallet instead of your real one. If you're ever forced to unlock your wallet under threat, the attacker sees only the decoy wallet with minimal funds.")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            // How it works
            VStack(alignment: .leading, spacing: 12) {
                Label("How It Works", systemImage: "gearshape.2")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    DuressFeatureRow(icon: "1.circle.fill", text: "You set two PINs: your real PIN and a duress PIN")
                    DuressFeatureRow(icon: "2.circle.fill", text: "Real PIN → Opens your real wallet with all funds")
                    DuressFeatureRow(icon: "3.circle.fill", text: "Duress PIN → Opens decoy wallet with minimal funds")
                    DuressFeatureRow(icon: "4.circle.fill", text: "No indication that a real wallet even exists")
                }
            }
            
            // Key features
            VStack(alignment: .leading, spacing: 12) {
                Label("Key Features", systemImage: "star.fill")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    DuressFeatureRow(icon: "eye.slash.fill", color: .blue, text: "Plausible deniability - impossible to prove real wallet exists")
                    DuressFeatureRow(icon: "bell.slash.fill", color: .purple, text: "Optional silent alert to trusted contact")
                    DuressFeatureRow(icon: "doc.text.fill", color: .green, text: "Realistic transaction history in decoy wallet")
                    DuressFeatureRow(icon: "clock.fill", color: .orange, text: "Activation logs (hidden in duress mode)")
                }
            }
            
            // Warning
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                
                Text("Important: Only you know about your real wallet. Never share your real PIN with anyone, even trusted contacts.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Set PIN Content
    
    private var setPinContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Set Your Duress PIN", systemImage: "lock.shield")
                    .font(.headline)
                
                Text("Choose a PIN that's different from your real PIN. This PIN will open the decoy wallet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Duress PIN")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    SecureField("Enter 4+ digit PIN", text: $duressPin)
                        .textFieldStyle(.roundedBorder)
                        .font(.title2)
                        .help("This PIN opens the decoy wallet — must differ from your real passcode")
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Confirm Duress PIN")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    SecureField("Confirm PIN", text: $confirmPin)
                        .textFieldStyle(.roundedBorder)
                        .font(.title2)
                        .help("Re-enter the duress PIN to confirm")
                }
                
                if !duressPin.isEmpty && !confirmPin.isEmpty && duressPin != confirmPin {
                    Label("PINs do not match", systemImage: "exclamationmark.circle")
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                if duressPin.count >= 4 && !duressPin.isEmpty {
                    Label("PIN strength: Good", systemImage: "checkmark.circle")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
            
            // Tips
            VStack(alignment: .leading, spacing: 8) {
                Text("Tips for choosing a duress PIN:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("• Make it memorable but not obvious")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("• Use something you'd naturally try if \"forgetting\" your PIN")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("• Consider using your birthday backwards or a common pattern")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Decoy Wallet Content
    
    private var decoyWalletContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Configure Decoy Wallet", systemImage: "wallet.pass")
                    .font(.headline)
                
                Text("The decoy wallet should look realistic. Set small balances that appear plausible.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Wallet name
            VStack(alignment: .leading, spacing: 8) {
                Text("Wallet Name")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextField("Main Wallet", text: $config.name)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Balances
            VStack(alignment: .leading, spacing: 12) {
                Text("Decoy Balances")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bitcoin")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            TextField("0.0015", value: Binding(
                                get: { config.balances["bitcoin"] ?? 0.0015 },
                                set: { config.balances["bitcoin"] = $0 }
                            ), format: .number)
                                .textFieldStyle(.roundedBorder)
                            Text("BTC")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ethereum")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            TextField("0.05", value: Binding(
                                get: { config.balances["ethereum"] ?? 0.05 },
                                set: { config.balances["ethereum"] = $0 }
                            ), format: .number)
                                .textFieldStyle(.roundedBorder)
                            Text("ETH")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Text("💡 Keep balances small but not zero - a $50-$200 wallet looks realistic")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Transaction history options
            VStack(alignment: .leading, spacing: 12) {
                Text("Transaction History")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Toggle("Include deposit transactions", isOn: $config.includeDeposits)
                    .help("Show fake incoming transactions to make the decoy wallet more believable")
                Toggle("Include send transactions", isOn: $config.includeSends)
                    .help("Show fake outgoing transactions in the decoy wallet")
                
                Text("Realistic transaction history makes the decoy more believable")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Preview
            VStack(alignment: .leading, spacing: 8) {
                Text("Seed Phrase Preview")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                        ForEach(Array(config.seedPhrase.enumerated()), id: \.offset) { index, word in
                            HStack(spacing: 4) {
                                Text("\(index + 1).")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(word)
                                    .font(.system(.caption, design: .monospaced))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(4)
                        }
                    }
                }
                
                Button("Generate New Phrase") {
                    config.seedPhrase = DecoyWalletConfig.generateDecoyPhrase()
                }
                .font(.caption)
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Silent Alert Content
    
    private var silentAlertContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Silent Alert (Optional)", systemImage: "bell.badge")
                    .font(.headline)
                
                Text("Optionally notify a trusted contact when duress mode is activated.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Toggle("Enable silent alert", isOn: $silentAlertEnabled)
                .help("Silently notify a trusted person when the duress passcode is used")
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            
            if silentAlertEnabled {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Contact Name")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        TextField("Trusted Person", text: $emergencyContact.name)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // Alert method
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Alert Method")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Picker("Method", selection: $emergencyContact.alertMethod) {
                            Text("SMS").tag(EmergencyContact.AlertMethod.sms)
                            Text("Email").tag(EmergencyContact.AlertMethod.email)
                            Text("Signal").tag(EmergencyContact.AlertMethod.signal)
                        }
                        .pickerStyle(.segmented)
                        .help("How the emergency contact will be notified — Signal is most private")
                    }
                    
                    // Contact info
                    switch emergencyContact.alertMethod {
                    case .sms:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Phone Number")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            TextField("+1 (555) 123-4567", text: Binding(
                                get: { emergencyContact.phoneNumber ?? "" },
                                set: { emergencyContact.phoneNumber = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                        
                    case .email:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email Address")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            TextField("contact@example.com", text: Binding(
                                get: { emergencyContact.email ?? "" },
                                set: { emergencyContact.email = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                        
                    case .signal, .none:
                        EmptyView()
                    }
                    
                    // Message
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Alert Message")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        TextField("Duress alert triggered", text: $emergencyContact.message)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
            }
            
            // Privacy note
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .foregroundColor(.green)
                
                Text("Alert is sent through secure channels. Your contact info is stored only on this device.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Review Content
    
    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Review Configuration", systemImage: "checkmark.circle")
                    .font(.headline)
                
                Text("Please review your duress protection settings.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Summary cards
            VStack(spacing: 16) {
                DuressReviewCard(
                    icon: "lock.shield.fill",
                    iconColor: .blue,
                    title: "Duress PIN",
                    value: "••••" + (duressPin.count > 4 ? "+" : ""),
                    subtitle: "\(duressPin.count) digits configured"
                )
                
                DuressReviewCard(
                    icon: "wallet.pass.fill",
                    iconColor: .orange,
                    title: "Decoy Wallet",
                    value: config.name,
                    subtitle: "BTC: \(String(format: "%.4f", config.balances["bitcoin"] ?? 0)), ETH: \(String(format: "%.4f", config.balances["ethereum"] ?? 0))"
                )
                
                DuressReviewCard(
                    icon: "bell.badge.fill",
                    iconColor: silentAlertEnabled ? .purple : .gray,
                    title: "Silent Alert",
                    value: silentAlertEnabled ? "Enabled" : "Disabled",
                    subtitle: silentAlertEnabled ? "Will notify \(emergencyContact.name)" : "No notifications"
                )
            }
            
            // How to use
            VStack(alignment: .leading, spacing: 12) {
                Text("How to use:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    DuressInstructionRow(number: "1", text: "Enter your duress PIN when forced to unlock")
                    DuressInstructionRow(number: "2", text: "The decoy wallet opens automatically")
                    DuressInstructionRow(number: "3", text: "Your real wallet remains completely hidden")
                    DuressInstructionRow(number: "4", text: "Enter your real PIN later to access real funds")
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
            
            // Final warning
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remember your PINs!")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("There is no way to recover your duress PIN if forgotten.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Navigation Buttons
    
    private var navigationButtons: some View {
        HStack {
            if currentStep != .intro {
                Button("Back") {
                    withAnimation {
                        currentStep = SetupStep(rawValue: currentStep.rawValue - 1) ?? .intro
                    }
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
            }
            
            Spacer()
            
            if currentStep == .review {
                Button("Complete Setup") {
                    completeSetup()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceed)
            } else {
                Button("Continue") {
                    withAnimation {
                        currentStep = SetupStep(rawValue: currentStep.rawValue + 1) ?? .review
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceed)
                .keyboardShortcut(.rightArrow, modifiers: [])
            }
        }
        .padding(24)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var canProceed: Bool {
        switch currentStep {
        case .intro:
            return true
        case .setPin:
            return duressPin.count >= 4 && duressPin == confirmPin
        case .decoyWallet:
            return !config.name.isEmpty
        case .silentAlert:
            if silentAlertEnabled {
                switch emergencyContact.alertMethod {
                case .sms:
                    return !(emergencyContact.phoneNumber ?? "").isEmpty
                case .email:
                    return !(emergencyContact.email ?? "").isEmpty
                case .signal, .none:
                    return true
                }
            }
            return true
        case .review:
            return true
        }
    }
    
    // MARK: - Success Sheet
    
    private var successSheet: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("Duress Protection Enabled")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Your wallet now has an additional layer of protection against coercion.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 8) {
                Label("Real PIN → Your real wallet", systemImage: "checkmark.circle")
                    .foregroundColor(.green)
                Label("Duress PIN → Decoy wallet", systemImage: "eye.slash")
                    .foregroundColor(.blue)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            Button("Done") {
                showSuccess = false
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(width: 400)
    }
    
    // MARK: - Actions
    
    private func completeSetup() {
        // Set duress PIN
        let pinResult = duressManager.setDuressPin(duressPin, confirmPin: confirmPin)
        switch pinResult {
        case .success:
            break
        case .failure(let error):
            errorMessage = error.localizedDescription
            return
        }
        
        // Configure decoy wallet
        let walletResult = duressManager.configureDecoyWallet(config)
        switch walletResult {
        case .success:
            break
        case .failure(let error):
            errorMessage = error.localizedDescription
            return
        }
        
        // Configure silent alert if enabled
        if silentAlertEnabled {
            _ = duressManager.setEmergencyContact(emergencyContact)
            duressManager.setSilentAlert(true)
        }
        
        showSuccess = true
    }
}

// MARK: - Helper Views

private struct DuressFeatureRow: View {
    let icon: String
    var color: Color = .primary
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

private struct DuressReviewCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 40, height: 40)
                .background(iconColor.opacity(0.1))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

private struct DuressInstructionRow: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.blue)
                .clipShape(Circle())
            
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    DuressSetupView()
}
#endif
#endif
#endif
