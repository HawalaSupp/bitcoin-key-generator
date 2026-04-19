#!/usr/bin/env python3
"""Restyle CustomTokenManager.swift UI views (lines 656+) to monochrome."""

import os

TARGET = os.path.expanduser("~/Desktop/888/swift-app/Sources/swift-app/Services/CustomTokenManager.swift")

with open(TARGET, 'r') as f:
    lines = f.readlines()

# Keep backend code (lines 1-655, index 0-654) 
backend = lines[:655]

# New UI views (monochrome restyled)
ui_code = r'''
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Add Custom Token Sheet (monochrome)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct AddCustomTokenSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tokenManager = CustomTokenManager.shared

    @State private var contractAddress = ""
    @State private var symbol = ""
    @State private var name = ""
    @State private var decimals = "18"
    @State private var selectedChain: TokenChain = .ethereum
    @State private var isLoading = false
    @State private var error: String?
    @State private var fetchedToken: CustomToken?
    @State private var manualEntry = false
    @State private var closeHovered = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(.white.opacity(0.06))

            ScrollView {
                VStack(spacing: 16) {
                    chainSelector
                    addressInput

                    if let token = fetchedToken {
                        tokenPreview(token)
                    } else if manualEntry {
                        manualEntryFields
                    }

                    if let error = error {
                        errorView(error)
                    }
                }
                .padding(20)
            }

            Divider().background(.white.opacity(0.06))
            footer
        }
        .frame(width: 450, height: 550)
        .background(Color(red: 0.10, green: 0.10, blue: 0.12))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("ADD CUSTOM TOKEN")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.55))

                Text("Import ERC-20, BEP-20, or SPL token")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
            }

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(closeHovered ? 0.8 : 0.35))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.white.opacity(closeHovered ? 0.10 : 0.05)))
            }
            .buttonStyle(.plain)
            .onHover { closeHovered = $0 }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var chainSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NETWORK")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.30))

            HStack(spacing: 6) {
                ForEach(TokenChain.allCases) { chain in
                    let sel = selectedChain == chain
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            selectedChain = chain
                            fetchedToken = nil
                            error = nil
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: chain.icon)
                                .font(.system(size: 10))
                            Text(chain == .ethereum ? "ETH" : chain == .bsc ? "BSC" : "SOL")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(0.5)
                        }
                        .foregroundColor(.white.opacity(sel ? 0.65 : 0.25))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.white.opacity(sel ? 0.08 : 0.02))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(sel ? 0.12 : 0.04)))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var addressInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CONTRACT ADDRESS")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.30))

            HStack(spacing: 8) {
                TextField(selectedChain.addressPlaceholder, text: $contractAddress)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.06)))
                    )
                    .onChange(of: contractAddress) { _ in
                        fetchedToken = nil
                        error = nil
                    }

                Button {
                    Task { await fetchTokenInfo() }
                } label: {
                    if isLoading {
                        ProgressView().scaleEffect(0.6).tint(.white.opacity(0.3))
                            .frame(width: 70, height: 32)
                    } else {
                        Text("FETCH")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundColor(.white.opacity(canFetch ? 0.55 : 0.18))
                            .frame(width: 70, height: 32)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(canFetch ? 0.06 : 0.02)))
                    }
                }
                .buttonStyle(.plain)
                .disabled(contractAddress.isEmpty || isLoading || !tokenManager.validateContractAddress(contractAddress, chain: selectedChain))
            }

            if !tokenManager.validateContractAddress(contractAddress, chain: selectedChain) && !contractAddress.isEmpty {
                Text("Invalid \(selectedChain.displayName) address format")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.30))
            }
        }
    }

    private var canFetch: Bool {
        !contractAddress.isEmpty && tokenManager.validateContractAddress(contractAddress, chain: selectedChain) && !isLoading
    }

    private func tokenPreview(_ token: CustomToken) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("TOKEN FOUND")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.40))
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.35))
            }

            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(.white.opacity(0.06)).frame(width: 40, height: 40)
                    Text(String(token.symbol.prefix(2)).uppercased())
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.40))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(token.name)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                    Text("\(token.symbol) \u{2022} \(token.decimals) decimals")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.30))
                }
                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.06)))
        )
    }

    private var manualEntryFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MANUAL ENTRY")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.30))

            ctmField(label: "SYMBOL", placeholder: "e.g. USDT", text: $symbol)
            ctmField(label: "NAME", placeholder: "e.g. Tether USD", text: $name)
            ctmField(label: "DECIMALS", placeholder: "18", text: $decimals)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.02))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.04)))
        )
    }

    private func ctmField(label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.3)
                .foregroundColor(.white.opacity(0.25))
                .frame(width: 65, alignment: .trailing)

            TextField(placeholder, text: text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))
                .textFieldStyle(.plain)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.06)))
                )
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                Text(message)
                    .font(.system(size: 9, design: .monospaced))
                Spacer()
            }
            .foregroundColor(.white.opacity(0.35))

            Button("Enter details manually") {
                manualEntry = true
                error = nil
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.white.opacity(0.40))
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.03))
        )
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.30))
                .buttonStyle(.plain)

            Spacer()

            Button { addToken() } label: {
                Text("ADD TOKEN")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(canAddToken ? 0.55 : 0.18))
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(canAddToken ? 0.06 : 0.02))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canAddToken)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var canAddToken: Bool {
        if fetchedToken != nil { return true }
        if manualEntry && !symbol.isEmpty && !name.isEmpty && !contractAddress.isEmpty { return true }
        return false
    }

    private func fetchTokenInfo() async {
        isLoading = true
        error = nil

        do {
            let token = try await tokenManager.fetchTokenInfo(contractAddress: contractAddress, chain: selectedChain)
            fetchedToken = token
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func addToken() {
        let token: CustomToken

        if let fetched = fetchedToken {
            token = fetched
        } else {
            token = CustomToken(
                contractAddress: contractAddress,
                symbol: symbol.uppercased(),
                name: name,
                decimals: Int(decimals) ?? 18,
                chain: selectedChain
            )
        }

        do {
            try tokenManager.addToken(token)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Custom Tokens List View (monochrome)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct CustomTokensListView: View {
    @ObservedObject private var tokenManager = CustomTokenManager.shared
    @State private var showAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CUSTOM TOKENS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(0.50))
                    Text("\(tokenManager.tokens.count) tokens added")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                }

                Spacer()

                Button { showAddSheet = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 9))
                        Text("ADD")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.3)
                    }
                    .foregroundColor(.white.opacity(0.40))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.05))
                    )
                }
                .buttonStyle(.plain)
            }

            if tokenManager.tokens.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "circle.hexagongrid")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.10))
                    Text("No custom tokens")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.20))
                    Text("Add tokens by their contract address")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.15))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 2) {
                    ForEach(tokenManager.tokens) { token in
                        CustomTokenRow(token: token)
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddCustomTokenSheet()
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Custom Token Row (monochrome)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct CustomTokenRow: View {
    let token: CustomToken
    @ObservedObject private var tokenManager = CustomTokenManager.shared
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(.white.opacity(0.06)).frame(width: 32, height: 32)
                Text(String(token.symbol.prefix(2)).uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(token.symbol.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.50))
                Text(token.name)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
            }

            Spacer()

            Text(token.chain == .ethereum ? "ERC-20" : token.chain == .bsc ? "BEP-20" : "SPL")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.3)
                .foregroundColor(.white.opacity(0.20))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.04)))

            if isHovered {
                Button {
                    tokenManager.removeToken(token)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(isHovered ? .white.opacity(0.04) : .white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHovered = $0 }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Custom Tokens Sheet — Settings Integration (monochrome)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct CustomTokensSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tokenManager = CustomTokenManager.shared
    @State private var showAddSheet = false
    @State private var showAutoDetectSheet = false
    @State private var closeHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CUSTOM TOKENS")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.white.opacity(0.55))
                    Text("\(tokenManager.tokens.count) tokens added")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                }

                Spacer()

                Button { showAutoDetectSheet = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 9))
                        Text("DETECT")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.3)
                    }
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.04)))
                }
                .buttonStyle(.plain)

                Button { showAddSheet = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 9))
                        Text("ADD")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.3)
                    }
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.06)))
                }
                .buttonStyle(.plain)

                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(closeHovered ? 0.8 : 0.35))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.white.opacity(closeHovered ? 0.10 : 0.05)))
                }
                .buttonStyle(.plain)
                .onHover { closeHovered = $0 }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider().background(.white.opacity(0.06))

            // Content
            if tokenManager.tokens.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "circle.hexagongrid")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.10))
                    Text("NO CUSTOM TOKENS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(0.25))
                    Text("Add ERC-20, BEP-20, or SPL tokens\nby their contract address")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.18))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)

                    Button { showAddSheet = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 10))
                            Text("ADD YOUR FIRST TOKEN")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(0.5)
                        }
                        .foregroundColor(.white.opacity(0.40))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.08)))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(tokenManager.tokens) { token in
                            CustomTokenRow(token: token)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 500, height: 450)
        .background(Color(red: 0.10, green: 0.10, blue: 0.12))
        .sheet(isPresented: $showAddSheet) {
            AddCustomTokenSheet()
        }
        .sheet(isPresented: $showAutoDetectSheet) {
            AutoDetectTokensSheet()
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Auto-Detect Tokens Sheet (monochrome)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct AutoDetectTokensSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tokenManager = CustomTokenManager.shared

    @State private var isScanning = false
    @State private var detectedTokens: [CustomToken] = []
    @State private var selectedTokens: Set<UUID> = []
    @State private var error: String?
    @State private var scanComplete = false
    @State private var closeHovered = false

    // Pull addresses from active wallet
    @State private var ethAddress: String = WalletManager.shared.activeHDWallet?.accounts.first(where: { $0.chainId == .ethereum })?.address ?? ""
    @State private var solAddress: String = WalletManager.shared.activeHDWallet?.accounts.first(where: { $0.chainId == .solana })?.address ?? ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AUTO-DETECT TOKENS")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.white.opacity(0.55))
                    Text("Scan wallets for tokens")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(closeHovered ? 0.8 : 0.35))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.white.opacity(closeHovered ? 0.10 : 0.05)))
                }
                .buttonStyle(.plain)
                .onHover { closeHovered = $0 }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider().background(.white.opacity(0.06))

            // Content
            if isScanning {
                scanningView
            } else if scanComplete && detectedTokens.isEmpty {
                noTokensFoundView
            } else if !detectedTokens.isEmpty {
                detectedTokensView
            } else {
                startScanView
            }

            Divider().background(.white.opacity(0.06))

            // Footer
            HStack {
                Button("Cancel") { dismiss() }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.30))
                    .buttonStyle(.plain)

                Spacer()

                if !detectedTokens.isEmpty {
                    Button { addSelectedTokens() } label: {
                        Text("ADD \(selectedTokens.count) TOKENS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundColor(.white.opacity(selectedTokens.isEmpty ? 0.18 : 0.55))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.white.opacity(selectedTokens.isEmpty ? 0.02 : 0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedTokens.isEmpty)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 500, height: 500)
        .background(Color(red: 0.10, green: 0.10, blue: 0.12))
    }

    private var startScanView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.12))

            VStack(spacing: 6) {
                Text("SCAN FOR TOKENS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.40))
                Text("Detect ERC-20 and SPL tokens\nwith non-zero balances")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.22))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            // Address inputs
            VStack(spacing: 8) {
                addrRow(icon: "diamond", label: "ETH", text: $ethAddress, placeholder: "Ethereum address (0x...)")
                addrRow(icon: "sparkles", label: "SOL", text: $solAddress, placeholder: "Solana address")
            }
            .padding(.horizontal, 30)

            Button {
                Task { await startScan() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 9))
                    Text("START SCAN")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                }
                .foregroundColor(.white.opacity(ethAddress.isEmpty && solAddress.isEmpty ? 0.18 : 0.50))
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(ethAddress.isEmpty && solAddress.isEmpty ? 0.02 : 0.06))
                )
            }
            .buttonStyle(.plain)
            .disabled(ethAddress.isEmpty && solAddress.isEmpty)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func addrRow(icon: String, label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.18))
                .frame(width: 20)

            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.3)
                .foregroundColor(.white.opacity(0.25))
                .frame(width: 28)

            TextField(placeholder, text: text)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.50))
                .textFieldStyle(.plain)
                .padding(.horizontal, 8).padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.06)))
                )
        }
    }

    private var scanningView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().scaleEffect(0.8).tint(.white.opacity(0.25))
            VStack(spacing: 4) {
                Text("SCANNING WALLETS...")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.35))
                Text("Looking for tokens with non-zero balances")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.22))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var noTokensFoundView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.15))
            VStack(spacing: 4) {
                Text("SCAN COMPLETE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.40))
                Text("No new tokens found.\nAll detected tokens are already added.")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.22))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            Button { dismiss() } label: {
                Text("DONE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var detectedTokensView: some View {
        VStack(spacing: 10) {
            HStack {
                Text("FOUND \(detectedTokens.count) TOKENS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.40))

                Spacer()

                Button {
                    if selectedTokens.count == detectedTokens.count {
                        selectedTokens.removeAll()
                    } else {
                        selectedTokens = Set(detectedTokens.map { $0.id })
                    }
                } label: {
                    Text(selectedTokens.count == detectedTokens.count ? "DESELECT ALL" : "SELECT ALL")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.3)
                        .foregroundColor(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 10)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(detectedTokens) { token in
                        DetectedTokenRow(
                            token: token,
                            isSelected: selectedTokens.contains(token.id),
                            onToggle: {
                                if selectedTokens.contains(token.id) {
                                    selectedTokens.remove(token.id)
                                } else {
                                    selectedTokens.insert(token.id)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func startScan() async {
        isScanning = true
        error = nil
        detectedTokens = []

        do {
            var allTokens: [CustomToken] = []

            if !ethAddress.isEmpty {
                let ethTokens = try await tokenManager.detectERC20Tokens(walletAddress: ethAddress)
                allTokens.append(contentsOf: ethTokens)
            }

            if !solAddress.isEmpty {
                let solTokens = try await tokenManager.detectSPLTokens(walletAddress: solAddress)
                allTokens.append(contentsOf: solTokens)
            }

            detectedTokens = allTokens
            selectedTokens = Set(allTokens.map { $0.id })
            scanComplete = true
        } catch {
            self.error = error.localizedDescription
        }

        isScanning = false
    }

    private func addSelectedTokens() {
        let tokensToAdd = detectedTokens.filter { selectedTokens.contains($0.id) }
        tokenManager.addDetectedTokens(tokensToAdd)
        dismiss()
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Detected Token Row (monochrome)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct DetectedTokenRow: View {
    let token: CustomToken
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button { onToggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(isSelected ? 0.50 : 0.15))

                ZStack {
                    Circle().fill(.white.opacity(0.06)).frame(width: 30, height: 30)
                    Text(String(token.symbol.prefix(2)).uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(token.symbol.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.50))
                    Text(token.name)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                }

                Spacer()

                Text(token.chain == .ethereum ? "ERC-20" : token.chain == .bsc ? "BEP-20" : "SPL")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.3)
                    .foregroundColor(.white.opacity(0.20))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.04)))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(isSelected ? .white.opacity(0.04) : .white.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white.opacity(isSelected ? 0.08 : 0.0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
struct CustomTokenManager_Previews: PreviewProvider {
    static var previews: some View {
        AddCustomTokenSheet()
            .preferredColorScheme(.dark)
    }
}
#endif
'''

with open(TARGET, 'w') as f:
    for line in backend:
        f.write(line)
    f.write(ui_code)

print(f"Written {os.path.getsize(TARGET)} bytes to {TARGET}")
