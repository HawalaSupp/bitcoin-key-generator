import SwiftUI

/// Main settings panel with language, currency, and navigation to other settings
struct SettingsPanelView: View {
    let hasKeys: Bool
    let onShowKeys: () -> Void
    let onOpenSecurity: () -> Void
    @Binding var selectedCurrency: String
    let onCurrencyChanged: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var localization = LocalizationManager.shared
    @ObservedObject private var feedbackManager = FeedbackManager.shared
    @State private var selectedLanguage: LocalizationManager.Language = .english
    @State private var showPrivacySettings = false
    @ObservedObject private var privacyManager = PrivacyManager.shared
    @ObservedObject private var analyticsService = AnalyticsService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    languageSection
                    
                    Divider()
                    
                    currencySection
                    
                    Divider()
                    
                    feedbackSection
                    
                    Divider()

                    keysButton
                    securityButton
                    privacyButton
                    analyticsToggle

                    Spacer()
                }
                .padding()
            }
            .frame(width: 380, height: 520)
            .navigationTitle("settings.title".localized)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close".localized) { dismiss() }
                }
            }
        }
    }
    
    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Feedback")
                .font(.headline)
            
            Toggle(isOn: Binding(
                get: { feedbackManager.isSoundEnabled },
                set: { feedbackManager.isSoundEnabled = $0 }
            )) {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sound Effects")
                            .font(.body)
                        Text("Play sounds for actions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .toggleStyle(.switch)
            
            Toggle(isOn: Binding(
                get: { feedbackManager.isHapticEnabled },
                set: { feedbackManager.isHapticEnabled = $0 }
            )) {
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill")
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Haptic Feedback")
                            .font(.body)
                        Text("Trackpad haptics for actions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .toggleStyle(.switch)
        }
        .padding(.bottom, 8)
    }
    
    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.language".localized)
                .font(.headline)
            Picker("Language", selection: $selectedLanguage) {
                ForEach(LocalizationManager.Language.allCases) { language in
                    HStack(spacing: 8) {
                        Text(language.flag)
                        Text(language.displayName)
                    }
                    .tag(language)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: selectedLanguage) { newLang in
                localization.setLanguage(newLang)
            }
            .onAppear {
                selectedLanguage = localization.currentLanguage
            }
            
            Text("settings.language.description".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }

    private var currencySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.currency".localized)
                .font(.headline)
            Picker("Currency", selection: $selectedCurrency) {
                ForEach(FiatCurrency.allCases) { currency in
                    Text("\(currency.symbol) \(currency.displayName)")
                        .tag(currency.rawValue)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: selectedCurrency) { _ in
                onCurrencyChanged()
            }
        }
        .padding(.bottom, 8)
    }

    private var keysButton: some View {
        Button {
            dismiss()
            onShowKeys()
        } label: {
            Label("settings.show_keys".localized, systemImage: "doc.text.magnifyingglass")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!hasKeys)
    }

    private var securityButton: some View {
        Button {
            dismiss()
            onOpenSecurity()
        } label: {
            Label("settings.security".localized, systemImage: "lock.shield")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }
    
    private var privacyButton: some View {
        Button {
            showPrivacySettings = true
        } label: {
            HStack {
                Label("Privacy", systemImage: privacyManager.isPrivacyModeEnabled ? "eye.slash.fill" : "eye.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                if privacyManager.isPrivacyModeEnabled {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .buttonStyle(.bordered)
        .sheet(isPresented: $showPrivacySettings) {
            NavigationStack {
                PrivacySettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showPrivacySettings = false }
                        }
                    }
            }
            .frame(width: 450, height: 550)
        }
    }
    
    // MARK: - Analytics Opt-In/Out
    
    private var analyticsToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $analyticsService.isEnabled) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Anonymous Analytics")
                            .font(HawalaTheme.Typography.body)
                        Text("Help improve Hawala. No personal data collected.")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                }
            }
            .toggleStyle(.switch)
            .tint(HawalaTheme.Colors.accent)
            
            if analyticsService.isEnabled {
                Text("\(analyticsService.eventCount) events this session")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
    }
}
