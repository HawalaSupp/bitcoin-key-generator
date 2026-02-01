import Foundation
import Combine

// MARK: - Transaction Confirmation Tracker

/// Tracks transaction confirmations across all chains
@MainActor
final class TransactionConfirmationTracker: ObservableObject {
    static let shared = TransactionConfirmationTracker()
    
    // MARK: - Published State
    
    @Published var trackedTransactions: [TrackedTransaction] = []
    @Published var isPolling = false
    
    // MARK: - Private State
    
    private var pollingTask: Task<Void, Never>?
    private var lastPollTime: Date?
    
    // Polling intervals
    private let bitcoinPollingInterval: TimeInterval = 30  // 30 seconds
    private let evmPollingInterval: TimeInterval = 12      // ~1 block time
    
    private init() {}
    
    // MARK: - Transaction Model
    
    struct TrackedTransaction: Identifiable, Equatable {
        let id: String // txid
        let chainId: String
        var confirmations: Int
        var status: TransactionStatus
        var blockHeight: Int?
        var timestamp: Date
        var lastChecked: Date
        
        enum TransactionStatus: String {
            case pending = "Pending"
            case confirming = "Confirming"
            case confirmed = "Confirmed"
            case failed = "Failed"
            case dropped = "Dropped"
        }
        
        var isConfirmed: Bool {
            switch chainId {
            case "bitcoin", "litecoin":
                return confirmations >= 6
            case "bitcoin-testnet":
                return confirmations >= 1
            case "ethereum", "bnb":
                return confirmations >= 12
            case "ethereum-sepolia":
                return confirmations >= 1
            default:
                return confirmations >= 1
            }
        }
        
        var confirmationProgress: Double {
            let required: Int
            switch chainId {
            case "bitcoin", "litecoin": required = 6
            case "bitcoin-testnet", "ethereum-sepolia": required = 1
            case "ethereum", "bnb": required = 12
            default: required = 1
            }
            return min(1.0, Double(confirmations) / Double(required))
        }
        
        var requiredConfirmations: Int {
            switch chainId {
            case "bitcoin", "litecoin": return 6
            case "bitcoin-testnet", "ethereum-sepolia": return 1
            case "ethereum", "bnb": return 12
            default: return 1
            }
        }
    }
    
    // MARK: - Public API
    
    /// Start tracking a new transaction
    func track(txid: String, chainId: String) {
        // Avoid duplicates
        guard !trackedTransactions.contains(where: { $0.id == txid }) else { return }
        
        let tx = TrackedTransaction(
            id: txid,
            chainId: chainId,
            confirmations: 0,
            status: .pending,
            blockHeight: nil,
            timestamp: Date(),
            lastChecked: Date()
        )
        trackedTransactions.append(tx)
        
        // Start polling if not already running
        startPolling()
        
        // Immediately check this transaction
        Task {
            await checkTransaction(txid: txid, chainId: chainId)
        }
    }
    
    /// Stop tracking a transaction
    func stopTracking(txid: String) {
        trackedTransactions.removeAll { $0.id == txid }
        
        // Stop polling if no more transactions to track
        if trackedTransactions.isEmpty {
            stopPolling()
        }
    }
    
    /// Manually refresh all tracked transactions
    func refreshAll() async {
        for tx in trackedTransactions where tx.status != .confirmed {
            await checkTransaction(txid: tx.id, chainId: tx.chainId)
        }
    }
    
    /// Get transaction by ID
    func getTransaction(txid: String) -> TrackedTransaction? {
        trackedTransactions.first { $0.id == txid }
    }
    
    // MARK: - Polling
    
    private func startPolling() {
        guard pollingTask == nil else { return }
        
        isPolling = true
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollTransactions()
                try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
            }
        }
    }
    
    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
    }
    
    private func pollTransactions() async {
        let pendingTxs = trackedTransactions.filter { $0.status != .confirmed && $0.status != .failed }
        
        for tx in pendingTxs {
            await checkTransaction(txid: tx.id, chainId: tx.chainId)
        }
        
        lastPollTime = Date()
    }
    
    // MARK: - Chain-Specific Checks
    
    private func checkTransaction(txid: String, chainId: String) async {
        switch chainId {
        case "bitcoin", "bitcoin-testnet", "litecoin":
            await checkBitcoinTransaction(txid: txid, chainId: chainId)
        case "ethereum", "ethereum-sepolia", "bnb":
            await checkEVMTransaction(txid: txid, chainId: chainId)
        default:
            break
        }
    }
    
    private func checkBitcoinTransaction(txid: String, chainId: String) async {
        let baseURL: String
        switch chainId {
        case "bitcoin-testnet":
            baseURL = "https://mempool.space/testnet/api"
        case "litecoin":
            baseURL = "https://litecoinspace.org/api"
        default:
            baseURL = "https://mempool.space/api"
        }
        
        guard let url = URL(string: "\(baseURL)/tx/\(txid)") else { return }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else { return }
            
            if httpResponse.statusCode == 404 {
                // Transaction not found - might be dropped or not yet propagated
                updateTransaction(txid: txid) { tx in
                    if tx.timestamp.timeIntervalSinceNow < -600 { // 10 minutes
                        tx.status = .dropped
                    }
                    tx.lastChecked = Date()
                }
                return
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            
            // Check confirmation status
            let status = json["status"] as? [String: Any]
            let confirmed = status?["confirmed"] as? Bool ?? false
            let blockHeight = status?["block_height"] as? Int
            
            updateTransaction(txid: txid) { tx in
                if confirmed, let height = blockHeight {
                    tx.blockHeight = height
                    tx.status = .confirming
                    
                    // Calculate confirmations
                    Task { [weak self] in
                        if let currentHeight = await self?.fetchBitcoinBlockHeight(baseURL: baseURL) {
                            await MainActor.run {
                                self?.updateTransaction(txid: txid) { tx in
                                    tx.confirmations = currentHeight - height + 1
                                    if tx.isConfirmed {
                                        tx.status = .confirmed
                                    }
                                }
                            }
                        }
                    }
                } else {
                    tx.confirmations = 0
                    tx.status = .pending
                }
                tx.lastChecked = Date()
            }
            
        } catch {
            print("Error checking Bitcoin tx: \(error)")
        }
    }
    
    private func fetchBitcoinBlockHeight(baseURL: String) async -> Int? {
        guard let url = URL(string: "\(baseURL)/blocks/tip/height") else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let heightString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(heightString ?? "")
        } catch {
            return nil
        }
    }
    
    private func checkEVMTransaction(txid: String, chainId: String) async {
        let rpcEndpoints: [String]
        switch chainId {
        case "ethereum":
            rpcEndpoints = [
                "https://eth.llamarpc.com",
                "https://ethereum.publicnode.com",
                "https://rpc.ankr.com/eth"
            ]
        case "ethereum-sepolia":
            rpcEndpoints = [
                "https://ethereum-sepolia-rpc.publicnode.com",
                "https://sepolia.drpc.org",
                "https://1rpc.io/sepolia"
            ]
        case "bnb":
            rpcEndpoints = [
                "https://bsc-dataseed.binance.org",
                "https://bsc-dataseed1.defibit.io",
                "https://bsc-dataseed1.ninicoin.io"
            ]
        default:
            return
        }

        // 1) If any endpoint returns a receipt -> mined.
        for endpoint in rpcEndpoints {
            if let receipt = await fetchEVMReceipt(txid: txid, rpcURL: endpoint) {
                let blockNumberHex = receipt["blockNumber"] as? String ?? "0x0"
                let blockNumber = Int(blockNumberHex.dropFirst(2), radix: 16) ?? 0

                // If we can parse the nonce from the original transaction, we can
                // positively confirm/release it from the nonce manager.
                let confirmedNonce: UInt64? = await fetchEVMTxNonce(txid: txid, rpcURL: endpoint)

                let statusHex = receipt["status"] as? String ?? "0x1"
                let success = statusHex == "0x1"
                if !success {
                    updateTransaction(txid: txid) { tx in
                        tx.status = .failed
                        tx.lastChecked = Date()
                    }

                    if let confirmedNonce {
                        EVMNonceManager.shared.confirmNonce(confirmedNonce, chainId: chainId)
                    }
                    return
                }

                let currentBlock = await fetchEVMBlockNumber(rpcURL: endpoint)
                updateTransaction(txid: txid) { tx in
                    tx.blockHeight = blockNumber
                    if let current = currentBlock {
                        tx.confirmations = current - blockNumber + 1
                    }
                    tx.status = tx.isConfirmed ? .confirmed : .confirming
                    tx.lastChecked = Date()
                }

                if let confirmedNonce {
                    EVMNonceManager.shared.confirmNonce(confirmedNonce, chainId: chainId)
                }
                return
            }
        }

        // 2) No receipt. Determine if tx exists on any node.
        var visibleSomewhere = false
        for endpoint in rpcEndpoints {
            if await fetchEVMTxExists(txid: txid, rpcURL: endpoint) {
                visibleSomewhere = true
                break
            }
        }

        if visibleSomewhere {
            updateTransaction(txid: txid) { tx in
                tx.confirmations = 0
                tx.status = .pending
                tx.lastChecked = Date()
            }
            return
        }

        // 3) Not visible anywhere. This usually means: dropped/evicted or never propagated.
        // Attempt a best-effort rebroadcast if we have the raw tx cached or persisted.
        var rawTx: String? = TransactionBroadcaster.shared.getCachedRawTx(txid: txid)
        if rawTx == nil {
            // Chain mapping: this tracker passes chain ids like "ethereum" / "ethereum-sepolia" / "bnb".
            // If the tx was persisted from SendView, it should be stored under that chain id.
            if let data = try? await TransactionStore.shared.fetchRawData(txHash: txid, chainId: chainId),
               let s = String(data: data, encoding: .utf8) {
                rawTx = s
            }
        }

        if let rawTx {
            for endpoint in rpcEndpoints {
                // Fire and forget; if a node errors it will be ignored.
                _ = try? await TransactionBroadcaster.shared.rebroadcastRawEVM(rawTxHex: rawTx, rpcURL: endpoint)
            }
        }

        updateTransaction(txid: txid) { tx in
            tx.confirmations = 0
            // After ~10 minutes of being not-found, mark dropped.
            if tx.timestamp.timeIntervalSinceNow < -600 {
                tx.status = .dropped
            } else {
                tx.status = .pending
            }
            tx.lastChecked = Date()
        }
    }

    private func fetchEVMReceipt(txid: String, rpcURL: String) async -> [String: Any]? {
        guard let url = URL(string: rpcURL) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getTransactionReceipt",
            "params": [txid],
            "id": 1
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let result = json?["result"] as? [String: Any] { return result }
            return nil
        } catch {
            return nil
        }
    }

    /// Fetch the nonce of an EVM transaction if the node can see it.
    /// Returns nil if the tx is not found or the response can't be parsed.
    private func fetchEVMTxNonce(txid: String, rpcURL: String) async -> UInt64? {
        guard let url = URL(string: rpcURL) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 4

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getTransactionByHash",
            "params": [txid],
            "id": 1
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            guard let result = json["result"] as? [String: Any] else {
                return nil
            }
            guard let nonceHex = result["nonce"] as? String else {
                return nil
            }
            let cleaned = nonceHex.hasPrefix("0x") ? String(nonceHex.dropFirst(2)) : nonceHex
            return UInt64(cleaned, radix: 16)
        } catch {
            return nil
        }
    }

    private func fetchEVMTxExists(txid: String, rpcURL: String) async -> Bool {
        guard let url = URL(string: rpcURL) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 6

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getTransactionByHash",
            "params": [txid],
            "id": 1
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let result = json?["result"] {
                return !(result is NSNull)
            }
            return false
        } catch {
            return false
        }
    }
    
    private func fetchEVMBlockNumber(rpcURL: String) async -> Int? {
        guard let url = URL(string: rpcURL) else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_blockNumber",
            "params": [],
            "id": 1
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            guard let resultHex = json?["result"] as? String else { return nil }
            return Int(resultHex.dropFirst(2), radix: 16)
        } catch {
            return nil
        }
    }
    
    // MARK: - Helpers
    
    private func updateTransaction(txid: String, update: (inout TrackedTransaction) -> Void) {
        if let index = trackedTransactions.firstIndex(where: { $0.id == txid }) {
            update(&trackedTransactions[index])
        }
    }
}

// MARK: - Confirmation Progress View

import SwiftUI

struct ConfirmationProgressView: View {
    let transaction: TransactionConfirmationTracker.TrackedTransaction
    
    var body: some View {
        VStack(spacing: 8) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                
                Circle()
                    .trim(from: 0, to: transaction.confirmationProgress)
                    .stroke(progressColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: transaction.confirmationProgress)
                
                VStack(spacing: 2) {
                    Text("\(transaction.confirmations)")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text("/\(transaction.requiredConfirmations)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 60, height: 60)
            
            // Status text
            Text(transaction.status.rawValue)
                .font(.caption)
                .foregroundStyle(statusColor)
        }
    }
    
    private var progressColor: Color {
        switch transaction.status {
        case .pending: return .orange
        case .confirming: return .blue
        case .confirmed: return .green
        case .failed: return .red
        case .dropped: return .gray
        }
    }
    
    private var statusColor: Color {
        switch transaction.status {
        case .confirmed: return .green
        case .failed, .dropped: return .red
        default: return .primary
        }
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    VStack(spacing: 20) {
        ConfirmationProgressView(
            transaction: .init(
                id: "abc123",
                chainId: "bitcoin",
                confirmations: 2,
                status: .confirming,
                blockHeight: 800000,
                timestamp: Date(),
                lastChecked: Date()
            )
        )
        
        ConfirmationProgressView(
            transaction: .init(
                id: "def456",
                chainId: "bitcoin",
                confirmations: 6,
                status: .confirmed,
                blockHeight: 800000,
                timestamp: Date(),
                lastChecked: Date()
            )
        )
    }
    .padding()
}
#endif
#endif
#endif
