import SwiftUI
import CryptoKit
import UniformTypeIdentifiers
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

fileprivate enum ChainBalanceState: Equatable {
    case idle
    case loading
    case loaded(String)
    case failed(String)
}

fileprivate enum ChainPriceState: Equatable {
    case idle
    case loading
    case loaded(String)
    case failed(String)
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
    @State private var priceUpdateTask: Task<Void, Never>?
    @State private var showAllPrivateKeysSheet = false
    @State private var showSettingsPanel = false
    @State private var showReceiveSheet = false
    @State private var showSendSheet = false
    @State private var sendChainContext: ChainInfo?
    private let moneroBalancePlaceholder = "Balance protected – open your Monero wallet"
    private static var cachedWorkspaceRoot: URL?

    @Environment(\.scenePhase) private var scenePhase

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]

    private var canAccessSensitiveData: Bool {
        storedPasscodeHash == nil || isUnlocked
    }

    var body: some View {
        Group {
            if onboardingCompleted {
                mainAppStage
            } else {
                onboardingFlow
            }
        }
        .animation(.easeInOut(duration: 0.3), value: onboardingCompleted)
        .animation(.easeInOut(duration: 0.3), value: onboardingStep)
        .onAppear {
            guard !hasResetOnboardingState else { return }
            onboardingCompleted = false
            onboardingStep = .welcome
            shouldAutoGenerateAfterOnboarding = false
            balanceStates.removeAll()
            priceStates.removeAll()
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
        .sheet(item: $selectedChain) { chain in
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
                    self.selectedChain = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        sendChainContext = selectedChain
                        showSendSheet = true
                    }
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
        .sheet(isPresented: $showSendSheet) {
            if let chain = sendChainContext, let keys {
                BitcoinSendSheet(
                    chain: chain,
                    keys: keys,
                    onDismiss: {
                        showSendSheet = false
                        sendChainContext = nil
                    },
                    onSuccess: { txid in
                        showSendSheet = false
                        sendChainContext = nil
                        showStatus("Transaction broadcast: \(txid.prefix(16))...", tone: .success)
                    }
                )
            }
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
                        
                        LazyVGrid(columns: columns, spacing: 14) {
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
                            }
                        }
                    }

                    transactionHistorySection
                }
                .padding(.top, 12)
                .padding(.bottom, 20)
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
            
            Text("Live estimate • Updates every 60s")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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

    private var totalBalanceDisplay: String {
        let result = calculatePortfolioTotal()
        guard let total = result.total, result.hasData else {
            return "—"
        }
        return formatFiatAmount(total, currencyCode: "USD")
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

    private func extractNumericAmount(from state: ChainBalanceState) -> Double? {
        guard case .loaded(let value) = state else { return nil }
        let raw = value.split(separator: " ").first.map(String.init) ?? value
        let cleaned = raw.replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
    }

    private func extractFiatPrice(from state: ChainPriceState) -> Double? {
        guard case .loaded(let value) = state else { return nil }
        let filtered = value.filter { "0123456789.,-".contains($0) }
        guard !filtered.isEmpty else { return nil }
        let normalized = filtered.replacingOccurrences(of: ",", with: "")
        return Double(normalized)
    }

    private var actionButtonsRow: some View {
        HStack(spacing: 10) {
            walletActionButton(
                title: "Send",
                systemImage: "paperplane.fill",
                color: .orange
            ) {
                // Auto-generate keys if they don't exist (instant, no UI blocking)
                if keys == nil {
                    Task {
                        // Generate keys silently in background
                        await runGenerator()
                        // Once keys are ready, open send sheet immediately
                        await MainActor.run {
                            openSendSheet()
                        }
                    }
                } else {
                    // Keys already exist, open immediately
                    openSendSheet()
                }
            }

            walletActionButton(
                title: "Receive",
                systemImage: "arrow.down.circle.fill",
                color: .green,
                prominent: true
            ) {
                guard keys != nil else {
                    showStatus("Generate keys to reveal receive addresses.", tone: .info)
                    return
                }
                showReceiveSheet = true
            }

            walletActionButton(
                title: "Swap",
                systemImage: "arrow.left.arrow.right.circle.fill",
                color: .blue
            ) {
                showStatus("Swap integrations are on the roadmap.", tone: .info)
            }

            walletActionButton(
                title: "Stake",
                systemImage: "chart.bar.fill",
                color: .purple
            ) {
                showStatus("Staking will unlock in a future release.", tone: .info)
            }
        }
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
            showStatus("Keys are being generated...", tone: .info)
            return
        }
        // Show Bitcoin mainnet by default
        let bitcoinChains = keys.chainInfos.filter { $0.id.starts(with: "bitcoin") }
        if let btcChain = bitcoinChains.first {
            sendChainContext = btcChain
            showSendSheet = true
        } else {
            showStatus("Bitcoin wallet not found.", tone: .error)
        }
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

    private func resolveCargoExecutable() throws -> String {
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

    private func candidateCargoPaths() -> [String] {
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

    private func locateCargoWithWhich() throws -> String? {
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

    private func mergedEnvironment(forCargoExecutableAt path: String) -> [String: String] {
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
        let cargoPath = try resolveCargoExecutable()

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
            process.environment = mergedEnvironment(forCargoExecutableAt: cargoPath)

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
        statusTask?.cancel()
        statusTask = nil
        statusMessage = nil
        pendingImportData = nil
        balanceStates.removeAll()
        priceStates.removeAll()
        
        // Delete from Keychain
        do {
            try KeychainHelper.deleteKeys()
            print("✅ Keys deleted from Keychain")
        } catch {
            print("⚠️ Failed to delete keys from Keychain: \(error)")
        }
    }

    private func prepareSecurityState() {
        if !hasAcknowledgedSecurityNotice {
            showSecurityNotice = true
        }

        if storedPasscodeHash != nil {
            if completedOnboardingThisSession {
                isUnlocked = true
                showUnlockSheet = false
                completedOnboardingThisSession = false
            } else {
                isUnlocked = false
                showUnlockSheet = true
            }
        } else {
            isUnlocked = true
        }
    }

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
        if let keys {
            primeStateCaches(for: keys)
        }
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
    }

    @MainActor
    private func markPriceStatesLoading() {
        let stableDisplay = formatFiatAmount(1.0, currencyCode: "USD")
        let ids = [
            "bitcoin", "bitcoin-testnet", "ethereum", "ethereum-sepolia", "litecoin", "monero",
            "solana", "xrp", "bnb",
            "usdt-erc20", "usdc-erc20", "dai-erc20"
        ]

        let fixedDisplays: [String: String] = [
            "usdt-erc20": stableDisplay,
            "usdc-erc20": stableDisplay,
            "dai-erc20": stableDisplay,
            "bitcoin-testnet": "Testnet asset",
            "ethereum-sepolia": "Testnet asset"
        ]

        for id in ids {
            if let value = fixedDisplays[id] {
                priceStates[id] = .loaded(value)
            } else {
                priceStates[id] = .loading
            }
        }
    }

    private func priceUpdateLoop() async {
        await fetchAndStorePrices()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 23_000_000_000)
            if Task.isCancelled { break }
            await fetchAndStorePrices()
        }
    }

    private func fetchAndStorePrices() async {
        do {
            let snapshot = try await fetchPriceSnapshot()
            await MainActor.run {
                if let btc = snapshot["bitcoin"] {
                    priceStates["bitcoin"] = .loaded(formatFiatAmount(btc, currencyCode: "USD"))
                } else {
                    priceStates["bitcoin"] = .failed("Missing BTC price data.")
                }

                if let eth = snapshot["ethereum"] {
                    priceStates["ethereum"] = .loaded(formatFiatAmount(eth, currencyCode: "USD"))
                } else {
                    priceStates["ethereum"] = .failed("Missing ETH price data.")
                }

                if let ltc = snapshot["litecoin"] {
                    priceStates["litecoin"] = .loaded(formatFiatAmount(ltc, currencyCode: "USD"))
                } else {
                    priceStates["litecoin"] = .failed("Missing LTC price data.")
                }

                if let xmr = snapshot["monero"] {
                    priceStates["monero"] = .loaded(formatFiatAmount(xmr, currencyCode: "USD"))
                } else {
                    priceStates["monero"] = .failed("Missing XMR price data.")
                }

                if let sol = snapshot["solana"] {
                    priceStates["solana"] = .loaded(formatFiatAmount(sol, currencyCode: "USD"))
                } else {
                    priceStates["solana"] = .failed("Missing SOL price data.")
                }

                if let xrp = snapshot["ripple"] ?? snapshot["xrp"] {
                    priceStates["xrp"] = .loaded(formatFiatAmount(xrp, currencyCode: "USD"))
                } else {
                    priceStates["xrp"] = .failed("Missing XRP price data.")
                }

                if let bnb = snapshot["binancecoin"] ?? snapshot["bnb"] {
                    priceStates["bnb"] = .loaded(formatFiatAmount(bnb, currencyCode: "USD"))
                } else {
                    priceStates["bnb"] = .failed("Missing BNB price data.")
                }

                let stableDisplay = formatFiatAmount(1.0, currencyCode: "USD")
                priceStates["usdt-erc20"] = .loaded(stableDisplay)
                priceStates["usdc-erc20"] = .loaded(stableDisplay)
                priceStates["dai-erc20"] = .loaded(stableDisplay)
                priceStates["bitcoin-testnet"] = .loaded("Testnet asset")
                priceStates["ethereum-sepolia"] = .loaded("Testnet asset")
            }
        } catch {
            let message = error.localizedDescription
            await MainActor.run {
                priceStates["bitcoin"] = .failed(message)
                priceStates["ethereum"] = .failed(message)
                priceStates["litecoin"] = .failed(message)
                priceStates["monero"] = .failed(message)
                priceStates["solana"] = .failed(message)
                priceStates["xrp"] = .failed(message)
                priceStates["bnb"] = .failed(message)
                priceStates["usdt-erc20"] = .failed(message)
                priceStates["usdc-erc20"] = .failed(message)
                priceStates["dai-erc20"] = .failed(message)
                priceStates["bitcoin-testnet"] = .loaded("Testnet asset")
                priceStates["ethereum-sepolia"] = .loaded("Testnet asset")
            }
        }
    }

    private func fetchPriceSnapshot() async throws -> [String: Double] {
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,litecoin,monero,solana,ripple,binancecoin,tether,usd-coin,dai&vs_currencies=usd") else {
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
        guard let dict = object as? [String: Any] else {
            throw BalanceFetchError.invalidPayload
        }

        var prices: [String: Double] = [:]
        if let btc = dict["bitcoin"] as? [String: Any], let usd = btc["usd"] as? NSNumber {
            prices["bitcoin"] = usd.doubleValue
        }
        if let eth = dict["ethereum"] as? [String: Any], let usd = eth["usd"] as? NSNumber {
            prices["ethereum"] = usd.doubleValue
        }
        if let ltc = dict["litecoin"] as? [String: Any], let usd = ltc["usd"] as? NSNumber {
            prices["litecoin"] = usd.doubleValue
        }
        if let xmr = dict["monero"] as? [String: Any], let usd = xmr["usd"] as? NSNumber {
            prices["monero"] = usd.doubleValue
        }
        if let sol = dict["solana"] as? [String: Any], let usd = sol["usd"] as? NSNumber {
            prices["solana"] = usd.doubleValue
        }
        if let xrp = dict["ripple"] as? [String: Any], let usd = xrp["usd"] as? NSNumber {
            prices["ripple"] = usd.doubleValue
        }
        if let bnb = dict["binancecoin"] as? [String: Any], let usd = bnb["usd"] as? NSNumber {
            prices["binancecoin"] = usd.doubleValue
        }
        if let usdt = dict["tether"] as? [String: Any], let usd = usdt["usd"] as? NSNumber {
            prices["tether"] = usd.doubleValue
        }
        if let usdc = dict["usd-coin"] as? [String: Any], let usd = usdc["usd"] as? NSNumber {
            prices["usd-coin"] = usd.doubleValue
        }
        if let dai = dict["dai"] as? [String: Any], let usd = dai["usd"] as? NSNumber {
            prices["dai"] = usd.doubleValue
        }

        return prices
    }

    @MainActor
    private func startBalanceFetch(for keys: AllKeys) {
        enqueueBalanceFetch(for: "bitcoin") {
            try await fetchBitcoinBalance(address: keys.bitcoin.address)
        }
        enqueueBalanceFetch(for: "bitcoin-testnet") {
            try await fetchBitcoinBalance(address: keys.bitcoinTestnet.address, isTestnet: true)
        }
        enqueueBalanceFetch(for: "litecoin") {
            try await fetchLitecoinBalance(address: keys.litecoin.address)
        }
        enqueueBalanceFetch(for: "solana") {
            try await fetchSolanaBalance(address: keys.solana.publicKeyBase58)
        }
        enqueueBalanceFetch(for: "xrp") {
            try await fetchXrpBalance(address: keys.xrp.classicAddress)
        }
        enqueueBalanceFetch(for: "bnb") {
            try await fetchBnbBalance(address: keys.bnb.address)
        }
    startEthereumAndTokenBalanceFetch(address: keys.ethereum.address)
    }

    @MainActor
    private func enqueueBalanceFetch(for chainId: String, fetcher: @escaping () async throws -> String) {
        balanceStates[chainId] = .loading

        Task {
            do {
                let displayValue = try await fetcher()
                await MainActor.run {
                    balanceStates[chainId] = .loaded(displayValue)
                }
            } catch {
                await MainActor.run {
                    balanceStates[chainId] = .failed(error.localizedDescription)
                }
            }
        }
    }

    @MainActor
    private func startEthereumAndTokenBalanceFetch(address: String) {
        balanceStates["ethereum"] = .loading
        balanceStates["usdt-erc20"] = .loading
        balanceStates["usdc-erc20"] = .loading
        balanceStates["dai-erc20"] = .loading

        // Fetch ETH balance
        Task {
            do {
                let ethBalance = try await fetchEthereumBalanceViaInfura(address: address)
                await MainActor.run {
                    balanceStates["ethereum"] = .loaded(ethBalance)
                }
            } catch {
                await MainActor.run {
                    balanceStates["ethereum"] = .failed(error.localizedDescription)
                }
            }
        }

        // Fetch USDT balance
        Task {
            do {
                let usdtBalance = try await fetchERC20Balance(
                    address: address,
                    contractAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
                    decimals: 6,
                    symbol: "USDT"
                )
                await MainActor.run {
                    balanceStates["usdt-erc20"] = .loaded(usdtBalance)
                }
            } catch {
                await MainActor.run {
                    balanceStates["usdt-erc20"] = .loaded("0 USDT")
                }
            }
        }

        // Fetch USDC balance
        Task {
            do {
                let usdcBalance = try await fetchERC20Balance(
                    address: address,
                    contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
                    decimals: 6,
                    symbol: "USDC"
                )
                await MainActor.run {
                    balanceStates["usdc-erc20"] = .loaded(usdcBalance)
                }
            } catch {
                await MainActor.run {
                    balanceStates["usdc-erc20"] = .loaded("0 USDC")
                }
            }
        }

        // Fetch DAI balance
        Task {
            do {
                let daiBalance = try await fetchERC20Balance(
                    address: address,
                    contractAddress: "0x6B175474E89094C44Da98b954EedeAC495271d0F",
                    decimals: 18,
                    symbol: "DAI"
                )
                await MainActor.run {
                    balanceStates["dai-erc20"] = .loaded(daiBalance)
                }
            } catch {
                await MainActor.run {
                    balanceStates["dai-erc20"] = .loaded("0 DAI")
                }
            }
        }
    }

    @MainActor
    private func ensurePriceStateEntries() {
        let ids = [
            "bitcoin", "bitcoin-testnet", "ethereum", "ethereum-sepolia", "litecoin", "monero",
            "solana", "xrp", "bnb",
            "usdt-erc20", "usdc-erc20", "dai-erc20"
        ]
        for id in ids {
            priceStates[id] = defaultPriceState(for: id)
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
            return .loaded("Use Sepolia faucet for funds")
        case "monero":
            return .loaded(moneroBalancePlaceholder)
        default:
            return .loading
        }
    }

    @MainActor
    private func defaultPriceState(for chainID: String) -> ChainPriceState {
        let stableDisplay = formatFiatAmount(1.0, currencyCode: "USD")
        switch chainID {
        case "usdt-erc20", "usdc-erc20", "dai-erc20":
            return .loaded(stableDisplay)
        case "bitcoin-testnet", "ethereum-sepolia":
            return .loaded("Testnet asset")
        default:
            return .loading
        }
    }

    private func fetchBitcoinBalance(address: String, isTestnet: Bool = false) async throws -> String {
        let baseURL = isTestnet ? "https://mempool.space/testnet/api" : "https://mempool.space/api"
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: "\(baseURL)/address/\(encodedAddress)") else {
            throw BalanceFetchError.invalidRequest
        }

        print("🔍 Fetching balance for \(isTestnet ? "TESTNET" : "MAINNET") address: \(address)")
        print("🔍 URL: \(url)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BalanceFetchError.invalidResponse
        }

        print("🔍 HTTP Status: \(httpResponse.statusCode)")

        let symbol = isTestnet ? "tBTC" : "BTC"
        
        if httpResponse.statusCode == 404 {
            print("⚠️ Address not found (404), returning 0")
            return formatCryptoAmount(0.0, symbol: symbol, maxFractionDigits: 8)
        }

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = jsonObject as? [String: Any],
              let chainStats = dictionary["chain_stats"] as? [String: Any] else {
            print("❌ Failed to parse chain_stats")
            throw BalanceFetchError.invalidPayload
        }

        let funded = (chainStats["funded_txo_sum"] as? NSNumber)?.doubleValue ?? 0
        let spent = (chainStats["spent_txo_sum"] as? NSNumber)?.doubleValue ?? 0
        let balanceInSats = max(0, funded - spent)
        let btc = balanceInSats / 100_000_000.0
        
        print("✅ Funded: \(funded) sats, Spent: \(spent) sats")
        print("✅ Balance: \(balanceInSats) sats = \(btc) \(symbol)")
        
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

    private func fetchXrpBalance(address: String) async throws -> String {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://data.ripple.com/v2/accounts/\(encodedAddress)/balances?currency=XRP") else {
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
            if httpResponse.statusCode == 404 {
                return formatCryptoAmount(0, symbol: "XRP", maxFractionDigits: 6)
            }
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = jsonObject as? [String: Any],
              let balances = dictionary["balances"] as? [[String: Any]] else {
            throw BalanceFetchError.invalidPayload
        }

        let xrpBalance = balances.first { ($0["currency"] as? String)?.uppercased() == "XRP" }
        let valueString = xrpBalance?["value"] as? String ?? "0"
        let value = Double(valueString) ?? 0
        return formatCryptoAmount(value, symbol: "XRP", maxFractionDigits: 6)
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
        guard let url = URL(string: "https://ethereum.publicnode.com") else {
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
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidResponse
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = jsonObject as? [String: Any],
              let result = dictionary["result"] as? String else {
            throw BalanceFetchError.invalidPayload
        }

        let weiDecimal = decimalFromHex(result)
        let divisor = Decimal(string: "1000000000000000000") ?? Decimal(1_000_000_000_000_000_000)
        let ethDecimal = weiDecimal / divisor
        let eth = NSDecimalNumber(decimal: ethDecimal).doubleValue
        let formatted = formatCryptoAmount(eth, symbol: "ETH", maxFractionDigits: 6)
        return formatted
    }

    private func fetchERC20Balance(address: String, contractAddress: String, decimals: Int, symbol: String) async throws -> String {
        guard let url = URL(string: "https://ethereum.publicnode.com") else {
            throw BalanceFetchError.invalidRequest
        }

        // ERC-20 balanceOf function signature: 0x70a08231 + 32-byte address parameter
        let normalizedAddress = normalizeAddressForCall(address)
        let data = "0x70a08231" + normalizedAddress

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "eth_call",
            "params": [
                [
                    "to": contractAddress,
                    "data": data
                ],
                "latest"
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidResponse
        }

                        let jsonObject = try JSONSerialization.jsonObject(with: responseData, options: [])
                        guard let dictionary = jsonObject as? [String: Any],
                                    let result = dictionary["result"] as? String else {
                                throw BalanceFetchError.invalidPayload
                        }

                        let rawBalance = decimalFromHex(result)
                        let divisor = Decimal(sign: .plus, exponent: decimals, significand: 1)
                        let tokenDecimal = rawBalance / divisor
                        let tokenAmount = NSDecimalNumber(decimal: tokenDecimal).doubleValue

                        return formatCryptoAmount(tokenAmount, symbol: symbol, maxFractionDigits: min(6, decimals))
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

// MARK: - Bitcoin Send Sheet

private struct BitcoinSendSheet: View {
    let chain: ChainInfo
    let keys: AllKeys
    let onDismiss: () -> Void
    let onSuccess: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var recipientAddress = ""
    @State private var amountBTC = ""
    @State private var selectedFeeRate: FeeRate = .medium
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
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Recipient") {
                    TextField("Bitcoin address", text: $recipientAddress)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                }
                
                Section("Amount") {
                    HStack {
                        TextField("0.00000000", text: $amountBTC)
                        Text("BTC")
                            .foregroundStyle(.secondary)
                    }
                    
                    if availableBalance > 0 {
                        HStack {
                            Text("Available:")
                            Spacer()
                            Text(formatSatoshis(availableBalance))
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        
                        Button("Send Max") {
                            sendMax()
                        }
                        .font(.caption)
                    }
                }
                
                Section("Transaction Fee") {
                    Picker("Speed", selection: $selectedFeeRate) {
                        ForEach(FeeRate.allCases, id: \.self) { rate in
                            Text(rate.rawValue).tag(rate)
                        }
                    }
                    .onChange(of: selectedFeeRate) { _ in
                        updateFeeEstimate()
                    }
                    
                    if let estimates = feeEstimates {
                        HStack {
                            Text("Fee Rate:")
                            Spacer()
                            Text("\(feeRateForSelection(estimates)) sat/vB")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                    
                    if estimatedFee > 0 {
                        HStack {
                            Text("Estimated Fee:")
                            Spacer()
                            Text(formatSatoshis(estimatedFee))
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                
                Section {
                    Button {
                        Task {
                            await sendTransaction()
                        }
                    } label: {
                        if isLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Sending...")
                            }
                        } else {
                            Text("Review & Send")
                        }
                    }
                    .disabled(isLoading || !isValidForm)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Send \(chain.title)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onDismiss()
                    }
                }
            }
            .onAppear {
                Task {
                    await loadBalanceAndFees()
                }
            }
        }
        .frame(minWidth: 480, minHeight: 520)
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
        defer { isLoading = false }
        
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
            
            // Convert UTXOs to the format expected by BitcoinTransaction
            let utxoList = confirmedUTXOs.map { utxo in
                (txid: utxo.txid, vout: UInt32(utxo.vout), value: UInt64(utxo.value), scriptPubKey: utxo.scriptpubkey)
            }
            
            // Get fee rate from estimates
            let feeRateValue: UInt64
            if let estimates = feeEstimates {
                switch selectedFeeRate {
                case .fast:
                    feeRateValue = UInt64(estimates.fastestFee)
                case .medium:
                    feeRateValue = UInt64(estimates.halfHourFee)
                case .slow:
                    feeRateValue = UInt64(estimates.hourFee)
                case .economy:
                    feeRateValue = UInt64(estimates.economyFee)
                }
            } else {
                feeRateValue = 10 // Default fallback
            }
            
            // Build and sign transaction
            let rawTxHex = try BitcoinTransaction.buildAndSign(
                from: utxoList,
                to: recipient,
                amount: UInt64(satoshis),
                feeRate: feeRateValue,
                changeAddress: address,
                privateKeyWIF: privateWIF
            )
            
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
        .frame(minWidth: 520, minHeight: 460)
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

    private var balanceLabel: String {
        switch balanceState {
        case .idle:
            return "—"
        case .loading:
            return "Loading…"
        case .loaded(let value):
            return value
        case .failed:
            return "Unavailable"
        }
    }

    private var priceLabel: String {
        switch priceState {
        case .idle:
            return "—"
        case .loading:
            return "Loading…"
        case .loaded(let value):
            return value
        case .failed:
            return "Unavailable"
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
                        Text(balanceLabel)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("Price")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                        Text(priceLabel)
                            .font(.caption)
                            .fontWeight(.medium)
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
            .frame(minWidth: 320, minHeight: 200)
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
        .frame(minWidth: 520, minHeight: 560)
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
        .frame(minWidth: 420, minHeight: 520)
    }
    
    @ViewBuilder
    private var quickActionsSection: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
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
                            onCopy(address)
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
            case .loaded(let value):
                Text(value)
                    .font(.headline)
                    .foregroundStyle(chain.accentColor)
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
            case .loaded(let value):
                Text(value)
                    .font(.headline)
                    .foregroundStyle(chain.accentColor)
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
        .frame(minWidth: 420, minHeight: 520)
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
        .frame(minWidth: 360, minHeight: 360)
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

private enum BalanceFetchError: LocalizedError {
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
