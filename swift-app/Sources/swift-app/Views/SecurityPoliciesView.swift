import SwiftUI

// MARK: - Security Policies View (P6 Integration)
/// Main view for managing security policies backed by Rust security modules

struct SecurityPoliciesView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SecurityPoliciesViewModel()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Threat Protection
                    SecuritySection(title: "Threat Protection", icon: "shield.checkered") {
                        ThreatProtectionSection(viewModel: viewModel)
                    }
                    
                    // Spending Limits
                    SecuritySection(title: "Spending Limits", icon: "creditcard.trianglebadge.exclamationmark") {
                        SpendingLimitsSection(viewModel: viewModel)
                    }
                    
                    // Address Whitelist
                    SecuritySection(title: "Trusted Addresses", icon: "person.badge.shield.checkmark") {
                        WhitelistSection(viewModel: viewModel)
                    }
                    
                    // Blacklist Management
                    SecuritySection(title: "Blocked Addresses", icon: "hand.raised.slash") {
                        BlacklistSection(viewModel: viewModel)
                    }
                    
                    // Key Rotation Status
                    SecuritySection(title: "Key Security", icon: "key.horizontal") {
                        KeyRotationSection(viewModel: viewModel)
                    }
                }
                .padding()
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("Security Policies")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { viewModel.loadSettings() }
            .alert("Security Alert", isPresented: $viewModel.showAlert) {
                Button("OK") { }
            } message: {
                Text(viewModel.alertMessage)
            }
        }
        .frame(minWidth: 600, minHeight: 700)
    }
}

// MARK: - View Model

@MainActor
class SecurityPoliciesViewModel: ObservableObject {
    @Published var threatProtectionEnabled = true
    @Published var autoBlockScams = true
    @Published var threatSensitivity: ThreatSensitivity = .medium
    
    @Published var perTxLimit: String = ""
    @Published var dailyLimit: String = ""
    @Published var weeklyLimit: String = ""
    @Published var monthlyLimit: String = ""
    @Published var requireWhitelist = false
    
    @Published var whitelistedAddresses: [WhitelistedAddress] = []
    @Published var blacklistedAddresses: [BlacklistedAddress] = []
    
    @Published var keyRotationStatus: KeyRotationStatus = .healthy
    @Published var lastRotationCheck: Date?
    @Published var daysSinceLastRotation: Int = 0
    
    @Published var showAlert = false
    @Published var alertMessage = ""
    
    @Published var isLoading = false
    @Published var selectedWalletId: String = "default"
    
    enum ThreatSensitivity: String, CaseIterable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        
        var description: String {
            switch self {
            case .low: return "Only block known scam addresses"
            case .medium: return "Block suspicious patterns and known scams"
            case .high: return "Strict mode - block anything unusual"
            }
        }
    }
    
    enum KeyRotationStatus {
        case healthy
        case dueSoon
        case overdue
        
        var color: Color {
            switch self {
            case .healthy: return .green
            case .dueSoon: return .orange
            case .overdue: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .healthy: return "checkmark.shield"
            case .dueSoon: return "exclamationmark.shield"
            case .overdue: return "xmark.shield"
            }
        }
    }
    
    struct WhitelistedAddress: Identifiable {
        let id = UUID()
        let address: String
        let label: String
        let addedDate: Date
    }
    
    struct BlacklistedAddress: Identifiable {
        let id = UUID()
        let address: String
        let reason: String
        let source: String // "user" or "system"
    }
    
    func loadSettings() {
        // Load from UserDefaults for UI state
        threatProtectionEnabled = UserDefaults.standard.bool(forKey: "security.threatProtection")
        if !UserDefaults.standard.contains(key: "security.threatProtection") {
            threatProtectionEnabled = true // default on
        }
        autoBlockScams = UserDefaults.standard.bool(forKey: "security.autoBlockScams")
        if !UserDefaults.standard.contains(key: "security.autoBlockScams") {
            autoBlockScams = true
        }
        
        perTxLimit = UserDefaults.standard.string(forKey: "security.perTxLimit") ?? ""
        dailyLimit = UserDefaults.standard.string(forKey: "security.dailyLimit") ?? ""
        weeklyLimit = UserDefaults.standard.string(forKey: "security.weeklyLimit") ?? ""
        monthlyLimit = UserDefaults.standard.string(forKey: "security.monthlyLimit") ?? ""
        requireWhitelist = UserDefaults.standard.bool(forKey: "security.requireWhitelist")
        
        // Check key rotation status
        checkKeyRotation()
    }
    
    func saveSpendingLimits() {
        isLoading = true
        
        Task {
            do {
                try HawalaBridge.shared.setSpendingLimits(
                    walletId: selectedWalletId,
                    perTxLimit: perTxLimit.isEmpty ? nil : perTxLimit,
                    dailyLimit: dailyLimit.isEmpty ? nil : dailyLimit,
                    weeklyLimit: weeklyLimit.isEmpty ? nil : weeklyLimit,
                    monthlyLimit: monthlyLimit.isEmpty ? nil : monthlyLimit,
                    requireWhitelist: requireWhitelist
                )
                
                // Save to UserDefaults
                UserDefaults.standard.set(perTxLimit, forKey: "security.perTxLimit")
                UserDefaults.standard.set(dailyLimit, forKey: "security.dailyLimit")
                UserDefaults.standard.set(weeklyLimit, forKey: "security.weeklyLimit")
                UserDefaults.standard.set(monthlyLimit, forKey: "security.monthlyLimit")
                UserDefaults.standard.set(requireWhitelist, forKey: "security.requireWhitelist")
                
                alertMessage = "Spending limits updated successfully"
                showAlert = true
            } catch {
                alertMessage = "Failed to save limits: \(error.localizedDescription)"
                showAlert = true
            }
            isLoading = false
        }
    }
    
    func whitelistAddress(_ address: String, label: String) {
        Task {
            do {
                try HawalaBridge.shared.whitelistAddress(walletId: selectedWalletId, address: address)
                let newEntry = WhitelistedAddress(address: address, label: label, addedDate: Date())
                whitelistedAddresses.append(newEntry)
                alertMessage = "Address added to whitelist"
                showAlert = true
            } catch {
                alertMessage = "Failed to whitelist: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
    
    func blacklistAddress(_ address: String, reason: String) {
        Task {
            do {
                try HawalaBridge.shared.blacklistAddress(address, reason: reason)
                let newEntry = BlacklistedAddress(address: address, reason: reason, source: "user")
                blacklistedAddresses.append(newEntry)
                alertMessage = "Address blocked"
                showAlert = true
            } catch {
                alertMessage = "Failed to block: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
    
    func checkKeyRotation() {
        Task {
            do {
                let result = try HawalaBridge.shared.checkKeyRotation(walletId: selectedWalletId)
                lastRotationCheck = Date()
                
                if result.needsRotation {
                    if let info = result.keysToRotate.first {
                        daysSinceLastRotation = Int(info.ageDays)
                        keyRotationStatus = daysSinceLastRotation > 365 ? .overdue : .dueSoon
                    }
                } else {
                    keyRotationStatus = .healthy
                    daysSinceLastRotation = Int(result.keysToRotate.first?.ageDays ?? 0)
                }
            } catch {
                print("Key rotation check failed: \(error)")
            }
        }
    }
    
    func saveThreatSettings() {
        UserDefaults.standard.set(threatProtectionEnabled, forKey: "security.threatProtection")
        UserDefaults.standard.set(autoBlockScams, forKey: "security.autoBlockScams")
        UserDefaults.standard.set(threatSensitivity.rawValue, forKey: "security.threatSensitivity")
    }
}

// MARK: - Helper Extension

extension UserDefaults {
    func contains(key: String) -> Bool {
        return object(forKey: key) != nil
    }
}

// MARK: - Section Components

struct SecuritySection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.headline)
            }
            
            content()
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
        }
    }
}

// MARK: - Threat Protection Section

struct ThreatProtectionSection: View {
    @ObservedObject var viewModel: SecurityPoliciesViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Enable Threat Detection", isOn: $viewModel.threatProtectionEnabled)
                .onChange(of: viewModel.threatProtectionEnabled) { _ in
                    viewModel.saveThreatSettings()
                }
            
            if viewModel.threatProtectionEnabled {
                Toggle("Auto-block known scam addresses", isOn: $viewModel.autoBlockScams)
                    .onChange(of: viewModel.autoBlockScams) { _ in
                        viewModel.saveThreatSettings()
                    }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sensitivity Level")
                        .font(.subheadline.weight(.medium))
                    
                    Picker("", selection: $viewModel.threatSensitivity) {
                        ForEach(SecurityPoliciesViewModel.ThreatSensitivity.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: viewModel.threatSensitivity) { _ in
                        viewModel.saveThreatSettings()
                    }
                    
                    Text(viewModel.threatSensitivity.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Threat indicators
            HStack(spacing: 16) {
                ThreatIndicator(label: "Scams Blocked", count: 0, color: .red)
                ThreatIndicator(label: "Warnings Shown", count: 0, color: .orange)
                ThreatIndicator(label: "Safe Txs", count: 0, color: .green)
            }
        }
    }
}

struct ThreatIndicator: View {
    let label: String
    let count: Int
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2.bold())
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Spending Limits Section

struct SpendingLimitsSection: View {
    @ObservedObject var viewModel: SecurityPoliciesViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set limits to protect against unauthorized large transactions")
                .font(.caption)
                .foregroundColor(.secondary)
            
            LimitTextField(label: "Per Transaction", placeholder: "e.g., 0.1 BTC", value: $viewModel.perTxLimit)
            LimitTextField(label: "Daily Limit", placeholder: "e.g., 0.5 BTC", value: $viewModel.dailyLimit)
            LimitTextField(label: "Weekly Limit", placeholder: "e.g., 2.0 BTC", value: $viewModel.weeklyLimit)
            LimitTextField(label: "Monthly Limit", placeholder: "e.g., 5.0 BTC", value: $viewModel.monthlyLimit)
            
            Toggle("Require whitelisted recipient", isOn: $viewModel.requireWhitelist)
            
            HStack {
                Spacer()
                Button(action: { viewModel.saveSpendingLimits() }) {
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Label("Save Limits", systemImage: "checkmark.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading)
            }
        }
    }
}

struct LimitTextField: View {
    let label: String
    let placeholder: String
    @Binding var value: String
    
    var body: some View {
        HStack {
            Text(label)
                .frame(width: 120, alignment: .leading)
            TextField(placeholder, text: $value)
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - Whitelist Section

struct WhitelistSection: View {
    @ObservedObject var viewModel: SecurityPoliciesViewModel
    @State private var newAddress = ""
    @State private var newLabel = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add trusted addresses to skip security checks")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Add new address
            HStack(spacing: 8) {
                TextField("Address", text: $newAddress)
                    .textFieldStyle(.roundedBorder)
                TextField("Label", text: $newLabel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Button(action: addAddress) {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(newAddress.isEmpty)
            }
            
            // List
            if viewModel.whitelistedAddresses.isEmpty {
                Text("No whitelisted addresses yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.whitelistedAddresses) { addr in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(addr.label)
                                .font(.subheadline.weight(.medium))
                            Text(addr.address.prefix(20) + "..." + addr.address.suffix(8))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(action: { removeWhitelisted(addr) }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    private func addAddress() {
        viewModel.whitelistAddress(newAddress, label: newLabel.isEmpty ? "Unnamed" : newLabel)
        newAddress = ""
        newLabel = ""
    }
    
    private func removeWhitelisted(_ addr: SecurityPoliciesViewModel.WhitelistedAddress) {
        viewModel.whitelistedAddresses.removeAll { $0.id == addr.id }
    }
}

// MARK: - Blacklist Section

struct BlacklistSection: View {
    @ObservedObject var viewModel: SecurityPoliciesViewModel
    @State private var newAddress = ""
    @State private var newReason = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Block addresses you don't want to interact with")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Add new
            HStack(spacing: 8) {
                TextField("Address to block", text: $newAddress)
                    .textFieldStyle(.roundedBorder)
                TextField("Reason", text: $newReason)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                Button(action: addBlacklist) {
                    Image(systemName: "hand.raised.slash.fill")
                        .foregroundColor(.red)
                }
                .disabled(newAddress.isEmpty)
            }
            
            // List
            if viewModel.blacklistedAddresses.isEmpty {
                Text("No blocked addresses")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.blacklistedAddresses) { addr in
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        VStack(alignment: .leading) {
                            Text(addr.address.prefix(20) + "..." + addr.address.suffix(8))
                                .font(.subheadline)
                            Text(addr.reason)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(addr.source == "system" ? "System" : "Manual")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.2)))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    private func addBlacklist() {
        viewModel.blacklistAddress(newAddress, reason: newReason.isEmpty ? "Manually blocked" : newReason)
        newAddress = ""
        newReason = ""
    }
}

// MARK: - Key Rotation Section

struct KeyRotationSection: View {
    @ObservedObject var viewModel: SecurityPoliciesViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: viewModel.keyRotationStatus.icon)
                    .foregroundColor(viewModel.keyRotationStatus.color)
                    .font(.title2)
                
                VStack(alignment: .leading) {
                    Text(statusText)
                        .font(.subheadline.weight(.medium))
                    Text("Last checked: \(lastCheckText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { viewModel.checkKeyRotation() }) {
                    Label("Check Now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            
            if viewModel.keyRotationStatus != .healthy {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Consider rotating your keys for enhanced security. Keys have been in use for \(viewModel.daysSinceLastRotation) days.")
                        .font(.caption)
                }
                .padding()
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            
            // Key info
            VStack(alignment: .leading, spacing: 8) {
                Text("Key Security Tips")
                    .font(.caption.weight(.medium))
                Text("• Rotate keys annually for best security")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("• Always backup before rotating")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("• Key rotation creates a new wallet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var statusText: String {
        switch viewModel.keyRotationStatus {
        case .healthy: return "Keys are secure"
        case .dueSoon: return "Rotation recommended soon"
        case .overdue: return "Key rotation overdue"
        }
    }
    
    private var lastCheckText: String {
        if let date = viewModel.lastRotationCheck {
            let formatter = RelativeDateTimeFormatter()
            return formatter.localizedString(for: date, relativeTo: Date())
        }
        return "Never"
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    SecurityPoliciesView()
}
#endif
#endif
#endif
