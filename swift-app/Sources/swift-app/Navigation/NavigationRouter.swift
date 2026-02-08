// NavigationRouter.swift
// Centralized navigation state management (ROADMAP-03)

import SwiftUI
import Combine

// MARK: - Navigation Destination
/// All possible navigation destinations in the app
enum NavigationDestination: Hashable, Equatable {
    // Core screens
    case portfolio
    case activity
    case discover
    
    // Actions
    case send(chainId: String? = nil)
    case receive(chainId: String? = nil)
    case swap(fromChain: String? = nil, toChain: String? = nil)
    
    // Detail screens
    case assetDetail(chainId: String)
    case transactionDetail(txId: String, chainId: String)
    
    // Settings & Security
    case settings
    case securitySettings
    case backupVerification
    
    // Connections
    case walletConnect
    case hardwareWallet
    
    // Advanced
    case staking
    case contacts
    case batchTransaction
    case priceAlerts
    
    var title: String {
        switch self {
        case .portfolio: return "Portfolio"
        case .activity: return "Activity"
        case .discover: return "Discover"
        case .send: return "Send"
        case .receive: return "Receive"
        case .swap: return "Swap"
        case .assetDetail: return "Asset"
        case .transactionDetail: return "Transaction"
        case .settings: return "Settings"
        case .securitySettings: return "Security"
        case .backupVerification: return "Verify Backup"
        case .walletConnect: return "WalletConnect"
        case .hardwareWallet: return "Hardware Wallet"
        case .staking: return "Staking"
        case .contacts: return "Contacts"
        case .batchTransaction: return "Batch Send"
        case .priceAlerts: return "Price Alerts"
        }
    }
}

// MARK: - Navigation Router
/// Centralized navigation state manager for the app
@MainActor
final class NavigationRouter: ObservableObject {
    static let shared = NavigationRouter()
    
    // MARK: - Published State
    
    /// Current navigation path (for NavigationStack)
    @Published var path: [NavigationDestination] = []
    
    /// Currently presented sheet
    @Published var presentedSheet: NavigationDestination?
    
    /// Currently presented alert
    @Published var presentedAlert: AlertInfo?
    
    /// Deep link being processed
    @Published private(set) var pendingDeepLink: URL?
    
    /// Whether a transaction is in progress (blocks some navigation)
    @Published var isTransactionInProgress: Bool = false
    
    // MARK: - Navigation Methods
    
    /// Navigate to a destination (push on stack)
    func navigate(to destination: NavigationDestination) {
        // Check if transaction in progress
        if isTransactionInProgress && !isNavigationAllowedDuringTransaction(destination) {
            presentedAlert = AlertInfo(
                title: "Transaction in Progress",
                message: "Please complete or cancel your current transaction first.",
                primaryAction: AlertAction(title: "OK", action: {})
            )
            return
        }
        
        path.append(destination)
        
        // Analytics
        NavigationAnalytics.trackNavigation(
            to: destination.title,
            method: .programmatic
        )
    }
    
    /// Go back one screen
    func goBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
        
        NavigationAnalytics.trackNavigation(
            to: path.last?.title ?? "Root",
            method: .back
        )
    }
    
    /// Go back to root
    func popToRoot() {
        path.removeAll()
        
        NavigationAnalytics.trackNavigation(
            to: "Root",
            method: .popToRoot
        )
    }
    
    /// Present a sheet
    func presentSheet(_ destination: NavigationDestination) {
        presentedSheet = destination
        
        NavigationAnalytics.trackNavigation(
            to: destination.title,
            method: .sheet
        )
    }
    
    /// Dismiss the current sheet
    func dismissSheet() {
        presentedSheet = nil
    }
    
    // MARK: - Deep Link Handling
    
    /// Handle an incoming deep link URL
    func handleDeepLink(_ url: URL) {
        pendingDeepLink = url
        
        // Parse the URL and navigate
        if let destination = parseDeepLink(url) {
            // If transaction in progress, show confirmation
            if isTransactionInProgress {
                presentedAlert = AlertInfo(
                    title: "Abandon Transaction?",
                    message: "You have an unsaved transaction. Opening this link will cancel it.",
                    primaryAction: AlertAction(title: "Continue", action: { [weak self] in
                        self?.isTransactionInProgress = false
                        self?.navigate(to: destination)
                        self?.pendingDeepLink = nil
                    }),
                    secondaryAction: AlertAction(title: "Cancel", action: { [weak self] in
                        self?.pendingDeepLink = nil
                    })
                )
            } else {
                navigate(to: destination)
                pendingDeepLink = nil
            }
        }
        
        NavigationAnalytics.trackDeepLink(
            url: url.absoluteString,
            success: pendingDeepLink == nil
        )
    }
    
    /// Parse a deep link URL into a navigation destination
    private func parseDeepLink(_ url: URL) -> NavigationDestination? {
        // hawala://send?chain=bitcoin&amount=0.001&address=bc1q...
        // hawala://tx/abc123?chain=bitcoin
        // hawala://settings
        
        guard url.scheme == "hawala" else { return nil }
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        
        let queryDict = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
            item.value.map { (item.name, $0) }
        })
        
        switch url.host {
        case "send":
            return .send(chainId: queryDict["chain"])
        case "receive":
            return .receive(chainId: queryDict["chain"])
        case "swap":
            return .swap(fromChain: queryDict["from"], toChain: queryDict["to"])
        case "settings":
            return .settings
        case "security":
            return .securitySettings
        case "tx":
            if let txId = pathComponents.first, let chain = queryDict["chain"] {
                return .transactionDetail(txId: txId, chainId: chain)
            }
            return nil
        case "asset":
            if let chainId = pathComponents.first ?? queryDict["chain"] {
                return .assetDetail(chainId: chainId)
            }
            return nil
        default:
            return nil
        }
    }
    
    // MARK: - Helpers
    
    private func isNavigationAllowedDuringTransaction(_ destination: NavigationDestination) -> Bool {
        // Only allow navigating to certain screens during a transaction
        switch destination {
        case .settings, .securitySettings:
            return true
        default:
            return false
        }
    }
    
    /// Check if currently at root
    var isAtRoot: Bool {
        path.isEmpty
    }
    
    /// Current depth in navigation stack
    var depth: Int {
        path.count
    }
}

// MARK: - Alert Info
struct AlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let primaryAction: AlertAction
    var secondaryAction: AlertAction?
}

struct AlertAction {
    let title: String
    let action: () -> Void
}

// MARK: - Navigation Analytics
/// Tracks navigation events for analytics
enum NavigationAnalytics {
    enum NavigationMethod: String {
        case tap
        case swipe
        case keyboard
        case programmatic
        case back
        case popToRoot
        case sheet
        case deepLink
    }
    
    static func trackNavigation(to screen: String, method: NavigationMethod) {
        #if DEBUG
        print("[Navigation] \(method.rawValue) -> \(screen)")
        #endif
        
        Task { @MainActor in
            AnalyticsService.shared.track(AnalyticsService.EventName.navigationTransition, properties: [
                "to_screen": screen,
                "method": method.rawValue
            ])
        }
    }
    
    static func trackDeepLink(url: String, success: Bool) {
        #if DEBUG
        print("[DeepLink] \(url) - \(success ? "✅" : "❌")")
        #endif
        
        Task { @MainActor in
            AnalyticsService.shared.track(AnalyticsService.EventName.deepLinkOpened, properties: [
                "url": url,
                "success": success ? "true" : "false"
            ])
        }
    }
}

// MARK: - Navigation Commands Manager
/// Manages keyboard shortcuts for navigation (ROADMAP-03)
@MainActor
final class NavigationCommandsManager: ObservableObject {
    static let shared = NavigationCommandsManager()
    
    private let router = NavigationRouter.shared
    
    // Callback closures for actions that need ContentView state
    var onOpenSettings: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onNewTransaction: (() -> Void)?
    var onShowHelp: (() -> Void)?
    var onReceive: (() -> Void)?
    var onToggleHistory: (() -> Void)?
    
    /// Handle ⌘, (Settings)
    func openSettings() {
        onOpenSettings?()
    }
    
    /// Handle ⌘R (Refresh)
    func refresh() {
        onRefresh?()
    }
    
    /// Handle ⌘N (New Transaction / Send)
    func newTransaction() {
        onNewTransaction?()
    }
    
    /// Handle ⌘? (Show Help/Shortcuts)
    func showHelp() {
        onShowHelp?()
    }
    
    /// Handle ⌘⇧R (Receive)
    func receive() {
        onReceive?()
    }
    
    /// Handle ⌘H (Toggle History)
    func toggleHistory() {
        onToggleHistory?()
    }
}

// MARK: - Keyboard Shortcuts Help View
struct KeyboardShortcutsHelpView: View {
    @Environment(\.dismiss) private var dismiss
    
    private let shortcuts: [(category: String, items: [(String, String)])] = [
        ("Navigation", [
            ("⌘,", "Open Settings"),
            ("⌘R", "Refresh Data"),
            ("⌘H", "Toggle History"),
            ("⌘W", "Close Window"),
            ("⌘M", "Minimize"),
        ]),
        ("Transactions", [
            ("⌘N", "New Send"),
            ("⌘⇧R", "Receive"),
            ("⌘⇧S", "Swap"),
        ]),
        ("Security", [
            ("⌘L", "Lock Wallet"),
            ("⌘⇧B", "Backup Recovery Phrase"),
        ]),
        ("General", [
            ("⌘?", "Show Shortcuts"),
            ("⌘Q", "Quit Hawala"),
            ("⌘C", "Copy Selected"),
            ("⌘V", "Paste"),
        ])
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.custom("ClashGrotesk-Bold", size: 20))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Shortcuts list
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(shortcuts, id: \.category) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(section.category)
                                .font(.custom("ClashGrotesk-Semibold", size: 14))
                                .foregroundColor(.white.opacity(0.5))
                                .textCase(.uppercase)
                            
                            ForEach(section.items, id: \.0) { shortcut, description in
                                HStack {
                                    Text(shortcut)
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(6)
                                    
                                    Text(description)
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundColor(.white.opacity(0.8))
                                    
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            
            // Footer hint
            Text("Press ⌘? anytime to show this sheet")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white.opacity(0.4))
                .padding(.bottom, 16)
        }
        .frame(width: 400, height: 500)
        .background(Color(hex: "#1A1A1A"))
        .cornerRadius(16)
    }
}

// MARK: - Preview
#if DEBUG
struct KeyboardShortcutsHelpView_Previews: PreviewProvider {
    static var previews: some View {
        KeyboardShortcutsHelpView()
            .preferredColorScheme(.dark)
    }
}
#endif
