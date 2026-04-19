import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Multisig Overlay
// Multi-signature wallet management — distributed trust infrastructure.
// Geometric lock polygons, orbital co-signer nodes,
// signature ring progress, mechanical piece assembly.
// Monumental. Monochrome. Precision.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct MultisigOverlay: View {
    @Binding var isPresented: Bool

    // ── View mode ──
    @State private var selectedTab: MSTab = .wallets

    enum MSTab: String, CaseIterable {
        case wallets = "VAULTS"
        case pending = "PENDING"
        case history = "HISTORY"
    }

    // ── Wallets ──
    @State private var msWallets: [MSWallet] = []
    @State private var expandedWalletId: String? = nil

    // ── Pending ──
    @State private var pendingTxs: [MSPendingTx] = []
    @State private var signingTxId: String? = nil
    @State private var signAnimPhase: CGFloat = 0

    // ── Create flow ──
    @State private var showCreate: Bool = false
    @State private var createM: Int = 2
    @State private var createN: Int = 3
    @State private var createAddresses: [String] = ["", "", ""]
    @State private var createName: String = ""

    // ── History ──
    @State private var completedTxs: [MSCompletedTx] = []

    // ── Animation ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var silkPhase: CGFloat = 0

    // ── Hover ──
    @State private var closeHovered: Bool = false
    @State private var createBtnHovered: Bool = false

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Body
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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
            loadData()
            startAnimations()
        }
    }

    private var backdrop: some View {
        Color.black.opacity(0.75)
            .ignoresSafeArea()
            .onTapGesture { dismissOverlay() }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Card Container
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Header
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var headerBar: some View {
        ZStack {
            Text("MULTISIG")
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

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Tab Bar
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(MSTab.allCases, id: \.self) { tab in
                msTabButton(tab)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }

    private func msTabButton(_ tab: MSTab) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedTab = tab
                showCreate = false
            }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text(tab.rawValue)
                        .font(.clashGroteskMedium(size: 12))
                        .tracking(2)
                        .foregroundColor(.white.opacity(selectedTab == tab ? 0.8 : 0.3))

                    if tab == .pending {
                        let count = pendingTxs.count
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(.white.opacity(0.08)))
                        }
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

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Tab Content
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var tabContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                switch selectedTab {
                case .wallets: walletsTabContent
                case .pending: pendingTabContent
                case .history: historyTabContent
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Wallets Tab
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var walletsTabContent: some View {
        VStack(spacing: 16) {
            if showCreate {
                createWalletForm
            } else {
                createButton
            }

            ForEach(msWallets) { wallet in
                walletCard(wallet)
            }
        }
    }

    // -- Create button --
    private var createButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                showCreate = true
                createM = 2
                createN = 3
                createName = ""
                createAddresses = ["", "", ""]
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 13))
                Text("NEW VAULT")
                    .font(.clashGroteskMedium(size: 12))
                    .tracking(1)
            }
            .foregroundColor(.white.opacity(createBtnHovered ? 0.7 : 0.45))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.white.opacity(createBtnHovered ? 0.15 : 0.08),
                                  style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            )
        }
        .buttonStyle(.plain)
        .onHover { createBtnHovered = $0 }
    }

    // -- Create wallet form --
    private var createWalletForm: some View {
        VStack(spacing: 16) {
            createFormHeader
            thresholdSelector
            addressInputs
            assembleButton
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var createFormHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("CONFIGURE VAULT")
                    .font(.clashGroteskMedium(size: 11))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.4))
                TextField("Vault Name", text: $createName)
                    .font(.clashGroteskMedium(size: 14))
                    .foregroundColor(.white.opacity(0.8))
                    .textFieldStyle(.plain)
            }
            Spacer()
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    showCreate = false
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

    // -- Threshold selector (M-of-N) --
    private var thresholdSelector: some View {
        VStack(spacing: 10) {
            // M-of-N display
            thresholdFractionDisplay

            HStack(spacing: 20) {
                nStepper
                mStepper
            }
        }
    }

    private var thresholdFractionDisplay: some View {
        HStack(spacing: 6) {
            Text("\(createM)")
                .font(.clashGroteskBold(size: 36))
                .foregroundColor(.white.opacity(0.9))
            Text("of")
                .font(.clashGroteskMedium(size: 14))
                .foregroundColor(.white.opacity(0.3))
            Text("\(createN)")
                .font(.clashGroteskBold(size: 36))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private var nStepper: some View {
        VStack(spacing: 4) {
            Text("SIGNERS")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
            HStack(spacing: 12) {
                stepperBtn(icon: "minus") {
                    if createN > 2 {
                        createN -= 1
                        if createM > createN { createM = createN }
                        syncAddressSlots()
                    }
                }
                Text("\(createN)")
                    .font(.clashGroteskMedium(size: 16))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 20)
                stepperBtn(icon: "plus") {
                    if createN < 7 {
                        createN += 1
                        syncAddressSlots()
                    }
                }
            }
        }
    }

    private var mStepper: some View {
        VStack(spacing: 4) {
            Text("REQUIRED")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
            HStack(spacing: 12) {
                stepperBtn(icon: "minus") {
                    if createM > 1 { createM -= 1 }
                }
                Text("\(createM)")
                    .font(.clashGroteskMedium(size: 16))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 20)
                stepperBtn(icon: "plus") {
                    if createM < createN { createM += 1 }
                }
            }
        }
    }

    private func stepperBtn(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) { action() }
        }) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 24, height: 24)
                .background(Circle().fill(.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    // -- Address inputs --
    private var addressInputs: some View {
        VStack(spacing: 8) {
            ForEach(0..<createAddresses.count, id: \.self) { i in
                addressInputRow(index: i)
            }
        }
    }

    private func addressInputRow(index: Int) -> some View {
        HStack(spacing: 8) {
            signerSegmentIcon(index: index, total: createN, filled: !createAddresses[index].isEmpty)

            TextField("Co-signer \(index + 1) public key", text: $createAddresses[index])
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.white.opacity(createAddresses[index].isEmpty ? 0.05 : 0.12), lineWidth: 1)
                )
        )
    }

    // -- Assemble --
    private var assembleButton: some View {
        Button {
            assembleVault()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 12))
                Text("ASSEMBLE VAULT")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundColor(.white.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Wallet Card (Geometric lock)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func walletCard(_ w: MSWallet) -> some View {
        let isExpanded = expandedWalletId == w.id
        return VStack(spacing: 0) {
            walletCardHeader(w, isExpanded: isExpanded)

            if isExpanded {
                walletCardExpanded(w)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(isExpanded ? 0.04 : 0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(isExpanded ? 0.10 : 0.05), lineWidth: 1)
                )
        )
    }

    private func walletCardHeader(_ w: MSWallet, isExpanded: Bool) -> some View {
        HStack(spacing: 14) {
            // Geometric lock polygon
            geometricLock(n: w.totalSigners, filled: w.requiredSigs)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(w.name)
                    .font(.clashGroteskMedium(size: 14))
                    .foregroundColor(.white.opacity(0.85))
                Text("\(w.requiredSigs)-of-\(w.totalSigners)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer()

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.25))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                expandedWalletId = isExpanded ? nil : w.id
            }
        }
    }

    private func walletCardExpanded(_ w: MSWallet) -> some View {
        VStack(spacing: 14) {
            Divider().background(.white.opacity(0.06))

            // Co-signer orbit
            cosignerOrbit(wallet: w)

            // Address
            if let addr = w.address {
                HStack {
                    Text(truncatedAddr(addr))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                    Button {
                        #if canImport(AppKit)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(addr, forType: .string)
                        #endif
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // -- Geometric lock: polygon with N sides, M segments filled --
    private func geometricLock(n: Int, filled: Int) -> some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 - 2
            let sides = max(n, 3)

            ZStack {
                // Draw each segment
                ForEach(0..<sides, id: \.self) { i in
                    polygonSegment(center: center, radius: radius, index: i, total: sides, isFilled: i < filled)
                }

                // Center keyhole
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
    }

    private func polygonSegment(center: CGPoint, radius: CGFloat, index: Int, total: Int, isFilled: Bool) -> some View {
        let startAngle = (2 * .pi / Double(total)) * Double(index) - .pi / 2
        let endAngle = (2 * .pi / Double(total)) * Double(index + 1) - .pi / 2
        let p1x = center.x + radius * CGFloat(cos(startAngle))
        let p1y = center.y + radius * CGFloat(sin(startAngle))
        let p2x = center.x + radius * CGFloat(cos(endAngle))
        let p2y = center.y + radius * CGFloat(sin(endAngle))

        return Path { path in
            path.move(to: CGPoint(x: p1x, y: p1y))
            path.addLine(to: CGPoint(x: p2x, y: p2y))
        }
        .stroke(.white.opacity(isFilled ? 0.6 : 0.12), lineWidth: isFilled ? 2.5 : 1)
    }

    // -- Signer segment for create form --
    private func signerSegmentIcon(index: Int, total: Int, filled: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(.white.opacity(filled ? 0.30 : 0.08), lineWidth: 1.5)
                .frame(width: 18, height: 18)
            if filled {
                Circle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 8, height: 8)
            }
        }
    }

    // -- Co-signer orbit --
    private func cosignerOrbit(wallet: MSWallet) -> some View {
        let signers = wallet.cosigners
        let count = max(signers.count, 1)
        return ZStack {
            Circle()
                .strokeBorder(.white.opacity(0.05), lineWidth: 1)
                .frame(width: 100, height: 100)

            ForEach(Array(signers.enumerated()), id: \.element.id) { idx, signer in
                cosignerNode(signer: signer, index: idx, total: count)
            }

            // Center: wallet name
            Text(String(wallet.name.prefix(2)).uppercased())
                .font(.clashGroteskBold(size: 12))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(height: 120)
    }

    private func cosignerNode(signer: MSCosigner, index: Int, total: Int) -> some View {
        let angle = (2 * .pi / Double(total)) * Double(index) - .pi / 2
        let r: CGFloat = 44
        let xOff = r * CGFloat(cos(angle))
        let yOff = r * CGFloat(sin(angle))
        let isConnected = signer.hasKey
        return VStack(spacing: 2) {
            Circle()
                .fill(.white.opacity(isConnected ? 0.12 : 0.03))
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(isConnected ? 0.35 : 0.08), lineWidth: 1)
                )
            Text(signer.label)
                .font(.system(size: 7, weight: .medium))
                .foregroundColor(.white.opacity(isConnected ? 0.5 : 0.2))
        }
        .offset(x: xOff, y: yOff)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Pending Tab
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var pendingTabContent: some View {
        VStack(spacing: 14) {
            if pendingTxs.isEmpty {
                emptyPending
            } else {
                ForEach(pendingTxs) { tx in
                    pendingTxCard(tx)
                }
            }
        }
    }

    private var emptyPending: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 26))
                .foregroundColor(.white.opacity(0.12))
            Text("No pending transactions")
                .font(.clashGroteskMedium(size: 13))
                .foregroundColor(.white.opacity(0.25))
        }
        .padding(.vertical, 40)
    }

    private func pendingTxCard(_ tx: MSPendingTx) -> some View {
        VStack(spacing: 14) {
            pendingTxHeader(tx)
            sigRingAndSigners(tx)
            signActionRow(tx)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func pendingTxHeader(_ tx: MSPendingTx) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.description)
                    .font(.clashGroteskMedium(size: 13))
                    .foregroundColor(.white.opacity(0.8))
                Text("to \(truncatedAddr(tx.recipient))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(tx.amount)
                    .font(.clashGroteskBold(size: 16))
                    .foregroundColor(.white.opacity(0.85))
                Text(tx.timeAgo)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.25))
            }
        }
    }

    // -- Signature ring + signer nodes --
    private func sigRingAndSigners(_ tx: MSPendingTx) -> some View {
        HStack(spacing: 16) {
            sigRing(collected: tx.collectedSigs, required: tx.requiredSigs, total: tx.totalSigners)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(tx.signers) { signer in
                    signerRow(signer)
                }
            }
        }
    }

    // -- Circular signature ring --
    private func sigRing(collected: Int, required: Int, total: Int) -> some View {
        ZStack {
            // Background ring segments
            ForEach(0..<total, id: \.self) { i in
                ringSegment(index: i, total: total, isSigned: i < collected)
            }

            // Center fraction
            VStack(spacing: 0) {
                Text("\(collected)")
                    .font(.clashGroteskBold(size: 18))
                    .foregroundColor(.white.opacity(0.85))
                Rectangle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 16, height: 1)
                Text("\(required)")
                    .font(.clashGroteskMedium(size: 12))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }

    private func ringSegment(index: Int, total: Int, isSigned: Bool) -> some View {
        let gap: Double = 0.02
        let segSize: Double = (1.0 / Double(total)) - gap
        let start: Double = Double(index) / Double(total) + gap / 2
        return Circle()
            .trim(from: CGFloat(start), to: CGFloat(start + segSize))
            .stroke(
                .white.opacity(isSigned ? 0.55 : 0.10),
                style: StrokeStyle(lineWidth: isSigned ? 3.5 : 2, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
    }

    private func signerRow(_ signer: MSSigner) -> some View {
        HStack(spacing: 6) {
            // Geometric piece — filled square if signed, hollow if not
            RoundedRectangle(cornerRadius: 3)
                .fill(.white.opacity(signer.hasSigned ? 0.15 : 0))
                .frame(width: 12, height: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(.white.opacity(signer.hasSigned ? 0.40 : 0.12), lineWidth: signer.hasSigned ? 1.5 : 1)
                )

            Text(signer.label)
                .font(.system(size: 10, weight: signer.hasSigned ? .semibold : .regular))
                .foregroundColor(.white.opacity(signer.hasSigned ? 0.65 : 0.30))

            if signer.isYou {
                Text("YOU")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.white.opacity(0.06)))
            }
        }
    }

    // -- Sign action --
    private func signActionRow(_ tx: MSPendingTx) -> some View {
        let canSign = tx.signers.contains(where: { $0.isYou && !$0.hasSigned })
        let isSigning = signingTxId == tx.id
        return Group {
            if canSign {
                Button {
                    performSign(tx)
                } label: {
                    signButtonContent(isSigning: isSigning)
                }
                .buttonStyle(.plain)
                .disabled(isSigning)
            } else if tx.collectedSigs >= tx.requiredSigs {
                broadcastLabel
            }
        }
    }

    private func signButtonContent(isSigning: Bool) -> some View {
        HStack(spacing: 6) {
            if isSigning {
                signAnimatingPiece
            } else {
                Image(systemName: "signature")
                    .font(.system(size: 11))
                Text("SIGN TRANSACTION")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
        }
        .foregroundColor(.white.opacity(isSigning ? 0.4 : 0.7))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(isSigning ? 0.04 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.white.opacity(isSigning ? 0.06 : 0.12), lineWidth: 1)
                )
        )
    }

    private var signAnimatingPiece: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.4))
                .frame(width: 8, height: 8)
                .rotationEffect(.degrees(signAnimPhase * 90))
            Text("SIGNING...")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
        }
    }

    private var broadcastLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "paperplane")
                .font(.system(size: 11))
            Text("READY TO BROADCAST")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
        }
        .foregroundColor(.white.opacity(0.55))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.05))
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – History Tab
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var historyTabContent: some View {
        VStack(spacing: 10) {
            if completedTxs.isEmpty {
                emptyHistory
            } else {
                ForEach(completedTxs) { tx in
                    historyRow(tx)
                }
            }
        }
    }

    private var emptyHistory: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 26))
                .foregroundColor(.white.opacity(0.12))
            Text("No completed transactions")
                .font(.clashGroteskMedium(size: 13))
                .foregroundColor(.white.opacity(0.25))
        }
        .padding(.vertical, 40)
    }

    private func historyRow(_ tx: MSCompletedTx) -> some View {
        HStack(spacing: 12) {
            // Completed lock geomety
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 28, height: 28)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.45))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.description)
                    .font(.clashGroteskMedium(size: 12))
                    .foregroundColor(.white.opacity(0.65))
                Text(tx.walletName)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(tx.amount)
                    .font(.clashGroteskMedium(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                Text(tx.dateLabel)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.025))
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Shared
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func truncatedAddr(_ addr: String) -> String {
        guard addr.count > 12 else { return addr }
        return String(addr.prefix(6)) + "..." + String(addr.suffix(4))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Actions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func dismissOverlay() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            cardScale = 0.95
            contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isPresented = false
        }
    }

    private func syncAddressSlots() {
        while createAddresses.count < createN {
            createAddresses.append("")
        }
        while createAddresses.count > createN {
            createAddresses.removeLast()
        }
    }

    private func assembleVault() {
        let name = createName.isEmpty ? "\(createM)-of-\(createN) Vault" : createName
        let cosigners: [MSCosigner] = (0..<createN).map { i in
            MSCosigner(
                id: UUID().uuidString,
                label: "Signer \(i + 1)",
                publicKey: createAddresses[i].isEmpty ? "pk_\(UUID().uuidString.prefix(8))" : createAddresses[i],
                hasKey: !createAddresses[i].isEmpty
            )
        }
        let wallet = MSWallet(
            id: UUID().uuidString,
            name: name,
            requiredSigs: createM,
            totalSigners: createN,
            cosigners: cosigners,
            address: "bc1q" + UUID().uuidString.prefix(32).lowercased(),
            createdAt: Date()
        )
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            msWallets.append(wallet)
            showCreate = false
        }
    }

    private func performSign(_ tx: MSPendingTx) {
        signingTxId = tx.id

        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            signAnimPhase = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            DispatchQueue.main.async {
                if let idx = pendingTxs.firstIndex(where: { $0.id == tx.id }) {
                    // Mark user's signer as signed
                    for si in pendingTxs[idx].signers.indices {
                        if pendingTxs[idx].signers[si].isYou && !pendingTxs[idx].signers[si].hasSigned {
                            pendingTxs[idx].signers[si].hasSigned = true
                            pendingTxs[idx].collectedSigs += 1
                            break
                        }
                    }
                }
                signingTxId = nil
                signAnimPhase = 0
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Data
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func loadData() {
        // 2-of-3 wallet
        let w1Cosigners: [MSCosigner] = [
            MSCosigner(id: "c1", label: "You", publicKey: "02a1b2c3d4...", hasKey: true),
            MSCosigner(id: "c2", label: "Alice", publicKey: "03e5f6a7b8...", hasKey: true),
            MSCosigner(id: "c3", label: "Bob", publicKey: "02c9d0e1f2...", hasKey: true)
        ]
        let w1 = MSWallet(
            id: "w1", name: "Team Treasury",
            requiredSigs: 2, totalSigners: 3,
            cosigners: w1Cosigners,
            address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
            createdAt: Date().addingTimeInterval(-86400 * 60)
        )

        // 3-of-5 wallet
        let w2Cosigners: [MSCosigner] = [
            MSCosigner(id: "c4", label: "You", publicKey: "02aa11bb22...", hasKey: true),
            MSCosigner(id: "c5", label: "CFO", publicKey: "03cc33dd44...", hasKey: true),
            MSCosigner(id: "c6", label: "CTO", publicKey: "02ee55ff66...", hasKey: true),
            MSCosigner(id: "c7", label: "Legal", publicKey: "03a1b2c3d4...", hasKey: true),
            MSCosigner(id: "c8", label: "Board", publicKey: "02e5f6a7b8...", hasKey: false)
        ]
        let w2 = MSWallet(
            id: "w2", name: "Corporate Cold",
            requiredSigs: 3, totalSigners: 5,
            cosigners: w2Cosigners,
            address: "bc1q9h5yjqka2msmq5pf6lxlwsyf7ehyjl7d9epxz",
            createdAt: Date().addingTimeInterval(-86400 * 120)
        )

        msWallets = [w1, w2]

        // Pending tx 1: 1 of 2 sigs collected
        let tx1Signers: [MSSigner] = [
            MSSigner(id: "s1", label: "You", isYou: true, hasSigned: false),
            MSSigner(id: "s2", label: "Alice", isYou: false, hasSigned: true),
            MSSigner(id: "s3", label: "Bob", isYou: false, hasSigned: false)
        ]
        let tx1 = MSPendingTx(
            id: "tx1", walletId: "w1", walletName: "Team Treasury",
            description: "Send BTC", amount: "0.15 BTC",
            recipient: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            collectedSigs: 1, requiredSigs: 2, totalSigners: 3,
            signers: tx1Signers, timeAgo: "2h ago"
        )

        // Pending tx 2: 2 of 2 sigs (ready to broadcast)
        let tx2Signers: [MSSigner] = [
            MSSigner(id: "s4", label: "You", isYou: true, hasSigned: true),
            MSSigner(id: "s5", label: "Alice", isYou: false, hasSigned: true),
            MSSigner(id: "s6", label: "Bob", isYou: false, hasSigned: false)
        ]
        let tx2 = MSPendingTx(
            id: "tx2", walletId: "w1", walletName: "Team Treasury",
            description: "Pay Invoice #427", amount: "0.025 BTC",
            recipient: "bc1q0sg9rdst255gtldsmcf8rk0764avqy2h2rl9kf",
            collectedSigs: 2, requiredSigs: 2, totalSigners: 3,
            signers: tx2Signers, timeAgo: "5h ago"
        )

        pendingTxs = [tx1, tx2]

        completedTxs = [
            MSCompletedTx(id: "h1", walletName: "Team Treasury", description: "Vendor Payment", amount: "0.5 BTC", dateLabel: "Jan 15"),
            MSCompletedTx(id: "h2", walletName: "Corporate Cold", description: "Quarterly Reserve", amount: "2.0 BTC", dateLabel: "Jan 8"),
            MSCompletedTx(id: "h3", walletName: "Team Treasury", description: "Dev Bounty", amount: "0.08 BTC", dateLabel: "Dec 22")
        ]
    }

    private func startAnimations() {
        withAnimation(.linear(duration: 6.0).repeatForever(autoreverses: false)) {
            silkPhase = 1.5
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Models
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct MSWallet: Identifiable {
    let id: String
    let name: String
    let requiredSigs: Int
    let totalSigners: Int
    let cosigners: [MSCosigner]
    let address: String?
    let createdAt: Date
}

struct MSCosigner: Identifiable {
    let id: String
    let label: String
    let publicKey: String
    let hasKey: Bool
}

struct MSPendingTx: Identifiable {
    let id: String
    let walletId: String
    let walletName: String
    let description: String
    let amount: String
    let recipient: String
    var collectedSigs: Int
    let requiredSigs: Int
    let totalSigners: Int
    var signers: [MSSigner]
    let timeAgo: String
}

struct MSSigner: Identifiable {
    let id: String
    let label: String
    let isYou: Bool
    var hasSigned: Bool
}

struct MSCompletedTx: Identifiable {
    let id: String
    let walletName: String
    let description: String
    let amount: String
    let dateLabel: String
}
