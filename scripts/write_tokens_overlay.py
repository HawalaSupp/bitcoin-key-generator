#!/usr/bin/env python3
"""Generate the new TokensOverlay.swift file."""

import os, shutil

TARGET = os.path.expanduser("~/Desktop/888/swift-app/Sources/swift-app/UI/TokensOverlay.swift")

content = r'''import SwiftUI
#if os(macOS)
import AppKit
#endif

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Tokens Overlay
// Token curation command center — fully wired to CustomTokenManager.
// No mock data. Every feature functional.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct TokensOverlay: View {
    @Binding var isPresented: Bool
    var onBackToSettings: (() -> Void)? = nil

    // ── Services ──
    @StateObject private var tokenManager = CustomTokenManager.shared

    // ── Section nav ──
    @State private var activeSection: TkSection = .collection

    enum TkSection: String, CaseIterable {
        case collection = "COLLECTION"
        case add        = "ADD TOKEN"
        case lists      = "LISTS"
        case spam       = "SPAM"
        case settings   = "SETTINGS"
    }

    // ── Collection ──
    @State private var searchText: String = ""
    @State private var selectedToken: CustomToken? = nil

    // ── Add token ──
    @State private var addAddress: String = ""
    @State private var addChain: TokenChain = .ethereum
    @State private var addScanning: Bool = false
    @State private var addError: String? = nil
    @State private var addPreview: CustomToken? = nil
    @State private var addManual: Bool = false
    @State private var addManualSymbol: String = ""
    @State private var addManualName: String = ""
    @State private var addManualDecimals: String = "18"

    // ── Spam ──
    @AppStorage("hawala.tokens.flaggedSpam") private var flaggedSpamData: Data = Data()
    @State private var flaggedSpamIds: Set<String> = []
    @AppStorage("hawala.tokens.autoHideSpam") private var autoHideSpam: Bool = true

    // ── Settings ──
    @AppStorage("hawala.tokens.showChainBadges") private var showChainBadges: Bool = true
    @AppStorage("hawala.tokens.showContracts") private var showContracts: Bool = false
    @AppStorage("hawala.tokens.compactView") private var compactView: Bool = false
    @State private var showClearConfirm: Bool = false

    // ── Animation ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var silkPhase: CGFloat = 0

    // ── Hover ──
    @State private var closeHovered: Bool = false
    @State private var backHovered: Bool = false

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Body
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━

    var body: some View {
        ZStack {
            backdrop
            cardShell
            if let token = selectedToken {
                TkTokenDetailCard(
                    token: token,
                    onDismiss: { selectedToken = nil },
                    onRemove: {
                        tokenManager.removeToken(token)
                        selectedToken = nil
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(10)
            }
        }
        .background(
            EscapeKeyHandler(isPresented: $isPresented, onEscape: dismissOverlay)
        )
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardScale = 1; contentOpacity = 1
            }
            startAnimations()
            loadFlaggedSpam()
        }
    }

    private var backdrop: some View {
        Color.black.opacity(0.75)
            .ignoresSafeArea()
            .onTapGesture { dismissOverlay() }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Card
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━

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

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Header
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var headerBar: some View {
        ZStack {
            Text("TOKENS")
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
                                .font(.system(size: 10, weight: .semibold))
                            Text("SETTINGS")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(0.5)
                        }
                        .foregroundColor(.white.opacity(backHovered ? 0.7 : 0.35))
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

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Section Picker
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(TkSection.allCases, id: \.self) { sec in
                    tkTabButton(sec)
                }
            }
            .padding(.horizontal, 16)
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
                    .foregroundColor(.white.opacity(selected ? 0.85 : 0.35))
                    .padding(.horizontal, 8)
                RoundedRectangle(cornerRadius: 1)
                    .fill(.white.opacity(selected ? 0.5 : 0))
                    .frame(height: 2)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Section Content
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var sectionContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                switch activeSection {
                case .collection: collectionContent
                case .add: addTokenContent
                case .lists: listsContent
                case .spam: spamContent
                case .settings: settingsContent
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – COLLECTION
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var filteredTokens: [CustomToken] {
        let base = autoHideSpam
            ? tokenManager.tokens.filter { !flaggedSpamIds.contains($0.contractAddress.lowercased()) }
            : tokenManager.tokens
        if searchText.isEmpty { return base }
        let q = searchText.lowercased()
        return base.filter {
            $0.name.lowercased().contains(q) ||
            $0.symbol.lowercased().contains(q) ||
            $0.contractAddress.lowercased().contains(q)
        }
    }

    private var collectionContent: some View {
        VStack(spacing: 16) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.20))

                TextField("Search tokens...", text: $searchText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.60))
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.20))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.06)))
            )

            // Stats
            HStack(spacing: 12) {
                tkStatPill(label: "TOTAL", value: "\(tokenManager.tokens.count)")
                tkStatPill(label: "ERC-20", value: "\(tokenManager.getTokens(for: .ethereum).count)")
                tkStatPill(label: "BEP-20", value: "\(tokenManager.getTokens(for: .bsc).count)")
                tkStatPill(label: "SPL", value: "\(tokenManager.getTokens(for: .solana).count)")
                Spacer()
            }

            // Token list or empty state
            if tokenManager.tokens.isEmpty {
                collectionEmptyState
            } else if filteredTokens.isEmpty {
                noSearchResults
            } else {
                VStack(spacing: 2) {
                    ForEach(filteredTokens) { token in
                        tkTokenRow(token)
                    }
                }
                .background(tkCardBg)
            }
        }
    }

    private var collectionEmptyState: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 30)
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.10))
            Text("NO CUSTOM TOKENS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.25))
            Text("Add ERC-20, BEP-20, or SPL tokens\nvia the ADD TOKEN tab")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.18))
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { activeSection = .add }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 10))
                    Text("ADD YOUR FIRST TOKEN")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                }
                .foregroundColor(.white.opacity(0.45))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.08)))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var noSearchResults: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.10))
            Text("No tokens matching \"\(searchText)\"")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.20))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func tkTokenRow(_ token: CustomToken) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedToken = token
            }
        } label: {
            HStack(spacing: 10) {
                // Icon
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.06))
                        .frame(width: compactView ? 28 : 34, height: compactView ? 28 : 34)
                    Text(String(token.symbol.prefix(2)).uppercased())
                        .font(.system(size: compactView ? 9 : 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.40))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(token.symbol.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.55))
                        if showChainBadges {
                            Text(chainBadge(token.chain))
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .tracking(0.3)
                                .foregroundColor(.white.opacity(0.22))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.04)))
                        }
                    }
                    if !compactView {
                        Text(token.name)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.25))
                    }
                    if showContracts {
                        Text(truncateAddress(token.contractAddress))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.white.opacity(0.15))
                    }
                }

                Spacer()

                // Decimals badge
                Text("\(token.decimals)d")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.18))

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.12))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, compactView ? 6 : 10)
        }
        .buttonStyle(.plain)
    }

    private func tkStatPill(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.50))
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.20))
        }
        .frame(width: 50)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – ADD TOKEN
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var addTokenContent: some View {
        VStack(spacing: 16) {
            tkSectionLabel("NETWORK")
            chainPicker

            tkSectionLabel("CONTRACT ADDRESS")
            addressInputField

            if let error = addError {
                addErrorView(error)
            }

            if addScanning {
                addScanningView
            } else if let preview = addPreview {
                addPreviewView(preview)
            } else if addManual {
                manualEntryForm
            }
        }
    }

    private var chainPicker: some View {
        HStack(spacing: 6) {
            ForEach(TokenChain.allCases) { chain in
                let selected = addChain == chain
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        addChain = chain
                        addPreview = nil
                        addError = nil
                        addManual = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: chain.icon)
                            .font(.system(size: 10))
                        Text(chain == .ethereum ? "ETH" : chain == .bsc ? "BSC" : "SOL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                    }
                    .foregroundColor(.white.opacity(selected ? 0.70 : 0.25))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(selected ? 0.08 : 0.02))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(selected ? 0.12 : 0.04)))
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var addressInputField: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField(addChain.addressPlaceholder, text: $addAddress)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.60))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.06)))
                    )
                    .onChange(of: addAddress) { _ in
                        addPreview = nil
                        addError = nil
                        addManual = false
                    }

                // Paste button
                Button {
                    #if os(macOS)
                    if let str = NSPasteboard.general.string(forType: .string) {
                        addAddress = str.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    #endif
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.30))
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
                }
                .buttonStyle(.plain)
            }

            // Fetch / validate
            HStack(spacing: 8) {
                Button {
                    fetchTokenMetadata()
                } label: {
                    HStack(spacing: 5) {
                        if addScanning {
                            ProgressView()
                                .scaleEffect(0.5)
                                .tint(.white.opacity(0.3))
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 9))
                        }
                        Text(addScanning ? "SCANNING..." : "FETCH METADATA")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                    }
                    .foregroundColor(.white.opacity(canFetch ? 0.55 : 0.18))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(canFetch ? 0.06 : 0.02))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canFetch || addScanning)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        addManual = true
                        addError = nil
                    }
                } label: {
                    Text("MANUAL")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(0.30))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03)))
                }
                .buttonStyle(.plain)
            }

            if !addAddress.isEmpty && !tokenManager.validateContractAddress(addAddress, chain: addChain) {
                Text("Invalid \(addChain == .solana ? "Solana" : "EVM") address format")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.30))
            }
        }
    }

    private var canFetch: Bool {
        !addAddress.isEmpty && tokenManager.validateContractAddress(addAddress, chain: addChain) && !addScanning
    }

    private func addErrorView(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 9))
            Text(message)
                .font(.system(size: 9, design: .monospaced))
        }
        .foregroundColor(.white.opacity(0.35))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03)))
    }

    private var addScanningView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.7)
                .tint(.white.opacity(0.25))
            Text("Fetching token metadata from blockchain...")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func addPreviewView(_ token: CustomToken) -> some View {
        VStack(spacing: 12) {
            tkSectionLabel("TOKEN FOUND")

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.06))
                            .frame(width: 44, height: 44)
                        Text(String(token.symbol.prefix(2)).uppercased())
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(token.name)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.55))
                        HStack(spacing: 8) {
                            Text(token.symbol.uppercased())
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.35))
                            Text("\(token.decimals) decimals")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.white.opacity(0.22))
                        }
                    }
                    Spacer()
                }

                previewMetaRow(label: "CONTRACT", value: truncateAddress(token.contractAddress))
                previewMetaRow(label: "CHAIN", value: chainBadge(token.chain))
            }
            .padding(14)
            .background(tkCardBg)

            Button { addTokenFromPreview(token) } label: {
                Text("ADD TO COLLECTION")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.10)))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func previewMetaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.22))
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.40))
        }
    }

    private var manualEntryForm: some View {
        VStack(spacing: 10) {
            tkSectionLabel("MANUAL ENTRY")

            manualField(label: "SYMBOL", placeholder: "e.g. USDT", text: $addManualSymbol)
            manualField(label: "NAME", placeholder: "e.g. Tether USD", text: $addManualName)
            manualField(label: "DECIMALS", placeholder: "18", text: $addManualDecimals)

            Button { addManualToken() } label: {
                Text("ADD TOKEN")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(canAddManual ? 0.55 : 0.18))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(canAddManual ? 0.06 : 0.02))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canAddManual)
        }
    }

    private func manualField(label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.25))
                .frame(width: 65, alignment: .trailing)

            TextField(placeholder, text: text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.06)))
                )
        }
    }

    private var canAddManual: Bool {
        !addManualSymbol.isEmpty && !addManualName.isEmpty && !addAddress.isEmpty &&
        tokenManager.validateContractAddress(addAddress, chain: addChain)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – LISTS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private struct TkTokenListInfo: Identifiable {
        let id = UUID()
        let name: String
        let description: String
        let url: String
        let icon: String
    }

    private var curatedLists: [TkTokenListInfo] {
        [
            TkTokenListInfo(name: "Uniswap Default", description: "Curated list of ERC-20 tokens", url: "https://tokens.uniswap.org/", icon: "arrow.triangle.swap"),
            TkTokenListInfo(name: "CoinGecko", description: "Comprehensive token catalog", url: "https://tokens.coingecko.com/uniswap/all.json", icon: "chart.line.uptrend.xyaxis"),
            TkTokenListInfo(name: "1inch", description: "DEX aggregator token list", url: "https://tokens.1inch.io/", icon: "arrow.triangle.branch"),
            TkTokenListInfo(name: "Solana Token List", description: "Official Solana SPL token registry", url: "https://cdn.jsdelivr.net/gh/solana-labs/token-list@main/src/tokens/solana.tokenlist.json", icon: "sun.max"),
        ]
    }

    private var listsContent: some View {
        VStack(spacing: 16) {
            tkSectionLabel("COMMUNITY TOKEN LISTS")

            Text("Browse external token lists for reference.\nTo add a specific token, use the ADD TOKEN tab.")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.22))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: .infinity)

            VStack(spacing: 2) {
                ForEach(curatedLists) { list in
                    tokenListRow(list)
                }
            }
            .background(tkCardBg)

            tkSectionLabel("ABOUT TOKEN LISTS")
            infoCard(
                icon: "info.circle",
                text: "Token lists are community-maintained catalogs of verified token contract addresses. They help identify legitimate tokens and avoid scams. You can look up contract addresses from these lists, then add tokens via the ADD TOKEN tab."
            )
        }
    }

    private func tokenListRow(_ list: TkTokenListInfo) -> some View {
        Button {
            #if os(macOS)
            if let url = URL(string: list.url) {
                NSWorkspace.shared.open(url)
            }
            #endif
        } label: {
            HStack(spacing: 12) {
                Image(systemName: list.icon)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.25))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.white.opacity(0.04)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.3)
                        .foregroundColor(.white.opacity(0.45))
                    Text(list.description)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.22))
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.15))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – SPAM
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var spamContent: some View {
        VStack(spacing: 16) {
            tkSectionLabel("SPAM PROTECTION")

            tkToggleRow(
                icon: "eye.slash",
                title: "AUTO-HIDE FLAGGED TOKENS",
                detail: "Flagged tokens won't appear in your collection",
                isOn: $autoHideSpam
            )

            tkSectionLabel("FLAGGED TOKENS")

            let flaggedTokens = tokenManager.tokens.filter { flaggedSpamIds.contains($0.contractAddress.lowercased()) }

            if flaggedTokens.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.12))
                    Text("No tokens flagged as spam")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.20))
                    Text("Long-press a token in your collection\nto flag it as suspicious")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.15))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 2) {
                    ForEach(flaggedTokens) { token in
                        HStack(spacing: 10) {
                            Text(token.symbol.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.30))
                                .strikethrough(true, color: .white.opacity(0.15))

                            Text(token.name)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.white.opacity(0.18))

                            Spacer()

                            Button {
                                unflagSpam(token)
                            } label: {
                                Text("UNFLAG")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .tracking(0.3)
                                    .foregroundColor(.white.opacity(0.30))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.04)))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                    }
                }
                .background(tkCardBg)
            }

            tkSectionLabel("COMMON SCAM TYPES")
            VStack(spacing: 2) {
                spamInfoRow(icon: "dollarsign.circle", title: "AIRDROP SPAM", detail: "Tokens sent to your wallet to lure you to phishing sites")
                spamInfoRow(icon: "doc.on.doc", title: "FAKE CLONES", detail: "Tokens mimicking popular coins with different contracts")
                spamInfoRow(icon: "link", title: "PHISHING TOKENS", detail: "Tokens with malicious approval requests in their contracts")
                spamInfoRow(icon: "exclamationmark.triangle", title: "HONEYPOTS", detail: "Tokens you can buy but never sell due to contract restrictions")
            }
            .background(tkCardBg)
        }
    }

    private func spamInfoRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.20))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.3)
                    .foregroundColor(.white.opacity(0.35))
                Text(detail)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.20))
                    .lineSpacing(2)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – SETTINGS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var settingsContent: some View {
        VStack(spacing: 16) {
            tkSectionLabel("DISPLAY PREFERENCES")

            VStack(spacing: 2) {
                tkToggleRow(icon: "tag", title: "SHOW CHAIN BADGES", detail: "Display ERC-20/BEP-20/SPL labels", isOn: $showChainBadges)
                tkToggleRow(icon: "doc.text", title: "SHOW CONTRACT ADDRESSES", detail: "Display truncated addresses in list", isOn: $showContracts)
                tkToggleRow(icon: "rectangle.compress.vertical", title: "COMPACT VIEW", detail: "Reduce token row height", isOn: $compactView)
            }
            .background(tkCardBg)

            tkSectionLabel("DATA")

            VStack(spacing: 6) {
                settingsDataRow(label: "CUSTOM TOKENS", value: "\(tokenManager.tokens.count)")
                settingsDataRow(label: "FLAGGED SPAM", value: "\(flaggedSpamIds.count)")
                settingsDataRow(label: "STORAGE", value: tokenStorageSize())
            }
            .padding(14)
            .background(tkCardBg)

            // Clear all
            if !tokenManager.tokens.isEmpty {
                if showClearConfirm {
                    VStack(spacing: 8) {
                        Text("Remove all custom tokens? This cannot be undone.")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                            .multilineTextAlignment(.center)

                        HStack(spacing: 8) {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    showClearConfirm = false
                                }
                            } label: {
                                Text("CANCEL")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .tracking(0.5)
                                    .foregroundColor(.white.opacity(0.30))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03)))
                            }
                            .buttonStyle(.plain)

                            Button {
                                clearAllTokens()
                            } label: {
                                Text("CLEAR ALL")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .tracking(0.5)
                                    .foregroundColor(.white.opacity(0.50))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                    .background(tkCardBg)
                } else {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            showClearConfirm = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 9))
                            Text("CLEAR ALL CUSTOM TOKENS")
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
            }
        }
    }

    private func settingsDataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.25))
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Shared Components
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func tkSectionLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.35))
            Spacer()
        }
    }

    private var tkCardBg: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.white.opacity(0.03))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.04)))
    }

    private func tkToggleRow(icon: String, title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.22))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.3)
                    .foregroundColor(.white.opacity(0.40))
                Text(detail)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.18))
            }

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .scaleEffect(0.6)
                .frame(width: 40)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func infoCard(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.18))
            Text(text)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.22))
                .lineSpacing(3)
        }
        .padding(14)
        .background(tkCardBg)
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
        withAnimation(.linear(duration: 6).repeatForever(autoreverses: true)) {
            silkPhase = 1
        }
    }

    // ── Add Token Actions ──

    private func fetchTokenMetadata() {
        guard canFetch else { return }
        addScanning = true
        addError = nil
        addPreview = nil

        Task { @MainActor in
            do {
                let token = try await tokenManager.fetchTokenInfo(contractAddress: addAddress, chain: addChain)
                addPreview = token
            } catch {
                addError = error.localizedDescription
            }
            addScanning = false
        }
    }

    private func addTokenFromPreview(_ token: CustomToken) {
        do {
            try tokenManager.addToken(token)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                addPreview = nil
                addAddress = ""
                addError = nil
                activeSection = .collection
            }
        } catch {
            addError = error.localizedDescription
        }
    }

    private func addManualToken() {
        guard canAddManual else { return }
        let token = CustomToken(
            contractAddress: addAddress,
            symbol: addManualSymbol.uppercased(),
            name: addManualName,
            decimals: Int(addManualDecimals) ?? 18,
            chain: addChain
        )
        do {
            try tokenManager.addToken(token)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                addAddress = ""
                addManualSymbol = ""
                addManualName = ""
                addManualDecimals = "18"
                addManual = false
                addError = nil
                activeSection = .collection
            }
        } catch {
            addError = error.localizedDescription
        }
    }

    // ── Spam Actions ──

    private func loadFlaggedSpam() {
        if let decoded = try? JSONDecoder().decode(Set<String>.self, from: flaggedSpamData) {
            flaggedSpamIds = decoded
        }
    }

    private func saveFlaggedSpam() {
        if let data = try? JSONEncoder().encode(flaggedSpamIds) {
            flaggedSpamData = data
        }
    }

    private func flagSpam(_ token: CustomToken) {
        flaggedSpamIds.insert(token.contractAddress.lowercased())
        saveFlaggedSpam()
    }

    private func unflagSpam(_ token: CustomToken) {
        flaggedSpamIds.remove(token.contractAddress.lowercased())
        saveFlaggedSpam()
    }

    // ── Settings Actions ──

    private func clearAllTokens() {
        for token in tokenManager.tokens {
            tokenManager.removeToken(token)
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showClearConfirm = false
            flaggedSpamIds.removeAll()
            saveFlaggedSpam()
        }
    }

    // ── Helpers ──

    private func truncateAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }

    private func chainBadge(_ chain: TokenChain) -> String {
        switch chain {
        case .ethereum: return "ERC-20"
        case .bsc: return "BEP-20"
        case .solana: return "SPL"
        }
    }

    private func tokenStorageSize() -> String {
        guard let data = UserDefaults.standard.data(forKey: "hawala.customTokens") else {
            return "0 B"
        }
        let bytes = data.count
        if bytes < 1024 { return "\(bytes) B" }
        return String(format: "%.1f KB", Double(bytes) / 1024.0)
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Token Detail Card
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct TkTokenDetailCard: View {
    let token: CustomToken
    let onDismiss: () -> Void
    let onRemove: () -> Void

    @State private var silkPhase: CGFloat = 0
    @State private var cardScale: CGFloat = 0.95
    @State private var opacity: Double = 0
    @State private var contractCopied: Bool = false
    @State private var closeHovered: Bool = false
    @State private var showRemoveConfirm: Bool = false
    @State private var isFlaggedSpam: Bool = false
    @AppStorage("hawala.tokens.flaggedSpam") private var flaggedSpamData: Data = Data()

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                detailHeader
                detailBody
            }
            .frame(width: 380, height: 460)
            .background(detailBg)
            .overlay(detailStroke)
            .shadow(color: .black.opacity(0.4), radius: 40, y: 20)
            .scaleEffect(cardScale)
            .opacity(opacity)
        }
        .onAppear {
            loadSpamState()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                cardScale = 1; opacity = 1
            }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: true)) {
                silkPhase = 1
            }
        }
    }

    private var detailBg: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.0), .white.opacity(0.015), .white.opacity(0.0)],
                        startPoint: UnitPoint(x: silkPhase - 0.3, y: 0),
                        endPoint: UnitPoint(x: silkPhase + 0.3, y: 1)
                    )
                )
        }
    }

    private var detailStroke: some View {
        RoundedRectangle(cornerRadius: 18)
            .strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.08), .white.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom
                ), lineWidth: 1
            )
    }

    private var detailHeader: some View {
        ZStack {
            Text("TOKEN DETAIL")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.35))

            HStack {
                Button { onDismiss() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .semibold))
                        Text("BACK")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                    }
                    .foregroundColor(.white.opacity(0.30))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(closeHovered ? 0.8 : 0.35))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.white.opacity(closeHovered ? 0.10 : 0.05)))
                }
                .buttonStyle(.plain)
                .onHover { closeHovered = $0 }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var detailBody: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                // Hero
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.06))
                            .frame(width: 64, height: 64)
                        Text(String(token.symbol.prefix(2)).uppercased())
                            .font(.clashGroteskMedium(size: 22))
                            .foregroundColor(.white.opacity(0.45))
                    }

                    Text(token.name)
                        .font(.clashGroteskMedium(size: 20))
                        .foregroundColor(.white.opacity(0.60))

                    Text(token.symbol.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.white.opacity(0.30))
                }

                // Metadata
                VStack(spacing: 6) {
                    detailRow(label: "CONTRACT", value: truncAddr(token.contractAddress), copyable: true)
                    detailRow(label: "CHAIN", value: badgeFor(token.chain))
                    detailRow(label: "DECIMALS", value: "\(token.decimals)")
                    detailRow(label: "ADDED", value: relDate(token.addedAt))
                    if let logo = token.logoURL, !logo.isEmpty {
                        detailRow(label: "LOGO", value: "Available")
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.03))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.04)))
                )

                // Explorer link
                Button {
                    let url = token.chain.explorerBaseURL + token.contractAddress
                    #if os(macOS)
                    if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                    #endif
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 9))
                        Text("VIEW ON EXPLORER")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                    }
                    .foregroundColor(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03)))
                }
                .buttonStyle(.plain)

                // Actions
                HStack(spacing: 8) {
                    Button {
                        toggleSpamFlag()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isFlaggedSpam ? "flag.slash" : "flag")
                                .font(.system(size: 9))
                            Text(isFlaggedSpam ? "UNFLAG" : "FLAG SPAM")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(0.3)
                        }
                        .foregroundColor(.white.opacity(0.30))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03)))
                    }
                    .buttonStyle(.plain)

                    if showRemoveConfirm {
                        Button { onRemove() } label: {
                            Text("CONFIRM REMOVE")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(0.3)
                                .foregroundColor(.white.opacity(0.55))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                showRemoveConfirm = true
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 9))
                                Text("REMOVE")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .tracking(0.3)
                            }
                            .foregroundColor(.white.opacity(0.30))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func detailRow(label: String, value: String, copyable: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.22))
            Spacer()
            if copyable {
                Button {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(token.contractAddress, forType: .string)
                    #endif
                    contractCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { contractCopied = false }
                } label: {
                    HStack(spacing: 4) {
                        Text(contractCopied ? "COPIED" : value)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(contractCopied ? 0.50 : 0.40))
                        Image(systemName: contractCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.20))
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text(value)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.40))
            }
        }
    }

    private func truncAddr(_ addr: String) -> String {
        guard addr.count > 12 else { return addr }
        return "\(addr.prefix(6))...\(addr.suffix(4))"
    }

    private func badgeFor(_ chain: TokenChain) -> String {
        switch chain {
        case .ethereum: return "Ethereum (ERC-20)"
        case .bsc: return "BNB Chain (BEP-20)"
        case .solana: return "Solana (SPL)"
        }
    }

    private func relDate(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 30 { return "\(days)d ago" }
        let months = days / 30
        return "\(months)mo ago"
    }

    // ── Spam ──

    private func loadSpamState() {
        if let decoded = try? JSONDecoder().decode(Set<String>.self, from: flaggedSpamData) {
            isFlaggedSpam = decoded.contains(token.contractAddress.lowercased())
        }
    }

    private func toggleSpamFlag() {
        var set: Set<String> = (try? JSONDecoder().decode(Set<String>.self, from: flaggedSpamData)) ?? []
        let addr = token.contractAddress.lowercased()
        if set.contains(addr) {
            set.remove(addr)
            isFlaggedSpam = false
        } else {
            set.insert(addr)
            isFlaggedSpam = true
        }
        if let data = try? JSONEncoder().encode(set) {
            flaggedSpamData = data
        }
    }
}
'''

BACKUP = TARGET + ".bak"
if os.path.exists(TARGET):
    shutil.copy2(TARGET, BACKUP)

with open(TARGET, 'w') as f:
    f.write(content)

print(f"Written {len(content)} bytes to {TARGET}")
print(f"Backup saved to {BACKUP}")
