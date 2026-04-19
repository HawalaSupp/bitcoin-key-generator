import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Privacy Overlay
// Master privacy toggle, balance hiding, address blur, tx history, screenshots.
// Every toggle wired to real PrivacyManager — zero dummy data.
// Monochrome · Monumental · Mechanical.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct PrivacyOverlay: View {
    @Binding var isPresented: Bool

    // ── Real manager ──
    @ObservedObject private var privacy = PrivacyManager.shared

    // ── UI state ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var silkPhase: CGFloat = 0
    @State private var closeHovered = false

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
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                silkPhase = 1.5
            }
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
                VStack(spacing: 20) {
                    masterToggleSection
                    if privacy.isPrivacyModeEnabled {
                        balancesSection
                        addressesSection
                        transactionsSection
                        networkSection
                        screenshotSection
                        revealSection
                    }
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
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.0), .white.opacity(0.02), .white.opacity(0.0)],
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
            Text("PRIVACY")
                .font(.clashGroteskMedium(size: 14))
                .tracking(3)
                .foregroundColor(.white.opacity(0.5))

            HStack {
                Spacer()
                Button(action: dismissOverlay) {
                    Circle()
                        .fill(closeHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                        )
                }
                .buttonStyle(.plain)
                .onHover { closeHovered = $0 }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Master Toggle
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var masterToggleSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: privacy.isPrivacyModeEnabled ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 22))
                    .foregroundColor(privacy.isPrivacyModeEnabled ? .green : .white.opacity(0.3))
                    .animation(.easeInOut(duration: 0.2), value: privacy.isPrivacyModeEnabled)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Privacy Mode")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                    Text(privacy.isPrivacyModeEnabled
                         ? "Active — sensitive data redacted"
                         : "Disabled — all data visible")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.35))
                }

                Spacer()

                Toggle("", isOn: $privacy.isPrivacyModeEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if !privacy.isPrivacyModeEnabled {
                Text("Enable privacy mode to configure which data is hidden across the app.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.25))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(
            privacy.isPrivacyModeEnabled
            ? Color.green.opacity(0.04)
            : Color.white.opacity(0.03)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    privacy.isPrivacyModeEnabled
                    ? Color.green.opacity(0.12)
                    : Color.white.opacity(0.06),
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.2), value: privacy.isPrivacyModeEnabled)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Balances
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var balancesSection: some View {
        VStack(spacing: 10) {
            privSectionHeader(icon: "dollarsign.circle", title: "Balances")

            privToggleRow(
                label: "Hide all balances",
                detail: "Show ●●●●●● instead of amounts",
                isOn: $privacy.hideBalances
            )
        }
        .privSectionCard()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Addresses
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var addressesSection: some View {
        VStack(spacing: 10) {
            privSectionHeader(icon: "textformat.abc", title: "Addresses")

            privToggleRow(
                label: "Blur wallet addresses",
                detail: "Only show first 6 and last 4 characters",
                isOn: $privacy.blurAddresses
            )
        }
        .privSectionCard()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Transactions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var transactionsSection: some View {
        VStack(spacing: 10) {
            privSectionHeader(icon: "list.bullet.rectangle", title: "Transactions")

            privToggleRow(
                label: "Hide transaction history",
                detail: "Redact all past transactions from view",
                isOn: $privacy.hideTransactionHistory
            )
        }
        .privSectionCard()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Network
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var networkSection: some View {
        VStack(spacing: 10) {
            privSectionHeader(icon: "network", title: "Network")

            privToggleRow(
                label: "Pause price fetching",
                detail: "Stops outgoing API calls for market data",
                isOn: $privacy.pausePriceFetching
            )
        }
        .privSectionCard()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Screenshots
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var screenshotSection: some View {
        VStack(spacing: 10) {
            privSectionHeader(icon: "camera.metering.none", title: "Screen Capture")

            privToggleRow(
                label: "Prevent screenshots",
                detail: "Sets window sharing type to none (macOS)",
                isOn: $privacy.disableScreenshots
            )
        }
        .privSectionCard()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Temporary Reveal
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var revealSection: some View {
        VStack(spacing: 10) {
            privSectionHeader(icon: "eye", title: "Quick Reveal")

            Text("Tap below to temporarily show hidden data for 5 seconds, then it auto-hides.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
                .fixedSize(horizontal: false, vertical: true)

            if privacy.temporaryRevealActive {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Revealing — auto-hides in a few seconds")
                        .font(.system(size: 12))
                        .foregroundColor(.green.opacity(0.8))
                    Spacer()
                    Button("Hide Now") {
                        privacy.endTemporaryReveal()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .buttonStyle(.plain)
                }
            } else {
                PrivOverlayButton(label: "Reveal Content", icon: "eye") {
                    privacy.temporaryReveal()
                }
            }
        }
        .privSectionCard()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Helpers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func privSectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.35))
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.35))
            Spacer()
        }
    }

    private func privToggleRow(label: String, detail: String? = nil, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Toggle("", isOn: isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            if let detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
            }
        }
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

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Reusable Components
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private struct PrivOverlayButton: View {
    let label: String
    let icon: String
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.6))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(hovered ? 0.08 : 0.04))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: – Section Card Modifier

private struct PrivSectionCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

extension View {
    fileprivate func privSectionCard() -> some View {
        modifier(PrivSectionCardModifier())
    }
}
