import SwiftUI
import LocalAuthentication

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Security Overlay
// Unified security panel: score · lock · biometrics · policies · duress · keys.
// Every toggle wired to real managers — zero dummy data.
// Monochrome · Monumental · Mechanical.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct SecurityOverlay: View {
    @Binding var isPresented: Bool
    var onBackToSettings: (() -> Void)? = nil
    var initialTab: SecSection? = nil

    // ── Tab sections ──
    enum SecSection: String, CaseIterable {
        case score = "SCORE"
        case lock = "LOCK"
        case bio = "BIO"
        case policies = "POLICIES"
        case duress = "DURESS"
        case keys = "KEYS"
    }

    // ── Real managers ──
    @ObservedObject private var passcodeManager = PasscodeManager.shared
    @ObservedObject private var autoLockManager = AutoLockManager.shared
    @ObservedObject private var scoreManager = SecurityScoreManager.shared
    @ObservedObject private var duressManager = DuressWalletManager.shared
    @StateObject private var policiesVM = SecurityPoliciesViewModel()

    // ── UI state ──
    @State private var activeSection: SecSection = .score
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var silkPhase: CGFloat = 0
    @State private var closeHovered = false
    @State private var backHovered = false

    // ── Sheets ──
    @State private var showPasscodeSetup = false
    @State private var showRemovePasscode = false
    @State private var removePasscodeInput = ""
    @State private var removePasscodeError = false

    // ── Funnel navigation ──
    enum ActiveView: Equatable {
        case main, changePasscode, duressMain, duressSetup, duressChangePasscode
    }
    @State private var activeView: ActiveView = .main

    // Change passcode state
    enum ChangePinStep: Equatable { case verifyCurrent, enterNew, confirmNew }
    @State private var cpStep: ChangePinStep = .verifyCurrent
    @State private var cpCurrent = ""
    @State private var cpNew = ""
    @State private var cpConfirm = ""
    @State private var cpError: String?
    @State private var cpShake: CGFloat = 0

    // Duress inline state
    @State private var duressShowInfo = false
    @State private var duressShowTips = false
    @State private var duressShowDisableConfirm = false

    // Duress setup state
    @State private var dsStep = 0
    @State private var dsPin = ""
    @State private var dsConfirm = ""
    @State private var dsError: String?
    @State private var dsShake: CGFloat = 0

    // Duress change passcode state
    enum DuressChangePinStep: Equatable { case verifyOld, enterNew, confirmNew }
    @State private var dcpStep: DuressChangePinStep = .verifyOld
    @State private var dcpOld = ""
    @State private var dcpNew = ""
    @State private var dcpConfirm = ""
    @State private var dcpError: String?
    @State private var dcpShake: CGFloat = 0

    // ── Biometric settings ──
    @AppStorage("hawala.biometricUnlockEnabled") private var biometricEnabled = false
    @AppStorage("hawala.biometricForSends") private var biometricForSends = false
    @AppStorage("hawala.biometricForKeyReveal") private var biometricForKeyReveal = false

    private let biometricType = BiometricAuthHelper.availableBiometricType
    private let biometricAvailable = BiometricAuthHelper.isBiometricAvailable

    // ── Policies local state ──
    @State private var wlNewAddress = ""
    @State private var wlNewLabel = ""
    @State private var blNewAddress = ""
    @State private var blNewReason = ""

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Body
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    var body: some View {
        ZStack {
            backdrop
            mainCard
        }
        .background(
            EscapeKeyHandler(isPresented: $isPresented, onEscape: dismissOverlay)
        )
        .onAppear {
            if let tab = initialTab { activeSection = tab }
            passcodeManager.checkPasscodeStatus()
            policiesVM.loadSettings()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardScale = 1
                contentOpacity = 1
            }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                silkPhase = 1.5
            }
        }
        .sheet(isPresented: $showPasscodeSetup) {
            PasscodeSetupSheet(passcodeManager: passcodeManager) {
                showPasscodeSetup = false
                scoreManager.complete(.passcodeCreated)
            }
        }
        .alert("Disable Duress Protection?", isPresented: $duressShowDisableConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Disable", role: .destructive) {
                duressManager.disableDuress()
                AnalyticsService.shared.track(AnalyticsService.EventName.duressModeDisabled)
            }
        } message: {
            Text("This will remove the decoy wallet and its passcode.")
        }
        .alert("Remove Passcode", isPresented: $showRemovePasscode) {
            SecureField("Current passcode", text: $removePasscodeInput)
            Button("Remove", role: .destructive) {
                if passcodeManager.removePasscode(current: removePasscodeInput) {
                    scoreManager.uncomplete(.passcodeCreated)
                    removePasscodeInput = ""
                } else {
                    removePasscodeError = true
                    removePasscodeInput = ""
                }
            }
            Button("Cancel", role: .cancel) {
                removePasscodeInput = ""
            }
        } message: {
            Text("Enter your current passcode to remove it.")
        }
        .alert("Incorrect Passcode", isPresented: $removePasscodeError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The passcode you entered is incorrect.")
        }
        .alert("Security Alert", isPresented: $policiesVM.showAlert) {
            Button("Dismiss") { }
        } message: {
            Text(policiesVM.alertMessage)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Backdrop
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var backdrop: some View {
        Color.black.opacity(0.75)
            .ignoresSafeArea()
            .onTapGesture { dismissOverlay() }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Main Card
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var mainCard: some View {
        ZStack {
            if activeView == .main { mainPanelContent.transition(.opacity) }
            if activeView == .changePasscode { changePinPanelContent.transition(.opacity) }
            if activeView == .duressMain { duressMainPanelContent.transition(.opacity) }
            if activeView == .duressSetup { duressSetupPanelContent.transition(.opacity) }
            if activeView == .duressChangePasscode { duressChangePinPanelContent.transition(.opacity) }
        }
        .clipped()
        .frame(width: 600, height: 750)
        .background(cardBackground)
        .overlay(cardStroke)
        .shadow(color: .black.opacity(0.5), radius: 50, y: 25)
        .scaleEffect(cardScale)
        .opacity(contentOpacity)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: activeView)
    }

    private var mainPanelContent: some View {
        VStack(spacing: 0) {
            headerBar
            tabPicker
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    tabContent
                }
                .padding(.horizontal, 28)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
        }
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.0), .white.opacity(0.02), .white.opacity(0.0)],
                        startPoint: UnitPoint(x: silkPhase - 0.3, y: 0),
                        endPoint: UnitPoint(x: silkPhase + 0.3, y: 1)
                    )
                )
        }
    }

    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: 20)
            .strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.10), .white.opacity(0.03)],
                    startPoint: .top, endPoint: .bottom
                ), lineWidth: 1
            )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Header
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var headerBar: some View {
        ZStack {
            Text("SECURITY")
                .font(.clashGroteskMedium(size: 14))
                .tracking(3)
                .foregroundColor(.white.opacity(0.5))

            HStack {
                if onBackToSettings != nil {
                    Button(action: handleBackToSettings) {
                        Circle()
                            .fill(backHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.4))
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { backHovered = $0 }
                }
                Spacer()
                Button(action: dismissOverlay) {
                    Circle()
                        .fill(closeHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                        )
                }
                .buttonStyle(.plain)
                .onHover { closeHovered = $0 }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Tab Picker
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var tabPicker: some View {
        HStack(spacing: 4) {
            ForEach(SecSection.allCases, id: \.self) { section in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        activeSection = section
                    }
                }) {
                    Text(section.rawValue)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(activeSection == section ? .white : .white.opacity(0.3))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            activeSection == section
                                ? Color.white.opacity(0.10)
                                : Color.clear
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    activeSection == section
                                        ? Color.white.opacity(0.12)
                                        : Color.clear,
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Tab Content
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    @ViewBuilder
    private var tabContent: some View {
        switch activeSection {
        case .score: securityScoreSection
        case .lock: lockTabContent
        case .bio: biometricSection
        case .policies: policiesTabContent
        case .duress: duressSection
        case .keys: keysTabContent
        }
    }

    private var lockTabContent: some View {
        VStack(spacing: 20) {
            sessionLockSection
            autoLockSection
        }
    }

    private var policiesTabContent: some View {
        VStack(spacing: 20) {
            threatProtectionContent
            spendingLimitsContent
            whitelistContent
            blacklistContent
        }
    }

    private var keysTabContent: some View {
        VStack(spacing: 20) {
            keyRotationContent
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Security Score
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var securityScoreSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.06), lineWidth: 4)
                        .frame(width: 52, height: 52)
                    Circle()
                        .trim(from: 0, to: CGFloat(scoreManager.currentScore) / CGFloat(scoreManager.maxScore))
                        .stroke(scoreManager.securityLevel.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 52, height: 52)
                        .rotationEffect(.degrees(-90))
                    Text("\(scoreManager.currentScore)")
                        .font(.clashGroteskMedium(size: 16))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: scoreManager.securityLevel.icon)
                            .font(.system(size: 11))
                            .foregroundColor(scoreManager.securityLevel.color)
                        Text(scoreManager.securityLevel.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(scoreManager.securityLevel.color)
                    }
                    Text(scoreManager.securityLevel.description)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()
            }

            let essentials = SecurityScoreManager.SecurityItem.allCases.filter { $0.isEssential }
            VStack(spacing: 6) {
                ForEach(essentials) { item in
                    let done = scoreManager.completedItems.contains(item)
                    HStack(spacing: 8) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11))
                            .foregroundColor(done ? .green : .white.opacity(0.2))
                        Text(item.title)
                            .font(.system(size: 11))
                            .foregroundColor(done ? .white.opacity(0.5) : .white.opacity(0.35))
                            .strikethrough(done, color: .white.opacity(0.2))
                        Spacer()
                        if !done {
                            Text("+\(item.points)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.2))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Session Lock
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var sessionLockSection: some View {
        VStack(spacing: 10) {
            sectionHeader(icon: "lock.fill", title: "Session Lock")

            if passcodeManager.hasPasscode {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.green)
                    Text("Passcode active")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                }

                HStack(spacing: 8) {
                    SecOverlayButton(label: "Change", icon: "arrow.triangle.2.circlepath") {
                        resetChangePinState()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            activeView = .changePasscode
                        }
                    }
                    SecOverlayButton(label: "Remove", icon: "lock.open", destructive: true) {
                        showRemovePasscode = true
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.orange)
                    Text("No passcode set")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                }

                SecOverlayButton(label: "Set Passcode", icon: "lock") {
                    showPasscodeSetup = true
                }
            }
        }
        .sectionCard()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Biometrics
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var biometricSection: some View {
        VStack(spacing: 10) {
            sectionHeader(icon: biometricType.iconName, title: biometricType.displayName)

            if !biometricAvailable {
                HStack(spacing: 10) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.3))
                    Text("Not available on this device")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.35))
                    Spacer()
                }
            } else if !passcodeManager.hasPasscode {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundColor(.orange.opacity(0.7))
                    Text("Set a passcode first to enable biometrics")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                }
            } else {
                secToggleRow(
                    label: "Unlock with \(biometricType.displayName)",
                    isOn: $biometricEnabled,
                    onChange: { newVal in
                        if newVal {
                            scoreManager.complete(.biometricsEnabled)
                        } else {
                            scoreManager.uncomplete(.biometricsEnabled)
                        }
                    }
                )

                if biometricEnabled {
                    secToggleRow(label: "Require for sends", isOn: $biometricForSends)
                    secToggleRow(label: "Require for key reveal", isOn: $biometricForKeyReveal)
                }
            }
        }
        .sectionCard()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Auto-Lock
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var autoLockSection: some View {
        VStack(spacing: 10) {
            sectionHeader(icon: "timer", title: "Auto-Lock")

            if !passcodeManager.hasPasscode {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundColor(.orange.opacity(0.7))
                    Text("Requires passcode")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                }
            } else {
                HStack {
                    Text("Lock after")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    Picker("", selection: $autoLockManager.lockTimeout) {
                        ForEach(LockTimeout.allCases) { timeout in
                            Text(timeout.displayName).tag(timeout)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                    .onChange(of: autoLockManager.lockTimeout) { newValue in
                        autoLockManager.setLockTimeout(newValue)
                        if newValue != .never {
                            scoreManager.complete(.autoLockEnabled)
                        } else {
                            scoreManager.uncomplete(.autoLockEnabled)
                        }
                    }
                }

                secToggleRow(
                    label: "Lock when app backgrounds",
                    isOn: $autoLockManager.lockOnBackground,
                    onChange: { autoLockManager.setLockOnBackground($0) }
                )
            }
        }
        .sectionCard()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Duress PIN
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var duressSection: some View {
        VStack(spacing: 10) {
            sectionHeader(icon: "shield.checkered", title: "Duress PIN")

            if !passcodeManager.hasPasscode {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundColor(.orange.opacity(0.7))
                    Text("Requires passcode")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: duressManager.isConfigured ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13))
                        .foregroundColor(duressManager.isConfigured ? .green : .white.opacity(0.2))
                    Text(duressManager.isConfigured ? "Decoy wallet configured" : "Not configured")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                }

                Text("A secondary PIN opens a decoy wallet with minimal funds for plausible deniability under coercion.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
                    .fixedSize(horizontal: false, vertical: true)

                SecOverlayButton(
                    label: duressManager.isConfigured ? "Manage" : "Set Up",
                    icon: duressManager.isConfigured ? "gearshape" : "plus"
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        activeView = .duressMain
                    }
                }
            }
        }
        .sectionCard()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Threat Protection (Policies Tab)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var threatProtectionContent: some View {
        VStack(spacing: 10) {
            sectionHeader(icon: "shield.checkered", title: "Threat Protection")

            pillToggleRow("Enable Threat Detection", isOn: $policiesVM.threatProtectionEnabled) {
                policiesVM.saveThreatSettings()
            }

            if policiesVM.threatProtectionEnabled {
                pillToggleRow("Auto-block known scam addresses", isOn: $policiesVM.autoBlockScams) {
                    policiesVM.saveThreatSettings()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sensitivity Level")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))

                    Picker("", selection: $policiesVM.threatSensitivity) {
                        ForEach(SecurityPoliciesViewModel.ThreatSensitivity.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: policiesVM.threatSensitivity) { _ in
                        policiesVM.saveThreatSettings()
                    }

                    Text(policiesVM.threatSensitivity.description)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                }
            }

            HStack(spacing: 16) {
                ThreatIndicator(label: "Scams Blocked", count: 0, color: Color(red: 1, green: 0.27, blue: 0.23))
                ThreatIndicator(label: "Warnings Shown", count: 0, color: Color(red: 1, green: 0.84, blue: 0.04))
                ThreatIndicator(label: "Safe Txs", count: 0, color: Color(red: 0.20, green: 0.84, blue: 0.29))
            }
        }
        .sectionCard()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Spending Limits (Policies Tab)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var spendingLimitsContent: some View {
        VStack(spacing: 10) {
            sectionHeader(icon: "creditcard.trianglebadge.exclamationmark", title: "Spending Limits")

            Text("Set limits to protect against unauthorized large transactions")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))

            SecLimitTextField(label: "Per Transaction", placeholder: "e.g., 0.1 BTC", value: $policiesVM.perTxLimit, tooltip: "Maximum amount allowed per single transaction")
            SecLimitTextField(label: "Daily Limit", placeholder: "e.g., 0.5 BTC", value: $policiesVM.dailyLimit, tooltip: "Maximum total amount allowed within a 24-hour window")
            SecLimitTextField(label: "Weekly Limit", placeholder: "e.g., 2.0 BTC", value: $policiesVM.weeklyLimit, tooltip: "Maximum total amount allowed within a 7-day window")
            SecLimitTextField(label: "Monthly Limit", placeholder: "e.g., 5.0 BTC", value: $policiesVM.monthlyLimit, tooltip: "Maximum total amount allowed within a 30-day window")

            pillToggleRow("Require whitelisted recipient", isOn: $policiesVM.requireWhitelist)

            HStack {
                Spacer()
                Button(action: { policiesVM.saveSpendingLimits() }) {
                    HStack(spacing: 6) {
                        if policiesVM.isLoading {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                        } else {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 11))
                            Text("Save Limits")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(policiesVM.isLoading ? 0.05 : 0.12))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(policiesVM.isLoading)
            }
        }
        .sectionCard()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Whitelist (Policies Tab)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var whitelistContent: some View {
        VStack(spacing: 10) {
            sectionHeader(icon: "person.badge.shield.checkmark", title: "Trusted Addresses")

            Text("Add trusted addresses to skip security checks")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))

            HStack(spacing: 8) {
                TextField("Address", text: $wlNewAddress)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)
                TextField("Label", text: $wlNewLabel)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)
                    .frame(width: 120)
                Button(action: addWhitelistedAddress) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.white.opacity(wlNewAddress.isEmpty ? 0.15 : 0.5))
                }
                .buttonStyle(.plain)
                .disabled(wlNewAddress.isEmpty)
            }

            if policiesVM.whitelistedAddresses.isEmpty {
                Text("No whitelisted addresses yet")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.25))
                    .padding(.vertical, 8)
            } else {
                ForEach(policiesVM.whitelistedAddresses) { addr in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(addr.label)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                            Text(addr.address.prefix(20) + "..." + addr.address.suffix(8))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white.opacity(0.35))
                        }
                        Spacer()
                        Button(action: { policiesVM.whitelistedAddresses.removeAll { $0.id == addr.id } }) {
                            Image(systemName: "trash")
                                .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23).opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .sectionCard()
    }

    private func addWhitelistedAddress() {
        policiesVM.whitelistAddress(wlNewAddress, label: wlNewLabel.isEmpty ? "Unnamed" : wlNewLabel)
        wlNewAddress = ""
        wlNewLabel = ""
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Blacklist (Policies Tab)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var blacklistContent: some View {
        VStack(spacing: 10) {
            sectionHeader(icon: "hand.raised.slash", title: "Blocked Addresses")

            Text("Block addresses you don't want to interact with")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))

            HStack(spacing: 8) {
                TextField("Address to block", text: $blNewAddress)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)
                TextField("Reason", text: $blNewReason)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)
                    .frame(width: 150)
                Button(action: addBlacklistedAddress) {
                    Image(systemName: "hand.raised.slash.fill")
                        .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23).opacity(blNewAddress.isEmpty ? 0.2 : 0.6))
                }
                .buttonStyle(.plain)
                .disabled(blNewAddress.isEmpty)
            }

            if policiesVM.blacklistedAddresses.isEmpty {
                Text("No blocked addresses")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.25))
                    .padding(.vertical, 8)
            } else {
                ForEach(policiesVM.blacklistedAddresses) { addr in
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23).opacity(0.5))
                        VStack(alignment: .leading) {
                            Text(addr.address.prefix(20) + "..." + addr.address.suffix(8))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                            Text(addr.reason)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        Spacer()
                        Text(addr.source == "system" ? "System" : "Manual")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .sectionCard()
    }

    private func addBlacklistedAddress() {
        policiesVM.blacklistAddress(blNewAddress, reason: blNewReason.isEmpty ? "Manually blocked" : blNewReason)
        blNewAddress = ""
        blNewReason = ""
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Key Rotation (Keys Tab)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var keyRotationContent: some View {
        VStack(spacing: 10) {
            sectionHeader(icon: "key.horizontal", title: "Key Security")

            HStack {
                Image(systemName: policiesVM.keyRotationStatus.icon)
                    .foregroundColor(policiesVM.keyRotationStatus.color)
                    .font(.system(size: 20))

                VStack(alignment: .leading) {
                    Text(keyStatusText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    Text("Last checked: \(keyLastCheckText)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                }

                Spacer()

                Button(action: { policiesVM.checkKeyRotation() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Check Now")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            if policiesVM.keyRotationStatus != .healthy {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Color(red: 1, green: 0.84, blue: 0.04).opacity(0.7))
                    Text("Consider rotating your keys for enhanced security. Keys have been in use for \(policiesVM.daysSinceLastRotation) days.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(10)
                .background(Color(red: 1, green: 0.84, blue: 0.04).opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Key Security Tips")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                Text("• Rotate keys annually for best security")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
                Text("• Always backup before rotating")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
                Text("• Key rotation creates a new wallet")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .sectionCard()
    }

    private var keyStatusText: String {
        switch policiesVM.keyRotationStatus {
        case .healthy: return "Keys are secure"
        case .dueSoon: return "Rotation recommended soon"
        case .overdue: return "Key rotation overdue"
        }
    }

    private var keyLastCheckText: String {
        if let date = policiesVM.lastRotationCheck {
            let formatter = RelativeDateTimeFormatter()
            return formatter.localizedString(for: date, relativeTo: Date())
        }
        return "Never"
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Helpers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.35))
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.35))
            Spacer()
        }
    }

    private func secToggleRow(
        label: String,
        isOn: Binding<Bool>,
        onChange: ((Bool) -> Void)? = nil
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .onChange(of: isOn.wrappedValue) { newVal in
                    onChange?(newVal)
                }
        }
    }

    private func pillToggleRow(_ title: String, isOn: Binding<Bool>, onChange: @escaping () -> Void = {}) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isOn.wrappedValue.toggle()
                }
                onChange()
            } label: {
                ZStack {
                    Capsule()
                        .fill(isOn.wrappedValue ? Color.white.opacity(0.25) : Color.white.opacity(0.08))
                        .frame(width: 40, height: 24)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .offset(x: isOn.wrappedValue ? 8 : -8)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func dismissOverlay() {
        resetAllState()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            cardScale = 0.95
            contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }

    private func closeOverlay() {
        resetAllState()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            cardScale = 0.95
            contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }

    private func handleBackToSettings() {
        resetAllState()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            cardScale = 0.95
            contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
            onBackToSettings?()
        }
    }

    private func navigateBack() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            switch activeView {
            case .main: break
            case .changePasscode:
                resetChangePinState()
                activeView = .main
            case .duressMain:
                activeView = .main
            case .duressSetup:
                resetDuressSetupState()
                activeView = .duressMain
            case .duressChangePasscode:
                resetDuressChangePinState()
                activeView = .duressMain
            }
        }
    }

    private func resetAllState() {
        activeView = .main
        resetChangePinState()
        resetDuressSetupState()
        resetDuressChangePinState()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Panel Header
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func panelHeader(title: String, onBack: @escaping () -> Void) -> some View {
        ZStack {
            Text(title.uppercased())
                .font(.clashGroteskMedium(size: 14))
                .tracking(3)
                .foregroundColor(.white.opacity(0.5))

            HStack {
                Button(action: onBack) {
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: closeOverlay) {
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
            Text(message)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(red: 1, green: 0.27, blue: 0.23).opacity(0.08))
        .cornerRadius(8)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Change Passcode Panel
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var changePinPanelContent: some View {
        VStack(spacing: 0) {
            panelHeader(title: cpStepTitle) { navigateBack() }

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(i <= cpStepIndex ? Color.white : Color.white.opacity(0.12))
                        .frame(width: i == cpStepIndex ? 24 : 8, height: 4)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: cpStepIndex)
                }
            }
            .padding(.bottom, 20)

            Spacer()

            Image(systemName: cpStepIcon)
                .font(.system(size: 36, weight: .thin))
                .foregroundColor(.white.opacity(0.5))
                .padding(.bottom, 16)

            Text(cpStepSubtitle)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 24)

            if let error = cpError {
                errorBanner(error)
                    .padding(.bottom, 16)
            }

            HawalaPinPad(pin: cpCurrentBinding, maxDigits: 6, onComplete: handleChangePinComplete)
                .offset(x: cpShake)

            Spacer()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: cpStep)
    }

    private var cpStepIndex: Int {
        switch cpStep {
        case .verifyCurrent: return 0
        case .enterNew: return 1
        case .confirmNew: return 2
        }
    }

    private var cpStepTitle: String {
        switch cpStep {
        case .verifyCurrent: return "Current Passcode"
        case .enterNew: return "New Passcode"
        case .confirmNew: return "Confirm Passcode"
        }
    }

    private var cpStepSubtitle: String {
        switch cpStep {
        case .verifyCurrent: return "Enter your current passcode to continue"
        case .enterNew: return "Choose a new 6-digit passcode"
        case .confirmNew: return "Enter the same passcode again to confirm"
        }
    }

    private var cpStepIcon: String {
        switch cpStep {
        case .verifyCurrent: return "key.fill"
        case .enterNew: return "lock.fill"
        case .confirmNew: return "checkmark.shield.fill"
        }
    }

    private var cpCurrentBinding: Binding<String> {
        switch cpStep {
        case .verifyCurrent: return $cpCurrent
        case .enterNew: return $cpNew
        case .confirmNew: return $cpConfirm
        }
    }

    private func handleChangePinComplete(_ pin: String) {
        cpError = nil
        switch cpStep {
        case .verifyCurrent:
            guard passcodeManager.verifyPasscode(pin) else {
                cpError = "Incorrect passcode"
                cpTriggerShake()
                cpCurrent = ""
                return
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cpStep = .enterNew
            }
        case .enterNew:
            guard pin != cpCurrent else {
                cpError = "Must be different from current"
                cpTriggerShake()
                cpNew = ""
                return
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cpStep = .confirmNew
            }
        case .confirmNew:
            guard pin == cpNew else {
                cpError = "Passcodes don't match"
                cpTriggerShake()
                cpConfirm = ""
                return
            }
            let result = passcodeManager.changePasscode(current: cpCurrent, new: cpNew)
            if result.success {
                ToastManager.shared.success("Passcode Updated")
                resetChangePinState()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    activeView = .main
                }
            } else {
                cpError = result.error ?? "Failed to update"
            }
        }
    }

    private func cpTriggerShake() {
        withAnimation(.default) { cpShake = -12 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.default) { self.cpShake = 12 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.default) { self.cpShake = -8 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { self.cpShake = 0 }
        }
    }

    private func resetChangePinState() {
        cpStep = .verifyCurrent
        cpCurrent = ""
        cpNew = ""
        cpConfirm = ""
        cpError = nil
        cpShake = 0
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Duress Main Panel
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var duressMainPanelContent: some View {
        VStack(spacing: 0) {
            panelHeader(title: "Duress PIN") { navigateBack() }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        sectionHeader(icon: "shield.lefthalf.filled", title: "Status")
                        HStack(spacing: 14) {
                            Image(systemName: duressManager.isDuressEnabled ? "checkmark.shield.fill" : "shield.slash")
                                .font(.system(size: 22))
                                .foregroundColor(duressManager.isDuressEnabled
                                    ? Color(red: 0.20, green: 0.84, blue: 0.29)
                                    : .white.opacity(0.25))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Duress Protection")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.85))
                                Text(duressManager.isDuressEnabled ? "Active" : "Not Configured")
                                    .font(.system(size: 12))
                                    .foregroundColor(duressManager.isDuressEnabled
                                        ? Color(red: 0.20, green: 0.84, blue: 0.29)
                                        : .white.opacity(0.35))
                            }
                            Spacer()
                        }
                    }
                    .sectionCard()

                    VStack(spacing: 10) {
                        Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { duressShowInfo.toggle() } }) {
                            HStack(spacing: 8) {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.35))
                                Text("WHAT IS DURESS MODE?")
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(1.2)
                                    .foregroundColor(.white.opacity(0.35))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.25))
                                    .rotationEffect(.degrees(duressShowInfo ? 90 : 0))
                            }
                        }
                        .buttonStyle(.plain)
                        if duressShowInfo {
                            VStack(spacing: 10) {
                                duressInfoRow(icon: "eye.slash", title: "Decoy Wallet", desc: "Opens when you enter the decoy passcode.")
                                duressInfoRow(icon: "lock.shield", title: "Plausible Deniability", desc: "No way to detect the real wallet exists.")
                                duressInfoRow(icon: "hand.raised", title: "Coercion Protection", desc: "Enter decoy passcode under duress.")
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .sectionCard()

                    VStack(spacing: 10) {
                        sectionHeader(icon: "gearshape", title: "Configuration")
                        if !duressManager.isDuressEnabled {
                            SecOverlayButton(label: "Set Up Decoy Wallet", icon: "plus") {
                                resetDuressSetupState()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    activeView = .duressSetup
                                }
                            }
                        } else {
                            SecOverlayButton(label: "Change Decoy Passcode", icon: "key") {
                                resetDuressChangePinState()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    activeView = .duressChangePasscode
                                }
                            }
                            SecOverlayButton(label: "Disable Protection", icon: "trash", destructive: true) {
                                duressShowDisableConfirm = true
                            }
                        }
                    }
                    .sectionCard()

                    VStack(spacing: 10) {
                        Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { duressShowTips.toggle() } }) {
                            HStack(spacing: 8) {
                                Image(systemName: "lightbulb")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.35))
                                Text("TIPS")
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(1.2)
                                    .foregroundColor(.white.opacity(0.35))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.25))
                                    .rotationEffect(.degrees(duressShowTips ? 90 : 0))
                            }
                        }
                        .buttonStyle(.plain)
                        if duressShowTips {
                            VStack(spacing: 6) {
                                duressTipRow("Use a passcode you can remember under stress")
                                duressTipRow("Keep a believable amount in your decoy wallet")
                                duressTipRow("Practice switching between wallets")
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .sectionCard()
                }
                .padding(.horizontal, 28)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
        }
    }

    @ViewBuilder
    private func duressInfoRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
    }

    @ViewBuilder
    private func duressTipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(Color(red: 0.20, green: 0.84, blue: 0.29).opacity(0.6))
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Duress Setup Panel
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var duressSetupPanelContent: some View {
        VStack(spacing: 0) {
            panelHeader(title: dsStepTitle) { navigateBack() }

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(i <= min(dsStep, 2) ? Color.white : Color.white.opacity(0.12))
                        .frame(width: i == min(dsStep, 2) ? 24 : 8, height: 4)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dsStep)
                }
            }
            .padding(.bottom, 20)

            Spacer()

            if dsStep == 0 {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 40, weight: .thin))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.bottom, 16)
                Text("Create a decoy wallet that opens\nwith a separate passcode.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 24)
                SecOverlayButton(label: "Continue", icon: "arrow.right") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { dsStep = 1 }
                }
            } else if dsStep == 1 {
                Image(systemName: "key.fill")
                    .font(.system(size: 32, weight: .thin))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.bottom, 12)
                Text("Choose a 6-digit decoy passcode")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.bottom, 20)
                if let error = dsError {
                    errorBanner(error).padding(.bottom, 16)
                }
                HawalaPinPad(pin: $dsPin, maxDigits: 6, onComplete: { _ in
                    dsError = nil
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { dsStep = 2 }
                })
                .offset(x: dsShake)
            } else if dsStep == 2 {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 32, weight: .thin))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.bottom, 12)
                Text("Confirm decoy passcode")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.bottom, 20)
                if let error = dsError {
                    errorBanner(error).padding(.bottom, 16)
                }
                HawalaPinPad(pin: $dsConfirm, maxDigits: 6, onComplete: handleDuressSetupConfirm)
                    .offset(x: dsShake)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44, weight: .thin))
                    .foregroundColor(Color(red: 0.20, green: 0.84, blue: 0.29))
                    .padding(.bottom, 16)
                Text("Decoy Wallet Created")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.bottom, 8)
                Text("Enter your decoy passcode at unlock.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 24)
                SecOverlayButton(label: "Done", icon: "checkmark.circle") {
                    resetDuressSetupState()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        activeView = .duressMain
                    }
                }
            }

            Spacer()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: dsStep)
    }

    private var dsStepTitle: String {
        switch dsStep {
        case 0: return "Set Up Decoy"
        case 1: return "Decoy Passcode"
        case 2: return "Confirm Passcode"
        default: return "Complete"
        }
    }

    private func handleDuressSetupConfirm(_ pin: String) {
        dsError = nil
        guard pin == dsPin else {
            dsError = "Passcodes don't match"
            dsTriggerShake()
            dsConfirm = ""
            return
        }
        let result = duressManager.setDuressPin(dsPin, confirmPin: dsConfirm)
        switch result {
        case .success:
            AnalyticsService.shared.track(AnalyticsService.EventName.duressModeEnabled)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { dsStep = 3 }
        case .failure(let error):
            dsError = error.localizedDescription
        }
    }

    private func dsTriggerShake() {
        withAnimation(.default) { dsShake = -12 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.default) { self.dsShake = 12 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.default) { self.dsShake = -8 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { self.dsShake = 0 }
        }
    }

    private func resetDuressSetupState() {
        dsStep = 0
        dsPin = ""
        dsConfirm = ""
        dsError = nil
        dsShake = 0
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Duress Change Passcode Panel
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var duressChangePinPanelContent: some View {
        VStack(spacing: 0) {
            panelHeader(title: dcpStepTitle) { navigateBack() }

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(i <= dcpStepIndex ? Color.white : Color.white.opacity(0.12))
                        .frame(width: i == dcpStepIndex ? 24 : 8, height: 4)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dcpStepIndex)
                }
            }
            .padding(.bottom, 20)

            Spacer()

            Image(systemName: dcpStepIcon)
                .font(.system(size: 36, weight: .thin))
                .foregroundColor(.white.opacity(0.5))
                .padding(.bottom, 16)

            Text(dcpStepSubtitle)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 24)

            if let error = dcpError {
                errorBanner(error)
                    .padding(.bottom, 16)
            }

            HawalaPinPad(pin: dcpCurrentBinding, maxDigits: 6, onComplete: handleDuressChangePinComplete)
                .offset(x: dcpShake)

            Spacer()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: dcpStep)
    }

    private var dcpStepIndex: Int {
        switch dcpStep {
        case .verifyOld: return 0
        case .enterNew: return 1
        case .confirmNew: return 2
        }
    }

    private var dcpStepTitle: String {
        switch dcpStep {
        case .verifyOld: return "Current Decoy PIN"
        case .enterNew: return "New Decoy PIN"
        case .confirmNew: return "Confirm Decoy PIN"
        }
    }

    private var dcpStepSubtitle: String {
        switch dcpStep {
        case .verifyOld: return "Enter your current decoy passcode"
        case .enterNew: return "Choose a new 6-digit decoy passcode"
        case .confirmNew: return "Enter the same passcode again to confirm"
        }
    }

    private var dcpStepIcon: String {
        switch dcpStep {
        case .verifyOld: return "key.fill"
        case .enterNew: return "lock.fill"
        case .confirmNew: return "checkmark.shield.fill"
        }
    }

    private var dcpCurrentBinding: Binding<String> {
        switch dcpStep {
        case .verifyOld: return $dcpOld
        case .enterNew: return $dcpNew
        case .confirmNew: return $dcpConfirm
        }
    }

    private func handleDuressChangePinComplete(_ pin: String) {
        dcpError = nil
        switch dcpStep {
        case .verifyOld:
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                dcpStep = .enterNew
            }
        case .enterNew:
            guard pin != dcpOld else {
                dcpError = "Must be different from current"
                dcpTriggerShake()
                dcpNew = ""
                return
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                dcpStep = .confirmNew
            }
        case .confirmNew:
            guard pin == dcpNew else {
                dcpError = "Passcodes don't match"
                dcpTriggerShake()
                dcpConfirm = ""
                return
            }
            let result = duressManager.changeDuressPin(oldPin: dcpOld, newPin: dcpNew, confirmPin: dcpConfirm)
            switch result {
            case .success:
                ToastManager.shared.success("Decoy Passcode Updated")
                resetDuressChangePinState()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    activeView = .duressMain
                }
            case .failure(let error):
                dcpError = error.localizedDescription
                dcpStep = .verifyOld
                dcpOld = ""
                dcpNew = ""
                dcpConfirm = ""
            }
        }
    }

    private func dcpTriggerShake() {
        withAnimation(.default) { dcpShake = -12 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.default) { self.dcpShake = 12 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.default) { self.dcpShake = -8 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { self.dcpShake = 0 }
        }
    }

    private func resetDuressChangePinState() {
        dcpStep = .verifyOld
        dcpOld = ""
        dcpNew = ""
        dcpConfirm = ""
        dcpError = nil
        dcpShake = 0
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Reusable Components
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private struct SecOverlayButton: View {
    let label: String
    let icon: String
    var destructive: Bool = false
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(destructive ? .red.opacity(0.8) : .white.opacity(0.6))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                (destructive ? Color.red : Color.white).opacity(hovered ? 0.08 : 0.04)
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        (destructive ? Color.red : Color.white).opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: – Section Card Modifier

private struct SectionCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

extension View {
    fileprivate func sectionCard() -> some View {
        modifier(SectionCardModifier())
    }
}

// MARK: – Threat Indicator

private struct ThreatIndicator: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }
}

// MARK: – Limit Text Field

private struct SecLimitTextField: View {
    let label: String
    let placeholder: String
    @Binding var value: String
    var tooltip: String = ""

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 120, alignment: .leading)
            TextField(placeholder, text: $value)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
        .help(tooltip)
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Security Policies View Model
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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

    enum KeyRotationStatus: Equatable {
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
        let source: String
    }

    func loadSettings() {
        threatProtectionEnabled = UserDefaults.standard.bool(forKey: "security.threatProtection")
        if !UserDefaults.standard.secContains(key: "security.threatProtection") {
            threatProtectionEnabled = true
        }
        autoBlockScams = UserDefaults.standard.bool(forKey: "security.autoBlockScams")
        if !UserDefaults.standard.secContains(key: "security.autoBlockScams") {
            autoBlockScams = true
        }

        perTxLimit = UserDefaults.standard.string(forKey: "security.perTxLimit") ?? ""
        dailyLimit = UserDefaults.standard.string(forKey: "security.dailyLimit") ?? ""
        weeklyLimit = UserDefaults.standard.string(forKey: "security.weeklyLimit") ?? ""
        monthlyLimit = UserDefaults.standard.string(forKey: "security.monthlyLimit") ?? ""
        requireWhitelist = UserDefaults.standard.bool(forKey: "security.requireWhitelist")

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

// MARK: – UserDefaults Helper

extension UserDefaults {
    func secContains(key: String) -> Bool {
        return object(forKey: key) != nil
    }
}
