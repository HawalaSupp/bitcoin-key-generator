import SwiftUI
import AppKit

// MARK: - About Hawala Overlay

struct AboutOverlay: View {
    @Binding var isPresented: Bool
    var onBackToSettings: (() -> Void)? = nil

    // ── Tab enum ──
    enum AboutTab: String, CaseIterable {
        case about = "ABOUT"
        case chains = "CHAINS"
        case credits = "CREDITS"
    }

    // ── UI state ──
    @State private var activeTab: AboutTab = .about
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var silkPhase: CGFloat = 0
    @State private var closeHovered = false
    @State private var logoGlow: CGFloat = 0

    var body: some View {
        ZStack {
            backdrop
            mainCard
        }
        .background(EscapeKeyHandler(isPresented: $isPresented, onEscape: dismissOverlay))
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardScale = 1
                contentOpacity = 1
            }
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                silkPhase = 1
            }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                logoGlow = 1
            }
        }
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        Color.black.opacity(0.75)
            .ignoresSafeArea()
            .onTapGesture { dismissOverlay() }
    }

    // MARK: - Main Card

    private var mainCard: some View {
        VStack(spacing: 0) {
            headerBar
            tabPicker
            tabContent
        }
        .frame(width: 700, height: 620)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(cardStroke)
        .shadow(color: .black.opacity(0.5), radius: 50, y: 25)
        .scaleEffect(cardScale)
        .opacity(contentOpacity)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Button(action: {
                dismissOverlay()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    onBackToSettings?()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Settings")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("About Hawala")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))

            Spacer()

            Button(action: dismissOverlay) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(closeHovered ? .white.opacity(0.9) : .white.opacity(0.4))
                    .frame(width: 28, height: 28)
                    .background(closeHovered ? Color.white.opacity(0.1) : Color.clear)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { closeHovered = $0 }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(AboutTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        activeTab = tab
                    }
                }) {
                    Text(tab.rawValue)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(activeTab == tab ? .white.opacity(0.9) : .white.opacity(0.35))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(
                            activeTab == tab
                            ? Color.white.opacity(0.08)
                            : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .about:
            aboutTabContent
                .transition(.opacity.combined(with: .move(edge: .top)))
        case .chains:
            chainsTabContent
                .transition(.opacity.combined(with: .move(edge: .top)))
        case .credits:
            creditsTabContent
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - ABOUT TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var aboutTabContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                heroSection
                philosophySection
                featuresGrid
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
    }

    // ── Hero ──

    private var heroSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 88, height: 88)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.06 + 0.03 * logoGlow), .clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 50
                        )
                    )
                    .frame(width: 88, height: 88)
                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
            }

            Text("Hawala")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))

            Text("v\(AppVersion.version) (\(AppVersion.build))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))

            Text("Self-custody multi-chain cryptocurrency wallet for macOS")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(.vertical, 8)
    }

    // ── Philosophy ──

    private var philosophySection: some View {
        HStack(spacing: 10) {
            philosophyPill(icon: "key.fill", label: "Self Custody")
            philosophyPill(icon: "eye.slash.fill", label: "Privacy First")
            philosophyPill(icon: "cube.transparent", label: "Open Architecture")
        }
    }

    private func philosophyPill(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.45))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    // ── Features Grid ──

    private var featuresGrid: some View {
        let features: [(String, String, String)] = [
            ("shield.lock.fill", "Self-Custody", "Your keys, your crypto"),
            ("link", "Multi-Chain", "12+ blockchains supported"),
            ("eye.slash.fill", "Privacy Focused", "No tracking, no analytics"),
            ("bolt.fill", "Native Performance", "Built for Apple Silicon"),
            ("lock.shield.fill", "Encrypted Backups", "AES-256 encrypted exports"),
            ("arrow.left.arrow.right", "WalletConnect", "Connect to any dApp"),
        ]

        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel("FEATURES")

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ], spacing: 10) {
                ForEach(features, id: \.1) { icon, title, subtitle in
                    featureCard(icon: icon, title: title, subtitle: subtitle)
                }
            }
        }
    }

    private func featureCard(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - CHAINS TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var chainsTabContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                chainsGrid
                comingSoonNote
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
    }

    private var chainsGrid: some View {
        let chains: [(String, String, String)] = [
            ("₿", "Bitcoin", "Layer 1"),
            ("Ξ", "Ethereum", "Smart Contracts"),
            ("◎", "Solana", "High Performance"),
            ("Ł", "Litecoin", "Payments"),
            ("ɱ", "Monero", "Privacy"),
            ("⬡", "BNB Chain", "DeFi"),
            ("▲", "Algorand", "Pure PoS"),
            ("⚛", "Cosmos", "Interchain"),
            ("●", "Polkadot", "Parachains"),
            ("◆", "Tron", "Layer 1"),
            ("◇", "Cardano", "Proof of Stake"),
            ("✕", "XRP", "Payments"),
        ]

        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel("SUPPORTED BLOCKCHAINS")

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ], spacing: 10) {
                ForEach(chains, id: \.1) { symbol, name, label in
                    chainCard(symbol: symbol, name: name, label: label)
                }
            }
        }
    }

    private func chainCard(symbol: String, name: String, label: String) -> some View {
        VStack(spacing: 8) {
            Text(symbol)
                .font(.system(size: 22))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.04))
                .clipShape(Circle())

            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)

            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.25))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var comingSoonNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle")
                .font(.system(size: 10))
            Text("More chains coming soon")
                .font(.system(size: 10))
        }
        .foregroundColor(.white.opacity(0.2))
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - CREDITS TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var creditsTabContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                versionHistorySection
                acknowledgementsSection
                legalSection
                buildInfoSection
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
    }

    // ── Version History ──

    private var versionHistorySection: some View {
        let versions: [(String, String)] = [
            ("2.2", "Contact address book, camera QR scanning, CSV export, transaction notes"),
            ("2.1", "Enhanced history: search/filter, confirmations, fee display, expandable details"),
            ("2.0", "Privacy blur: sensitive data hidden when app goes to background"),
            ("1.9", "Dynamic gas fee controls: EIP-1559 support with speed selector"),
            ("1.8", "Transaction history with live blockchain data and explorer links"),
            ("1.7", "Biometric security: TouchID/FaceID for sends and key reveals"),
            ("1.6", "CoinGecko rate limiting fix: 2-min polling, API key support"),
            ("1.5", "RBF/speed-up for stuck transactions, centralized version management"),
            ("1.4", "ENS/SNS resolution, clipboard auto-clear, pending tx tracking"),
            ("1.3", "Biometric unlock, fiat currency selector, sparkline charts"),
            ("1.2", "Send flows for Bitcoin, Ethereum, Litecoin, BNB, Solana"),
            ("1.1", "BIP-39 mnemonic support and encrypted backups"),
            ("1.0", "Initial release with multi-chain key generation"),
        ]

        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel("VERSION HISTORY")

            VStack(spacing: 0) {
                ForEach(Array(versions.enumerated()), id: \.offset) { index, entry in
                    HStack(alignment: .top, spacing: 10) {
                        Text("v\(entry.0)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 32, alignment: .trailing)

                        Rectangle()
                            .fill(Color.white.opacity(index == 0 ? 0.2 : 0.06))
                            .frame(width: 1)

                        Text(entry.1)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(index == 0 ? 0.6 : 0.35))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // ── Acknowledgements ──

    private var acknowledgementsSection: some View {
        let credits: [(String, String)] = [
            ("swift", "Built with Swift & SwiftUI"),
            ("cpu", "Cryptography by CryptoSwift"),
            ("paintbrush", "Icons by SF Symbols"),
            ("network", "WalletConnect Protocol v2"),
            ("cube", "SwiftPM Package Manager"),
        ]

        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel("ACKNOWLEDGMENTS")

            ForEach(credits, id: \.1) { icon, text in
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                        .frame(width: 20)
                    Text(text)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // ── Legal ──

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("LEGAL")

            VStack(alignment: .leading, spacing: 6) {
                Text("© 2024-2026 Hawala. All rights reserved.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))

                Text("Hawala is a non-custodial wallet. You maintain full control of your private keys at all times. We do not store, access, or transmit your keys or seed phrases.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
                    .lineLimit(3)

                Text("This software is provided as-is without warranty. Always verify transactions before signing.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
                    .lineLimit(2)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // ── Build Info ──

    private var buildInfoSection: some View {
        let buildPairs = buildInfoPairs
        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel("BUILD INFO")

            ForEach(buildPairs, id: \.0) { label, value in
                HStack {
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                    Text(value)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Computed Properties
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var buildInfoPairs: [(String, String)] {
        [
            ("Version", AppVersion.versionWithBuild),
            ("Bundle ID", Bundle.main.bundleIdentifier ?? "—"),
            ("Platform", "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"),
            ("Architecture", architectureString),
        ]
    }

    private var architectureString: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Unknown"
        #endif
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Helpers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1)
            .foregroundColor(.white.opacity(0.3))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Card Chrome
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.06, green: 0.06, blue: 0.07))
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(
                    colors: [.clear, .white.opacity(0.015), .clear],
                    startPoint: UnitPoint(x: silkPhase - 0.3, y: 0),
                    endPoint: UnitPoint(x: silkPhase + 0.3, y: 1)
                ))
        }
    }

    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.10), .white.opacity(0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private func dismissOverlay() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            cardScale = 0.95
            contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }
}
