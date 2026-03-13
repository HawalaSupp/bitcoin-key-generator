import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Payment Links Premium Overlay
// Matches the Bitcoin detail card aesthetic: monumental typography, strictly
// monochrome, mechanical interactions, silk animated background.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct PaymentLinksOverlay: View {
    @Binding var isPresented: Bool
    let receiveAddress: String

    // ── Build steps ──
    enum BuildPhase: Int, CaseIterable {
        case amount = 0
        case currency = 1
        case memo = 2
        case assembled = 3
    }

    // ── State ──
    @State private var buildPhase: BuildPhase = .amount
    @State private var amount: String = ""
    @State private var selectedCurrency: LinkCurrency = .bitcoin
    @State private var memo: String = ""
    @State private var generatedLink: String = ""
    @State private var showQR = false
    @State private var qrScale: CGFloat = 0.01
    @State private var isCopied = false
    @State private var copyParticlePhase: CGFloat = 0
    @State private var showHistory = false

    // ── Link history (simulated persistence) ──
    @State private var linkHistory: [PaymentLinkRecord] = []

    // ── Entrance animation ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92

    // ── Hover states ──
    @State private var closeHovered = false
    @State private var generateHovered = false
    @State private var copyHovered = false
    @State private var shareHovered = false
    @State private var historyHovered = false
    @State private var newLinkHovered = false

    // ── Expiration ──
    @State private var selectedExpiration: ExpirationOption = .oneHour

    enum ExpirationOption: String, CaseIterable {
        case fifteenMin = "15M"
        case oneHour = "1H"
        case oneDay = "24H"
        case oneWeek = "7D"
        case never = "∞"

        var label: String { rawValue }

        var seconds: UInt64? {
            switch self {
            case .fifteenMin: return 900
            case .oneHour:    return 3600
            case .oneDay:     return 86400
            case .oneWeek:    return 604800
            case .never:      return nil
            }
        }
    }

    enum LinkCurrency: String, CaseIterable {
        case bitcoin  = "BTC"
        case ethereum = "ETH"
        case litecoin = "LTC"
        case solana   = "SOL"
        case usdc     = "USDC"

        var protocolName: String {
            switch self {
            case .bitcoin:  return "BIP-21"
            case .ethereum: return "EIP-681"
            case .litecoin: return "BIP-21"
            case .solana:   return "Solana Pay"
            case .usdc:     return "EIP-681"
            }
        }
    }

    struct PaymentLinkRecord: Identifiable {
        let id = UUID()
        let link: String
        let amount: String
        let currency: LinkCurrency
        let memo: String
        let created: Date
        let expiresAt: Date?
        var status: LinkStatus = .pending

        enum LinkStatus {
            case pending, paid, expired

            var label: String {
                switch self {
                case .pending: return "PENDING"
                case .paid:    return "PAID"
                case .expired: return "EXPIRED"
                }
            }
        }

        var isExpired: Bool {
            guard let exp = expiresAt else { return false }
            return Date() > exp
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Body
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    var body: some View {
        ZStack {
            // ── Dimmed backdrop ──
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture { dismissOverlay() }

            // ── Card ──
            VStack(spacing: 0) {
                headerSection

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        if generatedLink.isEmpty {
                            // ── Builder flow ──
                            builderSection
                        } else {
                            // ── Result: QR + link ──
                            resultSection
                        }

                        // ── History timeline ──
                        if showHistory || !linkHistory.isEmpty {
                            historySection
                        }
                    }
                }
            }
            .frame(width: 440, height: 620)
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
        }
        .background(
            EscapeKeyHandler(isPresented: $isPresented, onEscape: dismissOverlay)
        )
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardScale = 1
                contentOpacity = 1
            }
            loadHistory()
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Header
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var headerSection: some View {
        ZStack {
            Text("Payment Links")
                .font(.clashGroteskMedium(size: 20))
                .foregroundColor(.white)

            HStack {
                // History toggle
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        showHistory.toggle()
                    }
                }) {
                    Circle()
                        .fill(Color.white.opacity(historyHovered ? 0.10 : (showHistory ? 0.10 : 0.06)))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color.white.opacity(showHistory ? 0.6 : 0.4))
                        )
                }
                .buttonStyle(.plain)
                .onHover { historyHovered = $0 }

                Spacer()

                Button(action: dismissOverlay) {
                    Circle()
                        .fill(Color.white.opacity(closeHovered ? 0.12 : 0.08))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.5))
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

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Builder (Assembler)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var builderSection: some View {
        VStack(spacing: 0) {
            // ── Hero amount display ──
            amountHero
                .padding(.top, 8)
                .padding(.bottom, 16)

            // ── Three mechanical assembly blocks ──
            VStack(spacing: 1) {
                // Block 1: Amount
                assemblyBlock(
                    phase: .amount,
                    icon: "number",
                    label: "AMOUNT",
                    isActive: buildPhase == .amount
                ) {
                    TextField("0.00", text: $amount)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 160)
                        .onSubmit { advancePhase() }
                }

                // Block 2: Currency
                assemblyBlock(
                    phase: .currency,
                    icon: "bitcoinsign.circle",
                    label: "CURRENCY",
                    isActive: buildPhase == .currency
                ) {
                    HStack(spacing: 6) {
                        ForEach(LinkCurrency.allCases, id: \.self) { currency in
                            Button(action: {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                                    selectedCurrency = currency
                                }
                            }) {
                                Text(currency.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(selectedCurrency == currency ? .white : .white.opacity(0.4))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(selectedCurrency == currency ? Color.white.opacity(0.10) : Color.clear)
                                    )
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(
                                                Color.white.opacity(selectedCurrency == currency ? 0.12 : 0.04),
                                                lineWidth: 0.5
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Block 3: Memo + Expiration
                assemblyBlock(
                    phase: .memo,
                    icon: "text.alignleft",
                    label: "DETAILS",
                    isActive: buildPhase == .memo
                ) {
                    VStack(spacing: 10) {
                        TextField("Optional memo", text: $memo)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))

                        // Expiration selector
                        HStack(spacing: 0) {
                            Text("EXPIRES")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(1.5)
                                .foregroundColor(.white.opacity(0.25))
                                .frame(width: 54, alignment: .leading)

                            HStack(spacing: 4) {
                                ForEach(ExpirationOption.allCases, id: \.self) { option in
                                    Button(action: {
                                        withAnimation(.easeOut(duration: 0.15)) {
                                            selectedExpiration = option
                                        }
                                    }) {
                                        Text(option.label)
                                            .font(.system(size: 10, weight: selectedExpiration == option ? .bold : .medium, design: .monospaced))
                                            .foregroundColor(selectedExpiration == option ? .white : .white.opacity(0.3))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                    .fill(selectedExpiration == option ? Color.white.opacity(0.08) : Color.clear)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // ── Generate button ──
            generateButton
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .opacity(contentOpacity)
    }

    // ── Hero: live-updating amount display ──
    private var amountHero: some View {
        VStack(spacing: 6) {
            let displayAmount = amount.isEmpty ? "0.00" : amount
            Text(displayAmount)
                .font(.clashGroteskBold(size: 42))
                .foregroundColor(.white.opacity(amount.isEmpty ? 0.25 : 1))
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: amount)

            HStack(spacing: 6) {
                Text(selectedCurrency.rawValue)
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.5)

                Text("·")

                Text(selectedCurrency.protocolName)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
    }

    // ── Assembly block (mechanical element) ──
    private func assemblyBlock<Content: View>(
        phase: BuildPhase,
        icon: String,
        label: String,
        isActive: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isCompleted = buildPhase.rawValue > phase.rawValue || !generatedLink.isEmpty

        return HStack(spacing: 12) {
            // Phase indicator
            ZStack {
                Circle()
                    .fill(Color.white.opacity(isActive ? 0.10 : (isCompleted ? 0.06 : 0.03)))
                    .frame(width: 28, height: 28)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(isActive ? 0.5 : 0.2))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.25))

                content()
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(isActive ? 0.04 : 0.02))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                buildPhase = phase
            }
        }
    }

    // ── Generate link button ──
    private var generateButton: some View {
        Button(action: generateLink) {
            HStack(spacing: 8) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                Text("Generate Link")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(generateHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(generateHovered ? 0.15 : 0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { generateHovered = $0 }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Result Section (QR + Actions)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var resultSection: some View {
        VStack(spacing: 0) {
            // ── Amount confirmed ──
            VStack(spacing: 6) {
                let displayAmount = amount.isEmpty ? "0.00" : amount
                Text(displayAmount)
                    .font(.clashGroteskBold(size: 42))
                    .foregroundColor(.white)

                HStack(spacing: 6) {
                    Text(selectedCurrency.rawValue)
                        .font(.system(size: 13, weight: .bold))
                        .tracking(1.5)
                    Text("·")
                    Text("Payment Request")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.35))

                if !memo.isEmpty {
                    Text("\"\(memo)\"")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                        .italic()
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 20)

            // ── QR Code (iris reveal) ──
            qrSection
                .padding(.bottom, 16)

            // ── Link text ──
            linkDisplay
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

            // ── Action buttons ──
            actionButtons
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

            // ── New Link button ──
            Button(action: resetBuilder) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("New Link")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(newLinkHovered ? Color.white.opacity(0.06) : Color.white.opacity(0.03))
                )
            }
            .buttonStyle(.plain)
            .onHover { newLinkHovered = $0 }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .opacity(contentOpacity)
    }

    // ── QR with iris animation ──
    private var qrSection: some View {
        ZStack {
            // Subtle radial glow behind QR
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.04), Color.clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 100
                    )
                )
                .frame(width: 200, height: 200)
                .scaleEffect(qrScale)

            if showQR {
                // QR code — rendered monochrome
                MonochromeQRView(content: generatedLink, size: 160)
                    .scaleEffect(qrScale)
                    .opacity(Double(qrScale))
            }
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
    }

    // ── Link text display ──
    private var linkDisplay: some View {
        VStack(spacing: 6) {
            Text("PAYMENT URI")
                .font(.system(size: 8, weight: .bold))
                .tracking(2)
                .foregroundColor(.white.opacity(0.2))

            Text(generatedLink)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        }
    }

    // ── Copy + Share buttons ──
    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Copy
            Button(action: copyLink) {
                HStack(spacing: 8) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 14, weight: .semibold))
                    Text(isCopied ? "Copied" : "Copy")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(copyHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(isCopied ? 0.20 : (copyHovered ? 0.15 : 0.08)), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .onHover { copyHovered = $0 }

            // Share
            Button(action: shareLink) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Share")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(shareHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(shareHovered ? 0.15 : 0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .onHover { shareHovered = $0 }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – History Timeline
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var historySection: some View {
        VStack(spacing: 0) {
            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
                .padding(.horizontal, 24)

            // Header
            HStack {
                Text("HISTORY")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.25))

                Spacer()

                Text("\(linkHistory.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)

            if linkHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "link.circle")
                        .font(.system(size: 24, weight: .thin))
                        .foregroundColor(.white.opacity(0.15))

                    Text("No payment links yet")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.2))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                // Timeline
                VStack(spacing: 0) {
                    ForEach(Array(linkHistory.enumerated()), id: \.element.id) { index, record in
                        PaymentLinkTimelineRow(record: record, isLast: index == linkHistory.count - 1)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Actions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func advancePhase() {
        guard buildPhase.rawValue < BuildPhase.assembled.rawValue else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            buildPhase = BuildPhase(rawValue: buildPhase.rawValue + 1) ?? .assembled
        }
    }

    private func generateLink() {
        let expiresAt: UInt64? = {
            guard let secs = selectedExpiration.seconds else { return nil }
            return UInt64(Date().timeIntervalSince1970) + secs
        }()

        let request = HawalaBridge.PaymentRequest(
            to: receiveAddress,
            amount: amount.isEmpty ? nil : amount,
            token: selectedCurrency.rawValue,
            chainId: nil,
            memo: memo.isEmpty ? nil : memo,
            requestId: UUID().uuidString,
            expiresAt: expiresAt,
            callbackUrl: nil
        )

        // Try protocol-specific link generation with fallback
        var link: String = ""
        do {
            switch selectedCurrency {
            case .bitcoin, .litecoin:
                link = try HawalaBridge.shared.createBip21Link(request: request)
            case .ethereum, .usdc:
                link = try HawalaBridge.shared.createEip681Link(request: request)
            default:
                link = try HawalaBridge.shared.createPaymentLink(request: request)
            }
        } catch {
            // Fallback: build a simple hawala:// link
            var components = "hawala://pay?to=\(receiveAddress)"
            if !amount.isEmpty { components += "&amount=\(amount)" }
            components += "&token=\(selectedCurrency.rawValue)"
            if !memo.isEmpty { components += "&memo=\(memo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? memo)" }
            link = components
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            generatedLink = link
            buildPhase = .assembled
        }

        // Record in history
        let expiration: Date? = {
            guard let secs = selectedExpiration.seconds else { return nil }
            return Date().addingTimeInterval(TimeInterval(secs))
        }()

        let record = PaymentLinkRecord(
            link: link,
            amount: amount.isEmpty ? "Any" : amount,
            currency: selectedCurrency,
            memo: memo,
            created: Date(),
            expiresAt: expiration
        )
        linkHistory.insert(record, at: 0)

        // Iris-reveal the QR
        showQR = true
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.1)) {
            qrScale = 1.0
        }
    }

    private func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(generatedLink, forType: .string)

        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { isCopied = false }
        }
    }

    private func shareLink() {
        let picker = NSSharingServicePicker(items: [generatedLink as Any])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }

    private func resetBuilder() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            generatedLink = ""
            amount = ""
            memo = ""
            showQR = false
            qrScale = 0.01
            isCopied = false
            buildPhase = .amount
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

    private func loadHistory() {
        // History lives in-memory for this session;
        // persisted records could be loaded from UserDefaults here.
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Monochrome QR View
// Pure black-and-white QR rendered as inverted (white code on dark surface)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private struct MonochromeQRView: View {
    let content: String
    let size: CGFloat

    private var qrImage: CGImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(content.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let output = filter.outputImage else { return nil }

        // Invert colors: dark background with white modules
        guard let inverted = CIFilter(name: "CIColorInvert", parameters: [kCIInputImageKey: output])?.outputImage else {
            return nil
        }

        let scale = size / inverted.extent.width
        let scaled = inverted.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(scaled, from: scaled.extent)
    }

    var body: some View {
        Group {
            if let cgImage = qrImage {
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
                Image(nsImage: nsImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "qrcode")
                            .font(.system(size: 32, weight: .thin))
                            .foregroundColor(.white.opacity(0.15))
                    )
            }
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Timeline Row
// Film-strip style timeline entry for link history
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private struct PaymentLinkTimelineRow: View {
    let record: PaymentLinksOverlay.PaymentLinkRecord
    let isLast: Bool

    @State private var isHovered = false

    private var effectiveStatus: PaymentLinksOverlay.PaymentLinkRecord.LinkStatus {
        if record.isExpired { return .expired }
        return record.status
    }

    private var statusOpacity: Double {
        switch effectiveStatus {
        case .paid:    return 0.35
        case .expired: return 0.25
        case .pending: return 1.0
        }
    }

    private var timeAgo: String {
        let interval = Date().timeIntervalSince(record.created)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Timeline spine
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.white.opacity(effectiveStatus == .pending ? 0.3 : 0.10))
                    .frame(width: 8, height: 8)

                if !isLast {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 8)

            // Content
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("\(record.amount) \(record.currency.rawValue)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)

                        Text(effectiveStatus.label)
                            .font(.system(size: 8, weight: .heavy))
                            .tracking(1)
                            .foregroundColor(.white.opacity(0.3))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }

                    if !record.memo.isEmpty {
                        Text(record.memo)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.25))
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(timeAgo)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.2))

                    if let exp = record.expiresAt {
                        let remaining = exp.timeIntervalSinceNow
                        if remaining > 0 {
                            Text(formatRemaining(remaining))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.15))
                        }
                    }
                }

                // Copy shortcut on hover
                if isHovered {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(record.link, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.3))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .padding(.leading, 8)
                }
            }
            .padding(.vertical, 8)
        }
        .opacity(statusOpacity)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contentShape(Rectangle())
    }

    private func formatRemaining(_ seconds: TimeInterval) -> String {
        if seconds < 3600 {
            return "\(Int(seconds / 60))m left"
        } else if seconds < 86400 {
            return "\(Int(seconds / 3600))h left"
        } else {
            return "\(Int(seconds / 86400))d left"
        }
    }
}
