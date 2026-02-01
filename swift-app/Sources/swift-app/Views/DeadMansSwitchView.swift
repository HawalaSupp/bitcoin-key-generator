import SwiftUI

// MARK: - Dead Man's Switch Setup View

/// Comprehensive UI for setting up inheritance protocol
struct DeadMansSwitchView: View {
    @StateObject private var manager = DeadMansSwitchManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentStep: SetupStep = .intro
    @State private var config = InheritanceConfig()
    @State private var showAddHeir = false
    @State private var editingHeir: Heir?
    @State private var showCancelConfirmation = false
    @State private var cancelPasscode = ""
    @State private var errorMessage: String?
    @State private var showSuccess = false
    
    enum SetupStep: Int, CaseIterable {
        case intro
        case heirs
        case timing
        case security
        case review
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            if manager.isConfigured {
                configuredView
            } else {
                setupView
            }
        }
        .frame(minWidth: 600, minHeight: 650)
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .sheet(isPresented: $showSuccess) {
            successSheet
        }
        .sheet(isPresented: $showAddHeir) {
            HeirEditorSheet(heir: nil) { heir in
                config.heirs.append(heir)
            }
        }
        .sheet(item: $editingHeir) { heir in
            HeirEditorSheet(heir: heir) { updated in
                if let index = config.heirs.firstIndex(where: { $0.id == updated.id }) {
                    config.heirs[index] = updated
                }
            }
        }
        .alert("Cancel Inheritance Protocol", isPresented: $showCancelConfirmation) {
            SecureField("Enter your passcode", text: $cancelPasscode)
            Button("Keep Active", role: .cancel) { cancelPasscode = "" }
            Button("Cancel Protocol", role: .destructive) {
                let result = manager.emergencyCancel(passcode: cancelPasscode)
                if case .failure(let error) = result {
                    errorMessage = error.localizedDescription
                }
                cancelPasscode = ""
            }
        } message: {
            Text("This will permanently cancel the inheritance protocol. Enter your passcode to confirm.")
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dead Man's Switch")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(manager.isConfigured ? "Active - \(manager.daysUntilTrigger ?? 0) days remaining" : "Inheritance Protocol")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Warning indicator
            if manager.warningLevel != .none {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(manager.warningLevel == .critical ? "Check in now!" : "Check in soon")
                }
                .foregroundColor(manager.warningLevel == .critical ? .red : .orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(manager.warningLevel == .critical ? Color.red.opacity(0.1) : Color.orange.opacity(0.1))
                .cornerRadius(8)
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
    
    // MARK: - Configured View (Active Protocol)
    
    private var configuredView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Status card
                statusCard
                
                // Check-in button
                checkInSection
                
                // Heirs overview
                heirsOverview
                
                // Settings
                settingsSection
                
                // Danger zone
                dangerZone
            }
            .padding(24)
        }
    }
    
    private var statusCard: some View {
        VStack(spacing: 16) {
            // Circular progress
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                
                Circle()
                    .trim(from: 0, to: progressValue)
                    .stroke(progressColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: progressValue)
                
                VStack(spacing: 4) {
                    Text("\(manager.daysUntilTrigger ?? 0)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("days remaining")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 180, height: 180)
            
            // Last check-in
            if let lastCheckIn = manager.lastCheckIn {
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    Text("Last check-in: \(lastCheckIn, style: .relative) ago")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(16)
    }
    
    private var progressValue: CGFloat {
        guard let config = manager.config, let daysRemaining = manager.daysUntilTrigger else { return 0 }
        return CGFloat(daysRemaining) / CGFloat(config.inactivityDays)
    }
    
    private var progressColor: Color {
        switch manager.warningLevel {
        case .critical: return .red
        case .warning: return .orange
        case .none: return .green
        }
    }
    
    private var checkInSection: some View {
        VStack(spacing: 12) {
            Button(action: {
                manager.recordCheckIn()
            }) {
                HStack {
                    Image(systemName: "hand.wave.fill")
                    Text("I'm Still Here - Check In")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            
            Text("Check in periodically to reset the inheritance timer")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var heirsOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Designated Heirs")
                    .font(.headline)
                Spacer()
                Text("\(manager.config?.heirs.count ?? 0) configured")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let heirs = manager.config?.heirs {
                ForEach(heirs) { heir in
                    HeirRow(heir: heir, showEdit: false)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Settings")
                .font(.headline)
            
            if let config = manager.config {
                HStack {
                    Label("Inactivity Period", systemImage: "calendar")
                    Spacer()
                    Text("\(config.inactivityDays) days")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Label("Warning Period", systemImage: "bell")
                    Spacer()
                    Text("\(config.warningDays) days before")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Label("Bitcoin Timelocks", systemImage: "bitcoinsign.circle")
                    Spacer()
                    Image(systemName: config.useBitcoinTimelocks ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(config.useBitcoinTimelocks ? .green : .gray)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Danger Zone")
                .font(.headline)
                .foregroundColor(.red)
            
            Button(action: { showCancelConfirmation = true }) {
                HStack {
                    Image(systemName: "xmark.octagon.fill")
                    Text("Cancel Inheritance Protocol")
                }
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            Text("This will permanently cancel the inheritance protocol. Your heirs will not receive funds automatically.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.red.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Setup View (Not Configured)
    
    private var setupView: some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressIndicator
            
            // Content
            ScrollView {
                VStack(spacing: 24) {
                    switch currentStep {
                    case .intro:
                        introContent
                    case .heirs:
                        heirsContent
                    case .timing:
                        timingContent
                    case .security:
                        securityContent
                    case .review:
                        reviewContent
                    }
                }
                .padding(24)
            }
            
            // Navigation
            navigationButtons
        }
    }
    
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
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
    
    // MARK: - Setup Steps Content
    
    private var introContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Hero section
            HStack(spacing: 20) {
                Image(systemName: "person.2.badge.gearshape.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Protect Your Legacy")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Ensure your crypto reaches your loved ones")
                        .foregroundColor(.secondary)
                }
            }
            
            // How it works
            VStack(alignment: .leading, spacing: 16) {
                Text("How It Works")
                    .font(.headline)
                
                SwitchFeatureRow(
                    number: 1,
                    title: "Configure Heirs",
                    description: "Designate up to 5 recipients with their wallet addresses and allocation percentages"
                )
                
                SwitchFeatureRow(
                    number: 2,
                    title: "Set Inactivity Period",
                    description: "Choose how long without activity before the protocol triggers (e.g., 1 year)"
                )
                
                SwitchFeatureRow(
                    number: 3,
                    title: "Check In Periodically",
                    description: "Simply open the app and tap \"Check In\" to reset the timer"
                )
                
                SwitchFeatureRow(
                    number: 4,
                    title: "Automatic Transfer",
                    description: "If you don't check in, funds transfer automatically to your heirs"
                )
            }
            
            // Security note
            VStack(alignment: .leading, spacing: 8) {
                Label("Fully Trustless", systemImage: "lock.shield.fill")
                    .font(.headline)
                    .foregroundColor(.green)
                
                Text("No third party required. Bitcoin transfers use native timelocks (CLTV). Ethereum uses trustless smart contracts. Your keys remain secure on your device.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    private var heirsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Designate Your Heirs")
                    .font(.headline)
                Text("Add up to 5 heirs with their wallet addresses. Allocations must total 100%.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Heir list
            if config.heirs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("No heirs configured yet")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
            } else {
                ForEach(config.heirs) { heir in
                    HeirRow(heir: heir, showEdit: true, onEdit: {
                        editingHeir = heir
                    }, onDelete: {
                        config.heirs.removeAll { $0.id == heir.id }
                    })
                }
                
                // Allocation summary
                let total = config.heirs.reduce(0) { $0 + $1.allocation }
                HStack {
                    Text("Total Allocation")
                        .font(.subheadline)
                    Spacer()
                    Text("\(total)%")
                        .font(.headline)
                        .foregroundColor(total == 100 ? .green : .red)
                }
                .padding()
                .background(total == 100 ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Add heir button
            if config.heirs.count < 5 {
                Button(action: { showAddHeir = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Heir")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var timingContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Set Timing")
                    .font(.headline)
                Text("Choose how long the protocol waits before triggering.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Inactivity period
            VStack(alignment: .leading, spacing: 12) {
                Text("Inactivity Period")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Picker("Inactivity Period", selection: $config.inactivityDays) {
                    ForEach(InheritanceConfig.inactivityOptions, id: \.days) { option in
                        Text(option.label).tag(option.days)
                    }
                }
                .pickerStyle(.segmented)
                
                Text("If you don't check in for \(config.inactivityDays) days, your funds will transfer to your designated heirs.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Warning period
            VStack(alignment: .leading, spacing: 12) {
                Text("Warning Period")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Picker("Warning Period", selection: $config.warningDays) {
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                    Text("60 days").tag(60)
                }
                .pickerStyle(.segmented)
                
                Text("You'll receive warnings \(config.warningDays) days before the protocol triggers.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Visual timeline
            VStack(alignment: .leading, spacing: 8) {
                Text("Timeline Preview")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.green)
                        .frame(height: 8)
                    
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: CGFloat(config.warningDays) / CGFloat(config.inactivityDays) * 200, height: 8)
                    
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                }
                .cornerRadius(4)
                
                HStack {
                    Text("Now")
                        .font(.caption2)
                    Spacer()
                    Text("Warning")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Spacer()
                    Text("Trigger")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
        }
    }
    
    private var securityContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Security Options")
                    .font(.headline)
                Text("Configure how the inheritance protocol operates.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Bitcoin timelocks
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $config.useBitcoinTimelocks) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Bitcoin CLTV Timelocks", systemImage: "bitcoinsign.circle.fill")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Use native Bitcoin timelocks for trustless inheritance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if config.useBitcoinTimelocks {
                    Text("Pre-signed transactions will be generated and stored encrypted. They can only be broadcast after the timelock expires.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            Divider()
            
            // Ethereum contract
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $config.useEthereumContract) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Ethereum Timelock Contract", systemImage: "circle.hexagonpath.fill")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Deploy a trustless smart contract for ETH/ERC-20 inheritance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Divider()
            
            // Check-in security
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $config.requirePasscodeForCheckIn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Require Passcode for Check-In", systemImage: "lock.fill")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Prevent unauthorized check-ins")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Divider()
            
            // Notify heirs
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $config.notifyHeirsOnSetup) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Notify Heirs on Setup", systemImage: "envelope.fill")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Send notification to heirs about the inheritance protocol")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Review Your Configuration")
                    .font(.headline)
                Text("Please verify all settings before activating the inheritance protocol.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Summary cards
            VStack(spacing: 16) {
                SwitchReviewCard(
                    icon: "person.2.fill",
                    iconColor: .blue,
                    title: "Heirs",
                    value: "\(config.heirs.count) configured",
                    subtitle: config.heirs.map { "\($0.name): \($0.allocation)%" }.joined(separator: ", ")
                )
                
                SwitchReviewCard(
                    icon: "calendar",
                    iconColor: .green,
                    title: "Inactivity Period",
                    value: formatDays(config.inactivityDays),
                    subtitle: "Warnings start \(config.warningDays) days before"
                )
                
                SwitchReviewCard(
                    icon: "lock.shield.fill",
                    iconColor: .purple,
                    title: "Security",
                    value: securitySummary,
                    subtitle: "Trustless blockchain-based transfers"
                )
            }
            
            // Important notes
            VStack(alignment: .leading, spacing: 12) {
                Label("Important", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 8) {
                    BulletPoint(text: "Check in regularly to prevent accidental triggering")
                    BulletPoint(text: "Keep heir addresses up to date")
                    BulletPoint(text: "You can cancel the protocol anytime with your passcode")
                    BulletPoint(text: "Pre-signed transactions are encrypted and stored locally")
                }
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    private var securitySummary: String {
        var features: [String] = []
        if config.useBitcoinTimelocks { features.append("BTC CLTV") }
        if config.useEthereumContract { features.append("ETH Contract") }
        if config.requirePasscodeForCheckIn { features.append("Passcode") }
        return features.isEmpty ? "Standard" : features.joined(separator: ", ")
    }
    
    private func formatDays(_ days: Int) -> String {
        if days >= 365 {
            return "\(days / 365) year\(days >= 730 ? "s" : "")"
        } else if days >= 30 {
            return "\(days / 30) month\(days >= 60 ? "s" : "")"
        }
        return "\(days) days"
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
            }
            
            Spacer()
            
            if currentStep == .review {
                Button("Activate Protocol") {
                    activateProtocol()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canActivate)
            } else {
                Button("Continue") {
                    withAnimation {
                        currentStep = SetupStep(rawValue: currentStep.rawValue + 1) ?? .review
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceed)
            }
        }
        .padding(24)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var canProceed: Bool {
        switch currentStep {
        case .intro:
            return true
        case .heirs:
            let total = config.heirs.reduce(0) { $0 + $1.allocation }
            return !config.heirs.isEmpty && total == 100
        case .timing:
            return config.inactivityDays >= 30
        case .security:
            return true
        case .review:
            return true
        }
    }
    
    private var canActivate: Bool {
        let total = config.heirs.reduce(0) { $0 + $1.allocation }
        return !config.heirs.isEmpty && total == 100 && config.inactivityDays >= 30
    }
    
    private var successSheet: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("Inheritance Protocol Active")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Your crypto will be automatically transferred to your heirs if you don't check in for \(config.inactivityDays) days.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 8) {
                Label("Remember to check in periodically", systemImage: "hand.wave")
                Label("You'll receive warnings before it triggers", systemImage: "bell.badge")
                Label("You can cancel anytime with your passcode", systemImage: "xmark.circle")
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
        .frame(width: 450)
    }
    
    private func activateProtocol() {
        let result = manager.configure(config)
        switch result {
        case .success:
            showSuccess = true
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Helper Views

private struct SwitchFeatureRow: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.blue)
                .clipShape(Circle())
            
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
}

private struct HeirRow: View {
    let heir: Heir
    var showEdit: Bool = false
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: chainIcon)
                .font(.title2)
                .foregroundColor(chainColor)
                .frame(width: 40, height: 40)
                .background(chainColor.opacity(0.1))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(heir.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(truncatedAddress)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text("\(heir.allocation)%")
                .font(.headline)
                .foregroundColor(.blue)
            
            if showEdit {
                Button(action: { onEdit?() }) {
                    Image(systemName: "pencil")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                
                Button(action: { onDelete?() }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var chainIcon: String {
        switch heir.chain.lowercased() {
        case "bitcoin": return "bitcoinsign.circle.fill"
        case "ethereum": return "circle.hexagonpath.fill"
        case "litecoin": return "l.circle.fill"
        default: return "circle.fill"
        }
    }
    
    private var chainColor: Color {
        switch heir.chain.lowercased() {
        case "bitcoin": return .orange
        case "ethereum": return .purple
        case "litecoin": return .gray
        default: return .blue
        }
    }
    
    private var truncatedAddress: String {
        guard heir.address.count > 16 else { return heir.address }
        return String(heir.address.prefix(8)) + "..." + String(heir.address.suffix(8))
    }
}

private struct SwitchReviewCard: View {
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
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

private struct BulletPoint: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.secondary)
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Heir Editor Sheet

private struct HeirEditorSheet: View {
    let heir: Heir?
    let onSave: (Heir) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var email: String
    @State private var address: String
    @State private var chain: String
    @State private var allocation: Int
    @State private var notes: String
    
    init(heir: Heir?, onSave: @escaping (Heir) -> Void) {
        self.heir = heir
        self.onSave = onSave
        _name = State(initialValue: heir?.name ?? "")
        _email = State(initialValue: heir?.email ?? "")
        _address = State(initialValue: heir?.address ?? "")
        _chain = State(initialValue: heir?.chain ?? "bitcoin")
        _allocation = State(initialValue: heir?.allocation ?? 100)
        _notes = State(initialValue: heir?.notes ?? "")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(heir == nil ? "Add Heir" : "Edit Heir")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            // Form
            Form {
                Section("Personal Information") {
                    TextField("Name", text: $name)
                    TextField("Email (optional)", text: $email)
                }
                
                Section("Wallet Information") {
                    Picker("Chain", selection: $chain) {
                        Text("Bitcoin").tag("bitcoin")
                        Text("Ethereum").tag("ethereum")
                        Text("Litecoin").tag("litecoin")
                        Text("BNB Chain").tag("bnb")
                    }
                    
                    TextField("Wallet Address", text: $address)
                        .textFieldStyle(.roundedBorder)
                }
                
                Section("Allocation") {
                    Stepper(value: $allocation, in: 1...100) {
                        HStack {
                            Text("Share")
                            Spacer()
                            Text("\(allocation)%")
                                .fontWeight(.bold)
                        }
                    }
                }
                
                Section("Notes (optional)") {
                    TextField("Additional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...5)
                }
            }
            .formStyle(.grouped)
            
            // Buttons
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    let newHeir = Heir(
                        name: name,
                        email: email.isEmpty ? nil : email,
                        address: address,
                        chain: chain,
                        allocation: allocation,
                        notes: notes.isEmpty ? nil : notes
                    )
                    onSave(newHeir)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || address.isEmpty)
            }
            .padding()
        }
        .frame(width: 450, height: 500)
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    DeadMansSwitchView()
}
#endif
#endif
#endif
