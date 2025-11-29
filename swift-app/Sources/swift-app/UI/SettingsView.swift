import SwiftUI

// MARK: - Settings View
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    // Settings State
    @AppStorage("biometricLockEnabled") private var biometricLockEnabled = false
    @AppStorage("autoLockTimeout") private var autoLockTimeout = 5 // minutes
    @AppStorage("showBalances") private var showBalances = true
    @AppStorage("enableNotifications") private var enableNotifications = true
    @AppStorage("transactionAlerts") private var transactionAlerts = true
    @AppStorage("priceAlerts") private var priceAlerts = false
    @AppStorage("networkAlerts") private var networkAlerts = true
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("currency") private var currency = "USD"
    @AppStorage("theme") private var theme = "dark"
    
    @State private var showAbout = false
    @State private var showBackupSheet = false
    @State private var showResetConfirm = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            // Settings content
            ScrollView {
                VStack(spacing: HawalaTheme.Spacing.xl) {
                    // Security Section
                    securitySection
                    
                    // Privacy Section
                    privacySection
                    
                    // Notifications Section
                    notificationsSection
                    
                    // Network & Sync Section
                    networkSection
                    
                    // Appearance Section
                    appearanceSection
                    
                    // General Section
                    generalSection
                    
                    // About Section
                    aboutSection
                    
                    // Danger Zone
                    dangerZone
                }
                .padding(HawalaTheme.Spacing.xl)
            }
        }
        .background(HawalaTheme.Colors.background)
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        .alert("Reset Wallet", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                // Handle reset
                ToastManager.shared.info("This would reset the wallet")
            }
        } message: {
            Text("Are you sure you want to reset your wallet? This action cannot be undone. Make sure you have backed up your seed phrase.")
        }
    }
    
    // MARK: - Header
    private var header: some View {
        HStack {
            Text("Settings")
                .font(HawalaTheme.Typography.h2)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(HawalaTheme.Spacing.xl)
        .background(HawalaTheme.Colors.backgroundSecondary)
    }
    
    // MARK: - Security Section
    private var securitySection: some View {
        SettingsSection("Security") {
            SettingsToggleRow(
                icon: "faceid",
                iconColor: HawalaTheme.Colors.success,
                title: "Biometric Lock",
                subtitle: "Require Face ID to open",
                isOn: $biometricLockEnabled
            )
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.leading, 56)
            
            SettingsRow(
                icon: "timer",
                iconColor: HawalaTheme.Colors.warning,
                title: "Auto-Lock Timeout",
                subtitle: "\(autoLockTimeout) minutes"
            ) {
                // Show timeout picker
                cycleAutoLockTimeout()
            }
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.leading, 56)
            
            SettingsRow(
                icon: "key.fill",
                iconColor: HawalaTheme.Colors.accent,
                title: "Change Passcode",
                subtitle: nil
            ) {
                ToastManager.shared.info("Passcode change would open here")
            }
        }
    }
    
    // MARK: - Privacy Section
    private var privacySection: some View {
        SettingsSection("Privacy") {
            SettingsToggleRow(
                icon: "eye.slash.fill",
                iconColor: HawalaTheme.Colors.info,
                title: "Hide Balances",
                subtitle: "Show ••••• instead of amounts",
                isOn: Binding(
                    get: { !showBalances },
                    set: { showBalances = !$0 }
                )
            )
        }
    }
    
    // MARK: - Notifications Section
    private var notificationsSection: some View {
        SettingsSection("Notifications") {
            SettingsToggleRow(
                icon: "bell.fill",
                iconColor: HawalaTheme.Colors.warning,
                title: "Enable Notifications",
                subtitle: nil,
                isOn: $enableNotifications
            )
            
            if enableNotifications {
                Divider()
                    .background(HawalaTheme.Colors.border)
                    .padding(.leading, 56)
                
                SettingsToggleRow(
                    icon: "arrow.left.arrow.right",
                    iconColor: HawalaTheme.Colors.success,
                    title: "Transaction Alerts",
                    subtitle: "When you send or receive",
                    isOn: $transactionAlerts
                )
                
                Divider()
                    .background(HawalaTheme.Colors.border)
                    .padding(.leading, 56)
                
                SettingsToggleRow(
                    icon: "chart.line.uptrend.xyaxis",
                    iconColor: HawalaTheme.Colors.accent,
                    title: "Price Alerts",
                    subtitle: "Significant price changes",
                    isOn: $priceAlerts
                )
                
                Divider()
                    .background(HawalaTheme.Colors.border)
                    .padding(.leading, 56)
                
                SettingsToggleRow(
                    icon: "network",
                    iconColor: HawalaTheme.Colors.info,
                    title: "Network Alerts",
                    subtitle: "Connectivity issues",
                    isOn: $networkAlerts
                )
            }
        }
    }
    
    // MARK: - Network Section
    private var networkSection: some View {
        SettingsSection("Network & Sync") {
            // WebSocket real-time prices
            WebSocketConnectionControl()
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.leading, 56)
            
            // Background sync
            SyncSettingsControl()
        }
    }
    
    // MARK: - Appearance Section
    private var appearanceSection: some View {
        SettingsSection("Appearance") {
            SettingsRow(
                icon: "paintbrush.fill",
                iconColor: HawalaTheme.Colors.accent,
                title: "Theme",
                subtitle: theme.capitalized
            ) {
                cycleTheme()
            }
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.leading, 56)
            
            SettingsRow(
                icon: "dollarsign.circle.fill",
                iconColor: HawalaTheme.Colors.success,
                title: "Display Currency",
                subtitle: currency
            ) {
                cycleCurrency()
            }
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.leading, 56)
            
            SettingsToggleRow(
                icon: "hand.tap.fill",
                iconColor: HawalaTheme.Colors.info,
                title: "Haptic Feedback",
                subtitle: "Tactile response on actions",
                isOn: $hapticFeedback
            )
        }
    }
    
    // MARK: - General Section
    private var generalSection: some View {
        SettingsSection("General") {
            SettingsRow(
                icon: "square.and.arrow.up.fill",
                iconColor: HawalaTheme.Colors.success,
                title: "Backup Wallet",
                subtitle: "View recovery phrase"
            ) {
                showBackupSheet = true
            }
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.leading, 56)
            
            SettingsRow(
                icon: "network",
                iconColor: HawalaTheme.Colors.info,
                title: "Network Settings",
                subtitle: "RPC endpoints, network selection"
            ) {
                ToastManager.shared.info("Network settings would open here")
            }
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.leading, 56)
            
            SettingsRow(
                icon: "doc.text.fill",
                iconColor: HawalaTheme.Colors.textSecondary,
                title: "Export Transaction History",
                subtitle: "Download as CSV"
            ) {
                ToastManager.shared.success("Export Started", message: "Preparing your transaction history...")
            }
        }
    }
    
    // MARK: - About Section
    private var aboutSection: some View {
        SettingsSection("About") {
            SettingsRow(
                icon: "info.circle.fill",
                iconColor: HawalaTheme.Colors.accent,
                title: "About Hawala",
                subtitle: "Version 2.0.0"
            ) {
                showAbout = true
            }
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.leading, 56)
            
            SettingsRow(
                icon: "doc.plaintext.fill",
                iconColor: HawalaTheme.Colors.textSecondary,
                title: "Terms of Service",
                subtitle: nil
            ) {
                // Open terms
            }
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.leading, 56)
            
            SettingsRow(
                icon: "hand.raised.fill",
                iconColor: HawalaTheme.Colors.textSecondary,
                title: "Privacy Policy",
                subtitle: nil
            ) {
                // Open privacy
            }
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.leading, 56)
            
            SettingsRow(
                icon: "questionmark.circle.fill",
                iconColor: HawalaTheme.Colors.info,
                title: "Help & Support",
                subtitle: nil
            ) {
                // Open support
            }
        }
    }
    
    // MARK: - Danger Zone
    private var dangerZone: some View {
        SettingsSection("Danger Zone") {
            SettingsRow(
                icon: "trash.fill",
                iconColor: HawalaTheme.Colors.error,
                title: "Reset Wallet",
                subtitle: "Erase all data from this device"
            ) {
                showResetConfirm = true
            }
        }
    }
    
    // MARK: - Helper Methods
    private func cycleAutoLockTimeout() {
        let options = [1, 5, 15, 30, 60]
        if let currentIndex = options.firstIndex(of: autoLockTimeout) {
            autoLockTimeout = options[(currentIndex + 1) % options.count]
        } else {
            autoLockTimeout = 5
        }
        ToastManager.shared.info("Auto-lock: \(autoLockTimeout) min")
    }
    
    private func cycleTheme() {
        let themes = ["dark", "light", "system"]
        if let currentIndex = themes.firstIndex(of: theme) {
            theme = themes[(currentIndex + 1) % themes.count]
        } else {
            theme = "dark"
        }
        ToastManager.shared.info("Theme: \(theme.capitalized)")
    }
    
    private func cycleCurrency() {
        let currencies = ["USD", "EUR", "GBP", "JPY", "BTC", "ETH"]
        if let currentIndex = currencies.firstIndex(of: currency) {
            currency = currencies[(currentIndex + 1) % currencies.count]
        } else {
            currency = "USD"
        }
    }
}

// MARK: - About View
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: HawalaTheme.Spacing.xl) {
            // Close button
            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Spacer()
            
            // Logo
            VStack(spacing: HawalaTheme.Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    HawalaTheme.Colors.accent,
                                    HawalaTheme.Colors.accentHover
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundColor(.white)
                }
                
                Text("Hawala")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("Version 2.0.0")
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            // Description
            Text("A modern, secure multi-chain cryptocurrency wallet for macOS.")
                .font(HawalaTheme.Typography.body)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, HawalaTheme.Spacing.xxl)
            
            // Features list
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                FeatureRow(icon: "shield.fill", text: "Self-custody security")
                FeatureRow(icon: "link", text: "Multi-chain support")
                FeatureRow(icon: "eye.slash.fill", text: "Privacy focused")
                FeatureRow(icon: "bolt.fill", text: "Lightning fast")
            }
            .padding(HawalaTheme.Spacing.xl)
            .background(HawalaTheme.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous))
            
            Spacer()
            
            // Footer
            VStack(spacing: HawalaTheme.Spacing.xs) {
                Text("Made with ❤️ for the crypto community")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                Text("© 2024 Hawala. All rights reserved.")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            .padding(.bottom, HawalaTheme.Spacing.xl)
        }
        .frame(width: 400, height: 600)
        .background(HawalaTheme.Colors.background)
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(HawalaTheme.Colors.accent)
                .frame(width: 24)
            
            Text(text)
                .font(HawalaTheme.Typography.body)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
        }
    }
}

#Preview {
    SettingsView()
        .frame(width: 500, height: 800)
}
