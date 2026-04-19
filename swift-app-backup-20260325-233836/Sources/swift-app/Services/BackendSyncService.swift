import Foundation
import Combine

// MARK: - Sync State

/// Represents the state of a sync operation
enum SyncState: Equatable {
    case idle
    case syncing
    case success(Date)
    case failed(String)
    case offline
    
    var isSyncing: Bool {
        if case .syncing = self { return true }
        return false
    }
    
    var lastSyncTime: Date? {
        if case .success(let date) = self { return date }
        return nil
    }
}

/// Type of data being synced
enum SyncDataType: String, CaseIterable {
    case balances = "balances"
    case transactions = "transactions"
    case prices = "prices"
    case exchangeRates = "exchange_rates"
    
    var cacheKey: String { "hawala_cache_\(rawValue)" }
    var staleAfterSeconds: TimeInterval {
        switch self {
        case .balances: return 60        // 1 minute
        case .transactions: return 300   // 5 minutes
        case .prices: return 30          // 30 seconds
        case .exchangeRates: return 3600 // 1 hour
        }
    }
}

// MARK: - Cache Models

/// Cached data with metadata
struct CachedData<T: Codable>: Codable {
    let data: T
    let timestamp: Date
    let eTag: String?
    
    var isStale: Bool {
        Date().timeIntervalSince(timestamp) > 300 // 5 minutes default
    }
    
    func isStale(after seconds: TimeInterval) -> Bool {
        Date().timeIntervalSince(timestamp) > seconds
    }
}

/// Generic cache entry for UserDefaults storage
struct CacheEntry: Codable {
    let data: Data
    let timestamp: Date
    let eTag: String?
    let chainId: String?
}

// MARK: - Retry Configuration

struct RetryConfiguration {
    let maxAttempts: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval
    let useExponentialBackoff: Bool
    
    static let `default` = RetryConfiguration(
        maxAttempts: 3,
        baseDelay: 1.0,
        maxDelay: 30.0,
        useExponentialBackoff: true
    )
    
    static let aggressive = RetryConfiguration(
        maxAttempts: 5,
        baseDelay: 0.5,
        maxDelay: 60.0,
        useExponentialBackoff: true
    )
    
    func delay(for attempt: Int) -> TimeInterval {
        if useExponentialBackoff {
            let delay = baseDelay * pow(2.0, Double(attempt - 1))
            return min(delay, maxDelay)
        }
        return baseDelay
    }
}

// MARK: - Network Error Types

enum NetworkError: LocalizedError {
    case noConnection
    case timeout
    case serverError(Int)
    case rateLimited(retryAfter: TimeInterval?)
    case invalidResponse
    case decodingError(Error)
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .noConnection: return "No internet connection"
        case .timeout: return "Request timed out"
        case .serverError(let code): return "Server error (\(code))"
        case .rateLimited: return "Rate limited - please wait"
        case .invalidResponse: return "Invalid server response"
        case .decodingError: return "Failed to parse response"
        case .cancelled: return "Request cancelled"
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .noConnection, .timeout, .serverError: return true
        case .rateLimited: return true
        case .invalidResponse, .decodingError, .cancelled: return false
        }
    }
}

// MARK: - Backend Sync Service

/// Centralized service for managing backend sync operations with caching and retry logic
@MainActor
class BackendSyncService: ObservableObject {
    static let shared = BackendSyncService()
    
    // MARK: - Published Properties
    
    @Published private(set) var syncStates: [SyncDataType: SyncState] = [:]
    @Published private(set) var isOnline: Bool = true
    @Published private(set) var lastFullSyncTime: Date?
    @Published var autoSyncEnabled: Bool = true
    
    // Offline queue for pending operations
    @Published private(set) var pendingOperationsCount: Int = 0
    
    // MARK: - Private Properties
    
    private let userDefaults = UserDefaults.standard
    private let cachePrefix = "hawala_sync_cache_"
    private var syncTasks: [SyncDataType: Task<Void, Never>] = [:]
    private var autoSyncTask: Task<Void, Never>?
    private var pendingOperations: [PendingOperation] = []
    
    private let session: URLSession
    
    // MARK: - Initialization
    
    private init() {
        // Configure URLSession with reasonable timeouts
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
        
        // Initialize sync states
        for type in SyncDataType.allCases {
            syncStates[type] = .idle
        }
        
        // Load pending operations
        loadPendingOperations()
    }
    
    // MARK: - Public Methods
    
    /// Start automatic sync with specified interval
    func startAutoSync(interval: TimeInterval = 60) {
        stopAutoSync()
        guard autoSyncEnabled else { return }
        
        autoSyncTask = Task {
            while !Task.isCancelled {
                await syncAll()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }
    
    /// Stop automatic sync
    func stopAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
    }
    
    /// Sync all data types
    func syncAll() async {
        guard isOnline else {
            for type in SyncDataType.allCases {
                syncStates[type] = .offline
            }
            return
        }
        
        // Run syncs concurrently
        await withTaskGroup(of: Void.self) { group in
            for type in SyncDataType.allCases {
                group.addTask {
                    await self.sync(type: type)
                }
            }
        }
        
        lastFullSyncTime = Date()
        
        // Process pending operations when back online
        await processPendingOperations()
    }
    
    /// Sync a specific data type
    func sync(type: SyncDataType) async {
        guard isOnline else {
            syncStates[type] = .offline
            return
        }
        
        syncStates[type] = .syncing
        
        do {
            switch type {
            case .balances:
                // Balances are chain-specific, handled elsewhere
                syncStates[type] = .success(Date())
            case .transactions:
                // Transactions are chain-specific, handled elsewhere
                syncStates[type] = .success(Date())
            case .prices:
                try await syncPrices()
                syncStates[type] = .success(Date())
            case .exchangeRates:
                try await syncExchangeRates()
                syncStates[type] = .success(Date())
            }
        } catch {
            let message = (error as? NetworkError)?.errorDescription ?? error.localizedDescription
            syncStates[type] = .failed(message)
        }
    }
    
    /// Force refresh, ignoring cache
    func forceRefresh(type: SyncDataType) async {
        clearCache(for: type)
        await sync(type: type)
    }
    
    // MARK: - Cached Fetch Methods
    
    /// Fetch data with caching and retry logic
    func fetchWithCache<T: Codable>(
        url: URL,
        cacheKey: String,
        staleAfter: TimeInterval = 300,
        retryConfig: RetryConfiguration = .default
    ) async throws -> T {
        
        // Check cache first
        if let cached: CachedData<T> = loadFromCache(key: cacheKey),
           !cached.isStale(after: staleAfter) {
            return cached.data
        }
        
        // Fetch from network with retry
        let data: T = try await fetchWithRetry(url: url, retryConfig: retryConfig)
        
        // Cache the result
        saveToCache(data: data, key: cacheKey)
        
        return data
    }
    
    /// Fetch data with retry logic
    func fetchWithRetry<T: Codable>(
        url: URL,
        retryConfig: RetryConfiguration = .default
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...retryConfig.maxAttempts {
            do {
                let (data, response) = try await session.data(from: url)
                
                // Check HTTP response
                if let httpResponse = response as? HTTPURLResponse {
                    switch httpResponse.statusCode {
                    case 200...299:
                        // Success - decode and return
                        return try JSONDecoder().decode(T.self, from: data)
                        
                    case 429:
                        // Rate limited
                        let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                            .flatMap { TimeInterval($0) }
                        throw NetworkError.rateLimited(retryAfter: retryAfter)
                        
                    case 500...599:
                        throw NetworkError.serverError(httpResponse.statusCode)
                        
                    default:
                        throw NetworkError.serverError(httpResponse.statusCode)
                    }
                }
                
                throw NetworkError.invalidResponse
                
            } catch let error as NetworkError {
                lastError = error
                
                if error.isRetryable && attempt < retryConfig.maxAttempts {
                    var delay = retryConfig.delay(for: attempt)
                    
                    // Use server-provided retry delay if available
                    if case .rateLimited(let retryAfter) = error, let after = retryAfter {
                        delay = after
                    }
                    
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                throw error
                
            } catch is DecodingError {
                throw NetworkError.decodingError(lastError ?? NSError())
                
            } catch {
                lastError = error
                
                if attempt < retryConfig.maxAttempts {
                    let delay = retryConfig.delay(for: attempt)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                throw error
            }
        }
        
        throw lastError ?? NetworkError.invalidResponse
    }
    
    // MARK: - Offline Queue
    
    /// Queue an operation to be performed when back online
    func queueOfflineOperation(_ operation: PendingOperation) {
        pendingOperations.append(operation)
        pendingOperationsCount = pendingOperations.count
        savePendingOperations()
    }
    
    /// Process all pending operations
    func processPendingOperations() async {
        guard isOnline else { return }
        
        var processed: [UUID] = []
        
        for operation in pendingOperations {
            do {
                try await executeOperation(operation)
                processed.append(operation.id)
            } catch {
                print("Failed to process pending operation: \(error)")
                // Keep in queue for next attempt
            }
        }
        
        pendingOperations.removeAll { processed.contains($0.id) }
        pendingOperationsCount = pendingOperations.count
        savePendingOperations()
    }
    
    // MARK: - Cache Management
    
    /// Clear all cached data
    func clearAllCaches() {
        for type in SyncDataType.allCases {
            clearCache(for: type)
        }
    }
    
    /// Clear cache for specific type
    func clearCache(for type: SyncDataType) {
        userDefaults.removeObject(forKey: type.cacheKey)
    }
    
    /// Get cache age for a type
    func cacheAge(for type: SyncDataType) -> TimeInterval? {
        guard let entry = loadCacheEntry(key: type.cacheKey) else { return nil }
        return Date().timeIntervalSince(entry.timestamp)
    }
    
    // MARK: - Private Methods
    
    private func syncPrices() async throws {
        let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,litecoin,monero,solana,ripple,binancecoin&vs_currencies=usd")!
        let _: [String: [String: Double]] = try await fetchWithRetry(url: url)
    }
    
    private func syncExchangeRates() async throws {
        let url = URL(string: "https://api.coingecko.com/api/v3/exchange_rates")!
        // Exchange rates API returns a nested structure
        struct ExchangeRatesResponse: Codable {
            let rates: [String: ExchangeRate]
        }
        struct ExchangeRate: Codable {
            let name: String
            let unit: String
            let value: Double
            let type: String
        }
        let _: ExchangeRatesResponse = try await fetchWithRetry(url: url)
    }
    
    // MARK: - Cache Helpers
    
    private func loadFromCache<T: Codable>(key: String) -> CachedData<T>? {
        guard let entry = loadCacheEntry(key: key),
              let decoded = try? JSONDecoder().decode(T.self, from: entry.data) else {
            return nil
        }
        return CachedData(data: decoded, timestamp: entry.timestamp, eTag: entry.eTag)
    }
    
    private func saveToCache<T: Codable>(data: T, key: String, eTag: String? = nil) {
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        let entry = CacheEntry(data: encoded, timestamp: Date(), eTag: eTag, chainId: nil)
        if let entryData = try? JSONEncoder().encode(entry) {
            userDefaults.set(entryData, forKey: cachePrefix + key)
        }
    }
    
    private func loadCacheEntry(key: String) -> CacheEntry? {
        guard let data = userDefaults.data(forKey: cachePrefix + key),
              let entry = try? JSONDecoder().decode(CacheEntry.self, from: data) else {
            return nil
        }
        return entry
    }
    
    // MARK: - Pending Operations
    
    private func loadPendingOperations() {
        guard let data = userDefaults.data(forKey: "hawala_pending_operations"),
              let operations = try? JSONDecoder().decode([PendingOperation].self, from: data) else {
            return
        }
        pendingOperations = operations
        pendingOperationsCount = operations.count
    }
    
    private func savePendingOperations() {
        guard let data = try? JSONEncoder().encode(pendingOperations) else { return }
        userDefaults.set(data, forKey: "hawala_pending_operations")
    }
    
    private func executeOperation(_ operation: PendingOperation) async throws {
        // Execute based on operation type
        switch operation.type {
        case .sendTransaction:
            // Transaction broadcast would be handled by the appropriate chain service
            break
        case .refreshBalance:
            // Trigger balance refresh
            break
        case .syncHistory:
            // Trigger history sync
            break
        }
    }
}

// MARK: - Pending Operation Model

struct PendingOperation: Identifiable, Codable {
    let id: UUID
    let type: OperationType
    let chainId: String
    let payload: Data?
    let createdAt: Date
    let retryCount: Int
    
    enum OperationType: String, Codable {
        case sendTransaction
        case refreshBalance
        case syncHistory
    }
    
    init(type: OperationType, chainId: String, payload: Data? = nil) {
        self.id = UUID()
        self.type = type
        self.chainId = chainId
        self.payload = payload
        self.createdAt = Date()
        self.retryCount = 0
    }
}

// MARK: - Sync Status View Model

/// Helper for displaying sync status in UI
extension BackendSyncService {
    var overallSyncStatus: String {
        if !isOnline { return "Offline" }
        if syncStates.values.contains(where: { $0.isSyncing }) { return "Syncing..." }
        if let lastSync = lastFullSyncTime {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Synced \(formatter.localizedString(for: lastSync, relativeTo: Date()))"
        }
        return "Not synced"
    }
    
    var syncStatusIcon: String {
        if !isOnline { return "wifi.slash" }
        if syncStates.values.contains(where: { $0.isSyncing }) { return "arrow.triangle.2.circlepath" }
        return "checkmark.circle"
    }
}
