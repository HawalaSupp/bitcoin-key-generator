import SwiftUI
import AppKit

// MARK: - Help & Support Overlay

struct HelpSupportOverlay: View {
    @Binding var isPresented: Bool
    var onBackToSettings: (() -> Void)? = nil

    // ── Tab enum ──
    enum HelpTab: String, CaseIterable {
        case support = "SUPPORT"
        case faq = "FAQ"
        case terms = "TERMS"
        case privacy = "PRIVACY"
    }

    // ── UI state ──
    @State private var activeTab: HelpTab = .support
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var silkPhase: CGFloat = 0
    @State private var closeHovered = false
    @State private var expandedFAQ: Int? = nil
    @State private var copiedDebugInfo = false

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

            Text("Help & Support")
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
            ForEach(HelpTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        activeTab = tab
                    }
                }) {
                    Text(tab.rawValue)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(activeTab == tab ? .white.opacity(0.9) : .white.opacity(0.35))
                        .padding(.horizontal, 14)
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
        case .support:
            supportTabContent
                .transition(.opacity.combined(with: .move(edge: .top)))
        case .faq:
            faqTabContent
                .transition(.opacity.combined(with: .move(edge: .top)))
        case .terms:
            termsTabContent
                .transition(.opacity.combined(with: .move(edge: .top)))
        case .privacy:
            privacyTabContent
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - SUPPORT TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var supportTabContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                getHelpSection
                shortcutsSection
                systemStatusSection
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
    }

    // ── Get Help ──

    private var getHelpSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("GET HELP")

            HStack(spacing: 10) {
                supportCard(icon: "book.fill", title: "Documentation") {
                    if let url = URL(string: "https://github.com/AeroNyx/Hawala") {
                        NSWorkspace.shared.open(url)
                    }
                }
                supportCard(icon: "envelope.fill", title: "Contact Us") {
                    if let url = URL(string: "mailto:support@hawala.app") {
                        NSWorkspace.shared.open(url)
                    }
                }
                supportCard(icon: "bubble.left.fill", title: "Community") {
                    if let url = URL(string: "https://github.com/AeroNyx/Hawala/discussions") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    private func supportCard(icon: String, title: String, action: @escaping () -> Void) -> some View {
        SupportCardButton(icon: icon, title: title, action: action)
    }

    // ── Keyboard Shortcuts ──

    private var shortcutsSection: some View {
        let shortcuts: [(String, String)] = [
            ("⌘ R", "Refresh"),
            ("⌘ L", "Lock Wallet"),
            ("⌘ ,", "Settings"),
            ("⌘ S", "Send"),
            ("⌘ E", "Export"),
            ("Esc", "Close Overlay"),
        ]

        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel("KEYBOARD SHORTCUTS")

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ], spacing: 8) {
                ForEach(shortcuts, id: \.0) { key, label in
                    HStack(spacing: 10) {
                        Text(key)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                            )

                        Text(label)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // ── System Status ──

    private var systemStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("SYSTEM STATUS")

            VStack(spacing: 8) {
                infoRow("Version", AppVersion.versionWithBuild)
                infoRow("Platform", "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                infoRow("Architecture", architectureString)
            }

            Button(action: copyDebugInfo) {
                HStack(spacing: 6) {
                    Image(systemName: copiedDebugInfo ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                    Text(copiedDebugInfo ? "Copied" : "Copy Debug Info")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.white.opacity(copiedDebugInfo ? 0.6 : 0.45))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - FAQ TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private let faqs: [(String, String)] = [
        ("How do I backup my wallet?", "Go to Settings → General → Backup Wallet. Write down your 24-word recovery phrase and store it in a safe place. Never share it with anyone or store it digitally."),
        ("What if I lose my recovery phrase?", "Without your recovery phrase, there is no way to recover your wallet. This is why it's crucial to backup your phrase immediately after creating a wallet."),
        ("Are my funds safe?", "Hawala is a self-custody wallet, meaning only you control your private keys. Your keys are encrypted and stored locally on your device. We never have access to your funds."),
        ("How do I send cryptocurrency?", "Click the send button (↑↓) in the navigation bar, select the asset you want to send, enter the recipient address and amount, then confirm the transaction."),
        ("Why is my balance not updating?", "Try refreshing by pressing Cmd+R or clicking the refresh button. Check your internet connection and ensure the blockchain network is operational."),
        ("How do I change networks?", "Go to Settings → General → Network Settings. You can switch between Mainnet, Testnet, or configure a custom RPC endpoint."),
        ("Is Hawala open source?", "Yes! Hawala is open source software. You can review the code and contribute on GitHub."),
    ]

    private var faqTabContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("FREQUENTLY ASKED QUESTIONS")

                    VStack(spacing: 6) {
                        ForEach(Array(faqs.enumerated()), id: \.offset) { index, faq in
                            faqItem(index: index, question: faq.0, answer: faq.1)
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
    }

    private func faqItem(index: Int, question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    expandedFAQ = expandedFAQ == index ? nil : index
                }
            }) {
                HStack {
                    Text(question)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Image(systemName: expandedFAQ == index ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.3))
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            if expandedFAQ == index {
                Text(answer)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                    .lineSpacing(4)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - TERMS TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var termsTabContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    sectionLabel("TERMS OF SERVICE")
                    Spacer()
                    Text("Last Updated: November 30, 2025")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.2))
                }

                termsBlock("1. Acceptance of Terms", "By accessing and using Hawala Wallet, you agree to be bound by these Terms of Service. If you do not agree to these terms, please do not use the application.")

                termsBlock("2. Self-Custody Wallet", "Hawala is a self-custody wallet. You are solely responsible for maintaining the security of your private keys and recovery phrase. We do not have access to your funds or the ability to recover lost keys.")

                termsBlock("3. No Financial Advice", "Hawala does not provide financial, investment, legal, or tax advice. All cryptocurrency transactions carry risk. You should consult with qualified professionals before making any financial decisions.")

                termsBlock("4. User Responsibilities", """
                    You agree to:
                    • Keep your recovery phrase secure and private
                    • Not share your private keys with anyone
                    • Use the wallet only for lawful purposes
                    • Accept full responsibility for all transactions made from your wallet
                    """)

                termsBlock("5. Limitation of Liability", "Hawala is provided \"as is\" without warranties of any kind. We are not liable for any losses, damages, or claims arising from the use of this software, including but not limited to loss of funds, hacking, or software errors.")

                termsBlock("6. Privacy", "We do not collect, store, or transmit your private keys or recovery phrase. Price data and blockchain information may be fetched from third-party services. See our Privacy Policy for more details.")

                termsBlock("7. Changes to Terms", "We reserve the right to modify these terms at any time. Continued use of the application after changes constitutes acceptance of the new terms.")

                termsBlock("8. Contact", "For questions about these terms, please reach out through our Help & Support section.")
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
    }

    private func termsBlock(_ title: String, _ content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.65))
            Text(content)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
                .lineSpacing(4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - PRIVACY TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var privacyTabContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                privacyHighlights

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        sectionLabel("PRIVACY POLICY")
                        Spacer()
                        Text("Last Updated: November 30, 2025")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.2))
                    }

                    termsBlock("Our Commitment", "Hawala is designed with privacy as a core principle. We believe your financial data belongs to you and you alone.")

                    termsBlock("What We DON'T Collect", """
                        • Private keys or recovery phrases
                        • Transaction history
                        • Wallet balances
                        • Personal identification information
                        • Location data
                        • Usage analytics
                        """)

                    termsBlock("Local Storage Only", "All sensitive data, including your encrypted keys and wallet settings, is stored locally on your device. We never transmit this information to external servers.")

                    termsBlock("Third-Party Services", """
                        To provide functionality, we connect to:
                        • Blockchain nodes for transaction broadcasting
                        • Price APIs for market data (CoinGecko)
                        • Block explorers for transaction verification
                        
                        These services may have their own privacy policies.
                        """)

                    termsBlock("Network Requests", "When fetching prices or broadcasting transactions, your IP address may be visible to third-party services. For enhanced privacy, consider using a VPN or Tor.")

                    termsBlock("Your Rights", "Since we don't collect your data, there's nothing to delete or export. Your data lives entirely on your device. Uninstalling the app removes all local data.")
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
    }

    private var privacyHighlights: some View {
        HStack(spacing: 10) {
            privacyPill(icon: "lock.shield.fill", label: "No Data Collection")
            privacyPill(icon: "eye.slash.fill", label: "No Tracking")
            privacyPill(icon: "key.fill", label: "Self-Custody")
        }
    }

    private func privacyPill(icon: String, label: String) -> some View {
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

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Helpers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1)
            .foregroundColor(.white.opacity(0.3))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
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

    private var architectureString: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Unknown"
        #endif
    }

    private func copyDebugInfo() {
        let info = """
        Hawala \(AppVersion.versionWithBuild)
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        \(architectureString)
        Bundle: \(Bundle.main.bundleIdentifier ?? "—")
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)
        copiedDebugInfo = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedDebugInfo = false
        }
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

// MARK: - Support Card Button

private struct SupportCardButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.04))
                    .clipShape(Circle())

                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isHovered ? Color.white.opacity(0.06) : Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
