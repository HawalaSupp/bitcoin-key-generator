import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Security Overlay
// Vault-grade security command center.
// Geometric lock completion, radial dial, layered shields,
// biometric scan patterns, mechanical event timeline.
// Monumental. Monochrome. Impenetrable.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct SecurityOverlay: View {
    @Binding var isPresented: Bool

    // ── Section navigation ──
    @State private var activeSection: SecSection = .overview

    enum SecSection: String, CaseIterable {
        case overview = "STATUS"
        case auth = "AUTH"
        case txSecurity = "TRANSACTIONS"
        case access = "ACCESS"
        case audit = "AUDIT"
    }

    // ── Auth settings ──
    @State private var hasPasscode: Bool = true
    @State private var biometricEnabled: Bool = true
    @State private var biometricType: String = "Touch ID"
    @State private var twoFactorEnabled: Bool = false

    // ── Password change flow ──
    @State private var showPasswordChange: Bool = false
    @State private var passwordStep: PasswordStep = .current
    @State private var currentPW: String = ""
    @State private var newPW: String = ""
    @State private var confirmPW: String = ""
    @State private var pwError: String? = nil
    @State private var pwSuccess: Bool = false
    @State private var holdVerifyProgress: CGFloat = 0
    @State private var holdingVerify: Bool = false
    @State private var holdVerifyTimer: Timer? = nil

    enum PasswordStep { case current, newPassword, confirm, success }

    // ── PIN ──
    @State private var showPINSetup: Bool = false
    @State private var pinDigits: [String] = ["", "", "", "", "", ""]
    @State private var pinFocusIndex: Int = 0
    @State private var pinSet: Bool = true

    // ── Biometric scan animation ──
    @State private var bioScanPhase: CGFloat = 0
    @State private var bioScanActive: Bool = false

    // ── Auto-lock radial dial ──
    @State private var autoLockOption: Int = 2 // index into autoLockOptions
    @State private var dialAngle: Double = 0
    @State private var dialDragging: Bool = false

    // ── Transaction confirmation ──
    @State private var txConfirmLevel: Int = 0  // 0=always, 1=threshold, 2=passkey, 3=multisig
    @State private var txThreshold: String = "100"
    @State private var passkeyThreshold: String = "1000"

    // ── Address book ──
    @State private var savedAddresses: [SecAddress] = []
    @State private var showAddAddress: Bool = false
    @State private var newAddrLabel: String = ""
    @State private var newAddrValue: String = ""
    @State private var newAddrWhitelist: Bool = false

    // ── Audit log ──
    @State private var auditLog: [SecAuditEvent] = []

    // ── Sessions ──
    @State private var activeSessions: [SecSession] = []

    // ── Phishing ──
    @State private var phishingEnabled: Bool = true
    @State private var txSimulation: Bool = true

    // ── 2FA setup ──
    @State private var show2FASetup: Bool = false
    @State private var twoFACode: String = ""
    @State private var twoFAStep: Int = 0

    // ── Animation ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var silkPhase: CGFloat = 0
    @State private var vaultCompletion: CGFloat = 0

    // ── Hover ──
    @State private var closeHovered: Bool = false

    // Auto-lock time options
    private let autoLockOptions: [(label: String, minutes: Int)] = [
        ("IMMEDIATE", 0), ("1 MIN", 1), ("5 MIN", 5),
        ("15 MIN", 15), ("30 MIN", 30), ("NEVER", -1)
    ]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Body
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    var body: some View {
        ZStack {
            backdrop
            cardShell
        }
        .background(
            EscapeKeyHandler(isPresented: $isPresented, onEscape: dismissOverlay)
        )
        .onAppear {
            loadMockData()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardScale = 1; contentOpacity = 1
            }
            startAnimations()
        }
    }

    private var backdrop: some View {
        Color.black.opacity(0.75)
            .ignoresSafeArea()
            .onTapGesture { dismissOverlay() }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Card
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var cardShell: some View {
        VStack(spacing: 0) {
            headerBar
            sectionPicker
            sectionContent
        }
        .frame(width: 460, height: 680)
        .background(cardBg)
        .overlay(cardStroke)
        .shadow(color: .black.opacity(0.5), radius: 50, y: 25)
        .scaleEffect(cardScale)
        .opacity(contentOpacity)
    }

    private var cardBg: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.0), .white.opacity(0.018), .white.opacity(0.0)],
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

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Header
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var headerBar: some View {
        ZStack {
            Text("SECURITY")
                .font(.clashGroteskMedium(size: 14))
                .tracking(3)
                .foregroundColor(.white.opacity(0.5))
            HStack {
                Spacer()
                Button(action: dismissOverlay) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(closeHovered ? 0.9 : 0.4))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white.opacity(closeHovered ? 0.12 : 0.06)))
                }
                .buttonStyle(.plain)
                .onHover { closeHovered = $0 }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Section Picker
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(SecSection.allCases, id: \.self) { sec in
                    secTabButton(sec)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 8)
    }

    private func secTabButton(_ sec: SecSection) -> some View {
        let selected = activeSection == sec
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                activeSection = sec
            }
        } label: {
            VStack(spacing: 5) {
                Text(sec.rawValue)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(selected ? 0.8 : 0.3))
                    .padding(.horizontal, 10)
                RoundedRectangle(cornerRadius: 1)
                    .fill(.white.opacity(selected ? 0.4 : 0))
                    .frame(height: 1.5)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Section Content
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var sectionContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                switch activeSection {
                case .overview: overviewSection
                case .auth: authenticationSection
                case .txSecurity: transactionSecuritySection
                case .access: accessSection
                case .audit: auditSection
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Overview (Vault Door)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var overviewSection: some View {
        VStack(spacing: 20) {
            vaultStatusView
            securityScoreBreakdown
            quickActions
        }
    }

    private var vaultStatusView: some View {
        let score = computeSecurityScore()
        let segments = 8
        return VStack(spacing: 14) {
            // Vault door — concentric rings with segments
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    vaultRing(ring: ring, filledSegments: filledSegments(ring: ring, score: score), totalSegments: segments)
                }
                // Center
                VStack(spacing: 2) {
                    Text("\(score)%")
                        .font(.clashGroteskBold(size: 32))
                        .foregroundColor(.white.opacity(0.85))
                    Text(score >= 80 ? "PROTECTED" : score >= 50 ? "MODERATE" : "AT RISK")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .frame(height: 140)
        }
    }

    private func vaultRing(ring: Int, filledSegments: Int, totalSegments: Int) -> some View {
        let radius: CGFloat = CGFloat(36 + ring * 18)
        let lineW: CGFloat = ring == 0 ? 4 : (ring == 1 ? 3 : 2)
        return ZStack {
            ForEach(0..<totalSegments, id: \.self) { seg in
                vaultSegmentArc(seg: seg, total: totalSegments, radius: radius,
                                filled: seg < filledSegments, lineWidth: lineW)
            }
        }
    }

    private func vaultSegmentArc(seg: Int, total: Int, radius: CGFloat, filled: Bool, lineWidth: CGFloat) -> some View {
        let gap = 6.0
        let segAngle = 360.0 / Double(total)
        let startA = segAngle * Double(seg) + gap / 2 - 90
        let endA = segAngle * Double(seg + 1) - gap / 2 - 90
        return Circle()
            .trim(from: CGFloat(startA / 360), to: CGFloat(endA / 360))
            .stroke(.white.opacity(filled ? 0.35 : 0.06), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: radius * 2, height: radius * 2)
    }

    private func filledSegments(ring: Int, score: Int) -> Int {
        let total = 8
        let fraction: Double
        switch ring {
        case 0: fraction = min(1.0, Double(score) / 100.0 * 1.2)
        case 1: fraction = min(1.0, Double(score) / 100.0)
        default: fraction = min(1.0, Double(score) / 100.0 * 0.8)
        }
        return Int(fraction * Double(total))
    }

    private var securityScoreBreakdown: some View {
        VStack(spacing: 6) {
            secScoreRow(label: "PASSWORD", enabled: hasPasscode)
            secScoreRow(label: "BIOMETRIC", enabled: biometricEnabled)
            secScoreRow(label: "TWO-FACTOR", enabled: twoFactorEnabled)
            secScoreRow(label: "PHISHING SHIELD", enabled: phishingEnabled)
            secScoreRow(label: "TX SIMULATION", enabled: txSimulation)
            secScoreRow(label: "AUTO-LOCK", enabled: autoLockOption != 5) // 5 = Never
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.025))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.05), lineWidth: 1))
        )
    }

    private func secScoreRow(label: String, enabled: Bool) -> some View {
        HStack(spacing: 8) {
            // Geometric status indicator: filled circle vs empty ring
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.2), lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                if enabled {
                    Circle()
                        .fill(.white.opacity(0.45))
                        .frame(width: 6, height: 6)
                }
            }
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(enabled ? 0.6 : 0.25))
                .tracking(1)
            Spacer()
            Text(enabled ? "ACTIVE" : "OFF")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(enabled ? 0.45 : 0.15))
        }
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            secActionBtn(icon: "arrow.down.doc", label: "EXPORT REPORT") {
                // Mock export
            }
            secActionBtn(icon: "arrow.clockwise", label: "RUN AUDIT") {
                // Mock audit
            }
        }
    }

    private func secActionBtn(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            .foregroundColor(.white.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.06), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    private func computeSecurityScore() -> Int {
        var s = 0
        if hasPasscode { s += 20 }
        if biometricEnabled { s += 15 }
        if twoFactorEnabled { s += 20 }
        if phishingEnabled { s += 15 }
        if txSimulation { s += 10 }
        if autoLockOption != 5 { s += 10 }
        if pinSet { s += 10 }
        return min(100, s)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Authentication Section
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var authenticationSection: some View {
        VStack(spacing: 16) {
            secSectionLabel("PASSWORD & PIN")
            passwordPINCard
            secSectionLabel("BIOMETRIC AUTHENTICATION")
            biometricCard
            secSectionLabel("TWO-FACTOR (2FA)")
            twoFactorCard
            secSectionLabel("AUTO-LOCK TIMER")
            autoLockCard
        }
    }

    // ── Password & PIN ──
    private var passwordPINCard: some View {
        VStack(spacing: 12) {
            if showPasswordChange {
                passwordChangeFlow
            } else {
                VStack(spacing: 10) {
                    secSettingRow(icon: "lock.fill", title: "Wallet Password",
                                 detail: hasPasscode ? "Protected" : "Not set",
                                 enabled: hasPasscode)
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showPasswordChange = true
                            passwordStep = hasPasscode ? .current : .newPassword
                            currentPW = ""; newPW = ""; confirmPW = ""; pwError = nil; pwSuccess = false
                        }
                    } label: {
                        Text(hasPasscode ? "CHANGE PASSWORD" : "SET PASSWORD")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
                    }
                    .buttonStyle(.plain)
                }

                Divider().background(.white.opacity(0.06))

                secSettingRow(icon: "number", title: "Quick-Access PIN",
                              detail: pinSet ? "6-digit PIN set" : "Not configured",
                              enabled: pinSet)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showPINSetup.toggle()
                    }
                } label: {
                    Text(pinSet ? "CHANGE PIN" : "SET UP PIN")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
                }
                .buttonStyle(.plain)

                if showPINSetup {
                    pinInputView
                }
            }
        }
        .padding(16)
        .background(secCardBg)
    }

    // ── Password change flow ──
    private var passwordChangeFlow: some View {
        VStack(spacing: 14) {
            passwordStepIndicator
            passwordStepContent
        }
    }

    private var passwordStepIndicator: some View {
        HStack(spacing: 8) {
            if hasPasscode {
                pwStepDot(label: "VERIFY", active: passwordStep == .current, done: passwordStep != .current)
            }
            pwStepDot(label: "NEW", active: passwordStep == .newPassword,
                       done: passwordStep == .confirm || passwordStep == .success)
            pwStepDot(label: "CONFIRM", active: passwordStep == .confirm,
                       done: passwordStep == .success)
        }
    }

    private func pwStepDot(label: String, active: Bool, done: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(active ? 0.35 : 0.12), lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                if done {
                    Circle()
                        .fill(.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                } else if active {
                    Circle()
                        .fill(.white.opacity(0.5))
                        .frame(width: 6, height: 6)
                }
            }
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(active ? 0.5 : 0.2))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var passwordStepContent: some View {
        switch passwordStep {
        case .current:
            currentPasswordStep
        case .newPassword:
            newPasswordStep
        case .confirm:
            confirmPasswordStep
        case .success:
            passwordSuccessStep
        }
    }

    private var currentPasswordStep: some View {
        VStack(spacing: 10) {
            Text("Verify your current password")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
            SecureField("Current password", text: $currentPW)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .textFieldStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.06))))
            if let err = pwError {
                Text(err)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
            }
            holdToVerifyButton
        }
    }

    // Hold-to-verify current password
    private var holdToVerifyButton: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05))
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.08))
                    .frame(width: geo.size.width * holdVerifyProgress)
            }
            Text(holdingVerify ? "VERIFYING..." : "HOLD TO VERIFY")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(holdingVerify ? 0.5 : 0.6))
                .frame(maxWidth: .infinity)
        }
        .frame(height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in beginHoldVerify() }
                .onEnded { _ in cancelHoldVerify() }
        )
    }

    private var newPasswordStep: some View {
        VStack(spacing: 10) {
            Text("Enter your new password")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
            SecureField("New password", text: $newPW)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .textFieldStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.06))))
            // Strength indicator — geometric bar
            passwordStrengthBar
            Button {
                if newPW.count >= 6 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { passwordStep = .confirm }
                } else {
                    pwError = "Minimum 6 characters"
                }
            } label: {
                Text("CONTINUE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(newPW.count >= 6 ? 0.6 : 0.25))
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05)))
            }
            .buttonStyle(.plain)
        }
    }

    private var passwordStrengthBar: some View {
        let strength = passwordStrength(newPW)
        return VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.06))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(strength.opacity))
                        .frame(width: geo.size.width * strength.fraction, height: 4)
                }
            }
            .frame(height: 4)
            HStack {
                Text("STRENGTH")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
                Spacer()
                Text(strength.label)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(strength.opacity))
            }
        }
    }

    private func passwordStrength(_ pw: String) -> (label: String, fraction: CGFloat, opacity: Double) {
        let len = pw.count
        if len == 0 { return ("", 0, 0.15) }
        if len < 6 { return ("WEAK", 0.25, 0.2) }
        var score = 0
        if len >= 8 { score += 1 }
        if len >= 12 { score += 1 }
        if pw.rangeOfCharacter(from: .uppercaseLetters) != nil { score += 1 }
        if pw.rangeOfCharacter(from: .decimalDigits) != nil { score += 1 }
        if pw.rangeOfCharacter(from: .punctuationCharacters) != nil { score += 1 }
        switch score {
        case 0...1: return ("FAIR", 0.4, 0.25)
        case 2...3: return ("GOOD", 0.7, 0.35)
        default: return ("STRONG", 1.0, 0.5)
        }
    }

    private var confirmPasswordStep: some View {
        VStack(spacing: 10) {
            Text("Confirm your new password")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
            SecureField("Confirm password", text: $confirmPW)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .textFieldStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.06))))
            if let err = pwError {
                Text(err).font(.system(size: 9)).foregroundColor(.white.opacity(0.4))
            }
            Button {
                if confirmPW == newPW {
                    pwError = nil
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        passwordStep = .success; pwSuccess = true
                    }
                    scheduleAfter(1.5) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            showPasswordChange = false
                        }
                    }
                } else { pwError = "Passwords do not match" }
            } label: {
                Text("SET PASSWORD")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(confirmPW == newPW ? 0.6 : 0.25))
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .disabled(confirmPW.isEmpty)
        }
    }

    private var passwordSuccessStep: some View {
        VStack(spacing: 10) {
            // Vault lock icon completing
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.15), lineWidth: 2)
                    .frame(width: 44, height: 44)
                Image(systemName: "lock.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.5))
            }
            Text("PASSWORD UPDATED")
                .font(.clashGroteskMedium(size: 14))
                .tracking(2)
                .foregroundColor(.white.opacity(0.7))
            Text("Your wallet is secured with the new password")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.vertical, 8)
    }

    // Cancel password change at bottom
    private func cancelPasswordChangeBtn() -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                showPasswordChange = false
            }
        } label: {
            Text("CANCEL")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
        }
        .buttonStyle(.plain)
    }

    // ── PIN input ──
    private var pinInputView: some View {
        VStack(spacing: 10) {
            Text("Enter 6-digit PIN")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { idx in
                    pinDot(index: idx)
                }
            }
            // Number pad
            pinNumberPad
            Button {
                let complete = pinDigits.allSatisfy { !$0.isEmpty }
                if complete {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        pinSet = true
                        showPINSetup = false
                        pinDigits = ["", "", "", "", "", ""]
                        pinFocusIndex = 0
                    }
                }
            } label: {
                Text("SAVE PIN")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    private func pinDot(index: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(index == pinFocusIndex ? 0.06 : 0.03))
                .frame(width: 34, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.white.opacity(index == pinFocusIndex ? 0.15 : 0.06), lineWidth: 1)
                )
            if !pinDigits[index].isEmpty {
                Circle()
                    .fill(.white.opacity(0.5))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var pinNumberPad: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(["1", "2", "3"], id: \.self) { d in pinKey(d) }
            }
            HStack(spacing: 6) {
                ForEach(["4", "5", "6"], id: \.self) { d in pinKey(d) }
            }
            HStack(spacing: 6) {
                ForEach(["7", "8", "9"], id: \.self) { d in pinKey(d) }
            }
            HStack(spacing: 6) {
                pinKey("") // spacer
                pinKey("0")
                pinDeleteKey
            }
        }
    }

    private func pinKey(_ digit: String) -> some View {
        Button {
            guard !digit.isEmpty, pinFocusIndex < 6 else { return }
            pinDigits[pinFocusIndex] = digit
            if pinFocusIndex < 5 { pinFocusIndex += 1 }
        } label: {
            Text(digit)
                .font(.clashGroteskMedium(size: 16))
                .foregroundColor(.white.opacity(digit.isEmpty ? 0 : 0.6))
                .frame(width: 56, height: 36)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(digit.isEmpty ? 0 : 0.03)))
        }
        .buttonStyle(.plain)
        .disabled(digit.isEmpty)
    }

    private var pinDeleteKey: some View {
        Button {
            if pinFocusIndex > 0 && pinDigits[pinFocusIndex].isEmpty {
                pinFocusIndex -= 1
            }
            pinDigits[pinFocusIndex] = ""
        } label: {
            Image(systemName: "delete.left")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 56, height: 36)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.03)))
        }
        .buttonStyle(.plain)
    }

    // ── Biometric card ──
    private var biometricCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                biometricScanVisual
                VStack(alignment: .leading, spacing: 4) {
                    Text(biometricType)
                        .font(.clashGroteskMedium(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                    Text(biometricEnabled ? "Authentication active" : "Not enabled")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                }
                Spacer()
            }

            // Vault-style toggle
            vaultToggle(label: "UNLOCK WITH \(biometricType.uppercased())", enabled: $biometricEnabled)
            vaultToggle(label: "REQUIRE FOR SENDS", enabled: .constant(biometricEnabled))
            vaultToggle(label: "REQUIRE FOR KEY REVEAL", enabled: .constant(biometricEnabled))

            if !biometricEnabled {
                Text("Enable biometric authentication for faster, more secure access to your wallet")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.25))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .background(secCardBg)
    }

    // Biometric scan visualization — concentric circles
    private var biometricScanVisual: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { ring in
                Circle()
                    .strokeBorder(
                        .white.opacity(biometricEnabled ? ridgeOpacity(ring) : 0.04),
                        lineWidth: ring == 0 ? 2 : 1
                    )
                    .frame(width: CGFloat(16 + ring * 8), height: CGFloat(16 + ring * 8))
            }
            if bioScanActive {
                Circle()
                    .strokeBorder(.white.opacity(0.2 * (1 - bioScanPhase)), lineWidth: 1)
                    .frame(width: 16 + 32 * bioScanPhase, height: 16 + 32 * bioScanPhase)
            }
            Circle()
                .fill(.white.opacity(biometricEnabled ? 0.3 : 0.08))
                .frame(width: 8, height: 8)
        }
        .frame(width: 50, height: 50)
        .onTapGesture {
            if biometricEnabled { triggerBioScan() }
        }
    }

    private func ridgeOpacity(_ ring: Int) -> Double {
        let base: [Double] = [0.30, 0.22, 0.14, 0.08]
        return base[min(ring, 3)]
    }

    // ── 2FA card ──
    private var twoFactorCard: some View {
        VStack(spacing: 12) {
            secSettingRow(icon: "lock.rotation", title: "Two-Factor Authentication",
                          detail: twoFactorEnabled ? "Enabled — TOTP" : "Not configured",
                          enabled: twoFactorEnabled)
            if show2FASetup {
                twoFASetupFlow
            } else {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        show2FASetup = true; twoFAStep = 0; twoFACode = ""
                    }
                } label: {
                    Text(twoFactorEnabled ? "RECONFIGURE 2FA" : "SET UP 2FA")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(secCardBg)
    }

    private var twoFASetupFlow: some View {
        VStack(spacing: 12) {
            if twoFAStep == 0 {
                // Show "secret key"
                VStack(spacing: 8) {
                    Text("SCAN OR ENTER KEY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.white.opacity(0.35))
                    // Mock QR placeholder
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.04))
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: "qrcode")
                                .font(.system(size: 36))
                                .foregroundColor(.white.opacity(0.15))
                        )
                    Text("HXKR-4M2N-7BPQ-VTLS")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.03)))
                }
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { twoFAStep = 1 }
                } label: {
                    Text("NEXT").font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
                }
                .buttonStyle(.plain)
            } else {
                // Enter verification code
                VStack(spacing: 8) {
                    Text("Enter the 6-digit code from your authenticator")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                    TextField("000000", text: $twoFACode)
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.06))))
                        .frame(width: 160)
                }
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        twoFactorEnabled = true
                        show2FASetup = false
                    }
                } label: {
                    Text("ACTIVATE 2FA").font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(twoFACode.count == 6 ? 0.6 : 0.25))
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .disabled(twoFACode.count != 6)
            }
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { show2FASetup = false }
            } label: {
                Text("CANCEL").font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
            }
            .buttonStyle(.plain)
        }
    }

    // ── Auto-lock card with radial dial ──
    private var autoLockCard: some View {
        VStack(spacing: 14) {
            radialDial
            Text(autoLockOptions[autoLockOption].label)
                .font(.clashGroteskBold(size: 18))
                .foregroundColor(.white.opacity(0.8))
            Text(autoLockDescription)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
            // Discrete option ticks
            autoLockTicks
        }
        .padding(16)
        .background(secCardBg)
    }

    private var autoLockDescription: String {
        switch autoLockOption {
        case 0: return "Wallet locks the moment you switch away"
        case 1: return "Wallet locks after 1 minute of inactivity"
        case 2: return "Wallet locks after 5 minutes of inactivity"
        case 3: return "Wallet locks after 15 minutes of inactivity"
        case 4: return "Wallet locks after 30 minutes of inactivity"
        case 5: return "Wallet remains unlocked until manually locked"
        default: return ""
        }
    }

    // Radial "clock" dial
    private var radialDial: some View {
        let count = autoLockOptions.count
        return ZStack {
            // Outer ring
            Circle()
                .strokeBorder(.white.opacity(0.06), lineWidth: 1.5)
                .frame(width: 120, height: 120)

            // Tick marks
            ForEach(0..<count, id: \.self) { i in
                dialTick(index: i, total: count, selected: i == autoLockOption)
            }

            // Selected indicator line from center
            selectedDialLine(total: count)

            // Center dot
            Circle()
                .fill(.white.opacity(0.3))
                .frame(width: 8, height: 8)
        }
        .frame(height: 130)
        .contentShape(Circle())
        .gesture(
            DragGesture()
                .onChanged { v in
                    let center = CGPoint(x: 60, y: 65)
                    let dx = v.location.x - center.x
                    let dy = v.location.y - center.y
                    let angle = atan2(dy, dx)
                    let normAngle = (angle + .pi / 2).truncatingRemainder(dividingBy: 2 * .pi)
                    let positiveAngle = normAngle < 0 ? normAngle + 2 * .pi : normAngle
                    let segAngle = (2 * Double.pi) / Double(count)
                    let newOpt = Int(positiveAngle / segAngle) % count
                    if newOpt != autoLockOption {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            autoLockOption = newOpt
                        }
                    }
                }
        )
    }

    private func dialTick(index: Int, total: Int, selected: Bool) -> some View {
        let angle = (2 * Double.pi / Double(total)) * Double(index) - .pi / 2
        let r: CGFloat = 52
        let x = r * CGFloat(cos(angle))
        let y = r * CGFloat(sin(angle))
        return VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(selected ? 0.5 : 0.15))
                .frame(width: selected ? 3 : 2, height: selected ? 10 : 6)
                .rotationEffect(.radians(angle + .pi / 2))
        }
        .offset(x: x, y: y)
    }

    private func selectedDialLine(total: Int) -> some View {
        let angle = (2 * Double.pi / Double(total)) * Double(autoLockOption) - .pi / 2
        let length: CGFloat = 40
        return Path { p in
            p.move(to: CGPoint(x: 60, y: 65))
            p.addLine(to: CGPoint(
                x: 60 + length * CGFloat(cos(angle)),
                y: 65 + length * CGFloat(sin(angle))
            ))
        }
        .stroke(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        .frame(width: 120, height: 130)
    }

    private var autoLockTicks: some View {
        HStack(spacing: 0) {
            ForEach(0..<autoLockOptions.count, id: \.self) { i in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { autoLockOption = i }
                } label: {
                    Text(autoLockOptions[i].label)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(i == autoLockOption ? 0.6 : 0.2))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Transaction Security
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var transactionSecuritySection: some View {
        VStack(spacing: 16) {
            secSectionLabel("CONFIRMATION LAYERS")
            txLayersCard
            secSectionLabel("PHISHING PROTECTION")
            phishingCard
        }
    }

    // ── Layered shields around a tx icon ──
    private var txLayersCard: some View {
        VStack(spacing: 16) {
            txShieldsVisual
            txLevelOptions
        }
        .padding(16)
        .background(secCardBg)
    }

    private var txShieldsVisual: some View {
        ZStack {
            // Layer 3: Multisig (outermost)
            shieldLayer(index: 3, sides: 8, size: 62, active: txConfirmLevel >= 3)
            // Layer 2: Passkey
            shieldLayer(index: 2, sides: 6, size: 46, active: txConfirmLevel >= 2)
            // Layer 1: Threshold
            shieldLayer(index: 1, sides: 5, size: 32, active: txConfirmLevel >= 1)
            // Center: Always confirm (core)
            ZStack {
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 20, height: 20)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .frame(height: 140)
    }

    private func shieldLayer(index: Int, sides: Int, size: CGFloat, active: Bool) -> some View {
        RegularPolygon(sides: sides)
            .stroke(.white.opacity(active ? 0.25 : 0.06), style: StrokeStyle(lineWidth: active ? 1.5 : 1, dash: active ? [] : [4, 3]))
            .frame(width: size, height: size)
    }

    private var txLevelOptions: some View {
        VStack(spacing: 8) {
            txLevelRow(level: 0, label: "ALWAYS CONFIRM", desc: "Every transaction requires approval")
            txLevelRow(level: 1, label: "THRESHOLD CONFIRM", desc: "Confirm transactions over amount")
            if txConfirmLevel >= 1 {
                txThresholdInput(label: "Confirm threshold", value: $txThreshold)
            }
            txLevelRow(level: 2, label: "PASSKEY FOR LARGE", desc: "Biometric for high-value sends")
            if txConfirmLevel >= 2 {
                txThresholdInput(label: "Passkey threshold", value: $passkeyThreshold)
            }
            txLevelRow(level: 3, label: "MULTISIG REQUIRED", desc: "Co-signer approval needed")
        }
    }

    private func txLevelRow(level: Int, label: String, desc: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                txConfirmLevel = level
            }
        } label: {
            HStack(spacing: 10) {
                // Geometric selection indicator
                ZStack {
                    RegularPolygon(sides: level + 3)
                        .strokeBorder(.white.opacity(txConfirmLevel >= level ? 0.35 : 0.10), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    if txConfirmLevel >= level {
                        RegularPolygon(sides: level + 3)
                            .fill(.white.opacity(0.15))
                            .frame(width: 10, height: 10)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(txConfirmLevel >= level ? 0.6 : 0.3))
                    Text(desc)
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.25))
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func txThresholdInput(label: String, value: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
            Spacer()
            HStack(spacing: 2) {
                Text("$")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                TextField("0", text: value)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .textFieldStyle(.plain)
                    .frame(width: 60)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.06))))
        }
        .padding(.leading, 28)
    }

    // ── Phishing ──
    private var phishingCard: some View {
        VStack(spacing: 10) {
            vaultToggle(label: "DOMAIN BLACKLIST CHECK", enabled: $phishingEnabled)
            vaultToggle(label: "TX SIMULATION WARNINGS", enabled: $txSimulation)
            Text("Screens transactions against known malicious contracts and simulates outcomes before signing")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.25))
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .background(secCardBg)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Access (Address Book + Sessions)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var accessSection: some View {
        VStack(spacing: 16) {
            secSectionLabel("ADDRESS BOOK")
            addressBookCard
            secSectionLabel("ACTIVE SESSIONS")
            sessionsCard
        }
    }

    // ── Address book ──
    private var addressBookCard: some View {
        VStack(spacing: 10) {
            ForEach(savedAddresses) { addr in
                addressRow(addr)
            }
            if showAddAddress {
                addAddressForm
            }
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showAddAddress.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showAddAddress ? "minus" : "plus")
                        .font(.system(size: 10))
                    Text(showAddAddress ? "CANCEL" : "ADD ADDRESS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.4))
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(secCardBg)
    }

    private func addressRow(_ addr: SecAddress) -> some View {
        HStack(spacing: 10) {
            // Whitelist indicator
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.white.opacity(addr.whitelisted ? 0.30 : 0.08), lineWidth: 1)
                    .frame(width: 16, height: 16)
                if addr.whitelisted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(addr.label)
                    .font(.clashGroteskMedium(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                Text(addr.truncated)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }
            Spacer()
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    savedAddresses.removeAll { $0.id == addr.id }
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.2))
            }
            .buttonStyle(.plain)
        }
    }

    private var addAddressForm: some View {
        VStack(spacing: 8) {
            TextField("Label", text: $newAddrLabel)
                .font(.system(size: 11)).foregroundColor(.white.opacity(0.7))
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.06))))
            TextField("Address (0x...)", text: $newAddrValue)
                .font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.06))))
            HStack {
                vaultToggle(label: "WHITELIST", enabled: $newAddrWhitelist)
                Spacer()
                Button {
                    guard !newAddrLabel.isEmpty, !newAddrValue.isEmpty else { return }
                    let addr = SecAddress(id: UUID().uuidString, label: newAddrLabel,
                                          address: newAddrValue, whitelisted: newAddrWhitelist)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        savedAddresses.append(addr)
                        newAddrLabel = ""; newAddrValue = ""; newAddrWhitelist = false
                        showAddAddress = false
                    }
                } label: {
                    Text("SAVE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.04)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ── Sessions ──
    private var sessionsCard: some View {
        VStack(spacing: 10) {
            ForEach(activeSessions) { session in
                sessionRow(session)
            }
            if !activeSessions.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        activeSessions.removeAll()
                    }
                } label: {
                    Text("REVOKE ALL SESSIONS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(secCardBg)
    }

    private func sessionRow(_ s: SecSession) -> some View {
        HStack(spacing: 10) {
            Image(systemName: s.icon)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.device)
                    .font(.clashGroteskMedium(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                Text(s.location + " · " + s.lastSeen)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
            }
            Spacer()
            if s.isCurrent {
                Text("THIS")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(0.06)))
            } else {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        activeSessions.removeAll { $0.id == s.id }
                    }
                } label: {
                    Text("REVOKE")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Audit Section
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var auditSection: some View {
        VStack(spacing: 16) {
            secSectionLabel("SECURITY TIMELINE")
            auditTimeline
            secSectionLabel("ACTIONS")
            auditActions
        }
    }

    // ── Timeline ──
    private var auditTimeline: some View {
        VStack(spacing: 0) {
            ForEach(Array(auditLog.enumerated()), id: \.element.id) { index, event in
                auditTimelineRow(event: event, isLast: index == auditLog.count - 1)
            }
        }
        .padding(16)
        .background(secCardBg)
    }

    private func auditTimelineRow(event: SecAuditEvent, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Timeline line + marker
            VStack(spacing: 0) {
                auditMarker(severity: event.severity)
                if !isLast {
                    Rectangle()
                        .fill(.white.opacity(0.06))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.clashGroteskMedium(size: 12))
                    .foregroundColor(.white.opacity(opacityForSeverity(event.severity)))
                if let detail = event.detail {
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))
                }
                Text(event.timestamp)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
            }
            Spacer()
        }
        .padding(.bottom, isLast ? 0 : 14)
    }

    private func auditMarker(severity: Int) -> some View {
        let size: CGFloat = severity >= 3 ? 12 : (severity >= 2 ? 10 : 8)
        let fill: Double = severity >= 3 ? 0.35 : (severity >= 2 ? 0.20 : 0.10)
        let border: Double = severity >= 3 ? 0.45 : (severity >= 2 ? 0.25 : 0.15)
        return ZStack {
            Circle()
                .fill(.white.opacity(fill))
                .frame(width: size, height: size)
            Circle()
                .strokeBorder(.white.opacity(border), lineWidth: severity >= 3 ? 1.5 : 1)
                .frame(width: size, height: size)
        }
    }

    private func opacityForSeverity(_ severity: Int) -> Double {
        severity >= 3 ? 0.8 : (severity >= 2 ? 0.6 : 0.5)
    }

    private var auditActions: some View {
        HStack(spacing: 10) {
            secActionBtn(icon: "arrow.down.doc", label: "EXPORT LOG") { }
            secActionBtn(icon: "trash", label: "CLEAR LOG") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { auditLog.removeAll() }
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Shared Components
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func secSectionLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
                .tracking(1)
            Spacer()
        }
    }

    private func secSettingRow(icon: String, title: String, detail: String, enabled: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(enabled ? 0.06 : 0.03))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(enabled ? 0.4 : 0.15))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.clashGroteskMedium(size: 13))
                    .foregroundColor(.white.opacity(0.8))
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.35))
            }
            Spacer()
            // Status dot
            Circle()
                .fill(.white.opacity(enabled ? 0.35 : 0.08))
                .frame(width: 6, height: 6)
        }
    }

    // Vault-style toggle — geometric, not standard  
    private func vaultToggle(label: String, enabled: Binding<Bool>) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                enabled.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                // Vault bolt — slides left/right
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.04))
                        .frame(width: 32, height: 16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                        )
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(enabled.wrappedValue ? 0.35 : 0.10))
                        .frame(width: 14, height: 12)
                        .offset(x: enabled.wrappedValue ? 7 : -7)
                }
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(enabled.wrappedValue ? 0.5 : 0.25))
                    .tracking(0.5)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private var secCardBg: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(.white.opacity(0.025))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.05), lineWidth: 1))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Actions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func dismissOverlay() {
        cancelHoldVerify()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            cardScale = 0.95; contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isPresented = false
        }
    }

    private func beginHoldVerify() {
        guard !holdingVerify else { return }
        holdingVerify = true; holdVerifyProgress = 0
        let interval: TimeInterval = 0.03
        let totalDuration: TimeInterval = 1.5
        let increment = CGFloat(interval / totalDuration)
        holdVerifyTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak holdVerifyTimer] _ in
            DispatchQueue.main.async {
                holdVerifyProgress += increment
                if holdVerifyProgress >= 1.0 {
                    holdVerifyTimer?.invalidate()
                    self.holdVerifyTimer = nil
                    self.holdingVerify = false
                    // Simulate verification
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        passwordStep = .newPassword
                    }
                }
            }
        }
    }

    private func cancelHoldVerify() {
        holdVerifyTimer?.invalidate()
        holdVerifyTimer = nil
        withAnimation(.easeOut(duration: 0.2)) { holdVerifyProgress = 0 }
        holdingVerify = false
    }

    private func triggerBioScan() {
        bioScanActive = true; bioScanPhase = 0
        withAnimation(.easeOut(duration: 1.0)) { bioScanPhase = 1 }
        scheduleAfter(1.0) { bioScanActive = false; bioScanPhase = 0 }
    }

    private func scheduleAfter(_ delay: Double, action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            DispatchQueue.main.async { action() }
        }
    }

    private func startAnimations() {
        withAnimation(.linear(duration: 6.0).repeatForever(autoreverses: false)) { silkPhase = 1.5 }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Mock Data
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func loadMockData() {
        savedAddresses = [
            SecAddress(id: "a1", label: "Hardware Cold Storage", address: "0x742d35Cc6634C0532925a3b844Bc9e7595f2bD18", whitelisted: true),
            SecAddress(id: "a2", label: "Exchange Deposit", address: "0x8Ba1f109551bD432803012645Ac136d9Fb62", whitelisted: false),
            SecAddress(id: "a3", label: "DeFi Treasury", address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh", whitelisted: true),
            SecAddress(id: "a4", label: "Team Multisig", address: "0xdAC17F958D2ee523a2206206994597C13D831ec7", whitelisted: true)
        ]

        activeSessions = [
            SecSession(id: "s1", device: "MacBook Pro 16\"", location: "Berlin, DE", lastSeen: "Active now", icon: "laptopcomputer", isCurrent: true),
            SecSession(id: "s2", device: "iPhone 15 Pro", location: "Berlin, DE", lastSeen: "2h ago", icon: "iphone", isCurrent: false),
            SecSession(id: "s3", device: "iPad Air", location: "Munich, DE", lastSeen: "3d ago", icon: "ipad", isCurrent: false)
        ]

        auditLog = [
            SecAuditEvent(id: "e1", title: "Failed Login Attempt", detail: "Incorrect password — 3 attempts", timestamp: "2026-02-24 09:14 UTC", severity: 3),
            SecAuditEvent(id: "e2", title: "Password Changed", detail: nil, timestamp: "2026-02-23 18:30 UTC", severity: 2),
            SecAuditEvent(id: "e3", title: "Biometric Enabled", detail: "Touch ID activated for wallet unlock", timestamp: "2026-02-23 18:28 UTC", severity: 1),
            SecAuditEvent(id: "e4", title: "Large Transaction", detail: "Sent 2.5 ETH to 0x742d...bD18", timestamp: "2026-02-22 14:05 UTC", severity: 2),
            SecAuditEvent(id: "e5", title: "New Device Connected", detail: "iPhone 15 Pro — Berlin, DE", timestamp: "2026-02-21 10:45 UTC", severity: 2),
            SecAuditEvent(id: "e6", title: "Session Started", detail: "MacBook Pro — Safari 18.3", timestamp: "2026-02-21 10:40 UTC", severity: 1),
            SecAuditEvent(id: "e7", title: "2FA Disabled", detail: "Two-factor authentication was deactivated", timestamp: "2026-02-20 08:12 UTC", severity: 3),
            SecAuditEvent(id: "e8", title: "Address Whitelisted", detail: "DeFi Treasury added to whitelist", timestamp: "2026-02-19 16:30 UTC", severity: 1),
            SecAuditEvent(id: "e9", title: "Auto-Lock Changed", detail: "Changed from 15 min to 5 min", timestamp: "2026-02-18 11:20 UTC", severity: 1),
            SecAuditEvent(id: "e10", title: "Phishing Alert Blocked", detail: "Suspicious contract interaction prevented", timestamp: "2026-02-17 22:05 UTC", severity: 3)
        ]
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Models
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct SecAddress: Identifiable {
    let id: String
    let label: String
    let address: String
    let whitelisted: Bool

    var truncated: String {
        if address.count > 16 {
            return String(address.prefix(8)) + "..." + String(address.suffix(6))
        }
        return address
    }
}

struct SecSession: Identifiable {
    let id: String
    let device: String
    let location: String
    let lastSeen: String
    let icon: String
    let isCurrent: Bool
}

struct SecAuditEvent: Identifiable {
    let id: String
    let title: String
    let detail: String?
    let timestamp: String
    let severity: Int  // 1=info, 2=notable, 3=critical
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Regular Polygon Shape
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct RegularPolygon: InsettableShape {
    let sides: Int
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - insetAmount
        var path = Path()
        for i in 0..<sides {
            let angle = (2 * Double.pi / Double(sides)) * Double(i) - .pi / 2
            let pt = CGPoint(x: center.x + radius * CGFloat(cos(angle)),
                             y: center.y + radius * CGFloat(sin(angle)))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> RegularPolygon {
        RegularPolygon(sides: sides, insetAmount: insetAmount + amount)
    }
}
