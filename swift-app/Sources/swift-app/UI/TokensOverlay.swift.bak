import SwiftUI
#if os(macOS)
import AppKit
#endif

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Tokens Overlay
// Token curation command center.
// Collection tiles, drag-reorder, hold-to-hide,
// contract address scanning animation,
// spam filter with geometric strike, metadata materialization.
// Monochrome. Monumental. Curated.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// MARK: - Token Display Model

struct TkDisplayToken: Identifiable, Equatable {
    let id: UUID
    let name: String
    let symbol: String
    let contractAddress: String
    let chain: String          // "Ethereum", "Solana", "BNB Chain"
    let chainIcon: String      // SF symbol
    let decimals: Int
    let balance: Double
    let usdValue: Double
    var isVisible: Bool
    var isSpam: Bool
    var isCustom: Bool
    var sortOrder: Int

    static func == (lhs: TkDisplayToken, rhs: TkDisplayToken) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Token List Source

struct TkTokenList: Identifiable {
    let id = UUID()
    let name: String
    let source: String
    let tokenCount: Int
    var isImported: Bool
    let icon: String
}

struct TokensOverlay: View {
    @Binding var isPresented: Bool

    // ── Section nav ──
    @State private var activeSection: TkSection = .collection

    enum TkSection: String, CaseIterable {
        case collection  = "COLLECTION"
        case add         = "ADD TOKEN"
        case lists       = "LISTS"
        case spam        = "SPAM"
        case settings    = "SETTINGS"
    }

    // ── Token collection ──
    @State private var tokens: [TkDisplayToken] = []
    @State private var searchText: String = ""
    @State private var showHiddenTokens: Bool = false
    @State private var draggedToken: TkDisplayToken? = nil

    // ── Add custom token ──
    @State private var addAddress: String = ""
    @State private var addChain: String = "Ethereum"
    @State private var addScanning: Bool = false
    @State private var addScanProgress: CGFloat = 0
    @State private var addFound: Bool = false
    @State private var addError: Bool = false
    @State private var addPreviewToken: TkDisplayToken? = nil

    // ── Token lists ──
    @State private var tokenLists: [TkTokenList] = []
    @State private var importURL: String = ""

    // ── Spam filter ──
    @State private var autoHideSpam: Bool = true
    @State private var showSpamWarning: Bool = true

    // ── Token detail ──
    @State private var selectedToken: TkDisplayToken? = nil

    // ── Animation ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var silkPhase: CGFloat = 0

    // ── Hover ──
    @State private var closeHovered: Bool = false

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Body
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture { dismissOverlay() }

            // Detail sub-overlay
            if selectedToken != nil {
                tokenDetailSheet
            } else {
                mainCard
            }
        }
        .background(
            EscapeKeyHandler(isPresented: $isPresented, onEscape: dismissOverlay)
        )
        .onAppear {
            loadMockData()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardScale = 1; contentOpacity = 1
            }
            withAnimation(.linear(duration: 6.0).repeatForever(autoreverses: false)) {
                silkPhase = 1.5
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Main Card
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var mainCard: some View {
        VStack(spacing: 0) {
            tkHeader
            tkSectionPicker
            tkSectionContent
        }
        .frame(width: 460, height: 680)
        .background(tkCardBg)
        .overlay(tkCardStroke)
        .shadow(color: .black.opacity(0.5), radius: 50, y: 25)
        .scaleEffect(cardScale)
        .opacity(contentOpacity)
    }

    private var tkCardBg: some View {
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

    private var tkCardStroke: some View {
        RoundedRectangle(cornerRadius: 20)
            .strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.10), .white.opacity(0.03)],
                    startPoint: .top, endPoint: .bottom
                ), lineWidth: 1
            )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Header
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var tkHeader: some View {
        ZStack {
            Text("TOKENS")
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

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Section Picker
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var tkSectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(TkSection.allCases, id: \.self) { sec in
                    tkTabButton(sec)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 8)
    }

    private func tkTabButton(_ sec: TkSection) -> some View {
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

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Section Router
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var tkSectionContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                switch activeSection {
                case .collection: collectionContent
                case .add:        addTokenContent
                case .lists:      listsContent
                case .spam:       spamContent
                case .settings:   settingsContent
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Collection
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var collectionContent: some View {
        VStack(spacing: 14) {
            // Search bar
            searchBar

            // Stats row
            collectionStats

            // Visible tokens
            tkSectionLabel("VISIBLE TOKENS")
            visibleTokensList

            // Hidden tokens
            hiddenTokensSection
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.20))
            TextField("Search by name, symbol, or address...", text: $searchText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.60))
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.06)))
        )
    }

    private var collectionStats: some View {
        HStack(spacing: 16) {
            tkStatPill(label: "TOTAL", value: "\(tokens.count)")
            tkStatPill(label: "VISIBLE", value: "\(visibleTokens.count)")
            tkStatPill(label: "HIDDEN", value: "\(hiddenTokens.count)")
            tkStatPill(label: "SPAM", value: "\(spamTokens.count)")
            Spacer()
        }
    }

    private func tkStatPill(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.50))
            Text(label)
                .font(.system(size: 6, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.18))
        }
    }

    // ── Visible tokens ──
    private var visibleTokensList: some View {
        VStack(spacing: 4) {
            if filteredVisibleTokens.isEmpty {
                emptyState(text: searchText.isEmpty ? "No visible tokens" : "No matching tokens")
            } else {
                ForEach(filteredVisibleTokens) { token in
                    tokenTile(token: token)
                }
            }
        }
    }

    // ── Hidden tokens ──
    private var hiddenTokensSection: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    showHiddenTokens.toggle()
                }
            } label: {
                HStack {
                    Text("HIDDEN TOKENS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.white.opacity(0.25))
                    Text("(\(hiddenTokens.count))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.15))
                    Spacer()
                    Image(systemName: showHiddenTokens ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.20))
                }
            }
            .buttonStyle(.plain)

            if showHiddenTokens {
                VStack(spacing: 4) {
                    ForEach(filteredHiddenTokens) { token in
                        tokenTile(token: token)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Token Tile
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func tokenTile(token: TkDisplayToken) -> some View {
        TokenTileView(
            token: token,
            onToggleVisibility: { toggleVisibility(token) },
            onTap: { selectedToken = token }
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Add Token
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var addTokenContent: some View {
        VStack(spacing: 16) {
            if addFound, let preview = addPreviewToken {
                addTokenPreview(preview)
            } else if addScanning {
                addScanningView
            } else if addError {
                addErrorView
            } else {
                addTokenForm
            }
        }
    }

    private var addTokenForm: some View {
        VStack(spacing: 20) {
            // Chain picker
            tkSectionLabel("SELECT CHAIN")
            chainPicker

            // Contract address
            tkSectionLabel("CONTRACT ADDRESS")
            HStack(spacing: 8) {
                TextField("Paste contract address...", text: $addAddress)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.60))
                    .textFieldStyle(.plain)
                    .onSubmit { beginScan() }

                // Paste from clipboard
                Button {
                    pasteAddress()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.25))
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.04)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.06)))
            )

            // Fetch button
            Button {
                beginScan()
            } label: {
                Text("FETCH TOKEN")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(addAddress.count > 8 ? 0.50 : 0.15))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.white.opacity(addAddress.count > 8 ? 0.06 : 0.02))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(addAddress.count > 8 ? 0.12 : 0.04)))
                    )
            }
            .buttonStyle(.plain)
            .disabled(addAddress.count <= 8)

            // Supported formats
            VStack(alignment: .leading, spacing: 6) {
                tkSectionLabel("SUPPORTED FORMATS")
                addFormatRow(chain: "Ethereum / BNB Chain", example: "0x1234...abcd")
                addFormatRow(chain: "Solana", example: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
            }
        }
    }

    // Chain selector
    private var chainPicker: some View {
        HStack(spacing: 4) {
            ForEach(["Ethereum", "BNB Chain", "Solana"], id: \.self) { chain in
                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) { addChain = chain }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: chainIcon(chain))
                            .font(.system(size: 9))
                        Text(chain.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                    }
                    .foregroundColor(.white.opacity(addChain == chain ? 0.6 : 0.2))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white.opacity(addChain == chain ? 0.06 : 0.02))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(.white.opacity(addChain == chain ? 0.10 : 0.03))
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func addFormatRow(chain: String, example: String) -> some View {
        HStack {
            Text(chain)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.20))
            Spacer()
            Text(example)
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.white.opacity(0.12))
        }
    }

    // ── Scanning animation ──
    private var addScanningView: some View {
        VStack(spacing: 24) {
            // Contract address scanning visualization
            ZStack {
                // Outer rings
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .strokeBorder(
                            .white.opacity(0.03 + Double(2 - i) * 0.02),
                            lineWidth: 1
                        )
                        .frame(
                            width: CGFloat(80 + i * 24),
                            height: CGFloat(80 + i * 24)
                        )
                }
                // Scanning sweep
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(.white.opacity(0.20), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(addScanProgress * 720))

                // Center
                VStack(spacing: 3) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .light))
                        .foregroundColor(.white.opacity(0.35))
                    Text("SCANNING")
                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.20))
                }
            }
            .frame(height: 140)

            // Address being scanned
            Text(truncateAddress(addAddress))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))

            // Progress
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.04))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.18))
                        .frame(width: geo.size.width * addScanProgress)
                }
            }
            .frame(height: 3)

            Text("Fetching metadata from \(addChain)")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.18))
        }
        .padding(.top, 30)
    }

    // ── Preview card ──
    private func addTokenPreview(_ token: TkDisplayToken) -> some View {
        VStack(spacing: 20) {
            // Success badge
            ZStack {
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 60, height: 60)
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(.white.opacity(0.45))
            }

            Text("TOKEN FOUND")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.40))

            // Token preview card
            VStack(spacing: 12) {
                // Icon + name
                HStack(spacing: 12) {
                    tokenIconView(token, size: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(token.name)
                            .font(.clashGroteskBold(size: 18))
                            .foregroundColor(.white.opacity(0.75))
                        Text(token.symbol)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.30))
                    }
                    Spacer()
                }

                Divider().background(.white.opacity(0.05))

                // Metadata rows
                previewRow(label: "CHAIN", value: token.chain)
                previewRow(label: "DECIMALS", value: "\(token.decimals)")
                previewRow(label: "CONTRACT", value: truncateAddress(token.contractAddress))
            }
            .padding(16)
            .background(tkTileBg)

            // Add button
            Button {
                addTokenToCollection(token)
            } label: {
                Text("ADD TO COLLECTION")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.white.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.14)))
                    )
            }
            .buttonStyle(.plain)

            // Cancel
            Button {
                resetAddState()
            } label: {
                Text("CANCEL")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.25))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 10)
    }

    private func previewRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.18))
                .tracking(0.5)
            Spacer()
            Text(value)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
        }
    }

    // ── Error view ──
    private var addErrorView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                    .frame(width: 60, height: 60)
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(.white.opacity(0.25))
            }

            Text("TOKEN NOT FOUND")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.30))

            Text("Could not fetch metadata for this address on \(addChain). Verify the contract address and selected chain.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.20))
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Button {
                resetAddState()
            } label: {
                Text("TRY AGAIN")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.40))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 40)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Token Lists
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var listsContent: some View {
        VStack(spacing: 16) {
            tkSectionLabel("COMMUNITY TOKEN LISTS")

            ForEach(tokenLists) { list in
                tokenListRow(list)
            }

            tkSectionLabel("IMPORT CUSTOM LIST")
            customListImport
        }
    }

    private func tokenListRow(_ list: TkTokenList) -> some View {
        HStack(spacing: 12) {
            // List icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.04))
                    .frame(width: 34, height: 34)
                Image(systemName: list.icon)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.25))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(list.name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
                HStack(spacing: 6) {
                    Text(list.source)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.18))
                    Text("\(list.tokenCount) tokens")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.15))
                }
            }

            Spacer()

            Button {
                toggleListImport(list)
            } label: {
                Text(list.isImported ? "IMPORTED" : "IMPORT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(list.isImported ? 0.35 : 0.50))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white.opacity(list.isImported ? 0.03 : 0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(.white.opacity(list.isImported ? 0.05 : 0.12))
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(tkTileBg)
    }

    // Custom URL import
    private var customListImport: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.18))
                TextField("Token list URL...", text: $importURL)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.50))
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.05)))
            )

            Button {
                // Mock import
                importURL = ""
            } label: {
                Text("IMPORT FROM URL")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(importURL.isEmpty ? 0.15 : 0.40))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03)))
            }
            .buttonStyle(.plain)
            .disabled(importURL.isEmpty)
        }
        .padding(14)
        .background(tkTileBg)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Spam Filter
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var spamContent: some View {
        VStack(spacing: 16) {
            tkSectionLabel("SPAM PROTECTION")
            spamSettingsCard

            if !spamTokens.isEmpty {
                tkSectionLabel("SUSPECTED SPAM (\(spamTokens.count))")
                spamTokensList
            }

            tkSectionLabel("HOW IT WORKS")
            spamInfoCard
        }
    }

    private var spamSettingsCard: some View {
        VStack(spacing: 12) {
            tkToggleRow(label: "AUTO-HIDE SPAM TOKENS", isOn: $autoHideSpam)
            Divider().background(.white.opacity(0.04))
            tkToggleRow(label: "SHOW SPAM WARNINGS", isOn: $showSpamWarning)
        }
        .padding(14)
        .background(tkTileBg)
    }

    private var spamTokensList: some View {
        VStack(spacing: 4) {
            ForEach(spamTokens) { token in
                spamTokenRow(token)
            }
        }
    }

    private func spamTokenRow(_ token: TkDisplayToken) -> some View {
        HStack(spacing: 10) {
            // Struck icon
            ZStack {
                tokenIconView(token, size: 28)
                // Strike diagonal
                Rectangle()
                    .fill(.white.opacity(0.20))
                    .frame(width: 34, height: 1)
                    .rotationEffect(.degrees(-45))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(token.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.25))
                    .strikethrough(true, color: .white.opacity(0.15))
                Text(token.symbol + " · " + token.chain)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.12))
            }

            Spacer()

            // Dismiss / Restore
            HStack(spacing: 4) {
                Button {
                    removeToken(token)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.20))
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.03)))
                }
                .buttonStyle(.plain)

                Button {
                    unmarkSpam(token)
                } label: {
                    Text("KEEP")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.30))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.03)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.015))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 0.8, dash: [4, 3])
                        )
                        .foregroundColor(.white.opacity(0.06))
                )
        )
    }

    private var spamInfoCard: some View {
        VStack(spacing: 10) {
            spamInfoRow(icon: "exclamationmark.triangle", title: "SUSPICIOUS NAMES", detail: "Tokens impersonating well-known projects")
            Divider().background(.white.opacity(0.04))
            spamInfoRow(icon: "drop.degreesign", title: "ZERO LIQUIDITY", detail: "Tokens with no trading volume or liquidity")
            Divider().background(.white.opacity(0.04))
            spamInfoRow(icon: "clock.badge.exclamationmark", title: "RECENT CONTRACTS", detail: "Newly deployed with no history or audits")
            Divider().background(.white.opacity(0.04))
            spamInfoRow(icon: "flag", title: "COMMUNITY FLAGGED", detail: "Reported by community as potential scam")
        }
        .padding(14)
        .background(tkTileBg)
    }

    private func spamInfoRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.20))
                .frame(width: 18, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.30))
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.18))
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Settings
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var settingsContent: some View {
        VStack(spacing: 16) {
            tkSectionLabel("DISPLAY")
            displaySettingsCard

            tkSectionLabel("DEFAULTS")
            restoreDefaultsCard

            tkSectionLabel("DATA")
            dataCard
        }
    }

    private var displaySettingsCard: some View {
        VStack(spacing: 12) {
            tkToggleRow(label: "SHOW BALANCES", isOn: .constant(true))
            Divider().background(.white.opacity(0.04))
            tkToggleRow(label: "SHOW USD VALUES", isOn: .constant(true))
            Divider().background(.white.opacity(0.04))
            tkToggleRow(label: "SHOW CHAIN BADGE", isOn: .constant(true))
            Divider().background(.white.opacity(0.04))
            tkToggleRow(label: "GRAYSCALE ICONS", isOn: .constant(true))
        }
        .padding(14)
        .background(tkTileBg)
    }

    private var restoreDefaultsCard: some View {
        VStack(spacing: 12) {
            Text("Reset token visibility to HAWALA defaults. Custom tokens remain but may be hidden.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.20))
                .lineSpacing(2)

            Button {
                restoreDefaults()
            } label: {
                Text("RESTORE DEFAULT TOKENS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.40))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.03))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.06)))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(tkTileBg)
    }

    private var dataCard: some View {
        VStack(spacing: 8) {
            dataRow(label: "TOTAL TOKENS", value: "\(tokens.count)")
            dataRow(label: "CUSTOM TOKENS", value: "\(tokens.filter { $0.isCustom }.count)")
            dataRow(label: "SPAM FILTERED", value: "\(spamTokens.count)")
            dataRow(label: "TOKEN LISTS", value: "\(tokenLists.filter { $0.isImported }.count) imported")
        }
        .padding(14)
        .background(tkTileBg)
    }

    private func dataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.18))
                .tracking(0.5)
            Spacer()
            Text(value)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Token Detail Sheet
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var tokenDetailSheet: some View {
        Group {
            if let token = selectedToken {
                TokenDetailCardView(
                    token: token,
                    onDismiss: { selectedToken = nil },
                    onToggleVisibility: { toggleVisibility(token) },
                    onRemove: {
                        removeToken(token)
                        selectedToken = nil
                    }
                )
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Shared Components
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func tkSectionLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
                .tracking(1)
            Spacer()
        }
    }

    private var tkTileBg: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(.white.opacity(0.025))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.05), lineWidth: 1))
    }

    private func tkToggleRow(label: String, isOn: Binding<Bool>) -> some View {
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

    private func tokenIconView(_ token: TkDisplayToken, size: CGFloat) -> some View {
        ZStack {
            // Grayscale circle with initial
            Circle()
                .fill(.white.opacity(0.06))
                .frame(width: size, height: size)
            Text(String(token.symbol.prefix(1)))
                .font(.system(size: size * 0.4, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.30))
        }
    }

    private func emptyState(text: String) -> some View {
        Text(text)
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.white.opacity(0.15))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Computed Properties
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var visibleTokens: [TkDisplayToken] {
        tokens.filter { $0.isVisible && !$0.isSpam }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var hiddenTokens: [TkDisplayToken] {
        tokens.filter { !$0.isVisible && !$0.isSpam }
    }

    private var spamTokens: [TkDisplayToken] {
        tokens.filter { $0.isSpam }
    }

    private var filteredVisibleTokens: [TkDisplayToken] {
        let base = visibleTokens
        if searchText.isEmpty { return base }
        let q = searchText.lowercased()
        return base.filter {
            $0.name.lowercased().contains(q) ||
            $0.symbol.lowercased().contains(q) ||
            $0.contractAddress.lowercased().contains(q)
        }
    }

    private var filteredHiddenTokens: [TkDisplayToken] {
        let base = hiddenTokens
        if searchText.isEmpty { return base }
        let q = searchText.lowercased()
        return base.filter {
            $0.name.lowercased().contains(q) ||
            $0.symbol.lowercased().contains(q) ||
            $0.contractAddress.lowercased().contains(q)
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

    private func toggleVisibility(_ token: TkDisplayToken) {
        guard let idx = tokens.firstIndex(where: { $0.id == token.id }) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            tokens[idx].isVisible.toggle()
        }
    }

    private func removeToken(_ token: TkDisplayToken) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            tokens.removeAll { $0.id == token.id }
        }
    }

    private func unmarkSpam(_ token: TkDisplayToken) {
        guard let idx = tokens.firstIndex(where: { $0.id == token.id }) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            tokens[idx].isSpam = false
            tokens[idx].isVisible = true
        }
    }

    private func toggleListImport(_ list: TkTokenList) {
        guard let idx = tokenLists.firstIndex(where: { $0.id == list.id }) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            tokenLists[idx].isImported.toggle()
        }
    }

    private func restoreDefaults() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            for i in tokens.indices {
                tokens[i].isVisible = !tokens[i].isSpam && !tokens[i].isCustom
            }
            // Show default ones
            let defaults = ["BTC", "ETH", "SOL", "USDC", "USDT"]
            for i in tokens.indices where defaults.contains(tokens[i].symbol) {
                tokens[i].isVisible = true
            }
        }
    }

    // ── Add token flow ──
    private func beginScan() {
        guard addAddress.count > 8 else { return }
        addScanning = true
        addScanProgress = 0
        addError = false
        addFound = false

        withAnimation(.easeInOut(duration: 2.5)) {
            addScanProgress = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            // Simulate: 80% chance found, 20% error
            let found = Int.random(in: 0..<5) < 4
            if found {
                self.addPreviewToken = TkDisplayToken(
                    id: UUID(),
                    name: "Custom Token",
                    symbol: "CSTM",
                    contractAddress: self.addAddress,
                    chain: self.addChain,
                    chainIcon: self.chainIcon(self.addChain),
                    decimals: 18,
                    balance: 0,
                    usdValue: 0,
                    isVisible: true,
                    isSpam: false,
                    isCustom: true,
                    sortOrder: self.tokens.count
                )
                self.addFound = true
            } else {
                self.addError = true
            }
            self.addScanning = false
        }
    }

    private func addTokenToCollection(_ token: TkDisplayToken) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            tokens.append(token)
        }
        resetAddState()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            activeSection = .collection
        }
    }

    private func resetAddState() {
        addAddress = ""
        addScanning = false
        addScanProgress = 0
        addFound = false
        addError = false
        addPreviewToken = nil
    }

    private func pasteAddress() {
        #if os(macOS)
        if let str = NSPasteboard.general.string(forType: .string) {
            addAddress = str.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
    }

    // ── Helpers ──
    private func truncateAddress(_ addr: String) -> String {
        guard addr.count > 14 else { return addr }
        return String(addr.prefix(8)) + "..." + String(addr.suffix(6))
    }

    private func chainIcon(_ chain: String) -> String {
        switch chain {
        case "Ethereum": return "diamond.fill"
        case "BNB Chain": return "bitcoinsign.circle.fill"
        case "Solana":   return "sun.max.fill"
        default:         return "circle.hexagongrid.fill"
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Mock Data
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func loadMockData() {
        tokens = [
            TkDisplayToken(id: UUID(), name: "Bitcoin", symbol: "BTC", contractAddress: "native", chain: "Bitcoin", chainIcon: "bitcoinsign.circle", decimals: 8, balance: 0.2847, usdValue: 18284.30, isVisible: true, isSpam: false, isCustom: false, sortOrder: 0),
            TkDisplayToken(id: UUID(), name: "Ethereum", symbol: "ETH", contractAddress: "native", chain: "Ethereum", chainIcon: "diamond.fill", decimals: 18, balance: 4.5120, usdValue: 7891.44, isVisible: true, isSpam: false, isCustom: false, sortOrder: 1),
            TkDisplayToken(id: UUID(), name: "Solana", symbol: "SOL", contractAddress: "native", chain: "Solana", chainIcon: "sun.max.fill", decimals: 9, balance: 82.40, usdValue: 4944.00, isVisible: true, isSpam: false, isCustom: false, sortOrder: 2),
            TkDisplayToken(id: UUID(), name: "USD Coin", symbol: "USDC", contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", chain: "Ethereum", chainIcon: "diamond.fill", decimals: 6, balance: 2500.00, usdValue: 2500.00, isVisible: true, isSpam: false, isCustom: false, sortOrder: 3),
            TkDisplayToken(id: UUID(), name: "Tether", symbol: "USDT", contractAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7", chain: "Ethereum", chainIcon: "diamond.fill", decimals: 6, balance: 1200.00, usdValue: 1200.00, isVisible: true, isSpam: false, isCustom: false, sortOrder: 4),
            TkDisplayToken(id: UUID(), name: "Chainlink", symbol: "LINK", contractAddress: "0x514910771AF9Ca656af840dff83E8264EcF986CA", chain: "Ethereum", chainIcon: "diamond.fill", decimals: 18, balance: 150.75, usdValue: 1055.25, isVisible: true, isSpam: false, isCustom: false, sortOrder: 5),
            TkDisplayToken(id: UUID(), name: "Uniswap", symbol: "UNI", contractAddress: "0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984", chain: "Ethereum", chainIcon: "diamond.fill", decimals: 18, balance: 200.00, usdValue: 760.00, isVisible: true, isSpam: false, isCustom: false, sortOrder: 6),
            TkDisplayToken(id: UUID(), name: "Bonk", symbol: "BONK", contractAddress: "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263", chain: "Solana", chainIcon: "sun.max.fill", decimals: 5, balance: 42_000_000, usdValue: 840.00, isVisible: true, isSpam: false, isCustom: false, sortOrder: 7),
            TkDisplayToken(id: UUID(), name: "Wrapped BTC", symbol: "WBTC", contractAddress: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599", chain: "Ethereum", chainIcon: "diamond.fill", decimals: 8, balance: 0.05, usdValue: 3210.50, isVisible: false, isSpam: false, isCustom: false, sortOrder: 8),
            TkDisplayToken(id: UUID(), name: "Aave", symbol: "AAVE", contractAddress: "0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9", chain: "Ethereum", chainIcon: "diamond.fill", decimals: 18, balance: 12.30, usdValue: 1107.00, isVisible: false, isSpam: false, isCustom: false, sortOrder: 9),
            // Spam tokens
            TkDisplayToken(id: UUID(), name: "Free ETH Airdrop", symbol: "FETH", contractAddress: "0xdead000000000000000000000000000000000001", chain: "Ethereum", chainIcon: "diamond.fill", decimals: 18, balance: 999999.0, usdValue: 0.0, isVisible: false, isSpam: true, isCustom: false, sortOrder: 99),
            TkDisplayToken(id: UUID(), name: "USDCoin.io", symbol: "USDC2", contractAddress: "0xdead000000000000000000000000000000000002", chain: "BNB Chain", chainIcon: "bitcoinsign.circle.fill", decimals: 18, balance: 50000.0, usdValue: 0.0, isVisible: false, isSpam: true, isCustom: false, sortOrder: 100),
        ]

        tokenLists = [
            TkTokenList(name: "Uniswap Default", source: "uniswap.org", tokenCount: 372, isImported: true, icon: "hexagon.fill"),
            TkTokenList(name: "CoinGecko", source: "coingecko.com", tokenCount: 5842, isImported: false, icon: "chart.bar.fill"),
            TkTokenList(name: "1inch", source: "1inch.io", tokenCount: 1203, isImported: false, icon: "bolt.fill"),
            TkTokenList(name: "Solana Token List", source: "solana.com", tokenCount: 891, isImported: true, icon: "sun.max.fill"),
        ]
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Token Tile View (extracted sub-view)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct TokenTileView: View {
    let token: TkDisplayToken
    let onToggleVisibility: () -> Void
    let onTap: () -> Void

    @State private var isHovered: Bool = false
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        HStack(spacing: 0) {
            // Drag handle
            dragHandle

            // Token info — tap to detail
            Button(action: onTap) {
                tokenInfoRow
            }
            .buttonStyle(.plain)

            Spacer()

            // Value column
            valueColumn

            // Visibility toggle
            visibilityButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(isHovered ? 0.035 : 0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(isHovered ? 0.07 : 0.05), lineWidth: 1)
                )
        )
        .opacity(token.isVisible ? 1 : 0.50)
        .offset(dragOffset)
        .onHover { isHovered = $0 }
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = CGSize(width: 0, height: value.translation.height)
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        dragOffset = .zero
                    }
                }
        )
    }

    private var dragHandle: some View {
        VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(.white.opacity(0.10))
                    .frame(width: 10, height: 1.5)
            }
        }
        .frame(width: 20)
        .padding(.trailing, 8)
    }

    private var tokenInfoRow: some View {
        HStack(spacing: 10) {
            // Grayscale icon
            ZStack {
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 32, height: 32)
                Text(String(token.symbol.prefix(1)))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.30))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(token.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(token.symbol)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                    // Chain badge
                    HStack(spacing: 3) {
                        Image(systemName: token.chainIcon)
                            .font(.system(size: 7))
                        Text(token.chain)
                            .font(.system(size: 7, design: .monospaced))
                    }
                    .foregroundColor(.white.opacity(0.15))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.03)))
                }
            }
        }
    }

    private var valueColumn: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(formatBalance(token.balance, symbol: token.symbol))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.40))
                .lineLimit(1)
            if token.usdValue > 0 {
                Text("$\(formatUSD(token.usdValue))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.20))
            }
        }
        .padding(.trailing, 10)
    }

    private var visibilityButton: some View {
        Button(action: onToggleVisibility) {
            Image(systemName: token.isVisible ? "eye" : "eye.slash")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(token.isVisible ? 0.30 : 0.12))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.03)))
        }
        .buttonStyle(.plain)
    }

    private func formatBalance(_ b: Double, symbol: String) -> String {
        if b >= 1_000_000 {
            return String(format: "%.0f %@", b, symbol)
        } else if b >= 100 {
            return String(format: "%.2f %@", b, symbol)
        } else if b >= 1 {
            return String(format: "%.4f %@", b, symbol)
        } else {
            return String(format: "%.6f %@", b, symbol)
        }
    }

    private func formatUSD(_ val: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: val)) ?? "0.00"
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Token Detail Card (extracted sub-view)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct TokenDetailCardView: View {
    let token: TkDisplayToken
    let onDismiss: () -> Void
    let onToggleVisibility: () -> Void
    let onRemove: () -> Void

    @State private var detailScale: CGFloat = 0.92
    @State private var detailOpacity: Double = 0
    @State private var closeHovered: Bool = false
    @State private var addressCopied: Bool = false
    @State private var silkPhase: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            ScrollView(.vertical, showsIndicators: false) {
                detailBody
            }
        }
        .frame(width: 400, height: 520)
        .background(detailCardBg)
        .overlay(detailCardStroke)
        .shadow(color: .black.opacity(0.5), radius: 50, y: 25)
        .scaleEffect(detailScale)
        .opacity(detailOpacity)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                detailScale = 1; detailOpacity = 1
            }
            withAnimation(.linear(duration: 6.0).repeatForever(autoreverses: false)) {
                silkPhase = 1.5
            }
        }
    }

    private var detailCardBg: some View {
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

    private var detailCardStroke: some View {
        RoundedRectangle(cornerRadius: 20)
            .strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.10), .white.opacity(0.03)],
                    startPoint: .top, endPoint: .bottom
                ), lineWidth: 1
            )
    }

    private var detailHeader: some View {
        ZStack {
            Text("TOKEN DETAIL")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.30))
            HStack {
                Button(action: dismissDetail) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: dismissDetail) {
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
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    private var detailBody: some View {
        VStack(spacing: 18) {
            // Hero icon + name
            heroSection

            // Balance
            balanceSection

            // Metadata
            metadataSection

            // Actions
            actionsSection
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 28)
    }

    private var heroSection: some View {
        VStack(spacing: 10) {
            // Large icon
            ZStack {
                Circle()
                    .fill(.white.opacity(0.05))
                    .frame(width: 64, height: 64)
                Circle()
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    .frame(width: 64, height: 64)
                Text(String(token.symbol.prefix(1)))
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }

            Text(token.name)
                .font(.clashGroteskBold(size: 28))
                .foregroundColor(.white.opacity(0.80))

            Text(token.symbol)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.30))
        }
    }

    private var balanceSection: some View {
        VStack(spacing: 6) {
            if token.usdValue > 0 {
                Text("$\(formatDetailUSD(token.usdValue))")
                    .font(.clashGroteskBold(size: 32))
                    .foregroundColor(.white.opacity(0.70))
            }
            Text("\(formatDetailBalance(token.balance)) \(token.symbol)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.30))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.025))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.05)))
        )
    }

    private var metadataSection: some View {
        VStack(spacing: 8) {
            // Contract address (copyable)
            HStack {
                Text("CONTRACT")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.18))
                    .tracking(0.5)
                Spacer()
                Button {
                    copyAddress()
                } label: {
                    HStack(spacing: 4) {
                        Text(truncateAddr(token.contractAddress))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                        Image(systemName: addressCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 7))
                            .foregroundColor(.white.opacity(addressCopied ? 0.40 : 0.20))
                    }
                }
                .buttonStyle(.plain)
            }

            detailMetaRow(label: "CHAIN", value: token.chain)
            detailMetaRow(label: "DECIMALS", value: "\(token.decimals)")
            detailMetaRow(label: "TYPE", value: token.isCustom ? "Custom" : "Default")
            detailMetaRow(label: "VISIBILITY", value: token.isVisible ? "Visible" : "Hidden")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.025))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.05)))
        )
    }

    private func detailMetaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.18))
                .tracking(0.5)
            Spacer()
            Text(value)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 8) {
            // Toggle visibility
            Button(action: onToggleVisibility) {
                HStack(spacing: 6) {
                    Image(systemName: token.isVisible ? "eye.slash" : "eye")
                        .font(.system(size: 10))
                    Text(token.isVisible ? "HIDE TOKEN" : "SHOW TOKEN")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                }
                .foregroundColor(.white.opacity(0.40))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.08)))
                )
            }
            .buttonStyle(.plain)

            // Remove (custom only)
            if token.isCustom {
                Button(action: onRemove) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                        Text("REMOVE TOKEN")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                    }
                    .foregroundColor(.white.opacity(0.25))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.white.opacity(0.02))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(
                                        style: StrokeStyle(lineWidth: 0.8, dash: [5, 3])
                                    )
                                    .foregroundColor(.white.opacity(0.06))
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ── Helpers ──
    private func dismissDetail() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            detailScale = 0.95; detailOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onDismiss()
        }
    }

    private func copyAddress() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token.contractAddress, forType: .string)
        #endif
        addressCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { addressCopied = false }
    }

    private func truncateAddr(_ a: String) -> String {
        guard a.count > 14 else { return a }
        return String(a.prefix(8)) + "..." + String(a.suffix(6))
    }

    private func formatDetailBalance(_ b: Double) -> String {
        if b >= 1_000_000 { return String(format: "%.0f", b) }
        if b >= 100 { return String(format: "%.2f", b) }
        if b >= 1 { return String(format: "%.4f", b) }
        return String(format: "%.6f", b)
    }

    private func formatDetailUSD(_ val: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: val)) ?? "0.00"
    }
}
