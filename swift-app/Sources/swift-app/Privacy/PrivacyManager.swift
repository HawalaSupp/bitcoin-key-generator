import SwiftUI
import Combine

/// Manages global privacy settings for the app
/// Controls balance hiding, screenshot prevention, and sensitive data redaction
@MainActor
public final class PrivacyManager: ObservableObject {
    
    // MARK: - Singleton
    public static let shared = PrivacyManager()
    
    // MARK: - Published Properties
    
    /// Master toggle for privacy mode
    @AppStorage("privacyModeEnabled") public var isPrivacyModeEnabled: Bool = false {
        didSet {
            objectWillChange.send()
            if isPrivacyModeEnabled {
                applyPrivacyRestrictions()
            } else {
                removePrivacyRestrictions()
            }
        }
    }
    
    /// Hide all balance displays (show "••••" instead)
    @AppStorage("hideBalances") public var hideBalances: Bool = true {
        didSet { objectWillChange.send() }
    }
    
    /// Attempt to prevent screenshots (macOS only, limited effectiveness)
    @AppStorage("disableScreenshots") public var disableScreenshots: Bool = true {
        didSet {
            objectWillChange.send()
            updateScreenshotPrevention()
        }
    }
    
    /// Stop fetching price data from external APIs
    @AppStorage("pausePriceFetching") public var pausePriceFetching: Bool = false {
        didSet { objectWillChange.send() }
    }
    
    /// Hide transaction history
    @AppStorage("hideTransactionHistory") public var hideTransactionHistory: Bool = false {
        didSet { objectWillChange.send() }
    }
    
    /// Blur addresses in UI
    @AppStorage("blurAddresses") public var blurAddresses: Bool = false {
        didSet { objectWillChange.send() }
    }
    
    /// Temporary reveal state (tap-to-reveal)
    @Published public var temporaryRevealActive: Bool = false
    
    /// Timer for auto-hiding after reveal
    private var revealTimer: Timer?
    
    /// Duration before auto-hiding revealed content (seconds)
    private let revealDuration: TimeInterval = 5.0
    
    // MARK: - Computed Properties
    
    /// Returns true if balances should be hidden right now
    public var shouldHideBalances: Bool {
        isPrivacyModeEnabled && hideBalances && !temporaryRevealActive
    }
    
    /// Returns true if addresses should be blurred
    public var shouldBlurAddresses: Bool {
        isPrivacyModeEnabled && blurAddresses && !temporaryRevealActive
    }
    
    /// Returns true if transaction history should be hidden
    public var shouldHideTransactions: Bool {
        isPrivacyModeEnabled && hideTransactionHistory && !temporaryRevealActive
    }
    
    /// Returns true if price fetching should be paused
    public var shouldPausePrices: Bool {
        isPrivacyModeEnabled && pausePriceFetching
    }
    
    // MARK: - Initialization
    
    private init() {
        // Apply initial state
        if isPrivacyModeEnabled {
            applyPrivacyRestrictions()
        }
    }
    
    // MARK: - Public Methods
    
    /// Toggle privacy mode on/off
    public func togglePrivacyMode() {
        isPrivacyModeEnabled.toggle()
        print("[Privacy] Privacy mode \(isPrivacyModeEnabled ? "enabled" : "disabled")")
    }
    
    /// Temporarily reveal hidden content
    /// Automatically hides again after `revealDuration` seconds
    public func temporaryReveal() {
        guard isPrivacyModeEnabled else { return }
        
        temporaryRevealActive = true
        print("[Privacy] Temporary reveal activated for \(revealDuration)s")
        
        // Cancel existing timer
        revealTimer?.invalidate()
        
        // Set new timer to hide again
        revealTimer = Timer.scheduledTimer(withTimeInterval: revealDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.temporaryRevealActive = false
                print("[Privacy] Temporary reveal expired")
            }
        }
    }
    
    /// Immediately end temporary reveal
    public func endTemporaryReveal() {
        revealTimer?.invalidate()
        revealTimer = nil
        temporaryRevealActive = false
    }
    
    /// Format a balance string respecting privacy settings
    public func formatBalance(_ value: Double, symbol: String) -> String {
        if shouldHideBalances {
            return "••••••"
        }
        return String(format: "%.8f %@", value, symbol)
    }
    
    /// Format a fiat value respecting privacy settings
    public func formatFiat(_ value: Double, currencySymbol: String = "$") -> String {
        if shouldHideBalances {
            return "\(currencySymbol)••••••"
        }
        return String(format: "%@%.2f", currencySymbol, value)
    }
    
    /// Redact an address for display
    public func redactAddress(_ address: String) -> String {
        if shouldBlurAddresses {
            // Show first 6 and last 4 characters
            if address.count > 12 {
                let prefix = String(address.prefix(6))
                let suffix = String(address.suffix(4))
                return "\(prefix)••••••\(suffix)"
            }
            return "••••••••••"
        }
        return address
    }
    
    // MARK: - Private Methods
    
    private func applyPrivacyRestrictions() {
        updateScreenshotPrevention()
        // Post notification for other parts of the app
        NotificationCenter.default.post(name: .privacyModeChanged, object: nil, userInfo: ["enabled": true])
    }
    
    private func removePrivacyRestrictions() {
        updateScreenshotPrevention()
        NotificationCenter.default.post(name: .privacyModeChanged, object: nil, userInfo: ["enabled": false])
    }
    
    private func updateScreenshotPrevention() {
        #if os(macOS)
        // On macOS, we can set sharingType on NSWindow
        // This needs to be called from the window controller
        NotificationCenter.default.post(name: .updateScreenshotPrevention, object: nil, userInfo: [
            "prevent": isPrivacyModeEnabled && disableScreenshots
        ])
        #endif
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let privacyModeChanged = Notification.Name("privacyModeChanged")
    static let updateScreenshotPrevention = Notification.Name("updateScreenshotPrevention")
}

// MARK: - SwiftUI View Modifiers

/// View modifier that redacts content when privacy mode is enabled
struct PrivacyRedactedModifier: ViewModifier {
    @ObservedObject var privacyManager = PrivacyManager.shared
    let redactionType: RedactionType
    
    enum RedactionType {
        case balance
        case address
        case transaction
    }
    
    func body(content: Content) -> some View {
        let shouldRedact: Bool = {
            switch redactionType {
            case .balance: return privacyManager.shouldHideBalances
            case .address: return privacyManager.shouldBlurAddresses
            case .transaction: return privacyManager.shouldHideTransactions
            }
        }()
        
        if shouldRedact {
            content
                .redacted(reason: .placeholder)
                .blur(radius: 8)
                .overlay(
                    Text("Tap to reveal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .opacity(0.7)
                )
                .onTapGesture {
                    privacyManager.temporaryReveal()
                }
        } else {
            content
        }
    }
}

/// View modifier for balance-specific redaction
struct BalancePrivacyModifier: ViewModifier {
    @ObservedObject var privacyManager = PrivacyManager.shared
    
    func body(content: Content) -> some View {
        if privacyManager.shouldHideBalances {
            Text("••••••")
                .foregroundColor(.secondary)
                .onTapGesture {
                    privacyManager.temporaryReveal()
                }
        } else {
            content
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Redact this view when privacy mode is enabled
    func privacyRedacted(_ type: PrivacyRedactedModifier.RedactionType = .balance) -> some View {
        modifier(PrivacyRedactedModifier(redactionType: type))
    }
    
    /// Hide balance when privacy mode is enabled
    func privacyBalance() -> some View {
        modifier(BalancePrivacyModifier())
    }
}

// MARK: - Privacy-Aware Balance Text

/// A text view that automatically respects privacy settings
struct PrivacyBalanceText: View {
    let value: Double
    let symbol: String
    let font: Font
    let color: Color
    
    @ObservedObject private var privacyManager = PrivacyManager.shared
    
    init(_ value: Double, symbol: String, font: Font = .body, color: Color = .primary) {
        self.value = value
        self.symbol = symbol
        self.font = font
        self.color = color
    }
    
    var body: some View {
        Group {
            if privacyManager.shouldHideBalances {
                Text("••••••")
                    .font(font)
                    .foregroundColor(.secondary)
            } else {
                Text(String(format: "%.8f %@", value, symbol))
                    .font(font)
                    .foregroundColor(color)
            }
        }
        .onTapGesture {
            if privacyManager.shouldHideBalances {
                privacyManager.temporaryReveal()
            }
        }
    }
}

/// A text view for fiat values that respects privacy settings
struct PrivacyFiatText: View {
    let value: Double
    let currencySymbol: String
    let font: Font
    let color: Color
    
    @ObservedObject private var privacyManager = PrivacyManager.shared
    
    init(_ value: Double, currencySymbol: String = "$", font: Font = .body, color: Color = .primary) {
        self.value = value
        self.currencySymbol = currencySymbol
        self.font = font
        self.color = color
    }
    
    var body: some View {
        Group {
            if privacyManager.shouldHideBalances {
                Text("\(currencySymbol)••••••")
                    .font(font)
                    .foregroundColor(.secondary)
            } else {
                Text(String(format: "%@%.2f", currencySymbol, value))
                    .font(font)
                    .foregroundColor(color)
            }
        }
        .onTapGesture {
            if privacyManager.shouldHideBalances {
                privacyManager.temporaryReveal()
            }
        }
    }
}

// MARK: - Privacy Toggle Button

/// A toolbar button for quickly toggling privacy mode
struct PrivacyToggleButton: View {
    @ObservedObject private var privacyManager = PrivacyManager.shared
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                privacyManager.togglePrivacyMode()
            }
        }) {
            Image(systemName: privacyManager.isPrivacyModeEnabled ? "eye.slash.fill" : "eye.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(privacyManager.isPrivacyModeEnabled ? .orange : .secondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(privacyManager.isPrivacyModeEnabled ? Color.orange.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(privacyManager.isPrivacyModeEnabled ? "Disable Privacy Mode" : "Enable Privacy Mode")
    }
}
