import Foundation

// MARK: - Analytics Event

/// Represents a single analytics event
struct AnalyticsEvent: Codable, Sendable {
    let name: String
    let properties: [String: String]
    let timestamp: Date
    let sessionId: String
    
    init(name: String, properties: [String: String] = [:], timestamp: Date = Date(), sessionId: String) {
        self.name = name
        self.properties = properties
        self.timestamp = timestamp
        self.sessionId = sessionId
    }
}

// MARK: - Analytics Provider Protocol

/// Protocol for pluggable analytics backends
protocol AnalyticsProvider: Sendable {
    func send(events: [AnalyticsEvent]) async throws
    var name: String { get }
}

// MARK: - Console Analytics Provider (Debug)

/// Debug provider that prints events to console
struct ConsoleAnalyticsProvider: AnalyticsProvider {
    let name = "Console"
    
    func send(events: [AnalyticsEvent]) async throws {
        for event in events {
            let props = event.properties.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            print("[Analytics] \(event.name) {\(props)}")
        }
    }
}

// MARK: - Analytics Service

/// Centralized analytics service with privacy-first design
/// Supports opt-out, batched event sending, and pluggable backends
@MainActor
final class AnalyticsService: ObservableObject {
    static let shared = AnalyticsService()
    
    // MARK: - Published State
    
    /// Whether the user has opted into analytics
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: analyticsEnabledKey)
            if !isEnabled {
                // Clear pending events when user opts out
                pendingEvents.removeAll()
                eventCount = 0
            }
        }
    }
    
    /// Total events tracked this session (for transparency UI)
    @Published private(set) var eventCount: Int = 0
    
    // MARK: - Configuration
    
    /// Maximum events to batch before auto-flush
    let batchSize: Int = 50
    
    /// Auto-flush interval in seconds
    let flushInterval: TimeInterval = 300 // 5 minutes
    
    // MARK: - Private State
    
    private var pendingEvents: [AnalyticsEvent] = []
    private var providers: [any AnalyticsProvider] = []
    private let sessionId: String
    private var flushTask: Task<Void, Never>?
    private let analyticsEnabledKey = "hawala.analytics.enabled"
    private let analyticsOptInShownKey = "hawala.analytics.optInShown"
    
    // MARK: - Event Names (type-safe)
    
    enum EventName {
        static let appLaunch = "app_launch"
        static let walletCreated = "wallet_created"
        static let walletImported = "wallet_imported"
        static let sendInitiated = "send_initiated"
        static let sendCompleted = "send_completed"
        static let sendFailed = "send_failed"
        static let receiveViewed = "receive_viewed"
        static let swapInitiated = "swap_initiated"
        static let swapCompleted = "swap_completed"
        static let bridgeInitiated = "bridge_initiated"
        static let navigationTransition = "navigation_transition"
        static let deepLinkOpened = "deep_link_opened"
        static let settingsChanged = "settings_changed"
        static let securityScoreViewed = "security_score_viewed"
        static let backupCompleted = "backup_completed"
        static let walletConnectSession = "wallet_connect_session"
        static let feeEstimateViewed = "fee_estimate_viewed"
        static let historyExported = "history_exported"
        static let contactAdded = "contact_added"
        static let hardwareWalletConnected = "hw_wallet_connected"
        static let errorOccurred = "error_occurred"
        static let screenViewed = "screen_viewed"
    }
    
    // MARK: - Init
    
    private init() {
        self.sessionId = UUID().uuidString
        self.isEnabled = UserDefaults.standard.bool(forKey: analyticsEnabledKey)
        
        #if DEBUG
        // Always add console provider in debug builds
        addProvider(ConsoleAnalyticsProvider())
        #endif
        
        startFlushTimer()
    }
    
    deinit {
        flushTask?.cancel()
    }
    
    // MARK: - Public API
    
    /// Track an analytics event (no-op if user has opted out)
    func track(_ eventName: String, properties: [String: String] = [:]) {
        guard isEnabled else { return }
        
        // Strip any PII from properties
        let sanitized = sanitizeProperties(properties)
        
        let event = AnalyticsEvent(
            name: eventName,
            properties: sanitized,
            timestamp: Date(),
            sessionId: sessionId
        )
        
        pendingEvents.append(event)
        eventCount += 1
        
        // Auto-flush if batch is full
        if pendingEvents.count >= batchSize {
            flush()
        }
    }
    
    /// Track a screen view event
    func trackScreen(_ screenName: String) {
        track(EventName.screenViewed, properties: ["screen": screenName])
    }
    
    /// Track an error event (sanitized — no stack traces or user data)
    func trackError(_ category: String, message: String) {
        track(EventName.errorOccurred, properties: [
            "category": category,
            "message": message.prefix(200).description // Truncate long messages
        ])
    }
    
    /// Flush all pending events to providers
    func flush() {
        guard !pendingEvents.isEmpty else { return }
        let eventsToSend = pendingEvents
        pendingEvents.removeAll()
        
        Task {
            for provider in providers {
                do {
                    try await provider.send(events: eventsToSend)
                } catch {
                    #if DEBUG
                    print("[Analytics] Failed to send to \(provider.name): \(error)")
                    #endif
                }
            }
        }
    }
    
    /// Register an analytics backend provider
    func addProvider(_ provider: any AnalyticsProvider) {
        providers.append(provider)
    }
    
    /// Whether the opt-in prompt has been shown to the user
    var hasShownOptIn: Bool {
        get { UserDefaults.standard.bool(forKey: analyticsOptInShownKey) }
        set { UserDefaults.standard.set(newValue, forKey: analyticsOptInShownKey) }
    }
    
    /// Reset all analytics data (for privacy/account deletion)
    func reset() {
        pendingEvents.removeAll()
        eventCount = 0
        isEnabled = false
        hasShownOptIn = false
    }
    
    // MARK: - Private Helpers
    
    /// Removes potentially sensitive information from properties
    private func sanitizeProperties(_ props: [String: String]) -> [String: String] {
        var sanitized = props
        
        // Strip any property that looks like an address, key, or seed
        let sensitivePatterns = ["address", "key", "seed", "private", "secret", "password", "mnemonic"]
        for key in sanitized.keys {
            if sensitivePatterns.contains(where: { key.lowercased().contains($0) }) {
                sanitized[key] = "[redacted]"
            }
        }
        
        // Strip any value that looks like a crypto address (long hex strings)
        for (key, value) in sanitized {
            if value.count > 30 && value.allSatisfy({ $0.isHexDigit || $0 == "x" }) {
                sanitized[key] = "[redacted_address]"
            }
        }
        
        return sanitized
    }
    
    private func startFlushTimer() {
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64((self?.flushInterval ?? 300) * 1_000_000_000))
                self?.flush()
            }
        }
    }
}
