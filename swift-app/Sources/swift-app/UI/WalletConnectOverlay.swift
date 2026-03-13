import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – WalletConnect Overlay
// Your wallet's bridge to decentralized applications.
// Hub-and-spoke topology, tether connections,
// flowing transaction cards, hold-to-confirm.
// Monumental. Monochrome. Connected.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct WalletConnectOverlay: View {
    @Binding var isPresented: Bool

    // ── Tab ──
    @State private var selectedTab: WCTab = .sessions

    enum WCTab: String, CaseIterable {
        case sessions = "SESSIONS"
        case requests = "REQUESTS"
        case history = "HISTORY"
    }

    // ── Sessions ──
    @State private var activeSessions: [WCDApp] = []
    @State private var selectedSessionId: String? = nil

    // ── Connect flow ──
    @State private var showConnect: Bool = false
    @State private var uriInput: String = ""
    @State private var connectState: ConnectState = .idle
    enum ConnectState: Equatable {
        case idle, scanning, detected, confirming(String), connected(String), failed
    }
    @State private var scanBracketScale: CGFloat = 1.4
    @State private var scanPulse: CGFloat = 0

    // ── Requests ──
    @State private var pendingRequests: [WCRequest] = []
    @State private var holdProgress: CGFloat = 0
    @State private var holdingRequestId: String? = nil
    @State private var holdTimer: Timer? = nil

    // ── History ──
    @State private var sessionHistory: [WCHistoryItem] = []

    // ── Disconnect animation ──
    @State private var disconnectingId: String? = nil

    // ── Animation ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var silkPhase: CGFloat = 0
    @State private var tetherPulse: CGFloat = 0

    // ── Hover ──
    @State private var closeHovered: Bool = false
    @State private var connectBtnHovered: Bool = false

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Body
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    var body: some View {
        ZStack {
            backdrop
            cardContainer
        }
        .background(
            EscapeKeyHandler(isPresented: $isPresented, onEscape: dismissOverlay)
        )
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardScale = 1
                contentOpacity = 1
            }
            loadMockData()
            startAnimations()
        }
    }

    private var backdrop: some View {
        Color.black.opacity(0.75)
            .ignoresSafeArea()
            .onTapGesture { dismissOverlay() }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Card
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var cardContainer: some View {
        VStack(spacing: 0) {
            headerBar
            tabBar
            tabContent
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

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Header
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var headerBar: some View {
        ZStack {
            Text("WALLETCONNECT")
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

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Tab Bar
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(WCTab.allCases, id: \.self) { tab in
                wcTabButton(tab)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }

    private func wcTabButton(_ tab: WCTab) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text(tab.rawValue)
                        .font(.clashGroteskMedium(size: 12))
                        .tracking(2)
                        .foregroundColor(.white.opacity(selectedTab == tab ? 0.8 : 0.3))

                    if tab == .requests && !pendingRequests.isEmpty {
                        Text("\(pendingRequests.count)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.white.opacity(0.08)))
                    }
                }
                RoundedRectangle(cornerRadius: 1)
                    .fill(.white.opacity(selectedTab == tab ? 0.4 : 0))
                    .frame(height: 1.5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Tab Content
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var tabContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                switch selectedTab {
                case .sessions: sessionsTabContent
                case .requests: requestsTabContent
                case .history: historyTabContent
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Sessions Tab
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var sessionsTabContent: some View {
        VStack(spacing: 16) {
            // Hub topology visualization
            hubVisualization

            // Connect button or flow
            if showConnect {
                connectFlow
            } else {
                newConnectionButton
            }

            // Session cards
            if !activeSessions.isEmpty {
                wcSectionHeader("ACTIVE CONNECTIONS")
            }
            ForEach(activeSessions) { session in
                sessionCard(session)
            }
        }
    }

    // ── Hub and spoke visualization ──
    private var hubVisualization: some View {
        let sessions = activeSessions
        let count = sessions.count
        return ZStack {
            // Tether lines from hub to nodes
            ForEach(Array(sessions.enumerated()), id: \.element.id) { idx, session in
                tetherLine(index: idx, total: count, disconnecting: disconnectingId == session.id)
            }

            // dApp nodes
            ForEach(Array(sessions.enumerated()), id: \.element.id) { idx, session in
                dappNode(session: session, index: idx, total: count)
            }

            // Central HAWALA hub
            centralHub
        }
        .frame(height: count > 0 ? 160 : 80)
    }

    private var centralHub: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.04))
                .frame(width: 44, height: 44)
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
            Text("H")
                .font(.clashGroteskBold(size: 16))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private func tetherLine(index: Int, total: Int, disconnecting: Bool) -> some View {
        let pos = nodePosition(index: index, total: total, radius: 60)
        let opacity = disconnecting ? 0.0 : (0.08 + 0.05 * tetherPulse)
        return Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: pos.x, y: pos.y))
        }
        .stroke(.white.opacity(opacity), lineWidth: 1)
        .frame(width: 0, height: 0)
        .offset(x: 0, y: 0)
    }

    private func dappNode(session: WCDApp, index: Int, total: Int) -> some View {
        let pos = nodePosition(index: index, total: total, radius: 60)
        let isDisconnecting = disconnectingId == session.id
        let isSelected = selectedSessionId == session.id
        return VStack(spacing: 3) {
            dappIconCircle(session: session, isSelected: isSelected)
            Text(session.shortName)
                .font(.system(size: 7, weight: .medium))
                .foregroundColor(.white.opacity(isDisconnecting ? 0.1 : 0.4))
        }
        .opacity(isDisconnecting ? 0.2 : 1.0)
        .offset(x: pos.x, y: pos.y)
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedSessionId = isSelected ? nil : session.id
            }
        }
    }

    private func dappIconCircle(session: WCDApp, isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(.white.opacity(isSelected ? 0.08 : 0.04))
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(isSelected ? 0.30 : 0.10), lineWidth: isSelected ? 1.5 : 1)
                )
            // Grayscale icon representation
            Text(String(session.name.prefix(1)))
                .font(.clashGroteskBold(size: 11))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private func nodePosition(index: Int, total: Int, radius: CGFloat) -> CGPoint {
        guard total > 0 else { return .zero }
        let angle = (2 * .pi / Double(total)) * Double(index) - .pi / 2
        return CGPoint(
            x: radius * CGFloat(cos(angle)),
            y: radius * CGFloat(sin(angle))
        )
    }

    // ── Permission badges ──
    private func permissionBadges(_ session: WCDApp) -> some View {
        HStack(spacing: 4) {
            ForEach(session.permissions, id: \.self) { perm in
                permissionIcon(perm)
            }
        }
    }

    private func permissionIcon(_ perm: String) -> some View {
        let icon: String
        switch perm {
        case "sign": icon = "signature"
        case "send": icon = "paperplane"
        case "read": icon = "eye"
        case "switch": icon = "arrow.triangle.2.circlepath"
        default: icon = "questionmark"
        }
        return Image(systemName: icon)
            .font(.system(size: 7))
            .foregroundColor(.white.opacity(0.3))
            .frame(width: 14, height: 14)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.04))
            )
    }

    // ── Connect button ──
    private var newConnectionButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showConnect = true
                connectState = .idle
                uriInput = ""
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 11))
                Text("NEW CONNECTION")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundColor(.white.opacity(connectBtnHovered ? 0.7 : 0.45))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(connectBtnHovered ? 0.15 : 0.08),
                                  style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            )
        }
        .buttonStyle(.plain)
        .onHover { connectBtnHovered = $0 }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Connect Flow
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var connectFlow: some View {
        VStack(spacing: 14) {
            connectFlowHeader
            connectFlowBody
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var connectFlowHeader: some View {
        HStack {
            Text("CONNECT dAPP")
                .font(.clashGroteskMedium(size: 11))
                .tracking(2)
                .foregroundColor(.white.opacity(0.4))
            Spacer()
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    showConnect = false
                    connectState = .idle
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var connectFlowBody: some View {
        switch connectState {
        case .idle:
            connectIdleView
        case .scanning:
            scanViewfinder
        case .detected:
            scanDetectedView
        case .confirming(let name):
            confirmConnectionView(name)
        case .connected(let name):
            connectedSuccessView(name)
        case .failed:
            connectionFailedView
        }
    }

    // ── Idle: URI input + scan button ──
    private var connectIdleView: some View {
        VStack(spacing: 12) {
            // URI input
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.25))
                TextField("Paste WalletConnect URI", text: $uriInput)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                    )
            )

            HStack(spacing: 10) {
                // Paste & connect
                Button {
                    simulateURIConnect()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 10))
                        Text("CONNECT")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.white.opacity(uriInput.isEmpty ? 0.25 : 0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(uriInput.isEmpty ? 0.03 : 0.06))
                    )
                }
                .buttonStyle(.plain)
                .disabled(uriInput.isEmpty)

                // Scan QR
                Button {
                    beginScan()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 10))
                        Text("SCAN QR")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ── QR Viewfinder ──
    private var scanViewfinder: some View {
        VStack(spacing: 12) {
            ZStack {
                // Background scan area
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.02))
                    .frame(width: 160, height: 160)

                // Corner brackets
                scanBrackets
                    .scaleEffect(scanBracketScale)

                // Center crosshair
                scanCrosshair

                // Scanning pulse
                Circle()
                    .strokeBorder(.white.opacity(0.06 * (1 - scanPulse)), lineWidth: 1)
                    .frame(width: 80 + 60 * scanPulse, height: 80 + 60 * scanPulse)
            }
            .frame(height: 170)

            Text("Position QR code in viewfinder")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
        }
    }

    private var scanBrackets: some View {
        ZStack {
            // Top-left
            scanCorner(rotation: 0).offset(x: -55, y: -55)
            // Top-right
            scanCorner(rotation: 90).offset(x: 55, y: -55)
            // Bottom-right
            scanCorner(rotation: 180).offset(x: 55, y: 55)
            // Bottom-left
            scanCorner(rotation: 270).offset(x: -55, y: 55)
        }
    }

    private func scanCorner(rotation: Double) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 16))
            path.addLine(to: .zero)
            path.addLine(to: CGPoint(x: 16, y: 0))
        }
        .stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .frame(width: 16, height: 16)
        .rotationEffect(.degrees(rotation))
    }

    private var scanCrosshair: some View {
        ZStack {
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(width: 1, height: 20)
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(width: 20, height: 1)
        }
    }

    // ── QR detected ──
    private var scanDetectedView: some View {
        VStack(spacing: 10) {
            Image(systemName: "qrcode")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.5))
            Text("QR CODE DETECTED")
                .font(.clashGroteskMedium(size: 13))
                .tracking(1)
                .foregroundColor(.white.opacity(0.7))
            Text("Establishing connection...")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.vertical, 12)
    }

    // ── Confirm connection ──
    private func confirmConnectionView(_ name: String) -> some View {
        VStack(spacing: 14) {
            // dApp icon placeholder
            ZStack {
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    )
                Text(String(name.prefix(1)))
                    .font(.clashGroteskBold(size: 18))
                    .foregroundColor(.white.opacity(0.5))
            }

            Text(name)
                .font(.clashGroteskMedium(size: 16))
                .foregroundColor(.white.opacity(0.8))

            Text("wants to connect")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))

            // Requested permissions
            VStack(spacing: 4) {
                confirmPermRow(icon: "signature", label: "Sign messages & transactions")
                confirmPermRow(icon: "eye", label: "View wallet addresses")
                confirmPermRow(icon: "arrow.triangle.2.circlepath", label: "Request chain switching")
            }
            .padding(.vertical, 4)

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        connectState = .failed
                    }
                } label: {
                    Text("REJECT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.white.opacity(0.03))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    approveConnection(name)
                } label: {
                    Text("APPROVE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func confirmPermRow(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.3))
                .frame(width: 14)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.45))
            Spacer()
        }
    }

    // ── Connected success ──
    private func connectedSuccessView(_ name: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.5))
            Text("CONNECTED")
                .font(.clashGroteskMedium(size: 14))
                .tracking(2)
                .foregroundColor(.white.opacity(0.7))
            Text(name)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.vertical, 12)
    }

    // ── Failed ──
    private var connectionFailedView: some View {
        VStack(spacing: 10) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.35))
            Text("CONNECTION REJECTED")
                .font(.clashGroteskMedium(size: 13))
                .tracking(1)
                .foregroundColor(.white.opacity(0.5))
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    connectState = .idle
                }
            } label: {
                Text("Try Again")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
    }

    // ── Session card ──
    private func sessionCard(_ session: WCDApp) -> some View {
        let isSelected = selectedSessionId == session.id
        let isDisconnecting = disconnectingId == session.id
        return VStack(spacing: 0) {
            sessionCardHeader(session, isSelected: isSelected)
            if isSelected {
                sessionCardExpanded(session)
            }
        }
        .opacity(isDisconnecting ? 0.4 : 1)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(isSelected ? 0.04 : 0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(isSelected ? 0.10 : 0.05), lineWidth: 1)
                )
        )
    }

    private func sessionCardHeader(_ s: WCDApp, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            // Grayscale dApp icon
            ZStack {
                Circle()
                    .fill(.white.opacity(0.05))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    )
                Text(String(s.name.prefix(1)))
                    .font(.clashGroteskBold(size: 13))
                    .foregroundColor(.white.opacity(0.45))
            }
            .grayscale(1.0)

            VStack(alignment: .leading, spacing: 2) {
                Text(s.name)
                    .font(.clashGroteskMedium(size: 13))
                    .foregroundColor(.white.opacity(0.8))
                Text(s.connectedAgo)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }

            Spacer()

            permissionBadges(s)

            Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.2))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedSessionId = isSelected ? nil : s.id
            }
        }
    }

    private func sessionCardExpanded(_ s: WCDApp) -> some View {
        VStack(spacing: 10) {
            Divider().background(.white.opacity(0.06))

            sessionRow(label: "URL", value: s.url)
            sessionRow(label: "CHAIN", value: s.chain)
            sessionRow(label: "LAST ACTIVE", value: s.lastActive)
            sessionRow(label: "PERMISSIONS", value: s.permissions.joined(separator: ", ").uppercased())

            disconnectButton(s)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private func sessionRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
        }
    }

    private func disconnectButton(_ s: WCDApp) -> some View {
        Button {
            disconnectSession(s)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 10))
                    .rotationEffect(.degrees(45))
                Text("DISCONNECT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            .foregroundColor(.white.opacity(0.35))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Requests Tab
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var requestsTabContent: some View {
        VStack(spacing: 14) {
            if pendingRequests.isEmpty {
                emptyRequests
            } else {
                ForEach(pendingRequests) { req in
                    requestCard(req)
                }
            }
        }
    }

    private var emptyRequests: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 26))
                .foregroundColor(.white.opacity(0.12))
            Text("No pending requests")
                .font(.clashGroteskMedium(size: 13))
                .foregroundColor(.white.opacity(0.25))
            Text("Transaction requests from dApps appear here")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.15))
        }
        .padding(.vertical, 40)
    }

    private func requestCard(_ req: WCRequest) -> some View {
        VStack(spacing: 14) {
            requestCardHeader(req)
            requestTxDetails(req)
            requestActions(req)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func requestCardHeader(_ req: WCRequest) -> some View {
        HStack(spacing: 10) {
            // dApp icon (grayscale)
            ZStack {
                Circle()
                    .fill(.white.opacity(0.05))
                    .frame(width: 28, height: 28)
                Text(String(req.dappName.prefix(1)))
                    .font(.clashGroteskBold(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            .grayscale(1.0)

            VStack(alignment: .leading, spacing: 2) {
                Text(req.dappName)
                    .font(.clashGroteskMedium(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                Text(req.methodDisplay)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }

            Spacer()

            Text(req.timeAgo)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.25))
        }
    }

    private func requestTxDetails(_ req: WCRequest) -> some View {
        VStack(spacing: 8) {
            if let amount = req.amount {
                HStack {
                    Text("AMOUNT")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                    Spacer()
                    Text(amount)
                        .font(.clashGroteskBold(size: 16))
                        .foregroundColor(.white.opacity(0.85))
                }
            }

            txDetailRow(label: "TO", value: req.toAddress)
            txDetailRow(label: "CHAIN", value: req.chain)

            if let gas = req.gasEstimate {
                txDetailRow(label: "EST. GAS", value: gas)
            }

            if let contract = req.contractInteraction {
                txDetailRow(label: "CONTRACT", value: contract)
            }

            if let data = req.dataPreview {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DATA")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                    Text(data)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.white.opacity(0.04), lineWidth: 1)
                )
        )
    }

    private func txDetailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
            Spacer()
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
        }
    }

    // ── Approve (hold-to-confirm) / Reject ──
    private func requestActions(_ req: WCRequest) -> some View {
        HStack(spacing: 10) {
            // Reject
            Button {
                rejectRequest(req)
            } label: {
                Text("REJECT")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.03))
                    )
            }
            .buttonStyle(.plain)

            // Hold to approve
            holdToApproveButton(req)
        }
    }

    private func holdToApproveButton(_ req: WCRequest) -> some View {
        let isHolding = holdingRequestId == req.id
        let progress = isHolding ? holdProgress : 0
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.06))

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.08))
                    .frame(width: geo.size.width * progress)
            }

            Text(isHolding ? "APPROVING..." : "HOLD TO APPROVE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(isHolding ? 0.5 : 0.65))
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in startHold(req) }
                .onEnded { _ in cancelHold() }
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – History Tab
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var historyTabContent: some View {
        VStack(spacing: 10) {
            if sessionHistory.isEmpty {
                emptyHistory
            } else {
                ForEach(sessionHistory) { item in
                    historyRow(item)
                }
            }
        }
    }

    private var emptyHistory: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 26))
                .foregroundColor(.white.opacity(0.12))
            Text("No session history")
                .font(.clashGroteskMedium(size: 13))
                .foregroundColor(.white.opacity(0.25))
        }
        .padding(.vertical, 40)
    }

    private func historyRow(_ item: WCHistoryItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.03))
                    .frame(width: 26, height: 26)
                Image(systemName: item.icon)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.dappName)
                    .font(.clashGroteskMedium(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                Text(item.action)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
            }

            Spacer()

            Text(item.dateLabel)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.2))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.025))
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Shared
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func wcSectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
                .tracking(1)
            Spacer()
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Actions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func dismissOverlay() {
        cancelHold()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            cardScale = 0.95
            contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isPresented = false
        }
    }

    private func beginScan() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            connectState = .scanning
            scanBracketScale = 1.4
        }
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            scanPulse = 1
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            scanBracketScale = 1.0
        }
        // Simulate detection
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    connectState = .detected
                    scanPulse = 0
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    connectState = .confirming("PancakeSwap")
                }
            }
        }
    }

    private func simulateURIConnect() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            connectState = .confirming("Custom dApp")
        }
    }

    private func approveConnection(_ name: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            connectState = .connected(name)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            DispatchQueue.main.async {
                let newSession = WCDApp(
                    id: UUID().uuidString,
                    name: name,
                    url: "\(name.lowercased().replacingOccurrences(of: " ", with: "")).finance",
                    chain: "Ethereum",
                    connectedAgo: "Just now",
                    lastActive: "Just now",
                    permissions: ["sign", "send", "read"]
                )
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    activeSessions.append(newSession)
                    showConnect = false
                    connectState = .idle
                }
            }
        }
    }

    private func disconnectSession(_ s: WCDApp) {
        withAnimation(.easeInOut(duration: 0.6)) {
            disconnectingId = s.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    activeSessions.removeAll { $0.id == s.id }
                    if selectedSessionId == s.id { selectedSessionId = nil }
                    disconnectingId = nil
                }
                // Add to history
                let hist = WCHistoryItem(
                    id: UUID().uuidString,
                    dappName: s.name,
                    action: "Disconnected",
                    icon: "link.badge.plus",
                    dateLabel: "Just now"
                )
                sessionHistory.insert(hist, at: 0)
            }
        }
    }

    private func startHold(_ req: WCRequest) {
        guard holdingRequestId == nil else { return }
        holdingRequestId = req.id
        holdProgress = 0

        let interval: TimeInterval = 0.03
        let totalDuration: TimeInterval = 1.5
        let increment = CGFloat(interval / totalDuration)

        holdTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak holdTimer] _ in
            DispatchQueue.main.async {
                holdProgress += increment
                if holdProgress >= 1.0 {
                    holdTimer?.invalidate()
                    self.holdTimer = nil
                    approveRequest(req)
                }
            }
        }
    }

    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        withAnimation(.easeOut(duration: 0.2)) {
            holdProgress = 0
        }
        holdingRequestId = nil
    }

    private func approveRequest(_ req: WCRequest) {
        holdingRequestId = nil
        holdProgress = 0
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            pendingRequests.removeAll { $0.id == req.id }
        }
        // Add to history
        let hist = WCHistoryItem(
            id: UUID().uuidString,
            dappName: req.dappName,
            action: "\(req.methodDisplay) — Approved",
            icon: "checkmark.circle",
            dateLabel: "Just now"
        )
        sessionHistory.insert(hist, at: 0)
    }

    private func rejectRequest(_ req: WCRequest) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            pendingRequests.removeAll { $0.id == req.id }
        }
        let hist = WCHistoryItem(
            id: UUID().uuidString,
            dappName: req.dappName,
            action: "\(req.methodDisplay) — Rejected",
            icon: "xmark.circle",
            dateLabel: "Just now"
        )
        sessionHistory.insert(hist, at: 0)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Data
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func loadMockData() {
        activeSessions = [
            WCDApp(
                id: "s1", name: "Uniswap", url: "app.uniswap.org",
                chain: "Ethereum", connectedAgo: "Connected 2h ago",
                lastActive: "15 min ago",
                permissions: ["sign", "send", "read"]
            ),
            WCDApp(
                id: "s2", name: "OpenSea", url: "opensea.io",
                chain: "Ethereum", connectedAgo: "Connected 1d ago",
                lastActive: "3h ago",
                permissions: ["sign", "read"]
            ),
            WCDApp(
                id: "s3", name: "Aave", url: "app.aave.com",
                chain: "Polygon", connectedAgo: "Connected 4h ago",
                lastActive: "1h ago",
                permissions: ["sign", "send", "read", "switch"]
            )
        ]

        pendingRequests = [
            WCRequest(
                id: "r1",
                dappName: "Uniswap",
                methodDisplay: "Send Transaction",
                chain: "Ethereum",
                toAddress: "0x68b3...4e2f",
                amount: "0.5 ETH",
                gasEstimate: "0.003 ETH (~$9.50)",
                contractInteraction: "swap(uint256, address[])",
                dataPreview: "0xa9059cbb0000000000000000000000...",
                timeAgo: "30s ago"
            )
        ]

        sessionHistory = [
            WCHistoryItem(id: "h1", dappName: "Uniswap", action: "Swap — Approved", icon: "checkmark.circle", dateLabel: "2h ago"),
            WCHistoryItem(id: "h2", dappName: "OpenSea", action: "Sign Message — Approved", icon: "checkmark.circle", dateLabel: "1d ago"),
            WCHistoryItem(id: "h3", dappName: "Compound", action: "Disconnected", icon: "link.badge.plus", dateLabel: "3d ago")
        ]
    }

    private func startAnimations() {
        withAnimation(.linear(duration: 6.0).repeatForever(autoreverses: false)) {
            silkPhase = 1.5
        }
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
            tetherPulse = 1.0
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Models
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct WCDApp: Identifiable {
    let id: String
    let name: String
    let url: String
    let chain: String
    let connectedAgo: String
    let lastActive: String
    let permissions: [String]

    var shortName: String {
        if name.count > 8 { return String(name.prefix(7)) + "." }
        return name
    }
}

struct WCRequest: Identifiable {
    let id: String
    let dappName: String
    let methodDisplay: String
    let chain: String
    let toAddress: String
    let amount: String?
    let gasEstimate: String?
    let contractInteraction: String?
    let dataPreview: String?
    let timeAgo: String
}

struct WCHistoryItem: Identifiable {
    let id: String
    let dappName: String
    let action: String
    let icon: String
    let dateLabel: String
}
