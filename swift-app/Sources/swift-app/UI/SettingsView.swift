import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Settings View
struct SettingsView: View {
    var onDismiss: (() -> Void)? = nil
    var onOpenSecurity: (() -> Void)? = nil
    var onOpenPrivacy: (() -> Void)? = nil
    var onOpenNetwork: (() -> Void)? = nil
    var onOpenBackup: (() -> Void)? = nil
    var onOpenTokens: (() -> Void)? = nil
    var onOpenSecurityPolicies: (() -> Void)? = nil
    var onOpenHardwareWallet: (() -> Void)? = nil
    var onOpenAddressBook: ((AddressBookOverlay.ABTab?) -> Void)? = nil
    var onOpenScheduledTx: (() -> Void)? = nil
    var onOpenExport: (() -> Void)? = nil
    var onOpenDebugConsole: (() -> Void)? = nil
    var onOpenAbout: (() -> Void)? = nil
    var onOpenHelpSupport: (() -> Void)? = nil
    @Environment(\.dismiss) private var envDismiss
    @ObservedObject var passcodeManager = PasscodeManager.shared
    @ObservedObject var themeManager = ThemeManager.shared
    @ObservedObject var privacyManager = PrivacyManager.shared
    @ObservedObject var walletManager = WalletManager.shared
    
    // Onboarding state for reset
    @AppStorage("hawala.onboardingCompleted") private var onboardingCompleted = false
    
    // Settings State
    @AppStorage("showBalances") private var showBalances = true
    @AppStorage("hawala.selectedFiatCurrency") private var currency = "USD"
    @AppStorage("showTestnets") private var showTestnets = false
    @AppStorage("selectedBackgroundType") private var selectedBackgroundType = "none"
    @AppStorage("portfolioTestMode") private var portfolioTestMode = false
    
    // Demo mode editable amounts
    @AppStorage("demo_bitcoin") private var demoBitcoin: Double = 45230.0
    @AppStorage("demo_ethereum") private var demoEthereum: Double = 28150.0
    @AppStorage("demo_solana") private var demoSolana: Double = 12890.0
    @AppStorage("demo_litecoin") private var demoLitecoin: Double = 8420.0
    @AppStorage("demo_monero") private var demoMonero: Double = 5310.0
    
    // Export now uses overlay via onOpenExport callback
    @State private var showResetConfirm = false
    @State private var showChangePasscode = false
    @State private var showSetPasscode = false

    @State private var isForceSyncing = false


    
    // Animation states
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.95
    @State private var selectedSection: SettingsSection? = nil
    
    enum SettingsSection: String, CaseIterable {
        case security = "Security"
        case privacy = "Privacy"
        case network = "Network"
        case appearance = "Appearance"
        case general = "General"
        case developer = "Developer"
        case about = "About"
    }
    
    // Debug/Developer info
    @StateObject private var debugLogger = DebugLogger.shared
    
    // Computed color scheme based on theme
    private var selectedColorScheme: ColorScheme? {
        themeManager.currentTheme.colorScheme
    }
    
    /// Unified dismiss: prefers overlay callback, falls back to sheet environment
    private func dismiss() {
        if let onDismiss {
            onDismiss()
        } else {
            envDismiss()
        }
    }
    
    var body: some View {
        ZStack {
            // Background
            Color(red: 0.06, green: 0.06, blue: 0.07)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                settingsHeader
                
                // Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        // Quick toggles at top
                        quickTogglesCard
                        
                        // Navigation grid
                        settingsGrid
                        
                        // Danger zone at bottom
                        dangerZoneCard
                    }
                    .padding(.horizontal, HawalaTheme.Spacing.xl)
                    .padding(.bottom, HawalaTheme.Spacing.xxl)
                }
                .opacity(contentOpacity)
            }
        }
        .frame(width: 500, height: 720)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.1), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.5), radius: 50, x: 0, y: 25)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                contentOpacity = 1
                cardScale = 1
            }
        }

        .sheet(isPresented: $showChangePasscode) {
            ChangePasscodeSheet(passcodeManager: passcodeManager)
        }
        .sheet(isPresented: $showSetPasscode) {
            PasscodeSetupSheet(passcodeManager: passcodeManager) {
                showSetPasscode = false
            }
        }
        // Backup, Tokens, Privacy, Export now use overlay callbacks

        .alert("Reset Wallet", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                Task {
                    do {
                        // Delete all wallets from secure storage
                        try await walletManager.deleteAllWallets()
                        
                        // Reset onboarding state
                        await MainActor.run {
                            onboardingCompleted = false
                            // Clear cached data
                            UserDefaults.standard.removeObject(forKey: "cached_balances")
                            UserDefaults.standard.removeObject(forKey: "cached_prices")
                            UserDefaults.standard.synchronize()
                            dismiss()
                        }
                        
                        ToastManager.shared.success("Wallet reset complete")
                    } catch {
                        ToastManager.shared.error("Failed to reset: \(error.localizedDescription)")
                    }
                }
            }
        } message: {
            Text("Are you sure you want to reset your wallet? This action cannot be undone. Make sure you have backed up your seed phrase.")
        }
        .preferredColorScheme(selectedColorScheme)
    }
    
    // MARK: - Settings Header
    private var settingsHeader: some View {
        ZStack {
            // Centered title
            Text("Settings")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
            
            // Close button
            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.5))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }
    
    // MARK: - Quick Toggles Card
    @ViewBuilder
    private var quickTogglesCard: some View {
        VStack(spacing: 0) {
            // Privacy Mode Toggle
            SettingsQuickToggle(
                icon: privacyManager.isPrivacyModeEnabled ? "eye.slash.fill" : "eye.fill",
                title: "Privacy Mode",
                subtitle: "Hide sensitive info",
                isOn: $privacyManager.isPrivacyModeEnabled
            )
            
            Divider()
                .background(Color.white.opacity(0.06))
                .padding(.leading, 52)
            
            // Testnets Toggle
            SettingsQuickToggle(
                icon: "testtube.2",
                title: "Testnets",
                subtitle: "Show test networks",
                isOn: $showTestnets
            )
            
            Divider()
                .background(Color.white.opacity(0.06))
                .padding(.leading, 52)
            
            // Portfolio Test Mode Toggle
            SettingsQuickToggle(
                icon: "chart.pie.fill",
                title: "Demo Mode",
                subtitle: "Show fake portfolio",
                isOn: $portfolioTestMode
            )
        }
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .padding(.bottom, HawalaTheme.Spacing.sm)
        
        // Demo Mode Amount Configuration (only show when demo mode is enabled)
        if portfolioTestMode {
            demoAmountsCard
        }
    }
    
    // MARK: - Demo Amounts Configuration Card
    private var demoAmountsCard: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                Text("Demo Portfolio Amounts")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
                .background(Color.white.opacity(0.06))
            
            // Bitcoin
            DemoAmountRow(
                icon: "bitcoinsign.circle.fill",
                label: "Bitcoin",
                color: HawalaTheme.Colors.bitcoin,
                amount: $demoBitcoin
            )
            
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
            
            // Ethereum
            DemoAmountRow(
                icon: "e.circle.fill",
                label: "Ethereum",
                color: HawalaTheme.Colors.ethereum,
                amount: $demoEthereum
            )
            
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
            
            // Solana
            DemoAmountRow(
                icon: "s.circle.fill",
                label: "Solana",
                color: HawalaTheme.Colors.solana,
                amount: $demoSolana
            )
            
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
            
            // Litecoin
            DemoAmountRow(
                icon: "l.circle.fill",
                label: "Litecoin",
                color: HawalaTheme.Colors.litecoin,
                amount: $demoLitecoin
            )
            
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
            
            // Monero
            DemoAmountRow(
                icon: "m.circle.fill",
                label: "Monero",
                color: HawalaTheme.Colors.monero,
                amount: $demoMonero
            )
        }
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .padding(.bottom, HawalaTheme.Spacing.sm)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(HawalaTheme.Animation.spring, value: portfolioTestMode)
    }
    
    // MARK: - Settings Grid
    private var settingsGrid: some View {
        VStack(spacing: 8) {
            // Row 1: Security & Privacy
            HStack(spacing: 8) {
                SettingsGridCard(
                    icon: "lock.shield.fill",
                    title: "Security",
                    subtitle: passcodeManager.hasPasscode ? "Protected" : "Set passcode",
                    accentColor: .white
                ) {
                    triggerHaptic()
                    onOpenSecurity?()
                }
                
                SettingsGridCard(
                    icon: "hand.raised.fill",
                    title: "Privacy",
                    subtitle: "Duress & stealth",
                    accentColor: .white
                ) {
                    triggerHaptic()
                    onOpenPrivacy?()
                }
            }
            
            // Row 2: Network & Appearance
            HStack(spacing: 8) {
                SettingsGridCard(
                    icon: "server.rack",
                    title: "Network",
                    subtitle: "Providers & sync",
                    accentColor: .white
                ) {
                    triggerHaptic()
                    onOpenNetwork?()
                }
                
                SettingsGridCard(
                    icon: "paintbrush.fill",
                    title: "Appearance",
                    subtitle: themeManager.currentTheme.rawValue,
                    accentColor: .white
                ) {
                    triggerHaptic()
                    cycleTheme()
                }
            }
            
            // Row 3: Wallet & Tokens
            HStack(spacing: 8) {
                SettingsGridCard(
                    icon: "key.fill",
                    title: "Backup",
                    subtitle: "Recovery phrase",
                    accentColor: .white
                ) {
                    triggerHaptic()
                    onOpenBackup?()
                }
                
                SettingsGridCard(
                    icon: "circle.hexagongrid.fill",
                    title: "Tokens",
                    subtitle: "Custom tokens",
                    accentColor: .white
                ) {
                    triggerHaptic()
                    onOpenTokens?()
                }
            }
            
            // Additional options list
            additionalOptionsList
        }
    }
    
    // MARK: - Additional Options List
    private var additionalOptionsList: some View {
        VStack(spacing: 0) {
            SettingsListRow(icon: "shield.checkered", title: "Security Policies") {
                triggerHaptic()
                if let onOpenSecurityPolicies {
                    onOpenSecurityPolicies()
                }
            }
            
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
            
            SettingsListRow(icon: "cpu", title: "Hardware Wallet") {
                triggerHaptic()
                if let onOpenHardwareWallet {
                    onOpenHardwareWallet()
                }
            }
            
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
            
            SettingsListRow(icon: "person.crop.rectangle.stack.fill", title: "Address Book") {
                triggerHaptic()
                onOpenAddressBook?(nil)
            }
            
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
            
            SettingsListRow(icon: "list.bullet.rectangle", title: "Address Management") {
                triggerHaptic()
                onOpenAddressBook?(.addresses)
            }
            
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
            
            SettingsListRow(icon: "calendar.badge.clock", title: "Scheduled Transactions") {
                triggerHaptic()
                if let cb = onOpenScheduledTx { cb() } else { /* legacy fallback */ }
            }
            
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
            
            SettingsListRow(icon: "network", title: "Network Settings") {
                triggerHaptic()
                if let cb = onOpenNetwork { cb() }
            }
            
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
            
            SettingsListRow(icon: "server.rack", title: "Node Management") {
                triggerHaptic()
                if let cb = onOpenNetwork { cb() }
            }
            
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
            
            SettingsListRow(icon: "doc.text.fill", title: "Export History") {
                triggerHaptic()
                if let cb = onOpenExport { cb() }
            }
            
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
            
            SettingsListRow(icon: "terminal.fill", title: "Debug Console") {
                triggerHaptic()
                if let cb = onOpenDebugConsole { cb() }
            }
            
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
            
            SettingsListRow(icon: "info.circle.fill", title: "About Hawala") {
                triggerHaptic()
                if let cb = onOpenAbout { cb() }
            }
            
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 52)
            
            SettingsListRow(icon: "questionmark.circle.fill", title: "Help & Support") {
                triggerHaptic()
                if let cb = onOpenHelpSupport { cb() }
            }
        }
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .padding(.top, HawalaTheme.Spacing.sm)
    }
    
    // MARK: - Danger Zone Card
    private var dangerZoneCard: some View {
        Button(action: { showResetConfirm = true }) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.red.opacity(0.8))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reset Wallet")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.red.opacity(0.9))
                    Text("Erase all data from this device")
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.35))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.red.opacity(0.4))
            }
            .padding(.horizontal, HawalaTheme.Spacing.lg)
            .padding(.vertical, HawalaTheme.Spacing.lg)
        }
        .buttonStyle(.plain)
        .background(Color.red.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                .strokeBorder(Color.red.opacity(0.15), lineWidth: 1)
        )
        .padding(.top, HawalaTheme.Spacing.lg)
    }
    
    // MARK: - Security Section
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
    
    // MARK: - Haptic Feedback
    private func triggerHaptic() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .default
        )
        #endif
    }
}

// MARK: - Settings Quick Toggle
struct SettingsQuickToggle: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isOn ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isOn ? .white : Color.white.opacity(0.4))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.4))
            }
            
            Spacer()
            
            // Modern pill toggle
            ZStack {
                Capsule()
                    .fill(isOn ? Color.white : Color.white.opacity(0.1))
                    .frame(width: 44, height: 26)
                
                Circle()
                    .fill(isOn ? Color(red: 0.06, green: 0.06, blue: 0.07) : Color.white.opacity(0.6))
                    .frame(width: 20, height: 20)
                    .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                    .offset(x: isOn ? 9 : -9)
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isOn.toggle()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(isHovered ? Color.white.opacity(0.02) : Color.clear)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint("Double-tap to toggle")
    }
}

// MARK: - Demo Amount Row
struct DemoAmountRow: View {
    let icon: String
    let label: String
    let color: Color
    @Binding var amount: Double
    
    @State private var isEditing = false
    @State private var textValue: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(color)
                )
            
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
            
            Spacer()
            
            // Amount input
            HStack(spacing: 4) {
                Text("$")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.5))
                
                TextField("0", text: $textValue)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onAppear {
                        textValue = formatAmount(amount)
                    }
                    .onChange(of: isFocused) { focused in
                        if !focused {
                            // Parse and save when losing focus
                            if let parsed = parseAmount(textValue) {
                                amount = parsed
                            }
                            textValue = formatAmount(amount)
                        }
                    }
                    .onSubmit {
                        if let parsed = parseAmount(textValue) {
                            amount = parsed
                        }
                        textValue = formatAmount(amount)
                        isFocused = false
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    private func formatAmount(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
    
    private func parseAmount(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: "")
                          .replacingOccurrences(of: "$", with: "")
                          .trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }
}

// MARK: - Settings Grid Card
struct SettingsGridCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let accentColor: Color
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                // Icon
                Circle()
                    .fill(Color.white.opacity(isHovered ? 0.12 : 0.08))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color.white.opacity(isHovered ? 0.9 : 0.6))
                    )
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HawalaTheme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.06 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovered ? 0.12 : 0.06), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.97 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Settings List Row
struct SettingsListRow: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.5))
                    )
                
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.25))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isHovered ? Color.white.opacity(0.03) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Theme Picker Row
struct ThemePickerRow: View {
    @ObservedObject var themeManager = ThemeManager.shared
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "paintbrush.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.5))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Theme")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Text("App appearance")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.4))
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
            .tint(Color.white.opacity(0.6))
            .frame(width: 110)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isHovered ? Color.white.opacity(0.04) : Color.clear)
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
        HStack(spacing: 14) {
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.5))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Display Currency")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Text("For balance display")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.4))
            }
            
            Spacer()
            
            Picker("", selection: $currency) {
                ForEach(currencies, id: \.code) { curr in
                    Text("\(curr.symbol) \(curr.code)")
                        .tag(curr.code)
                }
            }
            .pickerStyle(.menu)
            .tint(Color.white.opacity(0.6))
            .frame(width: 110)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isHovered ? Color.white.opacity(0.04) : Color.clear)
        .onHover { isHovered = $0 }
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
        HStack(spacing: 14) {
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "timer")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.5))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto-Lock Timeout")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Text("Lock app after inactivity")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.4))
            }
            
            Spacer()
            
            Picker("", selection: $autoLockTimeout) {
                ForEach(timeoutOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .tint(Color.white.opacity(0.6))
            .frame(width: 120)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isHovered ? Color.white.opacity(0.04) : Color.clear)
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
    @State private var step: ChangeStep = .verifyCurrent
    @State private var shakeOffset: CGFloat = 0
    
    enum ChangeStep {
        case verifyCurrent
        case enterNew
        case confirmNew
    }
    
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.06).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                ZStack {
                    Text(stepTitle)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    
                    HStack {
                        if step != .verifyCurrent {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    goBack()
                                }
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white.opacity(0.5))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)
                
                // Step indicator
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .fill(i <= stepIndex ? Color.white : Color.white.opacity(0.12))
                            .frame(width: i == stepIndex ? 24 : 8, height: 4)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: stepIndex)
                    }
                }
                .padding(.bottom, 20)
                
                Spacer()
                
                // Icon
                Image(systemName: stepIcon)
                    .font(.system(size: 36, weight: .thin))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.bottom, 16)
                
                // Subtitle
                Text(stepSubtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 24)
                
                // Error
                if let error = errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text(error)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                // PIN pad
                HawalaPinPad(pin: currentPinBinding, maxDigits: 6, onComplete: handlePinComplete)
                    .offset(x: shakeOffset)
                
                Spacer()
            }
        }
        .frame(width: 400, height: 560)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: step)
    }
    
    private var stepIndex: Int {
        switch step {
        case .verifyCurrent: return 0
        case .enterNew: return 1
        case .confirmNew: return 2
        }
    }
    
    private var stepTitle: String {
        switch step {
        case .verifyCurrent: return "Current Passcode"
        case .enterNew: return "New Passcode"
        case .confirmNew: return "Confirm Passcode"
        }
    }
    
    private var stepSubtitle: String {
        switch step {
        case .verifyCurrent: return "Enter your current passcode to continue"
        case .enterNew: return "Choose a new 6-digit passcode"
        case .confirmNew: return "Enter the same passcode again to confirm"
        }
    }
    
    private var stepIcon: String {
        switch step {
        case .verifyCurrent: return "key.fill"
        case .enterNew: return "lock.fill"
        case .confirmNew: return "checkmark.shield.fill"
        }
    }
    
    private var currentPinBinding: Binding<String> {
        switch step {
        case .verifyCurrent: return $currentPasscode
        case .enterNew: return $newPasscode
        case .confirmNew: return $confirmPasscode
        }
    }
    
    private func goBack() {
        errorMessage = nil
        switch step {
        case .confirmNew:
            step = .enterNew
            confirmPasscode = ""
        case .enterNew:
            step = .verifyCurrent
            newPasscode = ""
            currentPasscode = ""
        default: break
        }
    }
    
    private func handlePinComplete(_ pin: String) {
        errorMessage = nil
        switch step {
        case .verifyCurrent:
            guard passcodeManager.verifyPasscode(pin) else {
                errorMessage = "Incorrect passcode"
                triggerShake()
                currentPasscode = ""
                return
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                step = .enterNew
            }
        case .enterNew:
            guard pin != currentPasscode else {
                errorMessage = "Must be different from current"
                triggerShake()
                newPasscode = ""
                return
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                step = .confirmNew
            }
        case .confirmNew:
            guard pin == newPasscode else {
                errorMessage = "Passcodes don't match"
                triggerShake()
                confirmPasscode = ""
                return
            }
            isLoading = true
            let result = passcodeManager.changePasscode(current: currentPasscode, new: newPasscode)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isLoading = false
                if result.success {
                    ToastManager.shared.success("Passcode Updated")
                    dismiss()
                } else {
                    errorMessage = result.error ?? "Failed to update"
                }
            }
        }
    }
    
    private func triggerShake() {
        withAnimation(.default) { shakeOffset = -12 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.default) { shakeOffset = 12 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.default) { shakeOffset = -8 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { shakeOffset = 0 }
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
    @State private var shakeOffset: CGFloat = 0
    
    enum SetupStep {
        case create
        case confirm
    }
    
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.06).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                ZStack {
                    Text(step == .create ? "Set Passcode" : "Confirm Passcode")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    
                    HStack {
                        if step == .confirm {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    step = .create
                                    confirmPasscode = ""
                                    passcode = ""
                                    errorMessage = nil
                                }
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white.opacity(0.5))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)
                
                // Step indicator
                HStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { i in
                        Capsule()
                            .fill(i <= (step == .create ? 0 : 1) ? Color.white : Color.white.opacity(0.12))
                            .frame(width: i == (step == .create ? 0 : 1) ? 24 : 8, height: 4)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: step)
                    }
                }
                .padding(.bottom, 20)
                
                Spacer()
                
                // Icon
                Image(systemName: step == .create ? "lock.fill" : "checkmark.shield.fill")
                    .font(.system(size: 36, weight: .thin))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.bottom, 16)
                
                Text(step == .create ? "Choose a 6-digit passcode" : "Enter the same passcode again")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 24)
                
                if let error = errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text(error)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.bottom, 16)
                    .transition(.opacity)
                }
                
                HawalaPinPad(
                    pin: step == .create ? $passcode : $confirmPasscode,
                    maxDigits: 6,
                    onComplete: handlePinComplete
                )
                .offset(x: shakeOffset)
                
                Spacer()
            }
        }
        .frame(width: 400, height: 520)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: step)
    }
    
    private func handlePinComplete(_ pin: String) {
        errorMessage = nil
        if step == .create {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                step = .confirm
            }
        } else {
            guard pin == passcode else {
                errorMessage = "Passcodes don't match"
                triggerShake()
                confirmPasscode = ""
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
    
    private func triggerShake() {
        withAnimation(.default) { shakeOffset = -12 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.default) { shakeOffset = 12 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.default) { shakeOffset = -8 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { shakeOffset = 0 }
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

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    SettingsView()
        .frame(width: 500, height: 800)
}
#endif
#endif
#endif
