import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Privacy Overlay
// Stealth-grade privacy command center.
// Concentric shield layers, Tor route branching,
// fading address nodes, UTXO building blocks,
// data-flow particle streams.
// Monumental. Monochrome. Invisible.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct PrivacyOverlay: View {
    @Binding var isPresented: Bool

    // ── Section nav ──
    @State private var activeSection: PrivSection = .overview

    enum PrivSection: String, CaseIterable {
        case overview = "STATUS"
        case connection = "CONNECTION"
        case address = "ADDRESSES"
        case transaction = "TRANSACTIONS"
        case data = "DATA"
    }

    // ── Connection privacy ──
    @State private var torEnabled: Bool = false
    @State private var vpnEnabled: Bool = false
    @State private var privateRPC: Bool = true
    @State private var disableWebRTC: Bool = true

    // ── Tor routing viz ──
    @State private var torPaths: [[CGPoint]] = []
    @State private var torAnimPhase: CGFloat = 0

    // ── Address management ──
    @State private var neverReuseAddresses: Bool = true
    @State private var autoGenerateAddresses: Bool = true
    @State private var showUsedAddresses: Bool = false
    @State private var hdPathCustom: String = "m/84'/0'/0'"

    // ── Coin control ──
    @State private var coinControlActive: Bool = true
    @State private var coinJoinEnabled: Bool = false
    @State private var consolidationWarnings: Bool = true
    @State private var dustManagement: Bool = true
    @State private var mockUTXOs: [PrivUTXO] = []
    @State private var selectedUTXOs: Set<String> = []

    // ── Transaction privacy ──
    @State private var taprootEnabled: Bool = true
    @State private var stealthAddresses: Bool = false
    @State private var randomizeTiming: Bool = true
    @State private var customFeeSelection: Bool = false

    // ── Metadata protection ──
    @State private var stripEXIF: Bool = true
    @State private var randomizeBroadcast: Bool = true

    // ── Data collection ──
    @State private var analyticsEnabled: Bool = false
    @State private var crashReports: Bool = true
    @State private var clipboardAutoClear: Bool = true
    @State private var clipboardTimer: Int = 30  // seconds

    // ── Third-party ──
    @State private var priceFeedEnabled: Bool = true
    @State private var blockExplorerEnabled: Bool = true
    @State private var fingerprintProtection: Bool = true

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
            Text("PRIVACY")
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
                ForEach(PrivSection.allCases, id: \.self) { sec in
                    privTabButton(sec)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 8)
    }

    private func privTabButton(_ sec: PrivSection) -> some View {
        let selected = activeSection == sec
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { activeSection = sec }
        } label: {
            VStack(spacing: 5) {
                Text(sec.rawValue)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(selected ? 0.8 : 0.3))
                    .padding(.horizontal, 8)
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
                case .overview: overviewContent
                case .connection: connectionContent
                case .address: addressContent
                case .transaction: transactionContent
                case .data: dataContent
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Overview (Shield Layers)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var overviewContent: some View {
        VStack(spacing: 20) {
            shieldVisualization
            privacyScoreBreakdown
        }
    }

    // Concentric shield layers — each enabled feature adds a layer
    private var shieldVisualization: some View {
        let score = computePrivacyScore()
        let layers = enabledLayerCount()
        return VStack(spacing: 12) {
            ZStack {
                // 6 concentric shield outlines
                ForEach(0..<6, id: \.self) { i in
                    shieldRing(index: i, active: i < layers)
                }
                // Center core
                VStack(spacing: 2) {
                    Text("\(score)")
                        .font(.clashGroteskBold(size: 36))
                        .foregroundColor(.white.opacity(0.85))
                    Text("PRIVACY SCORE")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.35))
                }
            }
            .frame(height: 160)

            // Status label
            Text(privacyStatusLabel(score))
                .font(.clashGroteskMedium(size: 14))
                .tracking(1)
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private func shieldRing(index: Int, active: Bool) -> some View {
        let size: CGFloat = CGFloat(30 + index * 16)
        let sides = 6 // hexagonal shields
        let dashActive: [CGFloat] = []
        let dashInactive: [CGFloat] = [5, 4]
        return PrivShieldShape(sides: sides)
            .stroke(
                .white.opacity(active ? shieldOpacity(index) : 0.04),
                style: StrokeStyle(
                    lineWidth: active ? lineWidthForRing(index) : 0.8,
                    dash: active ? dashActive : dashInactive
                )
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(Double(index) * 5))
    }

    private func shieldOpacity(_ index: Int) -> Double {
        let opacities: [Double] = [0.35, 0.28, 0.22, 0.17, 0.13, 0.10]
        return opacities[min(index, 5)]
    }

    private func lineWidthForRing(_ index: Int) -> CGFloat {
        index == 0 ? 2.5 : (index < 3 ? 1.5 : 1.0)
    }

    private var privacyScoreBreakdown: some View {
        VStack(spacing: 6) {
            privScoreRow(label: "TOR ROUTING", pts: 20, enabled: torEnabled)
            privScoreRow(label: "ADDRESS REUSE PREVENTION", pts: 15, enabled: neverReuseAddresses)
            privScoreRow(label: "COIN CONTROL", pts: 15, enabled: coinControlActive)
            privScoreRow(label: "NO ANALYTICS", pts: 10, enabled: !analyticsEnabled)
            privScoreRow(label: "PRIVATE RPC", pts: 10, enabled: privateRPC)
            privScoreRow(label: "TAPROOT", pts: 10, enabled: taprootEnabled)
            privScoreRow(label: "CLIPBOARD CLEAR", pts: 5, enabled: clipboardAutoClear)
            privScoreRow(label: "FINGERPRINT PROTECTION", pts: 5, enabled: fingerprintProtection)
            privScoreRow(label: "TIMING RANDOMIZATION", pts: 5, enabled: randomizeTiming)
            privScoreRow(label: "METADATA STRIPPED", pts: 5, enabled: stripEXIF)
        }
        .padding(14)
        .background(privCardBg)
    }

    private func privScoreRow(label: String, pts: Int, enabled: Bool) -> some View {
        HStack(spacing: 8) {
            // Geometric indicator
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                if enabled {
                    Circle()
                        .fill(.white.opacity(0.45))
                        .frame(width: 6, height: 6)
                }
            }
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(enabled ? 0.55 : 0.20))
                .tracking(0.5)
            Spacer()
            Text("+\(pts)")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(enabled ? 0.4 : 0.12))
        }
    }

    private func privacyStatusLabel(_ score: Int) -> String {
        if score >= 90 { return "MAXIMUM STEALTH" }
        if score >= 70 { return "STRONG PRIVACY" }
        if score >= 50 { return "MODERATE PRIVACY" }
        if score >= 30 { return "BASIC PRIVACY" }
        return "EXPOSED"
    }

    private func computePrivacyScore() -> Int {
        var s = 0
        if torEnabled { s += 20 }
        if neverReuseAddresses { s += 15 }
        if coinControlActive { s += 15 }
        if !analyticsEnabled { s += 10 }
        if privateRPC { s += 10 }
        if taprootEnabled { s += 10 }
        if clipboardAutoClear { s += 5 }
        if fingerprintProtection { s += 5 }
        if randomizeTiming { s += 5 }
        if stripEXIF { s += 5 }
        return min(100, s)
    }

    private func enabledLayerCount() -> Int {
        var c = 0
        if torEnabled { c += 1 }
        if neverReuseAddresses { c += 1 }
        if coinControlActive { c += 1 }
        if privateRPC { c += 1 }
        if taprootEnabled { c += 1 }
        if !analyticsEnabled { c += 1 }
        return c
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Connection Privacy
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var connectionContent: some View {
        VStack(spacing: 16) {
            privSectionLabel("TOR NETWORK")
            torCard
            privSectionLabel("VPN & NETWORK")
            vpnCard
        }
    }

    private var torCard: some View {
        VStack(spacing: 14) {
            // Tor route visualization
            torRouteVisual
            cloakToggle(label: "ROUTE THROUGH TOR", enabled: $torEnabled)
            if torEnabled {
                Text("All wallet connections are routed through the Tor network. Latency will increase by 2-5 seconds per request. Your IP address is hidden from nodes and services.")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
                    .lineSpacing(2)
            } else {
                Text("Enable Tor to hide your IP address from blockchain nodes, price feeds, and other services the wallet connects to.")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.25))
                    .lineSpacing(2)
            }
            // Latency indicator
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.2))
                Text(torEnabled ? "LATENCY: +2-5s PER REQUEST" : "LATENCY: DIRECT CONNECTION")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                Spacer()
            }
        }
        .padding(16)
        .background(privCardBg)
    }

    // Tor route branching visualization
    private var torRouteVisual: some View {
        ZStack {
            if torEnabled {
                // Branching paths from left (you) → relays → right (node)
                torBranchingPaths
            } else {
                // Single direct line
                torDirectPath
            }
            // Origin (You)
            torEndpoint(label: "YOU", x: 20)
            // Destination (Node)
            torEndpoint(label: "NODE", x: 350)
        }
        .frame(height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var torBranchingPaths: some View {
        let midY: CGFloat = 40
        return ZStack {
            // Path 1: top route through 3 relays
            torPath(points: [
                CGPoint(x: 40, y: midY),
                CGPoint(x: 110, y: midY - 22),
                CGPoint(x: 200, y: midY - 18),
                CGPoint(x: 280, y: midY - 10),
                CGPoint(x: 330, y: midY)
            ])
            // Path 2: middle route
            torPath(points: [
                CGPoint(x: 40, y: midY),
                CGPoint(x: 120, y: midY + 5),
                CGPoint(x: 210, y: midY - 5),
                CGPoint(x: 290, y: midY + 3),
                CGPoint(x: 330, y: midY)
            ])
            // Path 3: bottom route
            torPath(points: [
                CGPoint(x: 40, y: midY),
                CGPoint(x: 100, y: midY + 20),
                CGPoint(x: 190, y: midY + 25),
                CGPoint(x: 270, y: midY + 15),
                CGPoint(x: 330, y: midY)
            ])
            // Relay nodes
            ForEach(0..<3, id: \.self) { i in
                relayDot(x: [110, 200, 280][i], y: [18, 22, 30][i], midY: midY, routeIndex: i)
            }
        }
    }

    private func torPath(points: [CGPoint]) -> some View {
        Path { p in
            guard let first = points.first else { return }
            p.move(to: first)
            for pt in points.dropFirst() { p.addLine(to: pt) }
        }
        .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    private func relayDot(x: Int, y: Int, midY: CGFloat, routeIndex: Int) -> some View {
        let yOffsets: [[CGFloat]] = [[-22, -18, -10], [5, -5, 3], [20, 25, 15]]
        let relayY = midY + (routeIndex < yOffsets.count ? yOffsets[routeIndex][min(y < 25 ? 0 : 1, 2)] : 0)
        return Circle()
            .fill(.white.opacity(0.15))
            .frame(width: 5, height: 5)
            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
            .offset(x: CGFloat(x) - 185, y: relayY - 40)
    }

    private var torDirectPath: some View {
        Path { p in
            p.move(to: CGPoint(x: 40, y: 40))
            p.addLine(to: CGPoint(x: 330, y: 40))
        }
        .stroke(.white.opacity(0.08), style: StrokeStyle(lineWidth: 1))
    }

    private func torEndpoint(label: String, x: CGFloat) -> some View {
        VStack(spacing: 3) {
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(.white.opacity(0.20), lineWidth: 1))
            Text(label)
                .font(.system(size: 6, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
        }
        .offset(x: x - 185, y: 0)
    }

    private var vpnCard: some View {
        VStack(spacing: 10) {
            cloakToggle(label: "VPN INTEGRATION", enabled: $vpnEnabled)
            Text("Connect through your system VPN. Requires external VPN to be configured at the OS level.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.25))
                .lineSpacing(2)

            Divider().background(.white.opacity(0.06))

            cloakToggle(label: "PRIVATE RPC NODES ONLY", enabled: $privateRPC)
            Text("Use only user-configured or privacy-focused blockchain nodes. Prevents data leakage to default public endpoints.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.25))
                .lineSpacing(2)

            Divider().background(.white.opacity(0.06))

            cloakToggle(label: "DISABLE WebRTC", enabled: $disableWebRTC)
            Text("Prevents IP address leakage through WebRTC if the wallet uses embedded web content.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.20))
                .lineSpacing(2)
        }
        .padding(16)
        .background(privCardBg)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Address & UTXO Privacy
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var addressContent: some View {
        VStack(spacing: 16) {
            privSectionLabel("ADDRESS MANAGEMENT")
            addressCard
            privSectionLabel("COIN CONTROL")
            coinControlCard
        }
    }

    private var addressCard: some View {
        VStack(spacing: 12) {
            // Address lifecycle visual
            addressLifecycleVisual

            cloakToggle(label: "NEVER REUSE ADDRESSES", enabled: $neverReuseAddresses)
            Text("Each receive address is used only once. After receiving funds, a new address is automatically generated. This prevents transaction graph analysis.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.25))
                .lineSpacing(2)

            Divider().background(.white.opacity(0.06))

            cloakToggle(label: "AUTO-GENERATE ADDRESSES", enabled: $autoGenerateAddresses)
            Text("Pre-generate addresses in the background so fresh ones are always available.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.20))
                .lineSpacing(2)

            Divider().background(.white.opacity(0.06))

            // HD path
            HStack(spacing: 8) {
                Text("DERIVATION PATH")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                Spacer()
                TextField("m/84'/0'/0'", text: $hdPathCustom)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .textFieldStyle(.plain)
                    .frame(width: 120)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.03))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.06)))
                    )
            }
        }
        .padding(16)
        .background(privCardBg)
    }

    // Address lifecycle — nodes fading / materializing
    private var addressLifecycleVisual: some View {
        HStack(spacing: 0) {
            // Used addresses fading
            ForEach(0..<3, id: \.self) { i in
                addressNode(opacity: Double(3 - i) * 0.08, label: "used")
            }
            // Divider
            Rectangle()
                .fill(.white.opacity(0.06))
                .frame(width: 1, height: 24)
                .padding(.horizontal, 6)
            // Current address
            addressNode(opacity: 0.40, label: "active")
            // Future addresses materializing
            ForEach(0..<2, id: \.self) { i in
                addressNode(opacity: 0.12 - Double(i) * 0.04, label: "next")
            }
        }
        .frame(height: 50)
    }

    private func addressNode(opacity: Double, label: String) -> some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 4)
                .fill(.white.opacity(opacity))
                .frame(width: 26, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.white.opacity(opacity + 0.05), lineWidth: 0.8)
                )
            Text(label.uppercased())
                .font(.system(size: 5, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(opacity * 0.8))
        }
        .frame(maxWidth: .infinity)
    }

    // ── Coin control ──
    private var coinControlCard: some View {
        VStack(spacing: 12) {
            cloakToggle(label: "MANUAL UTXO SELECTION", enabled: $coinControlActive)

            if coinControlActive {
                utxoBuildingBlocks
            }

            Divider().background(.white.opacity(0.06))

            cloakToggle(label: "COINJOIN / MIXING", enabled: $coinJoinEnabled)
            Text("Combine your transaction with others to break the ownership trail. Increases fees slightly.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.20))
                .lineSpacing(2)

            Divider().background(.white.opacity(0.06))

            cloakToggle(label: "CONSOLIDATION WARNINGS", enabled: $consolidationWarnings)
            Text("Alerts you when merging UTXOs could link previously separate transaction histories.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.20))
                .lineSpacing(2)

            cloakToggle(label: "DUST MANAGEMENT", enabled: $dustManagement)
        }
        .padding(16)
        .background(privCardBg)
    }

    // UTXO building blocks — selectable geometric pieces
    private var utxoBuildingBlocks: some View {
        VStack(spacing: 8) {
            privSectionLabel("SELECT UTXOS TO SPEND")
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6)
            ], spacing: 6) {
                ForEach(mockUTXOs) { utxo in
                    utxoBlock(utxo)
                }
            }
            // Selected total
            utxoSelectedTotal
        }
    }

    private func utxoBlock(_ utxo: PrivUTXO) -> some View {
        let sel = selectedUTXOs.contains(utxo.id)
        // Scale height by amount
        let h: CGFloat = utxoBlockHeight(utxo.amount)
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                if sel { selectedUTXOs.remove(utxo.id) }
                else { selectedUTXOs.insert(utxo.id) }
            }
        } label: {
            VStack(spacing: 3) {
                Text(utxo.amountLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(sel ? 0.7 : 0.35))
                Text(utxo.txidShort)
                    .font(.system(size: 6, design: .monospaced))
                    .foregroundColor(.white.opacity(sel ? 0.35 : 0.15))
            }
            .frame(maxWidth: .infinity)
            .frame(height: h)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(sel ? 0.08 : 0.025))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.white.opacity(sel ? 0.20 : 0.06), lineWidth: sel ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func utxoBlockHeight(_ amount: Double) -> CGFloat {
        let base: CGFloat = 44
        let scale = min(1.0, CGFloat(amount / 1.0))
        return base + scale * 20
    }

    private var utxoSelectedTotal: some View {
        let total = mockUTXOs.filter { selectedUTXOs.contains($0.id) }.reduce(0.0) { $0 + $1.amount }
        return HStack {
            Text("SELECTED")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
            Spacer()
            Text(String(format: "%.8f BTC", total))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(selectedUTXOs.isEmpty ? 0.2 : 0.6))
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Transaction Privacy
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var transactionContent: some View {
        VStack(spacing: 16) {
            privSectionLabel("PRIVACY PROTOCOLS")
            txProtocolsCard
            privSectionLabel("METADATA PROTECTION")
            metadataCard
        }
    }

    private var txProtocolsCard: some View {
        VStack(spacing: 12) {
            cloakToggle(label: "TAPROOT ADDRESSES", enabled: $taprootEnabled)
            Text("Use Taproot (P2TR) for enhanced on-chain privacy. Makes simple and complex transactions indistinguishable.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.25))
                .lineSpacing(2)

            Divider().background(.white.opacity(0.06))

            cloakToggle(label: "STEALTH ADDRESSES", enabled: $stealthAddresses)
            Text("Generate one-time addresses for each transaction, hiding the receiver from blockchain observers. Supported on select chains.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.20))
                .lineSpacing(2)

            Divider().background(.white.opacity(0.06))

            cloakToggle(label: "RANDOMIZE TX TIMING", enabled: $randomizeTiming)
            Text("Add a small random delay (0-60s) before broadcasting transactions to prevent timing correlation analysis.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.20))
                .lineSpacing(2)

            Divider().background(.white.opacity(0.06))

            cloakToggle(label: "CUSTOM FEE SELECTION", enabled: $customFeeSelection)
            Text("Manually set transaction fees to avoid fingerprinting through fee-rate patterns used by specific wallet software.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.20))
                .lineSpacing(2)
        }
        .padding(16)
        .background(privCardBg)
    }

    private var metadataCard: some View {
        VStack(spacing: 10) {
            cloakToggle(label: "STRIP EXIF FROM QR CODES", enabled: $stripEXIF)
            Text("Removes all metadata from generated QR code images before sharing.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.20))
                .lineSpacing(2)

            cloakToggle(label: "RANDOMIZE BROADCAST", enabled: $randomizeBroadcast)
            Text("Broadcast transactions to random subsets of nodes to prevent node-level traffic analysis.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.20))
                .lineSpacing(2)
        }
        .padding(16)
        .background(privCardBg)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Data & Analytics
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var dataContent: some View {
        VStack(spacing: 16) {
            privSectionLabel("DATA COLLECTION")
            dataCollectionCard
            privSectionLabel("CLIPBOARD")
            clipboardCard
            privSectionLabel("THIRD-PARTY SERVICES")
            thirdPartyCard
        }
    }

    private var dataCollectionCard: some View {
        VStack(spacing: 12) {
            // Data flow visualization
            dataFlowVisual

            cloakToggle(label: "ANONYMOUS USAGE ANALYTICS", enabled: $analyticsEnabled)
            Text("Help improve HAWALA by sharing anonymized usage patterns. No wallet addresses, balances, or transaction data is ever collected.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.25))
                .lineSpacing(2)

            Divider().background(.white.opacity(0.06))

            cloakToggle(label: "CRASH REPORTS", enabled: $crashReports)
            Text("Send anonymized crash data to help fix bugs. Contains only stack traces and device model — never wallet data.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.20))
                .lineSpacing(2)
        }
        .padding(16)
        .background(privCardBg)
    }

    // Data flow visualization — particles streaming (or blocked)
    private var dataFlowVisual: some View {
        ZStack {
            // Flow channel
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(0.02))
                .frame(height: 40)

            HStack(spacing: 0) {
                // Wallet icon
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.06))
                        .frame(width: 28, height: 28)
                    Image(systemName: "wallet.pass")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                }
                .padding(.leading, 12)

                // Flow dots
                HStack(spacing: 8) {
                    ForEach(0..<8, id: \.self) { i in
                        Circle()
                            .fill(.white.opacity(analyticsEnabled ? particleOpacity(i) : 0.03))
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(maxWidth: .infinity)

                // Block / allow indicator
                if !analyticsEnabled {
                    ZStack {
                        Rectangle()
                            .fill(.white.opacity(0.10))
                            .frame(width: 2, height: 24)
                        Rectangle()
                            .fill(.white.opacity(0.10))
                            .frame(width: 2, height: 24)
                            .offset(x: 4)
                    }
                    .padding(.trailing, 16)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white.opacity(0.04))
                            .frame(width: 28, height: 28)
                        Image(systemName: "server.rack")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.2))
                    }
                    .padding(.trailing, 12)
                }
            }
        }
        .frame(height: 50)
    }

    private func particleOpacity(_ index: Int) -> Double {
        0.06 + Double(index) * 0.025
    }

    private var clipboardCard: some View {
        VStack(spacing: 10) {
            cloakToggle(label: "AUTO-CLEAR CLIPBOARD", enabled: $clipboardAutoClear)
            if clipboardAutoClear {
                HStack {
                    Text("CLEAR AFTER")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                    Spacer()
                    clipboardTimerSelector
                }
            }
            Text("Automatically clears copied addresses and keys from the clipboard to prevent accidental exposure.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.20))
                .lineSpacing(2)
        }
        .padding(16)
        .background(privCardBg)
    }

    private var clipboardTimerSelector: some View {
        HStack(spacing: 4) {
            ForEach([15, 30, 60, 120], id: \.self) { secs in
                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) { clipboardTimer = secs }
                } label: {
                    Text(clipTimerLabel(secs))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(clipboardTimer == secs ? 0.6 : 0.2))
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white.opacity(clipboardTimer == secs ? 0.06 : 0.02))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func clipTimerLabel(_ s: Int) -> String {
        if s < 60 { return "\(s)s" }
        return "\(s / 60)m"
    }

    private var thirdPartyCard: some View {
        VStack(spacing: 10) {
            cloakToggle(label: "PRICE FEED SERVICES", enabled: $priceFeedEnabled)
            Text("Fetches live market prices from external APIs. Disabling removes price data but eliminates external requests.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.20))
                .lineSpacing(2)

            Divider().background(.white.opacity(0.06))

            cloakToggle(label: "BLOCK EXPLORER LINKS", enabled: $blockExplorerEnabled)
            Text("Links to block explorers for transaction verification. Disabling prevents any outbound explorer requests.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.20))
                .lineSpacing(2)

            Divider().background(.white.opacity(0.06))

            cloakToggle(label: "NETWORK FINGERPRINT PROTECTION", enabled: $fingerprintProtection)
            Text("Randomizes connection patterns and user agent strings to prevent network-level wallet identification.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.20))
                .lineSpacing(2)
        }
        .padding(16)
        .background(privCardBg)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Shared Components
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func privSectionLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
                .tracking(1)
            Spacer()
        }
    }

    // Cloaking toggle — stealth aesthetic
    private func cloakToggle(label: String, enabled: Binding<Bool>) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                enabled.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                // Shield bolt — fills/empties
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
                    .foregroundColor(.white.opacity(enabled.wrappedValue ? 0.55 : 0.25))
                    .tracking(0.5)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private var privCardBg: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(.white.opacity(0.025))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.05), lineWidth: 1))
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

    private func startAnimations() {
        withAnimation(.linear(duration: 6.0).repeatForever(autoreverses: false)) { silkPhase = 1.5 }
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) { shieldPulse = 1.0 }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Mock Data
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func loadMockData() {
        mockUTXOs = [
            PrivUTXO(id: "u1", txid: "a3f8c21e...9b4d", amount: 0.50000000, confirmations: 142),
            PrivUTXO(id: "u2", txid: "d7e29f13...c8a2", amount: 0.12500000, confirmations: 89),
            PrivUTXO(id: "u3", txid: "f1b40a87...3e71", amount: 0.03200000, confirmations: 1203),
            PrivUTXO(id: "u4", txid: "82c6d9e5...a4f0", amount: 0.00850000, confirmations: 45),
            PrivUTXO(id: "u5", txid: "19ae7b34...d682", amount: 0.25000000, confirmations: 312),
            PrivUTXO(id: "u6", txid: "c4f01e28...7b93", amount: 0.00120000, confirmations: 2100)
        ]
        selectedUTXOs = ["u1", "u5"]
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Models
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct PrivUTXO: Identifiable {
    let id: String
    let txid: String
    let amount: Double
    let confirmations: Int

    var amountLabel: String {
        if amount >= 0.01 {
            return String(format: "%.4f", amount)
        }
        return String(format: "%.8f", amount)
    }

    var txidShort: String {
        String(txid.prefix(8))
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Shield Shape (hexagonal)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct PrivShieldShape: Shape {
    let sides: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for i in 0..<sides {
            let angle = (2 * Double.pi / Double(sides)) * Double(i) - .pi / 2
            let pt = CGPoint(
                x: center.x + radius * CGFloat(cos(angle)),
                y: center.y + radius * CGFloat(sin(angle))
            )
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }
}
