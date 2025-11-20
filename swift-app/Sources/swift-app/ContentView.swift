import SwiftUI
import CryptoKit
import UniformTypeIdentifiers
import Security
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

private enum OnboardingStep: Int {
    case welcome
    case security
    case passcode
    case ready
}

private enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System Default"
        case .light: return "Light Mode"
        case .dark: return "Dark Mode"
        }
    }

    var menuIconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

private struct ViewWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 900
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ContentView: View {
    @State private var keys: AllKeys?
    @State private var rawJSON: String = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var statusColor: Color = .green
    @State private var statusTask: Task<Void, Never>?
    @State private var selectedChain: ChainInfo?
    @AppStorage("hawala.securityAcknowledged") private var hasAcknowledgedSecurityNotice = false
    @AppStorage("hawala.passcodeHash") private var storedPasscodeHash: String?
    @AppStorage("hawala.onboardingCompleted") private var onboardingCompleted = false
    @AppStorage("hawala.appearanceMode") private var storedAppearanceMode = AppearanceMode.system.rawValue
    @State private var isUnlocked = false
    @State private var showSecurityNotice = false
    @State private var showSecuritySettings = false
    @State private var showUnlockSheet = false
    @State private var showExportPasswordPrompt = false
    @State private var showImportPasswordPrompt = false
    @State private var pendingImportData: Data?
    @State private var showImportPrivateKeySheet = false
    @State private var onboardingStep: OnboardingStep = .welcome
    @State private var completedOnboardingThisSession = false
    @State private var shouldAutoGenerateAfterOnboarding = false
    @State private var hasResetOnboardingState = false
    @State private var balanceStates: [String: ChainBalanceState] = [:]
    @State private var priceStates: [String: ChainPriceState] = [:]
    @State private var cachedBalances: [String: CachedBalance] = [:]
    @State private var balanceBackoff: [String: BackoffTracker] = [:]
    @State private var balanceFetchTasks: [String: Task<Void, Never>] = [:]
    @State private var cachedPrices: [String: CachedPrice] = [:]
    @State private var priceBackoffTracker = BackoffTracker()
    @State private var priceUpdateTask: Task<Void, Never>?
    @State private var showAllPrivateKeysSheet = false
    @State private var showSettingsPanel = false
    @State private var showReceiveSheet = false
    @State private var showSendPicker = false
    @State private var sendChainContext: ChainInfo?
    @State private var pendingSendChain: ChainInfo?
    @State private var showSeedPhraseSheet = false
    @State private var viewportWidth: CGFloat = 900
    private let moneroBalancePlaceholder = "Balance protected – open your Monero wallet"
    private let trackedPriceChainIDs = [
        "bitcoin", "bitcoin-testnet", "ethereum", "ethereum-sepolia", "litecoin", "monero",
        "solana", "xrp", "bnb", "usdt-erc20", "usdc-erc20", "dai-erc20"
    ]
    private let sendEnabledChainIDs: Set<String> = [
        "bitcoin", "bitcoin-testnet", "litecoin", "ethereum", "ethereum-sepolia", "bnb", "solana"
    ]
    private let pricePollingInterval: TimeInterval = 30
    private let minimumBalanceRetryDelay: TimeInterval = 0.5
    private static var cachedWorkspaceRoot: URL?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var canAccessSensitiveData: Bool {
        storedPasscodeHash == nil || isUnlocked
    }

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: storedAppearanceMode) ?? .system
    }

    private var appearanceSelectionBinding: Binding<AppearanceMode> {
        Binding(
            get: { appearanceMode },
            set: { newValue in updateAppearanceMode(newValue) }
        )
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if onboardingCompleted {
                    mainAppStage
                } else {
                    onboardingFlow
                }
            }

            newestBuildBadge
                .padding(.top, 12)
                .padding(.trailing, 12)
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.3), value: onboardingCompleted)
        .animation(.easeInOut(duration: 0.3), value: onboardingStep)
        .preferredColorScheme(appearanceMode.colorScheme)
        .onAppear {
            guard !hasResetOnboardingState else { return }
            onboardingCompleted = false
            onboardingStep = .welcome
            shouldAutoGenerateAfterOnboarding = false
            balanceStates.removeAll()
            priceStates.removeAll()
            cachedBalances.removeAll()
            cachedPrices.removeAll()
            balanceBackoff.removeAll()
            priceBackoffTracker = BackoffTracker()
            hasResetOnboardingState = true
            
            // Try to load existing keys from Keychain
            loadKeysFromKeychain()
        }
        .onChange(of: onboardingCompleted) { completed in
            if completed && keys == nil {
                // Load keys when onboarding completes if not already loaded
                loadKeysFromKeychain()
            }
        }
    }

    private var mainAppStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Multi-Chain Key Generator")
                    .font(.largeTitle)
                    .bold()
                if let keys = keys {
                    Text("(\(keys.chainInfos.count) chains)")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                appearanceMenu
                Button {
                    guard hasAcknowledgedSecurityNotice else {
                        showSecurityNotice = true
                        return
                    }
                    guard canAccessSensitiveData else {
                        showUnlockSheet = true
                        return
                    }
                    showSettingsPanel = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title2)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }

            Text("Generate production-ready key material for Bitcoin, Litecoin, Monero, Solana, Ethereum, BNB, XRP, and popular ERC-20 tokens. Tap a card to inspect and copy individual keys.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    guard hasAcknowledgedSecurityNotice else {
                        showSecurityNotice = true
                        return
                    }
                    guard canAccessSensitiveData else {
                        showUnlockSheet = true
                        return
                    }
                    Task { await runGenerator() }
                } label: {
                    Label("Generate Keys", systemImage: "key.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating || !hasAcknowledgedSecurityNotice || !canAccessSensitiveData)

                Button {
                    clearSensitiveData()
                    errorMessage = nil
                } label: {
                    Label("Clear", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isGenerating || (keys == nil && errorMessage == nil))

                Button {
                    guard canAccessSensitiveData else {
                        showUnlockSheet = true
                        return
                    }
                    copyOutput()
                } label: {
                    Label("Copy JSON", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isGenerating || rawJSON.isEmpty || !canAccessSensitiveData)

                Menu {
                    Button {
                        guard keys != nil else {
                            showStatus("Generate keys before exporting.", tone: .info)
                            return
                        }
                        showExportPasswordPrompt = true
                    } label: {
                        Label("Export encrypted…", systemImage: "tray.and.arrow.up")
                    }
                    .disabled(keys == nil)

                    Button {
                        beginEncryptedImport()
                    } label: {
                        Label("Import encrypted…", systemImage: "tray.and.arrow.down")
                    }
                    
                    Divider()
                    
                    Button {
                        showImportPrivateKeySheet = true
                    } label: {
                        Label("Import Private Key…", systemImage: "key.horizontal")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                        .frame(maxWidth: .infinity)
                }
                .menuStyle(.borderedButton)
                .disabled(isGenerating || !hasAcknowledgedSecurityNotice || !canAccessSensitiveData)
            }

            if isGenerating {
                ProgressView("Running Rust generator...")
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            if let statusMessage {
                Text(statusMessage)
                    .foregroundStyle(statusColor)
                    .font(.caption)
            }

            contentArea

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 480)
        .sheet(item: $selectedChain, onDismiss: presentQueuedSendIfNeeded) { chain in
            let balanceState = balanceStates[chain.id] ?? defaultBalanceState(for: chain.id)
            let priceState = priceStates[chain.id] ?? defaultPriceState(for: chain.id)
            ChainDetailSheet(
                chain: chain,
                balanceState: balanceState,
                priceState: priceState,
                keys: keys,
                onCopy: { value in
                    copyToClipboard(value)
                },
                onSendRequested: { selectedChain in
                    pendingSendChain = selectedChain
                    self.selectedChain = nil
                }
            )
        }
        .sheet(isPresented: $showAllPrivateKeysSheet) {
            if let keys {
                AllPrivateKeysSheet(chains: keys.chainInfos, onCopy: copyToClipboard)
            } else {
                NoKeysPlaceholderView()
            }
        }
        .sheet(isPresented: $showReceiveSheet) {
            if let keys {
                ReceiveFundsSheet(chains: keys.chainInfos, onCopy: copyToClipboard)
            } else {
                NoKeysPlaceholderView()
            }
        }
        .sheet(item: $sendChainContext, onDismiss: { sendChainContext = nil }) { chain in
            if let keys {
                if chain.id.starts(with: "bitcoin") || chain.id.starts(with: "litecoin") {
                    BitcoinSendSheet(
                        chain: chain,
                        keys: keys,
                        onDismiss: {
                            sendChainContext = nil
                        },
                        onSuccess: { txid in
                            sendChainContext = nil
                            showStatus("Transaction broadcast: \(txid.prefix(16))...", tone: .success)
                        }
                    )
                } else if chain.id.starts(with: "ethereum") || chain.id.contains("erc20") {
                    EthereumSendSheet(
                        chain: chain,
                        keys: keys,
                        onDismiss: {
                            sendChainContext = nil
                        },
                        onSuccess: { txid in
                            sendChainContext = nil
                            showStatus("Transaction broadcast: \(txid.prefix(16))...", tone: .success)
                        }
                    )
                } else if chain.id == "bnb" {
                    BnbSendSheet(
                        chain: chain,
                        keys: keys,
                        onDismiss: {
                            sendChainContext = nil
                        },
                        onSuccess: { txid in
                            sendChainContext = nil
                            showStatus("Transaction broadcast: \(txid.prefix(16))...", tone: .success)
                        }
                    )
                } else if chain.id == "solana" {
                    SolanaSendSheet(
                        chain: chain,
                        keys: keys,
                        onDismiss: {
                            sendChainContext = nil
                        },
                        onSuccess: { txid in
                            sendChainContext = nil
                            showStatus("Transaction broadcast: \(txid.prefix(16))...", tone: .success)
                        }
                    )
                } else {
                    Text("Send functionality coming soon for \(chain.title)")
                        .padding()
                }
            } else {
                Text("Generate keys before sending funds.")
                    .padding()
            }
        }
        .sheet(isPresented: $showSendPicker, onDismiss: presentQueuedSendIfNeeded) {
            if let keys {
                SendAssetPickerSheet(
                    chains: sendEligibleChains(from: keys),
                    onSelect: { chain in
                        pendingSendChain = chain
                        showSendPicker = false
                    },
                    onDismiss: {
                        showSendPicker = false
                    }
                )
            }
        }
        .sheet(isPresented: $showSeedPhraseSheet) {
            SeedPhraseSheet(onCopy: { value in
                copyToClipboard(value)
            })
        }
        .sheet(isPresented: $showSettingsPanel) {
            SettingsPanelView(
                hasKeys: keys != nil,
                onShowKeys: {
                    if keys != nil {
                        DispatchQueue.main.async {
                            showAllPrivateKeysSheet = true
                        }
                    } else {
                        showStatus("Generate keys before viewing private material.", tone: .info)
                    }
                },
                onOpenSecurity: {
                    DispatchQueue.main.async {
                        showSecuritySettings = true
                    }
                }
            )
        }
        .sheet(isPresented: $showSecurityNotice) {
            SecurityNoticeView {
                hasAcknowledgedSecurityNotice = true
                showSecurityNotice = false
            }
        }
        .sheet(isPresented: $showSecuritySettings) {
            SecuritySettingsView(
                hasPasscode: storedPasscodeHash != nil,
                onSetPasscode: { passcode in
                    storedPasscodeHash = hashPasscode(passcode)
                    lock()
                    showSecuritySettings = false
                },
                onRemovePasscode: {
                    storedPasscodeHash = nil
                    isUnlocked = true
                    showSecuritySettings = false
                }
            )
        }
        .sheet(isPresented: $showUnlockSheet) {
            UnlockView(
                onSubmit: { candidate in
                    guard let expected = storedPasscodeHash else { return nil }
                    let hashed = hashPasscode(candidate)
                    if hashed == expected {
                        isUnlocked = true
                        showUnlockSheet = false
                        return nil
                    }
                    return "Incorrect passcode. Try again."
                },
                onCancel: {
                    showUnlockSheet = false
                }
            )
        }
        .sheet(isPresented: $showExportPasswordPrompt) {
            PasswordPromptView(
                mode: .export,
                onConfirm: { password in
                    showExportPasswordPrompt = false
                    performEncryptedExport(with: password)
                },
                onCancel: {
                    showExportPasswordPrompt = false
                }
            )
        }
        .sheet(isPresented: $showImportPasswordPrompt) {
            PasswordPromptView(
                mode: .import,
                onConfirm: { password in
                    showImportPasswordPrompt = false
                    finalizeEncryptedImport(with: password)
                },
                onCancel: {
                    showImportPasswordPrompt = false
                    pendingImportData = nil
                }
            )
        }
        .sheet(isPresented: $showImportPrivateKeySheet) {
            ImportPrivateKeySheet(
                onImport: { privateKey, chainType in
                    showImportPrivateKeySheet = false
                    Task {
                        await importPrivateKey(privateKey, for: chainType)
                    }
                },
                onCancel: {
                    showImportPrivateKeySheet = false
                }
            )
        }
        .onAppear {
            prepareSecurityState()
            triggerAutoGenerationIfNeeded()
            startPriceUpdatesIfNeeded()
        }
        .onChange(of: storedPasscodeHash) { _ in
            handlePasscodeChange()
        }
        .onChange(of: scenePhase) { phase in
            handleScenePhase(phase)
        }
        .onChange(of: shouldAutoGenerateAfterOnboarding) { newValue in
            if newValue {
                triggerAutoGenerationIfNeeded()
            }
        }
        .onChange(of: onboardingCompleted) { completed in
            if completed {
                startPriceUpdatesIfNeeded()
            } else {
                stopPriceUpdates()
            }
        }
    }

    private var onboardingFlow: some View {
        OnboardingFlowView(
            step: $onboardingStep,
            onSecurityAcknowledged: {
                hasAcknowledgedSecurityNotice = true
            },
            onSetPasscode: { passcode in
                storedPasscodeHash = hashPasscode(passcode)
                isUnlocked = true
            },
            onSkipPasscode: {
                storedPasscodeHash = nil
                isUnlocked = true
            },
            onFinish: {
                shouldAutoGenerateAfterOnboarding = true
                completedOnboardingThisSession = true
                onboardingCompleted = true
            }
        )
    }

    private struct OnboardingFlowView: View {
        @Binding var step: OnboardingStep
        let onSecurityAcknowledged: () -> Void
        let onSetPasscode: (String) -> Void
        let onSkipPasscode: () -> Void
        let onFinish: () -> Void

        @State private var passcode = ""
        @State private var confirmPasscode = ""
        @State private var errorMessage: String?
        @FocusState private var passcodeFieldFocused: Bool

        private var totalSteps: Double { 4 }

        var body: some View {
            VStack(alignment: .leading, spacing: 24) {
                header
                content
                Spacer()
                controls
            }
            .padding(32)
            .frame(minWidth: 560, minHeight: 520)
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to Hawala")
                    .font(.largeTitle)
                    .bold()
                Text(stepSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Step \(step.rawValue + 1) of 4")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(step.rawValue + 1), total: totalSteps)
                        .progressViewStyle(.linear)
                }
            }
        }

        @ViewBuilder
        private var content: some View {
            switch step {
            case .welcome:
                VStack(alignment: .leading, spacing: 16) {
                    Text("Let’s prepare your multi-chain vault with the right safeguards and workflows.")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 12) {
                        onboardingBullet("Generate secure keys across major chains in one flow.")
                        onboardingBullet("Encrypt backups and keep session data locked down.")
                        onboardingBullet("Track balances, history, and advanced features as we grow.")
                    }
                }
            case .security:
                VStack(alignment: .leading, spacing: 16) {
                    Label("Protect confidential material", systemImage: "lock.shield")
                        .font(.title3)
                        .bold()
                    Text("This app surfaces private keys, recovery phrases, and transaction secrets. Please review the essentials below before continuing:")
                        .font(.body)
                    VStack(alignment: .leading, spacing: 10) {
                        onboardingBullet("Never capture screenshots or paste keys into untrusted apps.")
                        onboardingBullet("Store any exports encrypted and keep them offline when possible.")
                        onboardingBullet("Clear the dashboard before leaving your device unattended.")
                        onboardingBullet("Use hardware wallets for long-term storage where practical.")
                    }
                }
            case .passcode:
                VStack(alignment: .leading, spacing: 16) {
                    Label("Secure the session", systemImage: "key.viewfinder")
                        .font(.title3)
                        .bold()
                    Text("Add a passcode to require unlocking before any generated keys are displayed. You can update this later in Security Settings.")
                        .font(.body)
                    VStack(alignment: .leading, spacing: 12) {
                        SecureField("Passcode", text: $passcode)
                            .textContentType(.password)
                            .focused($passcodeFieldFocused)
                        SecureField("Confirm passcode", text: $confirmPasscode)
                            .textContentType(.password)
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
            case .ready:
                VStack(alignment: .leading, spacing: 16) {
                    Label("All set", systemImage: "checkmark.seal.fill")
                        .font(.title3)
                        .bold()
                    Text("Your security preferences are saved. Next up you can generate fresh keys, review chain-by-chain details, and manage encrypted backups from the dashboard.")
                        .font(.body)
                    onboardingBullet("Generate keys and review details per supported chain.")
                    onboardingBullet("Export encrypted backups for safekeeping.")
                    onboardingBullet("Toggle security settings anytime from the toolbar.")
                }
            }
        }

        @ViewBuilder
        private var controls: some View {
            switch step {
            case .welcome:
                HStack {
                    Spacer()
                    Button("Get Started") {
                        withAnimation { step = .security }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .security:
                HStack {
                    backButton
                    Spacer()
                    Button("I Understand") {
                        onSecurityAcknowledged()
                        withAnimation { step = .passcode }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .passcode:
                HStack {
                    backButton
                    Spacer()
                    Button("Skip for now") {
                        passcode = ""
                        confirmPasscode = ""
                        errorMessage = nil
                        onSkipPasscode()
                        withAnimation { step = .ready }
                    }
                    .buttonStyle(.bordered)
                    Button("Save Passcode") {
                        handlePasscodeSave()
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .ready:
                HStack {
                    backButton
                    Spacer()
                    Button("Enter Hawala") {
                        onFinish()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }

        private var backButton: some View {
            Button("Back") {
                withAnimation {
                    switch step {
                    case .welcome:
                        break
                    case .security:
                        step = .welcome
                    case .passcode:
                        step = .security
                    case .ready:
                        step = .passcode
                    }
                }
            }
            .buttonStyle(.bordered)
            .opacity(step == .welcome ? 0 : 1)
            .disabled(step == .welcome)
        }

        private var stepSubtitle: String {
            switch step {
            case .welcome:
                return "Configure your secure workspace before generating keys."
            case .security:
                return "Understand the responsibilities that come with handling private keys."
            case .passcode:
                return "Add session protection to keep key material hidden when idle."
            case .ready:
                return "Everything is in place—let’s launch your dashboard."
            }
        }

        private func onboardingBullet(_ text: String) -> some View {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.callout)
                Text(text)
            }
        }

        private func handlePasscodeSave() {
            let trimmed = passcode.trimmingCharacters(in: .whitespacesAndNewlines)
            let confirmation = confirmPasscode.trimmingCharacters(in: .whitespacesAndNewlines)

            guard trimmed.count >= 6 else {
                errorMessage = "Choose at least 6 characters."
                passcodeFieldFocused = true
                return
            }

            guard trimmed == confirmation else {
                errorMessage = "Passcodes do not match."
                confirmPasscode = ""
                passcodeFieldFocused = true
                return
            }

            errorMessage = nil
            onSetPasscode(trimmed)
            withAnimation { step = .ready }
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if !hasAcknowledgedSecurityNotice {
            SecurityPromptView {
                showSecurityNotice = true
            }
        } else if !canAccessSensitiveData {
            LockedStateView {
                showUnlockSheet = true
            }
        } else if let keys {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    portfolioHeader
                    
                    actionButtonsRow

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Your Wallets")
                                    .font(.headline)
                                Text("\(keys.chainInfos.count) chains")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        
                        LazyVGrid(columns: gridColumns(for: viewportWidth), spacing: 14) {
                            ForEach(keys.chainInfos) { chain in
                                Button {
                                    guard canAccessSensitiveData else {
                                        showUnlockSheet = true
                                        return
                                    }
                                    selectedChain = chain
                                } label: {
                                    let balance = balanceStates[chain.id] ?? defaultBalanceState(for: chain.id)
                                    let price = priceStates[chain.id] ?? defaultPriceState(for: chain.id)
                                    ChainCard(
                                        chain: chain,
                                        balanceState: balance,
                                        priceState: price
                                    )
                                }
                                .buttonStyle(.plain)
                                .transition(cardTransition)
                            }
                        }
                        .animation(cardAnimation, value: viewportWidth)
                        .animation(cardAnimation, value: balanceAnimationToken)
                        .animation(cardAnimation, value: priceAnimationToken)
                    }

                    transactionHistorySection
                }
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: ViewWidthPreferenceKey.self, value: proxy.size.width)
                }
            )
            .onPreferenceChange(ViewWidthPreferenceKey.self) { width in
                viewportWidth = width
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "rectangle.and.text.magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No key material yet")
                    .font(.headline)
                Text("Generate a fresh set of keys to review per-chain details and copy them securely.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var cardBackgroundColor: Color {
        #if canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(UIColor.secondarySystemBackground)
        #endif
    }

    private func gridColumns(for width: CGFloat) -> [GridItem] {
        let effectiveWidth = (width.isFinite && width > 0) ? width : 900
        if effectiveWidth < 520 {
            return [GridItem(.flexible(), spacing: 12, alignment: .top)]
        } else if effectiveWidth < 900 {
            return [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14, alignment: .top)]
        } else {
            return [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 16, alignment: .top)]
        }
    }

    private var balanceAnimationToken: Int {
        balanceStates.reduce(0) { partial, entry in
            var hasher = Hasher()
            hasher.combine(entry.key)
            hasher.combine(String(describing: entry.value))
            return partial ^ hasher.finalize()
        }
    }

    private var priceAnimationToken: Int {
        priceStates.reduce(0) { partial, entry in
            var hasher = Hasher()
            hasher.combine(entry.key)
            hasher.combine(String(describing: entry.value))
            return partial ^ hasher.finalize()
        }
    }

    private var cardAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.45, dampingFraction: 0.82, blendDuration: 0.3)
    }

    private var cardTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity)
    }

    private var appearanceMenu: some View {
        Menu {
            Picker("Appearance", selection: appearanceSelectionBinding) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.menuIconName)
                        .tag(mode)
                }
            }
        } label: {
            Image(systemName: appearanceMode.menuIconName)
                .font(.title2)
                .padding(6)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Appearance")
        .help("Switch between system, light, or dark appearance")
    }

    private func updateAppearanceMode(_ mode: AppearanceMode) {
        guard appearanceMode != mode else { return }
        storedAppearanceMode = mode.rawValue
        showStatus("\(mode.displayName) enabled", tone: .info)
    }

    private var portfolioHeader: some View {
        VStack(spacing: 12) {
            Text("Total Portfolio Value")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            Text(totalBalanceDisplay)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            
            Text(priceStatusLine)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button {
                refreshAllBalances()
            } label: {
                Label("Refresh Balances", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.blue)
        }
        .frame(maxWidth: headerMaxWidth(for: viewportWidth))
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func headerMaxWidth(for width: CGFloat) -> CGFloat? {
        guard width.isFinite else { return nil }
        if width < 560 {
            return width - 16
        }
        return min(width - 120, 780)
    }

    private var totalBalanceDisplay: String {
        let result = calculatePortfolioTotal()
        guard let total = result.total, result.hasData else {
            return "—"
        }
        return formatFiatAmount(total, currencyCode: "USD")
    }

    private var priceStatusLine: String {
        if priceStates.isEmpty {
            return "Fetching live prices…"
        }

        if priceStates.values.contains(where: { state in
            if case .loading = state { return true }
            return false
        }) {
            return "Fetching live prices…"
        }

        if priceStates.values.contains(where: { state in
            if case .refreshing = state { return true }
            return false
        }) {
            return "Refreshing live prices…"
        }

        if priceStates.values.contains(where: { state in
            if case .stale = state { return true }
            return false
        }) {
            if let latest = latestPriceUpdate, let relative = relativeTimeDescription(from: latest) {
                return "Showing cached prices • updated \(relative)"
            }
            return "Showing cached prices"
        }

        if let latest = latestPriceUpdate, let relative = relativeTimeDescription(from: latest) {
            return "Live estimate • updated \(relative)"
        }

        return "Live estimate"
    }

    private var latestPriceUpdate: Date? {
        priceStates.values.compactMap { state in
            switch state {
            case .loaded(_, let timestamp):
                return timestamp
            case .refreshing(_, let timestamp):
                return timestamp
            case .stale(_, let timestamp, _):
                return timestamp
            default:
                return nil
            }
        }.max()
    }

    private func calculatePortfolioTotal() -> (total: Double?, hasData: Bool) {
        guard let keys else { return (nil, false) }
        var accumulator: Double = 0
        var hasValue = false

        for chain in keys.chainInfos {
            let balanceState = balanceStates[chain.id] ?? defaultBalanceState(for: chain.id)
            let priceState = priceStates[chain.id] ?? defaultPriceState(for: chain.id)

            guard
                let balance = extractNumericAmount(from: balanceState),
                let price = extractFiatPrice(from: priceState)
            else { continue }

            hasValue = true
            accumulator += balance * price
        }

        return hasValue ? (accumulator, true) : (nil, false)
    }

    @ViewBuilder
    private var actionButtonsRow: some View {
        if viewportWidth < 620 {
            VStack(spacing: 10) {
                actionButtonsContent
            }
        } else {
            HStack(spacing: 10) {
                actionButtonsContent
            }
        }
    }

    @ViewBuilder
    private var actionButtonsContent: some View {
        walletActionButton(
            title: "Send",
            systemImage: "paperplane.fill",
            color: .orange
        ) {
            if keys == nil {
                Task {
                    await runGenerator()
                    await MainActor.run {
                        openSendSheet()
                    }
                }
            } else {
                openSendSheet()
            }
        }
        .disabled(keys == nil && isGenerating)

        walletActionButton(
            title: "Receive",
            systemImage: "arrow.down.left.and.arrow.up.right",
            color: .green
        ) {
            guard keys != nil else {
                showStatus("Generate keys before receiving.", tone: .info)
                return
            }
            showReceiveSheet = true
        }
        .disabled(keys == nil)

        walletActionButton(
            title: "View Keys",
            systemImage: "doc.richtext",
            color: .blue
        ) {
            guard canAccessSensitiveData else {
                showUnlockSheet = true
                return
            }
            if keys != nil {
                showAllPrivateKeysSheet = true
            } else {
                showStatus("Generate keys before viewing private material.", tone: .info)
            }
        }
        .disabled(!canAccessSensitiveData)

        walletActionButton(
            title: "Export",
            systemImage: "tray.and.arrow.up",
            color: .purple
        ) {
            guard keys != nil else {
                showStatus("Generate keys before exporting.", tone: .info)
                return
            }
            showExportPasswordPrompt = true
        }
        .disabled(keys == nil)

        walletActionButton(
            title: "Seed Phrase",
            systemImage: "list.number.rtl",
            color: .purple
        ) {
            showSeedPhraseSheet = true
        }
    }


    @MainActor
    private func refreshAllBalances() {
        guard let keys else {
            showStatus("Generate keys to refresh balances.", tone: .info)
            return
        }

        startBalanceFetch(for: keys)
        showStatus("Refreshing balances…", tone: .info)
    }

    private func extractNumericAmount(from state: ChainBalanceState) -> Double? {
        let value: String
        switch state {
        case .loaded(let loadedValue, _), .refreshing(let loadedValue, _), .stale(let loadedValue, _, _):
            value = loadedValue
        default:
            return nil
        }

        let raw = value.split(separator: " ").first.map(String.init) ?? value
        let cleaned = raw.replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
    }

    private func extractFiatPrice(from state: ChainPriceState) -> Double? {
        let value: String
        switch state {
        case .loaded(let string, _), .refreshing(let string, _), .stale(let string, _, _):
            value = string
        default:
            return nil
        }

        let filtered = value.filter { "0123456789.,-".contains($0) }
        guard !filtered.isEmpty else { return nil }
        let normalized = filtered.replacingOccurrences(of: ",", with: "")
        return Double(normalized)
    }

    @ViewBuilder
    private func walletActionButton(
        title: String,
        systemImage: String,
        color: Color,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .tint(prominent ? color : .secondary)
        .controlSize(.large)
    }

    private var newestBuildBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.caption)
            Text("Version 1.3")
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.green.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.green.opacity(0.45), lineWidth: 1)
        )
        .foregroundStyle(Color.green)
        .accessibilityLabel("Version 1.3 indicator")
    }

    private var transactionHistorySection: some View {
        let history = mockHistoryEntries
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent Activity")
                        .font(.headline)
                    Text("Transaction history and events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showStatus("Full history view coming soon.", tone: .info)
                } label: {
                    Text("View All")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .buttonStyle(.link)
            }

            if history.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("No transactions yet")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Your activity will appear here once funds move.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(history) { entry in
                        TransactionHistoryRow(entry: entry)
                        if entry.id != history.last?.id {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var mockHistoryEntries: [TransactionHistoryEntry] {
        [
            TransactionHistoryEntry(
                id: "receive-btc",
                type: "Receive",
                asset: "Bitcoin",
                amountDisplay: "+0.015 BTC",
                status: "Completed",
                timestamp: "Mar 12 • 9:41 AM"
            ),
            TransactionHistoryEntry(
                id: "swap-usdc-sol",
                type: "Swap",
                asset: "USDC → SOL",
                amountDisplay: "Planned",
                status: "Coming soon",
                timestamp: "Roadmap"
            )
        ]
    }

    private struct TransactionHistoryEntry: Identifiable, Equatable {
        let id: String
        let type: String
        let asset: String
        let amountDisplay: String
        let status: String
        let timestamp: String
    }

    private struct TransactionHistoryRow: View {
        let entry: TransactionHistoryEntry

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: iconForType(entry.type))
                    .font(.title3)
                    .foregroundStyle(colorForType(entry.type))
                    .frame(width: 36, height: 36)
                    .background(colorForType(entry.type).opacity(0.15))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.asset)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(entry.timestamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 3) {
                    Text(entry.amountDisplay)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(amountColor)
                    Text(entry.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
        
        private func iconForType(_ type: String) -> String {
            switch type {
            case "Receive": return "arrow.down.circle.fill"
            case "Send": return "paperplane.fill"
            case "Swap": return "arrow.left.arrow.right.circle.fill"
            case "Stake": return "chart.bar.fill"
            default: return "circle.fill"
            }
        }
        
        private func colorForType(_ type: String) -> Color {
            switch type {
            case "Receive": return .green
            case "Send": return .orange
            case "Swap": return .blue
            case "Stake": return .purple
            default: return .gray
            }
        }
        
        private var amountColor: Color {
            if entry.amountDisplay.hasPrefix("+") {
                return .green
            } else if entry.amountDisplay.hasPrefix("-") {
                return .red
            }
            return .primary
        }
    }

    private enum StatusTone {
        case success
        case info
        case error

        var color: Color {
            switch self {
            case .success: return .green
            case .info: return .blue
            case .error: return .red
            }
        }
    }

    private func showStatus(_ message: String, tone: StatusTone, autoClear: Bool = true) {
        statusTask?.cancel()
        statusTask = nil
        statusColor = tone.color
        statusMessage = message

        guard autoClear else { return }

        statusTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                statusMessage = nil
                statusTask = nil
            }
        }
    }
    
    private func openSendSheet() {
        guard let keys else {
            showStatus("Generate keys before sending.", tone: .info)
            return
        }
        let available = sendEligibleChains(from: keys)
        guard !available.isEmpty else {
            showStatus("No send-ready chains available yet.", tone: .info)
            return
        }
        pendingSendChain = nil
        sendChainContext = nil
        showSendPicker = true
    }
    
    private func openSendSheet(for chain: ChainInfo) {
        pendingSendChain = nil
        sendChainContext = chain
    }

    private func presentQueuedSendIfNeeded() {
        guard let chain = pendingSendChain else { return }
        pendingSendChain = nil
        sendChainContext = chain
    }

    private func sendEligibleChains(from keys: AllKeys) -> [ChainInfo] {
        keys.chainInfos.filter { chain in
            isSendSupported(chainID: chain.id)
        }
    }

    private func isSendSupported(chainID: String) -> Bool {
        if sendEnabledChainIDs.contains(chainID) { return true }
        if chainID.contains("erc20") { return true }
        return false
    }

    private func loadKeysFromKeychain() {
        // Don't overwrite existing keys
        guard keys == nil else {
            print("ℹ️ Keys already loaded, skipping Keychain load")
            return
        }
        
        do {
            if let loadedKeys = try KeychainHelper.loadKeys() {
                keys = loadedKeys
                rawJSON = prettyPrintedJSON(from: try JSONEncoder().encode(loadedKeys))
                primeStateCaches(for: loadedKeys)
                print("✅ Loaded keys from Keychain")
                print("🔑 Bitcoin Testnet Address: \(loadedKeys.bitcoinTestnet.address)")
                
                // Mark onboarding as completed since user has existing keys
                if !onboardingCompleted {
                    onboardingCompleted = true
                    print("✅ Marking onboarding as completed (keys found in Keychain)")
                }
                
                startBalanceFetch(for: loadedKeys)
                startPriceUpdatesIfNeeded()
            } else {
                print("ℹ️ No keys found in Keychain")
            }
        } catch {
            print("⚠️ Failed to load keys from Keychain: \(error)")
        }
    }

    private func runGenerator() async {
        guard hasAcknowledgedSecurityNotice, canAccessSensitiveData else { return }
        isGenerating = true
        errorMessage = nil
        statusTask?.cancel()
        statusTask = nil
        statusMessage = nil

        do {
            let (result, jsonString) = try await runRustKeyGenerator()
            await MainActor.run {
                // Prime states BEFORE setting keys to avoid race condition
                primeStateCaches(for: result)
                keys = result
                rawJSON = jsonString
                isGenerating = false
                
                // Debug addresses
                print("🔑 Generated Bitcoin Testnet Address: \(result.bitcoinTestnet.address)")
                print("🔑 Generated Bitcoin Mainnet Address: \(result.bitcoin.address)")
                
                // Save to Keychain
                do {
                    try KeychainHelper.saveKeys(result)
                    print("✅ Keys saved to Keychain")
                } catch {
                    print("⚠️ Failed to save keys to Keychain: \(error)")
                }
                
                // Debug status
                let cardCount = result.chainInfos.count
                let hasTestnet = result.bitcoinTestnet.address.starts(with: "tb1")
                let hasSepolia = result.ethereumSepolia.address.starts(with: "0x")
                let summary = "Generated \(cardCount) chains • Bitcoin testnet available: \(hasTestnet ? "yes" : "no") • Ethereum Sepolia available: \(hasSepolia ? "yes" : "no")"
                statusMessage = summary
                statusColor = .green
                
                startBalanceFetch(for: result)
                startPriceUpdatesIfNeeded()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isGenerating = false
            }
        }
    }

    private func copyOutput() {
        guard !rawJSON.isEmpty, canAccessSensitiveData else { return }
        copyToClipboard(rawJSON)
    }

    private func copyToClipboard(_ text: String) {
#if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
#elseif canImport(UIKit)
        UIPasteboard.general.string = text
#endif

        showStatus("Copied to clipboard.", tone: .success)
    }

    private func performEncryptedExport(with password: String) {
        guard let keys else {
            showStatus("Nothing to export yet.", tone: .info)
            return
        }

        do {
            let archive = try buildEncryptedArchive(from: keys, password: password)
#if canImport(AppKit)
            DispatchQueue.main.async {
                let panel = NSSavePanel()
                var contentTypes: [UTType] = [.json]
                let customTypes = ["hawala", "hawbackup"].compactMap { UTType(filenameExtension: $0) }
                contentTypes.append(contentsOf: customTypes)
                panel.allowedContentTypes = contentTypes
                panel.nameFieldStringValue = defaultExportFileName()
                panel.title = "Save Encrypted Hawala Backup"
                panel.canCreateDirectories = true

                panel.begin { response in
                    if response == .OK, let url = panel.url {
                        do {
                            try archive.write(to: url)
                            self.showStatus("Encrypted backup saved to \(url.lastPathComponent)", tone: .success)
                        } catch {
                            self.showStatus("Failed to write file: \(error.localizedDescription)", tone: .error, autoClear: false)
                        }
                    }
                }
            }
#else
            showStatus("Encrypted export is only supported on macOS.", tone: .error, autoClear: false)
#endif
        } catch {
            showStatus("Export failed: \(error.localizedDescription)", tone: .error, autoClear: false)
        }
    }

    private func beginEncryptedImport() {
        guard hasAcknowledgedSecurityNotice else {
            showSecurityNotice = true
            return
        }

        guard canAccessSensitiveData else {
            showUnlockSheet = true
            return
        }

#if canImport(AppKit)
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            var contentTypes: [UTType] = [.json]
            let customTypes = ["hawala", "hawbackup"].compactMap { UTType(filenameExtension: $0) }
            contentTypes.append(contentsOf: customTypes)
            panel.allowedContentTypes = contentTypes
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.title = "Open Encrypted Hawala Backup"

            panel.begin { response in
                if response == .OK, let url = panel.url {
                    do {
                        let data = try Data(contentsOf: url)
                        self.pendingImportData = data
                        self.showImportPasswordPrompt = true
                    } catch {
                        self.showStatus("Failed to read file: \(error.localizedDescription)", tone: .error, autoClear: false)
                    }
                }
            }
        }
#else
        showStatus("Encrypted import is only supported on macOS.", tone: .error, autoClear: false)
#endif
    }

    @MainActor
    private func finalizeEncryptedImport(with password: String) {
        guard let archiveData = pendingImportData else {
            showStatus("No backup selected.", tone: .error)
            return
        }

        print("🔄 Starting encrypted import...")
        print("📦 Archive size: \(archiveData.count) bytes")
        
        do {
            let plaintext = try decryptArchive(archiveData, password: password)
            print("✅ Decryption successful, plaintext size: \(plaintext.count) bytes")
            
            // Debug: print first 200 characters of JSON
            if let jsonString = String(data: plaintext, encoding: .utf8) {
                print("📄 JSON preview: \(String(jsonString.prefix(200)))...")
            }
            
            let decoder = JSONDecoder()
            // Don't use convertFromSnakeCase because AllKeys already has custom CodingKeys
            let importedKeys = try decoder.decode(AllKeys.self, from: plaintext)
            print("✅ Keys decoded successfully")
            
            keys = importedKeys
            rawJSON = prettyPrintedJSON(from: plaintext)
            
            // Debug imported addresses
            print("🔑 Imported Bitcoin Testnet Address: \(importedKeys.bitcoinTestnet.address)")
            print("🔑 Imported Bitcoin Mainnet Address: \(importedKeys.bitcoin.address)")
            
            // Save to Keychain
            do {
                try KeychainHelper.saveKeys(importedKeys)
                print("✅ Imported keys saved to Keychain")
            } catch {
                print("⚠️ Failed to save imported keys to Keychain: \(error)")
            }
            
            primeStateCaches(for: importedKeys)
            startBalanceFetch(for: importedKeys)
            startPriceUpdatesIfNeeded()
            pendingImportData = nil
            showStatus("Encrypted backup imported successfully. Keys loaded.", tone: .success)
            print("✅ Import complete - UI should now show keys")
        } catch let DecodingError.keyNotFound(key, context) {
            print("❌ Missing key: \(key.stringValue)")
            print("❌ Context: \(context.debugDescription)")
            print("❌ Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            showStatus("Import failed: Missing required field '\(key.stringValue)'", tone: .error, autoClear: false)
        } catch let DecodingError.typeMismatch(type, context) {
            print("❌ Type mismatch for type: \(type)")
            print("❌ Context: \(context.debugDescription)")
            print("❌ Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            showStatus("Import failed: Invalid data format", tone: .error, autoClear: false)
        } catch {
            print("❌ Import failed: \(error)")
            showStatus("Import failed: \(error.localizedDescription)", tone: .error, autoClear: false)
        }
    }

    private func buildEncryptedArchive(from keys: AllKeys, password: String) throws -> Data {
        let encoder = JSONEncoder()
        // Don't use convertToSnakeCase because AllKeys already has custom CodingKeys
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let plaintext = try encoder.encode(keys)
        let envelope = try encryptPayload(plaintext, password: password)
        let archiveEncoder = JSONEncoder()
        archiveEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        archiveEncoder.dateEncodingStrategy = .iso8601
        return try archiveEncoder.encode(envelope)
    }

    private func decryptArchive(_ data: Data, password: String) throws -> Data {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(EncryptedPackage.self, from: data)
        return try decryptPayload(envelope, password: password)
    }

    private func encryptPayload(_ plaintext: Data, password: String) throws -> EncryptedPackage {
        let salt = randomData(count: 16)
        let key = deriveSymmetricKey(password: password, salt: salt)
        let nonce = try AES.GCM.Nonce(data: randomData(count: 12))
        let sealedBox = try AES.GCM.seal(plaintext, using: key, nonce: nonce)

        return EncryptedPackage(
            formatVersion: 1,
            createdAt: Date(),
            salt: salt.base64EncodedString(),
            nonce: Data(nonce).base64EncodedString(),
            ciphertext: sealedBox.ciphertext.base64EncodedString(),
            tag: sealedBox.tag.base64EncodedString()
        )
    }

    private func decryptPayload(_ envelope: EncryptedPackage, password: String) throws -> Data {
        guard
            let salt = Data(base64Encoded: envelope.salt),
            let nonceData = Data(base64Encoded: envelope.nonce),
            let ciphertext = Data(base64Encoded: envelope.ciphertext),
            let tag = Data(base64Encoded: envelope.tag)
        else {
            throw SecureArchiveError.invalidEnvelope
        }

        let key = deriveSymmetricKey(password: password, salt: salt)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(sealedBox, using: key)
    }

    private func deriveSymmetricKey(password: String, salt: Data) -> SymmetricKey {
        let passwordKey = SymmetricKey(data: Data(password.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: passwordKey,
            salt: salt,
            info: Data("hawala-key-backup".utf8),
            outputByteCount: 32
        )
    }

    private func randomData(count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: 0...255) })
    }
    
    @MainActor
    private func importPrivateKey(_ privateKey: String, for chainType: String) async {
        showStatus("Importing private key for \(chainType)...", tone: .info)
        
        // For now, show a message that the import functionality requires generating
        // keys from the Rust backend with custom seeds
        showStatus("""
            ⚠️ Private key import requires integration with the Rust key generator.
            
            Current implementation generates all keys from a single seed.
            To import individual private keys, you would need to:
            
            1. Modify the Rust backend to accept custom private keys
            2. Derive public addresses from the imported private key
            3. Merge with existing key set
            
            For now, you can:
            • Use the imported private key directly in the Bitcoin send flow
            • Export current keys and manually edit the JSON to include imported keys
            
            Imported key saved to clipboard for manual use.
            """, tone: .info, autoClear: false)
        
        // Copy to clipboard for user to use manually
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(privateKey, forType: .string)
    }

    private func defaultExportFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "hawala-backup-\(formatter.string(from: Date())).hawala"
    }

    private func prettyPrintedJSON(from data: Data) -> String {
        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
            let prettyString = String(data: prettyData, encoding: .utf8)
        else {
            return String(data: data, encoding: .utf8) ?? ""
        }

        return prettyString
    }

    private nonisolated static func resolveCargoExecutable() throws -> String {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment

        if let override = environment["CARGO_BIN"], fileManager.isExecutableFile(atPath: override) {
            return override
        }

        for path in candidateCargoPaths() {
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }

        if let whichPath = try locateCargoWithWhich(), fileManager.isExecutableFile(atPath: whichPath) {
            return whichPath
        }

        throw KeyGeneratorError.cargoNotFound
    }

    private nonisolated static func candidateCargoPaths() -> [String] {
        var paths: [String] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        paths.append("\(home)/.cargo/bin/cargo")
        paths.append(contentsOf: [
            "/opt/homebrew/bin/cargo",
            "/usr/local/bin/cargo",
            "/usr/bin/cargo"
        ])
        return paths
    }

    private nonisolated static func locateCargoWithWhich() throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "cargo"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    private nonisolated static func mergedEnvironment(forCargoExecutableAt path: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let cargoDirectory = (path as NSString).deletingLastPathComponent
        var segments = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        if !segments.contains(cargoDirectory) {
            segments.insert(cargoDirectory, at: 0)
        }
        environment["PATH"] = segments.joined(separator: ":")
        environment["CARGO_BIN"] = path
        return environment
    }

    private func runRustKeyGenerator() async throws -> (AllKeys, String) {
        // Run cargo resolution in a detached task to avoid blocking the main thread
        let cargoPath = try await Task.detached {
            try ContentView.resolveCargoExecutable()
        }.value

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "cargo",
                "run",
                "--manifest-path",
                manifestPath,
                "--quiet",
                "--",
                "--json"
            ]
            process.currentDirectoryURL = workspaceRoot
            process.environment = ContentView.mergedEnvironment(forCargoExecutableAt: cargoPath)

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { proc in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                let outputString = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let errorString = String(data: errorData, encoding: .utf8) ?? ""

                guard proc.terminationStatus == 0 else {
                    let message = errorString.isEmpty ? "Rust generator failed with exit code \(proc.terminationStatus)" : errorString
                    continuation.resume(throwing: KeyGeneratorError.executionFailed(message))
                    return
                }

                guard let jsonData = outputString.data(using: .utf8) else {
                    continuation.resume(throwing: KeyGeneratorError.executionFailed("Invalid UTF-8 output from generator"))
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    let decoded = try decoder.decode(AllKeys.self, from: jsonData)
                    continuation.resume(returning: (decoded, outputString))
                } catch {
                    print("Key decode failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }

            do {
                try process.run()
            } catch {
                let wrapped = KeyGeneratorError.executionFailed("Failed to launch cargo using \(cargoPath): \(error.localizedDescription)")
                continuation.resume(throwing: wrapped)
            }
        }
    }

    @MainActor
    private func clearSensitiveData() {
        keys = nil
        rawJSON = ""
        selectedChain = nil
        sendChainContext = nil
        statusTask?.cancel()
        statusTask = nil
        statusMessage = nil
        errorMessage = nil
        pendingImportData = nil
    pendingSendChain = nil
        showSendPicker = false
        showReceiveSheet = false
        showAllPrivateKeysSheet = false
        showImportPrivateKeySheet = false
        cancelBalanceFetchTasks()
        balanceStates.removeAll()
        cachedBalances.removeAll()
        balanceBackoff.removeAll()
        cachedPrices.removeAll()
        priceStates.removeAll()
        priceBackoffTracker = BackoffTracker()
        stopPriceUpdates()

        do {
            try KeychainHelper.deleteKeys()
            print("✅ Keys deleted from Keychain")
        } catch {
            print("⚠️ Failed to delete keys from Keychain: \(error)")
        }
    }

    @MainActor
    private func prepareSecurityState() {
        if !hasAcknowledgedSecurityNotice {
            showSecurityNotice = true
        }

        guard storedPasscodeHash != nil else {
            isUnlocked = true
            return
        }

        if completedOnboardingThisSession {
            isUnlocked = true
            showUnlockSheet = false
            completedOnboardingThisSession = false
        } else if !isUnlocked {
            showUnlockSheet = true
        }
    }

    @MainActor
    private func triggerAutoGenerationIfNeeded() {
        guard shouldAutoGenerateAfterOnboarding else { return }
        guard hasAcknowledgedSecurityNotice else { return }
        guard canAccessSensitiveData else { return }
        guard !isGenerating else { return }

        shouldAutoGenerateAfterOnboarding = false

        Task {
            await runGenerator()
        }
    }

    @MainActor
    private func startPriceUpdatesIfNeeded() {
        guard onboardingCompleted else { return }
        ensurePriceStateEntries()
        if priceUpdateTask == nil {
            markPriceStatesLoading()
            priceUpdateTask = Task {
                await priceUpdateLoop()
            }
        } else {
            Task {
                await fetchAndStorePrices()
            }
        }
    }

    @MainActor
    private func stopPriceUpdates() {
        priceUpdateTask?.cancel()
        priceUpdateTask = nil
        priceBackoffTracker = BackoffTracker()
    }

    @MainActor
    private func markPriceStatesLoading() {
        for id in trackedPriceChainIDs {
            applyPriceLoadingState(for: id)
        }
    }

    private func priceUpdateLoop() async {
        while !Task.isCancelled {
            let succeeded = await fetchAndStorePrices()
            let delay = await MainActor.run { () -> TimeInterval in
                if succeeded {
                    priceBackoffTracker.registerSuccess()
                    return pricePollingInterval
                } else {
                    return priceBackoffTracker.registerFailure()
                }
            }

            let clampedDelay = max(5, delay)
            let nanos = UInt64(clampedDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
        }
    }

    private func fetchAndStorePrices() async -> Bool {
        do {
            let snapshot = try await fetchPriceSnapshot()
            let now = Date()
            await MainActor.run {
                updatePriceStates(with: snapshot, timestamp: now)
            }
            return true
        } catch {
            await MainActor.run {
                applyPriceFailureState(message: error.localizedDescription)
            }
            return false
        }
    }

    @MainActor
    private func updatePriceStates(with snapshot: [String: Double], timestamp: Date) {
        for chainId in trackedPriceChainIDs {
            if let staticDisplay = staticPriceDisplay(for: chainId) {
                cachedPrices[chainId] = CachedPrice(value: staticDisplay, lastUpdated: timestamp)
                priceStates[chainId] = .loaded(value: staticDisplay, lastUpdated: timestamp)
                continue
            }

            guard let identifiers = priceIdentifiers(for: chainId) else { continue }
            guard let priceValue = identifiers.compactMap({ snapshot[$0] }).first else {
                if let cache = cachedPrices[chainId] {
                    priceStates[chainId] = .stale(value: cache.value, lastUpdated: cache.lastUpdated, message: "Price unavailable.")
                } else {
                    priceStates[chainId] = .failed("Price unavailable.")
                }
                continue
            }

            let display = formatFiatAmount(priceValue, currencyCode: "USD")
            cachedPrices[chainId] = CachedPrice(value: display, lastUpdated: timestamp)
            priceStates[chainId] = .loaded(value: display, lastUpdated: timestamp)
        }
    }

    private func priceIdentifiers(for chainId: String) -> [String]? {
        switch chainId {
        case "bitcoin":
            return ["bitcoin"]
        case "ethereum":
            return ["ethereum"]
        case "litecoin":
            return ["litecoin"]
        case "monero":
            return ["monero"]
        case "solana":
            return ["solana"]
        case "xrp":
            return ["ripple", "xrp"]
        case "bnb":
            return ["binancecoin", "bnb"]
        case "bitcoin-testnet", "ethereum-sepolia", "usdt-erc20", "usdc-erc20", "dai-erc20":
            return nil
        default:
            return nil
        }
    }

    private func fetchPriceSnapshot() async throws -> [String: Double] {
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,litecoin,monero,solana,ripple,binancecoin&vs_currencies=usd") else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = object as? [String: Any] else {
            throw BalanceFetchError.invalidPayload
        }

        var snapshot: [String: Double] = [:]
        for (key, value) in dictionary {
            if let entry = value as? [String: Any], let usd = entry["usd"] as? NSNumber {
                snapshot[key] = usd.doubleValue
            }
        }

        return snapshot
    }


    @MainActor
    private func startBalanceFetch(for keys: AllKeys) {
        cancelBalanceFetchTasks()
        balanceBackoff.removeAll()
        
        // Group 1: BlockCypher (Rate limited, must be spaced out)
        scheduleBalanceFetch(for: "bitcoin") {
            try await fetchBitcoinBalance(address: keys.bitcoin.address)
        }

        scheduleBalanceFetch(for: "bitcoin-testnet", delay: 0.5) {
            try await fetchBitcoinBalance(address: keys.bitcoinTestnet.address, isTestnet: true)
        }

        scheduleBalanceFetch(for: "litecoin", delay: 1.0) {
            try await fetchLitecoinBalance(address: keys.litecoin.address)
        }

        // Group 2: Independent APIs (Can run in parallel immediately)
        scheduleBalanceFetch(for: "solana") {
            try await fetchSolanaBalance(address: keys.solana.publicKeyBase58)
        }

        scheduleBalanceFetch(for: "xrp") {
            try await fetchXrpBalance(address: keys.xrp.classicAddress)
        }

        scheduleBalanceFetch(for: "bnb") {
            try await fetchBnbBalance(address: keys.bnb.address)
        }

        startEthereumAndTokenBalanceFetch(address: keys.ethereum.address)
    }

    @MainActor
    private func startEthereumAndTokenBalanceFetch(address: String) {
        scheduleBalanceFetch(for: "ethereum") {
            try await fetchEthereumBalanceViaInfura(address: address)
        }

        scheduleBalanceFetch(for: "usdt-erc20", delay: 0.7) {
            try await fetchERC20Balance(
                address: address,
                contractAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
                decimals: 6,
                symbol: "USDT"
            )
        }

        scheduleBalanceFetch(for: "usdc-erc20", delay: 1.4) {
            try await fetchERC20Balance(
                address: address,
                contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
                decimals: 6,
                symbol: "USDC"
            )
        }

        scheduleBalanceFetch(for: "dai-erc20", delay: 2.1) {
            try await fetchERC20Balance(
                address: address,
                contractAddress: "0x6B175474E89094C44Da98b954EedeAC495271d0F",
                decimals: 18,
                symbol: "DAI"
            )
        }
    }

    @MainActor
    private func ensurePriceStateEntries() {
        for id in trackedPriceChainIDs where priceStates[id] == nil {
            applyPriceLoadingState(for: id)
        }
    }

    @MainActor
    private func primeStateCaches(for keys: AllKeys) {
        let chains = keys.chainInfos
        for chain in chains {
            let balanceDefault = defaultBalanceState(for: chain.id)
            let priceDefault = defaultPriceState(for: chain.id)
            balanceStates[chain.id] = balanceDefault
            priceStates[chain.id] = priceDefault
        }
    }

    @MainActor
    private func defaultBalanceState(for chainID: String) -> ChainBalanceState {
        switch chainID {
        case "bitcoin-testnet":
            return .loading
        case "ethereum-sepolia":
            return .loaded(value: "Use Sepolia faucet for funds", lastUpdated: Date())
        case "monero":
            return .loaded(value: moneroBalancePlaceholder, lastUpdated: Date())
        default:
            return .loading
        }
    }

    @MainActor
    private func defaultPriceState(for chainID: String) -> ChainPriceState {
        if let staticDisplay = staticPriceDisplay(for: chainID) {
            return .loaded(value: staticDisplay, lastUpdated: Date())
        }
        return .loading
    }

    private func staticPriceDisplay(for chainID: String) -> String? {
        switch chainID {
        case "usdt-erc20", "usdc-erc20", "dai-erc20":
            return formatFiatAmount(1.0, currencyCode: "USD")
        case "bitcoin-testnet", "ethereum-sepolia":
            return "Testnet asset"
        default:
            return nil
        }
    }

    @MainActor
    private func applyPriceLoadingState(for chainId: String) {
        let now = Date()
        let state = PriceStateReducer.loadingState(
            cache: cachedPrices[chainId],
            staticDisplay: staticPriceDisplay(for: chainId),
            now: now
        )
        if case .loaded(let value, let timestamp) = state {
            cachedPrices[chainId] = CachedPrice(value: value, lastUpdated: timestamp)
        }
        priceStates[chainId] = state
    }

    @MainActor
    private func applyPriceFailureState(message: String) {
        let now = Date()
        for id in trackedPriceChainIDs {
            let state = PriceStateReducer.failureState(
                cache: cachedPrices[id],
                staticDisplay: staticPriceDisplay(for: id),
                message: message,
                now: now
            )
            if case .loaded(let value, let timestamp) = state {
                cachedPrices[id] = CachedPrice(value: value, lastUpdated: timestamp)
            }
            priceStates[id] = state
        }
    }

    @MainActor
    private func scheduleBalanceFetch(for chainId: String, delay: TimeInterval = 0, fetcher: @escaping () async throws -> String) {
        applyLoadingState(for: chainId)
        launchBalanceFetchTask(for: chainId, after: delay, fetcher: fetcher)
    }

    @MainActor
    private func cancelBalanceFetchTasks() {
        for task in balanceFetchTasks.values {
            task.cancel()
        }
        balanceFetchTasks.removeAll()
    }

    @MainActor
    private func launchBalanceFetchTask(for chainId: String, after delay: TimeInterval, fetcher: @escaping () async throws -> String) {
        balanceFetchTasks[chainId]?.cancel()
        let task = Task {
            if delay > 0 {
                let nanos = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
            await runBalanceFetchLoop(chainId: chainId, fetcher: fetcher)
        }
        balanceFetchTasks[chainId] = task
    }

    private func runBalanceFetchLoop(chainId: String, fetcher: @escaping () async throws -> String) async {
        while !Task.isCancelled {
            let succeeded = await performBalanceFetch(chainId: chainId, fetcher: fetcher)
            if succeeded || Task.isCancelled {
                return
            }

            let pendingDelay = await MainActor.run {
                balanceBackoff[chainId]?.remainingBackoff ?? minimumBalanceRetryDelay
            }
            let clampedDelay = max(pendingDelay, minimumBalanceRetryDelay)
            let nanos = UInt64(clampedDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
        }
    }

    @MainActor
    private func applyLoadingState(for chainId: String) {
        if let cache = cachedBalances[chainId] {
            balanceStates[chainId] = .refreshing(previous: cache.value, lastUpdated: cache.lastUpdated)
        } else {
            balanceStates[chainId] = .loading
        }
    }

    private func performBalanceFetch(chainId: String, fetcher: @escaping () async throws -> String) async -> Bool {
        if Task.isCancelled { return false }

        var pendingDelay: TimeInterval = 0
        await MainActor.run {
            if let tracker = balanceBackoff[chainId], tracker.isInBackoff {
                pendingDelay = tracker.remainingBackoff
            }
        }

        if pendingDelay > 0 {
            let nanos = UInt64(pendingDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            if Task.isCancelled { return false }
        }

        do {
            let displayValue = try await fetcher()
            await MainActor.run {
                let now = Date()
                cachedBalances[chainId] = CachedBalance(value: displayValue, lastUpdated: now)
                balanceStates[chainId] = .loaded(value: displayValue, lastUpdated: now)
                balanceBackoff[chainId] = nil
            }
            return true
        } catch {
            let friendlyMessage: String = await MainActor.run {
                var tracker = balanceBackoff[chainId] ?? BackoffTracker()
                let retryDelay = tracker.registerFailure()
                balanceBackoff[chainId] = tracker
                let message = friendlyBackoffMessage(for: error, retryDelay: retryDelay)
                if let cache = cachedBalances[chainId] {
                    balanceStates[chainId] = .stale(value: cache.value, lastUpdated: cache.lastUpdated, message: message)
                } else {
                    balanceStates[chainId] = .failed(message)
                }
                return message
            }
            let nextDelay = await MainActor.run {
                balanceBackoff[chainId]?.remainingBackoff ?? minimumBalanceRetryDelay
            }
            let addressHint = chainId == "xrp" ? " (XRP address retry pending)" : ""
            let formattedDelay = String(format: "%.1fs", max(nextDelay, minimumBalanceRetryDelay))
            print("⚠️ Balance fetch error for \(chainId): \(friendlyMessage) – \(error.localizedDescription). Next retry in \(formattedDelay)\(addressHint)")
            return false
        }
    }

    private func friendlyBackoffMessage(for error: Error, retryDelay: TimeInterval) -> String {
        var base: String
        if let balanceError = error as? BalanceFetchError {
            switch balanceError {
            case .invalidStatus(let code) where code == 429:
                base = "Temporarily rate limited"
            case .invalidStatus(let code):
                base = "Service returned status \(code)"
            case .invalidRequest:
                base = "Invalid request"
            case .invalidResponse:
                base = "Unexpected response"
            case .invalidPayload:
                base = "Unreadable data"
            }
        } else {
            base = error.localizedDescription
        }

        if retryDelay > 0.1 {
            return "\(base). Retrying in \(formatRetryDuration(retryDelay))…"
        }
        return base
    }

    private func formatRetryDuration(_ delay: TimeInterval) -> String {
        if delay >= 10 {
            return "\(Int(delay))s"
        } else {
            return String(format: "%.1fs", delay)
        }
    }

    private func fetchBitcoinBalance(address: String, isTestnet: Bool = false) async throws -> String {
        let symbol = isTestnet ? "tBTC" : "BTC"
        
        // Try BlockCypher first - more generous rate limits
        do {
            let baseURL = isTestnet ? "https://api.blockcypher.com/v1/btc/test3" : "https://api.blockcypher.com/v1/btc/main"
            guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                let url = URL(string: "\(baseURL)/addrs/\(encodedAddress)/balance") else {
                throw BalanceFetchError.invalidRequest
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BalanceFetchError.invalidResponse
            }

            if httpResponse.statusCode == 200 {
                let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
                if let dictionary = jsonObject as? [String: Any],
                   let balance = dictionary["balance"] as? NSNumber {
                    let btc = balance.doubleValue / 100_000_000.0
                    return formatCryptoAmount(btc, symbol: symbol, maxFractionDigits: 8)
                }
            }
        } catch {
            print("⚠️ BlockCypher failed, falling back to mempool.space: \(error)")
        }
        
        // Fallback to mempool.space
        let baseURL = isTestnet ? "https://mempool.space/testnet/api" : "https://mempool.space/api"
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: "\(baseURL)/address/\(encodedAddress)") else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }
        
        if httpResponse.statusCode == 404 {
            return formatCryptoAmount(0.0, symbol: symbol, maxFractionDigits: 8)
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = jsonObject as? [String: Any],
              let chainStats = dictionary["chain_stats"] as? [String: Any] else {
            throw BalanceFetchError.invalidPayload
        }

        let funded = (chainStats["funded_txo_sum"] as? NSNumber)?.doubleValue ?? 0
        let spent = (chainStats["spent_txo_sum"] as? NSNumber)?.doubleValue ?? 0
        let balanceInSats = max(0, funded - spent)
        let btc = balanceInSats / 100_000_000.0
        
        return formatCryptoAmount(btc, symbol: symbol, maxFractionDigits: 8)
    }

    private func fetchLitecoinBalance(address: String) async throws -> String {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://litecoinspace.org/api/address/\(encodedAddress)") else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            return "0.00000000 LTC"
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = jsonObject as? [String: Any],
              let chainStats = dictionary["chain_stats"] as? [String: Any] else {
            throw BalanceFetchError.invalidPayload
        }

        let funded = (chainStats["funded_txo_sum"] as? NSNumber)?.doubleValue ?? 0
        let spent = (chainStats["spent_txo_sum"] as? NSNumber)?.doubleValue ?? 0
        let balanceInLitoshis = max(0, funded - spent)
        let ltc = balanceInLitoshis / 100_000_000.0
        return formatCryptoAmount(ltc, symbol: "LTC", maxFractionDigits: 8)
    }

    private func fetchSolanaBalance(address: String) async throws -> String {
        guard let url = URL(string: "https://api.mainnet-beta.solana.com") else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getBalance",
            "params": [address]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidResponse
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = jsonObject as? [String: Any],
              let result = dictionary["result"] as? [String: Any],
              let lamportsNumber = result["value"] as? NSNumber else {
            throw BalanceFetchError.invalidPayload
        }

        let lamports = lamportsNumber.doubleValue
        let sol = lamports / 1_000_000_000.0
        return formatCryptoAmount(sol, symbol: "SOL", maxFractionDigits: 6)
    }

    private func fetchXrpBalanceViaRippleDataAPI(address: String) async throws -> String {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://data.ripple.com/v2/accounts/\(encodedAddress)/balances") else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            return formatCryptoAmount(0, symbol: "XRP", maxFractionDigits: 6)
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let payload = try decoder.decode(RippleDataAccountBalanceResponse.self, from: data)

        if payload.isAccountMissing {
            return formatCryptoAmount(0, symbol: "XRP", maxFractionDigits: 6)
        }

        if let balanceDecimal = payload.xrpBalanceValue {
            let xrp = NSDecimalNumber(decimal: balanceDecimal).doubleValue
            return formatCryptoAmount(xrp, symbol: "XRP", maxFractionDigits: 6)
        }

        return formatCryptoAmount(0, symbol: "XRP", maxFractionDigits: 6)
    }

    private func fetchXrpBalance(address: String) async throws -> String {
        let shortened = address.prefix(8)

        do {
            return try await fetchXrpBalanceViaRippleDataAPI(address: address)
        } catch {
            print("⚠️ Ripple Data API lookup failed for \(shortened)…: \(error.localizedDescription). Trying XRPSCAN next.")
        }

        do {
            return try await fetchXrpBalanceViaXrpScan(address: address)
        } catch {
            print("⚠️ XRPSCAN lookup failed for \(shortened)…: \(error.localizedDescription). Falling back to XRPL RPC endpoints.")
        }

        return try await fetchXrpBalanceViaRippleRPC(address: address)
    }

    private func fetchXrpBalanceViaRippleRPC(address: String) async throws -> String {
        var lastError: Error?
        let shortened = address.prefix(8)

        for endpoint in APIConfig.xrplEndpoints {
            do {
                return try await requestXrpBalance(address: address, endpoint: endpoint)
            } catch {
                print("⚠️ XRPL RPC \(endpoint) failed for \(shortened)…: \(error.localizedDescription)")
                lastError = error
                continue
            }
        }

        print("❌ All XRPL RPC endpoints exhausted for \(shortened)…")
        throw lastError ?? BalanceFetchError.invalidResponse
    }

    private func requestXrpBalance(address: String, endpoint: String) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try xrplAccountInfoPayload(address: address)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            return formatCryptoAmount(0, symbol: "XRP", maxFractionDigits: 6)
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        do {
            let xrpDecimal = try BalanceResponseParser.parseXRPLBalance(from: data)
            let xrp = NSDecimalNumber(decimal: xrpDecimal).doubleValue
            return formatCryptoAmount(xrp, symbol: "XRP", maxFractionDigits: 6)
        } catch {
            if xrplResponseIndicatesUnfundedAccount(data) {
                return formatCryptoAmount(0, symbol: "XRP", maxFractionDigits: 6)
            }
            throw error
        }
    }

    private func fetchXrpBalanceViaXrpScan(address: String) async throws -> String {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.xrpscan.com/api/v1/account/\(encodedAddress)") else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            return formatCryptoAmount(0, symbol: "XRP", maxFractionDigits: 6)
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let payload = try decoder.decode(XrpScanAccountResponse.self, from: data)

        if let balanceString = payload.xrpBalance ?? payload.balance,
           let balanceDecimal = Decimal(string: balanceString) {
            let xrp = NSDecimalNumber(decimal: balanceDecimal).doubleValue
            return formatCryptoAmount(xrp, symbol: "XRP", maxFractionDigits: 6)
        }

        return formatCryptoAmount(0, symbol: "XRP", maxFractionDigits: 6)
    }

    private func xrplAccountInfoPayload(address: String) throws -> Data {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "account_info",
            "id": 1,
            "params": [
                [
                    "account": address,
                    "ledger_index": "validated",
                    "queue": true
                ]
            ]
        ]

        return try JSONSerialization.data(withJSONObject: payload, options: [])
    }

    private func xrplResponseIndicatesUnfundedAccount(_ data: Data) -> Bool {
        guard
            let json = try? JSONSerialization.jsonObject(with: data, options: []),
            let dictionary = json as? [String: Any],
            let result = dictionary["result"] as? [String: Any]
        else { return false }

        if let errorCode = result["error"] as? String {
            return errorCode == "actNotFound"
        }

        if let status = result["status"] as? String, status == "error",
           let errorMessage = result["error_message"] as? String {
            return errorMessage.lowercased().contains("not found")
        }

        return false
    }

    private func fetchBnbBalance(address: String) async throws -> String {
        guard let url = URL(string: "https://bsc-dataseed.binance.org/") else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "eth_getBalance",
            "params": [address, "latest"]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = jsonObject as? [String: Any],
              let result = dictionary["result"] as? String else {
            throw BalanceFetchError.invalidPayload
        }

        let weiDecimal = decimalFromHex(result)
        let divisor = Decimal(string: "1000000000000000000") ?? Decimal(1_000_000_000_000_000_000)
        let bnbDecimal = weiDecimal / divisor
        let bnb = NSDecimalNumber(decimal: bnbDecimal).doubleValue
        return formatCryptoAmount(bnb, symbol: "BNB", maxFractionDigits: 6)
    }

    private func fetchEthereumBalanceViaInfura(address: String) async throws -> String {
        // Use Alchemy if configured, otherwise fallback to Blockchair
        if APIConfig.isAlchemyConfigured() {
            return try await fetchEthereumBalanceViaAlchemy(address: address)
        } else {
            return try await fetchEthereumBalanceViaBlockchair(address: address)
        }
    }
    
    private func fetchEthereumBalanceViaAlchemy(address: String) async throws -> String {
        guard let url = URL(string: APIConfig.alchemyMainnetURL) else {
            throw BalanceFetchError.invalidRequest
        }
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getBalance",
            "params": [address, "latest"],
            "id": 1
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }
        
                let ethDecimal = try BalanceResponseParser.parseAlchemyETHBalance(from: responseData)
                let eth = NSDecimalNumber(decimal: ethDecimal).doubleValue
        return formatCryptoAmount(eth, symbol: "ETH", maxFractionDigits: 6)
    }
    
    private func fetchEthereumBalanceViaBlockchair(address: String) async throws -> String {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.blockchair.com/ethereum/dashboards/address/\(encodedAddress)") else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }
        
        if httpResponse.statusCode == 404 {
            return "0.00 ETH"
        }
        
        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        do {
            let ethDecimal = try BalanceResponseParser.parseBlockchairETHBalance(from: data, address: address)
            let eth = NSDecimalNumber(decimal: ethDecimal).doubleValue
            return formatCryptoAmount(eth, symbol: "ETH", maxFractionDigits: 6)
        } catch {
            return "0.00 ETH"
        }
    }

    private func fetchERC20Balance(address: String, contractAddress: String, decimals: Int, symbol: String) async throws -> String {
        // Use Alchemy if configured, otherwise fallback to Blockchair
        if APIConfig.isAlchemyConfigured() {
            return try await fetchERC20BalanceViaAlchemy(address: address, contractAddress: contractAddress, decimals: decimals, symbol: symbol)
        } else {
            return try await fetchERC20BalanceViaBlockchair(address: address, contractAddress: contractAddress, decimals: decimals, symbol: symbol)
        }
    }
    
    private func fetchERC20BalanceViaAlchemy(address: String, contractAddress: String, decimals: Int, symbol: String) async throws -> String {
        guard let url = URL(string: APIConfig.alchemyMainnetURL) else {
            throw BalanceFetchError.invalidRequest
        }
        
        // balanceOf(address) function signature
        let functionSelector = "0x70a08231"
        let paddedAddress = String(address.dropFirst(2)).padding(toLength: 64, withPad: "0", startingAt: 0)
        let data = functionSelector + paddedAddress
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_call",
            "params": [
                [
                    "to": contractAddress,
                    "data": data
                ],
                "latest"
            ],
            "id": 1
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            return "0 \(symbol)"
        }
        
        do {
            let tokenAmountDecimal = try BalanceResponseParser.parseAlchemyERC20Balance(from: responseData, decimals: decimals)
            let amount = NSDecimalNumber(decimal: tokenAmountDecimal).doubleValue
            return formatCryptoAmount(amount, symbol: symbol, maxFractionDigits: decimals >= 6 ? 6 : decimals)
        } catch {
            return "0 \(symbol)"
        }
    }
    
    private func fetchERC20BalanceViaBlockchair(address: String, contractAddress: String, decimals: Int, symbol: String) async throws -> String {
        // Use Blockchair API for ERC-20 tokens - better rate limits
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.blockchair.com/ethereum/dashboards/address/\(encodedAddress)?erc_20=true") else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            return "0 \(symbol)"
        }

        let amountDecimal = try BalanceResponseParser.parseBlockchairERC20Balance(from: data, address: address, contractAddress: contractAddress, decimals: decimals)
        let amount = NSDecimalNumber(decimal: amountDecimal).doubleValue
        return formatCryptoAmount(amount, symbol: symbol, maxFractionDigits: decimals >= 6 ? 6 : decimals)
    }

    private func fetchEthplorerAccount(address: String) async throws -> EthplorerAddressResponse {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.ethplorer.io/getAddressInfo/\(encodedAddress)?apiKey=freekey") else {
            throw BalanceFetchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            return EthplorerAddressResponse(eth: .init(balance: 0), tokens: [])
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(EthplorerAddressResponse.self, from: data)
    }

    private func tokenBalance(for symbol: String, decimalsHint: Int, in tokens: [EthplorerAddressResponse.TokenBalance]?) -> Double {
        guard let tokens else { return 0 }
        let match = tokens.first { entry in
            guard let tokenSymbol = entry.tokenInfo?.symbol else { return false }
            return tokenSymbol.caseInsensitiveCompare(symbol) == .orderedSame
        }

        if let balance = match?.balance {
            return balance
        }

        if let rawBalance = match?.rawBalance,
           let rawDecimal = Decimal(string: rawBalance) {
            let decimals = match?.tokenInfo?.decimals.flatMap(Int.init) ?? decimalsHint
            let adjusted = decimalDividingByPowerOfTen(rawDecimal, exponent: decimals)
            return NSDecimalNumber(decimal: adjusted).doubleValue
        }

        return 0
    }

    private func decimalFromHex(_ hexString: String) -> Decimal {
        let sanitized = hexString.lowercased().hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
        guard !sanitized.isEmpty else { return Decimal.zero }

        var result = Decimal.zero
        for character in sanitized {
            result *= 16
            if let digit = Int(String(character), radix: 16) {
                result += Decimal(digit)
            } else {
                return Decimal.zero
            }
        }
        return result
    }

    private func decimalDividingByPowerOfTen(_ value: Decimal, exponent: Int) -> Decimal {
        var input = value
        var result = Decimal()
        let clampedExponent = Int16(clamping: exponent)
        NSDecimalMultiplyByPowerOf10(&result, &input, -clampedExponent, .plain)
        return result
    }

    private func normalizeAddressForCall(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") ? String(trimmed.dropFirst(2)) : trimmed
        let lowercased = stripped.lowercased()
        let filtered = lowercased.filter { "0123456789abcdef".contains($0) }
        let limited = filtered.count > 64 ? String(filtered.suffix(64)) : filtered
        guard limited.count < 64 else { return limited }
        return String(repeating: "0", count: 64 - limited.count) + limited
    }

    private func fetchEthereumBalance(address: String) async throws -> String {
        let payload = try await fetchEthplorerAccount(address: address)
        let balance = payload.eth.balance
        return formatCryptoAmount(balance, symbol: "ETH", maxFractionDigits: 6)
    }

    private func formatCryptoAmount(_ amount: Double, symbol: String, maxFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFractionDigits
        let formatted = formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.\(maxFractionDigits)f", amount)
        return "\(formatted) \(symbol)"
    }

    private func formatFiatAmount(_ amount: Double, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }

    private func handlePasscodeChange() {
        if storedPasscodeHash != nil {
            lock()
        } else {
            isUnlocked = true
        }
    }

    @MainActor
    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            startPriceUpdatesIfNeeded()
            if storedPasscodeHash != nil && !isUnlocked {
                showUnlockSheet = true
            }
        case .inactive, .background:
            stopPriceUpdates()
            clearSensitiveData()
            if storedPasscodeHash != nil {
                isUnlocked = false
            }
        @unknown default:
            break
        }
    }

    private func lock() {
        clearSensitiveData()
        isUnlocked = false
        showUnlockSheet = true
    }

    private func hashPasscode(_ passcode: String) -> String {
        let data = Data(passcode.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private var workspaceRoot: URL {
        if let cached = ContentView.cachedWorkspaceRoot {
            return cached
        }

        let resolved = resolveWorkspaceRoot()
        ContentView.cachedWorkspaceRoot = resolved
        return resolved
    }

    private var manifestPath: String {
        workspaceRoot
            .appendingPathComponent("rust-app")
            .appendingPathComponent("Cargo.toml")
            .path
    }

    private func resolveWorkspaceRoot() -> URL {
        let fm = FileManager.default

        let candidateDirectories: [URL] = [
            URL(fileURLWithPath: fm.currentDirectoryPath),
            URL(fileURLWithPath: Bundle.main.executablePath ?? "").deletingLastPathComponent(),
            Bundle.main.bundleURL,
            Bundle.main.bundleURL.deletingLastPathComponent()
        ]

        for candidate in candidateDirectories {
            if let root = findWorkspaceRoot(startingAt: candidate) {
                return root
            }
        }

        // Fallback to current directory if nothing else works
        return URL(fileURLWithPath: fm.currentDirectoryPath)
    }

    private func findWorkspaceRoot(startingAt initialURL: URL) -> URL? {
        let fm = FileManager.default
        var current = initialURL
            .resolvingSymlinksInPath()

        let maxDepth = 12
        for _ in 0..<maxDepth {
            let rustManifest = current
                .appendingPathComponent("rust-app")
                .appendingPathComponent("Cargo.toml")
            let swiftPackage = current
                .appendingPathComponent("swift-app")
                .appendingPathComponent("Package.swift")

            if fm.fileExists(atPath: rustManifest.path), fm.fileExists(atPath: swiftPackage.path) {
                return current
            }

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }

        return nil
    }
}

// MARK: - Bitcoin Transaction Types

private struct BitcoinUTXO: Codable {
    let txid: String
    let vout: Int
    let value: Int64
    let scriptpubkey: String
    let status: UTXOStatus
    
    struct UTXOStatus: Codable {
        let confirmed: Bool
        let blockHeight: Int?
        let blockHash: String?
        let blockTime: Int?
        
        enum CodingKeys: String, CodingKey {
            case confirmed
            case blockHeight = "block_height"
            case blockHash = "block_hash"
            case blockTime = "block_time"
        }
    }
}

private struct BitcoinFeeEstimates: Codable {
    let fastestFee: Int
    let halfHourFee: Int
    let hourFee: Int
    let economyFee: Int
    let minimumFee: Int
}

private enum BitcoinSendError: LocalizedError {
    case invalidAddress
    case insufficientFunds
    case amountTooLow
    case networkError(String)
    case signingFailed
    case broadcastFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Invalid Bitcoin address"
        case .insufficientFunds:
            return "Insufficient balance to cover amount + fees"
        case .amountTooLow:
            return "Amount must be greater than dust limit (546 sats)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .signingFailed:
            return "Failed to sign transaction"
        case .broadcastFailed(let msg):
            return "Broadcast failed: \(msg)"
        }
    }
}

// MARK: - Send Picker & Seed Phrase

private struct SendAssetPickerSheet: View {
    let chains: [ChainInfo]
    let onSelect: (ChainInfo) -> Void
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredChains: [ChainInfo] {
        let sorted = chains.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        if searchText.isEmpty { return sorted }
        return sorted.filter { $0.title.localizedCaseInsensitiveContains(searchText) || $0.id.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search assets", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.body)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding()

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredChains) { chain in
                            Button {
                                dismiss()
                                onSelect(chain)
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: chain.iconName)
                                        .font(.title2)
                                        .foregroundStyle(chain.accentColor)
                                        .frame(width: 44, height: 44)
                                        .background(chain.accentColor.opacity(0.1))
                                        .clipShape(Circle())
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(chain.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(chain.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(Color.gray.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Send Funds")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                        onDismiss()
                    }
                }
            }
        }
        .frame(width: 450, height: 550)
    }
}

private struct SeedPhraseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCount: MnemonicGenerator.WordCount = .twelve
    @State private var words: [String] = MnemonicGenerator.generate(wordCount: .twelve)
    let onCopy: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("Length", selection: $selectedCount) {
                    ForEach(MnemonicGenerator.WordCount.allCases) { count in
                        Text(count.title).tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedCount) { newValue in
                    regenerate(using: newValue)
                }

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                        ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                            HStack {
                                Text(String(format: "%02d", index + 1))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(word)
                                    .font(.headline)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal)
                }

                HStack(spacing: 12) {
                    Button {
                        regenerate(using: selectedCount)
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        let phrase = words.joined(separator: " ")
                        onCopy(phrase)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)

                Text("Back up this phrase securely. Anyone with access can control your wallets.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer(minLength: 0)
            }
            .padding(.top, 20)
            .navigationTitle("Seed Phrase")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 550, height: 600)
    }

    private func regenerate(using count: MnemonicGenerator.WordCount) {
        words = MnemonicGenerator.generate(wordCount: count)
    }
}

// MARK: - Bitcoin Send Sheet

private struct BitcoinSendSheet: View {
    let chain: ChainInfo
    let keys: AllKeys
    let onDismiss: () -> Void
    let onSuccess: (String) -> Void
    
    var body: some View {
        NavigationStack {
            BitcoinSendView(
                chain: chain,
                keys: keys,
                onDismiss: onDismiss,
                onSuccess: onSuccess,
                isPushed: false
            )
        }
        .frame(width: 480, height: 650)
    }

    enum FeeRate: String, CaseIterable {
        case fast = "Fast (~10 min)"
        case medium = "Medium (~30 min)"
        case slow = "Slow (~1 hour)"
        case economy = "Economy (~6+ hours)"
        
        var priority: Int {
            switch self {
            case .fast: return 0
            case .medium: return 1
            case .slow: return 2
            case .economy: return 3
            }
        }
    }
}

private struct BitcoinSendView: View {
    let chain: ChainInfo
    let keys: AllKeys
    let onDismiss: () -> Void
    let onSuccess: (String) -> Void
    let isPushed: Bool
    
    @Environment(\.dismiss) private var dismiss
    @State private var recipientAddress = ""
    @State private var amountBTC = ""
    @State private var selectedFeeRate: BitcoinSendSheet.FeeRate = .medium
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var feeEstimates: BitcoinFeeEstimates?
    @State private var availableBalance: Int64 = 0
    @State private var estimatedFee: Int64 = 0
    @State private var showConfirmation = false
    
    private var isTestnet: Bool {
        chain.id == "bitcoin-testnet"
    }
    
    private var baseURL: String {
        isTestnet ? "https://mempool.space/testnet/api" : "https://mempool.space/api"
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Amount Input (Large)
            VStack(spacing: 8) {
                Text("Amount to send")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TextField("0", text: $amountBTC)
                        .font(.system(size: 48, weight: .medium, design: .rounded))
                        .multilineTextAlignment(.center)
                        .frame(minWidth: 100)
                        .fixedSize(horizontal: true, vertical: false)
                    Text("BTC")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                
                if availableBalance > 0 {
                    Text("Available: \(formatSatoshis(availableBalance))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .onTapGesture { sendMax() }
                }
            }
            .padding(.top, 20)

            // Recipient Input
            VStack(alignment: .leading, spacing: 8) {
                Text("To")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.leading, 4)
                
                HStack {
                    Image(systemName: "person.circle.fill")
                        .foregroundStyle(.secondary)
                    TextField("Bitcoin Address", text: $recipientAddress)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                    
                    if !recipientAddress.isEmpty {
                        Button { recipientAddress = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)

            // Fee Selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Network Fee")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.leading, 4)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(BitcoinSendSheet.FeeRate.allCases, id: \.self) { rate in
                            FeeRateCard(
                                rate: rate,
                                isSelected: selectedFeeRate == rate,
                                estimates: feeEstimates,
                                onSelect: { selectedFeeRate = rate }
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal)
            
            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Spacer()

            // Send Button
            Button {
                Task { await sendTransaction() }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView().tint(.white)
                    }
                    Text(isLoading ? "Sending..." : "Send Bitcoin")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isValidForm ? Color.orange : Color.gray.opacity(0.3))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(isLoading || !isValidForm)
            .padding()
        }
        .navigationTitle("Send \(chain.title)")
        .toolbar {
            if !isPushed {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onDismiss()
                    }
                }
            }
        }
        .onAppear {
            Task {
                await loadBalanceAndFees()
            }
        }
    }
    
    private var isValidForm: Bool {
        !recipientAddress.isEmpty &&
        !amountBTC.isEmpty &&
        Double(amountBTC) ?? 0 > 0 &&
        feeEstimates != nil
    }
    
    private func feeRateForSelection(_ estimates: BitcoinFeeEstimates) -> Int {
        switch selectedFeeRate {
        case .fast: return estimates.fastestFee
        case .medium: return estimates.halfHourFee
        case .slow: return estimates.hourFee
        case .economy: return max(estimates.economyFee, estimates.minimumFee)
        }
    }
    
    private func formatSatoshis(_ sats: Int64) -> String {
        let btc = Double(sats) / 100_000_000.0
        return String(format: "%.8f BTC", btc)
    }
    
    private func sendMax() {
        // Reserve estimated fee (assume 1 input, 1 output = ~140 vBytes)
        let estimatedTxFee = Int64(feeEstimates.map { feeRateForSelection($0) * 140 } ?? 5000)
        let maxSendable = max(0, availableBalance - estimatedTxFee)
        amountBTC = String(format: "%.8f", Double(maxSendable) / 100_000_000.0)
        updateFeeEstimate()
    }
    
    private func updateFeeEstimate() {
        guard let estimates = feeEstimates else { return }
        // Rough estimate: 1 input (148 vB) + 2 outputs (2x34 vB) = ~216 vB
        let estimatedSize = 216
        let feeRate = feeRateForSelection(estimates)
        estimatedFee = Int64(estimatedSize * feeRate)
    }
    
    private func loadBalanceAndFees() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Get address
            let address = isTestnet ? keys.bitcoinTestnet.address : keys.bitcoin.address
            
            // Fetch UTXOs
            let utxos = try await fetchUTXOs(for: address)
            availableBalance = utxos.filter { $0.status.confirmed }.reduce(0) { $0 + $1.value }
            
            // Fetch fee estimates
            feeEstimates = try await fetchFeeEstimates()
            updateFeeEstimate()
            
        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
        }
    }
    
    private func fetchUTXOs(for address: String) async throws -> [BitcoinUTXO] {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseURL)/address/\(encoded)/utxo") else {
            throw BitcoinSendError.networkError("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BitcoinSendError.networkError("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw BitcoinSendError.networkError("HTTP \(httpResponse.statusCode)")
        }
        
        let utxos = try JSONDecoder().decode([BitcoinUTXO].self, from: data)
        return utxos
    }
    
    private func fetchFeeEstimates() async throws -> BitcoinFeeEstimates {
        guard let url = URL(string: "\(baseURL)/v1/fees/recommended") else {
            throw BitcoinSendError.networkError("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BitcoinSendError.networkError("Failed to fetch fees")
        }
        
        let estimates = try JSONDecoder().decode(BitcoinFeeEstimates.self, from: data)
        return estimates
    }
    
    private func sendTransaction() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Validate address
            let recipient = recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !recipient.isEmpty else {
                throw BitcoinSendError.invalidAddress
            }
            
            // Parse amount
            guard let btcAmount = Double(amountBTC) else {
                throw BitcoinSendError.amountTooLow
            }
            let satoshis = Int64(btcAmount * 100_000_000)
            
            guard satoshis >= 546 else { // Dust limit
                throw BitcoinSendError.amountTooLow
            }
            
            guard satoshis + estimatedFee <= availableBalance else {
                throw BitcoinSendError.insufficientFunds
            }
            
            // Get keys and fetch UTXOs
            let address = isTestnet ? keys.bitcoinTestnet.address : keys.bitcoin.address
            let privateWIF = isTestnet ? keys.bitcoinTestnet.privateWif : keys.bitcoin.privateWif
            
            let utxos = try await fetchUTXOs(for: address)
            let confirmedUTXOs = utxos.filter { $0.status.confirmed }
            
            guard !confirmedUTXOs.isEmpty else {
                throw BitcoinSendError.insufficientFunds
            }
            
            // Convert UTXOs to Input format for BitcoinTransactionBuilder
            let inputs = try confirmedUTXOs.map { utxo -> BitcoinTransactionBuilder.Input in
                guard let scriptData = Data(hex: utxo.scriptpubkey) else {
                    throw BitcoinSendError.networkError("Invalid scriptPubKey format")
                }
                return BitcoinTransactionBuilder.Input(
                    txid: utxo.txid,
                    vout: UInt32(utxo.vout),
                    value: Int64(utxo.value),
                    scriptPubKey: scriptData
                )
            }
            
            // Create outputs
            let outputs: [BitcoinTransactionBuilder.Output] = [
                BitcoinTransactionBuilder.Output(
                    address: recipient,
                    value: Int64(satoshis)
                )
            ]
            
            // Build and sign transaction
            let signedTx = try BitcoinTransactionBuilder.buildAndSign(
                inputs: inputs,
                outputs: outputs,
                privateKeyWIF: privateWIF,
                isTestnet: isTestnet
            )
            
            let rawTxHex = signedTx.rawHex
            
            // Broadcast transaction
            let baseURL = isTestnet ? "https://mempool.space/testnet/api" : "https://mempool.space/api"
            guard let url = URL(string: "\(baseURL)/tx") else {
                throw BitcoinSendError.networkError("Invalid broadcast URL")
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = rawTxHex.data(using: String.Encoding.utf8)
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BitcoinSendError.networkError("Invalid response")
            }
            
            if httpResponse.statusCode == 200 {
                // Success! Get txid from response
                let txid = String(data: data, encoding: .utf8) ?? "Unknown"
                
                await MainActor.run {
                    errorMessage = """
                    ✅ Transaction Sent Successfully!
                    
                    Transaction ID: \(txid)
                    Amount: \(btcAmount) BTC
                    Fee: \(Double(estimatedFee) / 100_000_000) BTC
                    
                    View on mempool.space
                    """
                    isLoading = false
                }
            } else {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw BitcoinSendError.broadcastFailed(errorMsg)
            }
            
        } catch let error as BitcoinSendError {
            await MainActor.run {
                errorMessage = error.errorDescription
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Error: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}

private struct FeeRateCard: View {
    let rate: BitcoinSendSheet.FeeRate
    let isSelected: Bool
    let estimates: BitcoinFeeEstimates?
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rate.rawValue.components(separatedBy: " (").first ?? "")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if let estimates {
                    let fee = feeRateForSelection(estimates, rate: rate)
                    Text("\(fee) sat/vB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(minWidth: 100, alignment: .leading)
            .background(isSelected ? Color.orange.opacity(0.15) : Color.gray.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
    
    private func feeRateForSelection(_ estimates: BitcoinFeeEstimates, rate: BitcoinSendSheet.FeeRate) -> Int {
        switch rate {
        case .fast: return estimates.fastestFee
        case .medium: return estimates.halfHourFee
        case .slow: return estimates.hourFee
        case .economy: return max(estimates.economyFee, estimates.minimumFee)
        }
    }
}

// MARK: - Ethereum Send Sheet

private struct EthereumSendSheet: View {
    let chain: ChainInfo
    let keys: AllKeys
    let onDismiss: () -> Void
    let onSuccess: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var recipientAddress = ""
    @State private var amountInput = ""
    @State private var selectedToken: TokenType = .eth
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var gasPrice: String = ""
    @State private var nonce: Int = 0
    @State private var balance: String = "0"
    @State private var estimatedGasFee: String = ""
    @State private var showConfirmation = false
    
    private var isTestnet: Bool {
        chain.id == "ethereum-sepolia"
    }
    
    private var rpcURL: String {
        isTestnet ? "https://sepolia.infura.io/v3/YOUR_KEY" : "https://ethereum.publicnode.com"
    }
    
    private var chainId: Int {
        isTestnet ? 11155111 : 1
    }
    
    enum TokenType: String, CaseIterable {
        case eth = "ETH"
        case usdt = "USDT"
        case usdc = "USDC"
        case dai = "DAI"
        
        var contractAddress: String? {
            switch self {
            case .eth: return nil
            case .usdt: return "0xdAC17F958D2ee523a2206206994597C13D831ec7"
            case .usdc: return "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
            case .dai: return "0x6B175474E89094C44Da98b954EedeAC495271d0F"
            }
        }
        
        var decimals: Int {
            switch self {
            case .eth: return 18
            case .usdt: return 6
            case .usdc: return 6
            case .dai: return 18
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Token Selector & Amount
                VStack(spacing: 16) {
                    Picker("Token", selection: $selectedToken) {
                        ForEach(TokenType.allCases, id: \.self) { token in
                            Text(token.rawValue).tag(token)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 40)
                    .onChange(of: selectedToken) { _ in
                        Task { await loadBalanceAndGas() }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        TextField("0", text: $amountInput)
                            .font(.system(size: 48, weight: .medium, design: .rounded))
                            .multilineTextAlignment(.center)
                            .frame(minWidth: 100)
                            .fixedSize(horizontal: true, vertical: false)
                            .onChange(of: amountInput) { _ in updateGasEstimate() }
                        Text(selectedToken.rawValue)
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("Available: \(balance)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .onTapGesture { sendMax() }
                }
                .padding(.top, 20)

                // Recipient Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("To")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.leading, 4)
                    
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .foregroundStyle(.secondary)
                        TextField("0x...", text: $recipientAddress)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                        
                        if !recipientAddress.isEmpty {
                            Button { recipientAddress = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                // Gas Info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Network Fee")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.leading, 4)
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Gas Price")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(gasPrice.isEmpty ? "—" : "\(gasPrice) Gwei")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Estimated Cost")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(estimatedGasFee.isEmpty ? "—" : "\(estimatedGasFee) ETH")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }

                Spacer()

                // Send Button
                Button {
                    Task { await sendTransaction() }
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView().tint(.white)
                        }
                        Text(isLoading ? "Sending..." : "Send \(selectedToken.rawValue)")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isValidForm ? Color.orange : Color.gray.opacity(0.3))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(!isValidForm || isLoading)
                .padding()
            }
            .navigationTitle("Send Ethereum")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss(); onDismiss() }
                }
            }
            .task {
                await loadBalanceAndGas()
            }
        }
        .frame(width: 480, height: 650)
    }
    
    private var isValidForm: Bool {
        !recipientAddress.isEmpty &&
        !amountInput.isEmpty &&
        (Double(amountInput) ?? 0) > 0 &&
        !gasPrice.isEmpty &&
        recipientAddress.hasPrefix("0x") &&
        recipientAddress.count == 42
    }
    
    private func sendMax() {
        // For ETH, subtract gas fee. For tokens, use full balance
        let balanceValue = Double(balance.replacingOccurrences(of: " \(selectedToken.rawValue)", with: "")) ?? 0
        
        if selectedToken == .eth {
            let gasFeeETH = Double(estimatedGasFee.replacingOccurrences(of: " ETH", with: "")) ?? 0
            let maxSendable = max(0, balanceValue - gasFeeETH)
            amountInput = String(format: "%.8f", maxSendable)
        } else {
            amountInput = String(format: "%.8f", balanceValue)
        }
    }
    
    private func updateGasEstimate() {
        guard !gasPrice.isEmpty else { return }
        let gasPriceGwei = Double(gasPrice) ?? 0
        let gasLimit = selectedToken == .eth ? 21000.0 : 65000.0
        let gasFeeETH = (gasPriceGwei * gasLimit) / 1_000_000_000.0
        estimatedGasFee = String(format: "%.6f", gasFeeETH)
    }
    
    private func loadBalanceAndGas() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let address = isTestnet ? keys.ethereumSepolia.address : keys.ethereum.address
            
            // Fetch nonce
            nonce = try await fetchNonce(address: address)
            
            // Fetch gas price
            let gasPriceWei = try await fetchGasPrice()
            let gasPriceGwei = Double(gasPriceWei) / 1_000_000_000.0
            await MainActor.run {
                gasPrice = String(format: "%.2f", gasPriceGwei)
                updateGasEstimate()
            }
            
            // Fetch balance
            let bal = try await fetchBalance(address: address)
            await MainActor.run {
                balance = bal
                isLoading = false
            }
            
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    private func fetchNonce(address: String) async throws -> Int {
        guard let url = URL(string: rpcURL) else {
            throw EthereumError.invalidAddress
        }
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getTransactionCount",
            "params": [address, "latest"],
            "id": 1
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let resultHex = json?["result"] as? String else {
            throw EthereumError.gasEstimationFailed
        }
        
        let cleaned = resultHex.hasPrefix("0x") ? String(resultHex.dropFirst(2)) : resultHex
        return Int(cleaned, radix: 16) ?? 0
    }
    
    private func fetchGasPrice() async throws -> UInt64 {
        guard let url = URL(string: rpcURL) else {
            throw EthereumError.invalidAddress
        }
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_gasPrice",
            "params": [],
            "id": 1
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let resultHex = json?["result"] as? String else {
            throw EthereumError.gasEstimationFailed
        }
        
        let cleaned = resultHex.hasPrefix("0x") ? String(resultHex.dropFirst(2)) : resultHex
        return UInt64(cleaned, radix: 16) ?? 20_000_000_000 // 20 Gwei default
    }
    
    private func fetchBalance(address: String) async throws -> String {
        if selectedToken == .eth {
            // Fetch ETH balance via RPC
            guard let url = URL(string: rpcURL) else {
                throw EthereumError.invalidAddress
            }
            
            let payload: [String: Any] = [
                "jsonrpc": "2.0",
                "method": "eth_getBalance",
                "params": [address, "latest"],
                "id": 1
            ]
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            guard let resultHex = json?["result"] as? String else {
                return "0 ETH"
            }
            
            let cleaned = resultHex.hasPrefix("0x") ? String(resultHex.dropFirst(2)) : resultHex
            let weiValue = Decimal(string: cleaned, locale: nil) ?? 0
            let ethValue = weiValue / Decimal(string: "1000000000000000000")!
            
            return String(format: "%.6f ETH", NSDecimalNumber(decimal: ethValue).doubleValue)
        } else {
            // TODO: Fetch ERC-20 token balance
            return "0 \(selectedToken.rawValue)"
        }
    }
    
    private func sendTransaction() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let privateKey = isTestnet ? keys.ethereumSepolia.privateHex : keys.ethereum.privateHex
            
            // Convert amount to Wei
            let amountValue = Double(amountInput) ?? 0
            let multiplier = pow(10.0, Double(selectedToken.decimals))
            let smallestUnit = UInt64(amountValue * multiplier)
            
            // Convert gas price to Wei
            let gasPriceGwei = Double(gasPrice) ?? 0
            let gasPriceWei = UInt64(gasPriceGwei * 1_000_000_000)
            
            let signedTx: String
            
            if selectedToken == .eth {
                // Send ETH
                signedTx = try EthereumTransaction.buildAndSign(
                    to: recipientAddress,
                    value: String(smallestUnit),
                    gasLimit: 21000,
                    gasPrice: String(gasPriceWei),
                    nonce: nonce,
                    chainId: chainId,
                    privateKeyHex: privateKey
                )
            } else {
                // Send ERC-20 token
                guard let contract = selectedToken.contractAddress else {
                    throw EthereumError.invalidAddress
                }
                
                signedTx = try EthereumTransaction.buildAndSignERC20Transfer(
                    tokenContract: contract,
                    to: recipientAddress,
                    amount: String(smallestUnit),
                    gasLimit: 65000,
                    gasPrice: String(gasPriceWei),
                    nonce: nonce,
                    chainId: chainId,
                    privateKeyHex: privateKey
                )
            }
            
            // Broadcast transaction
            let txid = try await broadcastTransaction(signedTx)
            
            await MainActor.run {
                isLoading = false
                onSuccess(txid)
                dismiss()
            }
            
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    private func broadcastTransaction(_ rawTx: String) async throws -> String {
        guard let url = URL(string: rpcURL) else {
            throw EthereumError.invalidAddress
        }
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_sendRawTransaction",
            "params": [rawTx],
            "id": 1
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw EthereumError.broadcastFailed("Network error")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        if let error = json?["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw EthereumError.broadcastFailed(message)
        }
        
        guard let txid = json?["result"] as? String else {
            throw EthereumError.broadcastFailed("No transaction ID returned")
        }
        
        return txid
    }
}

// MARK: - BNB Send Sheet

private struct BnbSendSheet: View {
    let chain: ChainInfo
    let keys: AllKeys
    let onDismiss: () -> Void
    let onSuccess: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var recipientAddress = ""
    @State private var amountInput = ""
    @State private var gasPriceGwei = ""
    @State private var balanceDisplay = "0 BNB"
    @State private var estimatedFee = "—"
    @State private var nonce: Int = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    private let rpcURL = "https://bsc-dataseed.binance.org/"
    private let chainId = 56
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Recipient") {
                    TextField("0x...", text: $recipientAddress)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                }
                
                Section("Amount") {
                    HStack {
                        TextField("0.0", text: $amountInput)
                        Text("BNB")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Available")
                        Spacer()
                        Text(balanceDisplay)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    
                    Button("Send Max") {
                        sendMax()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Section("Network Fee") {
                    HStack {
                        Text("Gas Price")
                        Spacer()
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(gasPriceGwei.isEmpty ? "—" : gasPriceGwei + " Gwei")
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    HStack {
                        Text("Estimated Fee")
                        Spacer()
                        Text(estimatedFee)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                
                Section {
                    Button {
                        Task { await sendTransaction() }
                    } label: {
                        HStack {
                            if isLoading { ProgressView().controlSize(.small).tint(.white) }
                            Text(isLoading ? "Sending..." : "Send BNB")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValidForm || isLoading)
                }
            }
            .navigationTitle("Send BNB")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onDismiss()
                    }
                }
            }
            .task { await loadWalletState() }
        }
        .frame(width: 500, height: 600)
    }
    
    private var isValidForm: Bool {
        recipientAddress.hasPrefix("0x") && recipientAddress.count == 42 &&
        (Double(amountInput) ?? 0) > 0 && !gasPriceGwei.isEmpty
    }
    
    private func sendMax() {
        let parts = balanceDisplay.replacingOccurrences(of: " BNB", with: "")
        let amount = Double(parts) ?? 0
        let fee = Double(estimatedFee.replacingOccurrences(of: " BNB", with: "")) ?? 0
        let maxValue = max(0, amount - fee)
        amountInput = String(format: "%.6f", maxValue)
    }
    
    private func loadWalletState() async {
        isLoading = true
        errorMessage = nil
        do {
            let address = keys.bnb.address
            nonce = try await fetchNonce(address: address)
            let gasPriceWei = try await fetchGasPrice()
            let gwei = Double(gasPriceWei) / 1_000_000_000.0
            gasPriceGwei = String(format: "%.2f", gwei)
            updateFeeEstimate()
            balanceDisplay = try await fetchBalance(address: address)
            isLoading = false
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    private func updateFeeEstimate() {
        let gasPrice = Double(gasPriceGwei) ?? 0
        let fee = (gasPrice * 21000.0) / 1_000_000_000.0
        estimatedFee = String(format: "%.6f BNB", fee)
    }
    
    private func fetchNonce(address: String) async throws -> Int {
        guard let url = URL(string: rpcURL) else { throw EthereumError.invalidAddress }
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getTransactionCount",
            "params": [address, "latest"],
            "id": 1
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let resultHex = json?["result"] as? String else {
            throw EthereumError.gasEstimationFailed
        }
        let cleaned = resultHex.hasPrefix("0x") ? String(resultHex.dropFirst(2)) : resultHex
        return Int(cleaned, radix: 16) ?? 0
    }
    
    private func fetchGasPrice() async throws -> UInt64 {
        guard let url = URL(string: rpcURL) else { throw EthereumError.invalidAddress }
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_gasPrice",
            "params": [],
            "id": 1
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let resultHex = json?["result"] as? String else {
            throw EthereumError.gasEstimationFailed
        }
        let cleaned = resultHex.hasPrefix("0x") ? String(resultHex.dropFirst(2)) : resultHex
        return UInt64(cleaned, radix: 16) ?? 5_000_000_000
    }
    
    private func fetchBalance(address: String) async throws -> String {
        guard let url = URL(string: rpcURL) else { throw EthereumError.invalidAddress }
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getBalance",
            "params": [address, "latest"],
            "id": 1
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let resultHex = json?["result"] as? String else {
            return "0 BNB"
        }
        let cleaned = resultHex.hasPrefix("0x") ? String(resultHex.dropFirst(2)) : resultHex
        let wei = UInt64(cleaned, radix: 16) ?? 0
        let bnb = Double(wei) / pow(10.0, 18.0)
        return String(format: "%.6f BNB", bnb)
    }
    
    private func sendTransaction() async {
        isLoading = true
        errorMessage = nil
        do {
            let privateKey = keys.bnb.privateHex
            let amountDecimal = NSDecimalNumber(string: amountInput)
            let multiplier = NSDecimalNumber(mantissa: 1, exponent: 18, isNegative: false)
            let weiAmount = amountDecimal.multiplying(by: multiplier).uint64Value
            guard weiAmount > 0 else { throw EthereumError.invalidAmount }
            let gasPriceWei = UInt64((Double(gasPriceGwei) ?? 5) * 1_000_000_000)
            let signedTx = try EthereumTransaction.buildAndSign(
                to: recipientAddress,
                value: String(weiAmount),
                gasLimit: 21000,
                gasPrice: String(gasPriceWei),
                nonce: nonce,
                chainId: chainId,
                privateKeyHex: privateKey
            )
            let txid = try await broadcastTransaction(signedTx)
            await MainActor.run {
                isLoading = false
                onSuccess(txid)
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    private func broadcastTransaction(_ raw: String) async throws -> String {
        guard let url = URL(string: rpcURL) else {
            throw EthereumError.invalidAddress
        }
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_sendRawTransaction",
            "params": [raw],
            "id": 1
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let error = json?["error"] as? [String: Any], let message = error["message"] as? String {
            throw EthereumError.broadcastFailed(message)
        }
        guard let txid = json?["result"] as? String else {
            throw EthereumError.broadcastFailed("No tx hash returned")
        }
        return txid
    }
}

// MARK: - Solana Send Sheet

private struct SolanaSendSheet: View {
    let chain: ChainInfo
    let keys: AllKeys
    let onDismiss: () -> Void
    let onSuccess: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var recipientAddress = ""
    @State private var amountSOL = ""
    @State private var balanceDisplay = "0 SOL"
    @State private var recentBlockhash = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    private let rpcURL = "https://api.mainnet-beta.solana.com"
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Amount Input
                VStack(spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        TextField("0", text: $amountSOL)
                            .font(.system(size: 48, weight: .medium, design: .rounded))
                            .multilineTextAlignment(.center)
                            .frame(minWidth: 100)
                            .fixedSize(horizontal: true, vertical: false)
                        Text("SOL")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("Available: \(balanceDisplay)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .onTapGesture { sendMax() }
                }
                .padding(.top, 20)

                // Recipient Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("To")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.leading, 4)
                    
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .foregroundStyle(.secondary)
                        TextField("Solana Address", text: $recipientAddress)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                        
                        if !recipientAddress.isEmpty {
                            Button { recipientAddress = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                // Network Fee Info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Network Fee")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.leading, 4)
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Estimated Fee")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("~0.000005 SOL")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.purple)
                        }
                        Spacer()
                        Text("Solana Network")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.1))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                // Send Button
                Button {
                    Task { await sendTransaction() }
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView().tint(.white)
                        }
                        Text(isLoading ? "Sending..." : "Send SOL")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isValidForm ? Color.purple : Color.gray.opacity(0.3))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(!isValidForm || isLoading)
                .padding()
            }
            .navigationTitle("Send Solana")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss(); onDismiss() }
                }
            }
            .task { await loadWalletState() }
        }
        .frame(width: 480, height: 600)
    }
    
    private var isValidForm: Bool {
        !recipientAddress.isEmpty && (Double(amountSOL) ?? 0) > 0 && !recentBlockhash.isEmpty
    }
    
    private func sendMax() {
        let value = Double(balanceDisplay.replacingOccurrences(of: " SOL", with: "")) ?? 0
        amountSOL = String(format: "%.6f", max(0, value - 0.000005))
    }
    
    private func loadWalletState() async {
        isLoading = true
        errorMessage = nil
        do {
            balanceDisplay = try await fetchBalance()
            recentBlockhash = try await fetchRecentBlockhash()
            isLoading = false
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    private func fetchBalance() async throws -> String {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getBalance",
            "params": [keys.solana.publicKeyBase58]
        ]
        let result = try await solanaRPCResult(payload: payload)
        if let wrapper = result as? [String: Any], let value = wrapper["value"] as? UInt64 {
            let sol = Double(value) / 1_000_000_000.0
            return String(format: "%.6f SOL", sol)
        }
        return "0 SOL"
    }
    
    private func fetchRecentBlockhash() async throws -> String {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getLatestBlockhash",
            "params": []
        ]
        if let result = try await solanaRPCResult(payload: payload) as? [String: Any],
           let value = result["value"] as? [String: Any],
           let hash = value["blockhash"] as? String {
            return hash
        }
        throw SolanaSendError.networkFailure("Missing blockhash")
    }
    
    private func solanaRPCResult(payload: [String: Any]) async throws -> Any {
        guard let url = URL(string: rpcURL) else {
            throw SolanaSendError.networkFailure("Invalid RPC URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let error = json?["error"] as? [String: Any], let message = error["message"] as? String {
            throw SolanaSendError.networkFailure(message)
        }
        guard let result = json?["result"] else {
            throw SolanaSendError.networkFailure("Malformed RPC response")
        }
        return result
    }
    
    private func sendTransaction() async {
        isLoading = true
        errorMessage = nil
        do {
            let amountDecimal = NSDecimalNumber(string: amountSOL)
            let lamports = amountDecimal.multiplying(by: NSDecimalNumber(value: 1_000_000_000)).uint64Value
            guard lamports > 0 else { throw SolanaSendError.invalidAmount }
            let signed = try SolanaTransaction.buildAndSign(
                from: keys.solana.publicKeyBase58,
                to: recipientAddress,
                amount: lamports,
                recentBlockhash: recentBlockhash,
                privateKeyBase58: keys.solana.privateKeyBase58
            )
            guard let txData = Base58.decode(signed) else {
                throw SolanaSendError.signingFailed
            }
            let base64Tx = txData.base64EncodedString()
            let payload: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sendTransaction",
                "params": [base64Tx]
            ]
            guard let txid = try await solanaRPCResult(payload: payload) as? String else {
                throw SolanaSendError.networkFailure("No transaction signature returned")
            }
            await MainActor.run {
                isLoading = false
                onSuccess(txid)
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

enum SolanaSendError: LocalizedError {
    case invalidAmount
    case signingFailed
    case networkFailure(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "Enter a valid SOL amount."
        case .signingFailed:
            return "Failed to sign transaction."
        case .networkFailure(let message):
            return message
        }
    }
}

private struct ReceiveFundsSheet: View {
    let chains: [ChainInfo]
    let onCopy: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var copiedChainID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(chains) { chain in
                        ReceiveAddressCard(
                            chain: chain,
                            isCopied: copiedChainID == chain.id,
                            onCopy: {
                                guard let address = chain.receiveAddress else { return }
                                onCopy(address)
                                copiedChainID = chain.id
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    if copiedChainID == chain.id {
                                        copiedChainID = nil
                                    }
                                }
                            }
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Receive Funds")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 550, height: 500)
    }
}

private struct ReceiveAddressCard: View {
    let chain: ChainInfo
    let isCopied: Bool
    let onCopy: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: chain.iconName)
                    .font(.title2)
                    .foregroundStyle(chain.accentColor)
                    .frame(width: 36, height: 36)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(chain.title)
                        .font(.headline)
                    Text(chain.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            Divider()
            
            if let address = chain.receiveAddress, !address.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Receive Address")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    
                    Text(address)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    Button(action: onCopy) {
                        Label(
                            isCopied ? "Copied!" : "Copy Address",
                            systemImage: isCopied ? "checkmark.circle.fill" : "doc.on.doc"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isCopied ? .green : chain.accentColor)
                    .animation(.easeInOut(duration: 0.2), value: isCopied)
                }
            } else {
                Text("Receiving address unavailable for this chain.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(chain.accentColor.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct ChainCard: View {
    let chain: ChainInfo
    let balanceState: ChainBalanceState
    let priceState: ChainPriceState

    @State private var skeletonPhase: CGFloat = -0.8

    private var pricePrimary: String {
        switch priceState {
        case .idle:
            return "—"
        case .loading:
            return "Loading…"
        case .refreshing(let value, _), .loaded(let value, _), .stale(let value, _, _):
            return value
        case .failed:
            return "Unavailable"
        }
    }

    private var isBalanceLoading: Bool {
        if case .loading = balanceState { return true }
        return false
    }

    private var isPriceLoading: Bool {
        if case .loading = priceState { return true }
        return false
    }

    private var priceDetail: (text: String, color: Color)? {
        switch priceState {
        case .refreshing(_, let timestamp):
            let detail = relativeTimeDescription(from: timestamp).map { "Refreshing… • updated \($0)" } ?? "Refreshing…"
            return (detail, .secondary)
        case .loaded(_, let timestamp):
            if let relative = relativeTimeDescription(from: timestamp) {
                return ("Updated \(relative)", .secondary)
            }
            return nil
        case .stale(_, let timestamp, let message):
            var detail = message
            if let relative = relativeTimeDescription(from: timestamp) {
                detail += " • updated \(relative)"
            }
            return (detail, .orange)
        case .failed(let message):
            return (message, .red)
        default:
            return nil
        }
    }

    private var balancePrimary: String {
        switch balanceState {
        case .idle:
            return "—"
        case .loading:
            return "Loading…"
        case .refreshing(let value, _), .loaded(let value, _), .stale(let value, _, _):
            return value
        case .failed:
            return "Unavailable"
        }
    }

    private var balanceDetail: (text: String, color: Color)? {
        switch balanceState {
        case .refreshing(_, let timestamp):
            if let relative = relativeTimeDescription(from: timestamp) {
                return ("Refreshing… • updated \(relative)", .secondary)
            }
            return ("Refreshing…", .secondary)
        case .loaded(_, let timestamp):
            if let relative = relativeTimeDescription(from: timestamp) {
                return ("Updated \(relative)", .secondary)
            }
            return nil
        case .stale(_, let timestamp, let message):
            var detail = message
            if let relative = relativeTimeDescription(from: timestamp) {
                detail += " • updated \(relative)"
            }
            return (detail, .orange)
        case .failed(let message):
            return (message, .red)
        default:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: chain.iconName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(chain.accentColor)
                    .frame(width: 40, height: 40)
                    .background(chain.accentColor.opacity(0.15))
                    .clipShape(Circle())
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(chain.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(chain.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer(minLength: 8)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Balance")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                        if isBalanceLoading {
                            SkeletonLine()
                        } else {
                            Text(balancePrimary)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                    if isBalanceLoading {
                        SkeletonLine(width: 110, height: 8)
                            .padding(.top, 2)
                    } else if let detail = balanceDetail {
                        Text(detail.text)
                            .font(.caption2)
                            .foregroundStyle(detail.color)
                    }
                    
                    HStack {
                        Text("Price")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                        if isPriceLoading {
                            SkeletonLine(width: 70)
                        } else {
                            Text(pricePrimary)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                    if isPriceLoading {
                        SkeletonLine(width: 90, height: 8)
                            .padding(.top, 2)
                    } else if let detail = priceDetail {
                        Text(detail.text)
                            .font(.caption2)
                            .foregroundStyle(detail.color)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(chain.accentColor.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct SkeletonLine: View {
    var width: CGFloat? = 80
    var height: CGFloat = 10
    var cornerRadius: CGFloat = 6

    @State private var phase: CGFloat = -0.8

    var body: some View {
        GeometryReader { geometry in
            let gradient = LinearGradient(
                colors: [
                    Color.primary.opacity(0.08),
                    Color.primary.opacity(0.18),
                    Color.primary.opacity(0.08)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(gradient)
                        .scaleEffect(x: 1.6, y: 1, anchor: .leading)
                        .offset(x: geometry.size.width * phase)
                )
                .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: phase)
                .onAppear {
                    phase = 0.9
                }
        }
        .frame(width: width, height: height)
    }
}

private struct CopyFeedbackBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.15), radius: 6, y: 4)
    }
}

private struct SettingsPanelView: View {
    let hasKeys: Bool
    let onShowKeys: () -> Void
    let onOpenSecurity: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    dismiss()
                    onShowKeys()
                } label: {
                    Label("Show All Private Keys", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasKeys)

                Button {
                    dismiss()
                    onOpenSecurity()
                } label: {
                    Label("Security Settings", systemImage: "lock.shield")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding()
            .frame(width: 350, height: 300)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct AllPrivateKeysSheet: View {
    let chains: [ChainInfo]
    let onCopy: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private var sections: [(chain: ChainInfo, items: [KeyDetail])] {
        chains.compactMap { chain in
            let privateItems = chain.details.filter { $0.label.localizedCaseInsensitiveContains("private") }
            guard !privateItems.isEmpty else { return nil }
            return (chain, privateItems)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if sections.isEmpty {
                        Text("No private key fields are available to display.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    } else {
                        ForEach(sections, id: \.chain.id) { section in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(section.chain.title)
                                    .font(.headline)
                                ForEach(section.items) { item in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(item.label)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        HStack(alignment: .top, spacing: 8) {
                                            Text(item.value)
                                                .font(.system(.body, design: .monospaced))
                                                .textSelection(.enabled)
                                            Spacer(minLength: 0)
                                            Button {
                                                onCopy(item.value)
                                            } label: {
                                                Image(systemName: "doc.on.doc")
                                                    .padding(6)
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                    .padding(12)
                                    .background(Color.gray.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("All Private Keys")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(width: 600, height: 700)
    }
}

private struct ChainDetailSheet: View {
    let chain: ChainInfo
    let balanceState: ChainBalanceState
    let priceState: ChainPriceState
    let keys: AllKeys?
    let onCopy: (String) -> Void
    let onSendRequested: (ChainInfo) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showReceiveInfo = false
    @State private var copyFeedbackMessage: String?
    @State private var copyFeedbackTask: Task<Void, Never>?
    
    private var isBitcoinChain: Bool {
        chain.id.starts(with: "bitcoin")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isBitcoinChain {
                        quickActionsSection
                    }
                    
                    if let receiveAddress = chain.receiveAddress {
                        receiveSection(address: receiveAddress)
                    }
                    balanceSummary
                    priceSummary
                }
                .padding()
            }
            .navigationTitle(chain.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(width: 480, height: 600)
        .overlay(alignment: .bottom) {
            if let message = copyFeedbackMessage {
                CopyFeedbackBanner(message: message)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    @ViewBuilder
    private var quickActionsSection: some View {
        HStack(spacing: 12) {
            Button {
                onSendRequested(chain)
            } label: {
                Label("Send", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(keys == nil)
            
            Button {
                withAnimation { showReceiveInfo = true }
            } label: {
                Label("Receive", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func receiveSection(address: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.title3)
                    .foregroundStyle(chain.accentColor)
                Text("Receive")
                    .font(.headline)
                Spacer()
                Button(showReceiveInfo ? "Hide" : "Show") {
                    withAnimation { showReceiveInfo.toggle() }
                }
                .buttonStyle(.bordered)
            }

            if showReceiveInfo {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Share this address to receive funds:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 8) {
                        Text(address)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button {
                            copyWithFeedback(value: address, label: "Receive address")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .padding(8)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(chain.accentColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var balanceSummary: some View {
        HStack(alignment: .center, spacing: 12) {
            Label("Balance", systemImage: "creditcard.fill")
                .font(.headline)
            Spacer()
            switch balanceState {
            case .idle:
                Text("—")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView()
                    .controlSize(.small)
            case .refreshing(let value, let timestamp):
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .foregroundStyle(chain.accentColor)
                    Text(relativeTimeDescription(from: timestamp).map { "Refreshing… • updated \($0)" } ?? "Refreshing…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .loaded(let value, let timestamp):
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .foregroundStyle(chain.accentColor)
                    if let relative = relativeTimeDescription(from: timestamp) {
                        Text("Updated \(relative)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            case .stale(let value, let timestamp, let message):
                let detail: String = {
                    if let relative = relativeTimeDescription(from: timestamp) {
                        return "\(message) • updated \(relative)"
                    }
                    return message
                }()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .foregroundStyle(chain.accentColor)
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            case .failed(let message):
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Unavailable")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            if let copyValue = balanceCopyValue {
                Button {
                    copyWithFeedback(value: copyValue, label: "\(chain.title) balance")
                } label: {
                    Label("Copy Balance", systemImage: "doc.on.doc")
                }
            }
        }
    }

    @ViewBuilder
    private var priceSummary: some View {
        HStack(alignment: .center, spacing: 12) {
            Label("Price", systemImage: "dollarsign.circle.fill")
                .font(.headline)
            Spacer()
            switch priceState {
            case .idle:
                Text("—")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView()
                    .controlSize(.small)
            case .refreshing(let value, let timestamp):
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .foregroundStyle(chain.accentColor)
                    Text(relativeTimeDescription(from: timestamp).map { "Refreshing… • updated \($0)" } ?? "Refreshing…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .loaded(let value, let timestamp):
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .foregroundStyle(chain.accentColor)
                    if let relative = relativeTimeDescription(from: timestamp) {
                        Text("Updated \(relative)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            case .stale(let value, let timestamp, let message):
                let detail: String = {
                    if let relative = relativeTimeDescription(from: timestamp) {
                        return "\(message) • updated \(relative)"
                    }
                    return message
                }()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .foregroundStyle(chain.accentColor)
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            case .failed(let message):
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Unavailable")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            if let copyValue = priceCopyValue {
                Button {
                    copyWithFeedback(value: copyValue, label: "\(chain.title) price")
                } label: {
                    Label("Copy Price", systemImage: "dollarsign.circle")
                }
            }
        }
    }

    private var balanceCopyValue: String? {
        switch balanceState {
        case .refreshing(let value, _), .loaded(let value, _), .stale(let value, _, _):
            return value
        default:
            return nil
        }
    }

    private var priceCopyValue: String? {
        switch priceState {
        case .refreshing(let value, _), .loaded(let value, _), .stale(let value, _, _):
            return value
        default:
            return nil
        }
    }

    private func copyWithFeedback(value: String, label: String) {
        onCopy(value)
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { @MainActor in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                copyFeedbackMessage = "\(label) copied"
            }
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(.easeInOut(duration: 0.25)) {
                copyFeedbackMessage = nil
            }
        }
    }
}

private struct SecurityPromptView: View {
    let onReview: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Sensitive material locked")
                .font(.title3)
                .bold()
            Text("Review and acknowledge the security notice before generating wallet credentials. This helps ensure you understand the handling requirements for the generated keys.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Review Security Notice", action: onReview)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LockedStateView: View {
    let onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.primary)
            Text("Session locked")
                .font(.title3)
                .bold()
            Text("Unlock with your passcode to view or copy any key material. Keys are automatically cleared when the app locks itself.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Unlock", action: onUnlock)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NoKeysPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No key material available")
                .font(.title3)
                .bold()
            Text("Generate a fresh set of keys to review private values.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
}

private struct SecurityNoticeView: View {
    let onAcknowledge: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Handle generated keys securely", systemImage: "lock.shield")
                        .font(.title2)
                        .bold()

                    Text("This tool produces private keys, recovery secrets, and wallet addresses. Treat everything shown in the app as confidential. Anyone with access to these keys can spend the associated funds.")

                    Text("Best practices")
                        .font(.headline)

                    bulletPoint("Never screenshot or share keys in plain text.")
                    bulletPoint("Store backups encrypted and offline whenever possible.")
                    bulletPoint("Clear key material before stepping away from the device.")
                    bulletPoint("Consider using hardware wallets for long-term storage.")

                    Divider()

                    Text("By tapping 'I Understand', you acknowledge the security implications and accept responsibility for safeguarding any generated keys.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Security Notice")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("I Understand") {
                        onAcknowledge()
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 500, height: 600)
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.callout)
            Text(text)
        }
        .font(.body)
    }
}

private struct SecuritySettingsView: View {
    let hasPasscode: Bool
    let onSetPasscode: (String) -> Void
    let onRemovePasscode: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var passcode = ""
    @State private var confirmPasscode = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Session Lock")) {
                    if hasPasscode {
                        Text("A passcode is currently required to unlock key material. You can remove it below or set a new one.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            onRemovePasscode()
                            dismiss()
                        } label: {
                            Label("Remove Passcode", systemImage: "lock.open")
                        }
                    } else {
                        Text("Add a passcode to require unlocking before any key data is shown. This clears keys when the app goes to the background.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(header: Text("Set New Passcode")) {
                    SecureField("New passcode", text: $passcode)
                        .textContentType(.password)
                    SecureField("Confirm passcode", text: $confirmPasscode)
                        .textContentType(.password)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button {
                        validateAndSave()
                    } label: {
                        Label("Save Passcode", systemImage: "lock")
                    }
                    .disabled(passcode.isEmpty || confirmPasscode.isEmpty)
                }
            }
            .navigationTitle("Security Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(width: 400, height: 450)
    }

    private func validateAndSave() {
        let trimmed = passcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else {
            errorMessage = "Choose at least 6 characters."
            return
        }
        guard trimmed == confirmPasscode.trimmingCharacters(in: .whitespacesAndNewlines) else {
            errorMessage = "Passcodes do not match."
            return
        }
        errorMessage = nil
        onSetPasscode(trimmed)
        dismiss()
    }
}

private struct UnlockView: View {
    let onSubmit: (String) -> String?
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var passcode = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Unlock Session")
                    .font(.title3)
                    .bold()
                Text("Enter the passcode you set in Security Settings to reveal the generated key material.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                SecureField("Passcode", text: $passcode)
                    .textContentType(.password)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                HStack {
                    Button("Cancel", role: .cancel) {
                        onCancel()
                        dismiss()
                    }
                    Spacer()
                    Button("Unlock") {
                        let message = onSubmit(passcode)
                        if let message {
                            errorMessage = message
                            passcode = ""
                        } else {
                            errorMessage = nil
                            passcode = ""
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(minWidth: 360, minHeight: 220)
    }
}

private struct PasswordPromptView: View {
    enum Mode {
        case export
        case `import`

        var title: String {
            switch self {
            case .export: return "Encrypt Backup"
            case .import: return "Unlock Backup"
            }
        }

        var actionTitle: String {
            switch self {
            case .export: return "Export"
            case .import: return "Import"
            }
        }

        var description: String {
            switch self {
            case .export:
                return "Choose a strong passphrase. You will need it to restore this backup later."
            case .import:
                return "Enter the passphrase that was used when this backup was created."
            }
        }
    }

    let mode: Mode
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(mode.title)) {
                    Text(mode.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    SecureField("Passphrase", text: $password)
                        .textContentType(.password)

                    if mode == .export {
                        SecureField("Confirm passphrase", text: $confirmation)
                            .textContentType(.password)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.actionTitle) {
                        confirmAction()
                    }
                    .disabled(password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 360, minHeight: mode == .export ? 280 : 240)
    }

    private func confirmAction() {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else {
            errorMessage = "Use at least 8 characters."
            return
        }

        if mode == .export {
            let confirmTrimmed = confirmation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed == confirmTrimmed else {
                errorMessage = "Passphrases do not match."
                return
            }
        }

        errorMessage = nil
        onConfirm(trimmed)
        dismiss()
    }
}

private struct ImportPrivateKeySheet: View {
    let onImport: (String, String) -> Void
    let onCancel: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var privateKeyInput = ""
    @State private var selectedChain = "bitcoin"
    @State private var errorMessage: String?
    
    private let supportedChains = [
        ("bitcoin", "Bitcoin (WIF)", "bc1..."),
        ("bitcoin-testnet", "Bitcoin Testnet (WIF)", "tb1..."),
        ("ethereum", "Ethereum (Hex)", "0x..."),
        ("litecoin", "Litecoin (WIF)", "ltc1..."),
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Import Private Key")) {
                    Text("⚠️ Only import private keys you trust. Never share your private keys with anyone.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    
                    Picker("Chain", selection: $selectedChain) {
                        ForEach(supportedChains, id: \.0) { chain in
                            Text(chain.1).tag(chain.0)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Private Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if let format = supportedChains.first(where: { $0.0 == selectedChain })?.2 {
                            Text("Format: \(format)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        
                        TextEditor(text: $privateKeyInput)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 100)
                            .border(Color.secondary.opacity(0.3))
                    }
                    
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                
                Section {
                    Text("Supported formats:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("• Bitcoin/Litecoin: WIF format (starts with K, L, or 5)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    
                    Text("• Ethereum: 64 hex characters (with or without 0x)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .navigationTitle("Import Private Key")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        importAction()
                    }
                    .disabled(privateKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
    }
    
    private func importAction() {
        let trimmed = privateKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            errorMessage = "Private key cannot be empty"
            return
        }
        
        // Basic validation
        if selectedChain == "bitcoin" || selectedChain == "bitcoin-testnet" || selectedChain == "litecoin" {
            // WIF format validation
            guard trimmed.count >= 51 && trimmed.count <= 52 else {
                errorMessage = "Invalid WIF format. Should be 51-52 characters."
                return
            }
            let firstChar = trimmed.prefix(1)
            guard firstChar == "K" || firstChar == "L" || firstChar == "5" else {
                errorMessage = "Invalid WIF format. Should start with K, L, or 5."
                return
            }
        } else if selectedChain == "ethereum" {
            var hexString = trimmed
            if hexString.hasPrefix("0x") {
                hexString = String(hexString.dropFirst(2))
            }
            guard hexString.count == 64 else {
                errorMessage = "Invalid Ethereum private key. Should be 64 hex characters."
                return
            }
            guard hexString.allSatisfy({ $0.isHexDigit }) else {
                errorMessage = "Invalid hex characters in private key."
                return
            }
        }
        
        errorMessage = nil
        onImport(trimmed, selectedChain)
        dismiss()
    }
}

struct ChainInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let iconName: String
    let accentColor: Color
    let details: [KeyDetail]
    let receiveAddress: String?
}

enum BalanceFetchError: LocalizedError {
    case invalidRequest
    case invalidResponse
    case invalidStatus(Int)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Failed to build balance request."
        case .invalidResponse:
            return "Remote balance service returned an unexpected response."
        case .invalidStatus(let code):
            return "Balance service returned status code \(code)."
        case .invalidPayload:
            return "Balance service returned unexpected data."
        }
    }
}

private struct EthplorerAddressResponse: Decodable {
    let eth: Eth
    let tokens: [TokenBalance]?

    struct Eth: Decodable {
        let balance: Double

        enum CodingKeys: String, CodingKey {
            case balance
        }
    }

    struct TokenBalance: Decodable {
        let tokenInfo: TokenInfo?
        let balance: Double?
        let rawBalance: String?
    }

    struct TokenInfo: Decodable {
        let symbol: String?
        let decimals: String?
        let address: String?
    }

    enum CodingKeys: String, CodingKey {
        case eth = "ETH"
        case tokens
    }
}

private struct XrpScanAccountResponse: Decodable {
    let xrpBalance: String?
    let balance: String?

    enum CodingKeys: String, CodingKey {
        case xrpBalance
        case balance = "Balance"
    }
}

private struct RippleDataAccountBalanceResponse: Decodable {
    struct BalanceEntry: Decodable {
        let currency: String
        let value: String
    }

    let result: String?
    let balances: [BalanceEntry]?
    let message: String?

    var xrpBalanceValue: Decimal? {
        guard let entry = balances?.first(where: { $0.currency.uppercased() == "XRP" }) else {
            return nil
        }
        return Decimal(string: entry.value)
    }

    var isAccountMissing: Bool {
        guard let result else { return false }
        if result.lowercased() == "success" { return false }
        if let message = message?.lowercased(), message.contains("not found") {
            return true
        }
        return false
    }
}

struct KeyDetail: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let value: String
}

private struct EncryptedPackage: Codable {
    let formatVersion: Int
    let createdAt: Date
    let salt: String
    let nonce: String
    let ciphertext: String
    let tag: String
}

private enum SecureArchiveError: LocalizedError {
    case invalidEnvelope

    var errorDescription: String? {
        switch self {
        case .invalidEnvelope:
            return "Encrypted backup file is malformed or corrupted."
        }
    }
}

struct AllKeys: Codable {
    let bitcoin: BitcoinKeys
    let bitcoinTestnet: BitcoinKeys
    let litecoin: LitecoinKeys
    let monero: MoneroKeys
    let solana: SolanaKeys
    let ethereum: EthereumKeys
    let ethereumSepolia: EthereumKeys
    let bnb: BnbKeys
    let xrp: XrpKeys

    private enum CodingKeys: String, CodingKey {
        case bitcoin
        case bitcoinTestnet = "bitcoin_testnet"
        case litecoin
        case monero
        case solana
        case ethereum
        case ethereumSepolia = "ethereum_sepolia"
        case bnb
        case xrp
    }

    var chainInfos: [ChainInfo] {
        var cards: [ChainInfo] = [
            ChainInfo(
                id: "bitcoin",
                title: "Bitcoin",
                subtitle: "SegWit P2WPKH",
                iconName: "bitcoinsign.circle.fill",
                accentColor: Color.orange,
                details: [
                    KeyDetail(label: "Private Key (hex)", value: bitcoin.privateHex),
                    KeyDetail(label: "Private Key (WIF)", value: bitcoin.privateWif),
                    KeyDetail(label: "Public Key (compressed hex)", value: bitcoin.publicCompressedHex),
                    KeyDetail(label: "Address", value: bitcoin.address)
                ],
                receiveAddress: bitcoin.address
            ),
            ChainInfo(
                id: "bitcoin-testnet",
                title: "Bitcoin Testnet",
                subtitle: "SegWit Testnet",
                iconName: "bitcoinsign.circle",
                accentColor: Color.orange.opacity(0.7),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: bitcoinTestnet.privateHex),
                    KeyDetail(label: "Private Key (WIF)", value: bitcoinTestnet.privateWif),
                    KeyDetail(label: "Public Key (compressed hex)", value: bitcoinTestnet.publicCompressedHex),
                    KeyDetail(label: "Testnet Address", value: bitcoinTestnet.address)
                ],
                receiveAddress: bitcoinTestnet.address
            ),
            ChainInfo(
                id: "litecoin",
                title: "Litecoin",
                subtitle: "Bech32 P2WPKH",
                iconName: "l.circle.fill",
                accentColor: Color.green,
                details: [
                    KeyDetail(label: "Private Key (hex)", value: litecoin.privateHex),
                    KeyDetail(label: "Private Key (WIF)", value: litecoin.privateWif),
                    KeyDetail(label: "Public Key (compressed hex)", value: litecoin.publicCompressedHex),
                    KeyDetail(label: "Address", value: litecoin.address)
                ],
                receiveAddress: litecoin.address
            ),
            ChainInfo(
                id: "monero",
                title: "Monero",
                subtitle: "Primary Account",
                iconName: "m.circle.fill",
                accentColor: Color.purple,
                details: [
                    KeyDetail(label: "Private Spend Key", value: monero.privateSpendHex),
                    KeyDetail(label: "Private View Key", value: monero.privateViewHex),
                    KeyDetail(label: "Public Spend Key", value: monero.publicSpendHex),
                    KeyDetail(label: "Public View Key", value: monero.publicViewHex),
                    KeyDetail(label: "Primary Address", value: monero.address)
                ],
                receiveAddress: monero.address
            ),
            ChainInfo(
                id: "solana",
                title: "Solana",
                subtitle: "Ed25519 Keypair",
                iconName: "s.circle.fill",
                accentColor: Color.blue,
                details: [
                    KeyDetail(label: "Private Seed (hex)", value: solana.privateSeedHex),
                    KeyDetail(label: "Private Key (base58)", value: solana.privateKeyBase58),
                    KeyDetail(label: "Public Key / Address", value: solana.publicKeyBase58)
                ],
                receiveAddress: solana.publicKeyBase58
            ),
            ChainInfo(
                id: "xrp",
                title: "XRP Ledger",
                subtitle: "Classic Address",
                iconName: "xmark.seal.fill",
                accentColor: Color.indigo,
                details: [
                    KeyDetail(label: "Private Key (hex)", value: xrp.privateHex),
                    KeyDetail(label: "Public Key (compressed hex)", value: xrp.publicCompressedHex),
                    KeyDetail(label: "Classic Address", value: xrp.classicAddress)
                ],
                receiveAddress: xrp.classicAddress
            )
        ]

        let ethereumDetails = [
            KeyDetail(label: "Private Key (hex)", value: ethereum.privateHex),
            KeyDetail(label: "Public Key (uncompressed hex)", value: ethereum.publicUncompressedHex),
            KeyDetail(label: "Checksummed Address", value: ethereum.address)
        ]

        cards.append(
            ChainInfo(
                id: "ethereum",
                title: "Ethereum",
                subtitle: "EIP-55 Address",
                iconName: "e.circle.fill",
                accentColor: Color.pink,
                details: ethereumDetails,
                receiveAddress: ethereum.address
            )
        )

        cards.append(
            ChainInfo(
                id: "ethereum-sepolia",
                title: "Ethereum Sepolia",
                subtitle: "Testnet Address",
                iconName: "e.circle",
                accentColor: Color.pink.opacity(0.7),
                details: [
                    KeyDetail(label: "Private Key (hex)", value: ethereumSepolia.privateHex),
                    KeyDetail(label: "Public Key (uncompressed hex)", value: ethereumSepolia.publicUncompressedHex),
                    KeyDetail(label: "Checksummed Address", value: ethereumSepolia.address)
                ],
                receiveAddress: ethereumSepolia.address
            )
        )

        let bnbDetails = [
            KeyDetail(label: "Private Key (hex)", value: bnb.privateHex),
            KeyDetail(label: "Public Key (uncompressed hex)", value: bnb.publicUncompressedHex),
            KeyDetail(label: "Checksummed Address", value: bnb.address)
        ]

        cards.append(
            ChainInfo(
                id: "bnb",
                title: "BNB Smart Chain",
                subtitle: "EVM Compatible",
                iconName: "b.circle.fill",
                accentColor: Color(red: 0.95, green: 0.77, blue: 0.23),
                details: bnbDetails,
                receiveAddress: bnb.address
            )
        )

        let tokenEntries: [(idPrefix: String, title: String, subtitle: String, accent: Color, contract: String)] = [
            ("usdt", "Tether USD (USDT)", "ERC-20 Token", Color(red: 0.0, green: 0.64, blue: 0.54), "0xdAC17F958D2ee523a2206206994597C13D831ec7"),
            ("usdc", "USD Coin (USDC)", "ERC-20 Token", Color.blue, "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"),
            ("dai", "Dai (DAI)", "ERC-20 Token", Color.yellow, "0x6B175474E89094C44Da98b954EedeAC495271d0F")
        ]

        for entry in tokenEntries {
            let tokenDetails: [KeyDetail] = [
                KeyDetail(label: "Ethereum Wallet Address", value: ethereum.address),
                KeyDetail(label: "Token Contract", value: entry.contract)
            ]

            cards.append(
                ChainInfo(
                    id: "\(entry.idPrefix)-erc20",
                    title: entry.title,
                    subtitle: entry.subtitle,
                    iconName: "dollarsign.circle.fill",
                    accentColor: entry.accent,
                    details: tokenDetails,
                    receiveAddress: ethereum.address
                )
            )
        }

        return cards
    }
}

struct BitcoinKeys: Codable {
    let privateHex: String
    let privateWif: String
    let publicCompressedHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case privateWif = "private_wif"
        case publicCompressedHex = "public_compressed_hex"
        case address
    }
}

struct LitecoinKeys: Codable {
    let privateHex: String
    let privateWif: String
    let publicCompressedHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case privateWif = "private_wif"
        case publicCompressedHex = "public_compressed_hex"
        case address
    }
}

struct MoneroKeys: Codable {
    let privateSpendHex: String
    let privateViewHex: String
    let publicSpendHex: String
    let publicViewHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateSpendHex = "private_spend_hex"
        case privateViewHex = "private_view_hex"
        case publicSpendHex = "public_spend_hex"
        case publicViewHex = "public_view_hex"
        case address
    }
}

struct SolanaKeys: Codable {
    let privateSeedHex: String
    let privateKeyBase58: String
    let publicKeyBase58: String

    private enum CodingKeys: String, CodingKey {
        case privateSeedHex = "private_seed_hex"
        case privateKeyBase58 = "private_key_base58"
        case publicKeyBase58 = "public_key_base58"
    }
}

struct EthereumKeys: Codable {
    let privateHex: String
    let publicUncompressedHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicUncompressedHex = "public_uncompressed_hex"
        case address
    }
}

struct BnbKeys: Codable {
    let privateHex: String
    let publicUncompressedHex: String
    let address: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicUncompressedHex = "public_uncompressed_hex"
        case address
    }
}

struct XrpKeys: Codable {
    let privateHex: String
    let publicCompressedHex: String
    let classicAddress: String

    private enum CodingKeys: String, CodingKey {
        case privateHex = "private_hex"
        case publicCompressedHex = "public_compressed_hex"
        case classicAddress = "classic_address"
    }
}

// MARK: - Keychain Storage
private struct KeychainHelper {
    static let keysIdentifier = "com.hawala.wallet.keys"
    
    static func saveKeys(_ keys: AllKeys) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(keys)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keysIdentifier,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    static func loadKeys() throws -> AllKeys? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keysIdentifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.loadFailed(status)
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(AllKeys.self, from: data)
    }
    
    static func deleteKeys() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keysIdentifier
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save keys to Keychain (status: \(status))"
        case .loadFailed(let status):
            return "Failed to load keys from Keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete keys from Keychain (status: \(status))"
        }
    }
}

enum KeyGeneratorError: LocalizedError {
    case executionFailed(String)
    case cargoNotFound

    var errorDescription: String? {
        switch self {
        case .executionFailed(let message):
            return message
        case .cargoNotFound:
            return "Unable to locate the cargo executable. Install Rust via https://rustup.rs or set the CARGO_BIN environment variable to the cargo path."
        }
    }
}

#Preview {
    ContentView()
}
