import SwiftUI
#if os(macOS)
import AppKit
#endif

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Backup Overlay
// Vault-grade backup command center.
// Concentric vault rings, hold-to-reveal phrase,
// word-by-word materialization, geometric verification,
// encrypted export sealing animation.
// Monumental. Monochrome. Protective.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct BackupOverlay: View {
    @Binding var isPresented: Bool

    // ── Section nav ──
    @State private var activeSection: BkSection = .status

    enum BkSection: String, CaseIterable {
        case status       = "STATUS"
        case phrase       = "PHRASE"
        case verify       = "VERIFY"
        case export       = "EXPORT"
        case guide        = "GUIDE"
    }

    // ── Backup status ──
    @State private var isBackedUp: Bool = true
    @State private var lastVerifiedDate: Date = Calendar.current.date(byAdding: .day, value: -42, to: Date()) ?? Date()
    @State private var walletCreatedDate: Date = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
    @State private var reminderInterval: Int = 3  // months

    // ── Recovery phrase ──
    private let mockPhrase: [String] = [
        "abandon", "ability", "able", "about", "above", "absent",
        "absorb", "abstract", "absurd", "abuse", "access", "accident"
    ]
    @State private var phraseRevealed: Bool = false
    @State private var revealProgress: CGFloat = 0     // hold-to-reveal 0→1
    @State private var isHoldingReveal: Bool = false
    @State private var revealedWordCount: Int = 0      // words materialized so far
    @State private var autoHideTimer: Int = 60         // seconds until auto-hide
    @State private var autoHideActive: Bool = false
    @State private var acknowledgedWarning: Bool = false
    @State private var hasCopied: Bool = false

    // ── Verification ──
    @State private var verifyStage: VerifyStage = .notStarted
    @State private var verifyQuestions: [(Int, String)] = []  // (wordIndex, correctAnswer)
    @State private var verifyCurrentQ: Int = 0
    @State private var verifyInput: String = ""
    @State private var verifyResults: [Bool] = []
    @State private var verifyComplete: Bool = false

    enum VerifyStage {
        case notStarted, inProgress, complete
    }

    // ── Encrypted export ──
    @State private var exportPassword: String = ""
    @State private var exportConfirmPassword: String = ""
    @State private var exportInProgress: Bool = false
    @State private var exportComplete: Bool = false
    @State private var exportSealProgress: CGFloat = 0

    // ── Backup history ──
    @State private var backupHistory: [BkHistoryEntry] = []

    // ── Animation ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var silkPhase: CGFloat = 0
    @State private var vaultPulse: CGFloat = 0

    // ── Hover ──
    @State private var closeHovered: Bool = false

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Body
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    var body: some View {
        ZStack {
            backdrop
            cardShell
        }
        .background(
            EscapeKeyHandler(isPresented: $isPresented, onEscape: dismissOverlay)
        )
        .onAppear {
            loadMockHistory()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardScale = 1; contentOpacity = 1
            }
            startAnimations()
        }
    }

    private var backdrop: some View {
        Color.black.opacity(0.75)
            .ignoresSafeArea()
            .onTapGesture { dismissOverlay() }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Card
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Header
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var headerBar: some View {
        ZStack {
            Text("BACKUP")
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

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Section Picker
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(BkSection.allCases, id: \.self) { sec in
                    bkTabButton(sec)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 8)
    }

    private func bkTabButton(_ sec: BkSection) -> some View {
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

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Section Content
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var sectionContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                switch activeSection {
                case .status: statusContent
                case .phrase: phraseContent
                case .verify: verifyContent
                case .export: exportContent
                case .guide: guideContent
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Status (Vault Visualization)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var statusContent: some View {
        VStack(spacing: 20) {
            vaultVisualization
            statusDetails
            bkSectionLabel("BACKUP HISTORY")
            historyList
            bkSectionLabel("REMINDERS")
            reminderCard
        }
    }

    // Vault door — concentric rings that are complete when backed up, broken when not
    private var vaultVisualization: some View {
        VStack(spacing: 12) {
            ZStack {
                // 4 concentric vault rings
                ForEach(0..<4, id: \.self) { i in
                    vaultRing(index: i)
                }
                // Center indicator
                VStack(spacing: 3) {
                    Image(systemName: isBackedUp ? "lock.fill" : "lock.open")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(isBackedUp ? 0.50 : 0.20))
                    Text(isBackedUp ? "SECURED" : "UNPROTECTED")
                        .font(.system(size: 6, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(isBackedUp ? 0.35 : 0.20))
                }
            }
            .frame(height: 140)
        }
    }

    private func vaultRing(index: Int) -> some View {
        let size: CGFloat = CGFloat(36 + index * 20)
        let trimEnd: CGFloat = isBackedUp ? 1.0 : vaultBrokenTrim(index)
        let op = isBackedUp ? vaultRingOpacity(index) : 0.06
        return Circle()
            .trim(from: 0, to: trimEnd)
            .stroke(
                .white.opacity(op),
                style: StrokeStyle(
                    lineWidth: isBackedUp ? vaultLineWidth(index) : 1.0,
                    lineCap: .round
                )
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(Double(index) * 15 - 90))
    }

    private func vaultBrokenTrim(_ index: Int) -> CGFloat {
        [0.25, 0.4, 0.15, 0.55][min(index, 3)]
    }

    private func vaultRingOpacity(_ index: Int) -> Double {
        [0.30, 0.22, 0.16, 0.10][min(index, 3)]
    }

    private func vaultLineWidth(_ index: Int) -> CGFloat {
        index == 0 ? 2.5 : (index < 3 ? 1.5 : 1.0)
    }

    private var statusDetails: some View {
        VStack(spacing: 6) {
            statusRow(label: "STATUS", value: isBackedUp ? "BACKED UP" : "NOT BACKED UP")
            if isBackedUp {
                statusRow(label: "LAST VERIFIED", value: relativeDate(lastVerifiedDate))
                statusRow(label: "DAYS SINCE VERIFICATION", value: "\(daysSince(lastVerifiedDate))")
            } else {
                statusRow(label: "WALLET CREATED", value: relativeDate(walletCreatedDate))
                statusRow(label: "DAYS WITHOUT BACKUP", value: "\(daysSince(walletCreatedDate))")
            }
            statusRow(label: "PHRASE LENGTH", value: "\(mockPhrase.count) WORDS")
        }
        .padding(14)
        .background(bkCardBg)
    }

    private func statusRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.20))
                .tracking(0.5)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
        }
    }

    // History list
    private var historyList: some View {
        VStack(spacing: 2) {
            if backupHistory.isEmpty {
                Text("No backup activity recorded")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.15))
                    .padding(.vertical, 16)
            } else {
                ForEach(backupHistory) { entry in
                    historyRow(entry)
                }
            }
        }
        .background(bkCardBg)
    }

    private func historyRow(_ entry: BkHistoryEntry) -> some View {
        HStack(spacing: 10) {
            // Timeline dot
            ZStack {
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 18, height: 18)
                Image(systemName: entry.icon)
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.25))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.action.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.35))
                Text(entry.detail)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.white.opacity(0.18))
            }
            Spacer()
            Text(relativeDate(entry.date))
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.white.opacity(0.15))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // Reminder card
    private var reminderCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("REMIND TO VERIFY EVERY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                Spacer()
            }
            HStack(spacing: 4) {
                ForEach([1, 3, 6, 0], id: \.self) { months in
                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) { reminderInterval = months }
                    } label: {
                        Text(months == 0 ? "NEVER" : "\(months)M")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(reminderInterval == months ? 0.6 : 0.2))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.white.opacity(reminderInterval == months ? 0.06 : 0.02))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(bkCardBg)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Recovery Phrase (Hold-to-Reveal)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var phraseContent: some View {
        VStack(spacing: 16) {
            if !acknowledgedWarning {
                warningGate
            } else if !phraseRevealed {
                holdToRevealSection
            } else {
                revealedPhraseSection
            }
        }
    }

    // ── Step 1: Warning gate ──
    private var warningGate: some View {
        VStack(spacing: 20) {
            // Warning frame — expanding geometric borders
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: CGFloat(12 + i * 4))
                        .strokeBorder(
                            .white.opacity(0.06 + Double(2 - i) * 0.03),
                            lineWidth: 1
                        )
                        .frame(
                            width: CGFloat(260 + i * 24),
                            height: CGFloat(160 + i * 16)
                        )
                }
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(.white.opacity(0.40))

                    Text("CRITICAL SECURITY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.45))
                }
            }
            .frame(height: 200)

            // Warning bullets
            warningBullet(text: "Never share your recovery phrase with anyone")
            warningBullet(text: "Anyone with these words controls your funds")
            warningBullet(text: "Store securely offline — never in cloud, email, or photos")
            warningBullet(text: "HAWALA support will never ask for your phrase")

            // Acknowledge button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    acknowledgedWarning = true
                }
            } label: {
                Text("I UNDERSTAND THE RISKS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.50))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func warningBullet(text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Diamond marker
            Diamond()
                .fill(.white.opacity(0.20))
                .frame(width: 6, height: 6)
                .padding(.top, 4)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.40))
                .lineSpacing(2)
        }
    }

    // ── Step 2: Hold to reveal ──
    private var holdToRevealSection: some View {
        VStack(spacing: 24) {
            // Hold-to-reveal instruction
            Text("HOLD TO REVEAL PHRASE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.35))

            // Hold target — fills as user presses
            holdRevealButton

            Text("Press and hold for 2 seconds to reveal your recovery phrase")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.20))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(.top, 40)
    }

    private var holdRevealButton: some View {
        ZStack {
            // Outer ring — progress
            Circle()
                .strokeBorder(.white.opacity(0.06), lineWidth: 3)
                .frame(width: 100, height: 100)
            Circle()
                .trim(from: 0, to: revealProgress)
                .stroke(.white.opacity(0.30), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(-90))

            // Center
            VStack(spacing: 4) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(.white.opacity(isHoldingReveal ? 0.50 : 0.25))
                Text("HOLD")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.25))
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in startHoldReveal() }
                .onEnded { _ in cancelHoldReveal() }
        )
    }

    // ── Step 3: Revealed phrase ──
    private var revealedPhraseSection: some View {
        VStack(spacing: 16) {
            // Auto-hide timer
            autoHideBar

            // The phrase grid
            phraseGrid

            // Actions
            phraseActions

            // Post-reveal prompt
            postRevealPrompt
        }
    }

    private var autoHideBar: some View {
        VStack(spacing: 4) {
            HStack {
                Text("AUTO-HIDE IN")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.20))
                Spacer()
                Text("\(autoHideTimer)s")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.white.opacity(0.04))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.white.opacity(0.15))
                        .frame(width: geo.size.width * CGFloat(autoHideTimer) / 60.0)
                }
            }
            .frame(height: 2)
        }
    }

    // Word grid — words materialize one by one
    private var phraseGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ], spacing: 8) {
            ForEach(Array(mockPhrase.enumerated()), id: \.offset) { index, word in
                phraseWordTile(index: index, word: word)
            }
        }
        .padding(16)
        .background(bkCardBg)
    }

    private func phraseWordTile(index: Int, word: String) -> some View {
        let visible = index < revealedWordCount
        return HStack(spacing: 4) {
            Text("\(index + 1)")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(visible ? 0.20 : 0.06))
                .frame(width: 16, alignment: .trailing)
            Text(visible ? word : "·····")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(visible ? 0.65 : 0.08))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(visible ? 0.04 : 0.015))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.white.opacity(visible ? 0.08 : 0.03), lineWidth: 0.8)
                )
        )
        .opacity(visible ? 1 : 0.5)
    }

    private var phraseActions: some View {
        HStack(spacing: 8) {
            // Copy
            Button {
                copyPhrase()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: hasCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9))
                    Text(hasCopied ? "COPIED" : "COPY")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                }
                .foregroundColor(.white.opacity(hasCopied ? 0.40 : 0.25))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03)))
            }
            .buttonStyle(.plain)

            // Hide
            Button {
                hidePhrase()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 9))
                    Text("HIDE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                }
                .foregroundColor(.white.opacity(0.25))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03)))
            }
            .buttonStyle(.plain)
        }
    }

    private var postRevealPrompt: some View {
        VStack(spacing: 8) {
            Text("Have you written down your phrase securely?")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.30))

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    activeSection = .verify
                    hidePhrase()
                }
            } label: {
                Text("VERIFY MY BACKUP NOW")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.05))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.10)))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Verification
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var verifyContent: some View {
        VStack(spacing: 16) {
            switch verifyStage {
            case .notStarted:
                verifyIntro
            case .inProgress:
                verifyQuestionView
            case .complete:
                verifyResultView
            }
        }
    }

    private var verifyIntro: some View {
        VStack(spacing: 20) {
            // Shield checkpoint icon
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .strokeBorder(.white.opacity(0.04 + Double(2 - i) * 0.02), lineWidth: 1)
                        .frame(width: CGFloat(50 + i * 20), height: CGFloat(50 + i * 20))
                }
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(.white.opacity(0.35))
            }
            .frame(height: 100)

            Text("SECURITY CHECKPOINT")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(3)
                .foregroundColor(.white.opacity(0.40))

            Text("Verify you have correctly stored your recovery phrase by answering 4 questions about specific words.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.25))
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Button {
                startVerification()
            } label: {
                Text("BEGIN VERIFICATION")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.50))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.white.opacity(0.05))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 20)
    }

    private var verifyQuestionView: some View {
        VStack(spacing: 20) {
            // Progress indicator
            verifyProgressIndicator

            if verifyCurrentQ < verifyQuestions.count {
                let question = verifyQuestions[verifyCurrentQ]
                let wordNum = question.0 + 1

                Text("WHAT IS WORD #\(wordNum)?")
                    .font(.clashGroteskBold(size: 24))
                    .foregroundColor(.white.opacity(0.70))

                // Input field
                TextField("Type word \(wordNum)...", text: $verifyInput)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.03))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.08)))
                    )
                    .onSubmit { submitVerifyAnswer() }

                // Submit
                Button {
                    submitVerifyAnswer()
                } label: {
                    Text("CONFIRM")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.white.opacity(verifyInput.isEmpty ? 0.15 : 0.50))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.white.opacity(verifyInput.isEmpty ? 0.02 : 0.06))
                        )
                }
                .buttonStyle(.plain)
                .disabled(verifyInput.isEmpty)
            }
        }
    }

    private var verifyProgressIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<verifyQuestions.count, id: \.self) { i in
                verifyProgressDot(index: i)
            }
        }
    }

    private func verifyProgressDot(index: Int) -> some View {
        ZStack {
            if index < verifyResults.count {
                // Answered
                Circle()
                    .fill(.white.opacity(verifyResults[index] ? 0.35 : 0.08))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle().strokeBorder(.white.opacity(verifyResults[index] ? 0.20 : 0.06), lineWidth: 1)
                    )
                Image(systemName: verifyResults[index] ? "checkmark" : "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(verifyResults[index] ? 0.50 : 0.20))
            } else if index == verifyCurrentQ {
                // Current
                Circle()
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                Text("\(index + 1)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.40))
            } else {
                // Future
                Circle()
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                    .frame(width: 20, height: 20)
            }
        }
    }

    private var verifyResultView: some View {
        let correct = verifyResults.filter { $0 }.count
        let total = verifyResults.count
        let allCorrect = correct == total

        return VStack(spacing: 20) {
            // Result visualization
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .strokeBorder(
                            .white.opacity(allCorrect ? (0.08 + Double(2 - i) * 0.04) : 0.03),
                            lineWidth: 1
                        )
                        .frame(width: CGFloat(50 + i * 20), height: CGFloat(50 + i * 20))
                }
                Image(systemName: allCorrect ? "checkmark.shield.fill" : "shield.slash")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(.white.opacity(allCorrect ? 0.50 : 0.20))
            }
            .frame(height: 100)

            Text(allCorrect ? "VERIFICATION PASSED" : "VERIFICATION INCOMPLETE")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(allCorrect ? 0.55 : 0.30))

            Text("\(correct) of \(total) words correct")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))

            if allCorrect {
                Text("Your recovery phrase is verified and backed up securely.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.30))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            } else {
                Text("Review your recovery phrase and try again to ensure your backup is correct.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                Button {
                    startVerification()
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
        }
        .padding(.top, 20)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Encrypted Export
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var exportContent: some View {
        VStack(spacing: 16) {
            if exportComplete {
                exportCompleteView
            } else if exportInProgress {
                exportProgressView
            } else {
                exportForm
            }
        }
    }

    private var exportForm: some View {
        VStack(spacing: 16) {
            bkSectionLabel("ENCRYPTED BACKUP")

            Text("Create a password-protected backup file containing your wallet data. Keep both the file and password secure.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.25))
                .lineSpacing(2)

            // Password field
            VStack(alignment: .leading, spacing: 6) {
                Text("PASSWORD")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.20))
                    .tracking(0.5)
                SecureField("Enter password", text: $exportPassword)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.06)))
                    )
            }

            // Password strength
            passwordStrengthBar

            // Confirm password
            VStack(alignment: .leading, spacing: 6) {
                Text("CONFIRM PASSWORD")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.20))
                    .tracking(0.5)
                SecureField("Confirm password", text: $exportConfirmPassword)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.06)))
                    )
                if !exportConfirmPassword.isEmpty && exportPassword != exportConfirmPassword {
                    Text("Passwords do not match")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                }
            }

            // Cloud warning
            cloudWarning

            // Export button
            Button {
                beginExport()
            } label: {
                Text("CREATE ENCRYPTED BACKUP")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(canExport ? 0.50 : 0.15))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.white.opacity(canExport ? 0.06 : 0.02))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(.white.opacity(canExport ? 0.12 : 0.04))
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canExport)
        }
    }

    // Password strength geometric fill
    private var passwordStrengthBar: some View {
        let strength = passwordStrength(exportPassword)
        return VStack(spacing: 4) {
            HStack {
                Text("STRENGTH")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.18))
                Spacer()
                Text(strengthLabel(strength))
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(strengthOpacity(strength)))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.04))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(strengthOpacity(strength)))
                        .frame(width: geo.size.width * strength)
                }
            }
            .frame(height: 3)
        }
    }

    // Cloud warning
    private var cloudWarning: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 14, weight: .light))
                .foregroundColor(.white.opacity(0.20))
            VStack(alignment: .leading, spacing: 3) {
                Text("NEVER STORE IN CLOUD")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.30))
                Text("Do not upload this backup to iCloud, Google Drive, Dropbox, or any cloud service. Store on encrypted local media only.")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.20))
                    .lineSpacing(2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.015))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.05)))
        )
    }

    // Export progress — sealing animation
    private var exportProgressView: some View {
        VStack(spacing: 24) {
            // Container sealing animation
            ZStack {
                // Container body
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.04))
                    .frame(width: 80, height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1.5)
                    )

                // Seal line moving down
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 76, height: 2)
                    .offset(y: -48 + exportSealProgress * 96)

                // Lock icon at center
                Image(systemName: "lock.fill")
                    .font(.system(size: 16, weight: .light))
                    .foregroundColor(.white.opacity(exportSealProgress > 0.5 ? 0.40 : 0.10))
            }
            .frame(height: 120)

            Text("ENCRYPTING & SEALING")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.35))

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.04))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.20))
                        .frame(width: geo.size.width * exportSealProgress)
                }
            }
            .frame(height: 3)
        }
        .padding(.top, 40)
    }

    // Export complete
    private var exportCompleteView: some View {
        VStack(spacing: 20) {
            ZStack {
                // Sealed container
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.06))
                    .frame(width: 80, height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1.5)
                    )
                Image(systemName: "lock.fill")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(.white.opacity(0.40))
            }
            .frame(height: 120)

            Text("BACKUP SEALED")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.50))

            Text("Encrypted backup file created. Store the file and its password in separate, secure locations.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.25))
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    exportComplete = false
                    exportPassword = ""
                    exportConfirmPassword = ""
                    exportSealProgress = 0
                }
            } label: {
                Text("DONE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.40))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 20)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Guide & Education
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var guideContent: some View {
        VStack(spacing: 16) {
            bkSectionLabel("BEST PRACTICES")
            bestPracticesCard

            bkSectionLabel("METAL BACKUP")
            metalBackupCard

            bkSectionLabel("WHAT TO AVOID")
            avoidCard
        }
    }

    private var bestPracticesCard: some View {
        VStack(spacing: 10) {
            guideRow(icon: "pencil.and.outline", title: "WRITE IT DOWN", detail: "Use pen and paper. Write clearly. Verify each word number and spelling.")
            Divider().background(.white.opacity(0.04))
            guideRow(icon: "doc.on.doc", title: "MULTIPLE COPIES", detail: "Store at least two copies in separate secure locations. Consider a trusted family member.")
            Divider().background(.white.opacity(0.04))
            guideRow(icon: "clock.arrow.2.circlepath", title: "VERIFY PERIODICALLY", detail: "Test your backup every 6 months to ensure it remains intact and readable.")
            Divider().background(.white.opacity(0.04))
            guideRow(icon: "lock.square.stack", title: "SECURE LOCATION", detail: "Home safe, bank safety deposit box, or fireproof document container.")
        }
        .padding(14)
        .background(bkCardBg)
    }

    private var metalBackupCard: some View {
        VStack(spacing: 10) {
            guideRow(icon: "hammer", title: "STEEL STAMPING", detail: "Stamp your seed words into stainless steel plates. Survives fire, flood, and corrosion. DIY with letter punches.")
            Divider().background(.white.opacity(0.04))
            guideRow(icon: "flame.fill", title: "FIREPROOF STORAGE", detail: "Metal plates withstand temperatures up to 1450°C. Paper burns at 230°C. Metal is the permanent solution.")
            Divider().background(.white.opacity(0.04))
            guideRow(icon: "drop.fill", title: "WATERPROOF", detail: "Stainless steel resists water damage indefinitely. Paper and ink degrade over time, especially in humid environments.")
        }
        .padding(14)
        .background(bkCardBg)
    }

    private var avoidCard: some View {
        VStack(spacing: 8) {
            avoidRow(text: "Never store in cloud services (iCloud, Google Drive, Dropbox)")
            avoidRow(text: "Never take a screenshot or photo of your seed phrase")
            avoidRow(text: "Never type into email, messaging apps, or notes apps")
            avoidRow(text: "Never store on a device connected to the internet")
            avoidRow(text: "Never share with anyone claiming to be support")
        }
        .padding(14)
        .background(bkCardBg)
    }

    private func guideRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(0.04))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.25))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.35))
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.20))
                    .lineSpacing(2)
            }
        }
    }

    private func avoidRow(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // X marker
            Image(systemName: "xmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.white.opacity(0.15))
                .padding(.top, 3)
            Text(text)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.22))
                .lineSpacing(2)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Shared Components
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func bkSectionLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
                .tracking(1)
            Spacer()
        }
    }

    private var bkCardBg: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(.white.opacity(0.025))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.05), lineWidth: 1))
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
        withAnimation(.linear(duration: 6.0).repeatForever(autoreverses: false)) { silkPhase = 1.5 }
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) { vaultPulse = 1.0 }
    }

    // ── Hold-to-reveal ──
    private func startHoldReveal() {
        guard !isHoldingReveal else { return }
        isHoldingReveal = true
        // Animate progress from 0→1 over 2 seconds
        withAnimation(.linear(duration: 2.0)) {
            revealProgress = 1.0
        }
        // After 2 seconds, reveal
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if self.isHoldingReveal {
                self.phraseRevealed = true
                self.startWordMaterialization()
                self.startAutoHideCountdown()
            }
        }
    }

    private func cancelHoldReveal() {
        isHoldingReveal = false
        if !phraseRevealed {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                revealProgress = 0
            }
        }
    }

    private func startWordMaterialization() {
        revealedWordCount = 0
        for i in 0..<mockPhrase.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.15) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    revealedWordCount = i + 1
                }
            }
        }
    }

    private func startAutoHideCountdown() {
        autoHideTimer = 60
        autoHideActive = true
        tickAutoHide()
    }

    private func tickAutoHide() {
        guard autoHideActive, autoHideTimer > 0 else {
            if autoHideTimer <= 0 { hidePhrase() }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if self.autoHideActive {
                self.autoHideTimer -= 1
                self.tickAutoHide()
            }
        }
    }

    private func hidePhrase() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            phraseRevealed = false
            revealProgress = 0
            revealedWordCount = 0
            isHoldingReveal = false
            autoHideActive = false
            hasCopied = false
        }
    }

    private func copyPhrase() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(mockPhrase.joined(separator: " "), forType: .string)
        #endif
        hasCopied = true
        // Auto-clear clipboard after 60 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            #if os(macOS)
            NSPasteboard.general.clearContents()
            #endif
        }
    }

    // ── Verification ──
    private func startVerification() {
        // Pick 4 random unique indices
        var indices = Array(0..<mockPhrase.count)
        indices.shuffle()
        let picked = Array(indices.prefix(4)).sorted()
        verifyQuestions = picked.map { ($0, mockPhrase[$0]) }
        verifyResults = []
        verifyCurrentQ = 0
        verifyInput = ""
        verifyComplete = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            verifyStage = .inProgress
        }
    }

    private func submitVerifyAnswer() {
        guard verifyCurrentQ < verifyQuestions.count else { return }
        let correct = verifyInput.lowercased().trimmingCharacters(in: .whitespaces) == verifyQuestions[verifyCurrentQ].1
        verifyResults.append(correct)
        verifyInput = ""

        if verifyCurrentQ + 1 < verifyQuestions.count {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                verifyCurrentQ += 1
            }
        } else {
            // Complete
            let allCorrect = verifyResults.allSatisfy { $0 }
            if allCorrect {
                isBackedUp = true
                lastVerifiedDate = Date()
                backupHistory.insert(
                    BkHistoryEntry(action: "Verification Passed", detail: "\(verifyResults.count)/\(verifyResults.count) correct", icon: "checkmark.shield", date: Date()),
                    at: 0
                )
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                verifyStage = .complete
            }
        }
    }

    // ── Export ──
    private var canExport: Bool {
        exportPassword.count >= 8 &&
        exportPassword == exportConfirmPassword
    }

    private func beginExport() {
        guard canExport else { return }
        exportInProgress = true
        exportSealProgress = 0

        withAnimation(.easeInOut(duration: 2.5)) {
            exportSealProgress = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            self.exportInProgress = false
            self.exportComplete = true
            self.backupHistory.insert(
                BkHistoryEntry(action: "Encrypted Export", detail: "wallet_backup.hawala", icon: "lock.doc", date: Date()),
                at: 0
            )
        }
    }

    private func passwordStrength(_ pw: String) -> CGFloat {
        guard !pw.isEmpty else { return 0 }
        var score: CGFloat = 0
        if pw.count >= 8 { score += 0.20 }
        if pw.count >= 12 { score += 0.15 }
        if pw.count >= 16 { score += 0.10 }
        if pw.rangeOfCharacter(from: .uppercaseLetters) != nil { score += 0.15 }
        if pw.rangeOfCharacter(from: .lowercaseLetters) != nil { score += 0.10 }
        if pw.rangeOfCharacter(from: .decimalDigits) != nil { score += 0.15 }
        if pw.rangeOfCharacter(from: CharacterSet.punctuationCharacters.union(.symbols)) != nil { score += 0.15 }
        return min(1.0, score)
    }

    private func strengthLabel(_ s: CGFloat) -> String {
        if s >= 0.85 { return "STRONG" }
        if s >= 0.55 { return "MODERATE" }
        if s > 0 { return "WEAK" }
        return ""
    }

    private func strengthOpacity(_ s: CGFloat) -> Double {
        if s >= 0.85 { return 0.35 }
        if s >= 0.55 { return 0.22 }
        return 0.12
    }

    // ── Helpers ──
    private func relativeDate(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        return "\(Int(diff / 86400))d ago"
    }

    private func daysSince(_ date: Date) -> Int {
        Int(Date().timeIntervalSince(date) / 86400)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Mock Data
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func loadMockHistory() {
        backupHistory = [
            BkHistoryEntry(action: "Verification Passed", detail: "4/4 correct", icon: "checkmark.shield", date: Calendar.current.date(byAdding: .day, value: -42, to: Date()) ?? Date()),
            BkHistoryEntry(action: "Encrypted Export", detail: "wallet_backup.hawala", icon: "lock.doc", date: Calendar.current.date(byAdding: .day, value: -42, to: Date()) ?? Date()),
            BkHistoryEntry(action: "Phrase Viewed", detail: "Duration: 25s", icon: "eye", date: Calendar.current.date(byAdding: .day, value: -45, to: Date()) ?? Date()),
            BkHistoryEntry(action: "Verification Passed", detail: "4/4 correct", icon: "checkmark.shield", date: Calendar.current.date(byAdding: .month, value: -4, to: Date()) ?? Date()),
            BkHistoryEntry(action: "Wallet Created", detail: "12-word phrase generated", icon: "plus.circle", date: Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()),
        ]
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Models
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct BkHistoryEntry: Identifiable {
    let id = UUID()
    let action: String
    let detail: String
    let icon: String
    let date: Date
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Diamond Shape
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}
