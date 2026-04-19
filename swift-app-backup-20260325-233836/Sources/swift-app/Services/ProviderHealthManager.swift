import Foundation
import SwiftUI
import Combine

// MARK: - Provider Health State

/// Represents the health status of a data provider
public enum ProviderHealthState: Equatable, Sendable {
    case healthy
    case degraded(reason: String)
    case offline(reason: String)
    case unknown
    
    var isUsable: Bool {
        switch self {
        case .healthy, .degraded: return true
        case .offline, .unknown: return false
        }
    }
    
    var displayText: String {
        switch self {
        case .healthy: return "Connected"
        case .degraded(let reason): return "Limited: \(reason)"
        case .offline(let reason): return "Offline: \(reason)"
        case .unknown: return "Checking..."
        }
    }
    
    var iconName: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .offline: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .healthy: return .green
        case .degraded: return .orange
        case .offline: return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - Provider Type

/// Known provider types
public enum ProviderType: String, CaseIterable, Identifiable, Sendable {
    case moralis = "Moralis"
    case tatum = "Tatum"
    case coinCap = "CoinCap"
    case cryptoCompare = "CryptoCompare"
    case coinGecko = "CoinGecko"
    case alchemy = "Alchemy"
    case blockchair = "Blockchair"
    case mempool = "Mempool"
    case xrpScan = "XRPScan"
    case solscan = "Solscan"
    
    public var id: String { rawValue }
    
    var displayName: String { rawValue }
    
    var category: ProviderCategory {
        switch self {
        case .moralis, .tatum, .coinCap, .cryptoCompare, .coinGecko:
            return .price
        case .alchemy, .blockchair, .mempool, .xrpScan, .solscan:
            return .blockchain
        }
    }
    
    /// Priority order for fallback (lower = higher priority)
    var priority: Int {
        switch self {
        case .moralis: return 1     // Trust Wallet's provider - highest reliability
        case .alchemy: return 2     // Enterprise-grade
        case .tatum: return 3       // 130+ chains
        case .mempool: return 4     // Bitcoin-specific excellence
        case .blockchair: return 5
        case .coinCap: return 6
        case .cryptoCompare: return 7
        case .coinGecko: return 8   // Often rate-limited
        case .xrpScan: return 9
        case .solscan: return 10
        }
    }
}

public enum ProviderCategory: String, Sendable {
    case price = "Price Data"
    case blockchain = "Blockchain Data"
}

// MARK: - Provider Status

/// Tracks status of an individual provider
public struct ProviderStatus: Identifiable, Sendable {
    public let id: ProviderType
    public var state: ProviderHealthState
    public var lastSuccess: Date?
    public var lastFailure: Date?
    public var failureCount: Int
    public var lastError: String?
    
    public init(provider: ProviderType) {
        self.id = provider
        self.state = .unknown
        self.lastSuccess = nil
        self.lastFailure = nil
        self.failureCount = 0
        self.lastError = nil
    }
}

// MARK: - Provider Health Manager

/// Manages health status of all data providers
@MainActor
public final class ProviderHealthManager: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = ProviderHealthManager()
    
    // MARK: - Published State
    
    /// Status of each provider
    @Published public private(set) var providerStatuses: [ProviderType: ProviderStatus] = [:]
    
    /// Overall system health (aggregate)
    @Published public private(set) var overallHealth: ProviderHealthState = .unknown
    
    /// Whether we're currently checking health
    @Published public private(set) var isChecking: Bool = false
    
    // MARK: - Configuration
    
    /// Number of consecutive failures before marking offline
    public var failureThreshold: Int = 3
    
    /// Time after which a provider is retried automatically
    public var retryInterval: TimeInterval = 60
    
    /// Whether to automatically retry failed providers
    public var autoRetry: Bool = true
    
    // MARK: - Private
    
    private var retryTimers: [ProviderType: Timer] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Init
    
    private init() {
        // Initialize status for all providers
        for provider in ProviderType.allCases {
            providerStatuses[provider] = ProviderStatus(provider: provider)
        }
        updateOverallHealth()
    }
    
    // MARK: - Public API
    
    /// Record a successful provider call
    public func recordSuccess(for provider: ProviderType) {
        var status = providerStatuses[provider] ?? ProviderStatus(provider: provider)
        status.state = .healthy
        status.lastSuccess = Date()
        status.failureCount = 0
        status.lastError = nil
        providerStatuses[provider] = status
        
        // Cancel any retry timer
        retryTimers[provider]?.invalidate()
        retryTimers[provider] = nil
        
        updateOverallHealth()
        Log.debug("Provider \(provider.rawValue) marked healthy", category: .provider)
    }
    
    /// Record a provider failure
    public func recordFailure(for provider: ProviderType, error: Error) {
        recordFailure(for: provider, reason: error.localizedDescription)
    }
    
    /// Record a provider failure with reason string
    public func recordFailure(for provider: ProviderType, reason: String) {
        var status = providerStatuses[provider] ?? ProviderStatus(provider: provider)
        status.lastFailure = Date()
        status.failureCount += 1
        status.lastError = friendlyErrorMessage(reason)
        
        // Determine state based on failure count
        if status.failureCount >= failureThreshold {
            status.state = .offline(reason: status.lastError ?? "Multiple failures")
        } else {
            status.state = .degraded(reason: status.lastError ?? "Temporary issue")
        }
        
        providerStatuses[provider] = status
        updateOverallHealth()
        
        Log.warn("Provider \(provider.rawValue) failure #\(status.failureCount): \(reason)", category: .provider)
        
        // Schedule retry if enabled
        if autoRetry {
            scheduleRetry(for: provider)
        }
    }
    
    /// Manually mark a provider as offline
    public func markOffline(_ provider: ProviderType, reason: String) {
        var status = providerStatuses[provider] ?? ProviderStatus(provider: provider)
        status.state = .offline(reason: friendlyErrorMessage(reason))
        status.lastError = reason
        providerStatuses[provider] = status
        updateOverallHealth()
    }
    
    /// Check if a provider is usable
    public func isProviderUsable(_ provider: ProviderType) -> Bool {
        providerStatuses[provider]?.state.isUsable ?? false
    }
    
    /// Get the best available provider for a category
    public func bestProvider(for category: ProviderCategory) -> ProviderType? {
        ProviderType.allCases
            .filter { $0.category == category }
            .filter { isProviderUsable($0) }
            .first
    }
    
    /// Reset all providers to unknown state
    public func resetAll() {
        for provider in ProviderType.allCases {
            providerStatuses[provider] = ProviderStatus(provider: provider)
            retryTimers[provider]?.invalidate()
            retryTimers[provider] = nil
        }
        overallHealth = .unknown
    }
    
    /// Force refresh health check for all providers
    public func refreshAll() async {
        isChecking = true
        // In a real implementation, this would ping each provider
        // For now, just reset the checking state after a delay
        try? await Task.sleep(nanoseconds: 500_000_000)
        isChecking = false
    }
    
    // MARK: - Private Helpers
    
    private func updateOverallHealth() {
        let statuses = Array(providerStatuses.values)
        
        let healthyCount = statuses.filter { $0.state == .healthy }.count
        let offlineCount = statuses.filter {
            if case .offline = $0.state { return true }
            return false
        }.count
        
        if healthyCount == statuses.count {
            overallHealth = .healthy
        } else if offlineCount == statuses.count {
            overallHealth = .offline(reason: "All providers unavailable")
        } else if healthyCount > 0 {
            overallHealth = .degraded(reason: "Some providers unavailable")
        } else {
            overallHealth = .unknown
        }
    }
    
    private func scheduleRetry(for provider: ProviderType) {
        // Cancel existing timer
        retryTimers[provider]?.invalidate()
        
        // Schedule new retry
        retryTimers[provider] = Timer.scheduledTimer(withTimeInterval: retryInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                // Reset failure count to give provider another chance
                if var status = self?.providerStatuses[provider] {
                    status.state = .unknown
                    status.failureCount = max(0, status.failureCount - 1)
                    self?.providerStatuses[provider] = status
                    self?.updateOverallHealth()
                    Log.debug("Provider \(provider.rawValue) retry scheduled", category: .provider)
                }
            }
        }
    }
    
    /// Convert technical error messages to user-friendly versions
    private func friendlyErrorMessage(_ error: String) -> String {
        let lowercased = error.lowercased()
        
        if lowercased.contains("could not be found") || lowercased.contains("dns") {
            return "Server unreachable"
        }
        if lowercased.contains("403") {
            return "Access denied"
        }
        if lowercased.contains("401") {
            return "Authentication required"
        }
        if lowercased.contains("429") || lowercased.contains("rate limit") {
            return "Rate limited"
        }
        if lowercased.contains("timeout") {
            return "Request timed out"
        }
        if lowercased.contains("500") || lowercased.contains("502") || lowercased.contains("503") {
            return "Server error"
        }
        if lowercased.contains("cancelled") {
            return "Request cancelled"
        }
        if lowercased.contains("network") || lowercased.contains("internet") {
            return "No internet connection"
        }
        
        // Return shortened version if too long
        if error.count > 50 {
            return String(error.prefix(47)) + "..."
        }
        
        return error
    }
}

// MARK: - Provider Status Banner View

/// A banner that shows when providers are degraded or offline
public struct ProviderStatusBanner: View {
    @ObservedObject private var healthManager = ProviderHealthManager.shared
    @State private var isExpanded = false
    
    public init() {}
    
    public var body: some View {
        Group {
            switch healthManager.overallHealth {
            case .healthy:
                EmptyView()
                
            case .degraded(let reason), .offline(let reason):
                bannerContent(reason: reason, isOffline: isOfflineState)
                
            case .unknown:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: healthManager.overallHealth)
    }
    
    private var isOfflineState: Bool {
        if case .offline = healthManager.overallHealth { return true }
        return false
    }
    
    @ViewBuilder
    private func bannerContent(reason: String, isOffline: Bool) -> some View {
        VStack(spacing: 0) {
            // Main banner
            HStack(spacing: 12) {
                Image(systemName: isOffline ? "wifi.slash" : "exclamationmark.triangle.fill")
                    .foregroundColor(isOffline ? .red : .orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(isOffline ? "Connection Issues" : "Limited Connectivity")
                        .font(.subheadline.weight(.semibold))
                    Text(reason)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    withAnimation {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isOffline ? Color.red.opacity(0.1) : Color.orange.opacity(0.1))
            
            // Expanded details
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(Array(healthManager.providerStatuses.values).sorted(by: { $0.id.rawValue < $1.id.rawValue })) { status in
                        HStack {
                            Image(systemName: status.state.iconName)
                                .foregroundColor(status.state.color)
                                .frame(width: 20)
                            
                            Text(status.id.displayName)
                                .font(.caption)
                            
                            Spacer()
                            
                            Text(status.state.displayText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button {
                        Task {
                            await healthManager.refreshAll()
                        }
                    } label: {
                        HStack {
                            if healthManager.isChecking {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Text(healthManager.isChecking ? "Checking..." : "Retry All")
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(healthManager.isChecking)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isOffline ? Color.red.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#if DEBUG
struct ProviderStatusBanner_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ProviderStatusBanner()
        }
        .padding()
        .onAppear {
            // Simulate some failures for preview
            ProviderHealthManager.shared.recordFailure(for: .coinCap, reason: "DNS lookup failed")
            ProviderHealthManager.shared.recordFailure(for: .alchemy, reason: "HTTP 403")
            ProviderHealthManager.shared.recordSuccess(for: .cryptoCompare)
        }
    }
}
#endif
