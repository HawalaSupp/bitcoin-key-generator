import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Staking Overlay
// Stake assets, track rewards, select validators, claim yields.
// APY pillars, growing geometric stakes, particle reward claims,
// iris unstaking countdown, orbital validator selection.
// Monumental. Monochrome. Silk.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct StakingOverlay: View {
    @Binding var isPresented: Bool

    // ── View mode ──
    @State private var selectedTab: StakingTab = .opportunities

    enum StakingTab: String, CaseIterable {
        case opportunities = "EARN"
        case positions = "ACTIVE"
        case history = "REWARDS"
    }

    // ── Opportunities ──
    @State private var opportunities: [StakeOpportunity] = []
    @State private var expandedOpportunity: String? = nil

    // ── Active positions ──
    @State private var activeStakes: [ActiveStake] = []
    @State private var claimingId: String? = nil
    @State private var unstakingId: String? = nil

    // ── Validators ──
    @State private var validators: [StakeValidator] = []
    @State private var stakingAssetId: String? = nil
    @State private var stakeAmountText: String = ""
    @State private var selectedValidatorId: String? = nil

    // ── Rewards history ──
    @State private var rewardBlocks: [RewardBlock] = []

    // ── Totals ──
    @State private var totalStakedUSD: Double = 0
    @State private var totalRewardsUSD: Double = 0
    @State private var displayedStaked: Double = 0
    @State private var displayedRewards: Double = 0

    // ── Animation ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var silkPhase: CGFloat = 0
    @State private var pillarGrow: CGFloat = 0
    @State private var tickerTimer: Timer? = nil
    @State private var growthPulse: CGFloat = 0
    @State private var claimParticles: [ClaimParticle] = []

    // ── Hover ──
    @State private var closeHovered: Bool = false

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Body
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    var body: some View {
        ZStack {
            backdrop
            cardContainer
            particleLayer
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
        .onDisappear {
            tickerTimer?.invalidate()
            tickerTimer = nil
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
    // MARK: – Card Container
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var cardContainer: some View {
        VStack(spacing: 0) {
            headerBar
            heroValue
            tabBar
            tabContent
        }
        .frame(width: 460, height: 680)
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

            // Silk shimmer
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.0),
                            .white.opacity(0.018),
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
            Text("STAKING")
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
    // MARK: – Hero Value
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var heroValue: some View {
        VStack(spacing: 4) {
            Text(formattedMoney(displayedStaked))
                .font(.clashGroteskBold(size: 42))
                .foregroundColor(.white.opacity(0.9))

            HStack(spacing: 8) {
                Text("TOTAL STAKED")
                    .font(.clashGroteskMedium(size: 11))
                    .tracking(3)
                    .foregroundColor(.white.opacity(0.3))

                Text("·")
                    .foregroundColor(.white.opacity(0.15))

                Text("+\(formattedMoney(displayedRewards))")
                    .font(.clashGroteskMedium(size: 11))
                    .foregroundColor(.white.opacity(0.45))

                Text("earned")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
            }
        }
        .padding(.vertical, 10)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Tab Bar
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(StakingTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }

    private func tabButton(_ tab: StakingTab) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 6) {
                Text(tab.rawValue)
                    .font(.clashGroteskMedium(size: 12))
                    .tracking(2)
                    .foregroundColor(.white.opacity(selectedTab == tab ? 0.8 : 0.3))

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
                case .opportunities:
                    opportunitiesContent
                case .positions:
                    positionsContent
                case .history:
                    rewardsHistoryContent
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Opportunities Tab (APY Pillars)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var opportunitiesContent: some View {
        VStack(spacing: 20) {
            apyPillarChart
            opportunityDetailsList
        }
    }

    // -- APY Pillar Chart --
    private var apyPillarChart: some View {
        let maxAPY = opportunities.map(\.apy).max() ?? 1
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(opportunities) { opp in
                pillarColumn(opp: opp, maxAPY: maxAPY)
            }
        }
        .frame(height: 130)
        .padding(.top, 8)
    }

    private func pillarColumn(opp: StakeOpportunity, maxAPY: Double) -> some View {
        let heightFraction = CGFloat(opp.apy / max(maxAPY, 1))
        let isExpanded = expandedOpportunity == opp.id
        return VStack(spacing: 4) {
            Text(String(format: "%.1f%%", opp.apy))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(isExpanded ? 0.85 : 0.45))

            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(isExpanded ? 0.22 : 0.12),
                            .white.opacity(isExpanded ? 0.10 : 0.04)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(height: max(12, 100 * heightFraction * pillarGrow))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.white.opacity(isExpanded ? 0.2 : 0.06), lineWidth: 1)
                )

            Text(opp.symbol)
                .font(.clashGroteskMedium(size: 10))
                .foregroundColor(.white.opacity(isExpanded ? 0.7 : 0.35))
        }
        .frame(maxWidth: .infinity)
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                expandedOpportunity = expandedOpportunity == opp.id ? nil : opp.id
            }
        }
    }

    // -- Opportunity Details --
    private var opportunityDetailsList: some View {
        VStack(spacing: 8) {
            ForEach(opportunities) { opp in
                opportunityRow(opp)
            }
        }
    }

    private func opportunityRow(_ opp: StakeOpportunity) -> some View {
        let isExpanded = expandedOpportunity == opp.id
        return VStack(spacing: 0) {
            // Collapsed row
            HStack(spacing: 12) {
                assetIcon(opp.symbol)

                VStack(alignment: .leading, spacing: 2) {
                    Text(opp.name)
                        .font(.clashGroteskMedium(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                    Text(opp.network)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.2f%%", opp.apy))
                        .font(.clashGroteskBold(size: 16))
                        .foregroundColor(.white.opacity(0.85))
                    Text("APY")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    expandedOpportunity = isExpanded ? nil : opp.id
                }
            }

            // Expanded staking UI
            if isExpanded {
                expandedStakeForm(opp)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(isExpanded ? 0.05 : 0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(isExpanded ? 0.10 : 0.04), lineWidth: 1)
                )
        )
    }

    // -- Expanded Stake Form --
    private func expandedStakeForm(_ opp: StakeOpportunity) -> some View {
        VStack(spacing: 14) {
            Divider().background(.white.opacity(0.06))

            // Validator mini-orbit
            if stakingAssetId == opp.id {
                validatorOrbit(for: opp)
            } else {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        stakingAssetId = opp.id
                        selectedValidatorId = nil
                        stakeAmountText = ""
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "circle.hexagongrid")
                            .font(.system(size: 11))
                        Text("Select Validator & Stake")
                            .font(.clashGroteskMedium(size: 12))
                    }
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            // Quick stats
            HStack(spacing: 16) {
                miniStat(label: "MIN", value: opp.minStake)
                miniStat(label: "LOCK", value: opp.lockPeriod)
                miniStat(label: "NETWORK", value: opp.network)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private func miniStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
            Text(value)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Validator Orbit
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func validatorOrbit(for opp: StakeOpportunity) -> some View {
        let relevantValidators = validators.filter { $0.chain == opp.chain }
        return VStack(spacing: 14) {
            orbitRing(validators: relevantValidators)
                .frame(height: 160)

            if selectedValidatorId != nil {
                stakeInputRow(opp)
            }
        }
    }

    private func orbitRing(validators vals: [StakeValidator]) -> some View {
        let count = max(vals.count, 1)
        return ZStack {
            Circle()
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                .frame(width: 140, height: 140)

            ForEach(Array(vals.enumerated()), id: \.element.id) { idx, val in
                orbitNodePositioned(val: val, index: idx, total: count)
            }

            orbitCenterLabel(validators: vals)
        }
    }

    private func orbitNodePositioned(val: StakeValidator, index: Int, total: Int) -> some View {
        let angle: Double = (2 * .pi / Double(total)) * Double(index) - .pi / 2
        let radius: CGFloat = 62
        let isSelected: Bool = selectedValidatorId == val.id
        let diameter: CGFloat = 14 + CGFloat(val.votingPower) * 20
        let xOff: CGFloat = radius * CGFloat(cos(angle))
        let yOff: CGFloat = radius * CGFloat(sin(angle))

        return validatorNode(val: val, isSelected: isSelected, diameter: diameter)
            .offset(x: xOff, y: yOff)
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    selectedValidatorId = val.id
                }
            }
    }

    private func orbitCenterLabel(validators vals: [StakeValidator]) -> some View {
        Group {
            if let sel = vals.first(where: { $0.id == selectedValidatorId }) {
                validatorCenterInfo(sel)
            } else {
                Text("TAP\nNODE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.2))
            }
        }
    }

    private func validatorNode(val: StakeValidator, isSelected: Bool, diameter: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(.white.opacity(isSelected ? 0.15 : 0.04))
                .frame(width: diameter, height: diameter)
            Circle()
                .strokeBorder(.white.opacity(isSelected ? 0.4 : val.uptime * 0.2), lineWidth: isSelected ? 1.5 : 1)
                .frame(width: diameter, height: diameter)
            if isSelected {
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: diameter + 8, height: diameter + 8)
                    .blur(radius: 4)
            }
        }
    }

    private func validatorCenterInfo(_ v: StakeValidator) -> some View {
        VStack(spacing: 2) {
            Text(v.name)
                .font(.clashGroteskMedium(size: 10))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
            Text(String(format: "%.1f%% fee", v.commission))
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.35))
            Text(String(format: "%.0f%% up", v.uptime * 100))
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.35))
        }
    }

    private func stakeInputRow(_ opp: StakeOpportunity) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                TextField("0.00", text: $stakeAmountText)
                    .font(.clashGroteskMedium(size: 14))
                    .foregroundColor(.white.opacity(0.8))
                    .textFieldStyle(.plain)
                    .frame(width: 70)

                Text(opp.symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.08), lineWidth: 1))
            )

            Button {
                confirmStake(opp)
            } label: {
                Text("STAKE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Positions Tab (Growing forms)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var positionsContent: some View {
        VStack(spacing: 16) {
            if activeStakes.isEmpty {
                emptyPositionsView
            } else {
                ForEach(activeStakes) { stake in
                    positionCard(stake)
                }
            }
        }
    }

    private var emptyPositionsView: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.3.layers.3d.down.left")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.12))
            Text("No active stakes")
                .font(.clashGroteskMedium(size: 13))
                .foregroundColor(.white.opacity(0.25))
            Text("Choose an opportunity to start earning")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.18))
        }
        .padding(.vertical, 40)
    }

    private func positionCard(_ stake: ActiveStake) -> some View {
        let rewardFraction = CGFloat(min(stake.rewardsUSD / max(stake.stakedUSD, 1), 0.3))
        return VStack(spacing: 12) {
            // Top row
            HStack(spacing: 12) {
                assetIcon(stake.symbol)

                VStack(alignment: .leading, spacing: 2) {
                    Text(stake.validatorName)
                        .font(.clashGroteskMedium(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                    Text(stake.network)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.4f %@", stake.amount, stake.symbol))
                        .font(.clashGroteskMedium(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                    Text(formattedMoney(stake.stakedUSD))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            // Growing reward bar
            growingRewardBar(fraction: rewardFraction, rewardText: formattedMoney(stake.rewardsUSD))

            // Actions
            HStack(spacing: 10) {
                claimButton(for: stake)
                unstakeButton(for: stake)
            }

            // Unstaking iris (if deactivating)
            if stake.status == .deactivating, let remaining = stake.lockRemaining {
                irisCountdown(remaining: remaining, total: stake.lockTotal ?? 1)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // -- Growing reward bar --
    private func growingRewardBar(fraction: CGFloat, rewardText: String) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.04))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.12), .white.opacity(0.06)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * fraction * (1 + growthPulse * 0.02))

                    // Shimmer edge
                    if fraction > 0.01 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white.opacity(0.15))
                            .frame(width: 3, height: 6)
                            .offset(x: geo.size.width * fraction - 2)
                    }
                }
            }
            .frame(height: 6)

            HStack {
                Text("REWARDS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                Spacer()
                Text(rewardText)
                    .font(.clashGroteskMedium(size: 11))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
    }

    // -- Claim button --
    private func claimButton(for stake: ActiveStake) -> some View {
        Button {
            triggerClaim(stake)
        } label: {
            HStack(spacing: 4) {
                if claimingId == stake.id {
                    progressDots
                } else {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 10))
                    Text("CLAIM")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
            }
            .foregroundColor(.white.opacity(claimingId == stake.id ? 0.5 : 0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.08), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .disabled(claimingId != nil || stake.rewardsUSD <= 0)
    }

    // -- Unstake button --
    private func unstakeButton(for stake: ActiveStake) -> some View {
        Button {
            triggerUnstake(stake)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "lock.open")
                    .font(.system(size: 10))
                Text("UNSTAKE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            .foregroundColor(.white.opacity(stake.status == .deactivating ? 0.25 : 0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.06), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .disabled(stake.status == .deactivating)
    }

    // -- Iris countdown --
    private func irisCountdown(remaining: Double, total: Double) -> some View {
        let progress = 1.0 - CGFloat(remaining / max(total, 1))
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.08), lineWidth: 2)
                    .frame(width: 30, height: 30)

                // Closing iris — an arc that grows from 0 to full circle
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.white.opacity(0.25), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 30, height: 30)
                    .rotationEffect(.degrees(-90))

                Text(String(format: "%.0f%%", progress * 100))
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("UNSTAKING")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                Text("\(Int(remaining))h remaining")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer()
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Rewards History (Stacking blocks)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var rewardsHistoryContent: some View {
        VStack(spacing: 20) {
            rewardsAccumulationChart
            rewardsListSection
        }
    }

    // -- Block accumulation chart --
    private var rewardsAccumulationChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "ACCUMULATION", icon: "square.stack.3d.up")

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(rewardBlocks) { block in
                    rewardBlockColumn(block)
                }
            }
            .frame(height: 100)
            .frame(maxWidth: .infinity)
        }
    }

    private func rewardBlockColumn(_ block: RewardBlock) -> some View {
        let maxVal = rewardBlocks.map(\.amount).max() ?? 1
        let h = CGFloat(block.amount / maxVal) * 80 + 8
        return VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.08 + 0.07 * CGFloat(block.amount / maxVal)))
                .frame(height: h)

            Text(block.weekLabel)
                .font(.system(size: 7))
                .foregroundColor(.white.opacity(0.2))
        }
        .frame(maxWidth: .infinity)
    }

    // -- Rewards list --
    private var rewardsListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "HISTORY", icon: "clock")

            ForEach(rewardBlocks.suffix(6).reversed()) { block in
                HStack(spacing: 12) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(.white.opacity(0.10))
                            .frame(width: 8, height: 8)
                        if block.id != rewardBlocks.last?.id {
                            Rectangle()
                                .fill(.white.opacity(0.04))
                                .frame(width: 1, height: 20)
                        }
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(block.weekLabel)
                            .font(.clashGroteskMedium(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                        Text("+\(formattedMoney(block.amount))")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                    }

                    Spacer()

                    Text(block.asset)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.25))
                }
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Claim Particles
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var particleLayer: some View {
        ZStack {
            ForEach(claimParticles) { p in
                Circle()
                    .fill(.white.opacity(p.opacity))
                    .frame(width: p.size, height: p.size)
                    .position(p.position)
            }
        }
        .allowsHitTesting(false)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Shared Components
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func assetIcon(_ symbol: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.06))
                .frame(width: 32, height: 32)
            Text(String(symbol.prefix(1)))
                .font(.clashGroteskBold(size: 14))
                .foregroundColor(.white.opacity(0.5))
        }
    }

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

    private var progressDots: some View {
        HStack(spacing: 3) {
            dotCircle(index: 0)
            dotCircle(index: 1)
            dotCircle(index: 2)
        }
    }

    private func dotCircle(index: Int) -> some View {
        let phase = Double(index) * .pi / 3 + silkPhase * .pi * 2
        let o = 0.3 + 0.7 * abs(sin(phase))
        return Circle()
            .fill(.white.opacity(0.4))
            .frame(width: 3, height: 3)
            .opacity(o)
    }

    private func formattedMoney(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "$%.0f", value)
        }
        return String(format: "$%.2f", value)
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

    private func confirmStake(_ opp: StakeOpportunity) {
        guard let amount = Double(stakeAmountText), amount > 0, selectedValidatorId != nil else { return }
        let newStake = ActiveStake(
            id: UUID().uuidString,
            symbol: opp.symbol,
            network: opp.network,
            chain: opp.chain,
            validatorName: validators.first(where: { $0.id == selectedValidatorId })?.name ?? "Validator",
            amount: amount,
            stakedUSD: amount * opp.priceUSD,
            rewardsUSD: 0,
            apy: opp.apy,
            status: .activating,
            lockRemaining: nil,
            lockTotal: nil
        )
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            activeStakes.append(newStake)
            stakingAssetId = nil
            stakeAmountText = ""
            selectedValidatorId = nil
            expandedOpportunity = nil
            totalStakedUSD += newStake.stakedUSD
        }
    }

    private func triggerClaim(_ stake: ActiveStake) {
        guard stake.rewardsUSD > 0 else { return }
        claimingId = stake.id

        // Spawn particles
        let particleCount = 8
        for i in 0..<particleCount {
            let angle = Double(i) / Double(particleCount) * 2 * .pi
            let startX = CGFloat(230 + cos(angle) * 40)
            let startY = CGFloat(400 + sin(angle) * 30)
            let particle = ClaimParticle(
                id: UUID().uuidString,
                position: CGPoint(x: startX, y: startY),
                size: CGFloat.random(in: 3...6),
                opacity: 0.6
            )
            claimParticles.append(particle)
        }

        // Animate particles toward hero
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            DispatchQueue.main.async {
                withAnimation(.easeIn(duration: 0.8)) {
                    for i in claimParticles.indices {
                        claimParticles[i].position = CGPoint(x: 230, y: 80)
                        claimParticles[i].opacity = 0
                    }
                }
            }
        }

        // Finalise
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            DispatchQueue.main.async {
                if let idx = activeStakes.firstIndex(where: { $0.id == stake.id }) {
                    totalRewardsUSD += activeStakes[idx].rewardsUSD
                    activeStakes[idx].rewardsUSD = 0
                }
                claimingId = nil
                claimParticles.removeAll()
                animateTicker()
            }
        }
    }

    private func triggerUnstake(_ stake: ActiveStake) {
        guard let idx = activeStakes.firstIndex(where: { $0.id == stake.id }) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            activeStakes[idx].status = .deactivating
            activeStakes[idx].lockRemaining = 168 // 7 days in hours
            activeStakes[idx].lockTotal = 168
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Data & Animations
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func loadData() {
        opportunities = [
            StakeOpportunity(id: "eth", symbol: "ETH", name: "Ethereum", network: "Ethereum", chain: "ethereum", apy: 3.8, minStake: "0.01 ETH", lockPeriod: "Variable", priceUSD: 3200),
            StakeOpportunity(id: "sol", symbol: "SOL", name: "Solana", network: "Solana", chain: "solana", apy: 7.2, minStake: "0.1 SOL", lockPeriod: "~2-3 days", priceUSD: 145),
            StakeOpportunity(id: "atom", symbol: "ATOM", name: "Cosmos", network: "Cosmos Hub", chain: "cosmos", apy: 12.5, minStake: "0.1 ATOM", lockPeriod: "21 days", priceUSD: 9.50),
            StakeOpportunity(id: "dot", symbol: "DOT", name: "Polkadot", network: "Polkadot", chain: "polkadot", apy: 14.8, minStake: "1 DOT", lockPeriod: "28 days", priceUSD: 7.20),
            StakeOpportunity(id: "bnb", symbol: "BNB", name: "BNB Chain", network: "BSC", chain: "bnb", apy: 2.9, minStake: "0.01 BNB", lockPeriod: "7 days", priceUSD: 610),
            StakeOpportunity(id: "avax", symbol: "AVAX", name: "Avalanche", network: "Avalanche C", chain: "avalanche", apy: 8.1, minStake: "0.1 AVAX", lockPeriod: "14 days", priceUSD: 35)
        ]

        validators = [
            // Ethereum
            StakeValidator(id: "v-eth-1", name: "Lido", chain: "ethereum", commission: 10.0, uptime: 0.998, votingPower: 0.9),
            StakeValidator(id: "v-eth-2", name: "Rocket Pool", chain: "ethereum", commission: 5.0, uptime: 0.995, votingPower: 0.5),
            StakeValidator(id: "v-eth-3", name: "Coinbase", chain: "ethereum", commission: 25.0, uptime: 0.999, votingPower: 0.7),
            // Solana
            StakeValidator(id: "v-sol-1", name: "Marinade", chain: "solana", commission: 2.0, uptime: 0.997, votingPower: 0.65),
            StakeValidator(id: "v-sol-2", name: "Jito", chain: "solana", commission: 5.0, uptime: 0.993, votingPower: 0.8),
            StakeValidator(id: "v-sol-3", name: "Helius", chain: "solana", commission: 0.0, uptime: 0.990, votingPower: 0.3),
            StakeValidator(id: "v-sol-4", name: "Everstake", chain: "solana", commission: 7.0, uptime: 0.996, votingPower: 0.55),
            // Cosmos
            StakeValidator(id: "v-atom-1", name: "Chorus One", chain: "cosmos", commission: 7.5, uptime: 0.999, votingPower: 0.6),
            StakeValidator(id: "v-atom-2", name: "SG-1", chain: "cosmos", commission: 5.0, uptime: 0.998, votingPower: 0.45),
            StakeValidator(id: "v-atom-3", name: "Figment", chain: "cosmos", commission: 9.0, uptime: 0.997, votingPower: 0.7),
            // Polkadot
            StakeValidator(id: "v-dot-1", name: "Stakefish", chain: "polkadot", commission: 3.0, uptime: 0.996, votingPower: 0.5),
            StakeValidator(id: "v-dot-2", name: "P2P", chain: "polkadot", commission: 1.0, uptime: 0.999, votingPower: 0.4),
            StakeValidator(id: "v-dot-3", name: "Zug Capital", chain: "polkadot", commission: 5.0, uptime: 0.992, votingPower: 0.35),
            // BNB
            StakeValidator(id: "v-bnb-1", name: "Ankr", chain: "bnb", commission: 10.0, uptime: 0.998, votingPower: 0.6),
            StakeValidator(id: "v-bnb-2", name: "InfStones", chain: "bnb", commission: 8.0, uptime: 0.995, votingPower: 0.4),
            // Avalanche
            StakeValidator(id: "v-avax-1", name: "Benqi", chain: "avalanche", commission: 5.0, uptime: 0.997, votingPower: 0.55),
            StakeValidator(id: "v-avax-2", name: "GoGoPool", chain: "avalanche", commission: 2.0, uptime: 0.994, votingPower: 0.35)
        ]

        activeStakes = [
            ActiveStake(id: "as-1", symbol: "ETH", network: "Ethereum", chain: "ethereum", validatorName: "Lido", amount: 2.5, stakedUSD: 8000, rewardsUSD: 42.80, apy: 3.8, status: .active, lockRemaining: nil, lockTotal: nil),
            ActiveStake(id: "as-2", symbol: "SOL", network: "Solana", chain: "solana", validatorName: "Marinade", amount: 120, stakedUSD: 17400, rewardsUSD: 185.50, apy: 7.2, status: .active, lockRemaining: nil, lockTotal: nil),
            ActiveStake(id: "as-3", symbol: "ATOM", network: "Cosmos Hub", chain: "cosmos", validatorName: "Chorus One", amount: 500, stakedUSD: 4750, rewardsUSD: 78.30, apy: 12.5, status: .deactivating, lockRemaining: 120, lockTotal: 504)
        ]

        totalStakedUSD = activeStakes.reduce(0) { $0 + $1.stakedUSD }
        totalRewardsUSD = activeStakes.reduce(0) { $0 + $1.rewardsUSD }

        rewardBlocks = (0..<12).map { i in
            RewardBlock(
                id: "rb-\(i)",
                weekLabel: "W\(12 - i)",
                amount: Double.random(in: 5...65),
                asset: ["ETH", "SOL", "ATOM"][i % 3]
            )
        }
    }

    private func startAnimations() {
        // Pillar grow
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.75)) {
                    pillarGrow = 1.0
                }
            }
        }

        // Silk shimmer
        withAnimation(
            .linear(duration: 6.0)
                .repeatForever(autoreverses: false)
        ) {
            silkPhase = 1.5
        }

        // Growth pulse
        withAnimation(
            .easeInOut(duration: 3.0)
                .repeatForever(autoreverses: true)
        ) {
            growthPulse = 1.0
        }

        // Ticker animation for totals
        animateTicker()
    }

    private func animateTicker() {
        displayedStaked = 0
        displayedRewards = 0
        let steps = 30
        let interval = 0.03
        var step = 0
        let targetStaked = totalStakedUSD
        let targetRewards = totalRewardsUSD
        tickerTimer?.invalidate()
        tickerTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak tickerTimer] _ in
            DispatchQueue.main.async {
                step += 1
                let t = min(Double(step) / Double(steps), 1.0)
                let ease = 1.0 - pow(1.0 - t, 3)
                self.displayedStaked = targetStaked * ease
                self.displayedRewards = targetRewards * ease
                if step >= steps {
                    tickerTimer?.invalidate()
                    self.tickerTimer = nil
                }
            }
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Models
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct StakeOpportunity: Identifiable {
    let id: String
    let symbol: String
    let name: String
    let network: String
    let chain: String
    let apy: Double
    let minStake: String
    let lockPeriod: String
    let priceUSD: Double
}

struct StakeValidator: Identifiable {
    let id: String
    let name: String
    let chain: String
    let commission: Double
    let uptime: Double      // 0.0 – 1.0
    let votingPower: Double  // 0.0 – 1.0 (relative)
}

struct ActiveStake: Identifiable {
    let id: String
    let symbol: String
    let network: String
    let chain: String
    let validatorName: String
    let amount: Double
    var stakedUSD: Double
    var rewardsUSD: Double
    let apy: Double
    var status: StakeStatus
    var lockRemaining: Double? // hours
    var lockTotal: Double?     // hours

    enum StakeStatus {
        case active, activating, deactivating
    }
}

struct RewardBlock: Identifiable {
    let id: String
    let weekLabel: String
    let amount: Double
    let asset: String
}

struct ClaimParticle: Identifiable {
    let id: String
    var position: CGPoint
    let size: CGFloat
    var opacity: Double
}
