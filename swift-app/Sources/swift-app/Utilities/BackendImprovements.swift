import Foundation
import Combine
import Network
import SwiftUI

// MARK: - 5. WebSocket Price Streaming

/// Real-time price streaming via WebSocket
@MainActor
final class WebSocketPriceStream: ObservableObject {
    static let shared = WebSocketPriceStream()
    
    @Published private(set) var prices: [String: Double] = [:]
    @Published private(set) var isConnected = false
    @Published private(set) var lastUpdate: Date?
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private let reconnectDelay: TimeInterval = 2.0
    
    // Supported coins for streaming
    private let supportedCoins = [
        "bitcoin", "ethereum", "litecoin", "solana", "ripple", "binancecoin", "monero"
    ]
    
    private init() {}
    
    // MARK: - Connection Management
    
    func connect() {
        guard webSocketTask == nil else { return }
        
        // Using CoinCap WebSocket API (free, no auth required)
        // Format: wss://ws.coincap.io/prices?assets=bitcoin,ethereum,...
        let assets = supportedCoins.joined(separator: ",")
        guard let url = URL(string: "wss://ws.coincap.io/prices?assets=\(assets)") else {
            print("WebSocketPriceStream: Invalid URL")
            return
        }
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        isConnected = true
        reconnectAttempts = 0
        
        // Start receiving messages
        receiveMessage()
        
        // Start ping timer to keep connection alive
        startPingTimer()
        
        print("WebSocketPriceStream: Connected to \(url)")
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        pingTimer?.invalidate()
        pingTimer = nil
        isConnected = false
        print("WebSocketPriceStream: Disconnected")
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self?.handleMessage(message)
                    self?.receiveMessage() // Continue listening
                    
                case .failure(let error):
                    print("WebSocketPriceStream: Receive error: \(error)")
                    self?.handleDisconnect()
                }
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseJSONPrices(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseJSONPrices(text)
            }
        @unknown default:
            break
        }
    }
    
    private func parseJSONPrices(_ json: String) {
        guard let data = json.data(using: .utf8),
              let priceDict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return
        }
        
        // Update prices
        for (coin, priceString) in priceDict {
            if let price = Double(priceString) {
                prices[coin] = price
            }
        }
        
        lastUpdate = Date()
    }
    
    private func handleDisconnect() {
        isConnected = false
        webSocketTask = nil
        pingTimer?.invalidate()
        
        // Attempt reconnection
        if reconnectAttempts < maxReconnectAttempts {
            reconnectAttempts += 1
            let delay = reconnectDelay * Double(reconnectAttempts)
            print("WebSocketPriceStream: Reconnecting in \(delay)s (attempt \(reconnectAttempts))")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.connect()
            }
        } else {
            print("WebSocketPriceStream: Max reconnect attempts reached")
        }
    }
    
    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendPing()
            }
        }
    }
    
    private func sendPing() {
        webSocketTask?.sendPing { [weak self] error in
            if let error = error {
                print("WebSocketPriceStream: Ping failed: \(error)")
                Task { @MainActor in
                    self?.handleDisconnect()
                }
            }
        }
    }
    
    // MARK: - Price Helpers
    
    func price(for coinId: String) -> Double? {
        // Map chain IDs to CoinCap IDs
        let mapping: [String: String] = [
            "bitcoin": "bitcoin",
            "bitcoin-testnet": "bitcoin",
            "ethereum": "ethereum",
            "ethereum-sepolia": "ethereum",
            "litecoin": "litecoin",
            "solana": "solana",
            "xrp": "ripple",
            "bnb": "binancecoin",
            "monero": "monero"
        ]
        
        if let mappedId = mapping[coinId] {
            return prices[mappedId]
        }
        return prices[coinId]
    }
}

// MARK: - 6. Transaction Mempool Monitoring

/// Monitors pending transactions in the mempool
@MainActor
final class MempoolMonitor: ObservableObject {
    static let shared = MempoolMonitor()
    
    struct PendingTransaction: Identifiable, Sendable {
        let id: String // txHash
        let chainId: String
        let timestamp: Date
        var status: Status
        var confirmations: Int
        var estimatedConfirmTime: TimeInterval?
        
        enum Status: String, Sendable {
            case pending = "Pending"
            case confirming = "Confirming"
            case confirmed = "Confirmed"
            case failed = "Failed"
        }
    }
    
    @Published private(set) var pendingTransactions: [PendingTransaction] = []
    @Published private(set) var isMonitoring = false
    
    private var monitoringTasks: [String: Task<Void, Never>] = [:]
    private let pollingInterval: TimeInterval = 15.0
    
    private init() {}
    
    // MARK: - Monitoring
    
    func addTransaction(txHash: String, chainId: String) {
        let tx = PendingTransaction(
            id: txHash,
            chainId: chainId,
            timestamp: Date(),
            status: .pending,
            confirmations: 0,
            estimatedConfirmTime: estimatedTime(for: chainId)
        )
        
        pendingTransactions.append(tx)
        startMonitoring(txHash: txHash, chainId: chainId)
    }
    
    func removeTransaction(txHash: String) {
        pendingTransactions.removeAll { $0.id == txHash }
        monitoringTasks[txHash]?.cancel()
        monitoringTasks.removeValue(forKey: txHash)
    }
    
    private func startMonitoring(txHash: String, chainId: String) {
        let task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.checkTransactionStatus(txHash: txHash, chainId: chainId)
                
                // Check if confirmed
                if let tx = self?.pendingTransactions.first(where: { $0.id == txHash }),
                   tx.status == .confirmed || tx.status == .failed {
                    break
                }
                
                try? await Task.sleep(nanoseconds: UInt64(self?.pollingInterval ?? 15) * 1_000_000_000)
            }
        }
        
        monitoringTasks[txHash] = task
        isMonitoring = !monitoringTasks.isEmpty
    }
    
    private func checkTransactionStatus(txHash: String, chainId: String) async {
        guard let index = pendingTransactions.firstIndex(where: { $0.id == txHash }) else {
            return
        }
        
        do {
            let (status, confirmations) = try await fetchTransactionStatus(txHash: txHash, chainId: chainId)
            
            pendingTransactions[index].confirmations = confirmations
            
            if confirmations >= requiredConfirmations(for: chainId) {
                pendingTransactions[index].status = .confirmed
                // Notify user
                await notifyConfirmation(tx: pendingTransactions[index])
            } else if confirmations > 0 {
                pendingTransactions[index].status = .confirming
            } else if status == "failed" {
                pendingTransactions[index].status = .failed
            }
        } catch {
            print("MempoolMonitor: Error checking \(txHash): \(error)")
        }
    }
    
    private func fetchTransactionStatus(txHash: String, chainId: String) async throws -> (String, Int) {
        // Different APIs for different chains
        switch chainId {
        case "bitcoin", "bitcoin-testnet":
            return try await fetchBitcoinTxStatus(txHash: txHash, testnet: chainId == "bitcoin-testnet")
        case "ethereum", "ethereum-sepolia":
            return try await fetchEthereumTxStatus(txHash: txHash, testnet: chainId == "ethereum-sepolia")
        case "litecoin":
            return try await fetchLitecoinTxStatus(txHash: txHash)
        default:
            return ("unknown", 0)
        }
    }
    
    private func fetchBitcoinTxStatus(txHash: String, testnet: Bool) async throws -> (String, Int) {
        let baseURL = testnet ? "https://blockstream.info/testnet/api" : "https://blockstream.info/api"
        guard let url = URL(string: "\(baseURL)/tx/\(txHash)") else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = json["status"] as? [String: Any] {
            let confirmed = status["confirmed"] as? Bool ?? false
            let blockHeight = status["block_height"] as? Int
            
            if confirmed, let height = blockHeight {
                // Get current block height to calculate confirmations
                let tipURL = URL(string: "\(baseURL)/blocks/tip/height")!
                let (tipData, _) = try await URLSession.shared.data(from: tipURL)
                if let tipHeight = Int(String(data: tipData, encoding: .utf8) ?? "") {
                    return ("confirmed", tipHeight - height + 1)
                }
            }
            
            return (confirmed ? "confirmed" : "pending", 0)
        }
        
        return ("unknown", 0)
    }
    
    private func fetchEthereumTxStatus(txHash: String, testnet: Bool) async throws -> (String, Int) {
        // Using public RPC
        let rpcURL = testnet 
            ? "https://ethereum-sepolia-rpc.publicnode.com"
            : "https://eth.llamarpc.com"
        
        guard let url = URL(string: rpcURL) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getTransactionReceipt",
            "params": [txHash],
            "id": 1
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = json["result"] as? [String: Any] {
            let status = result["status"] as? String
            let blockNumber = result["blockNumber"] as? String
            
            if status == "0x1", let blockHex = blockNumber {
                // Transaction confirmed
                // Get current block for confirmation count
                let blockBody: [String: Any] = [
                    "jsonrpc": "2.0",
                    "method": "eth_blockNumber",
                    "params": [],
                    "id": 1
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: blockBody)
                let (blockData, _) = try await URLSession.shared.data(for: request)
                
                if let blockJson = try? JSONSerialization.jsonObject(with: blockData) as? [String: Any],
                   let currentBlockHex = blockJson["result"] as? String {
                    let txBlock = Int(blockHex.dropFirst(2), radix: 16) ?? 0
                    let currentBlock = Int(currentBlockHex.dropFirst(2), radix: 16) ?? 0
                    return ("confirmed", currentBlock - txBlock + 1)
                }
            } else if status == "0x0" {
                return ("failed", 0)
            }
        }
        
        return ("pending", 0)
    }
    
    private func fetchLitecoinTxStatus(txHash: String) async throws -> (String, Int) {
        guard let url = URL(string: "https://litecoinspace.org/api/tx/\(txHash)") else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = json["status"] as? [String: Any] {
            let confirmed = status["confirmed"] as? Bool ?? false
            let blockHeight = status["block_height"] as? Int
            
            if confirmed, let height = blockHeight {
                let tipURL = URL(string: "https://litecoinspace.org/api/blocks/tip/height")!
                let (tipData, _) = try await URLSession.shared.data(from: tipURL)
                if let tipHeight = Int(String(data: tipData, encoding: .utf8) ?? "") {
                    return ("confirmed", tipHeight - height + 1)
                }
            }
            
            return (confirmed ? "confirmed" : "pending", 0)
        }
        
        return ("unknown", 0)
    }
    
    private func requiredConfirmations(for chainId: String) -> Int {
        switch chainId {
        case "bitcoin", "bitcoin-testnet": return 3
        case "ethereum", "ethereum-sepolia": return 12
        case "litecoin": return 6
        default: return 1
        }
    }
    
    private func estimatedTime(for chainId: String) -> TimeInterval {
        switch chainId {
        case "bitcoin", "bitcoin-testnet": return 30 * 60 // 30 min for 3 confirmations
        case "ethereum", "ethereum-sepolia": return 3 * 60 // 3 min for 12 confirmations
        case "litecoin": return 15 * 60 // 15 min for 6 confirmations
        default: return 10 * 60
        }
    }
    
    private func notifyConfirmation(tx: PendingTransaction) async {
        // Send notification
        let content = UNMutableNotificationContent()
        content.title = "Transaction Confirmed"
        content.body = "Your \(tx.chainId) transaction has been confirmed"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: tx.id,
            content: content,
            trigger: nil
        )
        
        try? await UNUserNotificationCenter.current().add(request)
        
        // Play sound and haptic (uses UXEnhancements)
        #if canImport(AppKit)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        NSSound(named: "Glass")?.play()
        #endif
    }
}

import UserNotifications
import AppKit

// MARK: - 7. Better Error Recovery

/// Centralized error recovery with exponential backoff
@MainActor
final class ErrorRecoveryManager: ObservableObject {
    static let shared = ErrorRecoveryManager()
    
    struct RetryConfig {
        var maxAttempts: Int = 5
        var baseDelay: TimeInterval = 1.0
        var maxDelay: TimeInterval = 60.0
        var multiplier: Double = 2.0
        var jitter: Double = 0.1 // Random jitter to prevent thundering herd
    }
    
    @Published private(set) var activeRetries: [String: Int] = [:] // operationId -> attempt count
    
    private init() {}
    
    /// Execute an operation with automatic retry on failure
    func withRetry<T: Sendable>(
        operationId: String,
        config: RetryConfig = RetryConfig(),
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...config.maxAttempts {
            activeRetries[operationId] = attempt
            
            do {
                let result = try await operation()
                activeRetries.removeValue(forKey: operationId)
                return result
            } catch {
                lastError = error
                
                // Don't retry on certain errors
                if shouldNotRetry(error) {
                    activeRetries.removeValue(forKey: operationId)
                    throw error
                }
                
                // Calculate delay with exponential backoff
                if attempt < config.maxAttempts {
                    let delay = calculateDelay(attempt: attempt, config: config)
                    print("ErrorRecovery [\(operationId)]: Attempt \(attempt) failed, retrying in \(delay)s")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        activeRetries.removeValue(forKey: operationId)
        throw lastError ?? NSError(domain: "ErrorRecovery", code: -1, userInfo: [NSLocalizedDescriptionKey: "Max retries exceeded"])
    }
    
    private func calculateDelay(attempt: Int, config: RetryConfig) -> TimeInterval {
        let exponentialDelay = config.baseDelay * pow(config.multiplier, Double(attempt - 1))
        let cappedDelay = min(exponentialDelay, config.maxDelay)
        
        // Add jitter
        let jitterRange = cappedDelay * config.jitter
        let jitter = Double.random(in: -jitterRange...jitterRange)
        
        return max(0, cappedDelay + jitter)
    }
    
    private func shouldNotRetry(_ error: Error) -> Bool {
        // Don't retry on authentication errors, invalid input, etc.
        if let urlError = error as? URLError {
            switch urlError.code {
            case .userAuthenticationRequired,
                 .userCancelledAuthentication,
                 .badURL:
                return true
            default:
                return false
            }
        }
        
        // Don't retry HTTP 4xx errors (client errors)
        if let httpError = error as NSError?,
           httpError.domain == "HTTP",
           (400..<500).contains(httpError.code) {
            return true
        }
        
        return false
    }
    
    /// Cancel a retry operation
    func cancelRetry(operationId: String) {
        activeRetries.removeValue(forKey: operationId)
    }
}

// MARK: - 8. Offline Mode

/// Manages offline transaction queue and sync
@MainActor
final class OfflineManager: ObservableObject {
    static let shared = OfflineManager()
    
    struct QueuedTransaction: Codable, Identifiable {
        let id: UUID
        let chainId: String
        let fromAddress: String
        let toAddress: String
        let amount: String
        let signedTx: String
        let timestamp: Date
        var syncAttempts: Int
        var lastError: String?
    }
    
    @Published private(set) var queuedTransactions: [QueuedTransaction] = []
    @Published private(set) var isSyncing = false
    @Published var isOffline = false
    
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.hawala.network-monitor")
    private let storageKey = "hawala_offline_queue"
    
    private init() {
        loadQueue()
        startNetworkMonitoring()
    }
    
    // MARK: - Network Monitoring
    
    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasOffline = self?.isOffline ?? false
                self?.isOffline = path.status != .satisfied
                
                // If we just came online, sync queued transactions
                if wasOffline && path.status == .satisfied {
                    await self?.syncQueuedTransactions()
                }
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }
    
    // MARK: - Queue Management
    
    func queueTransaction(
        chainId: String,
        fromAddress: String,
        toAddress: String,
        amount: String,
        signedTx: String
    ) {
        let tx = QueuedTransaction(
            id: UUID(),
            chainId: chainId,
            fromAddress: fromAddress,
            toAddress: toAddress,
            amount: amount,
            signedTx: signedTx,
            timestamp: Date(),
            syncAttempts: 0,
            lastError: nil
        )
        
        queuedTransactions.append(tx)
        saveQueue()
        
        // Try to sync immediately if online
        if !isOffline {
            Task {
                await syncTransaction(tx)
            }
        }
    }
    
    func removeFromQueue(id: UUID) {
        queuedTransactions.removeAll { $0.id == id }
        saveQueue()
    }
    
    // MARK: - Sync
    
    func syncQueuedTransactions() async {
        guard !isSyncing, !queuedTransactions.isEmpty else { return }
        
        isSyncing = true
        
        for tx in queuedTransactions {
            await syncTransaction(tx)
        }
        
        isSyncing = false
    }
    
    private func syncTransaction(_ tx: QueuedTransaction) async {
        guard let index = queuedTransactions.firstIndex(where: { $0.id == tx.id }) else {
            return
        }
        
        queuedTransactions[index].syncAttempts += 1
        
        do {
            // Broadcast the signed transaction
            try await broadcastTransaction(signedTx: tx.signedTx, chainId: tx.chainId)
            
            // Success - remove from queue
            removeFromQueue(id: tx.id)
            
            // Notify user with haptic and sound
            #if canImport(AppKit)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            NSSound(named: "Blow")?.play()
            #endif
            
        } catch {
            queuedTransactions[index].lastError = error.localizedDescription
            saveQueue()
            
            // If too many attempts, notify user
            if queuedTransactions[index].syncAttempts >= 5 {
                await notifyFailure(tx: tx, error: error)
            }
        }
    }
    
    private func broadcastTransaction(signedTx: String, chainId: String) async throws {
        // Different broadcast endpoints for different chains
        let url: URL
        let body: Data
        
        switch chainId {
        case "bitcoin":
            url = URL(string: "https://blockstream.info/api/tx")!
            body = signedTx.data(using: .utf8)!
            
        case "bitcoin-testnet":
            url = URL(string: "https://blockstream.info/testnet/api/tx")!
            body = signedTx.data(using: .utf8)!
            
        case "ethereum":
            url = URL(string: "https://eth.llamarpc.com")!
            let jsonBody: [String: Any] = [
                "jsonrpc": "2.0",
                "method": "eth_sendRawTransaction",
                "params": [signedTx],
                "id": 1
            ]
            body = try JSONSerialization.data(withJSONObject: jsonBody)
            
        case "litecoin":
            url = URL(string: "https://litecoinspace.org/api/tx")!
            body = signedTx.data(using: .utf8)!
            
        default:
            throw NSError(domain: "OfflineManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported chain: \(chainId)"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        
        if chainId.contains("ethereum") {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else {
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "OfflineManager", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
    }
    
    private func notifyFailure(tx: QueuedTransaction, error: Error) async {
        let content = UNMutableNotificationContent()
        content.title = "Transaction Failed to Sync"
        content.body = "Your \(tx.chainId) transaction couldn't be broadcast. Tap to retry."
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: tx.id.uuidString,
            content: content,
            trigger: nil
        )
        
        try? await UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Persistence
    
    private func saveQueue() {
        if let data = try? JSONEncoder().encode(queuedTransactions) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func loadQueue() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let transactions = try? JSONDecoder().decode([QueuedTransaction].self, from: data) {
            queuedTransactions = transactions
        }
    }
}

// MARK: - Offline Status Banner

struct OfflineStatusBanner: View {
    @ObservedObject private var offlineManager = OfflineManager.shared
    
    var body: some View {
        if offlineManager.isOffline {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 14, weight: .semibold))
                
                Text("You're offline")
                    .font(.system(size: 13, weight: .medium))
                
                if !offlineManager.queuedTransactions.isEmpty {
                    Text("• \(offlineManager.queuedTransactions.count) pending")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                if offlineManager.isSyncing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.white)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange.gradient)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
