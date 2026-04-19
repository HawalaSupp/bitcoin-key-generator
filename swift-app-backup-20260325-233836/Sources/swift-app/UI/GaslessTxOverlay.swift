import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Gasless Transactions Overlay
// Paymaster-sponsored transactions — zero-friction crypto UX.
// Flip-toggle sponsor badges, checklist rule verification,
// glowing sponsored history, depleting balance bar.
// Monumental. Monochrome. Silk.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct GaslessTxOverlay: View {
    @Binding var isPresented: Bool

    // ── Paymaster state ──
    @State private var paymasters: [PaymasterEntry] = []
    @State private var sponsoredHistory: [SponsoredTxEntry] = []
    @State private var paymasterBalanceUSD: Double = 48.50
    @State private var paymasterBalanceMax: Double = 100.0

    // ── Animation ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var balanceDepleted: CGFloat = 0
    @State private var silkPhase: CGFloat = 0
    @State private var entranceStagger: Bool = false

    // ── Hover ──
    @State private var closeHovered: Bool = false
    @State private var addPaymasterHovered: Bool = false

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Body
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    var body: some View {
        ZStack {
            backdrop
            mainCard
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

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Backdrop
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var backdrop: some View {
        Color.black.opacity(0.75)
            .ignoresSafeArea()
            .onTapGesture { dismissOverlay() }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Main Card
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var mainCard: some View {
        VStack(spacing: 0) {
            headerBar
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    heroSection
                    paymasterListSection
                    sponsorshipRulesSection
                    balanceBarSection
                    historySection
                }
                .padding(.horizontal, 28)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
        }
        .frame(width: 450, height: 670)
        .background(cardBackground)
        .overlay(cardStroke)
        .shadow(color: .black.opacity(0.5), radius: 50, y: 25)
        .scaleEffect(cardScale)
        .opacity(contentOpacity)
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))

            // Silk shimmer — subtle diagonal sweep
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.0),
                            .white.opacity(0.02),
                            .white.opacity(0.0)
                        ],
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
    // MARK: – Header Bar
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var headerBar: some View {
        ZStack {
            Text("GASLESS")
                .font(.clashGroteskMedium(size: 14))
                .tracking(3)
                .foregroundColor(.white.opacity(0.5))

            HStack {
                Spacer()
                closeButton
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var closeButton: some View {
        Button(action: dismissOverlay) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(closeHovered ? 0.9 : 0.4))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(.white.opacity(closeHovered ? 0.12 : 0.06))
                )
        }
        .buttonStyle(.plain)
        .onHover { closeHovered = $0 }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Hero Section
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var heroSection: some View {
        VStack(spacing: 6) {
            Text("$0.00")
                .font(.clashGroteskBold(size: 42))
                .foregroundColor(.white.opacity(0.9))

            Text("GAS FEES")
                .font(.clashGroteskMedium(size: 13))
                .tracking(4)
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.top, 4)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Paymaster List
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var paymasterListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "PAYMASTERS", icon: "checkmark.seal")

            ForEach(Array(paymasters.enumerated()), id: \.element.id) { index, _ in
                paymasterBadge(index: index)
            }

            addPaymasterButton
        }
    }

    private func paymasterBadge(index: Int) -> some View {
        let pm = paymasters[index]
        return HStack(spacing: 12) {
            // Badge icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(pm.isEnabled ? 0.08 : 0.03))
                    .frame(width: 38, height: 38)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(pm.isEnabled ? 0.7 : 0.2))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(pm.name)
                    .font(.clashGroteskMedium(size: 14))
                    .foregroundColor(.white.opacity(pm.isEnabled ? 0.85 : 0.35))
                Text(pm.description)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(pm.isEnabled ? 0.35 : 0.2))
            }

            Spacer()

            // Flip-toggle badge
            flipToggle(isOn: pm.isEnabled) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    paymasters[index].isEnabled.toggle()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(pm.isEnabled ? 0.04 : 0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(pm.isEnabled ? 0.08 : 0.03), lineWidth: 1)
                )
        )
        .opacity(entranceStagger ? 1 : 0)
        .offset(y: entranceStagger ? 0 : 8)
        .animation(
            .spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.08),
            value: entranceStagger
        )
    }

    private func flipToggle(isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(isOn ? 0.12 : 0.04))
                    .frame(width: 44, height: 26)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.white.opacity(isOn ? 0.2 : 0.08), lineWidth: 1)
                    )

                Text(isOn ? "ON" : "OFF")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(isOn ? 0.8 : 0.3))
                    .rotation3DEffect(
                        .degrees(isOn ? 0 : 180),
                        axis: (x: 1, y: 0, z: 0)
                    )
            }
            .rotation3DEffect(
                .degrees(isOn ? 0 : 180),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.5
            )
        }
        .buttonStyle(.plain)
    }

    private var addPaymasterButton: some View {
        Button(action: {}) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 13))
                Text("Add Paymaster")
                    .font(.clashGroteskMedium(size: 12))
            }
            .foregroundColor(.white.opacity(addPaymasterHovered ? 0.7 : 0.4))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        .white.opacity(addPaymasterHovered ? 0.15 : 0.08),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { addPaymasterHovered = $0 }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Sponsorship Rules (Checklist)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var sponsorshipRulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "SPONSORSHIP RULES", icon: "list.bullet.rectangle")

            ruleCheckItem(
                label: "Hold ≥ 100 USDC",
                met: true
            )
            ruleCheckItem(
                label: "Transaction ≤ $500",
                met: true
            )
            ruleCheckItem(
                label: "Daily limit not reached",
                met: true
            )
            ruleCheckItem(
                label: "Supported chain (L2 only)",
                met: false
            )
        }
    }

    private func ruleCheckItem(label: String, met: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(.white.opacity(met ? 0.25 : 0.10), lineWidth: 1.5)
                    .frame(width: 18, height: 18)

                if met {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(met ? 0.7 : 0.30))
                .strikethrough(!met, color: .white.opacity(0.15))

            Spacer()

            if met {
                Text("MET")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(.white.opacity(0.06))
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(met ? 0.03 : 0.015))
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Paymaster Balance Bar
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var balanceBarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "SPONSOR BALANCE", icon: "battery.75percent")

            balanceBarTrack

            balanceBarLabels
        }
    }

    private var balanceBarTrack: some View {
        GeometryReader { geo in
            let fraction = CGFloat(paymasterBalanceUSD / paymasterBalanceMax) * balanceDepleted

            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.06))

                // Fill — depletes right-to-left
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.20),
                                .white.opacity(fraction < 0.25 ? 0.08 : 0.12)
                            ],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * fraction)

                // Edge glow on the fill end
                if fraction > 0.02 {
                    Circle()
                        .fill(.white.opacity(0.15))
                        .frame(width: 8, height: 8)
                        .blur(radius: 4)
                        .offset(x: geo.size.width * fraction - 4)
                }
            }
        }
        .frame(height: 8)
    }

    private var balanceBarLabels: some View {
        HStack {
            Text("$\(String(format: "%.2f", paymasterBalanceUSD))")
                .font(.clashGroteskBold(size: 20))
                .foregroundColor(.white.opacity(0.85))

            Text("remaining")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))

            Spacer()

            Text("of $\(String(format: "%.0f", paymasterBalanceMax))")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Sponsored History
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "SPONSORED HISTORY", icon: "clock")

            if sponsoredHistory.isEmpty {
                emptyHistoryPlaceholder
            } else {
                ForEach(sponsoredHistory) { tx in
                    historyRow(tx)
                }
            }
        }
    }

    private var emptyHistoryPlaceholder: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "tray")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.15))
                Text("No sponsored transactions yet")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(.vertical, 18)
            Spacer()
        }
    }

    private func historyRow(_ tx: SponsoredTxEntry) -> some View {
        HStack(spacing: 12) {
            // Sponsored glow indicator
            ZStack {
                Circle()
                    .fill(.white.opacity(0.04))
                    .frame(width: 32, height: 32)

                // Subtle outer glow for sponsored
                Circle()
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    .frame(width: 32, height: 32)
                    .shadow(color: .white.opacity(0.08), radius: 6)

                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.action)
                    .font(.clashGroteskMedium(size: 12))
                    .foregroundColor(.white.opacity(0.75))

                Text(tx.chain)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(tx.gasSaved)
                    .font(.clashGroteskMedium(size: 12))
                    .foregroundColor(.white.opacity(0.6))

                Text(tx.timeAgo)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.25))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.025))
                .overlay(
                    // Subtle glow border for sponsored items
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.white.opacity(0.05), lineWidth: 1)
                )
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Shared Components
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
            Text(title)
                .font(.clashGroteskMedium(size: 11))
                .tracking(2)
                .foregroundColor(.white.opacity(0.3))
        }
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

    private func loadData() {
        paymasters = [
            PaymasterEntry(
                id: "pimlico",
                name: "Pimlico",
                description: "ERC-4337 paymaster — broad L2 coverage",
                isEnabled: true
            ),
            PaymasterEntry(
                id: "alchemy",
                name: "Alchemy Gas Manager",
                description: "Policy-based sponsorship engine",
                isEnabled: true
            ),
            PaymasterEntry(
                id: "stackup",
                name: "Stackup",
                description: "Open source bundler + paymaster",
                isEnabled: false
            ),
            PaymasterEntry(
                id: "zerodev",
                name: "ZeroDev",
                description: "Kernel smart account paymaster",
                isEnabled: false
            )
        ]

        sponsoredHistory = [
            SponsoredTxEntry(id: "1", action: "Swap ETH → USDC", chain: "Arbitrum", gasSaved: "−$0.45", timeAgo: "1h ago"),
            SponsoredTxEntry(id: "2", action: "Approve USDC", chain: "Base", gasSaved: "−$0.12", timeAgo: "3h ago"),
            SponsoredTxEntry(id: "3", action: "Transfer DAI", chain: "Optimism", gasSaved: "−$0.08", timeAgo: "1d ago"),
            SponsoredTxEntry(id: "4", action: "Create Asset", chain: "Polygon", gasSaved: "−$0.03", timeAgo: "2d ago")
        ]
    }

    private func startAnimations() {
        // Stagger entrance
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    entranceStagger = true
                }
            }
        }

        // Balance bar fill-in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 1.2)) {
                    balanceDepleted = 1.0
                }
            }
        }

        // Silk shimmer loop
        withAnimation(
            .linear(duration: 6.0)
                .repeatForever(autoreverses: false)
        ) {
            silkPhase = 1.5
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Models
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct PaymasterEntry: Identifiable {
    let id: String
    let name: String
    let description: String
    var isEnabled: Bool
}

struct SponsoredTxEntry: Identifiable {
    let id: String
    let action: String
    let chain: String
    let gasSaved: String
    let timeAgo: String
}
