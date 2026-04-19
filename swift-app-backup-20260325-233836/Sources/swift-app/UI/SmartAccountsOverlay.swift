import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Smart Accounts Overlay
// ERC-4337 Account Abstraction.
// Counterfactual address materialisation, gas sponsorship dome,
// spending-limit constraint ring, orbital recovery guardians.
// Monumental. Monochrome. Mechanical.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct SmartAccountsOverlay: View {
    @Binding var isPresented: Bool

    // ── Account selection ──
    @State private var accounts: [SmartAccountInfo] = []
    @State private var selectedAccount: SmartAccountInfo? = nil

    // ── Creation flow ──
    @State private var showCreateFlow: Bool = false
    @State private var selectedAccountType: AccountType = .simpleAccount
    @State private var selectedChain: String = "Ethereum"
    @State private var isDeploying: Bool = false
    @State private var deployProgress: CGFloat = 0
    @State private var deployPhase: DeployPhase = .idle

    // ── Feature toggles ──
    @State private var gasSponsorship: Bool = false
    @State private var showSpendingLimits: Bool = false
    @State private var showRecovery: Bool = false
    @State private var dailyLimit: Double = 1000
    @State private var weeklyLimit: Double = 5000

    // ── Recovery guardians ──
    @State private var guardians: [GuardianNode] = []
    @State private var showAddGuardian: Bool = false
    @State private var newGuardianName: String = ""

    // ── Entrance animation ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92

    // ── Orbital / particle animation ──
    @State private var orbitalPhase: CGFloat = 0
    @State private var particlePhase: CGFloat = 0
    @State private var shieldPulse: CGFloat = 0

    // ── Hover ──
    @State private var closeHovered: Bool = false

    private let chains = ["Ethereum", "Polygon", "Arbitrum", "Optimism", "Base"]

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
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
            headerSection
            if showCreateFlow {
                creationFlow
            } else if let account = selectedAccount {
                accountDetailView(account)
            } else {
                accountListOrEmpty
            }
        }
        .frame(width: 460, height: 680)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.5), radius: 50, x: 0, y: 25)
        .scaleEffect(cardScale)
        .opacity(contentOpacity)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Header
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var headerSection: some View {
        ZStack {
            Text("Smart Accounts")
                .font(.clashGroteskMedium(size: 20))
                .foregroundColor(.white)

            HStack {
                // Back button (when in sub-views)
                if showCreateFlow || selectedAccount != nil {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            showCreateFlow = false
                            selectedAccount = nil
                            deployPhase = .idle
                            deployProgress = 0
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.4))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Close
                Button(action: dismissOverlay) {
                    Circle()
                        .fill(Color.white.opacity(closeHovered ? 0.12 : 0.08))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.5))
                        )
                }
                .buttonStyle(.plain)
                .onHover { closeHovered = $0 }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Account List / Empty State
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var accountListOrEmpty: some View {
        VStack(spacing: 0) {
            if accounts.isEmpty {
                emptyState
            } else {
                accountsList
            }
        }
    }

    // ── Empty State — particle nucleus visualization ──
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            // Nucleus visualization — dormant smart account
            nucleusVisualization

            Text("No Smart Accounts")
                .font(.clashGroteskBold(size: 28))
                .foregroundColor(.white.opacity(0.8))

            Text("Deploy an ERC-4337 account for gasless\ntransactions and social recovery")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.25))
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()

            createAccountButton
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }

    // ── Nucleus: concentric rings with floating particles ──
    private var nucleusVisualization: some View {
        ZStack {
            // Outer ring
            Circle()
                .strokeBorder(Color.white.opacity(0.03), lineWidth: 0.5)
                .frame(width: 140, height: 140)

            // Middle ring
            Circle()
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 0.5)
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(Double(orbitalPhase) * 360))

            // Inner ring
            Circle()
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                .frame(width: 60, height: 60)
                .rotationEffect(.degrees(Double(orbitalPhase) * -360))

            // Core
            Circle()
                .fill(Color.white.opacity(0.04))
                .frame(width: 24, height: 24)

            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.15))

            // Orbiting particles
            ForEach(0..<5, id: \.self) { i in
                let angle = (Double(orbitalPhase) + Double(i) * 0.2) * .pi * 2
                let radius: CGFloat = CGFloat(35 + i * 12)
                Circle()
                    .fill(Color.white.opacity(0.06 + Double(i) * 0.01))
                    .frame(width: CGFloat(2 + i % 2), height: CGFloat(2 + i % 2))
                    .offset(
                        x: cos(angle) * radius,
                        y: sin(angle) * radius * 0.6
                    )
            }
        }
        .frame(width: 160, height: 160)
    }

    // ── Accounts list (when accounts exist) ──
    private var accountsList: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(accounts, id: \.id) { account in
                        accountCard(account)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }

            Spacer(minLength: 0)

            createAccountButton
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }

    // ── Single account card in the list ──
    private func accountCard(_ account: SmartAccountInfo) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedAccount = account
            }
        }) {
            HStack(spacing: 14) {
                // Account type icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .frame(width: 42, height: 42)
                    Image(systemName: account.accountType.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(account.accountType.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                    Text(account.shortAddress)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                }

                Spacer()

                // Status
                deploymentStatusBadge(account.isDeployed)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.12))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.04), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func deploymentStatusBadge(_ isDeployed: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.white.opacity(isDeployed ? 0.25 : 0.08))
                .frame(width: 5, height: 5)
            Text(isDeployed ? "LIVE" : "GHOST")
                .font(.system(size: 8, weight: .bold))
                .tracking(1)
                .foregroundColor(.white.opacity(isDeployed ? 0.35 : 0.15))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.white.opacity(isDeployed ? 0.05 : 0.02))
        )
    }

    // ── Create account button ──
    private var createAccountButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                showCreateFlow = true
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12, weight: .semibold))
                Text("CREATE SMART ACCOUNT")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
            }
            .foregroundColor(.white.opacity(0.45))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Creation Flow
    // Counterfactual address materialises from particles,
    // then solidifies into a deployed account.
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var creationFlow: some View {
        VStack(spacing: 0) {
            if deployPhase == .idle {
                creationConfig
            } else {
                deploymentAnimation
            }
        }
    }

    // ── Configuration step ──
    private var creationConfig: some View {
        VStack(spacing: 16) {
            // Account type selector
            VStack(alignment: .leading, spacing: 8) {
                Text("ACCOUNT TYPE")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.2))
                    .padding(.horizontal, 24)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(AccountType.allCases, id: \.self) { type in
                            accountTypeRow(type)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .frame(maxHeight: 200)
            }

            // Chain selector
            VStack(alignment: .leading, spacing: 8) {
                Text("NETWORK")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.2))
                    .padding(.horizontal, 24)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(chains, id: \.self) { chain in
                            chainChip(chain)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }

            // Counterfactual address preview
            addressPreview

            Spacer(minLength: 0)

            // Deploy button
            deployButton
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .padding(.top, 8)
    }

    private func accountTypeRow(_ type: AccountType) -> some View {
        let isSelected = selectedAccountType == type
        return Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                selectedAccountType = type
            }
        }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(isSelected ? 0.06 : 0.03))
                        .frame(width: 36, height: 36)
                    Image(systemName: type.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(isSelected ? 0.45 : 0.2))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(isSelected ? 0.7 : 0.4))
                    Text(type.description)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.2))
                }

                Spacer()

                // Radio
                Circle()
                    .strokeBorder(Color.white.opacity(isSelected ? 0.3 : 0.1), lineWidth: 1.5)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .fill(Color.white.opacity(isSelected ? 0.3 : 0))
                            .frame(width: 8, height: 8)
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.035 : 0.015))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(isSelected ? 0.06 : 0.02), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func chainChip(_ chain: String) -> some View {
        let isSelected = selectedChain == chain
        return Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                selectedChain = chain
            }
        }) {
            Text(chain)
                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                .foregroundColor(.white.opacity(isSelected ? 0.6 : 0.2))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(isSelected ? 0.06 : 0.02))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(isSelected ? 0.08 : 0.03), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // ── Counterfactual address preview ──
    // The address flickers like particles assembling before deployment.
    private var addressPreview: some View {
        let addr = counterfactualAddress
        let flickerChars = particleFlickerAddress(addr)

        return VStack(spacing: 6) {
            Text("COUNTERFACTUAL ADDRESS")
                .font(.system(size: 8, weight: .bold))
                .tracking(2)
                .foregroundColor(.white.opacity(0.15))

            Text(flickerChars)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .lineLimit(1)
                .truncationMode(.middle)

            Text("Address exists but is not yet deployed on-chain")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.12))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.02))
                .padding(.horizontal, 24)
        )
    }

    // ── Deploy button ──
    private var deployButton: some View {
        Button(action: startDeployment) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.circle")
                    .font(.system(size: 12, weight: .semibold))
                Text("DEPLOY ACCOUNT")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
            }
            .foregroundColor(.white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Deployment Animation
    // Mechanical assembly: components click together,
    // particles coalesce, address solidifies.
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var deploymentAnimation: some View {
        VStack(spacing: 24) {
            Spacer()

            // Assembly visualization
            assemblyVisualization

            // Phase label
            phaseLabel

            // Progress bar
            deployProgressBar

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var assemblyVisualization: some View {
        ZStack {
            // Outer assembly ring — expands as progress increases
            Circle()
                .strokeBorder(Color.white.opacity(0.04), lineWidth: deployProgress > 0.3 ? 1 : 0.5)
                .frame(
                    width: 120 + (deployProgress * 20),
                    height: 120 + (deployProgress * 20)
                )
                .scaleEffect(deployPhase == .complete ? 1.1 : 1)

            // Middle ring — clicks into place at 50%
            Circle()
                .strokeBorder(Color.white.opacity(deployProgress > 0.5 ? 0.1 : 0.03), lineWidth: 1)
                .frame(width: 80, height: 80)
                .rotationEffect(.degrees(deployProgress > 0.5 ? 0 : 45))

            // Inner core — solidifies
            Circle()
                .fill(Color.white.opacity(deployProgress > 0.8 ? 0.08 : 0.02))
                .frame(width: 40, height: 40)

            // Account type icon — appears at centre
            Image(systemName: selectedAccountType.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(Double(deployProgress) * 0.5))

            // Assembly particles converging toward centre
            if deployPhase == .assembling || deployPhase == .materializing {
                ForEach(0..<8, id: \.self) { i in
                    let angle = Double(i) * .pi / 4 + Double(orbitalPhase) * .pi * 2
                    let dist: CGFloat = max(10, 80 * (1 - deployProgress))
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 3, height: 3)
                        .offset(
                            x: cos(angle) * dist,
                            y: sin(angle) * dist
                        )
                }
            }

            // Solidified checkmark
            if deployPhase == .complete {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .offset(y: 30)
                    .transition(.opacity.combined(with: .scale(scale: 0.5)))
            }
        }
        .frame(width: 160, height: 160)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: deployProgress)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: deployPhase)
    }

    private var phaseLabel: some View {
        VStack(spacing: 4) {
            Text(deployPhase.label)
                .font(.clashGroteskBold(size: 22))
                .foregroundColor(.white.opacity(0.7))

            Text(deployPhase.detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.2))
        }
    }

    private var deployProgressBar: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.03))

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: geo.size.width * deployProgress)
                }
            }
            .frame(height: 4)

            HStack {
                Text("\(Int(deployProgress * 100))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                Spacer()
                Text(selectedChain.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.12))
            }
        }
        .padding(.horizontal, 40)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Account Detail View
    // Central status hub with shield, spending ring, guardians.
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func accountDetailView(_ account: SmartAccountInfo) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                accountStatusHub(account)
                gasSponsorshipSection
                spendingLimitsSection
                recoveryGuardiansSection
                accountInfoSection(account)
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    // ── Account Status Hub ──
    // Central visualization: the account as a shielded nucleus.
    // Shield activates when gas sponsorship is on.
    // Spending limit shown as a constraining ring.
    private func accountStatusHub(_ account: SmartAccountInfo) -> some View {
        ZStack {
            // Spending limit ring — shrinks with lower limits
            let limitFraction = CGFloat(dailyLimit / 10000)
            let ringSize: CGFloat = 100 + limitFraction * 40
            Circle()
                .strokeBorder(
                    Color.white.opacity(showSpendingLimits ? 0.08 : 0.03),
                    style: StrokeStyle(lineWidth: showSpendingLimits ? 2 : 0.5, dash: showSpendingLimits ? [4, 4] : [])
                )
                .frame(width: ringSize, height: ringSize)
                .animation(.easeInOut(duration: 0.5), value: dailyLimit)

            // Gas sponsorship shield dome
            if gasSponsorship {
                sponsorshipShield
            }

            // Core account
            VStack(spacing: 4) {
                Image(systemName: account.accountType.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))

                Text(account.isDeployed ? "LIVE" : "GHOST")
                    .font(.system(size: 7, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(account.isDeployed ? 0.3 : 0.15))
            }

            // Guardian satellites
            ForEach(guardians.indices, id: \.self) { i in
                let count = guardians.count
                let angle = (Double(orbitalPhase) + Double(i) / Double(max(count, 1))) * .pi * 2
                let orbitRadius: CGFloat = (ringSize / 2) + 20

                guardianSatellite(guardians[i])
                    .offset(
                        x: cos(angle) * orbitRadius,
                        y: sin(angle) * orbitRadius * 0.5
                    )
            }
        }
        .frame(height: 180)
        .padding(.vertical, 4)
    }

    // ── Gas sponsorship shield ──
    private var sponsorshipShield: some View {
        ZStack {
            // Shield arcs
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .trim(from: CGFloat(i) * 0.33, to: CGFloat(i) * 0.33 + 0.2)
                    .stroke(
                        Color.white.opacity(0.06 + Double(shieldPulse) * 0.04),
                        lineWidth: 1.5
                    )
                    .frame(width: CGFloat(76 + i * 8), height: CGFloat(76 + i * 8))
                    .rotationEffect(.degrees(Double(orbitalPhase) * 120 + Double(i) * 40))
            }

            // Shield label
            Text("SPONSORED")
                .font(.system(size: 6, weight: .bold))
                .tracking(2)
                .foregroundColor(.white.opacity(0.12))
                .offset(y: 48)
        }
    }

    // ── Guardian satellite node ──
    private func guardianSatellite(_ guardian: GuardianNode) -> some View {
        VStack(spacing: 2) {
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.white.opacity(0.25))
                )
            Text(guardian.initials)
                .font(.system(size: 6, weight: .bold))
                .foregroundColor(.white.opacity(0.15))
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Feature Sections
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    // ── Gas Sponsorship ──
    private var gasSponsorshipSection: some View {
        featureCard(
            icon: "shield.checkered",
            title: "Gas Sponsorship",
            subtitle: gasSponsorship ? "Paymaster active" : "Pay gas from your balance",
            isExpanded: .constant(true)
        ) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PAYMASTER")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.15))
                    Text(gasSponsorship ? "Transactions are gas-free" : "Enable gasless transactions")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.25))
                }

                Spacer()

                // Toggle
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        gasSponsorship.toggle()
                    }
                }) {
                    sponsorshipToggle
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sponsorshipToggle: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(gasSponsorship ? 0.08 : 0.03))
                .frame(width: 44, height: 24)
            Capsule()
                .strokeBorder(Color.white.opacity(gasSponsorship ? 0.12 : 0.05), lineWidth: 0.5)
                .frame(width: 44, height: 24)
            Circle()
                .fill(Color.white.opacity(gasSponsorship ? 0.35 : 0.1))
                .frame(width: 18, height: 18)
                .offset(x: gasSponsorship ? 10 : -10)
        }
    }

    // ── Spending Limits ──
    private var spendingLimitsSection: some View {
        featureCard(
            icon: "circle.dashed",
            title: "Spending Limits",
            subtitle: showSpendingLimits ? "Active constraints" : "No limits set",
            isExpanded: $showSpendingLimits
        ) {
            VStack(spacing: 12) {
                limitSlider(label: "DAILY", value: $dailyLimit, range: 100...10000)
                limitSlider(label: "WEEKLY", value: $weeklyLimit, range: 500...50000)
            }
        }
    }

    private func limitSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.15))
                Spacer()
                Text("$\(Int(value.wrappedValue))")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }

            GeometryReader { geo in
                let fraction = CGFloat((value.wrappedValue - range.lowerBound) / (range.upperBound - range.lowerBound))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.white.opacity(0.03))

                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: geo.size.width * fraction)
                }
                .frame(height: 3)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let frac = min(1, max(0, drag.location.x / geo.size.width))
                            value.wrappedValue = range.lowerBound + Double(frac) * (range.upperBound - range.lowerBound)
                        }
                )
            }
            .frame(height: 3)
        }
    }

    // ── Recovery Guardians ──
    private var recoveryGuardiansSection: some View {
        featureCard(
            icon: "person.3",
            title: "Recovery Guardians",
            subtitle: guardians.isEmpty ? "No guardians configured" : "\(guardians.count) guardian\(guardians.count == 1 ? "" : "s")",
            isExpanded: $showRecovery
        ) {
            VStack(spacing: 8) {
                // Guardian list
                ForEach(guardians, id: \.id) { guardian in
                    guardianRow(guardian)
                }

                // Add guardian
                if showAddGuardian {
                    addGuardianInput
                } else {
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            showAddGuardian = true
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .bold))
                            Text("ADD GUARDIAN")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1)
                        }
                        .foregroundColor(.white.opacity(0.2))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.05), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func guardianRow(_ guardian: GuardianNode) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.white.opacity(0.04))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.2))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(guardian.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                Text(guardian.shortAddress)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.15))
            }

            Spacer()

            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    guardians.removeAll { $0.id == guardian.id }
                }
            }) {
                Image(systemName: "minus.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.15))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
    }

    private var addGuardianInput: some View {
        HStack(spacing: 8) {
            TextField("Guardian name", text: $newGuardianName)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                )

            Button(action: addGuardian) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)

            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    showAddGuardian = false
                    newGuardianName = ""
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.2))
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // ── Account Info ──
    private func accountInfoSection(_ account: SmartAccountInfo) -> some View {
        VStack(spacing: 4) {
            infoRow(label: "ADDRESS", value: account.shortAddress)
            infoRow(label: "TYPE", value: account.accountType.displayName)
            infoRow(label: "CHAIN ID", value: "\(account.chainId)")
            infoRow(label: "BALANCE", value: "\(account.balance) ETH")
            infoRow(label: "STATUS", value: account.isDeployed ? "Deployed" : "Counterfactual")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.03), lineWidth: 0.5)
        )
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.12))
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.vertical, 4)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Feature Card Container
    // Reusable collapsible section.
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func featureCard<Content: View>(
        icon: String,
        title: String,
        subtitle: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            // Header row
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isExpanded.wrappedValue.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.3))
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.55))
                        Text(subtitle)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.18))
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.15))
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            // Content
            if isExpanded.wrappedValue {
                content()
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.04), lineWidth: 0.5)
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Actions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func startDeployment() {
        deployPhase = .assembling
        deployProgress = 0

        // Phase 1: Assembling (0→0.4)
        withAnimation(.easeInOut(duration: 1.2)) { deployProgress = 0.4 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            deployPhase = .materializing

            // Phase 2: Materializing (0.4→0.8)
            withAnimation(.easeInOut(duration: 1.0)) { deployProgress = 0.8 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                deployPhase = .deploying

                // Phase 3: Deploying (0.8→1.0)
                withAnimation(.easeInOut(duration: 0.8)) { deployProgress = 1.0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        deployPhase = .complete
                    }

                    // Create the account
                    let newAccount = SmartAccountInfo(
                        id: UUID().uuidString,
                        address: counterfactualAddress,
                        accountType: selectedAccountType,
                        isDeployed: true,
                        chainId: chainId(for: selectedChain),
                        balance: "0.0"
                    )

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            accounts.append(newAccount)
                            selectedAccount = newAccount
                            showCreateFlow = false
                            deployPhase = .idle
                            deployProgress = 0
                        }
                    }
                }
            }
        }
    }

    private func addGuardian() {
        guard !newGuardianName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let guardian = GuardianNode(
            id: UUID().uuidString,
            name: newGuardianName,
            address: "0x" + String((0..<40).map { _ in "0123456789abcdef".randomElement()! })
        )
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            guardians.append(guardian)
            newGuardianName = ""
            showAddGuardian = false
        }
    }

    private func dismissOverlay() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            cardScale = 0.95
            contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isPresented = false
        }
    }

    private func startAnimations() {
        withAnimation(
            .linear(duration: 12)
            .repeatForever(autoreverses: false)
        ) {
            orbitalPhase = 1
        }
        withAnimation(
            .easeInOut(duration: 2)
            .repeatForever(autoreverses: true)
        ) {
            shieldPulse = 1
        }
        // Particle flicker timer
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            DispatchQueue.main.async {
                particlePhase = CGFloat.random(in: 0...1)
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Helpers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var counterfactualAddress: String {
        // Deterministic-looking address based on type + chain
        let base = selectedAccountType.rawValue + selectedChain
        let hash = abs(base.hashValue)
        return "0x" + String(format: "%040x", hash).prefix(40)
    }

    private func particleFlickerAddress(_ addr: String) -> String {
        // Occasionally replace characters with dots to simulate particle assembly
        let chars = Array(addr)
        var result = chars
        let flickerCount = Int(particlePhase * 6) + 2
        for _ in 0..<flickerCount {
            let idx = Int.random(in: 2..<min(chars.count, 40))
            if idx < result.count {
                result[idx] = "·"
            }
        }
        return String(result)
    }

    private func chainId(for chain: String) -> Int {
        switch chain {
        case "Ethereum": return 1
        case "Polygon": return 137
        case "Arbitrum": return 42161
        case "Optimism": return 10
        case "Base": return 8453
        default: return 1
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Supporting Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private enum DeployPhase {
    case idle, assembling, materializing, deploying, complete

    var label: String {
        switch self {
        case .idle: return ""
        case .assembling: return "Assembling"
        case .materializing: return "Materialising"
        case .deploying: return "Deploying"
        case .complete: return "Deployed"
        }
    }

    var detail: String {
        switch self {
        case .idle: return ""
        case .assembling: return "Constructing account bytecode"
        case .materializing: return "Computing counterfactual address"
        case .deploying: return "Submitting UserOperation to bundler"
        case .complete: return "Smart account is live on-chain"
        }
    }
}

struct GuardianNode: Identifiable {
    let id: String
    let name: String
    let address: String

    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var shortAddress: String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }
}
