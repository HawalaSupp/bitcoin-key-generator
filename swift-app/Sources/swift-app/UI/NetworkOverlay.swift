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
    var onBackToSettings: (() -> Void)? = nil

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
    @State private var newProviderRequiresAuth: Bool = false
    @State private var newProviderAuthToken: String = ""

    // ── Edit node ──
    @State private var editingNodeId: UUID? = nil
    @State private var editLabel: String = ""
    @State private var editURL: String = ""
    @State private var editKey: String = ""
    @State private var editAuthToken: String = ""
    @State private var editRequiresAuth: Bool = false

    // ── Delete confirmation ──
    @State private var confirmDeleteNodeId: UUID? = nil

    // ── API Key editing ──
    @State private var editingAPIKeyType: String? = nil
    @State private var apiKeyDraft: String = ""

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

    // ── Network mode ──
    @AppStorage("hawala.selectedNetwork") private var selectedNetwork: String = "mainnet"
    @AppStorage("hawala.customRpcUrl") private var customRpcUrl: String = ""
    @State private var testnetMode: Bool = false
    @State private var isTestingCustomRpc: Bool = false
    @State private var customRpcTestResult: String? = nil

    // ── Failover ──
    @State private var failoverThreshold: Int = 3

    // ── Animation ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var silkPhase: CGFloat = 0
    @State private var constellationPulse: CGFloat = 0

    // ── Hover ──
    @State private var closeHovered: Bool = false
    @State private var backHovered: Bool = false

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
        .frame(width: 540, height: 720)
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
                .font(.clashGroteskMedium(size: 15))
                .tracking(3)
                .foregroundColor(.white.opacity(0.6))
            HStack {
                if onBackToSettings != nil {
                    Button {
                        dismissOverlay()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            onBackToSettings?()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text("SETTINGS")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(0.5)
                        }
                        .foregroundColor(.white.opacity(backHovered ? 0.8 : 0.35))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(.white.opacity(backHovered ? 0.10 : 0.04))
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { backHovered = $0 }
                }
                Spacer()
                Button(action: dismissOverlay) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(closeHovered ? 0.9 : 0.45))
                        .frame(width: 30, height: 30)
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
            netStatusDot(label: label)
            Text("\(count)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(count > 0 ? 0.7 : 0.20))
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(count > 0 ? 0.40 : 0.15))
        }
    }

    private func netStatusDot(label: String) -> some View {
        ZStack {
            if label == "CONNECTED" {
                Circle()
                    .fill(.white.opacity(0.40))
                    .frame(width: 7, height: 7)
            } else if label == "SYNCING" {
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(.white.opacity(0.30), lineWidth: 1.5)
                    .frame(width: 7, height: 7)
                    .rotationEffect(.degrees(constellationPulse * 360))
            } else {
                Circle()
                    .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    .frame(width: 7, height: 7)
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
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(selected ? 0.85 : 0.35))
                    .padding(.horizontal, 10)
                RoundedRectangle(cornerRadius: 1)
                    .fill(.white.opacity(selected ? 0.5 : 0))
                    .frame(height: 2)
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
    // MARK: – Topology (Chain Status)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var topologyContent: some View {
        VStack(spacing: 16) {
            netSectionLabel("CHAIN STATUS")
            chainStatusList
            testAllChainsButton
        }
    }

    private var chainStatusList: some View {
        VStack(spacing: 2) {
            ForEach(NodeChain.allCases) { chain in
                chainStatusRow(chain)
            }
        }
        .background(netCardBg)
    }

    private func chainStatusRow(_ chain: NodeChain) -> some View {
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
                chainStatusDot(status)
                    .frame(width: 14, height: 14)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(chain.symbol)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundColor(.white.opacity(isSelected ? 0.75 : 0.50))
                        Text(chain.displayName.uppercased())
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.30))
                    }
                    if let node = defaultNode {
                        Text(node.label)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.white.opacity(0.22))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if let lat = defaultNode?.health.latencyMs {
                        Text("\(lat)ms")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(latencyOpacity(lat)))
                    }
                    if let height = defaultNode?.health.blockHeight {
                        Text("#\(formatBlockHeight(height))")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.white.opacity(0.22))
                    } else if let lastConn = defaultNode?.health.lastConnected {
                        Text(relativeTime(lastConn))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.white.opacity(0.18))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? Color.white.opacity(0.03) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func chainStatusDot(_ status: NodeConnectionStatus) -> some View {
        ZStack {
            switch status {
            case .connected:
                Circle()
                    .fill(.white.opacity(0.35))
                    .overlay(Circle().strokeBorder(.white.opacity(0.20), lineWidth: 1))
            case .testing:
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(.white.opacity(0.25), lineWidth: 1.5)
                    .rotationEffect(.degrees(constellationPulse * 360))
            case .disconnected, .error:
                Circle()
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
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

    private var testAllChainsButton: some View {
        Button {
            runDiagnostics()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 10))
                Text(isRunningDiagnostics ? "TESTING..." : "TEST ALL CHAINS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.5)
            }
            .foregroundColor(.white.opacity(isRunningDiagnostics ? 0.25 : 0.45))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(isRunningDiagnostics ? 0.02 : 0.04))
            )
        }
        .buttonStyle(.plain)
        .disabled(isRunningDiagnostics)
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
            netSectionLabel("API KEYS")
            apiKeysSection
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
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundColor(.white.opacity(node.isDefault ? 0.70 : 0.45))

                        if node.isDefault {
                            Text("DEFAULT")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundColor(.white.opacity(0.35))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(.white.opacity(0.05))
                                )
                        }
                    }

                    // URL truncated
                    Text(truncateURL(node.url))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.22))
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

            // Inline edit form
            if editingNodeId == node.id {
                editNodeForm(node)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
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
        case .connected: text = "CONNECTED"; opacity = 0.35
        case .disconnected: text = "OFFLINE"; opacity = 0.20
        case .testing: text = "TESTING"; opacity = 0.28
        case .error: text = "ERROR"; opacity = 0.25
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
            // Edit
            providerActionBtn(icon: "pencil", label: editingNodeId == node.id ? "CLOSE" : "EDIT") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    if editingNodeId == node.id {
                        editingNodeId = nil
                    } else {
                        editingNodeId = node.id
                        editLabel = node.label
                        editURL = node.url
                        editKey = node.apiKey ?? ""
                        editAuthToken = node.authToken ?? ""
                        editRequiresAuth = node.requiresAuth
                    }
                }
            }
            // Delete (if allowed) — two-tap confirm
            if nodeManager.canDeleteNode(node) && !node.isBuiltIn {
                if confirmDeleteNodeId == node.id {
                    providerActionBtn(icon: "exclamationmark.triangle", label: "CONFIRM?", isDestructive: true) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            nodeManager.deleteNode(node)
                            confirmDeleteNodeId = nil
                            if editingNodeId == node.id { editingNodeId = nil }
                        }
                    }
                } else {
                    providerActionBtn(icon: "trash", label: "REMOVE") {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                            confirmDeleteNodeId = node.id
                        }
                        // Auto-reset after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                if confirmDeleteNodeId == node.id { confirmDeleteNodeId = nil }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func providerActionBtn(icon: String, label: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                Text(label)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.5)
            }
            .foregroundColor(isDestructive ? .red.opacity(0.65) : .white.opacity(0.35))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 5).fill(isDestructive ? .red.opacity(0.08) : .white.opacity(0.04)))
        }
        .buttonStyle(.plain)
    }

    // ── Inline edit node form ──
    private func editNodeForm(_ node: NodeConfiguration) -> some View {
        VStack(spacing: 10) {
            Rectangle().fill(.white.opacity(0.06)).frame(height: 1)

            netSectionLabel("EDIT NODE")

            netTextField(placeholder: "Label", text: $editLabel)
            netTextField(placeholder: "https://rpc.example.com", text: $editURL)
            netTextField(placeholder: "API Key (optional)", text: $editKey)

            HStack(spacing: 8) {
                Text("REQUIRES AUTH")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.25))
                Spacer()
                netToggle(label: "", enabled: $editRequiresAuth)
            }

            if editRequiresAuth {
                netTextField(placeholder: "Auth Token", text: $editAuthToken)
            }

            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        editingNodeId = nil
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
                    saveEditedNode(node)
                } label: {
                    Text("SAVE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.white.opacity(canSaveEdit ? 0.6 : 0.15))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.white.opacity(canSaveEdit ? 0.08 : 0.02))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSaveEdit)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private var canSaveEdit: Bool {
        !editLabel.isEmpty && editURL.contains("://")
    }

    private func saveEditedNode(_ node: NodeConfiguration) {
        var updated = node
        updated.label = editLabel
        updated.url = editURL
        updated.apiKey = editKey.isEmpty ? nil : editKey
        updated.requiresAuth = editRequiresAuth
        updated.authToken = editRequiresAuth ? (editAuthToken.isEmpty ? nil : editAuthToken) : nil
        nodeManager.updateNode(updated)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            editingNodeId = nil
        }
    }

    // ── Add provider ──
    private var addProviderButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                isAddingProvider = true
                newProviderLabel = ""
                newProviderURL = ""
                newProviderKey = ""
                newProviderRequiresAuth = false
                newProviderAuthToken = ""
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10))
                Text("ADD PROVIDER")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
            }
            .foregroundColor(.white.opacity(0.35))
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
                Text("REQUIRES AUTH")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.25))
                Spacer()
                netToggle(label: "", enabled: $newProviderRequiresAuth)
            }

            if newProviderRequiresAuth {
                netTextField(placeholder: "Auth Token", text: $newProviderAuthToken)
            }

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
            apiKey: newProviderKey.isEmpty ? nil : newProviderKey,
            requiresAuth: newProviderRequiresAuth,
            authToken: newProviderRequiresAuth ? (newProviderAuthToken.isEmpty ? nil : newProviderAuthToken) : nil
        )
        nodeManager.addNode(node)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            isAddingProvider = false
        }
        // Auto-test new node
        Task { await nodeManager.testNode(node.id) }
    }

    // ── API Keys Section ──

    private var apiKeysSection: some View {
        VStack(spacing: 2) {
            apiKeyRow(name: "ALCHEMY", configured: APIKeys.shared.hasAlchemyKey, keyType: "alchemy")
            apiKeyRow(name: "MORALIS", configured: APIKeys.shared.hasMoralisKey, keyType: "moralis")
            apiKeyRow(name: "TATUM", configured: APIKeys.shared.hasTatumKey, keyType: "tatum")
            apiKeyRow(name: "COINGECKO", configured: APIKeys.shared.hasCoinGeckoKey, keyType: "coingecko")
        }
        .background(netCardBg)
    }

    private func apiKeyRow(name: String, configured: Bool, keyType: String) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    if editingAPIKeyType == keyType {
                        editingAPIKeyType = nil
                        apiKeyDraft = ""
                    } else {
                        editingAPIKeyType = keyType
                        apiKeyDraft = currentAPIKeyValue(keyType) ?? ""
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(name)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(0.50))

                    Spacer()

                    Text(configured ? "CONFIGURED" : "NOT SET")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(configured ? 0.35 : 0.15))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white.opacity(configured ? 0.04 : 0.02))
                        )

                    Image(systemName: editingAPIKeyType == keyType ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.20))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if editingAPIKeyType == keyType {
                apiKeyEditor(keyType: keyType)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func apiKeyEditor(keyType: String) -> some View {
        VStack(spacing: 8) {
            netTextField(placeholder: "Paste API key...", text: $apiKeyDraft)

            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        editingAPIKeyType = nil
                        apiKeyDraft = ""
                    }
                } label: {
                    Text("CANCEL")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(0.25))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.03)))
                }
                .buttonStyle(.plain)

                Button {
                    saveAPIKey(keyType: keyType, value: apiKeyDraft)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        editingAPIKeyType = nil
                        apiKeyDraft = ""
                    }
                } label: {
                    Text("SAVE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(!apiKeyDraft.isEmpty ? 0.50 : 0.15))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.white.opacity(!apiKeyDraft.isEmpty ? 0.06 : 0.02))
                        )
                }
                .buttonStyle(.plain)
                .disabled(apiKeyDraft.isEmpty)

                if currentAPIKeyValue(keyType) != nil {
                    Button {
                        removeAPIKey(keyType: keyType)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            editingAPIKeyType = nil
                            apiKeyDraft = ""
                        }
                    } label: {
                        Text("REMOVE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundColor(.white.opacity(0.20))
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.02)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 12)
    }

    private func currentAPIKeyValue(_ keyType: String) -> String? {
        switch keyType {
        case "alchemy":
            let k = APIKeys.shared.alchemyAPIKey
            return k.isEmpty ? nil : k
        case "moralis":  return APIKeys.shared.moralisKey
        case "tatum":    return APIKeys.shared.tatumKey
        case "coingecko": return APIKeys.shared.coinGeckoKey
        default: return nil
        }
    }

    private func saveAPIKey(keyType: String, value: String) {
        switch keyType {
        case "alchemy":  APIKeys.setAlchemyKey(value)
        case "moralis":  APIKeys.setMoralisKey(value)
        case "tatum":    APIKeys.setTatumKey(value)
        case "coingecko": APIKeys.setCoinGeckoKey(value)
        default: break
        }
    }

    private func removeAPIKey(keyType: String) {
        switch keyType {
        case "alchemy":  APIKeys.removeAlchemyKey()
        case "moralis":  APIKeys.removeMoralisKey()
        case "tatum":    APIKeys.removeTatumKey()
        case "coingecko": APIKeys.removeCoinGeckoKey()
        default: break
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Sync Status
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var syncContent: some View {
        VStack(spacing: 16) {
            netSectionLabel("BLOCK HEIGHTS")
            ForEach(NodeChain.allCases) { chain in
                syncRow(chain)
            }
            refreshAllButton
        }
    }

    private func syncRow(_ chain: NodeChain) -> some View {
        let defaultNode = nodeManager.defaultNode(for: chain)
        let height = defaultNode?.health.blockHeight
        let status = defaultNode?.health.status ?? .disconnected

        return HStack(spacing: 10) {
            syncStatusIndicator(status)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(chain.displayName.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.55))

                if let h = height {
                    HStack(spacing: 4) {
                        Text("BLOCK")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.25))
                        Text(formatBlockHeight(h))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.60))
                    }
                } else {
                    Text("—")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.18))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                statusLabel(status)
                if let lastConn = defaultNode?.health.lastConnected {
                    Text(relativeTime(lastConn))
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.white.opacity(0.12))
                }
            }
        }
        .padding(14)
        .background(netCardBg)
    }

    private func syncStatusIndicator(_ status: NodeConnectionStatus) -> some View {
        ZStack {
            Circle()
                .strokeBorder(.white.opacity(0.04), lineWidth: 2.5)

            switch status {
            case .connected:
                Circle()
                    .trim(from: 0, to: 1)
                    .stroke(.white.opacity(0.25), lineWidth: 2.5)
                    .rotationEffect(.degrees(-90))
            case .testing:
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(.white.opacity(0.15), lineWidth: 2)
                    .rotationEffect(.degrees(constellationPulse * 360))
            case .disconnected, .error:
                EmptyView()
            }
        }
    }

    private var refreshAllButton: some View {
        Button {
            Task {
                for chain in NodeChain.allCases {
                    await nodeManager.testAllNodes(for: chain)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
                Text("REFRESH ALL")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.5)
            }
            .foregroundColor(.white.opacity(0.30))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03)))
        }
        .buttonStyle(.plain)
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
            netSectionLabel("PROVIDER HEALTH")
            providerHealthCard
        }
    }

    // ── Diagnostics — pulse test ──
    private var diagnosticsCard: some View {
        VStack(spacing: 14) {
            if !pulseResults.isEmpty {
                diagnosticsResultList
            } else {
                diagnosticsEmptyState
            }

            Button {
                runDiagnostics()
            } label: {
                HStack(spacing: 6) {
                    if isRunningDiagnostics {
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(.white.opacity(0.30), lineWidth: 1.5)
                            .frame(width: 12, height: 12)
                            .rotationEffect(.degrees(constellationPulse * 360))
                    } else {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 12))
                    }
                    Text(isRunningDiagnostics ? "TESTING..." : "RUN DIAGNOSTICS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1)
                }
                .foregroundColor(.white.opacity(isRunningDiagnostics ? 0.25 : 0.50))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(.white.opacity(isRunningDiagnostics ? 0.02 : 0.06))
                )
            }
            .buttonStyle(.plain)
            .disabled(isRunningDiagnostics)
        }
        .padding(16)
        .background(netCardBg)
    }

    private var diagnosticsEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.12))
            Text("Run diagnostics to test all chain connections")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.20))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var diagnosticsResultList: some View {
        VStack(spacing: 4) {
            ForEach(NodeChain.allCases) { chain in
                if let result = pulseResults[chain] {
                    diagnosticsResultRow(chain: chain, result: result)
                }
            }
        }
    }

    private func diagnosticsResultRow(chain: NodeChain, result: PulseResult) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.white.opacity(result.connected ? 0.35 : 0.08))
                .frame(width: 8, height: 8)

            Text(chain.symbol)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
                .frame(width: 45, alignment: .leading)

            Text(chain.displayName)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))

            Spacer()

            if let lat = result.latencyMs {
                Text("\(lat)ms")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(latencyOpacity(lat)))
            } else {
                Text("FAIL")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.15))
            }

            Text(result.connected ? "OK" : "ERR")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(result.connected ? 0.35 : 0.15))
                .frame(width: 28)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    // ── Latency map — bar visualization ──
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
        let normalized = min(1.0, CGFloat(lat) / 500.0)
        return max(4, normalized * maxWidth)
    }

    private func latencyBarOpacity(_ latency: Int?) -> Double {
        guard let lat = latency else { return 0 }
        if lat < 100 { return 0.25 }
        if lat < 300 { return 0.15 }
        return 0.08
    }

    // ── Provider health — status from ProviderHealthManager ──
    private var providerHealthCard: some View {
        let manager = ProviderHealthManager.shared
        return VStack(spacing: 4) {
            ForEach(ProviderType.allCases) { provider in
                providerHealthRow(provider, status: manager.providerStatuses[provider])
            }
        }
        .background(netCardBg)
    }

    private func providerHealthRow(_ provider: ProviderType, status: ProviderStatus?) -> some View {
        let state = status?.state ?? .unknown
        return HStack(spacing: 10) {
            providerHealthDot(state)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(provider.displayName.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.3)
                    .foregroundColor(.white.opacity(0.45))
                Text(provider.category.rawValue.uppercased())
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.18))
            }

            Spacer()

            Text(providerStateLabel(state))
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.3)
                .foregroundColor(.white.opacity(providerStateOpacity(state)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func providerHealthDot(_ state: ProviderHealthState) -> some View {
        Circle().fill(.white.opacity(
            state == .healthy ? 0.40 :
            state == .unknown ? 0.12 :
            0.20
        ))
    }

    private func providerStateLabel(_ state: ProviderHealthState) -> String {
        switch state {
        case .healthy: return "HEALTHY"
        case .degraded: return "DEGRADED"
        case .offline: return "OFFLINE"
        case .unknown: return "UNKNOWN"
        }
    }

    private func providerStateOpacity(_ state: ProviderHealthState) -> Double {
        switch state {
        case .healthy: return 0.40
        case .degraded: return 0.30
        case .offline: return 0.22
        case .unknown: return 0.15
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Settings
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var settingsContent: some View {
        VStack(spacing: 16) {
            netSectionLabel("NETWORK MODE")
            networkModeCard
            if selectedNetwork == "custom" {
                customRpcCard
            }
            netSectionLabel("AUTO-FAILOVER")
            failoverCard
            netSectionLabel("CONNECTION")
            connectionCard
        }
    }

    // ── Network mode selector — mainnet / testnet / custom ──
    private var networkModeCard: some View {
        VStack(spacing: 12) {
            networkModeVisual

            // Radio options
            VStack(spacing: 6) {
                networkModeOption(
                    mode: "mainnet",
                    label: "MAINNET",
                    description: "Production network. All transactions involve real assets."
                )
                networkModeOption(
                    mode: "testnet",
                    label: "TESTNET",
                    description: "Test network. Balances and transactions are not real."
                )
                networkModeOption(
                    mode: "custom",
                    label: "CUSTOM RPC",
                    description: "Connect to a custom RPC endpoint."
                )
            }
        }
        .padding(16)
        .background(netCardBg)
    }

    private func networkModeOption(mode: String, label: String, description: String) -> some View {
        let isSelected = selectedNetwork == mode
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedNetwork = mode
                testnetMode = (mode == "testnet")
            }
        } label: {
            HStack(spacing: 10) {
                // Radio indicator
                ZStack {
                    Circle()
                        .strokeBorder(.white.opacity(isSelected ? 0.35 : 0.10), lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                    if isSelected {
                        Circle()
                            .fill(.white.opacity(0.45))
                            .frame(width: 8, height: 8)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(isSelected ? 0.60 : 0.30))
                    Text(description)
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(isSelected ? 0.25 : 0.15))
                }

                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(isSelected ? 0.04 : 0.01))
            )
        }
        .buttonStyle(.plain)
    }

    // ── Custom RPC card ──
    private var customRpcCard: some View {
        VStack(spacing: 10) {
            netTextField(placeholder: "https://your-rpc-endpoint.com", text: $customRpcUrl)

            HStack(spacing: 8) {
                Button {
                    testCustomRpc()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 9))
                        Text(isTestingCustomRpc ? "TESTING..." : "TEST CONNECTION")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                    }
                    .foregroundColor(.white.opacity(isTestingCustomRpc ? 0.20 : 0.35))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
                }
                .buttonStyle(.plain)
                .disabled(isTestingCustomRpc || customRpcUrl.isEmpty)
            }

            if let result = customRpcTestResult {
                Text(result)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.30))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(netCardBg)
    }

    private func testCustomRpc() {
        guard !customRpcUrl.isEmpty else { return }
        isTestingCustomRpc = true
        customRpcTestResult = nil

        let tempNode = NodeConfiguration(
            chain: .ethereum,
            label: "Custom RPC Test",
            url: customRpcUrl
        )
        nodeManager.addNode(tempNode)

        Task {
            await nodeManager.testNode(tempNode.id)
            if let tested = nodeManager.nodes.first(where: { $0.id == tempNode.id }) {
                if tested.health.status == .connected {
                    let latency = tested.health.latencyMs.map { "\($0)ms" } ?? "?"
                    customRpcTestResult = "Connected — \(latency) latency"
                } else {
                    customRpcTestResult = tested.health.lastError ?? "Connection failed"
                }
                nodeManager.nodes.removeAll { $0.id == tempNode.id }
                nodeManager.saveNodes()
            } else {
                customRpcTestResult = "Test interrupted"
            }
            isTestingCustomRpc = false
        }
    }

    // ── Network mode visual — M / T / C circles ──
    private var networkModeVisual: some View {
        HStack(spacing: 12) {
            networkModeCircle(letter: "M", label: "MAINNET", isActive: selectedNetwork == "mainnet")

            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.08))

            networkModeCircle(letter: "T", label: "TESTNET", isActive: selectedNetwork == "testnet", isDashed: true)

            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.08))

            networkModeCircle(letter: "C", label: "CUSTOM", isActive: selectedNetwork == "custom", isDashed: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func networkModeCircle(letter: String, label: String, isActive: Bool, isDashed: Bool = false) -> some View {
        VStack(spacing: 4) {
            ZStack {
                if isDashed {
                    Circle()
                        .strokeBorder(
                            .white.opacity(isActive ? 0.18 : 0.06),
                            style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])
                        )
                        .frame(width: 28, height: 28)
                } else {
                    Circle()
                        .fill(.white.opacity(isActive ? 0.10 : 0.04))
                        .frame(width: 28, height: 28)
                    Circle()
                        .strokeBorder(.white.opacity(isActive ? 0.18 : 0.06), lineWidth: 1.5)
                        .frame(width: 28, height: 28)
                }
                Text(letter)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(isActive ? 0.45 : 0.12))
            }
            Text(label)
                .font(.system(size: 6, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(isActive ? 0.30 : 0.10))
        }
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

                    HStack {
                        netSectionLabel("FAILOVER LOG")
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                nodeManager.failoverEvents.removeAll()
                            }
                        } label: {
                            Text("CLEAR")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .tracking(0.5)
                                .foregroundColor(.white.opacity(0.20))
                        }
                        .buttonStyle(.plain)
                    }

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 2) {
                            ForEach(nodeManager.failoverEvents) { event in
                                failoverEventRow(event)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
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
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    nodeManager.nodes = NodeManager.defaultNodes()
                    nodeManager.saveNodes()
                }
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
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
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
}
