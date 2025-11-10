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
    @State private var onboardingStep: OnboardingStep = .welcome
    @State private var completedOnboardingThisSession = false
    @State private var shouldAutoGenerateAfterOnboarding = false
    @State private var hasResetOnboardingState = false
    @State private var balanceStates: [String: ChainBalanceState] = [:]

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
            hasResetOnboardingState = true
        }
    }

    private var mainAppStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Multi-Chain Key Generator")
                .font(.largeTitle)
                .bold()

            Text("Generate production-ready key material for Bitcoin, Litecoin, Monero, Solana, Ethereum, BNB, XRP, and popular ERC-20 tokens. Tap a card to inspect and copy individual keys.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button {
                    showSecuritySettings = true
                } label: {
                    Label("Security Settings", systemImage: "lock.shield")
                }
                .buttonStyle(.bordered)
            }

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
            let balanceState = balanceStates[chain.id] ?? .idle
            ChainDetailSheet(chain: chain, balanceState: balanceState) { value in
                copyToClipboard(value)
            }
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
        .onAppear {
            prepareSecurityState()
            triggerAutoGenerationIfNeeded()
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
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(keys.chainInfos) { chain in
                        Button {
                            guard canAccessSensitiveData else {
                                showUnlockSheet = true
                                return
                            }
                            selectedChain = chain
                        } label: {
                            ChainCard(chain: chain, balanceState: balanceStates[chain.id] ?? .idle)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
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
                keys = result
                rawJSON = jsonString
                isGenerating = false
                startBalanceFetch(for: result)
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

    private func finalizeEncryptedImport(with password: String) {
        guard let archiveData = pendingImportData else {
            showStatus("No backup selected.", tone: .error)
            return
        }

        do {
            let plaintext = try decryptArchive(archiveData, password: password)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let importedKeys = try decoder.decode(AllKeys.self, from: plaintext)
            keys = importedKeys
            rawJSON = prettyPrintedJSON(from: plaintext)
            pendingImportData = nil
            showStatus("Encrypted backup imported.", tone: .success)
        } catch {
            showStatus("Import failed: \(error.localizedDescription)", tone: .error, autoClear: false)
        }
    }

    private func buildEncryptedArchive(from keys: AllKeys, password: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
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
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let decoded = try decoder.decode(AllKeys.self, from: jsonData)
                    continuation.resume(returning: (decoded, outputString))
                } catch {
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

    private func clearSensitiveData() {
        keys = nil
        rawJSON = ""
        selectedChain = nil
        statusTask?.cancel()
        statusTask = nil
        statusMessage = nil
        pendingImportData = nil
        balanceStates.removeAll()
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
    private func startBalanceFetch(for keys: AllKeys) {
        balanceStates.removeAll()
        enqueueBalanceFetch(for: "bitcoin") {
            try await fetchBitcoinBalance(address: keys.bitcoin.address)
        }
        enqueueBalanceFetch(for: "ethereum") {
            try await fetchEthereumBalance(address: keys.ethereum.address)
        }
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

    private func fetchBitcoinBalance(address: String) async throws -> String {
      guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
          let url = URL(string: "https://mempool.space/api/address/\(encodedAddress)") else {
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
            return "0.00000000 BTC"
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
        return formatCryptoAmount(btc, symbol: "BTC", maxFractionDigits: 8)
    }

    private func fetchEthereumBalance(address: String) async throws -> String {
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

        guard httpResponse.statusCode == 200 else {
            throw BalanceFetchError.invalidStatus(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let payload = try decoder.decode(EthplorerAddressResponse.self, from: data)
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

    private func handlePasscodeChange() {
        if storedPasscodeHash != nil {
            lock()
        } else {
            isUnlocked = true
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if storedPasscodeHash != nil && !isUnlocked {
                showUnlockSheet = true
            }
        case .inactive, .background:
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
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent() // ContentView.swift
        url.deleteLastPathComponent() // Sources
        url.deleteLastPathComponent() // swift-app
        return url // workspace root
    }

    private var manifestPath: String {
        workspaceRoot
            .appendingPathComponent("rust-app")
            .appendingPathComponent("Cargo.toml")
            .path
    }
}

private struct ChainCard: View {
    let chain: ChainInfo
    let balanceState: ChainBalanceState

    private var balanceLabel: String {
        switch balanceState {
        case .idle:
            return "Balance: —"
        case .loading:
            return "Balance: Loading…"
        case .loaded(let value):
            return "Balance: \(value)"
        case .failed:
            return "Balance: Unavailable"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: chain.iconName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(chain.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(chain.title)
                    .font(.headline)
                Text(chain.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(balanceLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                Text("View keys")
                    .font(.footnote)
                    .foregroundStyle(chain.accentColor)
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(chain.accentColor)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(chain.accentColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct ChainDetailSheet: View {
    let chain: ChainInfo
    let balanceState: ChainBalanceState
    let onCopy: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    balanceSummary
                    ForEach(chain.details) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.label)
                                .font(.headline)
                            HStack(alignment: .top, spacing: 8) {
                                Text(item.value)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                Spacer(minLength: 0)
                                Button {
                                    onCopy(item.value)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .padding(8)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(12)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
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

struct ChainInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let iconName: String
    let accentColor: Color
    let details: [KeyDetail]
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

    struct Eth: Decodable {
        let balance: Double

        enum CodingKeys: String, CodingKey {
            case balance
        }
    }

    enum CodingKeys: String, CodingKey {
        case eth = "ETH"
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
    let litecoin: LitecoinKeys
    let monero: MoneroKeys
    let solana: SolanaKeys
    let ethereum: EthereumKeys
    let bnb: BnbKeys
    let xrp: XrpKeys

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
                ]
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
                ]
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
                ]
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
                ]
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
                ]
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
                details: ethereumDetails
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
                details: bnbDetails
            )
        )

        let tokenEntries: [(String, String, String, Color)] = [
            ("usdt", "Tether USD (USDT)", "ERC-20 Token", Color(red: 0.0, green: 0.64, blue: 0.54)),
            ("usdc", "USD Coin (USDC)", "ERC-20 Token", Color.blue),
            ("dai", "Dai (DAI)", "ERC-20 Token", Color.yellow)
        ]

        for entry in tokenEntries {
            cards.append(
                ChainInfo(
                    id: "\(entry.0)-erc20",
                    title: entry.1,
                    subtitle: entry.2,
                    iconName: "dollarsign.circle.fill",
                    accentColor: entry.3,
                    details: ethereumDetails
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
}

struct LitecoinKeys: Codable {
    let privateHex: String
    let privateWif: String
    let publicCompressedHex: String
    let address: String
}

struct MoneroKeys: Codable {
    let privateSpendHex: String
    let privateViewHex: String
    let publicSpendHex: String
    let publicViewHex: String
    let address: String
}

struct SolanaKeys: Codable {
    let privateSeedHex: String
    let privateKeyBase58: String
    let publicKeyBase58: String
}

struct EthereumKeys: Codable {
    let privateHex: String
    let publicUncompressedHex: String
    let address: String
}

struct BnbKeys: Codable {
    let privateHex: String
    let publicUncompressedHex: String
    let address: String
}

struct XrpKeys: Codable {
    let privateHex: String
    let publicCompressedHex: String
    let classicAddress: String
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
