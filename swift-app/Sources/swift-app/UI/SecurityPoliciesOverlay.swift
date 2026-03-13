import SwiftUI
#if os(macOS)
import AppKit
#endif

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Security Policies Overlay
// Fortress-grade policy command center.
// Concentric shield rings, arc limit controls,
// 24-hour clock face, mechanical lockdown switch,
// geometric violation pulses.
// Monochrome. Monumental. Unbreachable.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// MARK: - Policy Models

struct SpPolicy: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let icon: String
    var isEnabled: Bool
    let category: SpPolicyCategory
}

enum SpPolicyCategory: String {
    case transaction = "TRANSACTION"
    case access      = "ACCESS"
    case time        = "TIME"
    case emergency   = "EMERGENCY"
}

struct SpViolation: Identifiable {
    let id = UUID()
    let action: String
    let policy: String
    let outcome: String
    let icon: String
    let date: Date
}

// MARK: - Main Overlay

struct SecurityPoliciesOverlay: View {
    @Binding var isPresented: Bool

    // ── Section nav ──
    @State private var activeSection: SpSection = .overview

    enum SpSection: String, CaseIterable {
        case overview    = "OVERVIEW"
        case limits      = "LIMITS"
        case access      = "ACCESS"
        case time        = "TIME"
        case lockdown    = "LOCKDOWN"
        case violations  = "LOG"
    }

    // ── Transaction limits ──
    @State private var dailyLimit: Double = 5000
    @State private var weeklyLimit: Double = 25000
    @State private var perTxLimit: Double = 10000
    @State private var monthlyLimit: Double = 100000
    @State private var dailyUsed: Double = 1250
    @State private var weeklyUsed: Double = 8400
    @State private var monthlyUsed: Double = 32000
    @State private var limitsEnforced: Bool = true
    @State private var limitAction: Int = 0 // 0=block, 1=require auth, 2=notify

    // ── Withdrawal restrictions ──
    @State private var highValueThreshold: Double = 10000
    @State private var confirmationDelay: Int = 1 // 0=none, 1=1h, 2=24h, 3=7d
    @State private var requireBiometric: Bool = true
    @State private var requireWhitelist: Bool = true

    // ── Velocity ──
    @State private var maxTxPerHour: Int = 10
    @State private var cooldownSeconds: Int = 30
    @State private var burstAllowance: Int = 3
    @State private var velocityEnforced: Bool = true

    // ── Access / Whitelist ──
    @State private var whitelistEnforced: Bool = true
    @State private var whitelistBypassAmount: Double = 50
    @State private var approvalDelay: Int = 1 // 0=immediate, 1=24h, 2=multisig

    // ── Geographic ──
    @State private var blockVPN: Bool = false
    @State private var blockTor: Bool = false

    // ── Time-based ──
    @State private var timeRestrictionEnabled: Bool = true
    @State private var allowedStartHour: Int = 9
    @State private var allowedEndHour: Int = 18
    @State private var blockWeekends: Bool = false

    // ── Emergency lockdown ──
    @State private var lockdownActive: Bool = false
    @State private var lockdownHoldProgress: CGFloat = 0
    @State private var isHoldingLockdown: Bool = false
    @State private var autoLockOnFailedAuth: Bool = true
    @State private var autoLockThreshold: Int = 5

    // ── Multi-approval ──
    @State private var requireMultiApproval: Bool = true
    @State private var recoveryDelay: Int = 24 // hours
    @State private var policyChangeDelay: Int = 6 // hours

    // ── Violations ──
    @State private var violations: [SpViolation] = []

    // ── Animation ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var silkPhase: CGFloat = 0
    @State private var shieldPulse: CGFloat = 0

    // ── Hover ──
    @State private var closeHovered: Bool = false

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Body
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture { dismissOverlay() }

            mainCard
        }
        .background(
            EscapeKeyHandler(isPresented: $isPresented, onEscape: dismissOverlay)
        )
        .onAppear {
            loadMockViolations()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardScale = 1; contentOpacity = 1
            }
            withAnimation(.linear(duration: 6.0).repeatForever(autoreverses: false)) {
                silkPhase = 1.5
            }
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                shieldPulse = 1
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Card Shell
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var mainCard: some View {
        VStack(spacing: 0) {
            spHeader
            spSectionPicker
            spSectionContent
        }
        .frame(width: 460, height: 680)
        .background(spCardBg)
        .overlay(spCardStroke)
        .shadow(color: .black.opacity(0.5), radius: 50, y: 25)
        .scaleEffect(cardScale)
        .opacity(contentOpacity)
    }

    private var spCardBg: some View {
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

    private var spCardStroke: some View {
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

    private var spHeader: some View {
        ZStack {
            Text("SECURITY POLICIES")
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

    private var spSectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(SpSection.allCases, id: \.self) { sec in
                    spTabButton(sec)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 8)
    }

    private func spTabButton(_ sec: SpSection) -> some View {
        let selected = activeSection == sec
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { activeSection = sec }
        } label: {
            VStack(spacing: 5) {
                Text(sec.rawValue)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(selected ? 0.8 : 0.3))
                    .padding(.horizontal, 6)
                RoundedRectangle(cornerRadius: 1)
                    .fill(.white.opacity(selected ? 0.4 : 0))
                    .frame(height: 1.5)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Section Router
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var spSectionContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                switch activeSection {
                case .overview:   overviewContent
                case .limits:     limitsContent
                case .access:     accessContent
                case .time:       timeContent
                case .lockdown:   lockdownContent
                case .violations: violationsContent
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Overview (Shield Visualization)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var overviewContent: some View {
        VStack(spacing: 18) {
            shieldVisualization
            postureStats
            spLabel("ACTIVE POLICIES")
            activePoliciesList
        }
    }

    // Concentric shield rings — each ring = a category of protection
    private var shieldVisualization: some View {
        ZStack {
            // 5 concentric rings
            ForEach(0..<5, id: \.self) { i in
                shieldRing(index: i)
            }
            // Center lock
            VStack(spacing: 4) {
                Image(systemName: lockdownActive ? "lock.fill" : "shield.checkered")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(.white.opacity(lockdownActive ? 0.55 : 0.35))
                Text(lockdownActive ? "LOCKED" : protectionLabel)
                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.25))
            }
        }
        .frame(height: 150)
    }

    private func shieldRing(index: Int) -> some View {
        let size: CGFloat = CGFloat(40 + index * 18)
        let active = isRingActive(index)
        let op = active ? ringOpacity(index) : 0.03
        let width: CGFloat = active ? ringWidth(index) : 0.5
        return Circle()
            .trim(from: 0, to: active ? 1.0 : ringBrokenTrim(index))
            .stroke(
                .white.opacity(op),
                style: StrokeStyle(lineWidth: width, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(Double(index) * 22 - 90))
    }

    private func isRingActive(_ i: Int) -> Bool {
        switch i {
        case 0: return limitsEnforced
        case 1: return whitelistEnforced
        case 2: return timeRestrictionEnabled
        case 3: return velocityEnforced
        case 4: return requireMultiApproval
        default: return false
        }
    }

    private func ringOpacity(_ i: Int) -> Double {
        [0.30, 0.24, 0.18, 0.13, 0.09][min(i, 4)]
    }

    private func ringWidth(_ i: Int) -> CGFloat {
        i == 0 ? 2.5 : (i < 3 ? 1.5 : 1.0)
    }

    private func ringBrokenTrim(_ i: Int) -> CGFloat {
        [0.3, 0.5, 0.15, 0.4, 0.25][min(i, 4)]
    }

    private var protectionLabel: String {
        let count = activePolicyCount
        if count >= 8 { return "MAXIMUM" }
        if count >= 5 { return "STRONG" }
        if count >= 3 { return "MODERATE" }
        return "MINIMAL"
    }

    private var activePolicyCount: Int {
        var c = 0
        if limitsEnforced { c += 1 }
        if whitelistEnforced { c += 1 }
        if timeRestrictionEnabled { c += 1 }
        if velocityEnforced { c += 1 }
        if requireMultiApproval { c += 1 }
        if requireBiometric { c += 1 }
        if requireWhitelist { c += 1 }
        if autoLockOnFailedAuth { c += 1 }
        if blockVPN { c += 1 }
        if blockTor { c += 1 }
        return c
    }

    private var postureStats: some View {
        HStack(spacing: 14) {
            spStatPill(value: "\(activePolicyCount)", label: "ACTIVE")
            spStatPill(value: "\(violations.count)", label: "VIOLATIONS")
            spStatPill(value: lockdownActive ? "ON" : "OFF", label: "LOCKDOWN")
            Spacer()
        }
    }

    private func spStatPill(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.50))
            Text(label)
                .font(.system(size: 6, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.18))
        }
    }

    private var activePoliciesList: some View {
        VStack(spacing: 4) {
            policyRow(name: "Transaction Limits", enabled: limitsEnforced, icon: "chart.bar")
            policyRow(name: "Whitelist Enforcement", enabled: whitelistEnforced, icon: "checklist")
            policyRow(name: "Time Restrictions", enabled: timeRestrictionEnabled, icon: "clock")
            policyRow(name: "Velocity Limits", enabled: velocityEnforced, icon: "speedometer")
            policyRow(name: "Multi-Approval", enabled: requireMultiApproval, icon: "person.2")
            policyRow(name: "Biometric Auth", enabled: requireBiometric, icon: "faceid")
            policyRow(name: "Auto-Lockdown", enabled: autoLockOnFailedAuth, icon: "lock.shield")
            policyRow(name: "Block VPN", enabled: blockVPN, icon: "network.slash")
            policyRow(name: "Block Tor", enabled: blockTor, icon: "globe")
        }
    }

    private func policyRow(name: String, enabled: Bool, icon: String) -> some View {
        HStack(spacing: 10) {
            // Status indicator — geometric: filled circle = active, ring = inactive
            ZStack {
                Circle()
                    .fill(.white.opacity(enabled ? 0.12 : 0.0))
                    .frame(width: 22, height: 22)
                Circle()
                    .strokeBorder(.white.opacity(enabled ? 0.20 : 0.06), lineWidth: 1)
                    .frame(width: 22, height: 22)
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(enabled ? 0.40 : 0.12))
            }

            Text(name)
                .font(.system(size: 10, weight: enabled ? .bold : .medium))
                .foregroundColor(.white.opacity(enabled ? 0.50 : 0.20))

            Spacer()

            Text(enabled ? "ENFORCED" : "OFF")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(enabled ? 0.30 : 0.12))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(enabled ? 0.025 : 0.01))
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Transaction Limits
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var limitsContent: some View {
        VStack(spacing: 16) {
            spLabel("TRANSACTION LIMITS")
            spToggleRow(label: "ENFORCE LIMITS", isOn: $limitsEnforced)
                .padding(14)
                .background(spTileBg)

            // Limit arcs
            limitArcCard(title: "DAILY LIMIT", limit: $dailyLimit, used: dailyUsed, max: 50000, step: 1000)
            limitArcCard(title: "WEEKLY LIMIT", limit: $weeklyLimit, used: weeklyUsed, max: 200000, step: 5000)
            limitArcCard(title: "PER-TRANSACTION", limit: $perTxLimit, used: 0, max: 50000, step: 1000)
            limitArcCard(title: "MONTHLY LIMIT", limit: $monthlyLimit, used: monthlyUsed, max: 500000, step: 10000)

            spLabel("WHEN LIMIT REACHED")
            limitActionPicker

            spLabel("WITHDRAWAL RESTRICTIONS")
            withdrawalCard
        }
    }

    // Arc-based limit control — shows usage vs limit on a semicircular arc
    private func limitArcCard(title: String, limit: Binding<Double>, used: Double, max: Double, step: Double) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.25))
                Spacer()
                Text("$\(formatAmount(limit.wrappedValue))")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
            }

            // Arc visualization
            ZStack {
                // Background arc
                SpArc()
                    .stroke(.white.opacity(0.04), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(height: 50)

                // Limit arc (full extent)
                SpArc()
                    .trim(from: 0, to: CGFloat(limit.wrappedValue / max))
                    .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(height: 50)

                // Usage arc
                if used > 0 {
                    SpArc()
                        .trim(from: 0, to: CGFloat(min(used / max, limit.wrappedValue / max)))
                        .stroke(.white.opacity(0.30), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(height: 50)
                }

                // Usage label
                if used > 0 {
                    VStack(spacing: 1) {
                        Text("$\(formatAmount(used))")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                        Text("USED")
                            .font(.system(size: 5, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.15))
                    }
                    .offset(y: 8)
                }
            }
            .frame(height: 60)

            // Slider
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        limit.wrappedValue = Swift.max(0, limit.wrappedValue - step)
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.25))
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.04)))
                }
                .buttonStyle(.plain)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white.opacity(0.04))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white.opacity(0.15))
                            .frame(width: geo.size.width * CGFloat(limit.wrappedValue / max))
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let pct = Swift.min(Swift.max(value.location.x / geo.size.width, 0), 1)
                                let raw = Double(pct) * max
                                limit.wrappedValue = (raw / step).rounded() * step
                            }
                    )
                }
                .frame(height: 6)

                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        limit.wrappedValue = Swift.min(max, limit.wrappedValue + step)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.25))
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.04)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(spTileBg)
    }

    private var limitActionPicker: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                let labels = ["BLOCK", "REQUIRE AUTH", "NOTIFY"]
                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) { limitAction = i }
                } label: {
                    Text(labels[i])
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(limitAction == i ? 0.55 : 0.20))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.white.opacity(limitAction == i ? 0.06 : 0.02))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(.white.opacity(limitAction == i ? 0.10 : 0.03))
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // Withdrawal restrictions card
    private var withdrawalCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("HIGH-VALUE THRESHOLD")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.20))
                    .tracking(0.5)
                Spacer()
                Text("$\(formatAmount(highValueThreshold))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
            }

            Divider().background(.white.opacity(0.04))
            spToggleRow(label: "REQUIRE BIOMETRIC", isOn: $requireBiometric)
            Divider().background(.white.opacity(0.04))
            spToggleRow(label: "REQUIRE WHITELISTED DEST", isOn: $requireWhitelist)
            Divider().background(.white.opacity(0.04))

            HStack {
                Text("CONFIRMATION DELAY")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.20))
                    .tracking(0.5)
                Spacer()
            }
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { i in
                    let labels = ["NONE", "1 HOUR", "24 HOURS", "7 DAYS"]
                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) { confirmationDelay = i }
                    } label: {
                        Text(labels[i])
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(confirmationDelay == i ? 0.50 : 0.18))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.white.opacity(confirmationDelay == i ? 0.06 : 0.02))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(spTileBg)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Access Control
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var accessContent: some View {
        VStack(spacing: 16) {
            spLabel("WHITELIST ENFORCEMENT")
            whitelistCard

            spLabel("VELOCITY LIMITS")
            velocityCard

            spLabel("GEOGRAPHIC RESTRICTIONS")
            geoCard

            spLabel("MULTI-APPROVAL")
            multiApprovalCard

            spLabel("RECOVERY DELAYS")
            recoveryCard
        }
    }

    private var whitelistCard: some View {
        VStack(spacing: 12) {
            spToggleRow(label: "ENFORCE WHITELIST", isOn: $whitelistEnforced)
            Divider().background(.white.opacity(0.04))

            // Bypass threshold
            HStack {
                Text("BYPASS FOR AMOUNTS UNDER")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.20))
                    .tracking(0.5)
                Spacer()
                Text("$\(formatAmount(whitelistBypassAmount))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
            }

            Divider().background(.white.opacity(0.04))

            // Approval process
            HStack {
                Text("APPROVAL PROCESS")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.20))
                    .tracking(0.5)
                Spacer()
            }
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    let labels = ["IMMEDIATE", "24H DELAY", "MULTI-SIG"]
                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) { approvalDelay = i }
                    } label: {
                        Text(labels[i])
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(approvalDelay == i ? 0.50 : 0.18))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.white.opacity(approvalDelay == i ? 0.06 : 0.02))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Protective explanation
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.15))
                    .padding(.top, 1)
                Text("Whitelist enforcement prevents sending to unverified addresses. Attackers cannot redirect funds to unknown destinations.")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.18))
                    .lineSpacing(2)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(spTileBg)
    }

    private var velocityCard: some View {
        VStack(spacing: 12) {
            spToggleRow(label: "ENFORCE VELOCITY LIMITS", isOn: $velocityEnforced)
            Divider().background(.white.opacity(0.04))

            spValueRow(label: "MAX TX PER HOUR", value: "\(maxTxPerHour)")
            spValueRow(label: "COOLDOWN", value: "\(cooldownSeconds)s")
            spValueRow(label: "BURST ALLOWANCE", value: "\(burstAllowance) tx")

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "speedometer")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.15))
                    .padding(.top, 1)
                Text("Velocity limits prevent wallet-draining attacks where an attacker sends many rapid transactions before you can respond.")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.18))
                    .lineSpacing(2)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(spTileBg)
    }

    private var geoCard: some View {
        VStack(spacing: 12) {
            spToggleRow(label: "BLOCK VPN TRANSACTIONS", isOn: $blockVPN)
            Divider().background(.white.opacity(0.04))
            spToggleRow(label: "BLOCK TOR TRANSACTIONS", isOn: $blockTor)
            Divider().background(.white.opacity(0.04))

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.15))
                    .padding(.top, 1)
                Text("Enabling geographic restrictions reduces your privacy. Your network information must be analyzed to enforce these rules. Consider the trade-off carefully.")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.18))
                    .lineSpacing(2)
            }
        }
        .padding(14)
        .background(spTileBg)
    }

    private var multiApprovalCard: some View {
        VStack(spacing: 12) {
            spToggleRow(label: "REQUIRE MULTI-APPROVAL", isOn: $requireMultiApproval)
            Divider().background(.white.opacity(0.04))

            spInfoRow(icon: "arrow.counterclockwise", title: "RECOVERY OPERATIONS", detail: "Require 2+ authentications")
            Divider().background(.white.opacity(0.04))
            spInfoRow(icon: "gearshape", title: "POLICY CHANGES", detail: "Require confirmation to modify")
            Divider().background(.white.opacity(0.04))
            spInfoRow(icon: "banknote", title: "LARGE WITHDRAWALS", detail: "Require multi-device approval")
        }
        .padding(14)
        .background(spTileBg)
    }

    private var recoveryCard: some View {
        VStack(spacing: 12) {
            spValueRow(label: "SEED PHRASE ACCESS DELAY", value: "\(recoveryDelay)h")
            Divider().background(.white.opacity(0.04))
            spValueRow(label: "POLICY CHANGE DELAY", value: "\(policyChangeDelay)h")
            Divider().background(.white.opacity(0.04))

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.15))
                    .padding(.top, 1)
                Text("Recovery delays give you time to detect and respond to unauthorized access. Even if an attacker gains entry, they cannot immediately extract sensitive data.")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.18))
                    .lineSpacing(2)
            }
        }
        .padding(14)
        .background(spTileBg)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Time-Based Policies (Clock Face)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var timeContent: some View {
        VStack(spacing: 16) {
            spLabel("TIME-BASED RESTRICTIONS")
            spToggleRow(label: "ENABLE TIME RESTRICTIONS", isOn: $timeRestrictionEnabled)
                .padding(14)
                .background(spTileBg)

            // 24-hour clock visualization
            clockFaceCard

            // Settings
            timeSettingsCard
        }
    }

    private var clockFaceCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("ALLOWED TRANSACTION HOURS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.25))
                Spacer()
            }

            // Clock face
            ZStack {
                // Outer ring
                Circle()
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                    .frame(width: 180, height: 180)

                // Hour ticks
                ForEach(0..<24, id: \.self) { hour in
                    clockTick(hour: hour)
                }

                // Allowed arc (filled)
                SpClockArc(startHour: allowedStartHour, endHour: allowedEndHour)
                    .fill(.white.opacity(timeRestrictionEnabled ? 0.08 : 0.02))
                    .frame(width: 160, height: 160)

                // Allowed arc stroke
                SpClockArc(startHour: allowedStartHour, endHour: allowedEndHour)
                    .stroke(.white.opacity(timeRestrictionEnabled ? 0.20 : 0.05), lineWidth: 2)
                    .frame(width: 160, height: 160)

                // Center
                VStack(spacing: 2) {
                    Text("\(formatHour(allowedStartHour))–\(formatHour(allowedEndHour))")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.50))
                    Text("ALLOWED")
                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.white.opacity(0.18))
                }

                // Hour labels at cardinal positions
                clockLabel(hour: 0, text: "0", xOff: 0, yOff: -98)
                clockLabel(hour: 6, text: "6", xOff: 98, yOff: 0)
                clockLabel(hour: 12, text: "12", xOff: 0, yOff: 98)
                clockLabel(hour: 18, text: "18", xOff: -98, yOff: 0)
            }
            .frame(height: 210)
        }
        .padding(14)
        .background(spTileBg)
    }

    private func clockTick(hour: Int) -> some View {
        let angle = Double(hour) / 24.0 * 360.0 - 90
        let inRange = isHourInRange(hour)
        return Rectangle()
            .fill(.white.opacity(inRange ? 0.25 : 0.06))
            .frame(width: hour % 6 == 0 ? 8 : 4, height: 1.5)
            .offset(x: 85)
            .rotationEffect(.degrees(angle))
    }

    private func clockLabel(hour: Int, text: String, xOff: CGFloat, yOff: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.20))
            .offset(x: xOff, y: yOff)
    }

    private func isHourInRange(_ hour: Int) -> Bool {
        if allowedStartHour <= allowedEndHour {
            return hour >= allowedStartHour && hour < allowedEndHour
        } else {
            return hour >= allowedStartHour || hour < allowedEndHour
        }
    }

    private var timeSettingsCard: some View {
        VStack(spacing: 12) {
            // Start hour
            HStack {
                Text("START HOUR")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.20))
                    .tracking(0.5)
                Spacer()
                HStack(spacing: 4) {
                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            allowedStartHour = (allowedStartHour - 1 + 24) % 24
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white.opacity(0.25))
                            .frame(width: 20, height: 20)
                            .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.04)))
                    }
                    .buttonStyle(.plain)

                    Text(formatHour(allowedStartHour))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.50))
                        .frame(width: 40)

                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            allowedStartHour = (allowedStartHour + 1) % 24
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white.opacity(0.25))
                            .frame(width: 20, height: 20)
                            .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.04)))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().background(.white.opacity(0.04))

            // End hour
            HStack {
                Text("END HOUR")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.20))
                    .tracking(0.5)
                Spacer()
                HStack(spacing: 4) {
                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            allowedEndHour = (allowedEndHour - 1 + 24) % 24
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white.opacity(0.25))
                            .frame(width: 20, height: 20)
                            .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.04)))
                    }
                    .buttonStyle(.plain)

                    Text(formatHour(allowedEndHour))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.50))
                        .frame(width: 40)

                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            allowedEndHour = (allowedEndHour + 1) % 24
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white.opacity(0.25))
                            .frame(width: 20, height: 20)
                            .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.04)))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().background(.white.opacity(0.04))
            spToggleRow(label: "BLOCK WEEKENDS", isOn: $blockWeekends)
        }
        .padding(14)
        .background(spTileBg)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Emergency Lockdown
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var lockdownContent: some View {
        VStack(spacing: 16) {
            spLabel("EMERGENCY LOCKDOWN")

            // Vault door visualization
            lockdownHero

            // Status
            lockdownStatusCard

            // Auto-lockdown triggers
            spLabel("AUTO-LOCKDOWN TRIGGERS")
            autoLockdownCard

            // What it does
            spLabel("LOCKDOWN EFFECTS")
            lockdownEffectsCard
        }
    }

    // Vault door — mechanical lockdown switch
    private var lockdownHero: some View {
        VStack(spacing: 16) {
            // Vault door
            ZStack {
                // Outer door frame
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.white.opacity(lockdownActive ? 0.25 : 0.06), lineWidth: 2)
                    .frame(width: 140, height: 140)

                // Inner rings (bolts)
                ForEach(0..<4, id: \.self) { i in
                    lockdownBolt(index: i)
                }

                // Handle
                VStack(spacing: 6) {
                    Image(systemName: lockdownActive ? "lock.fill" : "lock.open")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(.white.opacity(lockdownActive ? 0.55 : 0.20))
                    Text(lockdownActive ? "LOCKED DOWN" : "OPERATIONAL")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.white.opacity(lockdownActive ? 0.40 : 0.15))
                }
            }
            .frame(height: 150)

            // Hold-to-toggle button
            lockdownSwitch
        }
        .padding(14)
        .background(spTileBg)
    }

    private func lockdownBolt(index: Int) -> some View {
        let positions: [(CGFloat, CGFloat)] = [(-50, -50), (50, -50), (-50, 50), (50, 50)]
        let pos = positions[min(index, 3)]
        return ZStack {
            Circle()
                .fill(.white.opacity(lockdownActive ? 0.10 : 0.02))
                .frame(width: 16, height: 16)
            Circle()
                .strokeBorder(.white.opacity(lockdownActive ? 0.20 : 0.05), lineWidth: 1)
                .frame(width: 16, height: 16)
            // Cross pattern for bolt
            Rectangle()
                .fill(.white.opacity(lockdownActive ? 0.25 : 0.06))
                .frame(width: 8, height: 1.5)
            Rectangle()
                .fill(.white.opacity(lockdownActive ? 0.25 : 0.06))
                .frame(width: 1.5, height: 8)
        }
        .offset(x: pos.0, y: pos.1)
    }

    private var lockdownSwitch: some View {
        VStack(spacing: 8) {
            if lockdownActive {
                // Deactivate
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        lockdownActive = false
                        lockdownHoldProgress = 0
                    }
                } label: {
                    Text("DEACTIVATE LOCKDOWN")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.white.opacity(0.50))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.white.opacity(0.06))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.14)))
                        )
                }
                .buttonStyle(.plain)
            } else {
                // Hold-to-activate
                ZStack {
                    // Progress background
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.03))
                        .overlay(
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.white.opacity(0.06))
                                    .frame(width: geo.size.width * lockdownHoldProgress)
                            },
                            alignment: .leading
                        )
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.08)))

                    Text(isHoldingLockdown ? "ACTIVATING..." : "HOLD TO ACTIVATE LOCKDOWN")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.white.opacity(isHoldingLockdown ? 0.55 : 0.35))
                }
                .frame(height: 44)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in startLockdownHold() }
                        .onEnded { _ in cancelLockdownHold() }
                )
            }
        }
    }

    private var lockdownStatusCard: some View {
        VStack(spacing: 8) {
            spValueRow(label: "STATUS", value: lockdownActive ? "ACTIVE" : "INACTIVE")
            spValueRow(label: "ALL TRANSACTIONS", value: lockdownActive ? "BLOCKED" : "ALLOWED")
            spValueRow(label: "SENDING", value: lockdownActive ? "DISABLED" : "ENABLED")
            spValueRow(label: "WALLET ACCESS", value: lockdownActive ? "READ-ONLY" : "FULL")
        }
        .padding(14)
        .background(spTileBg)
    }

    private var autoLockdownCard: some View {
        VStack(spacing: 12) {
            spToggleRow(label: "AUTO-LOCK ON FAILED AUTH", isOn: $autoLockOnFailedAuth)
            Divider().background(.white.opacity(0.04))
            HStack {
                Text("FAILED ATTEMPTS THRESHOLD")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.20))
                    .tracking(0.5)
                Spacer()
                HStack(spacing: 4) {
                    ForEach([3, 5, 10], id: \.self) { n in
                        Button {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) { autoLockThreshold = n }
                        } label: {
                            Text("\(n)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(autoLockThreshold == n ? 0.50 : 0.18))
                                .frame(width: 28, height: 22)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(.white.opacity(autoLockThreshold == n ? 0.06 : 0.02))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Divider().background(.white.opacity(0.04))
            spInfoRow(icon: "exclamationmark.shield", title: "SUSPICIOUS ACTIVITY", detail: "Triggers lockdown on anomalous patterns")
            Divider().background(.white.opacity(0.04))
            spInfoRow(icon: "antenna.radiowaves.left.and.right.slash", title: "NETWORK ANOMALY", detail: "Triggers on unexpected network changes")
        }
        .padding(14)
        .background(spTileBg)
    }

    private var lockdownEffectsCard: some View {
        VStack(spacing: 8) {
            lockdownEffectRow(icon: "xmark.circle", effect: "All outgoing transactions blocked")
            lockdownEffectRow(icon: "lock.rectangle", effect: "Wallet enters read-only mode")
            lockdownEffectRow(icon: "key.slash", effect: "Signing keys temporarily sealed")
            lockdownEffectRow(icon: "bell.badge", effect: "Security alert notification sent")
            lockdownEffectRow(icon: "arrow.counterclockwise", effect: "Requires password to deactivate")
        }
        .padding(14)
        .background(spTileBg)
    }

    private func lockdownEffectRow(icon: String, effect: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.20))
                .frame(width: 16, alignment: .center)
            Text(effect)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.30))
            Spacer()
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Violations Log
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var violationsContent: some View {
        VStack(spacing: 16) {
            spLabel("POLICY VIOLATIONS")

            if violations.isEmpty {
                emptyLog
            } else {
                violationsSummary
                ForEach(violations) { v in
                    violationRow(v)
                }
            }
        }
    }

    private var emptyLog: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.white.opacity(0.20))
            Text("No violations recorded")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.20))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var violationsSummary: some View {
        HStack(spacing: 14) {
            let blocked = violations.filter { $0.outcome == "Blocked" }.count
            let warned = violations.filter { $0.outcome == "Warning" }.count
            spStatPill(value: "\(violations.count)", label: "TOTAL")
            spStatPill(value: "\(blocked)", label: "BLOCKED")
            spStatPill(value: "\(warned)", label: "WARNED")
            Spacer()
        }
    }

    private func violationRow(_ v: SpViolation) -> some View {
        HStack(spacing: 10) {
            // Alert indicator
            ZStack {
                Circle()
                    .fill(.white.opacity(v.outcome == "Blocked" ? 0.08 : 0.03))
                    .frame(width: 24, height: 24)
                Circle()
                    .strokeBorder(.white.opacity(v.outcome == "Blocked" ? 0.15 : 0.06), lineWidth: 1)
                    .frame(width: 24, height: 24)
                Image(systemName: v.icon)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(v.outcome == "Blocked" ? 0.35 : 0.15))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(v.action)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(v.policy)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.white.opacity(0.18))
                    Text(v.outcome.uppercased())
                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(v.outcome == "Blocked" ? 0.30 : 0.15))
                }
            }

            Spacer()

            Text(relativeDate(v.date))
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.white.opacity(0.12))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.04), lineWidth: 0.8)
                )
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Shared Components
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func spLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
                .tracking(1)
            Spacer()
        }
    }

    private var spTileBg: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(.white.opacity(0.025))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.05), lineWidth: 1))
    }

    private func spToggleRow(label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.30))
                .tracking(0.5)
            Spacer()
            Button {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    isOn.wrappedValue.toggle()
                }
            } label: {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(isOn.wrappedValue ? 0.12 : 0.04))
                    .frame(width: 28, height: 16)
                    .overlay(
                        Circle()
                            .fill(.white.opacity(isOn.wrappedValue ? 0.6 : 0.2))
                            .frame(width: 10, height: 10)
                            .offset(x: isOn.wrappedValue ? 7 : -7),
                        alignment: .center
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func spValueRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.20))
                .tracking(0.5)
            Spacer()
            Text(value)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.40))
        }
    }

    private func spInfoRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.18))
                .frame(width: 16, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.30))
                Text(detail)
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.18))
            }
            Spacer()
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Actions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func dismissOverlay() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            cardScale = 0.95; contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isPresented = false
        }
    }

    private func startLockdownHold() {
        guard !isHoldingLockdown else { return }
        isHoldingLockdown = true
        withAnimation(.linear(duration: 2.5)) {
            lockdownHoldProgress = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if self.isHoldingLockdown {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.lockdownActive = true
                }
            }
        }
    }

    private func cancelLockdownHold() {
        isHoldingLockdown = false
        if !lockdownActive {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                lockdownHoldProgress = 0
            }
        }
    }

    // ── Helpers ──
    private func formatAmount(_ val: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: val)) ?? "0"
    }

    private func formatHour(_ h: Int) -> String {
        let ampm = h >= 12 ? "PM" : "AM"
        let display = h % 12 == 0 ? 12 : h % 12
        return "\(display)\(ampm)"
    }

    private func relativeDate(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        return "\(Int(diff / 86400))d ago"
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Mock Data
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func loadMockViolations() {
        violations = [
            SpViolation(action: "Send 0.5 BTC to non-whitelisted address", policy: "Whitelist Enforcement", outcome: "Blocked", icon: "xmark.shield", date: Calendar.current.date(byAdding: .hour, value: -3, to: Date()) ?? Date()),
            SpViolation(action: "Transaction exceeding $12,000 daily limit", policy: "Daily Limit", outcome: "Blocked", icon: "chart.bar", date: Calendar.current.date(byAdding: .hour, value: -18, to: Date()) ?? Date()),
            SpViolation(action: "Send during restricted hours (11:42 PM)", policy: "Time Restriction", outcome: "Blocked", icon: "clock", date: Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()),
            SpViolation(action: "5 transactions in 2 minutes", policy: "Velocity Limit", outcome: "Warning", icon: "speedometer", date: Calendar.current.date(byAdding: .day, value: -4, to: Date()) ?? Date()),
            SpViolation(action: "Send $25,000 without biometric", policy: "Withdrawal Restriction", outcome: "Blocked", icon: "faceid", date: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()),
            SpViolation(action: "Modify security policy via API", policy: "Multi-Approval", outcome: "Blocked", icon: "person.2", date: Calendar.current.date(byAdding: .day, value: -12, to: Date()) ?? Date()),
        ]
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Custom Shapes
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Semi-circular arc for limit visualization
struct SpArc: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY),
            radius: rect.width / 2,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        return p
    }
}

// Clock arc for time-based policy visualization
struct SpClockArc: Shape {
    let startHour: Int
    let endHour: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let startAngle = Angle.degrees(Double(startHour) / 24.0 * 360.0 - 90)
        let endAngle = Angle.degrees(Double(endHour) / 24.0 * 360.0 - 90)

        var p = Path()
        p.move(to: center)
        p.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        p.closeSubpath()
        return p
    }
}
