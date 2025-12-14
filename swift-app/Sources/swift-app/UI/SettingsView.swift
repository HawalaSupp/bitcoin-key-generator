import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Settings View
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var passcodeManager = PasscodeManager.shared
    @ObservedObject var themeManager = ThemeManager.shared
    
    // Settings State
    @AppStorage("biometricLockEnabled") private var biometricLockEnabled = false
    @AppStorage("showBalances") private var showBalances = true
    @AppStorage("enableNotifications") private var enableNotifications = true
    @AppStorage("transactionAlerts") private var transactionAlerts = true
    @AppStorage("priceAlerts") private var priceAlerts = false
    @AppStorage("networkAlerts") private var networkAlerts = true
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("hawala.selectedFiatCurrency") private var currency = "USD"
    @AppStorage("showTestnets") private var showTestnets = false
    
    @State private var showAbout = false
    @State private var showBackupSheet = false
    @State private var showNetworkSettingsSheet = false
    @State private var showExportSheet = false
    @State private var showResetConfirm = false
    @State private var showChangePasscode = false
    @State private var showSetPasscode = false
    @State private var showAutoLockPicker = false
    @State private var showTermsSheet = false
    @State private var showPrivacySheet = false
    @State private var showSupportSheet = false
    @State private var showDebugConsole = false
    @State private var isForceSyncing = false
    @State private var showCustomTokensSheet = false
    @State private var showAddressManagement = false
    @State private var showStealthAddresses = false
    @State private var showScheduledTransactions = false
    @State private var showFeeIntelligence = false
    @State private var showTransactionIntentDemo = false
    
    // Debug/Developer info
    @StateObject private var debugLogger = DebugLogger.shared
    
    // Computed color scheme based on theme
    private var selectedColorScheme: ColorScheme? {
        themeManager.currentTheme.colorScheme
    }
    
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
                    
                    // Tokens Section
                    tokensSection
                    
                    // General Section
                    generalSection
                    
                    // Developer Section
                    developerSection
                    
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
        .sheet(isPresented: $showChangePasscode) {
            ChangePasscodeSheet(passcodeManager: passcodeManager)
        }
        .sheet(isPresented: $showSetPasscode) {
            PasscodeSetupSheet(passcodeManager: passcodeManager) {
                showSetPasscode = false
            }
        }
        .sheet(isPresented: $showBackupSheet) {
            BackupWalletSheet()
        }
        .sheet(isPresented: $showNetworkSettingsSheet) {
            NetworkSettingsSheet()
        }
        .sheet(isPresented: $showExportSheet) {
            ExportHistorySheet()
        }
        .sheet(isPresented: $showTermsSheet) {
            TermsOfServiceSheet()
        }
        .sheet(isPresented: $showPrivacySheet) {
            PrivacyPolicySheet()
        }
        .sheet(isPresented: $showSupportSheet) {
            HelpSupportSheet()
        }
        .sheet(isPresented: $showDebugConsole) {
            DebugConsoleSheet()
        }
        .sheet(isPresented: $showCustomTokensSheet) {
            CustomTokensSheet()
        }
        .sheet(isPresented: $showAddressManagement) {
            AddressManagementView()
        }
        .sheet(isPresented: $showStealthAddresses) {
            StealthAddressView()
        }
        .sheet(isPresented: $showScheduledTransactions) {
            ScheduledTransactionsView()
        }
        .sheet(isPresented: $showFeeIntelligence) {
            FeeIntelligenceView()
                .frame(width: 700, height: 800)
        }
        .sheet(isPresented: $showTransactionIntentDemo) {
            TransactionIntentDemoView()
                .frame(width: 550, height: 750)
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
        .preferredColorScheme(selectedColorScheme)
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
            
            AutoLockTimeoutPicker(
                autoLockTimeout: Binding(
                    get: { passcodeManager.currentAutoLockMinutes },
                    set: { passcodeManager.setAutoLockTimeout($0) }
                )
            )
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.leading, 56)
            
            // Show "Set Passcode" or "Change Passcode" based on whether passcode exists
            if passcodeManager.hasPasscode {
                SettingsRow(
                    icon: "key.fill",
                    iconColor: HawalaTheme.Colors.accent,
                    title: "Change Passcode",
                    subtitle: "Update your security code"
                ) {
                    showChangePasscode = true
                }
            } else {
                SettingsRow(
                    icon: "key.fill",
                    iconColor: HawalaTheme.Colors.warning,
                    title: "Set Passcode",
                    subtitle: "Protect your wallet"
                ) {
                    showSetPasscode = true
                }
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
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.leading, 56)
            
            SettingsRow(
                icon: "list.bullet.rectangle",
                iconColor: HawalaTheme.Colors.accent,
                title: "Address Management",
                subtitle: "HD wallet addresses, reuse warnings"
            ) {
                showAddressManagement = true
            }
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.leading, 56)
            
            SettingsRow(
                icon: "eye.slash.circle.fill",
                iconColor: HawalaTheme.Colors.success,
                title: "Stealth Addresses",
                subtitle: "One-time addresses for maximum privacy"
            ) {
                showStealthAddresses = true
            }
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
                
                // Transaction Alerts with Test button
                HStack {
                    SettingsToggleRow(
                        icon: "arrow.left.arrow.right",
                        iconColor: HawalaTheme.Colors.success,
                        title: "Transaction Alerts",
                        subtitle: "When you send or receive",
                        isOn: $transactionAlerts
                    )
                    
                    Button(action: {
                        triggerHaptic()
                        sendTestNotification(type: .transaction)
                    }) {
                        Text("Test")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.accent)
                            .padding(.horizontal, HawalaTheme.Spacing.sm)
                            .padding(.vertical, 4)
                            .background(HawalaTheme.Colors.accent.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, HawalaTheme.Spacing.md)
                }
                
                Divider()
                    .background(HawalaTheme.Colors.border)
                    .padding(.leading, 56)
                
                // Price Alerts with Test button
                HStack {
                    SettingsToggleRow(
                        icon: "chart.line.uptrend.xyaxis",
                        iconColor: HawalaTheme.Colors.accent,
                        title: "Price Alerts",
                        subtitle: "Significant price changes",
                        isOn: $priceAlerts
                    )
                    
                    Button(action: {
                        triggerHaptic()
                        sendTestNotification(type: .price)
                    }) {
                        Text("Test")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.accent)
                            .padding(.horizontal, HawalaTheme.Spacing.sm)
                            .padding(.vertical, 4)
                            .background(HawalaTheme.Colors.accent.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, HawalaTheme.Spacing.md)
                }
                
                Divider()
                    .background(HawalaTheme.Colors.border)
                    .padding(.leading, 56)
                
                // Network Alerts with Test button
                HStack {
                    SettingsToggleRow(
                        icon: "network",
                        iconColor: HawalaTheme.Colors.info,
                        title: "Network Alerts",
                        subtitle: "Connectivity issues",
                        isOn: $networkAlerts
                    )
                    
                    Button(action: {
                        triggerHaptic()
                        sendTestNotification(type: .network)
                    }) {
                        Text("Test")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.accent)
                            .padding(.horizontal, HawalaTheme.Spacing.sm)
                            .padding(.vertical, 4)
                            .background(HawalaTheme.Colors.accent.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, HawalaTheme.Spacing.md)
                }
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
            // Theme Picker
            ThemePickerRow()
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.leading, 56)
            
            // Currency Dropdown
            CurrencyPickerRow(currency: $currency)
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.leading, 56)
            
            // Haptic Feedback with Test button
            HStack {
                SettingsToggleRow(
                    icon: "hand.tap.fill",
                    iconColor: HawalaTheme.Colors.info,
                    title: "Haptic Feedback",
                    subtitle: "Tactile response on actions",
                    isOn: $hapticFeedback
                )
                
                Button(action: {
                    triggerHaptic(force: true)
                    ToastManager.shared.info("Haptic triggered!")
                }) {
                    Text("Test")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.accent)
                        .padding(.horizontal, HawalaTheme.Spacing.sm)
                        .padding(.vertical, 4)
                        .background(HawalaTheme.Colors.accent.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(.trailing, HawalaTheme.Spacing.md)
            }
        }
    }
    
    // MARK: - Tokens Section
    private var tokensSection: some View {
        SettingsSection("Tokens") {
            SettingsRow(
                icon: "circle.hexagongrid.fill",
                iconColor: HawalaTheme.Colors.accent,
                title: "Custom Tokens",
                subtitle: "Add ERC-20, BEP-20, or SPL tokens"
            ) {
                triggerHaptic()
                showCustomTokensSheet = true
            }
        }
    }
    
    // MARK: - General Section
    private var generalSection: some View {
        SettingsSection("General") {
            SettingsRow(
                icon: "calendar.badge.clock",
                iconColor: HawalaTheme.Colors.accent,
                title: "Scheduled Transactions",
                subtitle: "Automate recurring payments"
            ) {
                triggerHaptic()
                showScheduledTransactions = true
            }
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.leading, 56)
            
            SettingsRow(
                icon: "chart.line.uptrend.xyaxis",
                iconColor: .orange,
                title: "Fee Intelligence",
                subtitle: "Optimize transaction fees"
            ) {
                triggerHaptic()
                showFeeIntelligence = true
            }
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.leading, 56)
            
            SettingsRow(
                icon: "doc.text.magnifyingglass",
                iconColor: .purple,
                title: "Transaction Intent Preview",
                subtitle: "Human-readable transaction signing"
            ) {
                triggerHaptic()
                showTransactionIntentDemo = true
            }
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.leading, 56)
            
            SettingsRow(
                icon: "square.and.arrow.up.fill",
                iconColor: HawalaTheme.Colors.success,
                title: "Backup Wallet",
                subtitle: "View recovery phrase"
            ) {
                triggerHaptic()
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
                triggerHaptic()
                showNetworkSettingsSheet = true
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
                triggerHaptic()
                showExportSheet = true
            }
        }
    }
    
    // MARK: - Developer Section
    private var developerSection: some View {
        SettingsSection("Developer") {
            SettingsToggleRow(
                icon: "testtube.2",
                iconColor: HawalaTheme.Colors.warning,
                title: "Show Testnets",
                subtitle: "Display Bitcoin Testnet & Ethereum Sepolia",
                isOn: $showTestnets
            )
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.leading, 56)
            
            // Debug Console
            SettingsRow(
                icon: "terminal.fill",
                iconColor: HawalaTheme.Colors.accent,
                title: "Debug Console",
                subtitle: "\(debugLogger.entries.count) log entries"
            ) {
                triggerHaptic()
                showDebugConsole = true
            }
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.leading, 56)
            
            // Network Latency
            HStack {
                ZStack {
                    Circle()
                        .fill(HawalaTheme.Colors.info.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(HawalaTheme.Colors.info)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Network Latency")
                        .font(HawalaTheme.Typography.body)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    Text(debugLogger.latencyDescription)
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
                
                Spacer()
                
                // Latency indicator
                Circle()
                    .fill(latencyIndicatorColor)
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, HawalaTheme.Spacing.md)
            .padding(.vertical, HawalaTheme.Spacing.sm)
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.leading, 56)
            
            // WebSocket Status
            HStack {
                ZStack {
                    Circle()
                        .fill(HawalaTheme.Colors.success.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(HawalaTheme.Colors.success)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("WebSocket")
                        .font(HawalaTheme.Typography.body)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    Text(debugLogger.webSocketStatus)
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(debugLogger.webSocketStatus == "Connected" ? HawalaTheme.Colors.success : HawalaTheme.Colors.textSecondary)
                }
                
                Spacer()
                
                // Force Sync button
                Button(action: {
                    triggerHaptic()
                    forceSyncWebSocket()
                }) {
                    HStack(spacing: 4) {
                        if isForceSyncing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text("Sync")
                            .font(HawalaTheme.Typography.caption)
                    }
                    .foregroundColor(HawalaTheme.Colors.accent)
                    .padding(.horizontal, HawalaTheme.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(HawalaTheme.Colors.accent.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(isForceSyncing)
            }
            .padding(.horizontal, HawalaTheme.Spacing.md)
            .padding(.vertical, HawalaTheme.Spacing.sm)
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.leading, 56)
            
            // Clear Cache
            SettingsRow(
                icon: "trash.fill",
                iconColor: HawalaTheme.Colors.error,
                title: "Clear App Cache",
                subtitle: "Removes cached data"
            ) {
                triggerHaptic()
                clearAppCache()
            }
        }
    }
    
    // Latency indicator color based on average latency
    private var latencyIndicatorColor: Color {
        guard let avg = debugLogger.averageLatency else { return .gray }
        if avg < 0.2 { return HawalaTheme.Colors.success }
        if avg < 0.5 { return HawalaTheme.Colors.warning }
        return HawalaTheme.Colors.error
    }
    
    // Force sync WebSocket
    private func forceSyncWebSocket() {
        isForceSyncing = true
        debugLogger.log("Force sync requested", level: .info, category: .network)
        
        // Post notification to trigger WebSocket reconnection
        NotificationCenter.default.post(name: NSNotification.Name("ForceWebSocketReconnect"), object: nil)
        
        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isForceSyncing = false
        }
    }
    
    // Clear app cache
    private func clearAppCache() {
        // Clear asset cache
        AssetCache.shared.clearCache()
        
        // Clear sparkline cache and refetch
        SparklineCache.shared.sparklines.removeAll()
        
        // Clear debug logs
        debugLogger.clear()
        
        ToastManager.shared.success("Cache cleared")
        
        // Trigger sparkline refetch after a short delay
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
            SparklineCache.shared.fetchAllSparklines(force: true)
        }
    }
    
    // MARK: - About Section
    private var aboutSection: some View {
        SettingsSection("About") {
            SettingsRow(
                icon: "info.circle.fill",
                iconColor: HawalaTheme.Colors.accent,
                title: "About Hawala",
                subtitle: "Version \(AppVersion.version)"
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
                triggerHaptic()
                showTermsSheet = true
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
                triggerHaptic()
                showPrivacySheet = true
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
                triggerHaptic()
                showSupportSheet = true
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
    private func cycleTheme() {
        let themes = ThemeManager.AppTheme.allCases
        if let currentIndex = themes.firstIndex(of: themeManager.currentTheme) {
            themeManager.currentTheme = themes[(currentIndex + 1) % themes.count]
        } else {
            themeManager.currentTheme = .dark
        }
        ToastManager.shared.info("Theme: \(themeManager.currentTheme.rawValue)")
    }
    
    private func cycleCurrency() {
        let currencies = ["USD", "EUR", "GBP", "JPY", "BTC", "ETH"]
        if let currentIndex = currencies.firstIndex(of: currency) {
            currency = currencies[(currentIndex + 1) % currencies.count]
        } else {
            currency = "USD"
        }
    }
    
    // MARK: - Test Notification
    private enum TestNotificationType {
        case transaction, price, network
    }
    
    private func sendTestNotification(type: TestNotificationType) {
        Task {
            switch type {
            case .transaction:
                await NotificationManager.shared.sendNotification(
                    type: .transactionConfirmed,
                    title: "Transaction Received",
                    body: "You received 0.005 BTC ($485.00) from bc1q...xyz"
                )
                ToastManager.shared.success("Test Sent", message: "Transaction notification sent!")
            case .price:
                await NotificationManager.shared.sendNotification(
                    type: .priceAlert,
                    title: "Price Alert: Bitcoin",
                    body: "BTC is up 5.2% in the last hour. Current price: $97,500"
                )
                ToastManager.shared.success("Test Sent", message: "Price alert notification sent!")
            case .network:
                await NotificationManager.shared.sendNotification(
                    type: .securityReminder,
                    title: "Network Status",
                    body: "Connection restored. All services are operational."
                )
                ToastManager.shared.success("Test Sent", message: "Network notification sent!")
            }
        }
    }
    
    // MARK: - Haptic Feedback
    private func triggerHaptic(force: Bool = false) {
        guard hapticFeedback || force else { return }
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .default
        )
        #endif
    }
}

// MARK: - Theme Picker Row
struct ThemePickerRow: View {
    @ObservedObject var themeManager = ThemeManager.shared
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(HawalaTheme.Colors.accent.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Image(systemName: "paintbrush.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(HawalaTheme.Colors.accent)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Theme")
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("App appearance")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            
            Spacer()
            
            Picker("", selection: Binding(
                get: { themeManager.currentTheme },
                set: { themeManager.currentTheme = $0 }
            )) {
                ForEach(ThemeManager.AppTheme.allCases, id: \.self) { theme in
                    HStack {
                        Image(systemName: theme.icon)
                        Text(theme.rawValue)
                    }
                    .tag(theme)
                }
            }
            .pickerStyle(.menu)
            .tint(HawalaTheme.Colors.accent)
            .frame(width: 110)
        }
        .padding(HawalaTheme.Spacing.md)
        .background(isHovered ? HawalaTheme.Colors.backgroundHover : Color.clear)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Currency Picker Row
struct CurrencyPickerRow: View {
    @Binding var currency: String
    @State private var isHovered = false
    
    private let currencies: [(code: String, name: String, symbol: String)] = [
        ("USD", "US Dollar", "$"),
        ("EUR", "Euro", "€"),
        ("GBP", "British Pound", "£"),
        ("JPY", "Japanese Yen", "¥"),
        ("CAD", "Canadian Dollar", "CA$"),
        ("AUD", "Australian Dollar", "A$"),
        ("CHF", "Swiss Franc", "CHF"),
        ("CNY", "Chinese Yuan", "¥"),
        ("INR", "Indian Rupee", "₹"),
        ("BTC", "Bitcoin", "₿"),
        ("ETH", "Ethereum", "Ξ")
    ]
    
    var body: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(HawalaTheme.Colors.success.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(HawalaTheme.Colors.success)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Display Currency")
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("For balance display")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            
            Spacer()
            
            Picker("", selection: $currency) {
                ForEach(currencies, id: \.code) { curr in
                    Text("\(curr.symbol) \(curr.code)")
                        .tag(curr.code)
                }
            }
            .pickerStyle(.menu)
            .tint(HawalaTheme.Colors.accent)
            .frame(width: 110)
        }
        .padding(HawalaTheme.Spacing.md)
        .background(isHovered ? HawalaTheme.Colors.backgroundHover : Color.clear)
        .onHover { isHovered = $0 }
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
                
                Text("Version \(AppVersion.version)")
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

// MARK: - Auto Lock Timeout Picker
struct AutoLockTimeoutPicker: View {
    @Binding var autoLockTimeout: Int
    @State private var isHovered = false
    
    private let timeoutOptions: [(value: Int, label: String)] = [
        (1, "1 minute"),
        (5, "5 minutes"),
        (15, "15 minutes"),
        (30, "30 minutes"),
        (60, "1 hour"),
        (0, "Never")
    ]
    
    var body: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(HawalaTheme.Colors.warning.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Image(systemName: "timer")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(HawalaTheme.Colors.warning)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto-Lock Timeout")
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("Lock app after inactivity")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            
            Spacer()
            
            Picker("", selection: $autoLockTimeout) {
                ForEach(timeoutOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .tint(HawalaTheme.Colors.accent)
            .frame(width: 120)
        }
        .padding(HawalaTheme.Spacing.md)
        .background(isHovered ? HawalaTheme.Colors.backgroundHover : Color.clear)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Change Passcode Sheet
struct ChangePasscodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var passcodeManager: PasscodeManager
    
    @State private var currentPasscode = ""
    @State private var newPasscode = ""
    @State private var confirmPasscode = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: HawalaTheme.Spacing.xl) {
            // Header
            HStack {
                Text("Change Passcode")
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
            .padding(.horizontal, HawalaTheme.Spacing.xl)
            .padding(.top, HawalaTheme.Spacing.xl)
            
            // Icon
            ZStack {
                Circle()
                    .fill(HawalaTheme.Colors.accent.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "key.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(HawalaTheme.Colors.accent)
            }
            
            // Instructions
            Text("Enter your current passcode, then create a new one")
                .font(HawalaTheme.Typography.body)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, HawalaTheme.Spacing.xl)
            
            // Form
            VStack(spacing: HawalaTheme.Spacing.md) {
                PasscodeField(
                    title: "Current Passcode",
                    text: $currentPasscode,
                    placeholder: "Enter current passcode"
                )
                
                PasscodeField(
                    title: "New Passcode",
                    text: $newPasscode,
                    placeholder: "Enter new passcode (min 4 digits)"
                )
                
                PasscodeField(
                    title: "Confirm New Passcode",
                    text: $confirmPasscode,
                    placeholder: "Confirm new passcode"
                )
                
                // Error message
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(HawalaTheme.Colors.error)
                        Text(error)
                            .font(HawalaTheme.Typography.bodySmall)
                            .foregroundColor(HawalaTheme.Colors.error)
                    }
                    .padding(HawalaTheme.Spacing.sm)
                    .background(HawalaTheme.Colors.error.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, HawalaTheme.Spacing.xl)
            
            Spacer()
            
            // Buttons
            VStack(spacing: HawalaTheme.Spacing.md) {
                HawalaPrimaryButton(
                    isLoading ? "Updating..." : "Update Passcode",
                    icon: "checkmark.shield.fill"
                ) {
                    validateAndSavePasscode()
                }
                .disabled(isLoading || currentPasscode.isEmpty || newPasscode.isEmpty || confirmPasscode.isEmpty)
                
                Button("Cancel") {
                    dismiss()
                }
                .font(HawalaTheme.Typography.body)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, HawalaTheme.Spacing.xl)
            .padding(.bottom, HawalaTheme.Spacing.xl)
        }
        .frame(width: 400, height: 550)
        .background(HawalaTheme.Colors.background)
    }
    
    private func validateAndSavePasscode() {
        errorMessage = nil
        
        // Actually verify current passcode against stored hash
        guard passcodeManager.verifyPasscode(currentPasscode) else {
            errorMessage = "Current passcode is incorrect"
            return
        }
        
        // Validate new passcode length
        guard newPasscode.count >= 4 else {
            errorMessage = "New passcode must be at least 4 digits"
            return
        }
        
        // Validate passcodes match
        guard newPasscode == confirmPasscode else {
            errorMessage = "New passcodes don't match"
            return
        }
        
        // Validate not same as current
        guard newPasscode != currentPasscode else {
            errorMessage = "New passcode must be different from current"
            return
        }
        
        isLoading = true
        
        // Use the passcode manager to change the passcode
        let result = passcodeManager.changePasscode(current: currentPasscode, new: newPasscode)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isLoading = false
            if result.success {
                ToastManager.shared.success("Passcode Updated", message: "Your passcode has been changed successfully")
                dismiss()
            } else {
                errorMessage = result.error ?? "Failed to update passcode"
            }
        }
    }
}

// MARK: - Passcode Setup Sheet (for Settings)
struct PasscodeSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var passcodeManager: PasscodeManager
    let onComplete: () -> Void
    
    @State private var passcode = ""
    @State private var confirmPasscode = ""
    @State private var step: SetupStep = .create
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    enum SetupStep {
        case create
        case confirm
    }
    
    var body: some View {
        VStack(spacing: HawalaTheme.Spacing.xl) {
            // Header
            HStack {
                Text(step == .create ? "Set Passcode" : "Confirm Passcode")
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
            .padding(.horizontal, HawalaTheme.Spacing.xl)
            .padding(.top, HawalaTheme.Spacing.xl)
            
            // Icon
            ZStack {
                Circle()
                    .fill(HawalaTheme.Colors.accent.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                Image(systemName: step == .create ? "lock.fill" : "checkmark.shield.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(HawalaTheme.Colors.accent)
            }
            
            // Instructions
            Text(step == .create ? "Choose a passcode to protect your wallet" : "Enter the same passcode again")
                .font(HawalaTheme.Typography.body)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, HawalaTheme.Spacing.xl)
            
            // Form
            VStack(spacing: HawalaTheme.Spacing.md) {
                PasscodeField(
                    title: step == .create ? "New Passcode" : "Confirm Passcode",
                    text: step == .create ? $passcode : $confirmPasscode,
                    placeholder: step == .create ? "Enter passcode (min 4 digits)" : "Confirm your passcode"
                )
                
                // Error message
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(HawalaTheme.Colors.error)
                        Text(error)
                            .font(HawalaTheme.Typography.bodySmall)
                            .foregroundColor(HawalaTheme.Colors.error)
                    }
                    .padding(HawalaTheme.Spacing.sm)
                    .background(HawalaTheme.Colors.error.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, HawalaTheme.Spacing.xl)
            
            Spacer()
            
            // Buttons
            VStack(spacing: HawalaTheme.Spacing.md) {
                if step == .create {
                    HawalaPrimaryButton("Continue", icon: "arrow.right") {
                        if passcode.count >= 4 {
                            step = .confirm
                            errorMessage = nil
                        } else {
                            errorMessage = "Passcode must be at least 4 digits"
                        }
                    }
                    .disabled(passcode.isEmpty)
                } else {
                    HawalaPrimaryButton(
                        isLoading ? "Saving..." : "Set Passcode",
                        icon: "checkmark.shield.fill"
                    ) {
                        savePasscode()
                    }
                    .disabled(isLoading || confirmPasscode.isEmpty)
                    
                    Button("Back") {
                        step = .create
                        confirmPasscode = ""
                        errorMessage = nil
                    }
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .buttonStyle(.plain)
                }
                
                Button("Cancel") {
                    dismiss()
                }
                .font(HawalaTheme.Typography.body)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, HawalaTheme.Spacing.xl)
            .padding(.bottom, HawalaTheme.Spacing.xl)
        }
        .frame(width: 400, height: 450)
        .background(HawalaTheme.Colors.background)
    }
    
    private func savePasscode() {
        errorMessage = nil
        
        guard confirmPasscode == passcode else {
            errorMessage = "Passcodes don't match"
            return
        }
        
        isLoading = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if passcodeManager.setPasscode(passcode) {
                isLoading = false
                ToastManager.shared.success("Passcode Set", message: "Your wallet is now protected")
                onComplete()
                dismiss()
            } else {
                isLoading = false
                errorMessage = "Failed to save passcode"
            }
        }
    }
}

// MARK: - Passcode Field
struct PasscodeField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    
    @State private var isSecure = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xs) {
            Text(title)
                .font(HawalaTheme.Typography.bodySmall)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
            
            HStack {
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                        .font(HawalaTheme.Typography.body)
                } else {
                    TextField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                        .font(HawalaTheme.Typography.body)
                }
                
                Button(action: { isSecure.toggle() }) {
                    Image(systemName: isSecure ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                    .stroke(HawalaTheme.Colors.border, lineWidth: 1)
            )
        }
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

// MARK: - Backup Wallet Sheet
struct BackupWalletSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showSeedPhrase = false
    @State private var hasCopied = false
    
    // Simulated seed phrase - in real app this would come from secure storage
    private let seedPhrase = [
        "abandon", "ability", "able", "about", "above", "absent",
        "absorb", "abstract", "absurd", "abuse", "access", "accident",
        "account", "accuse", "achieve", "acid", "acoustic", "acquire",
        "across", "act", "action", "actor", "actress", "actual"
    ]
    
    var body: some View {
        VStack(spacing: HawalaTheme.Spacing.xl) {
            // Header
            HStack {
                Text("Backup Wallet")
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
            .padding(.horizontal, HawalaTheme.Spacing.xl)
            .padding(.top, HawalaTheme.Spacing.xl)
            
            // Warning banner
            HStack(spacing: HawalaTheme.Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(HawalaTheme.Colors.warning)
                    .font(.system(size: 20))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keep Your Seed Phrase Safe")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    Text("Never share it with anyone. Anyone with this phrase can access your funds.")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
            }
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.warning.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                    .stroke(HawalaTheme.Colors.warning.opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal, HawalaTheme.Spacing.xl)
            
            // Seed phrase display
            if showSeedPhrase {
                VStack(spacing: HawalaTheme.Spacing.md) {
                    // 4x6 grid of words
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: HawalaTheme.Spacing.sm) {
                        ForEach(Array(seedPhrase.enumerated()), id: \.offset) { index, word in
                            HStack(spacing: 4) {
                                Text("\(index + 1).")
                                    .font(HawalaTheme.Typography.caption)
                                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                                    .frame(width: 20, alignment: .trailing)
                                
                                Text(word)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                            }
                            .padding(.vertical, HawalaTheme.Spacing.xs)
                            .padding(.horizontal, HawalaTheme.Spacing.sm)
                            .background(HawalaTheme.Colors.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(HawalaTheme.Spacing.md)
                    .background(HawalaTheme.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                            .stroke(HawalaTheme.Colors.border, lineWidth: 1)
                    )
                    
                    // Copy button
                    Button(action: {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(seedPhrase.joined(separator: " "), forType: .string)
                        #endif
                        hasCopied = true
                        ToastManager.shared.success("Copied", message: "Seed phrase copied to clipboard")
                        
                        // Clear clipboard after 60 seconds for security
                        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            #endif
                        }
                    }) {
                        HStack {
                            Image(systemName: hasCopied ? "checkmark" : "doc.on.doc")
                            Text(hasCopied ? "Copied!" : "Copy to Clipboard")
                        }
                        .font(HawalaTheme.Typography.bodySmall)
                        .foregroundColor(hasCopied ? HawalaTheme.Colors.success : HawalaTheme.Colors.accent)
                        .padding(.horizontal, HawalaTheme.Spacing.md)
                        .padding(.vertical, HawalaTheme.Spacing.sm)
                        .background(hasCopied ? HawalaTheme.Colors.success.opacity(0.15) : HawalaTheme.Colors.accent.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, HawalaTheme.Spacing.xl)
            } else {
                // Reveal button
                VStack(spacing: HawalaTheme.Spacing.lg) {
                    ZStack {
                        Circle()
                            .fill(HawalaTheme.Colors.accent.opacity(0.15))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundColor(HawalaTheme.Colors.accent)
                    }
                    
                    Text("Your seed phrase is hidden for security")
                        .font(HawalaTheme.Typography.body)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    
                    HawalaPrimaryButton("Reveal Seed Phrase", icon: "eye.fill") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showSeedPhrase = true
                        }
                    }
                }
                .padding(.horizontal, HawalaTheme.Spacing.xl)
            }
            
            Spacer()
            
            // Done button
            Button("Done") {
                dismiss()
            }
            .font(HawalaTheme.Typography.body)
            .foregroundColor(HawalaTheme.Colors.textSecondary)
            .buttonStyle(.plain)
            .padding(.bottom, HawalaTheme.Spacing.xl)
        }
        .frame(width: 500, height: 550)
        .background(HawalaTheme.Colors.background)
    }
}

// MARK: - Network Settings Sheet
struct NetworkSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hawala.selectedNetwork") private var selectedNetwork = "mainnet"
    @AppStorage("hawala.customRpcUrl") private var customRpcUrl = ""
    
    @State private var isTestingConnection = false
    @State private var connectionStatus: ConnectionStatus?
    
    enum ConnectionStatus {
        case success(latency: Int)
        case error(String)
    }
    
    private let networks = [
        ("mainnet", "Mainnet", "Production network"),
        ("testnet", "Testnet", "Test network for development"),
        ("custom", "Custom RPC", "Use your own endpoint")
    ]
    
    var body: some View {
        VStack(spacing: HawalaTheme.Spacing.xl) {
            // Header
            HStack {
                Text("Network Settings")
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
            .padding(.horizontal, HawalaTheme.Spacing.xl)
            .padding(.top, HawalaTheme.Spacing.xl)
            
            // Network Selection
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
                Text("Network")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                ForEach(networks, id: \.0) { network in
                    NetworkOptionRow(
                        id: network.0,
                        title: network.1,
                        subtitle: network.2,
                        isSelected: selectedNetwork == network.0,
                        onSelect: {
                            selectedNetwork = network.0
                            connectionStatus = nil
                        }
                    )
                }
            }
            .padding(.horizontal, HawalaTheme.Spacing.xl)
            
            // Custom RPC URL field (if custom is selected)
            if selectedNetwork == "custom" {
                VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                    Text("Custom RPC URL")
                        .font(HawalaTheme.Typography.bodySmall)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    
                    HStack {
                        TextField("https://your-node.example.com", text: $customRpcUrl)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                        
                        if !customRpcUrl.isEmpty {
                            Button(action: { customRpcUrl = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(HawalaTheme.Spacing.md)
                    .background(HawalaTheme.Colors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                            .stroke(HawalaTheme.Colors.border, lineWidth: 1)
                    )
                }
                .padding(.horizontal, HawalaTheme.Spacing.xl)
            }
            
            // Test connection button
            VStack(spacing: HawalaTheme.Spacing.sm) {
                Button(action: testConnection) {
                    HStack {
                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                        Text(isTestingConnection ? "Testing..." : "Test Connection")
                    }
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.accent)
                    .padding(.horizontal, HawalaTheme.Spacing.lg)
                    .padding(.vertical, HawalaTheme.Spacing.md)
                    .background(HawalaTheme.Colors.accent.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                }
                .buttonStyle(.plain)
                .disabled(isTestingConnection)
                
                // Connection status
                if let status = connectionStatus {
                    HStack {
                        switch status {
                        case .success(let latency):
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(HawalaTheme.Colors.success)
                            Text("Connected • \(latency)ms latency")
                                .foregroundColor(HawalaTheme.Colors.success)
                        case .error(let message):
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(HawalaTheme.Colors.error)
                            Text(message)
                                .foregroundColor(HawalaTheme.Colors.error)
                        }
                    }
                    .font(HawalaTheme.Typography.bodySmall)
                }
            }
            .padding(.horizontal, HawalaTheme.Spacing.xl)
            
            Spacer()
            
            // Save button
            HawalaPrimaryButton("Save Settings", icon: "checkmark") {
                ToastManager.shared.success("Settings Saved", message: "Network configuration updated")
                dismiss()
            }
            .padding(.horizontal, HawalaTheme.Spacing.xl)
            .padding(.bottom, HawalaTheme.Spacing.xl)
        }
        .frame(width: 450, height: 550)
        .background(HawalaTheme.Colors.background)
    }
    
    private func testConnection() {
        isTestingConnection = true
        connectionStatus = nil
        
        // Simulate network test
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isTestingConnection = false
            
            if selectedNetwork == "custom" && customRpcUrl.isEmpty {
                connectionStatus = .error("Please enter a valid RPC URL")
            } else {
                // Simulate successful connection with random latency
                let latency = Int.random(in: 50...200)
                connectionStatus = .success(latency: latency)
            }
        }
    }
}

// MARK: - Network Option Row
struct NetworkOptionRow: View {
    let id: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: HawalaTheme.Spacing.md) {
                // Radio button
                ZStack {
                    Circle()
                        .stroke(isSelected ? HawalaTheme.Colors.accent : HawalaTheme.Colors.border, lineWidth: 2)
                        .frame(width: 20, height: 20)
                    
                    if isSelected {
                        Circle()
                            .fill(HawalaTheme.Colors.accent)
                            .frame(width: 10, height: 10)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(HawalaTheme.Typography.body)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    Text(subtitle)
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(HawalaTheme.Colors.accent)
                }
            }
            .padding(HawalaTheme.Spacing.md)
            .background(isSelected ? HawalaTheme.Colors.accent.opacity(0.1) : (isHovered ? HawalaTheme.Colors.backgroundHover : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                    .stroke(isSelected ? HawalaTheme.Colors.accent.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Export History Sheet
struct ExportHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .csv
    @State private var selectedDateRange: DateRange = .all
    @State private var includeNotes = true
    @State private var isExporting = false
    @State private var exportComplete = false
    
    enum ExportFormat: String, CaseIterable {
        case csv = "CSV"
        case json = "JSON"
        case pdf = "PDF"
        
        var icon: String {
            switch self {
            case .csv: return "tablecells"
            case .json: return "curlybraces"
            case .pdf: return "doc.richtext"
            }
        }
    }
    
    enum DateRange: String, CaseIterable {
        case week = "Last 7 Days"
        case month = "Last 30 Days"
        case year = "Last Year"
        case all = "All Time"
    }
    
    var body: some View {
        VStack(spacing: HawalaTheme.Spacing.xl) {
            // Header
            HStack {
                Text("Export Transaction History")
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
            .padding(.horizontal, HawalaTheme.Spacing.xl)
            .padding(.top, HawalaTheme.Spacing.xl)
            
            if exportComplete {
                // Success state
                VStack(spacing: HawalaTheme.Spacing.lg) {
                    ZStack {
                        Circle()
                            .fill(HawalaTheme.Colors.success.opacity(0.15))
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(HawalaTheme.Colors.success)
                    }
                    
                    Text("Export Complete!")
                        .font(HawalaTheme.Typography.h3)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    Text("Your transaction history has been exported and saved to your Downloads folder.")
                        .font(HawalaTheme.Typography.body)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, HawalaTheme.Spacing.xl)
                }
            } else {
                // Export options
                VStack(alignment: .leading, spacing: HawalaTheme.Spacing.lg) {
                    // Format selection
                    VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                        Text("Export Format")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                        
                        HStack(spacing: HawalaTheme.Spacing.sm) {
                            ForEach(ExportFormat.allCases, id: \.self) { format in
                                FormatOptionButton(
                                    format: format,
                                    isSelected: selectedFormat == format,
                                    onSelect: { selectedFormat = format }
                                )
                            }
                        }
                    }
                    
                    // Date range
                    VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                        Text("Date Range")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                        
                        Picker("", selection: $selectedDateRange) {
                            ForEach(DateRange.allCases, id: \.self) { range in
                                Text(range.rawValue).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // Options
                    VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                        Text("Options")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                        
                        Toggle(isOn: $includeNotes) {
                            HStack {
                                Image(systemName: "note.text")
                                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                                Text("Include transaction notes")
                                    .font(HawalaTheme.Typography.body)
                                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(HawalaTheme.Colors.accent)
                    }
                }
                .padding(.horizontal, HawalaTheme.Spacing.xl)
            }
            
            Spacer()
            
            // Action buttons
            VStack(spacing: HawalaTheme.Spacing.md) {
                if exportComplete {
                    HawalaPrimaryButton("Done", icon: "checkmark") {
                        dismiss()
                    }
                } else {
                    HawalaPrimaryButton(isExporting ? "Exporting..." : "Export", icon: "square.and.arrow.up") {
                        performExport()
                    }
                    .disabled(isExporting)
                    
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, HawalaTheme.Spacing.xl)
            .padding(.bottom, HawalaTheme.Spacing.xl)
        }
        .frame(width: 450, height: exportComplete ? 400 : 500)
        .background(HawalaTheme.Colors.background)
        .animation(.easeInOut(duration: 0.3), value: exportComplete)
    }
    
    private func performExport() {
        isExporting = true
        
        // Simulate export process
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Create and save the file
            let filename = "hawala_transactions_\(Date().ISO8601Format()).\(selectedFormat.rawValue.lowercased())"
            
            #if os(macOS)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = filename
            panel.allowedContentTypes = [.commaSeparatedText, .json, .pdf]
            panel.canCreateDirectories = true
            
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    // Generate sample export content
                    let content = generateExportContent()
                    
                    do {
                        try content.write(to: url, atomically: true, encoding: .utf8)
                        isExporting = false
                        exportComplete = true
                        ToastManager.shared.success("Export Complete", message: "Saved to \(url.lastPathComponent)")
                    } catch {
                        isExporting = false
                        ToastManager.shared.error("Export Failed", message: error.localizedDescription)
                    }
                } else {
                    isExporting = false
                }
            }
            #endif
        }
    }
    
    private func generateExportContent() -> String {
        switch selectedFormat {
        case .csv:
            return """
            Date,Type,Asset,Amount,Value,TxHash,Notes
            2024-11-30 10:00:00,Received,BTC,0.005,485.00,bc1q...abc,Deposit
            2024-11-29 15:30:00,Sent,ETH,0.1,350.00,0x123...def,Payment
            2024-11-28 09:15:00,Received,SOL,10.0,220.00,5xYz...ghi,Staking reward
            """
        case .json:
            return """
            {
              "transactions": [
                {"date": "2024-11-30T10:00:00Z", "type": "received", "asset": "BTC", "amount": 0.005, "value": 485.00},
                {"date": "2024-11-29T15:30:00Z", "type": "sent", "asset": "ETH", "amount": 0.1, "value": 350.00}
              ]
            }
            """
        case .pdf:
            return "PDF export would generate a formatted document"
        }
    }
}

// MARK: - Format Option Button
struct FormatOptionButton: View {
    let format: ExportHistorySheet.ExportFormat
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: HawalaTheme.Spacing.xs) {
                Image(systemName: format.icon)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? HawalaTheme.Colors.accent : HawalaTheme.Colors.textSecondary)
                
                Text(format.rawValue)
                    .font(HawalaTheme.Typography.bodySmall)
                    .foregroundColor(isSelected ? HawalaTheme.Colors.accent : HawalaTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, HawalaTheme.Spacing.md)
            .background(isSelected ? HawalaTheme.Colors.accent.opacity(0.1) : (isHovered ? HawalaTheme.Colors.backgroundHover : HawalaTheme.Colors.backgroundSecondary))
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                    .stroke(isSelected ? HawalaTheme.Colors.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Terms of Service Sheet
struct TermsOfServiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Terms of Service")
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
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: HawalaTheme.Spacing.lg) {
                    Text("Last Updated: November 30, 2025")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    
                    TermsSection(title: "1. Acceptance of Terms", content: "By accessing and using Hawala Wallet, you agree to be bound by these Terms of Service. If you do not agree to these terms, please do not use the application.")
                    
                    TermsSection(title: "2. Self-Custody Wallet", content: "Hawala is a self-custody wallet. You are solely responsible for maintaining the security of your private keys and recovery phrase. We do not have access to your funds or the ability to recover lost keys.")
                    
                    TermsSection(title: "3. No Financial Advice", content: "Hawala does not provide financial, investment, legal, or tax advice. All cryptocurrency transactions carry risk. You should consult with qualified professionals before making any financial decisions.")
                    
                    TermsSection(title: "4. User Responsibilities", content: """
                        You agree to:
                        • Keep your recovery phrase secure and private
                        • Not share your private keys with anyone
                        • Use the wallet only for lawful purposes
                        • Accept full responsibility for all transactions made from your wallet
                        """)
                    
                    TermsSection(title: "5. Limitation of Liability", content: "Hawala is provided \"as is\" without warranties of any kind. We are not liable for any losses, damages, or claims arising from the use of this software, including but not limited to loss of funds, hacking, or software errors.")
                    
                    TermsSection(title: "6. Privacy", content: "We do not collect, store, or transmit your private keys or recovery phrase. Price data and blockchain information may be fetched from third-party services. See our Privacy Policy for more details.")
                    
                    TermsSection(title: "7. Changes to Terms", content: "We reserve the right to modify these terms at any time. Continued use of the application after changes constitutes acceptance of the new terms.")
                    
                    TermsSection(title: "8. Contact", content: "For questions about these terms, please reach out through our Help & Support section.")
                }
                .padding(HawalaTheme.Spacing.xl)
            }
            
            // Accept button
            Button(action: { dismiss() }) {
                Text("I Understand")
                    .font(HawalaTheme.Typography.body)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, HawalaTheme.Spacing.md)
                    .background(HawalaTheme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
            }
            .buttonStyle(.plain)
            .padding(HawalaTheme.Spacing.xl)
        }
        .frame(width: 500, height: 600)
        .background(HawalaTheme.Colors.background)
    }
}

// MARK: - Terms Section Helper
struct TermsSection: View {
    let title: String
    let content: String
    
    init(title: String, content: String) {
        self.title = title
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(HawalaTheme.Colors.textPrimary)
            
            Text(content)
                .font(HawalaTheme.Typography.body)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .lineSpacing(4)
        }
    }
}

// MARK: - Privacy Policy Sheet
struct PrivacyPolicySheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Privacy Policy")
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
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: HawalaTheme.Spacing.lg) {
                    Text("Last Updated: November 30, 2025")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    
                    // Privacy highlights
                    HStack(spacing: HawalaTheme.Spacing.md) {
                        PrivacyHighlight(icon: "lock.shield.fill", title: "No Data Collection", color: HawalaTheme.Colors.success)
                        PrivacyHighlight(icon: "eye.slash.fill", title: "No Tracking", color: HawalaTheme.Colors.info)
                        PrivacyHighlight(icon: "key.fill", title: "Self-Custody", color: HawalaTheme.Colors.accent)
                    }
                    .padding(.vertical, HawalaTheme.Spacing.md)
                    
                    TermsSection(title: "Our Commitment", content: "Hawala is designed with privacy as a core principle. We believe your financial data belongs to you and you alone.")
                    
                    TermsSection(title: "What We DON'T Collect", content: """
                        • Private keys or recovery phrases
                        • Transaction history
                        • Wallet balances
                        • Personal identification information
                        • Location data
                        • Usage analytics
                        """)
                    
                    TermsSection(title: "Local Storage Only", content: "All sensitive data, including your encrypted keys and wallet settings, is stored locally on your device. We never transmit this information to external servers.")
                    
                    TermsSection(title: "Third-Party Services", content: """
                        To provide functionality, we connect to:
                        • Blockchain nodes for transaction broadcasting
                        • Price APIs for market data (CoinGecko)
                        • Block explorers for transaction verification
                        
                        These services may have their own privacy policies.
                        """)
                    
                    TermsSection(title: "Network Requests", content: "When fetching prices or broadcasting transactions, your IP address may be visible to third-party services. For enhanced privacy, consider using a VPN or Tor.")
                    
                    TermsSection(title: "Your Rights", content: "Since we don't collect your data, there's nothing to delete or export. Your data lives entirely on your device. Uninstalling the app removes all local data.")
                }
                .padding(HawalaTheme.Spacing.xl)
            }
            
            // Done button
            Button(action: { dismiss() }) {
                Text("Done")
                    .font(HawalaTheme.Typography.body)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, HawalaTheme.Spacing.md)
                    .background(HawalaTheme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
            }
            .buttonStyle(.plain)
            .padding(HawalaTheme.Spacing.xl)
        }
        .frame(width: 500, height: 600)
        .background(HawalaTheme.Colors.background)
    }
}

// MARK: - Privacy Highlight
struct PrivacyHighlight: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        VStack(spacing: HawalaTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
            
            Text(title)
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(HawalaTheme.Spacing.md)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
    }
}

// MARK: - Help & Support Sheet
struct HelpSupportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFAQ: Int? = nil
    
    private let faqs: [(question: String, answer: String)] = [
        ("How do I backup my wallet?", "Go to Settings → General → Backup Wallet. Write down your 24-word recovery phrase and store it in a safe place. Never share it with anyone or store it digitally."),
        ("What if I lose my recovery phrase?", "Without your recovery phrase, there is no way to recover your wallet. This is why it's crucial to backup your phrase immediately after creating a wallet."),
        ("Are my funds safe?", "Hawala is a self-custody wallet, meaning only you control your private keys. Your keys are encrypted and stored locally on your device. We never have access to your funds."),
        ("How do I send cryptocurrency?", "Click the send button (↑↓) in the navigation bar, select the asset you want to send, enter the recipient address and amount, then confirm the transaction."),
        ("Why is my balance not updating?", "Try refreshing by pressing Cmd+R or clicking the refresh button. Check your internet connection and ensure the blockchain network is operational."),
        ("How do I change networks?", "Go to Settings → General → Network Settings. You can switch between Mainnet, Testnet, or configure a custom RPC endpoint."),
        ("Is Hawala open source?", "Yes! Hawala is open source software. You can review the code and contribute on GitHub.")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Help & Support")
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
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xl) {
                    // Quick actions
                    VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
                        Text("Quick Actions")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                        
                        HStack(spacing: HawalaTheme.Spacing.md) {
                            SupportActionButton(
                                icon: "book.fill",
                                title: "Documentation",
                                color: HawalaTheme.Colors.accent
                            ) {
                                #if os(macOS)
                                if let url = URL(string: "https://github.com/HawalaSupp/bitcoin-key-generator") {
                                    NSWorkspace.shared.open(url)
                                }
                                #endif
                            }
                            
                            SupportActionButton(
                                icon: "envelope.fill",
                                title: "Contact Us",
                                color: HawalaTheme.Colors.info
                            ) {
                                #if os(macOS)
                                if let url = URL(string: "mailto:support@hawala.app") {
                                    NSWorkspace.shared.open(url)
                                }
                                #endif
                            }
                            
                            SupportActionButton(
                                icon: "bubble.left.fill",
                                title: "Community",
                                color: HawalaTheme.Colors.success
                            ) {
                                #if os(macOS)
                                if let url = URL(string: "https://github.com/HawalaSupp/bitcoin-key-generator/discussions") {
                                    NSWorkspace.shared.open(url)
                                }
                                #endif
                            }
                        }
                    }
                    
                    Divider()
                        .background(HawalaTheme.Colors.border)
                    
                    // FAQs
                    VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
                        Text("Frequently Asked Questions")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                        
                        ForEach(Array(faqs.enumerated()), id: \.offset) { index, faq in
                            FAQItem(
                                question: faq.question,
                                answer: faq.answer,
                                isExpanded: selectedFAQ == index,
                                onTap: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedFAQ = selectedFAQ == index ? nil : index
                                    }
                                }
                            )
                        }
                    }
                    
                    Divider()
                        .background(HawalaTheme.Colors.border)
                    
                    // App info
                    VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                        Text("App Information")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                        
                        HStack {
                            Text("Version")
                                .foregroundColor(HawalaTheme.Colors.textSecondary)
                            Spacer()
                            Text(AppVersion.versionWithBuild)
                                .foregroundColor(HawalaTheme.Colors.textTertiary)
                        }
                        .font(HawalaTheme.Typography.body)
                        
                        HStack {
                            Text("Platform")
                                .foregroundColor(HawalaTheme.Colors.textSecondary)
                            Spacer()
                            Text("macOS")
                                .foregroundColor(HawalaTheme.Colors.textTertiary)
                        }
                        .font(HawalaTheme.Typography.body)
                    }
                }
                .padding(HawalaTheme.Spacing.xl)
            }
            
            // Done button
            Button(action: { dismiss() }) {
                Text("Done")
                    .font(HawalaTheme.Typography.body)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, HawalaTheme.Spacing.md)
                    .background(HawalaTheme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
            }
            .buttonStyle(.plain)
            .padding(HawalaTheme.Spacing.xl)
        }
        .frame(width: 500, height: 650)
        .background(HawalaTheme.Colors.background)
    }
}

// MARK: - Support Action Button
struct SupportActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: HawalaTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
                
                Text(title)
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(HawalaTheme.Spacing.md)
            .background(isHovered ? color.opacity(0.15) : HawalaTheme.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - FAQ Item
struct FAQItem: View {
    let question: String
    let answer: String
    let isExpanded: Bool
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack {
                    Text(question)
                        .font(HawalaTheme.Typography.body)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                .padding(HawalaTheme.Spacing.md)
                .background(isHovered ? HawalaTheme.Colors.backgroundHover : HawalaTheme.Colors.backgroundSecondary)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            
            if isExpanded {
                Text(answer)
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .lineSpacing(4)
                    .padding(HawalaTheme.Spacing.md)
                    .padding(.top, 0)
                    .background(HawalaTheme.Colors.backgroundSecondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                .stroke(HawalaTheme.Colors.border, lineWidth: 1)
        )
    }
}

// MARK: - Debug Console Sheet
struct DebugConsoleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var logger = DebugLogger.shared
    @State private var filterCategory: LogCategory? = nil
    @State private var filterLevel: LogLevel? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Debug Console")
                    .font(HawalaTheme.Typography.h2)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Spacer()
                
                // Filter buttons
                Menu {
                    Button("All Categories") { filterCategory = nil }
                    Divider()
                    ForEach([LogCategory.general, .network, .wallet, .transaction, .security], id: \.self) { cat in
                        Button(cat.rawValue.capitalized) { filterCategory = cat }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text(filterCategory?.rawValue.capitalized ?? "All")
                    }
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                
                Button(action: { logger.clear() }) {
                    Image(systemName: "trash")
                        .foregroundColor(HawalaTheme.Colors.error)
                }
                .buttonStyle(.plain)
                .padding(.leading, HawalaTheme.Spacing.sm)
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .padding(.leading, HawalaTheme.Spacing.sm)
            }
            .padding(HawalaTheme.Spacing.lg)
            .background(HawalaTheme.Colors.backgroundSecondary)
            
            // Stats bar
            HStack(spacing: HawalaTheme.Spacing.lg) {
                DebugStatBadge(title: "Entries", value: "\(logger.entries.count)")
                DebugStatBadge(title: "Network Latency", value: logger.latencyDescription)
                DebugStatBadge(title: "WebSocket", value: logger.webSocketStatus)
                Spacer()
            }
            .padding(.horizontal, HawalaTheme.Spacing.lg)
            .padding(.vertical, HawalaTheme.Spacing.sm)
            .background(HawalaTheme.Colors.backgroundTertiary.opacity(0.5))
            
            Divider()
                .background(HawalaTheme.Colors.border)
            
            // Log entries
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredEntries) { entry in
                        LogEntryRow(entry: entry)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(HawalaTheme.Colors.background)
    }
    
    private var filteredEntries: [LogEntry] {
        var result = logger.entries
        if let cat = filterCategory {
            result = result.filter { $0.category == cat }
        }
        if let level = filterLevel {
            result = result.filter { $0.level == level }
        }
        return result.reversed() // Most recent first
    }
}

// Log entry row
private struct LogEntryRow: View {
    let entry: LogEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: HawalaTheme.Spacing.sm) {
            Text(entry.timeString)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(HawalaTheme.Colors.textTertiary)
                .frame(width: 80, alignment: .leading)
            
            Text(entry.level.rawValue.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(levelColor(entry.level))
                .frame(width: 50, alignment: .leading)
            
            Text(entry.category.rawValue)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .frame(width: 70, alignment: .leading)
            
            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(HawalaTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, HawalaTheme.Spacing.md)
        .padding(.vertical, 4)
        .background(entry.level == .error ? HawalaTheme.Colors.error.opacity(0.05) : Color.clear)
    }
    
    private func levelColor(_ level: LogLevel) -> Color {
        switch level {
        case .debug: return HawalaTheme.Colors.textTertiary
        case .info: return HawalaTheme.Colors.accent
        case .warning: return HawalaTheme.Colors.warning
        case .error: return HawalaTheme.Colors.error
        }
    }
}

// Debug stat badge
private struct DebugStatBadge: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(HawalaTheme.Colors.textPrimary)
        }
    }
}

#Preview {
    SettingsView()
        .frame(width: 500, height: 800)
}
