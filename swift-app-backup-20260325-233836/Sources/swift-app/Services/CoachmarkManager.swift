import SwiftUI

// MARK: - Coachmark Manager
/// Manages first-launch coachmarks and feature spotlights
/// Tracks which tips have been shown and when to display them

@MainActor
final class CoachmarkManager: ObservableObject {
    static let shared = CoachmarkManager()
    
    // MARK: - Coachmark Types
    
    enum CoachmarkID: String, CaseIterable {
        // Onboarding coachmarks
        case welcomeSwipe = "welcome_swipe"
        case passcodeEntry = "passcode_entry"
        case seedPhraseImportance = "seed_phrase_importance"
        case backupReminder = "backup_reminder"
        
        // Main app coachmarks
        case portfolioTotal = "portfolio_total"
        case portfolioSwipe = "portfolio_swipe"
        case quickSend = "quick_send"
        case assetDetail = "asset_detail"
        case settingsAccess = "settings_access"
        case receiveAddress = "receive_address"
        case transactionHistory = "transaction_history"
        case refreshGesture = "refresh_gesture"
        
        // Feature discovery
        case stakingIntro = "staking_intro"
        case dappBrowser = "dapp_browser"
        case multiWallet = "multi_wallet"
        case hardwareWallet = "hardware_wallet"
        case priceAlerts = "price_alerts"
        
        var title: String {
            switch self {
            case .welcomeSwipe: return "Welcome to Hawala"
            case .passcodeEntry: return "Secure Your Wallet"
            case .seedPhraseImportance: return "Your Recovery Phrase"
            case .backupReminder: return "Back Up Your Wallet"
            case .portfolioTotal: return "Your Portfolio"
            case .portfolioSwipe: return "Swipe to Explore"
            case .quickSend: return "Quick Send"
            case .assetDetail: return "Asset Details"
            case .settingsAccess: return "Settings & Security"
            case .receiveAddress: return "Receive Crypto"
            case .transactionHistory: return "Transaction History"
            case .refreshGesture: return "Pull to Refresh"
            case .stakingIntro: return "Earn Rewards"
            case .dappBrowser: return "Connect to dApps"
            case .multiWallet: return "Multiple Wallets"
            case .hardwareWallet: return "Hardware Wallet"
            case .priceAlerts: return "Price Alerts"
            }
        }
        
        var message: String {
            switch self {
            case .welcomeSwipe:
                return "Swipe left or right to navigate between screens, or use the tabs below."
            case .passcodeEntry:
                return "Create a 6-digit passcode to protect your wallet. You'll need this to access your funds."
            case .seedPhraseImportance:
                return "This phrase is the ONLY way to recover your wallet. Write it down and store it safely."
            case .backupReminder:
                return "We recommend backing up your recovery phrase to multiple secure locations."
            case .portfolioTotal:
                return "This shows your total portfolio value across all assets. Tap to refresh."
            case .portfolioSwipe:
                return "Swipe horizontally to see more assets, or tap an asset for details."
            case .quickSend:
                return "Tap the Send button or press ⌘S to quickly send crypto to any address."
            case .assetDetail:
                return "Tap any asset to see price charts, transaction history, and more options."
            case .settingsAccess:
                return "Access settings by clicking the gear icon or pressing ⌘,"
            case .receiveAddress:
                return "Tap Receive to show your wallet address and QR code for receiving crypto."
            case .transactionHistory:
                return "View your complete transaction history in the Activity tab."
            case .refreshGesture:
                return "Pull down to refresh balances, or press ⌘R."
            case .stakingIntro:
                return "Stake supported assets to earn passive rewards directly in your wallet."
            case .dappBrowser:
                return "Connect to decentralized apps securely with WalletConnect."
            case .multiWallet:
                return "Create multiple wallets to organize your assets by purpose."
            case .hardwareWallet:
                return "Connect a Ledger or Trezor for enhanced security."
            case .priceAlerts:
                return "Set price alerts to get notified when assets hit your target prices."
            }
        }
        
        var icon: String {
            switch self {
            case .welcomeSwipe: return "hand.draw"
            case .passcodeEntry: return "lock.fill"
            case .seedPhraseImportance: return "key.fill"
            case .backupReminder: return "externaldrive.fill"
            case .portfolioTotal: return "chart.pie.fill"
            case .portfolioSwipe: return "rectangle.stack"
            case .quickSend: return "paperplane.fill"
            case .assetDetail: return "chart.line.uptrend.xyaxis"
            case .settingsAccess: return "gearshape.fill"
            case .receiveAddress: return "qrcode"
            case .transactionHistory: return "clock.fill"
            case .refreshGesture: return "arrow.clockwise"
            case .stakingIntro: return "percent"
            case .dappBrowser: return "globe"
            case .multiWallet: return "wallet.pass.fill"
            case .hardwareWallet: return "cpu"
            case .priceAlerts: return "bell.fill"
            }
        }
    }
    
    // MARK: - State
    
    @Published private(set) var currentCoachmark: CoachmarkID?
    @Published private(set) var pendingCoachmarks: [CoachmarkID] = []
    
    private let seenKey = "hawala.coachmarks.seen"
    private var seenCoachmarks: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: seenKey)
        }
    }
    
    private init() {}
    
    // MARK: - Public API
    
    /// Check if a coachmark should be shown
    func shouldShow(_ id: CoachmarkID) -> Bool {
        !seenCoachmarks.contains(id.rawValue)
    }
    
    /// Mark a coachmark as seen
    func markSeen(_ id: CoachmarkID) {
        seenCoachmarks.insert(id.rawValue)
        if currentCoachmark == id {
            currentCoachmark = nil
            showNextPending()
        }
    }
    
    /// Show a coachmark if not yet seen
    func showIfNeeded(_ id: CoachmarkID) {
        guard shouldShow(id) else { return }
        
        if currentCoachmark == nil {
            currentCoachmark = id
        } else {
            // Queue for later
            if !pendingCoachmarks.contains(id) {
                pendingCoachmarks.append(id)
            }
        }
    }
    
    /// Queue a coachmark to show after current (if not seen)
    func queue(_ id: CoachmarkID) {
        guard shouldShow(id) else { return }
        
        if currentCoachmark == nil && pendingCoachmarks.isEmpty {
            // Show immediately
            currentCoachmark = id
        } else {
            // Add to queue
            if !pendingCoachmarks.contains(id) {
                pendingCoachmarks.append(id)
            }
        }
    }
    
    /// Dismiss current coachmark
    func dismiss() {
        if let current = currentCoachmark {
            markSeen(current)
        }
    }
    
    /// Skip all remaining coachmarks
    func skipAll() {
        CoachmarkID.allCases.forEach { seenCoachmarks.insert($0.rawValue) }
        currentCoachmark = nil
        pendingCoachmarks.removeAll()
    }
    
    /// Reset all coachmarks (for testing)
    func reset() {
        seenCoachmarks.removeAll()
        currentCoachmark = nil
        pendingCoachmarks.removeAll()
    }
    
    // MARK: - Private
    
    private func showNextPending() {
        guard let next = pendingCoachmarks.first else { return }
        pendingCoachmarks.removeFirst()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.currentCoachmark = next
        }
    }
}

// MARK: - Coachmark View

struct CoachmarkView: View {
    let id: CoachmarkManager.CoachmarkID
    let anchor: Anchor<CGRect>?
    let onDismiss: () -> Void
    
    @State private var isAnimating = false
    
    var body: some View {
        GeometryReader { geometry in
            if let anchor = anchor {
                let rect = geometry[anchor]
                coachmarkContent
                    .position(
                        x: rect.midX,
                        y: rect.maxY + 80
                    )
            } else {
                coachmarkContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                isAnimating = true
            }
        }
    }
    
    private var coachmarkContent: some View {
        VStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#5E17EB"), Color(hex: "#B341F9")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                
                Image(systemName: id.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            // Title
            Text(id.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            
            // Message
            Text(id.message)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            
            // Dismiss button
            Button(action: onDismiss) {
                Text("Got it")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .scaleEffect(isAnimating ? 1 : 0.8)
        .opacity(isAnimating ? 1 : 0)
    }
}

// MARK: - Spotlight Overlay

struct SpotlightOverlay: View {
    let spotlightRect: CGRect?
    let coachmarkID: CoachmarkManager.CoachmarkID
    let onDismiss: () -> Void
    
    @State private var isVisible = false
    
    var body: some View {
        ZStack {
            // Dimmed background with cutout
            if let rect = spotlightRect {
                SpotlightMask(spotlightRect: rect)
                    .fill(Color.black.opacity(0.7), style: FillStyle(eoFill: true))
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)
            } else {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)
            }
            
            // Coachmark
            CoachmarkView(
                id: coachmarkID,
                anchor: nil,
                onDismiss: onDismiss
            )
        }
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Spotlight Mask Shape

struct SpotlightMask: Shape {
    let spotlightRect: CGRect
    let cornerRadius: CGFloat = 12
    let padding: CGFloat = 8
    
    func path(in rect: CGRect) -> Path {
        // Create the outer rectangle
        var path = Path(rect)
        
        // Create spotlight cutout using even-odd fill rule
        let spotlight = spotlightRect.insetBy(dx: -padding, dy: -padding)
        path.addRoundedRect(in: spotlight, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        
        return path
    }
}

// MARK: - Coachmark Preference Key

struct CoachmarkAnchorKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [CoachmarkManager.CoachmarkID: Anchor<CGRect>] = [:]
    
    static func reduce(value: inout [CoachmarkManager.CoachmarkID: Anchor<CGRect>], nextValue: () -> [CoachmarkManager.CoachmarkID: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - View Extension

extension View {
    /// Mark this view as a coachmark anchor
    func coachmarkAnchor(_ id: CoachmarkManager.CoachmarkID) -> some View {
        anchorPreference(key: CoachmarkAnchorKey.self, value: .bounds) { anchor in
            [id: anchor]
        }
    }
    
    /// Show coachmark overlay when needed
    func coachmarkOverlay() -> some View {
        self.overlayPreferenceValue(CoachmarkAnchorKey.self) { anchors in
            if let currentID = CoachmarkManager.shared.currentCoachmark,
               let anchor = anchors[currentID] {
                GeometryReader { geometry in
                    let rect = geometry[anchor]
                    SpotlightOverlay(
                        spotlightRect: rect,
                        coachmarkID: currentID,
                        onDismiss: { CoachmarkManager.shared.dismiss() }
                    )
                }
            }
        }
    }
    
    /// Trigger coachmark when view appears
    func showCoachmarkOnAppear(_ id: CoachmarkManager.CoachmarkID, delay: Double = 1.0) -> some View {
        self.onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                CoachmarkManager.shared.showIfNeeded(id)
            }
        }
    }
}

// MARK: - Inline Tip View

struct InlineTipView: View {
    let id: CoachmarkManager.CoachmarkID
    @StateObject private var manager = CoachmarkManager.shared
    @State private var isVisible = true
    
    var body: some View {
        if manager.shouldShow(id) && isVisible {
            HStack(spacing: 12) {
                Image(systemName: id.icon)
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "#B341F9"))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(id.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(id.message)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(2)
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isVisible = false
                    }
                    manager.markSeen(id)
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(hex: "#B341F9").opacity(0.3), lineWidth: 1)
                    )
            )
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity.combined(with: .scale(scale: 0.95))
            ))
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CoachmarkPreview: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text("Main Content")
                    .foregroundColor(.white)
                
                Button("Show Coachmark") {
                    CoachmarkManager.shared.reset()
                    CoachmarkManager.shared.showIfNeeded(.welcomeSwipe)
                }
                .buttonStyle(.borderedProminent)
                .coachmarkAnchor(.welcomeSwipe)
                
                InlineTipView(id: .quickSend)
                    .padding(.horizontal)
            }
        }
        .coachmarkOverlay()
    }
}
#endif
