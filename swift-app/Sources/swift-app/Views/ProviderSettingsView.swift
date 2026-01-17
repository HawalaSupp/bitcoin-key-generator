import SwiftUI

// MARK: - Provider Settings View

/// Settings screen for managing data providers
struct ProviderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var healthManager = ProviderHealthManager.shared
    
    // Provider enable/disable toggles
    @AppStorage("provider.moralis.enabled") private var moralisEnabled = true
    @AppStorage("provider.tatum.enabled") private var tatumEnabled = true
    @AppStorage("provider.coinCap.enabled") private var coinCapEnabled = true
    @AppStorage("provider.cryptoCompare.enabled") private var cryptoCompareEnabled = true
    @AppStorage("provider.coinGecko.enabled") private var coinGeckoEnabled = true
    @AppStorage("provider.alchemy.enabled") private var alchemyEnabled = true
    @AppStorage("provider.mempool.enabled") private var mempoolEnabled = true
    @AppStorage("provider.blockchair.enabled") private var blockchairEnabled = true
    
    // Provider priority (lower = higher priority)
    @AppStorage("provider.price.priority") private var pricePriority = "moralis,coinCap,cryptoCompare,coinGecko"
    @AppStorage("provider.blockchain.priority") private var blockchainPriority = "moralis,alchemy,tatum,mempool,blockchair"
    
    // API key editing
    @State private var showMoralisKeyEditor = false
    @State private var moralisKeyInput = ""
    @State private var showTatumKeyEditor = false
    @State private var tatumKeyInput = ""
    @State private var showAlchemyKeyEditor = false
    @State private var alchemyKeyInput = ""
    @State private var showCoinGeckoKeyEditor = false
    @State private var coinGeckoKeyInput = ""
    
    // Check if API keys are configured
    private var hasMoralisKey: Bool {
        APIKeys.shared.hasMoralisKey
    }
    
    private var hasTatumKey: Bool {
        APIKeys.shared.hasTatumKey
    }
    
    private var hasAlchemyKey: Bool {
        APIKeys.shared.hasAlchemyKey
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            // Content
            ScrollView {
                VStack(spacing: HawalaTheme.Spacing.xl) {
                    // Status Overview
                    statusOverview
                    
                    // Price Providers
                    priceProvidersSection
                    
                    // Blockchain Providers
                    blockchainProvidersSection
                    
                    // API Keys Section
                    apiKeysSection
                    
                    // Advanced Section
                    advancedSection
                }
                .padding(HawalaTheme.Spacing.xl)
            }
        }
        .background(HawalaTheme.Colors.background)
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.accent)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text("Provider Settings")
                .font(HawalaTheme.Typography.h3)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
            
            Spacer()
            
            Button(action: {
                Task {
                    await healthManager.refreshAll()
                }
            }) {
                if healthManager.isChecking {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(HawalaTheme.Colors.accent)
                }
            }
            .buttonStyle(.plain)
            .disabled(healthManager.isChecking)
        }
        .padding(HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.backgroundSecondary)
    }
    
    // MARK: - Status Overview
    
    private var statusOverview: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            Text("Status")
                .font(HawalaTheme.Typography.h3)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
            
            HStack(spacing: HawalaTheme.Spacing.lg) {
                statusCard(
                    title: "Overall",
                    state: healthManager.overallHealth,
                    icon: overallHealthIcon
                )
                
                statusCard(
                    title: "Price Data",
                    state: bestPriceProviderState,
                    icon: "chart.line.uptrend.xyaxis"
                )
                
                statusCard(
                    title: "Blockchain",
                    state: bestBlockchainProviderState,
                    icon: "link"
                )
            }
        }
        .padding(HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .cornerRadius(HawalaTheme.Radius.md)
    }
    
    private var overallHealthIcon: String {
        switch healthManager.overallHealth {
        case .healthy: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .offline: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private var bestPriceProviderState: ProviderHealthState {
        // Check Moralis first (primary provider)
        if let moralis = healthManager.providerStatuses[.moralis], moralis.state == .healthy {
            return .healthy
        }
        if let coinCap = healthManager.providerStatuses[.coinCap], coinCap.state == .healthy {
            return .healthy
        }
        if let cryptoCompare = healthManager.providerStatuses[.cryptoCompare], cryptoCompare.state == .healthy {
            return .healthy
        }
        if let coinGecko = healthManager.providerStatuses[.coinGecko], coinGecko.state == .healthy {
            return .healthy
        }
        return .offline(reason: "No price providers available")
    }
    
    private var bestBlockchainProviderState: ProviderHealthState {
        if let moralis = healthManager.providerStatuses[.moralis], moralis.state == .healthy {
            return .healthy
        }
        if let alchemy = healthManager.providerStatuses[.alchemy], alchemy.state == .healthy {
            return .healthy
        }
        if let tatum = healthManager.providerStatuses[.tatum], tatum.state == .healthy {
            return .healthy
        }
        if let mempool = healthManager.providerStatuses[.mempool], mempool.state == .healthy {
            return .healthy
        }
        return .degraded(reason: "Limited connectivity")
    }
    
    @ViewBuilder
    private func statusCard(title: String, state: ProviderHealthState, icon: String) -> some View {
        VStack(spacing: HawalaTheme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(state.color.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(state.color)
            }
            
            Text(title)
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
            
            Text(state.displayText.components(separatedBy: ":").first ?? state.displayText)
                .font(HawalaTheme.Typography.captionBold)
                .foregroundColor(state.color)
        }
        .frame(maxWidth: .infinity)
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.backgroundTertiary)
        .cornerRadius(HawalaTheme.Radius.sm)
    }
    
    // MARK: - Price Providers Section
    
    private var priceProvidersSection: some View {
        SettingsSection("Price Providers") {
            // Moralis - Primary (Trust Wallet/Exodus/MetaMask)
            providerRow(
                provider: .moralis,
                title: "Moralis",
                subtitle: hasMoralisKey ? "API key configured ★ Primary" : "Used by Trust Wallet, Exodus, MetaMask",
                enabled: $moralisEnabled
            )
            
            Divider().padding(.leading, 56)
            
            providerRow(
                provider: .coinCap,
                title: "CoinCap",
                subtitle: "Free, no API key required",
                enabled: $coinCapEnabled
            )
            
            Divider().padding(.leading, 56)
            
            providerRow(
                provider: .cryptoCompare,
                title: "CryptoCompare",
                subtitle: "Free tier available",
                enabled: $cryptoCompareEnabled
            )
            
            Divider().padding(.leading, 56)
            
            providerRow(
                provider: .coinGecko,
                title: "CoinGecko",
                subtitle: "Rate limited on free tier",
                enabled: $coinGeckoEnabled
            )
        }
    }
    
    // MARK: - Blockchain Providers Section
    
    private var blockchainProvidersSection: some View {
        SettingsSection("Blockchain Providers") {
            providerRow(
                provider: .alchemy,
                title: "Alchemy",
                subtitle: hasAlchemyKey ? "API key configured" : "No API key",
                enabled: $alchemyEnabled
            )
            
            Divider().padding(.leading, 56)
            
            providerRow(
                provider: .tatum,
                title: "Tatum",
                subtitle: hasTatumKey ? "130+ chains configured" : "130+ blockchain networks",
                enabled: $tatumEnabled
            )
            
            Divider().padding(.leading, 56)
            
            providerRow(
                provider: .mempool,
                title: "Mempool.space",
                subtitle: "Bitcoin & Lightning",
                enabled: $mempoolEnabled
            )
            
            Divider().padding(.leading, 56)
            
            providerRow(
                provider: .blockchair,
                title: "Blockchair",
                subtitle: "Multi-chain explorer",
                enabled: $blockchairEnabled
            )
        }
    }
    
    @ViewBuilder
    private func providerRow(
        provider: ProviderType,
        title: String,
        subtitle: String,
        enabled: Binding<Bool>
    ) -> some View {
        let status = healthManager.providerStatuses[provider]
        
        HStack(spacing: HawalaTheme.Spacing.md) {
            // Status indicator
            ZStack {
                Circle()
                    .fill((status?.state ?? .unknown).color.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: (status?.state ?? .unknown).iconName)
                    .font(.system(size: 16))
                    .foregroundColor((status?.state ?? .unknown).color)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                HStack(spacing: 4) {
                    Text(subtitle)
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    
                    if let lastSuccess = status?.lastSuccess {
                        Text("• Last: \(timeAgo(lastSuccess))")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                }
            }
            
            Spacer()
            
            // Enable toggle
            Toggle("", isOn: enabled)
                .toggleStyle(SwitchToggleStyle(tint: HawalaTheme.Colors.accent))
                .labelsHidden()
        }
        .padding(.horizontal, HawalaTheme.Spacing.md)
        .padding(.vertical, HawalaTheme.Spacing.sm)
    }
    
    // MARK: - API Keys Section
    
    private var apiKeysSection: some View {
        SettingsSection("API Keys") {
            // Moralis (Primary - used by Trust Wallet, Exodus, MetaMask)
            apiKeyRow(
                title: "Moralis API Key",
                subtitle: hasMoralisKey ? "Configured ✓ (Recommended)" : "40K CU/day free • Used by Trust Wallet",
                color: .purple,
                isConfigured: hasMoralisKey,
                action: {
                    moralisKeyInput = ""
                    showMoralisKeyEditor = true
                }
            )
            
            Divider().padding(.leading, 56)
            
            // Tatum (130+ chains)
            apiKeyRow(
                title: "Tatum API Key",
                subtitle: hasTatumKey ? "Configured ✓" : "Optional • 130+ blockchain networks",
                color: .orange,
                isConfigured: hasTatumKey,
                action: {
                    tatumKeyInput = ""
                    showTatumKeyEditor = true
                }
            )
            
            Divider().padding(.leading, 56)
            
            // Alchemy
            apiKeyRow(
                title: "Alchemy API Key",
                subtitle: hasAlchemyKey ? "Configured ✓" : "Enterprise-grade RPC",
                color: .blue,
                isConfigured: hasAlchemyKey,
                action: {
                    alchemyKeyInput = ""
                    showAlchemyKeyEditor = true
                }
            )
            
            Divider().padding(.leading, 56)
            
            // CoinGecko
            apiKeyRow(
                title: "CoinGecko API Key",
                subtitle: "Optional - increases rate limits",
                color: .green,
                isConfigured: false,
                action: {
                    coinGeckoKeyInput = ""
                    showCoinGeckoKeyEditor = true
                }
            )
        }
        .sheet(isPresented: $showMoralisKeyEditor) {
            apiKeyEditor(
                title: "Moralis API Key",
                placeholder: "Enter your Moralis API key",
                helpText: "Get free key at moralis.io • Used by Trust Wallet, Exodus, MetaMask",
                value: $moralisKeyInput,
                onSave: {
                    if !moralisKeyInput.isEmpty {
                        APIKeys.setMoralisKey(moralisKeyInput)
                        ToastManager.shared.success("Moralis API key saved")
                    }
                    showMoralisKeyEditor = false
                }
            )
        }
        .sheet(isPresented: $showTatumKeyEditor) {
            apiKeyEditor(
                title: "Tatum API Key",
                placeholder: "Enter your Tatum API key",
                helpText: "Get free key at tatum.io • Supports 130+ blockchain networks",
                value: $tatumKeyInput,
                onSave: {
                    if !tatumKeyInput.isEmpty {
                        APIKeys.setTatumKey(tatumKeyInput)
                        ToastManager.shared.success("Tatum API key saved")
                    }
                    showTatumKeyEditor = false
                }
            )
        }
        .sheet(isPresented: $showAlchemyKeyEditor) {
            apiKeyEditor(
                title: "Alchemy API Key",
                placeholder: "Enter your Alchemy API key",
                helpText: "Get free key at alchemy.com",
                value: $alchemyKeyInput,
                onSave: {
                    if !alchemyKeyInput.isEmpty {
                        APIKeys.setAlchemyKey(alchemyKeyInput)
                        ToastManager.shared.success("Alchemy API key saved")
                    }
                    showAlchemyKeyEditor = false
                }
            )
        }
        .sheet(isPresented: $showCoinGeckoKeyEditor) {
            apiKeyEditor(
                title: "CoinGecko API Key",
                placeholder: "Enter your CoinGecko API key",
                helpText: "Optional • Increases rate limits",
                value: $coinGeckoKeyInput,
                onSave: {
                    // TODO: Implement CoinGecko key storage
                    ToastManager.shared.info("CoinGecko key support coming soon")
                    showCoinGeckoKeyEditor = false
                }
            )
        }
    }
    
    @ViewBuilder
    private func apiKeyRow(
        title: String,
        subtitle: String,
        color: Color,
        isConfigured: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "key.fill")
                    .font(.system(size: 16))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                Text(subtitle)
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(isConfigured ? .green : HawalaTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            Button(action: action) {
                Text(isConfigured ? "Update" : "Add")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.accent)
                    .padding(.horizontal, HawalaTheme.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(HawalaTheme.Colors.accent.opacity(0.15))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, HawalaTheme.Spacing.md)
        .padding(.vertical, HawalaTheme.Spacing.sm)
    }
    
    @ViewBuilder
    private func apiKeyEditor(
        title: String,
        placeholder: String,
        helpText: String = "",
        value: Binding<String>,
        onSave: @escaping () -> Void
    ) -> some View {
        VStack(spacing: HawalaTheme.Spacing.lg) {
            Text(title)
                .font(HawalaTheme.Typography.h3)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
            
            if !helpText.isEmpty {
                Text(helpText)
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            SecureField(placeholder, text: value)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 400)
            
            HStack(spacing: HawalaTheme.Spacing.md) {
                Button("Cancel") {
                    showMoralisKeyEditor = false
                    showTatumKeyEditor = false
                    showAlchemyKeyEditor = false
                    showCoinGeckoKeyEditor = false
                }
                .buttonStyle(.plain)
                
                Button("Save") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(HawalaTheme.Spacing.xl)
        .frame(minWidth: 400, minHeight: 220)
    }
    
    // MARK: - Advanced Section
    
    private var advancedSection: some View {
        SettingsSection("Advanced") {
            // Auto-retry toggle
            HStack(spacing: HawalaTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 16))
                        .foregroundColor(.orange)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Retry Failed Providers")
                        .font(HawalaTheme.Typography.body)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    Text("Automatically retry after \(Int(healthManager.retryInterval))s")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { healthManager.autoRetry },
                    set: { healthManager.autoRetry = $0 }
                ))
                .toggleStyle(SwitchToggleStyle(tint: HawalaTheme.Colors.accent))
                .labelsHidden()
            }
            .padding(.horizontal, HawalaTheme.Spacing.md)
            .padding(.vertical, HawalaTheme.Spacing.sm)
            
            Divider().padding(.leading, 56)
            
            // Reset all providers
            Button(action: {
                healthManager.resetAll()
                ToastManager.shared.info("Provider status reset")
            }) {
                HStack(spacing: HawalaTheme.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16))
                            .foregroundColor(.red)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset Provider Status")
                            .font(HawalaTheme.Typography.body)
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                        Text("Clear all health data and retry")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, HawalaTheme.Spacing.md)
            .padding(.vertical, HawalaTheme.Spacing.sm)
        }
    }
    
    // MARK: - Helpers
    
    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ProviderSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ProviderSettingsView()
            .frame(width: 500, height: 800)
    }
}
#endif
