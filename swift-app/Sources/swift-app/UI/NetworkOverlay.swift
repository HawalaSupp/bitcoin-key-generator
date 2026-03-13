import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Network Overlay
// Mission-control network operations center.
// Constellation topology, sync arcs, latency proximity,
// pulse diagnostics, provider pathways, failover routing.
// Monumental. Monochrome. Connected.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct NetworkOverlay: View {
    @Binding var isPresented: Bool

    // ── Node manager ──
    @StateObject private var nodeManager = NodeManager.shared

    // ── Section nav ──
    @State private var activeSection: NetSection = .topology

    enum NetSection: String, CaseIterable {
        case topology   = "TOPOLOGY"
        case providers  = "PROVIDERS"
        case sync       = "SYNC"
        case health     = "HEALTH"
        case settings   = "SETTINGS"
    }

    // ── Selected chain ──
    @State private var selectedChain: NodeChain = .bitcoin

    // ── Provider management ──
    @State private var isAddingProvider: Bool = false
    @State private var newProviderLabel: String = ""
    @State private var newProviderURL: String = ""
    @State private var newProviderKey: String = ""

    // ── Diagnostics ──
    @State private var isPulsing: Bool = false
    @State private var pulsePhase: CGFloat = 0
    @State private var pulseResults: [NodeChain: PulseResult] = [:]
    @State private var isRunningDiagnostics: Bool = false

    struct PulseResult {
        let latencyMs: Int?
        let connected: Bool
        let timestamp: Date
    }

    // ── Testnet ──
    @State private var testnetMode: Bool = false

    // ── Failover ──
    @State private var failoverThreshold: Int = 3

    // ── Animation ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var silkPhase: CGFloat = 0
    @State private var constellationPulse: CGFloat = 0

    // ── Hover ──
    @State private var closeHovered: Bool = false

    // ── Visible chains for topology ──
    private let topologyChains: [NodeChain] = [.bitcoin, .ethereum, .solana, .litecoin, .polygon, .arbitrum]

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
            statusRibbon
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
            Text("NETWORK")
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

    // ── Status ribbon — aggregate connection summary ──
    private var statusRibbon: some View {
        let stats = connectionStats()
        return HStack(spacing: 16) {
            statusPill(label: "CONNECTED", count: stats.connected)
            statusPill(label: "SYNCING", count: stats.syncing)
            statusPill(label: "OFFLINE", count: stats.offline)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }

    private func statusPill(label: String, count: Int) -> some View {
        HStack(spacing: 5) {
            // Geometric indicator based on label
            netStatusDot(label: label)
            Text("\(count)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(count > 0 ? 0.6 : 0.15))
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(count > 0 ? 0.3 : 0.12))
        }
    }

    private func netStatusDot(label: String) -> some View {
        ZStack {
            if label == "CONNECTED" {
                // Complete circle
                Circle()
                    .fill(.white.opacity(0.30))
                    .frame(width: 6, height: 6)
            } else if label == "SYNCING" {
                // Incomplete arc
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(.white.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 6, height: 6)
                    .rotationEffect(.degrees(constellationPulse * 360))
            } else {
                // Empty ring
                Circle()
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    .frame(width: 6, height: 6)
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Section Picker
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(NetSection.allCases, id: \.self) { sec in
                    netTabButton(sec)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 8)
    }

    private func netTabButton(_ sec: NetSection) -> some View {
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
                case .topology: topologyContent
                case .providers: providersContent
                case .sync: syncContent
                case .health: healthContent
                case .settings: settingsContent
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Topology (Network Graph)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var topologyContent: some View {
        VStack(spacing: 16) {
            constellationGraph
            netSectionLabel("ALL CHAINS")
            chainListCompact
        }
    }

    // ── Constellation graph — HAWALA at center, chains orbit ──
    private var constellationGraph: some View {
        ZStack {
            // Connection lines from center to each chain
            ForEach(Array(topologyChains.enumerated()), id: \.element) { idx, chain in
                constellationLine(index: idx, total: topologyChains.count, chain: chain)
            }
            // Chain nodes orbiting
            ForEach(Array(topologyChains.enumerated()), id: \.element) { idx, chain in
                constellationNode(index: idx, total: topologyChains.count, chain: chain)
            }
            // Center hub
            constellationCenter
        }
        .frame(height: 200)
        .padding(.vertical, 8)
    }

    private var constellationCenter: some View {
        ZStack {
            // Pulse rings
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .strokeBorder(.white.opacity(0.04 - Double(i) * 0.01), lineWidth: 1)
                    .frame(width: CGFloat(30 + i * 16), height: CGFloat(30 + i * 16))
            }
            // Core
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(.white.opacity(0.20), lineWidth: 1.5))
            Text("H")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.50))
        }
    }

    private func constellationLine(index: Int, total: Int, chain: NodeChain) -> some View {
        let angle = constellationAngle(index: index, total: total)
        let radius: CGFloat = 80
        let status = chainConnectionStatus(chain)
        let lineOpacity = status == .connected ? 0.15 : (status == .testing ? 0.08 : 0.04)
        let dashPattern: [CGFloat] = status == .connected ? [] : [4, 3]

        return Path { p in
            p.move(to: CGPoint(x: 200, y: 100))
            p.addLine(to: CGPoint(
                x: 200 + radius * cos(angle),
                y: 100 + radius * sin(angle)
            ))
        }
        .stroke(
            .white.opacity(lineOpacity),
            style: StrokeStyle(
                lineWidth: status == .connected ? 1.5 : 0.8,
                dash: dashPattern
            )
        )
        .frame(width: 400, height: 200)
    }

    private func constellationNode(index: Int, total: Int, chain: NodeChain) -> some View {
        let angle = constellationAngle(index: index, total: total)
        let radius: CGFloat = 80
        let status = chainConnectionStatus(chain)
        let isSelected = selectedChain == chain

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedChain = chain
                activeSection = .providers
            }
        } label: {
            VStack(spacing: 3) {
                // Node shape — completeness shows connection
                constellationNodeShape(status: status, isSelected: isSelected)
                Text(chain.symbol)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(isSelected ? 0.6 : 0.3))
            }
        }
        .buttonStyle(.plain)
        .offset(
            x: radius * cos(angle),
            y: radius * sin(angle)
        )
    }

    private func constellationNodeShape(status: NodeConnectionStatus, isSelected: Bool) -> some View {
        ZStack {
            // Outer ring — completeness denotes status
            if status == .connected {
                // Complete ring
                Circle()
                    .strokeBorder(.white.opacity(isSelected ? 0.45 : 0.25), lineWidth: isSelected ? 2 : 1.5)
                    .frame(width: 22, height: 22)
                Circle()
                    .fill(.white.opacity(isSelected ? 0.10 : 0.05))
                    .frame(width: 22, height: 22)
            } else if status == .testing {
                // Animating arc
                Circle()
                    .trim(from: 0, to: 0.65)
                    .stroke(.white.opacity(0.20), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                    .rotationEffect(.degrees(constellationPulse * 360))
            } else {
                // Broken ring — disconnected
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
                    .frame(width: 22, height: 22)
                Circle()
                    .trim(from: 0.5, to: 0.8)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
                    .frame(width: 22, height: 22)
            }
            // Inner dot
            Circle()
                .fill(.white.opacity(status == .connected ? 0.30 : 0.08))
                .frame(width: 6, height: 6)
        }
    }

    private func constellationAngle(index: Int, total: Int) -> CGFloat {
        let base = -CGFloat.pi / 2  // Start from top
        let step = 2 * CGFloat.pi / CGFloat(total)
        return base + step * CGFloat(index)
    }

    // ── Compact chain list under topology ──
    private var chainListCompact: some View {
        VStack(spacing: 2) {
            ForEach(NodeChain.allCases) { chain in
                chainListRow(chain)
            }
        }
        .background(netCardBg)
    }

    private func chainListRow(_ chain: NodeChain) -> some View {
        let status = chainConnectionStatus(chain)
        let defaultNode = nodeManager.defaultNode(for: chain)
        let isSelected = selectedChain == chain

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedChain = chain
                activeSection = .providers
            }
        } label: {
            HStack(spacing: 10) {
                // Status geometry
                chainStatusGeometry(status)
                    .frame(width: 14, height: 14)

                // Chain name
                VStack(alignment: .leading, spacing: 1) {
                    Text(chain.displayName.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(isSelected ? 0.65 : 0.40))
                    if let node = defaultNode {
                        Text(node.label)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.white.opacity(0.18))
                    }
                }

                Spacer()

                // Latency
                if let lat = defaultNode?.health.latencyMs {
                    Text("\(lat)ms")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(latencyOpacity(lat)))
                }

                // Block height
                if let height = defaultNode?.health.blockHeight {
                    Text("#\(formatBlockHeight(height))")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.18))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? Color.white.opacity(0.03) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func chainStatusGeometry(_ status: NodeConnectionStatus) -> some View {
        ZStack {
            switch status {
            case .connected:
                Circle()
                    .fill(.white.opacity(0.25))
                    .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
            case .testing:
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(.white.opacity(0.20), lineWidth: 1.5)
                    .rotationEffect(.degrees(constellationPulse * 360))
            case .disconnected, .error:
                Circle()
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    .overlay(
                        Path { p in
                            p.move(to: CGPoint(x: 3, y: 3))
                            p.addLine(to: CGPoint(x: 11, y: 11))
                        }
                        .stroke(.white.opacity(0.08), lineWidth: 0.8)
                    )
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Providers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var providersContent: some View {
        VStack(spacing: 16) {
            chainSelector
            netSectionLabel("PROVIDERS FOR \(selectedChain.displayName.uppercased())")
            providerPathways
            if isAddingProvider {
                addProviderForm
            } else {
                addProviderButton
            }
        }
    }

    // ── Chain selector pills ──
    private var chainSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(NodeChain.allCases) { chain in
                    chainPill(chain)
                }
            }
        }
    }

    private func chainPill(_ chain: NodeChain) -> some View {
        let sel = selectedChain == chain
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                selectedChain = chain
                isAddingProvider = false
            }
        } label: {
            Text(chain.symbol)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(sel ? 0.7 : 0.25))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white.opacity(sel ? 0.08 : 0.02))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(sel ? 0.15 : 0.04)))
                )
        }
        .buttonStyle(.plain)
    }

    // ── Provider pathways — visual routes to the chain ──
    private var providerPathways: some View {
        let chainNodes = nodeManager.nodes(for: selectedChain)
        return VStack(spacing: 6) {
            ForEach(chainNodes) { node in
                providerRow(node)
            }
        }
    }

    private func providerRow(_ node: NodeConfiguration) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Route line / pathway indicator
                providerPathwayIndicator(node)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(node.label.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundColor(.white.opacity(node.isDefault ? 0.6 : 0.35))

                        if node.isDefault {
                            Text("DEFAULT")
                                .font(.system(size: 6, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundColor(.white.opacity(0.3))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(.white.opacity(0.05))
                                )
                        }
                    }

                    // URL truncated
                    Text(truncateURL(node.url))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.15))
                        .lineLimit(1)
                }

                Spacer()

                // Latency / status
                VStack(alignment: .trailing, spacing: 2) {
                    if node.health.status == .testing {
                        Text("TESTING")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.25))
                    } else if let lat = node.health.latencyMs {
                        Text("\(lat)ms")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(latencyOpacity(lat)))
                    }
                    statusLabel(node.health.status)
                }
            }
            .padding(14)

            // Action buttons
            providerActions(node)
        }
        .background(netCardBg)
    }

    private func providerPathwayIndicator(_ node: NodeConfiguration) -> some View {
        ZStack {
            // Pathway — solid for connected, dashed for disconnected
            RoundedRectangle(cornerRadius: 3)
                .fill(.white.opacity(node.isDefault ? 0.06 : 0.02))
                .frame(width: 4, height: 40)

            if node.health.status == .connected {
                // Filled pathway
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(node.isDefault ? 0.25 : 0.12))
                    .frame(width: 4, height: 40)
            } else if node.health.status == .testing {
                // Animating fill
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.15))
                    .frame(width: 4, height: 40 * constellationPulse)
                    .frame(height: 40, alignment: .bottom)
            }
        }
    }

    private func statusLabel(_ status: NodeConnectionStatus) -> some View {
        let text: String
        let opacity: Double
        switch status {
        case .connected: text = "CONNECTED"; opacity = 0.25
        case .disconnected: text = "OFFLINE"; opacity = 0.15
        case .testing: text = "TESTING"; opacity = 0.20
        case .error: text = "ERROR"; opacity = 0.18
        }
        return Text(text)
            .font(.system(size: 6, weight: .bold, design: .monospaced))
            .tracking(0.5)
            .foregroundColor(.white.opacity(opacity))
    }

    private func providerActions(_ node: NodeConfiguration) -> some View {
        HStack(spacing: 0) {
            // Test
            providerActionBtn(icon: "antenna.radiowaves.left.and.right", label: "TEST") {
                Task { await nodeManager.testNode(node.id) }
            }
            // Set default
            if !node.isDefault {
                providerActionBtn(icon: "star", label: "DEFAULT") {
                    nodeManager.setDefault(node)
                }
            }
            // Delete (if allowed)
            if nodeManager.canDeleteNode(node) && !node.isBuiltIn {
                providerActionBtn(icon: "trash", label: "REMOVE") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        nodeManager.deleteNode(node)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func providerActionBtn(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                Text(label)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.5)
            }
            .foregroundColor(.white.opacity(0.25))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.03)))
        }
        .buttonStyle(.plain)
    }

    // ── Add provider ──
    private var addProviderButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                isAddingProvider = true
                newProviderLabel = ""
                newProviderURL = ""
                newProviderKey = ""
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10))
                Text("ADD PROVIDER")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
            }
            .foregroundColor(.white.opacity(0.25))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(netCardBg)
        }
        .buttonStyle(.plain)
    }

    private var addProviderForm: some View {
        VStack(spacing: 12) {
            netSectionLabel("NEW PROVIDER")

            netTextField(placeholder: "Provider Name", text: $newProviderLabel)
            netTextField(placeholder: "https://rpc.example.com", text: $newProviderURL)
            netTextField(placeholder: "API Key (optional)", text: $newProviderKey)

            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isAddingProvider = false
                    }
                } label: {
                    Text("CANCEL")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.white.opacity(0.25))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03)))
                }
                .buttonStyle(.plain)

                Button {
                    saveNewProvider()
                } label: {
                    Text("SAVE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.white.opacity(canSaveProvider ? 0.6 : 0.15))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.white.opacity(canSaveProvider ? 0.08 : 0.02))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSaveProvider)
            }
        }
        .padding(16)
        .background(netCardBg)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func netTextField(placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.white.opacity(0.6))
            .textFieldStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.06)))
            )
    }

    private var canSaveProvider: Bool {
        !newProviderLabel.isEmpty && newProviderURL.contains("://")
    }

    private func saveNewProvider() {
        let node = NodeConfiguration(
            chain: selectedChain,
            label: newProviderLabel,
            url: newProviderURL,
            apiKey: newProviderKey.isEmpty ? nil : newProviderKey
        )
        nodeManager.addNode(node)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            isAddingProvider = false
        }
        // Auto-test new node
        Task { await nodeManager.testNode(node.id) }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Sync Status
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var syncContent: some View {
        VStack(spacing: 16) {
            netSectionLabel("BLOCK SYNC STATUS")
            ForEach(NodeChain.allCases) { chain in
                syncRow(chain)
            }
        }
    }

    private func syncRow(_ chain: NodeChain) -> some View {
        let defaultNode = nodeManager.defaultNode(for: chain)
        let height = defaultNode?.health.blockHeight
        let status = defaultNode?.health.status ?? .disconnected
        let mockNetworkHeight = mockNetworkBlockHeight(chain)
        let syncProgress = computeSyncProgress(current: height, network: mockNetworkHeight)

        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                // Sync arc — circular fill showing progress
                syncArc(progress: syncProgress, status: status)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(chain.displayName.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(0.45))

                    if let h = height {
                        HStack(spacing: 4) {
                            Text("BLOCK")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.18))
                            Text(formatBlockHeight(h))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    } else {
                        Text("NO DATA")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.12))
                    }
                }

                Spacer()

                // Sync percentage / status
                VStack(alignment: .trailing, spacing: 2) {
                    if status == .connected {
                        Text(String(format: "%.1f%%", syncProgress * 100))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    if let lastConn = defaultNode?.health.lastConnected {
                        Text(relativeTime(lastConn))
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(.white.opacity(0.15))
                    }
                }
            }
        }
        .padding(14)
        .background(netCardBg)
    }

    // ── Sync arc — circular progress ──
    private func syncArc(progress: Double, status: NodeConnectionStatus) -> some View {
        ZStack {
            // Background arc
            Circle()
                .strokeBorder(.white.opacity(0.04), lineWidth: 3)

            // Progress arc
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(.white.opacity(status == .connected ? 0.25 : 0.08), lineWidth: 3)
                .rotationEffect(.degrees(-90))

            // Center text
            if status == .connected {
                Text(String(format: "%.0f", progress * 100))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            } else if status == .testing {
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(.white.opacity(0.15), lineWidth: 2)
                    .rotationEffect(.degrees(constellationPulse * 360))
                    .frame(width: 12, height: 12)
            } else {
                Text("—")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.12))
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Health
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var healthContent: some View {
        VStack(spacing: 16) {
            netSectionLabel("DIAGNOSTICS")
            diagnosticsCard
            netSectionLabel("LATENCY MAP")
            latencyMap
            netSectionLabel("BANDWIDTH")
            bandwidthCard
        }
    }

    // ── Diagnostics — pulse test ──
    private var diagnosticsCard: some View {
        VStack(spacing: 14) {
            // Pulse visualization
            pulseVisualization

            Button {
                runDiagnostics()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 11))
                    Text(isRunningDiagnostics ? "TESTING..." : "RUN DIAGNOSTICS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                }
                .foregroundColor(.white.opacity(isRunningDiagnostics ? 0.20 : 0.40))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(.white.opacity(isRunningDiagnostics ? 0.02 : 0.05))
                )
            }
            .buttonStyle(.plain)
            .disabled(isRunningDiagnostics)
        }
        .padding(16)
        .background(netCardBg)
    }

    // ── Pulse visualization — expanding rings from center ──
    private var pulseVisualization: some View {
        ZStack {
            // Concentric pulse rings
            if isPulsing {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .strokeBorder(
                            .white.opacity(max(0, 0.15 - Double(i) * 0.04) * Double(1 - pulsePhase)),
                            lineWidth: 1.5
                        )
                        .frame(
                            width: 20 + pulsePhase * 120 + CGFloat(i) * 20,
                            height: 20 + pulsePhase * 120 + CGFloat(i) * 20
                        )
                }
            }
            // Center dot
            Circle()
                .fill(.white.opacity(isPulsing ? 0.30 : 0.10))
                .frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(.white.opacity(0.20), lineWidth: 1))

            // Result dots — positioned radially
            ForEach(Array(pulseResults.keys.sorted(by: { $0.rawValue < $1.rawValue }).enumerated()), id: \.element) { idx, chain in
                if let result = pulseResults[chain] {
                    pulseResultDot(chain: chain, result: result, index: idx, total: pulseResults.count)
                }
            }
        }
        .frame(height: 130)
    }

    private func pulseResultDot(chain: NodeChain, result: PulseResult, index: Int, total: Int) -> some View {
        let angle = constellationAngle(index: index, total: max(total, 1))
        // Distance based on latency — closer = faster
        let dist: CGFloat
        if let lat = result.latencyMs {
            dist = min(55, max(20, CGFloat(lat) / 10))
        } else {
            dist = 55
        }
        return VStack(spacing: 2) {
            Circle()
                .fill(.white.opacity(result.connected ? 0.25 : 0.06))
                .frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(.white.opacity(result.connected ? 0.15 : 0.05), lineWidth: 0.8))
            Text(chain.symbol)
                .font(.system(size: 5, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.20))
        }
        .offset(x: dist * cos(angle), y: dist * sin(angle))
    }

    // ── Latency map — proximity visualization ──
    private var latencyMap: some View {
        VStack(spacing: 4) {
            ForEach(NodeChain.allCases) { chain in
                latencyRow(chain)
            }
        }
        .background(netCardBg)
    }

    private func latencyRow(_ chain: NodeChain) -> some View {
        let node = nodeManager.defaultNode(for: chain)
        let latency = node?.health.latencyMs
        return HStack(spacing: 10) {
            Text(chain.symbol)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.30))
                .frame(width: 40, alignment: .leading)

            // Latency bar — length proportional to response time
            GeometryReader { geo in
                let maxW = geo.size.width
                let barW = latencyBarWidth(latency: latency, maxWidth: maxW)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.03))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(latencyBarOpacity(latency)))
                        .frame(width: barW, height: 4)
                }
            }
            .frame(height: 4)

            if let lat = latency {
                Text("\(lat)ms")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(latencyOpacity(lat)))
                    .frame(width: 42, alignment: .trailing)
            } else {
                Text("—")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.10))
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func latencyBarWidth(latency: Int?, maxWidth: CGFloat) -> CGFloat {
        guard let lat = latency else { return 0 }
        // Inverse — lower latency = shorter bar (closer)
        let normalized = min(1.0, CGFloat(lat) / 500.0)
        return max(4, normalized * maxWidth)
    }

    private func latencyBarOpacity(_ latency: Int?) -> Double {
        guard let lat = latency else { return 0 }
        if lat < 100 { return 0.25 }
        if lat < 300 { return 0.15 }
        return 0.08
    }

    // ── Bandwidth card ──
    private var bandwidthCard: some View {
        VStack(spacing: 8) {
            ForEach([NodeChain.bitcoin, .ethereum, .solana], id: \.self) { chain in
                bandwidthRow(chain)
            }
        }
        .padding(14)
        .background(netCardBg)
    }

    private func bandwidthRow(_ chain: NodeChain) -> some View {
        let mockData = mockBandwidth(chain)
        return HStack(spacing: 10) {
            Text(chain.symbol)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.30))
                .frame(width: 35, alignment: .leading)
            // Upload
            HStack(spacing: 3) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 7))
                    .foregroundColor(.white.opacity(0.15))
                Text(mockData.tx)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
            }
            Spacer()
            // Download
            HStack(spacing: 3) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 7))
                    .foregroundColor(.white.opacity(0.15))
                Text(mockData.rx)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Settings
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var settingsContent: some View {
        VStack(spacing: 16) {
            netSectionLabel("TESTNET MODE")
            testnetCard
            netSectionLabel("AUTO-FAILOVER")
            failoverCard
            netSectionLabel("CONNECTION")
            connectionCard
        }
    }

    private var testnetCard: some View {
        VStack(spacing: 12) {
            // Testnet visualization — dimmed parallel
            testnetVisual

            netToggle(label: "TESTNET MODE", enabled: $testnetMode)

            if testnetMode {
                Text("Connected to test networks. Balances and transactions are not real. Separate provider configurations apply.")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.25))
                    .lineSpacing(2)
            } else {
                Text("Running on mainnet. All transactions involve real assets and irreversible operations.")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.20))
                    .lineSpacing(2)
            }
        }
        .padding(16)
        .background(netCardBg)
    }

    // Testnet visual — a faded/outlined version of the network
    private var testnetVisual: some View {
        HStack(spacing: 16) {
            // Mainnet representation
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(testnetMode ? 0.04 : 0.10))
                        .frame(width: 32, height: 32)
                    Circle()
                        .strokeBorder(.white.opacity(testnetMode ? 0.06 : 0.18), lineWidth: 1.5)
                        .frame(width: 32, height: 32)
                    Text("M")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(testnetMode ? 0.15 : 0.45))
                }
                Text("MAINNET")
                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(testnetMode ? 0.10 : 0.30))
            }

            // Arrow
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.10))

            // Testnet representation
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            .white.opacity(testnetMode ? 0.18 : 0.06),
                            style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])
                        )
                        .frame(width: 32, height: 32)
                    Text("T")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(testnetMode ? 0.45 : 0.12))
                }
                Text("TESTNET")
                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(testnetMode ? 0.30 : 0.10))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var failoverCard: some View {
        VStack(spacing: 12) {
            netToggle(label: "AUTO-FAILOVER", enabled: $nodeManager.autoFailoverEnabled)
            Text("Automatically switch to backup providers when the default fails. Configurable threshold and backup order.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.20))
                .lineSpacing(2)

            if nodeManager.autoFailoverEnabled {
                Divider().background(.white.opacity(0.06))

                HStack {
                    Text("THRESHOLD")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                    Spacer()
                    failoverThresholdSelector
                }

                // Failover history
                if !nodeManager.failoverEvents.isEmpty {
                    Divider().background(.white.opacity(0.06))
                    netSectionLabel("RECENT FAILOVERS")
                    ForEach(nodeManager.failoverEvents.prefix(3)) { event in
                        failoverEventRow(event)
                    }
                }
            }
        }
        .padding(16)
        .background(netCardBg)
    }

    private var failoverThresholdSelector: some View {
        HStack(spacing: 4) {
            ForEach([2, 3, 5, 10], id: \.self) { count in
                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) { failoverThreshold = count }
                } label: {
                    Text("\(count)×")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(failoverThreshold == count ? 0.6 : 0.2))
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white.opacity(failoverThreshold == count ? 0.06 : 0.02))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func failoverEventRow(_ event: FailoverEvent) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.white.opacity(0.10))
                .frame(width: 4, height: 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(event.chain.symbol)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.30))
                    Text(event.fromNodeLabel)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.15))
                        .strikethrough(true, color: .white.opacity(0.1))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 6))
                        .foregroundColor(.white.opacity(0.10))
                    Text(event.toNodeLabel)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                }
                Text(event.reason)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.white.opacity(0.12))
            }
            Spacer()
        }
    }

    private var connectionCard: some View {
        VStack(spacing: 10) {
            // Test all chains
            Button {
                Task {
                    for chain in NodeChain.allCases {
                        await nodeManager.testAllNodes(for: chain)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 10))
                    Text("TEST ALL CONNECTIONS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                }
                .foregroundColor(.white.opacity(0.35))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
            }
            .buttonStyle(.plain)

            // Reset all
            Button {
                // Placeholder — resets node configs to defaults
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10))
                    Text("RESET TO DEFAULTS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                }
                .foregroundColor(.white.opacity(0.20))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.02)))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(netCardBg)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Shared Components
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func netSectionLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
                .tracking(1)
            Spacer()
        }
    }

    private func netToggle(label: String, enabled: Binding<Bool>) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                enabled.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 8) {
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

    private var netCardBg: some View {
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
        withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) { constellationPulse = 1.0 }
    }

    private func runDiagnostics() {
        guard !isRunningDiagnostics else { return }
        isRunningDiagnostics = true
        isPulsing = true
        pulseResults = [:]

        withAnimation(.easeOut(duration: 1.5)) { pulsePhase = 1.0 }

        // Simulate testing each chain
        Task {
            for chain in NodeChain.allCases {
                await nodeManager.testAllNodes(for: chain)
                let node = nodeManager.defaultNode(for: chain)

                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        pulseResults[chain] = PulseResult(
                            latencyMs: node?.health.latencyMs,
                            connected: node?.health.status == .connected,
                            timestamp: Date()
                        )
                    }
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }

            DispatchQueue.main.async {
                isRunningDiagnostics = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        isPulsing = false
                        pulsePhase = 0
                    }
                }
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Helpers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func connectionStats() -> (connected: Int, syncing: Int, offline: Int) {
        var conn = 0, sync = 0, off = 0
        for chain in NodeChain.allCases {
            let status = chainConnectionStatus(chain)
            switch status {
            case .connected: conn += 1
            case .testing: sync += 1
            default: off += 1
            }
        }
        return (conn, sync, off)
    }

    private func chainConnectionStatus(_ chain: NodeChain) -> NodeConnectionStatus {
        nodeManager.defaultNode(for: chain)?.health.status ?? .disconnected
    }

    private func latencyOpacity(_ ms: Int) -> Double {
        if ms < 100 { return 0.50 }
        if ms < 300 { return 0.35 }
        if ms < 1000 { return 0.25 }
        return 0.15
    }

    private func formatBlockHeight(_ h: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: h)) ?? "\(h)"
    }

    private func truncateURL(_ url: String) -> String {
        var clean = url
        if clean.hasPrefix("https://") { clean = String(clean.dropFirst(8)) }
        if clean.hasPrefix("http://") { clean = String(clean.dropFirst(7)) }
        if clean.count > 35 { clean = String(clean.prefix(32)) + "..." }
        return clean
    }

    private func relativeTime(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        return "\(Int(diff / 86400))d ago"
    }

    private func computeSyncProgress(current: UInt64?, network: UInt64) -> Double {
        guard let c = current, network > 0 else { return 0 }
        return min(1.0, Double(c) / Double(network))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Mock Data
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func mockNetworkBlockHeight(_ chain: NodeChain) -> UInt64 {
        switch chain {
        case .bitcoin:   return 882_450
        case .ethereum:  return 21_987_654
        case .solana:    return 318_452_100
        case .litecoin:  return 2_743_200
        case .monero:    return 3_245_600
        case .bnb:       return 47_123_456
        case .xrp:       return 92_345_678
        case .polygon:   return 68_901_234
        case .arbitrum:  return 312_456_789
        case .optimism:  return 134_567_890
        case .base:      return 27_890_123
        case .avalanche: return 58_901_234
        }
    }

    private func mockBandwidth(_ chain: NodeChain) -> (tx: String, rx: String) {
        switch chain {
        case .bitcoin:  return ("2.1 MB", "14.8 MB")
        case .ethereum: return ("5.3 MB", "28.4 MB")
        case .solana:   return ("8.7 MB", "42.1 MB")
        default:        return ("1.2 MB", "6.5 MB")
        }
    }
}
