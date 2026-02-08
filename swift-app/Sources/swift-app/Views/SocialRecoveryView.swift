import SwiftUI

// MARK: - Social Recovery Setup View
// Phase 3.5: Multisig Made Simple - Social Recovery UI

struct SocialRecoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var multisigManager = MultisigManager.shared
    @State private var selectedWallet: MultisigConfig?
    @State private var showAddGuardian = false
    @State private var showInviteCoSigner = false
    @State private var showRecoveryWizard = false
    @State private var alertMessage = ""
    @State private var showAlert = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    socialRecoveryHeader
                    
                    // Quick Setup Card
                    quickSetupCard
                    
                    // Guardians Section
                    if let wallet = selectedWallet {
                        guardiansSection(wallet: wallet)
                    }
                    
                    // Recovery Options
                    recoveryOptionsSection
                    
                    // Security Tips
                    securityTipsCard
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("Social Recovery")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 500, height: 600)
        .sheet(isPresented: $showAddGuardian) {
            AddGuardianSheet(wallet: selectedWallet) { guardian in
                if let walletId = selectedWallet?.id {
                    multisigManager.addGuardian(guardian, to: walletId)
                }
            }
        }
        .sheet(isPresented: $showInviteCoSigner) {
            InviteCoSignerSheet(wallet: selectedWallet, multisigManager: multisigManager)
        }
        .sheet(isPresented: $showRecoveryWizard) {
            RecoveryWizardSheet(wallet: selectedWallet, multisigManager: multisigManager)
        }
        .alert("Social Recovery", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            if let first = multisigManager.wallets.first {
                selectedWallet = first
            }
        }
    }
    
    // MARK: - Header
    private var socialRecoveryHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.3), .pink.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "person.3.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.purple)
            }
            
            Text("Social Recovery")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Protect your wallet with trusted guardians")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .padding(.vertical)
    }
    
    // MARK: - Quick Setup Card
    private var quickSetupCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundColor(.purple)
                Text("Easy Setup")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            Text("Social recovery lets you regain access to your wallet if you lose your keys, using trusted friends or family as guardians.")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            // Wallet picker
            if !multisigManager.wallets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Wallet")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Picker("Wallet", selection: $selectedWallet) {
                        ForEach(multisigManager.wallets) { wallet in
                            Text(wallet.name)
                                .tag(Optional(wallet))
                        }
                    }
                    .pickerStyle(.menu)
                }
            } else {
                HStack {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.orange)
                    Text("Create a multisig wallet first to enable social recovery")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            // Setup buttons
            HStack(spacing: 12) {
                SocialRecoveryButton(
                    icon: "person.badge.plus",
                    title: "Add Guardian",
                    color: .blue
                ) {
                    if selectedWallet != nil {
                        showAddGuardian = true
                    } else {
                        alertMessage = "Please select or create a multisig wallet first."
                        showAlert = true
                    }
                }
                
                SocialRecoveryButton(
                    icon: "link.badge.plus",
                    title: "Invite Co-Signer",
                    color: .green
                ) {
                    if selectedWallet != nil {
                        showInviteCoSigner = true
                    } else {
                        alertMessage = "Please select or create a multisig wallet first."
                        showAlert = true
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Guardians Section
    private func guardiansSection(wallet: MultisigConfig) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "shield.checkered")
                    .foregroundColor(.green)
                Text("Your Guardians")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button {
                    showAddGuardian = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            
            // This would show actual guardians in a real implementation
            VStack(spacing: 8) {
                GuardianPlaceholderRow(
                    name: "Add Guardian 1",
                    icon: "person.badge.plus",
                    action: { showAddGuardian = true }
                )
                
                GuardianPlaceholderRow(
                    name: "Add Guardian 2",
                    icon: "person.badge.plus",
                    action: { showAddGuardian = true }
                )
                
                GuardianPlaceholderRow(
                    name: "Add Guardian 3",
                    icon: "person.badge.plus",
                    action: { showAddGuardian = true }
                )
            }
            
            Text("Recommended: Add 3-5 guardians for optimal security")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Recovery Options
    private var recoveryOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundColor(.orange)
                Text("Recovery Options")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 8) {
                RecoveryOptionRow(
                    icon: "key.fill",
                    title: "Initiate Recovery",
                    description: "Lost your keys? Start the recovery process",
                    color: .orange
                ) {
                    if selectedWallet != nil {
                        showRecoveryWizard = true
                    } else {
                        alertMessage = "Please select a wallet to recover."
                        showAlert = true
                    }
                }
                
                RecoveryOptionRow(
                    icon: "checkmark.shield.fill",
                    title: "Approve Recovery",
                    description: "Review and approve pending recoveries",
                    color: .green
                ) {
                    alertMessage = "No pending recovery requests."
                    showAlert = true
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Security Tips
    private var securityTipsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Security Tips")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                SocialRecoveryTipItem(text: "Choose guardians who won't collude against you")
                SocialRecoveryTipItem(text: "Guardians should be geographically distributed")
                SocialRecoveryTipItem(text: "Verify guardian contact info periodically")
                SocialRecoveryTipItem(text: "Keep recovery threshold at majority (e.g., 3-of-5)")
            }
        }
        .padding()
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(16)
    }
}

// MARK: - Supporting Views

struct SocialRecoveryButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color.opacity(0.2))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct GuardianPlaceholderRow: View {
    let name: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .foregroundColor(.gray)
                }
                
                Text(name)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct RecoveryOptionRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .foregroundColor(color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct SocialRecoveryTipItem: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Add Guardian Sheet

struct AddGuardianSheet: View {
    let wallet: MultisigConfig?
    let onAdd: (Guardian) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var publicKey = ""
    @State private var contactMethod: Guardian.ContactMethod = .inApp
    
    var body: some View {
        NavigationView {
            Form {
                Section("Guardian Details") {
                    TextField("Name", text: $name)
                    
                    TextField("Public Key", text: $publicKey)
                        .font(.system(.body, design: .monospaced))
                    
                    Picker("Contact Method", selection: $contactMethod) {
                        Text("In-App").tag(Guardian.ContactMethod.inApp)
                        Text("Email").tag(Guardian.ContactMethod.email)
                        Text("Phone").tag(Guardian.ContactMethod.phone)
                        Text("Hardware").tag(Guardian.ContactMethod.hardware)
                    }
                }
                
                Section("About Guardians") {
                    Text("A guardian can help you recover your wallet if you lose your keys. Choose someone you trust who is unlikely to lose their own keys.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    Button("Add Guardian") {
                        let guardian = Guardian(
                            id: UUID(),
                            name: name,
                            publicKey: publicKey,
                            contactMethod: contactMethod,
                            addedAt: Date(),
                            lastVerified: nil
                        )
                        onAdd(guardian)
                        dismiss()
                    }
                    .disabled(name.isEmpty || publicKey.isEmpty)
                }
            }
            .navigationTitle("Add Guardian")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(width: 400, height: 400)
    }
}

// MARK: - Invite Co-Signer Sheet

struct InviteCoSignerSheet: View {
    let wallet: MultisigConfig?
    @ObservedObject var multisigManager: MultisigManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var invitation: CoSignerInvitation?
    @State private var showCopied = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                if let wallet = wallet {
                    // Wallet info
                    VStack(spacing: 8) {
                        Text(wallet.name)
                            .font(.headline)
                        Text(wallet.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                    
                    if let invitation = invitation {
                        // Show invitation code
                        VStack(spacing: 16) {
                            Text("Invitation Code")
                                .font(.headline)
                            
                            Text(invitation.inviteCode)
                                .font(.system(.caption, design: .monospaced))
                                .padding()
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                            
                            Text("Share this code with your co-signer")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text("Expires: \(invitation.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            
                            Button {
                                // Copy to clipboard
                                ClipboardHelper.copySensitive(invitation.inviteCode, timeout: 60)
                                showCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    showCopied = false
                                }
                            } label: {
                                HStack {
                                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                    Text(showCopied ? "Copied!" : "Copy Code")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        Button("Generate Invitation") {
                            invitation = multisigManager.generateInvitationLink(for: wallet.id)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Text("No wallet selected")
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Invite Co-Signer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 400, height: 400)
    }
}

// MARK: - Recovery Wizard Sheet

struct RecoveryWizardSheet: View {
    let wallet: MultisigConfig?
    @ObservedObject var multisigManager: MultisigManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var step = 1
    @State private var newPublicKey = ""
    @State private var reason = ""
    @State private var recoveryRequest: RecoveryRequest?
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Progress
                HStack(spacing: 8) {
                    ForEach(1...3, id: \.self) { i in
                        Circle()
                            .fill(i <= step ? Color.orange : Color.gray.opacity(0.3))
                            .frame(width: 10, height: 10)
                    }
                }
                
                switch step {
                case 1:
                    reasonStep
                case 2:
                    newKeyStep
                case 3:
                    confirmStep
                default:
                    successStep
                }
                
                Spacer()
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding()
            .navigationTitle("Wallet Recovery")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(width: 450, height: 450)
    }
    
    private var reasonStep: some View {
        VStack(spacing: 16) {
            Text("Step 1: Why do you need recovery?")
                .font(.headline)
            
            TextEditor(text: $reason)
                .frame(height: 100)
                .border(Color.gray.opacity(0.3))
            
            Text("This reason will be shown to your guardians for verification.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Continue") {
                if !reason.isEmpty {
                    step = 2
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(reason.isEmpty)
        }
    }
    
    private var newKeyStep: some View {
        VStack(spacing: 16) {
            Text("Step 2: Enter your new public key")
                .font(.headline)
            
            TextField("New Public Key", text: $newPublicKey)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
            
            Text("This key will replace your compromised key after guardian approval.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Button("Back") {
                    step = 1
                }
                
                Button("Continue") {
                    if !newPublicKey.isEmpty {
                        step = 3
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newPublicKey.isEmpty)
            }
        }
    }
    
    private var confirmStep: some View {
        VStack(spacing: 16) {
            Text("Step 3: Confirm Recovery Request")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Reason: \(reason)")
                    .font(.caption)
                
                Text("New Key: \(newPublicKey.prefix(20))...")
                    .font(.caption)
                    .fontDesign(.monospaced)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            
            Text("Your guardians will be notified and asked to approve this recovery.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Button("Back") {
                    step = 2
                }
                
                Button("Submit Request") {
                    submitRecovery()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private var successStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
            
            Text("Recovery Request Submitted")
                .font(.headline)
            
            Text("Your guardians have been notified. You'll need approval from the majority before recovery can proceed.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private func submitRecovery() {
        guard let wallet = wallet else { return }
        
        do {
            recoveryRequest = try multisigManager.initiateRecovery(
                for: wallet.id,
                newPublicKey: newPublicKey,
                reason: reason
            )
            step = 4
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
    SocialRecoveryView()
}
#endif
#endif
#endif
