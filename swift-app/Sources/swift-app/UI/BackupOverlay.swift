import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Backup Overlay
// Vault-grade backup command center — fully wired to real services.
// No mock data. Every feature functional.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct BackupOverlay: View {
    @Binding var isPresented: Bool
    var onBackToSettings: (() -> Void)? = nil

    // ── Section nav ──
    @State private var activeSection: BkSection = .status

    enum BkSection: String, CaseIterable {
        case status  = "STATUS"
        case phrase  = "PHRASE"
        case verify  = "VERIFY"
        case backup  = "BACKUP"
        case guide   = "GUIDE"
    }

    // ── History store ──
    @StateObject private var historyStore = BackupHistoryStore.shared

    // ── Phrase state ──
    @State private var realPhrase: [String] = []
    @State private var phraseRevealed: Bool = false
    @State private var revealProgress: CGFloat = 0
    @State private var isHoldingReveal: Bool = false
    @State private var revealedWordCount: Int = 0
    @State private var autoHideTimer: Int = 60
    @State private var autoHideActive: Bool = false
    @State private var acknowledgedWarning: Bool = false
    @State private var hasCopied: Bool = false
    @State private var phraseError: String? = nil
    @State private var isFetchingPhrase: Bool = false

    // ── Verification ──
    @State private var verifyStage: VerifyStage = .notStarted
    @State private var verifyQuestions: [(Int, String)] = []
    @State private var verifyCurrentQ: Int = 0
    @State private var verifyInput: String = ""
    @State private var verifyResults: [Bool] = []
    @State private var verifyPhrase: [String] = []

    enum VerifyStage { case notStarted, inProgress, complete }

    // ── Backup (Export + Import) ──
    @State private var backupMode: BackupMode = .export
    enum BackupMode { case export, import_ }

    @State private var exportPassword: String = ""
    @State private var exportConfirmPassword: String = ""
    @State private var exportInProgress: Bool = false
    @State private var exportComplete: Bool = false
    @State private var exportError: String? = nil

    @State private var importFileData: Data? = nil
    @State private var importFileName: String? = nil
    @State private var importPassword: String = ""
    @State private var importInProgress: Bool = false
    @State private var importResult: ImportResult? = nil
    @State private var importError: String? = nil
    @State private var importPreview: BackupManager.BackupContents? = nil

    // ── Animation ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var silkPhase: CGFloat = 0

    // ── Hover ──
    @State private var closeHovered: Bool = false
    @State private var backHovered: Bool = false

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
        .frame(width: 540, height: 720)
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
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(selected ? 0.85 : 0.35))
                    .padding(.horizontal, 10)
                RoundedRectangle(cornerRadius: 1)
                    .fill(.white.opacity(selected ? 0.5 : 0))
                    .frame(height: 2)
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
                case .backup: backupContent
                case .guide: guideContent
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – STATUS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var statusContent: some View {
        VStack(spacing: 20) {
            statusIndicator
            statusDetails
            bkSectionLabel("BACKUP HISTORY")
            historyList
            bkSectionLabel("REMINDERS")
            reminderCard
        }
    }

    private var statusIndicator: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.08), lineWidth: 3)
                    .frame(width: 60, height: 60)
                if historyStore.isBackedUp {
                    Circle()
                        .fill(.white.opacity(0.06))
                        .frame(width: 60, height: 60)
                }
                Image(systemName: historyStore.isBackedUp ? "lock.fill" : "lock.open")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(historyStore.isBackedUp ? 0.50 : 0.18))
            }
            Text(historyStore.isBackedUp ? "SECURED" : "NOT BACKED UP")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(historyStore.isBackedUp ? 0.45 : 0.25))
        }
        .padding(.vertical, 8)
    }

    private var statusDetails: some View {
        let walletManager = WalletManager.shared
        let walletCount = walletManager.hdWallets.count
        let accountCount = walletManager.importedAccounts.count

        return VStack(spacing: 6) {
            statusRow(label: "STATUS", value: historyStore.isBackedUp ? "BACKED UP" : "NOT BACKED UP")
            statusRow(label: "WALLETS", value: "\(walletCount) HD" + (accountCount > 0 ? " + \(accountCount) IMPORTED" : ""))
            if let lastExport = historyStore.lastExportDate {
                statusRow(label: "LAST EXPORT", value: relativeDate(lastExport))
            }
            if let lastVerified = historyStore.lastVerifiedDate {
                statusRow(label: "LAST VERIFIED", value: relativeDate(lastVerified))
            }
            if !historyStore.isBackedUp {
                statusRow(label: "ACTION NEEDED", value: "EXPORT A BACKUP")
            }
        }
        .padding(16)
        .background(bkCardBg)
    }

    private func statusRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.30))
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))
        }
    }

    private var historyList: some View {
        Group {
            if historyStore.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.10))
                    Text("No backup activity recorded")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.18))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 2) {
                    ForEach(historyStore.entries.prefix(10)) { entry in
                        historyRow(entry)
                    }
                }
                .background(bkCardBg)
            }
        }
    }

    private func historyRow(_ entry: BackupHistoryEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.icon)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.30))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.actionLabel.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.3)
                    .foregroundColor(.white.opacity(0.45))
                Text(entry.detail)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.22))
            }

            Spacer()

            Text(relativeDate(entry.date))
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.white.opacity(0.18))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var reminderCard: some View {
        VStack(spacing: 10) {
            Text("REMIND ME TO VERIFY")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.30))

            HStack(spacing: 6) {
                ForEach([1, 3, 6, 0], id: \.self) { months in
                    reminderButton(months)
                }
            }
        }
        .padding(16)
        .background(bkCardBg)
    }

    private func reminderButton(_ months: Int) -> some View {
        let selected = historyStore.reminderMonths == months
        let label = months == 0 ? "NEVER" : "\(months)M"
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                historyStore.reminderMonths = months
            }
        } label: {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(selected ? 0.70 : 0.25))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white.opacity(selected ? 0.08 : 0.02))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(selected ? 0.15 : 0.04)))
                )
        }
        .buttonStyle(.plain)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – PHRASE
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var phraseContent: some View {
        VStack(spacing: 20) {
            if !acknowledgedWarning {
                warningGate
            } else if !phraseRevealed {
                holdToRevealSection
            } else {
                revealedPhraseSection
            }
        }
    }

    private var warningGate: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                    .frame(width: 100, height: 100)
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white.opacity(0.04), lineWidth: 1)
                    .frame(width: 70, height: 70)
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.20))
            }
            .padding(.top, 10)

            Text("SENSITIVE INFORMATION")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.50))

            VStack(alignment: .leading, spacing: 8) {
                warningBullet("Anyone with this phrase can steal your funds")
                warningBullet("Never share it over email, chat, or phone")
                warningBullet("Write it on paper and store it physically")
                warningBullet("Hawala will never ask for your phrase")
            }
            .padding(.horizontal, 8)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    acknowledgedWarning = true
                }
            } label: {
                Text("I UNDERSTAND THE RISKS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.white.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.10)))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func warningBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(.white.opacity(0.15))
                .frame(width: 5, height: 5)
                .padding(.top, 5)
            Text(text)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
        }
    }

    private var holdToRevealSection: some View {
        VStack(spacing: 24) {
            Text("Hold the button to reveal your recovery phrase.\nThis requires biometric authentication.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.30))
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            if let error = phraseError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                    Text(error)
                        .font(.system(size: 9, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.40))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
            }

            holdRevealButton

            Text("Press and hold for 2 seconds")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.white.opacity(0.18))
        }
        .padding(.top, 30)
    }

    private var holdRevealButton: some View {
        ZStack {
            // Outer progress ring
            Circle()
                .trim(from: 0, to: revealProgress)
                .stroke(.white.opacity(0.20), lineWidth: 3)
                .frame(width: 80, height: 80)
                .rotationEffect(.degrees(-90))

            Circle()
                .fill(.white.opacity(isFetchingPhrase ? 0.06 : 0.04))
                .frame(width: 70, height: 70)
                .overlay(
                    Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )

            if isFetchingPhrase {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(.white.opacity(0.3))
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.30))
                    Text("HOLD")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.white.opacity(0.25))
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in startHoldReveal() }
                .onEnded { _ in cancelHoldReveal() }
        )
    }

    private var revealedPhraseSection: some View {
        VStack(spacing: 16) {
            autoHideBar
            phraseGrid
            phraseActions
        }
    }

    private var autoHideBar: some View {
        VStack(spacing: 4) {
            HStack {
                Text("AUTO-HIDE IN")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.25))
                Text("\(autoHideTimer)s")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
            }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 1)
                    .fill(.white.opacity(0.06))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(.white.opacity(0.20))
                            .frame(width: geo.size.width * CGFloat(autoHideTimer) / 60.0)
                    }
            }
            .frame(height: 2)
        }
    }

    private var phraseGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ], spacing: 8) {
            ForEach(Array(realPhrase.enumerated()), id: \.offset) { index, word in
                phraseWordTile(index: index, word: word)
            }
        }
    }

    private func phraseWordTile(index: Int, word: String) -> some View {
        let visible = index < revealedWordCount
        return HStack(spacing: 6) {
            Text("\(index + 1)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.20))
                .frame(width: 20, alignment: .trailing)
            Text(visible ? word : String(repeating: "\u{2022}", count: 5))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(visible ? 0.60 : 0.10))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(visible ? 0.04 : 0.02))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(visible ? 0.06 : 0.02)))
        )
        .animation(.easeOut(duration: 0.2).delay(Double(index) * 0.05), value: visible)
    }

    private var phraseActions: some View {
        HStack(spacing: 10) {
            Button { copyPhrase() } label: {
                HStack(spacing: 5) {
                    Image(systemName: hasCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9))
                    Text(hasCopied ? "COPIED" : "COPY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                }
                .foregroundColor(.white.opacity(hasCopied ? 0.50 : 0.35))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
            }
            .buttonStyle(.plain)

            Button { hidePhrase() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 9))
                    Text("HIDE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                }
                .foregroundColor(.white.opacity(0.35))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
            }
            .buttonStyle(.plain)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – VERIFY
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var verifyContent: some View {
        VStack(spacing: 20) {
            switch verifyStage {
            case .notStarted: verifyIntro
            case .inProgress: verifyQuestionView
            case .complete: verifyResultView
            }
        }
    }

    private var verifyIntro: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.06), lineWidth: 2)
                    .frame(width: 80, height: 80)
                Circle()
                    .strokeBorder(.white.opacity(0.04), lineWidth: 1.5)
                    .frame(width: 56, height: 56)
                Image(systemName: "shield.checkered")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.20))
            }
            .padding(.top, 10)

            Text("SECURITY CHECKPOINT")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.50))

            Text("Verify that you have correctly backed up your recovery phrase by answering 4 questions about your seed words.\n\nRequires biometric authentication.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.28))
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Button {
                startVerification()
            } label: {
                Text("BEGIN VERIFICATION")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.white.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.10)))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var verifyQuestionView: some View {
        VStack(spacing: 20) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    verifyProgressDot(index: i)
                }
            }

            if verifyCurrentQ < verifyQuestions.count {
                let (wordIndex, _) = verifyQuestions[verifyCurrentQ]
                VStack(spacing: 16) {
                    Text("WHAT IS WORD #\(wordIndex + 1)?")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.white.opacity(0.50))

                    TextField("Type the word...", text: $verifyInput)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.60))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.08)))
                        )

                    Button {
                        submitVerifyAnswer()
                    } label: {
                        Text("CONFIRM")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(.white.opacity(verifyInput.isEmpty ? 0.18 : 0.55))
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
    }

    private func verifyProgressDot(index: Int) -> some View {
        ZStack {
            if index < verifyResults.count {
                Circle()
                    .fill(.white.opacity(verifyResults[index] ? 0.35 : 0.08))
                    .frame(width: 10, height: 10)
                    .overlay {
                        if verifyResults[index] {
                            Image(systemName: "checkmark")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundColor(.white.opacity(0.50))
                        } else {
                            Image(systemName: "xmark")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundColor(.white.opacity(0.25))
                        }
                    }
            } else if index == verifyCurrentQ {
                Circle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 10, height: 10)
            } else {
                Circle()
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    .frame(width: 10, height: 10)
            }
        }
    }

    private var verifyResultView: some View {
        let correct = verifyResults.filter { $0 }.count
        let total = verifyResults.count
        let allCorrect = correct == total

        return VStack(spacing: 20) {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.08), lineWidth: 2)
                    .frame(width: 70, height: 70)
                if allCorrect {
                    Circle()
                        .fill(.white.opacity(0.06))
                        .frame(width: 70, height: 70)
                }
                Image(systemName: allCorrect ? "checkmark.shield.fill" : "shield.slash")
                    .font(.system(size: 26))
                    .foregroundColor(.white.opacity(allCorrect ? 0.45 : 0.18))
            }

            Text(allCorrect ? "VERIFICATION PASSED" : "VERIFICATION FAILED")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(allCorrect ? 0.55 : 0.35))

            Text("\(correct) / \(total) CORRECT")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.30))

            if allCorrect {
                Text("Your recovery phrase backup is verified and secure.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                    .multilineTextAlignment(.center)
            } else {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        verifyStage = .notStarted
                        verifyResults = []
                        verifyCurrentQ = 0
                        verifyInput = ""
                        verifyPhrase = []
                    }
                } label: {
                    Text("TRY AGAIN")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – BACKUP (Export + Import)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var backupContent: some View {
        VStack(spacing: 16) {
            // Segmented picker
            HStack(spacing: 0) {
                backupModeButton("EXPORT", mode: .export)
                backupModeButton("IMPORT", mode: .import_)
            }
            .background(bkCardBg)

            switch backupMode {
            case .export: exportSection
            case .import_: importSection
            }
        }
    }

    private func backupModeButton(_ label: String, mode: BackupMode) -> some View {
        let selected: Bool
        switch (backupMode, mode) {
        case (.export, .export), (.import_, .import_): selected = true
        default: selected = false
        }
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                backupMode = mode
            }
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(selected ? 0.70 : 0.25))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(selected ? 0.06 : 0.0))
                )
        }
        .buttonStyle(.plain)
    }

    // ── Export ──

    private var exportSection: some View {
        VStack(spacing: 16) {
            if exportComplete {
                exportCompleteView
            } else {
                exportForm
            }
        }
    }

    private var exportForm: some View {
        VStack(spacing: 14) {
            bkSectionLabel("ENCRYPTED EXPORT")

            Text("Create a password-encrypted .hawala backup file.\nThis contains your seed phrase and wallet data.")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            VStack(spacing: 8) {
                SecureField("Password (8+ characters)", text: $exportPassword)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.60))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.06)))
                    )

                passwordStrengthBar

                SecureField("Confirm password", text: $exportConfirmPassword)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.60))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(
                                !exportConfirmPassword.isEmpty && exportPassword != exportConfirmPassword ? 0.12 : 0.06
                            )))
                    )

                if !exportConfirmPassword.isEmpty && exportPassword != exportConfirmPassword {
                    Text("Passwords do not match")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.30))
                }
            }

            if let error = exportError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 9))
                    Text(error)
                        .font(.system(size: 9, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.40))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
            }

            Button {
                beginExport()
            } label: {
                HStack(spacing: 6) {
                    if exportInProgress {
                        ProgressView()
                            .scaleEffect(0.5)
                            .tint(.white.opacity(0.3))
                    } else {
                        Image(systemName: "lock.doc")
                            .font(.system(size: 10))
                    }
                    Text(exportInProgress ? "ENCRYPTING..." : "CREATE ENCRYPTED BACKUP")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                }
                .foregroundColor(.white.opacity(canExport ? 0.55 : 0.18))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(canExport ? 0.06 : 0.02))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canExport || exportInProgress)

            // Cloud warning
            HStack(spacing: 8) {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.15))
                Text("Do not store backups in cloud services.\nUse a USB drive or offline storage.")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.18))
                    .lineSpacing(2)
            }
            .padding(12)
            .background(bkCardBg)
        }
    }

    private var passwordStrengthBar: some View {
        let strength = passwordStrength(exportPassword)
        return HStack(spacing: 8) {
            Text("STRENGTH")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.20))

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.04))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white.opacity(strengthOpacity(strength)))
                            .frame(width: geo.size.width * strength)
                    }
            }
            .frame(height: 3)

            Text(strengthLabel(strength))
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(strengthOpacity(strength)))
                .frame(width: 60, alignment: .trailing)
        }
    }

    private var exportCompleteView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 60, height: 60)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.white.opacity(0.40))
            }

            Text("BACKUP CREATED")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.50))

            Text("Your encrypted backup has been saved.\nStore it somewhere safe and offline.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    exportComplete = false
                    exportPassword = ""
                    exportConfirmPassword = ""
                    exportError = nil
                }
            } label: {
                Text("DONE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05)))
            }
            .buttonStyle(.plain)
        }
    }

    // ── Import ──

    private var importSection: some View {
        VStack(spacing: 16) {
            if let result = importResult {
                importResultView(result)
            } else if importPreview != nil {
                importPreviewView
            } else if importFileData != nil {
                importPasswordView
            } else {
                importSelectView
            }
        }
    }

    private var importSelectView: some View {
        VStack(spacing: 16) {
            bkSectionLabel("RESTORE FROM BACKUP")

            Text("Select a .hawala backup file to restore\nyour wallets from an encrypted backup.")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Button {
                selectImportFile()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 11))
                    Text("SELECT BACKUP FILE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                }
                .foregroundColor(.white.opacity(0.50))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.10)))
                )
            }
            .buttonStyle(.plain)

            if let error = importError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 9))
                    Text(error)
                        .font(.system(size: 9, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.35))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
            }
        }
    }

    private var importPasswordView: some View {
        VStack(spacing: 16) {
            bkSectionLabel("ENTER BACKUP PASSWORD")

            if let name = importFileName {
                HStack(spacing: 6) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.25))
                    Text(name)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.40))
                }
            }

            SecureField("Backup password", text: $importPassword)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.60))
                .textFieldStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.06)))
                )

            if let error = importError {
                Text(error)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }

            HStack(spacing: 8) {
                Button { resetImport() } label: {
                    Text("CANCEL")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(0.30))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03)))
                }
                .buttonStyle(.plain)

                Button { decryptImportFile() } label: {
                    Text("DECRYPT")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(importPassword.isEmpty ? 0.15 : 0.50))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(importPassword.isEmpty ? 0.02 : 0.06)))
                }
                .buttonStyle(.plain)
                .disabled(importPassword.isEmpty)
            }
        }
    }

    private var importPreviewView: some View {
        VStack(spacing: 16) {
            guard let preview = importPreview else { return AnyView(EmptyView()) }

            return AnyView(VStack(spacing: 16) {
                bkSectionLabel("BACKUP CONTENTS")

                VStack(spacing: 6) {
                    importPreviewRow(label: "HD WALLETS", value: "\(preview.hdWallets.count)")
                    importPreviewRow(label: "IMPORTED ACCOUNTS", value: "\(preview.importedAccounts.count)")
                    importPreviewRow(label: "CREATED", value: relativeDate(preview.createdAt))
                    importPreviewRow(label: "APP VERSION", value: preview.appVersion)
                }
                .padding(14)
                .background(bkCardBg)

                if !preview.hdWallets.isEmpty {
                    VStack(spacing: 2) {
                        ForEach(preview.hdWallets, id: \.id) { wallet in
                            HStack {
                                Text(wallet.name.uppercased())
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.40))
                                Spacer()
                                Text("\(wallet.accounts.count) ACCOUNTS")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.22))
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                        }
                    }
                    .background(bkCardBg)
                }

                HStack(spacing: 8) {
                    Button { resetImport() } label: {
                        Text("CANCEL")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundColor(.white.opacity(0.30))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03)))
                    }
                    .buttonStyle(.plain)

                    Button { performImport() } label: {
                        HStack(spacing: 5) {
                            if importInProgress {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .tint(.white.opacity(0.3))
                            }
                            Text(importInProgress ? "RESTORING..." : "RESTORE WALLETS")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(0.5)
                        }
                        .foregroundColor(.white.opacity(importInProgress ? 0.20 : 0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(importInProgress ? 0.02 : 0.06)))
                    }
                    .buttonStyle(.plain)
                    .disabled(importInProgress)
                }
            })
        }
    }

    private func importPreviewRow(label: String, value: String) -> some View {
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

    private func importResultView(_ result: ImportResult) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.white.opacity(result.hasErrors ? 0.03 : 0.06))
                    .frame(width: 60, height: 60)
                Image(systemName: result.hasErrors ? "exclamationmark.triangle" : "checkmark.seal.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.white.opacity(result.hasErrors ? 0.25 : 0.40))
            }

            Text(result.hasErrors ? "IMPORT COMPLETED WITH ERRORS" : "IMPORT SUCCESSFUL")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.50))

            VStack(spacing: 4) {
                if result.imported > 0 {
                    Text("\(result.imported) wallet(s) imported")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                }
                if result.skipped > 0 {
                    Text("\(result.skipped) skipped (already exist)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                }
                if result.hasErrors {
                    ForEach(result.errors, id: \.self) { err in
                        Text(err)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.white.opacity(0.25))
                    }
                }
            }

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    resetImport()
                }
            } label: {
                Text("DONE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05)))
            }
            .buttonStyle(.plain)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – GUIDE
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var guideContent: some View {
        VStack(spacing: 20) {
            bkSectionLabel("BEST PRACTICES")
            bestPracticesCard

            bkSectionLabel("METAL BACKUP")
            metalBackupCard

            bkSectionLabel("WHAT TO AVOID")
            avoidCard
        }
    }

    private var bestPracticesCard: some View {
        VStack(spacing: 2) {
            guideRow(icon: "pencil.and.outline", title: "WRITE IT DOWN", detail: "Write your 12/24 word phrase on paper. Never type it into a computer or phone.")
            guideRow(icon: "doc.on.doc", title: "MAKE COPIES", detail: "Keep 2-3 copies in different physical locations that you control.")
            guideRow(icon: "clock.arrow.2.circlepath", title: "VERIFY REGULARLY", detail: "Test your backup every few months. Use the verification tab to confirm.")
            guideRow(icon: "lock.doc", title: "ENCRYPTED EXPORT", detail: "Use the backup tab to create an AES-256 encrypted file for digital storage.")
            guideRow(icon: "lock.square.stack", title: "SEPARATE STORAGE", detail: "Never store your backup password with your seed phrase backup.")
        }
        .background(bkCardBg)
    }

    private var metalBackupCard: some View {
        VStack(spacing: 2) {
            guideRow(icon: "hammer", title: "STEEL PLATES", detail: "Stamp seed words into stainless steel plates. Survives fire and flood.")
            guideRow(icon: "flame.fill", title: "FIRE RESISTANT", detail: "Metal backups withstand temperatures that would destroy paper.")
            guideRow(icon: "drop.fill", title: "WATER PROOF", detail: "Steel plates are unaffected by water damage unlike paper or electronics.")
        }
        .background(bkCardBg)
    }

    private var avoidCard: some View {
        VStack(spacing: 2) {
            avoidRow("Screenshots or photos of your seed phrase")
            avoidRow("Storing in cloud notes, email, or messaging apps")
            avoidRow("Sharing with anyone, even people claiming to be support")
            avoidRow("Typing into websites or unknown applications")
            avoidRow("Keeping only a single copy in one location")
        }
        .background(bkCardBg)
    }

    private func guideRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
                .frame(width: 24, height: 24)
                .background(Circle().fill(.white.opacity(0.04)))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.45))
                Text(detail)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                    .lineSpacing(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func avoidRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white.opacity(0.18))
                .frame(width: 16)
            Text(text)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.30))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Shared Components
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func bkSectionLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.35))
            Spacer()
        }
    }

    private var bkCardBg: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.white.opacity(0.03))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.04)))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Actions & Handlers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    // ── Lifecycle ──

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

    // ── Phrase: hold-to-reveal with biometric ──

    private func startHoldReveal() {
        guard !isHoldingReveal, !isFetchingPhrase else { return }
        isHoldingReveal = true
        phraseError = nil
        withAnimation(.linear(duration: 2)) { revealProgress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
            guard isHoldingReveal else { return }
            fetchRealPhrase()
        }
    }

    private func cancelHoldReveal() {
        guard isHoldingReveal else { return }
        isHoldingReveal = false
        if !phraseRevealed {
            withAnimation(.easeOut(duration: 0.2)) { revealProgress = 0 }
        }
    }

    private func fetchRealPhrase() {
        isFetchingPhrase = true
        Task { @MainActor in
            let authResult = await BiometricAuthHelper.authenticate(reason: "Authenticate to view recovery phrase")
            switch authResult {
            case .success:
                do {
                    guard let wallet = WalletManager.shared.activeHDWallet ?? WalletManager.shared.hdWallets.first else {
                        phraseError = "No wallet found"
                        isFetchingPhrase = false
                        isHoldingReveal = false
                        withAnimation(.easeOut(duration: 0.2)) { revealProgress = 0 }
                        return
                    }
                    let phrase = try await WalletManager.shared.getSeedPhrase(for: wallet.id)
                    realPhrase = phrase.components(separatedBy: " ")
                    phraseRevealed = true
                    isFetchingPhrase = false
                    historyStore.recordEvent(.phraseViewed, detail: "Recovery phrase viewed")
                    startWordMaterialization()
                    startAutoHideCountdown()
                } catch {
                    phraseError = "Failed to retrieve phrase: \(error.localizedDescription)"
                    isFetchingPhrase = false
                    isHoldingReveal = false
                    withAnimation(.easeOut(duration: 0.2)) { revealProgress = 0 }
                }
            case .cancelled:
                isFetchingPhrase = false
                isHoldingReveal = false
                withAnimation(.easeOut(duration: 0.2)) { revealProgress = 0 }
            case .failed(let msg):
                phraseError = msg
                isFetchingPhrase = false
                isHoldingReveal = false
                withAnimation(.easeOut(duration: 0.2)) { revealProgress = 0 }
            case .notAvailable:
                // No biometrics — proceed anyway
                do {
                    guard let wallet = WalletManager.shared.activeHDWallet ?? WalletManager.shared.hdWallets.first else {
                        phraseError = "No wallet found"
                        isFetchingPhrase = false
                        isHoldingReveal = false
                        return
                    }
                    let phrase = try await WalletManager.shared.getSeedPhrase(for: wallet.id)
                    realPhrase = phrase.components(separatedBy: " ")
                    phraseRevealed = true
                    isFetchingPhrase = false
                    historyStore.recordEvent(.phraseViewed, detail: "Recovery phrase viewed")
                    startWordMaterialization()
                    startAutoHideCountdown()
                } catch {
                    phraseError = "Failed to retrieve phrase"
                    isFetchingPhrase = false
                    isHoldingReveal = false
                }
            }
        }
    }

    private func startWordMaterialization() {
        revealedWordCount = 0
        for i in 0..<realPhrase.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.12) {
                withAnimation(.easeOut(duration: 0.15)) {
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
        guard autoHideActive, autoHideTimer > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            guard autoHideActive else { return }
            autoHideTimer -= 1
            if autoHideTimer <= 0 {
                hidePhrase()
            } else {
                tickAutoHide()
            }
        }
    }

    private func hidePhrase() {
        autoHideActive = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            phraseRevealed = false
            revealProgress = 0
            revealedWordCount = 0
            hasCopied = false
            isHoldingReveal = false
        }
        // Clear from memory
        realPhrase = []
    }

    private func copyPhrase() {
        guard !realPhrase.isEmpty else { return }
        let joined = realPhrase.joined(separator: " ")
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(joined, forType: .string)
        #endif
        hasCopied = true
        // Auto-clear pasteboard after 60 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            #if os(macOS)
            if NSPasteboard.general.string(forType: .string) == joined {
                NSPasteboard.general.clearContents()
            }
            #endif
        }
    }

    // ── Verification ──

    private func startVerification() {
        Task { @MainActor in
            let authResult = await BiometricAuthHelper.authenticate(reason: "Authenticate to verify backup")
            switch authResult {
            case .success, .notAvailable:
                do {
                    guard let wallet = WalletManager.shared.activeHDWallet ?? WalletManager.shared.hdWallets.first else { return }
                    let phrase = try await WalletManager.shared.getSeedPhrase(for: wallet.id)
                    verifyPhrase = phrase.components(separatedBy: " ")
                    let indices = Array(verifyPhrase.indices).shuffled().prefix(4)
                    verifyQuestions = indices.map { ($0, verifyPhrase[$0]) }
                    verifyResults = []
                    verifyCurrentQ = 0
                    verifyInput = ""
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        verifyStage = .inProgress
                    }
                } catch {
                    // Could not retrieve phrase
                }
            case .cancelled, .failed:
                break
            }
        }
    }

    private func submitVerifyAnswer() {
        guard verifyCurrentQ < verifyQuestions.count else { return }
        let (_, correct) = verifyQuestions[verifyCurrentQ]
        let isCorrect = verifyInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == correct.lowercased()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            verifyResults.append(isCorrect)
            verifyInput = ""
            verifyCurrentQ += 1
        }

        if verifyCurrentQ >= verifyQuestions.count {
            let allCorrect = verifyResults.allSatisfy { $0 }
            if allCorrect {
                historyStore.recordEvent(.verificationPassed, detail: "4/4 correct")
            } else {
                let correct = verifyResults.filter { $0 }.count
                historyStore.recordEvent(.verificationFailed, detail: "\(correct)/4 correct")
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                verifyStage = .complete
            }
            // Clear sensitive data
            verifyPhrase = []
        }
    }

    // ── Export ──

    private var canExport: Bool {
        exportPassword.count >= 8 && exportPassword == exportConfirmPassword && !exportInProgress
    }

    private func beginExport() {
        guard canExport else { return }
        exportInProgress = true
        exportError = nil

        Task { @MainActor in
            do {
                let data = try await BackupManager.shared.exportBackup(
                    password: exportPassword,
                    walletManager: WalletManager.shared
                )

                // Present NSSavePanel
                #if canImport(AppKit)
                let panel = NSSavePanel()
                var contentTypes: [UTType] = [.json]
                let customTypes = ["hawala"].compactMap { UTType(filenameExtension: $0) }
                contentTypes.append(contentsOf: customTypes)
                panel.allowedContentTypes = contentTypes

                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                panel.nameFieldStringValue = "hawala-backup-\(formatter.string(from: Date())).hawala"
                panel.title = "Save Encrypted Hawala Backup"
                panel.canCreateDirectories = true

                panel.begin { response in
                    if response == .OK, let url = panel.url {
                        do {
                            try data.write(to: url, options: [.atomic, .completeFileProtection])
                            self.exportInProgress = false
                            self.exportComplete = true
                            self.historyStore.recordEvent(.exportCreated, detail: url.lastPathComponent)
                        } catch {
                            self.exportInProgress = false
                            self.exportError = "Failed to write file: \(error.localizedDescription)"
                        }
                    } else {
                        self.exportInProgress = false
                    }
                }
                #endif
            } catch {
                exportInProgress = false
                exportError = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func passwordStrength(_ pw: String) -> CGFloat {
        guard !pw.isEmpty else { return 0 }
        var score: CGFloat = 0
        if pw.count >= 8 { score += 0.2 }
        if pw.count >= 12 { score += 0.15 }
        if pw.count >= 16 { score += 0.15 }
        if pw.rangeOfCharacter(from: .uppercaseLetters) != nil { score += 0.15 }
        if pw.rangeOfCharacter(from: .lowercaseLetters) != nil { score += 0.10 }
        if pw.rangeOfCharacter(from: .decimalDigits) != nil { score += 0.10 }
        if pw.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil { score += 0.15 }
        return min(1, score)
    }

    private func strengthLabel(_ s: CGFloat) -> String {
        if s >= 0.8 { return "STRONG" }
        if s >= 0.5 { return "MODERATE" }
        if s > 0 { return "WEAK" }
        return ""
    }

    private func strengthOpacity(_ s: CGFloat) -> Double {
        if s >= 0.8 { return 0.40 }
        if s >= 0.5 { return 0.25 }
        if s > 0 { return 0.15 }
        return 0.05
    }

    // ── Import ──

    private func selectImportFile() {
        importError = nil
        #if canImport(AppKit)
        BackupService.shared.beginEncryptedImport { data in
            if let data = data {
                self.importFileData = data
                // Try to get filename from pasteboard or just show generic
                self.importFileName = "backup.hawala"
            }
        }
        #endif
    }

    private func decryptImportFile() {
        guard let data = importFileData, !importPassword.isEmpty else { return }
        importError = nil

        do {
            let contents = try BackupManager.shared.parseBackup(data: data, password: importPassword)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                importPreview = contents
            }
        } catch {
            importError = "Wrong password or corrupted file"
        }
    }

    private func performImport() {
        guard let contents = importPreview else { return }
        importInProgress = true

        Task { @MainActor in
            do {
                let result = try await BackupManager.shared.importBackup(
                    contents: contents,
                    walletManager: WalletManager.shared
                )
                importInProgress = false
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    importResult = result
                }
                historyStore.recordEvent(.importCompleted, detail: result.summary)
            } catch {
                importInProgress = false
                importError = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    private func resetImport() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            importFileData = nil
            importFileName = nil
            importPassword = ""
            importPreview = nil
            importResult = nil
            importError = nil
            importInProgress = false
        }
    }

    // ── Helpers ──

    private func relativeDate(_ date: Date) -> String {
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
}
