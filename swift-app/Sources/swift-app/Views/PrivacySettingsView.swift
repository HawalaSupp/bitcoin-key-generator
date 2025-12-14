import SwiftUI

/// Settings view for configuring privacy options
struct PrivacySettingsView: View {
    @ObservedObject private var privacyManager = PrivacyManager.shared
    @ObservedObject private var duressManager = DuressManager.shared
    @State private var showingResetConfirmation = false
    
    var body: some View {
        Form {
            // MARK: - Privacy Mode Section
            Section {
                Toggle("Enable Privacy Mode", isOn: $privacyManager.isPrivacyModeEnabled)
                    .toggleStyle(.switch)
                
                if privacyManager.isPrivacyModeEnabled {
                    Text("Privacy mode is active. Sensitive data is hidden.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } header: {
                Label("Privacy Mode", systemImage: "eye.slash")
            } footer: {
                Text("When enabled, privacy mode hides sensitive information from view. Tap on hidden content to temporarily reveal it.")
            }
            
            // MARK: - Privacy Options
            Section {
                Toggle("Hide Balances", isOn: $privacyManager.hideBalances)
                    .disabled(!privacyManager.isPrivacyModeEnabled)
                
                Toggle("Blur Addresses", isOn: $privacyManager.blurAddresses)
                    .disabled(!privacyManager.isPrivacyModeEnabled)
                
                Toggle("Hide Transaction History", isOn: $privacyManager.hideTransactionHistory)
                    .disabled(!privacyManager.isPrivacyModeEnabled)
                
                Toggle("Pause Price Fetching", isOn: $privacyManager.pausePriceFetching)
                    .disabled(!privacyManager.isPrivacyModeEnabled)
            } header: {
                Label("When Privacy Mode is On", systemImage: "lock.shield")
            } footer: {
                Text("Pausing price fetching stops network requests to price APIs, reducing your digital footprint.")
            }
            
            // MARK: - Screenshot Prevention
            Section {
                Toggle("Prevent Screenshots", isOn: $privacyManager.disableScreenshots)
                    .disabled(!privacyManager.isPrivacyModeEnabled)
            } header: {
                Label("Screen Capture", systemImage: "rectangle.dashed.badge.record")
            } footer: {
                Text("Attempts to prevent screen captures. Effectiveness depends on your operating system.")
            }
            
            // MARK: - Duress Protection
            Section {
                NavigationLink(destination: DuressSettingsView()) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Duress Protection")
                            Text(duressManager.isDuressEnabled ? "Configured" : "Not Set Up")
                                .font(.caption)
                                .foregroundColor(duressManager.isDuressEnabled ? .green : .secondary)
                        }
                        Spacer()
                        if duressManager.isDuressEnabled {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.green)
                        }
                    }
                }
            } header: {
                Label("Duress Mode", systemImage: "shield.lefthalf.filled")
            } footer: {
                Text("Create a decoy wallet with a separate passcode for protection under coercion.")
            }
            
            // MARK: - Quick Actions
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Status")
                            .font(.headline)
                        Text(privacyManager.isPrivacyModeEnabled ? "Privacy Mode Active" : "Normal Mode")
                            .font(.caption)
                            .foregroundColor(privacyManager.isPrivacyModeEnabled ? .orange : .green)
                    }
                    
                    Spacer()
                    
                    Circle()
                        .fill(privacyManager.isPrivacyModeEnabled ? Color.orange : Color.green)
                        .frame(width: 12, height: 12)
                }
                
                Button(action: {
                    privacyManager.temporaryReveal()
                }) {
                    Label("Reveal Content (5 seconds)", systemImage: "eye")
                }
                .disabled(!privacyManager.isPrivacyModeEnabled || !privacyManager.shouldHideBalances)
            } header: {
                Label("Quick Actions", systemImage: "bolt")
            }
            
            // MARK: - Tips
            Section {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        tipRow(icon: "hand.tap", text: "Tap any hidden content to reveal it temporarily")
                        tipRow(icon: "keyboard", text: "Use ⌘P to quickly toggle privacy mode")
                        tipRow(icon: "eye.slash", text: "The eye icon in the toolbar shows current status")
                        tipRow(icon: "clock", text: "Revealed content hides again after 5 seconds")
                    }
                    .padding(.vertical, 8)
                } label: {
                    Label("Tips", systemImage: "lightbulb")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Privacy")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                PrivacyToggleButton()
            }
        }
    }
    
    @ViewBuilder
    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PrivacySettingsView()
    }
    .frame(width: 500, height: 700)
}

// MARK: - Privacy Settings Card (for main settings)

struct PrivacySettingsCard: View {
    @ObservedObject private var privacyManager = PrivacyManager.shared
    
    var body: some View {
        NavigationLink(destination: PrivacySettingsView()) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(privacyManager.isPrivacyModeEnabled ? Color.orange.opacity(0.15) : Color.gray.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: privacyManager.isPrivacyModeEnabled ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 18))
                        .foregroundColor(privacyManager.isPrivacyModeEnabled ? .orange : .secondary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Privacy Mode")
                        .font(.headline)
                    Text(privacyManager.isPrivacyModeEnabled ? "Active - Data Hidden" : "Inactive")
                        .font(.caption)
                        .foregroundColor(privacyManager.isPrivacyModeEnabled ? .orange : .secondary)
                }
                
                Spacer()
                
                if privacyManager.isPrivacyModeEnabled {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                }
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }
}
