import Foundation
import SwiftUI

// MARK: - Node Management Service
// Persistent node configuration, health monitoring, and failover for all chains.

// ─────────────────────────── Data Model ───────────────────────────

enum NodeChain: String, CaseIterable, Identifiable, Codable, Sendable {
    case bitcoin       = "bitcoin"
    case ethereum      = "ethereum"
    case solana        = "solana"
    case litecoin      = "litecoin"
    case monero        = "monero"
    case bnb           = "bnb"
    case xrp           = "xrp"
    case polygon       = "polygon"
    case arbitrum      = "arbitrum"
    case optimism      = "optimism"
    case base          = "base"
    case avalanche     = "avalanche"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bitcoin:   return "Bitcoin"
        case .ethereum:  return "Ethereum"
        case .solana:    return "Solana"
        case .litecoin:  return "Litecoin"
        case .monero:    return "Monero"
        case .bnb:       return "BNB Chain"
        case .xrp:       return "XRP Ledger"
        case .polygon:   return "Polygon"
        case .arbitrum:  return "Arbitrum"
        case .optimism:  return "Optimism"
        case .base:      return "Base"
        case .avalanche: return "Avalanche"
        }
    }

    var symbol: String {
        switch self {
        case .bitcoin:   return "BTC"
        case .ethereum:  return "ETH"
        case .solana:    return "SOL"
        case .litecoin:  return "LTC"
        case .monero:    return "XMR"
        case .bnb:       return "BNB"
        case .xrp:       return "XRP"
        case .polygon:   return "MATIC"
        case .arbitrum:  return "ARB"
        case .optimism:  return "OP"
        case .base:      return "ETH"
        case .avalanche: return "AVAX"
        }
    }

    var icon: String {
        switch self {
        case .bitcoin:   return "bitcoinsign.circle"
        case .ethereum:  return "e.circle"
        case .solana:    return "s.circle"
        case .litecoin:  return "l.circle"
        case .monero:    return "m.circle"
        case .bnb:       return "b.circle"
        case .xrp:       return "x.circle"
        case .polygon:   return "p.circle"
        case .arbitrum:  return "a.circle"
        case .optimism:  return "o.circle"
        case .base:      return "b.circle"
        case .avalanche: return "a.circle"
        }
    }
}

enum NodeConnectionStatus: String, Codable, Sendable {
    case connected
    case disconnected
    case testing
    case error
}

struct NodeHealth: Codable, Sendable {
    var latencyMs: Int?
    var blockHeight: UInt64?
    var lastConnected: Date?
    var lastError: String?
    var status: NodeConnectionStatus
}

struct NodeConfiguration: Identifiable, Codable, Sendable {
    let id: UUID
    var chain: NodeChain
    var label: String
    var url: String
    var apiKey: String?
    var requiresAuth: Bool
    var authToken: String?
    var isDefault: Bool
    var isBuiltIn: Bool
    var health: NodeHealth

    init(
        id: UUID = UUID(),
        chain: NodeChain,
        label: String,
        url: String,
        apiKey: String? = nil,
        requiresAuth: Bool = false,
        authToken: String? = nil,
        isDefault: Bool = false,
        isBuiltIn: Bool = false,
        health: NodeHealth = NodeHealth(status: .disconnected)
    ) {
        self.id = id
        self.chain = chain
        self.label = label
        self.url = url
        self.apiKey = apiKey
        self.requiresAuth = requiresAuth
        self.authToken = authToken
        self.isDefault = isDefault
        self.isBuiltIn = isBuiltIn
        self.health = health
    }
}

struct FailoverEvent: Identifiable, Codable, Sendable {
    let id: UUID
    let chain: NodeChain
    let fromNodeLabel: String
    let toNodeLabel: String
    let reason: String
    let timestamp: Date

    init(chain: NodeChain, from: String, to: String, reason: String) {
        self.id = UUID()
        self.chain = chain
        self.fromNodeLabel = from
        self.toNodeLabel = to
        self.reason = reason
        self.timestamp = Date()
    }
}

// ─────────────────────────── Service ───────────────────────────

@MainActor
final class NodeManager: ObservableObject {
    static let shared = NodeManager()

    @Published var nodes: [NodeConfiguration] = []
    @Published var failoverEvents: [FailoverEvent] = []
    @AppStorage("hawala.autoFailover") var autoFailoverEnabled: Bool = true

    private let storageKey = "hawala.nodeConfigurations"
    private let failoverKey = "hawala.failoverEvents"

    /// Dedicated session with short timeouts for node testing
    private lazy var testSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 12
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private init() {
        loadNodes()
        if nodes.isEmpty {
            nodes = Self.defaultNodes()
        }
        loadFailoverEvents()
    }

    // MARK: - Persistence

    private func loadNodes() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            nodes = try JSONDecoder().decode([NodeConfiguration].self, from: data)
        } catch {
            print("⚠️ Failed to decode nodes: \(error)")
        }
    }

    func saveNodes() {
        do {
            let data = try JSONEncoder().encode(nodes)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("⚠️ Failed to encode nodes: \(error)")
        }
    }

    private func loadFailoverEvents() {
        guard let data = UserDefaults.standard.data(forKey: failoverKey) else { return }
        failoverEvents = (try? JSONDecoder().decode([FailoverEvent].self, from: data)) ?? []
    }

    private func saveFailoverEvents() {
        let data = try? JSONEncoder().encode(failoverEvents.suffix(100))
        UserDefaults.standard.set(data, forKey: failoverKey)
    }

    // MARK: - Node CRUD

    func nodes(for chain: NodeChain) -> [NodeConfiguration] {
        nodes.filter { $0.chain == chain }
    }

    func addNode(_ node: NodeConfiguration) {
        var newNode = node
        // If this is the first node for a chain, make it default
        if nodes(for: node.chain).isEmpty {
            newNode.isDefault = true
        }
        nodes.append(newNode)
        saveNodes()
    }

    func updateNode(_ node: NodeConfiguration) {
        guard let idx = nodes.firstIndex(where: { $0.id == node.id }) else { return }
        nodes[idx] = node
        saveNodes()
    }

    func deleteNode(_ node: NodeConfiguration) {
        let chainNodes = nodes(for: node.chain)
        // Cannot delete if it's the only node for this chain
        guard chainNodes.count > 1 else { return }

        nodes.removeAll { $0.id == node.id }

        // If we deleted the default, promote the first remaining
        if node.isDefault {
            if let idx = nodes.firstIndex(where: { $0.chain == node.chain }) {
                nodes[idx].isDefault = true
            }
        }
        saveNodes()
    }

    func canDeleteNode(_ node: NodeConfiguration) -> Bool {
        nodes(for: node.chain).count > 1
    }

    func setDefault(_ node: NodeConfiguration) {
        for i in nodes.indices {
            if nodes[i].chain == node.chain {
                nodes[i].isDefault = (nodes[i].id == node.id)
            }
        }
        saveNodes()
    }

    func defaultNode(for chain: NodeChain) -> NodeConfiguration? {
        nodes.first(where: { $0.chain == chain && $0.isDefault })
    }

    // MARK: - Connection Testing

    func testNode(_ nodeId: UUID) async {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        nodes[idx].health.status = .testing

        let node = nodes[idx]
        let start = CFAbsoluteTimeGetCurrent()

        do {
            let (status, blockHeight) = try await performNodeTest(url: node.url, chain: node.chain, apiKey: node.apiKey)
            let latency = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

            if let idx = nodes.firstIndex(where: { $0.id == nodeId }) {
                nodes[idx].health = NodeHealth(
                    latencyMs: latency,
                    blockHeight: blockHeight,
                    lastConnected: Date(),
                    lastError: nil,
                    status: status
                )
            }
        } catch {
            let latency = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            if let idx = nodes.firstIndex(where: { $0.id == nodeId }) {
                nodes[idx].health = NodeHealth(
                    latencyMs: latency > 10000 ? nil : latency,
                    blockHeight: nil,
                    lastConnected: nodes[idx].health.lastConnected,
                    lastError: describeError(error),
                    status: .error
                )
            }
        }
        saveNodes()
    }

    func testAllNodes(for chain: NodeChain) async {
        let chainNodes = nodes(for: chain)
        for node in chainNodes {
            await testNode(node.id)
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    // MARK: - Auto-Failover

    func performFailoverIfNeeded(for chain: NodeChain) async {
        guard autoFailoverEnabled else { return }
        guard let current = defaultNode(for: chain), current.health.status == .error else { return }

        let alternatives = nodes(for: chain).filter { $0.id != current.id && $0.health.status != .error }
        guard let best = alternatives.min(by: { ($0.health.latencyMs ?? 9999) < ($1.health.latencyMs ?? 9999) }) else { return }

        setDefault(best)

        let event = FailoverEvent(chain: chain, from: current.label, to: best.label, reason: current.health.lastError ?? "Connection failed")
        failoverEvents.insert(event, at: 0)
        saveFailoverEvents()
    }

    // MARK: - Network Testing Implementation

    private func performNodeTest(url urlStr: String, chain: NodeChain, apiKey: String?) async throws -> (NodeConnectionStatus, UInt64?) {
        guard let url = URL(string: urlStr) else {
            throw NodeTestError.invalidURL
        }

        switch chain {
        case .bitcoin, .litecoin:
            // Blockstream/Electrum-style REST API
            let infoURL = URL(string: urlStr.hasSuffix("/") ? "\(urlStr)blocks/tip/height" : "\(urlStr)/blocks/tip/height")!
            let (data, response) = try await testSession.data(from: infoURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw NodeTestError.httpError
            }
            let text = String(data: data, encoding: .utf8) ?? ""
            let height = UInt64(text.trimmingCharacters(in: .whitespacesAndNewlines))
            return (.connected, height)

        case .ethereum, .bnb, .polygon, .arbitrum, .optimism, .base, .avalanche:
            // JSON-RPC eth_blockNumber
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let key = apiKey, !key.isEmpty {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
            let payload: [String: Any] = ["jsonrpc": "2.0", "method": "eth_blockNumber", "params": [], "id": 1]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await testSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw NodeTestError.httpError
            }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? String {
                let hex = result.hasPrefix("0x") ? String(result.dropFirst(2)) : result
                let height = UInt64(hex, radix: 16)
                return (.connected, height)
            }
            return (.connected, nil)

        case .solana:
            // Solana JSON-RPC getBlockHeight
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "getBlockHeight", "params": []]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await testSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw NodeTestError.httpError
            }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? UInt64 {
                return (.connected, result)
            }
            return (.connected, nil)

        case .monero:
            // Monero daemon JSON RPC get_info
            let rpcURL = URL(string: urlStr.hasSuffix("/") ? "\(urlStr)json_rpc" : "\(urlStr)/json_rpc")!
            var request = URLRequest(url: rpcURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = ["jsonrpc": "2.0", "id": "0", "method": "get_info"]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await testSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw NodeTestError.httpError
            }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? [String: Any],
               let height = result["height"] as? UInt64 {
                return (.connected, height)
            }
            return (.connected, nil)

        case .xrp:
            // XRP Ledger server_info
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = ["method": "server_info", "params": [[:] as [String: Any]]]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await testSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw NodeTestError.httpError
            }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? [String: Any],
               let info = result["info"] as? [String: Any],
               let seq = info["validated_ledger"] as? [String: Any],
               let height = seq["seq"] as? UInt64 {
                return (.connected, height)
            }
            return (.connected, nil)
        }
    }

    private func describeError(_ error: Error) -> String {
        if let nodeErr = error as? NodeTestError {
            switch nodeErr {
            case .invalidURL: return "Invalid URL"
            case .httpError: return "Server returned error"
            case .timeout: return "Connection timed out"
            case .invalidResponse: return "Invalid response format"
            }
        }
        let desc = error.localizedDescription
        if desc.contains("timed out") || desc.contains("timeout") {
            return "Timeout after 10s"
        }
        if desc.contains("Could not connect") || desc.contains("not reachable") {
            return "Host unreachable"
        }
        if desc.contains("certificate") || desc.contains("SSL") {
            return "SSL/TLS error"
        }
        return desc.count > 60 ? String(desc.prefix(57)) + "..." : desc
    }

    // MARK: - Default Nodes

    static func defaultNodes() -> [NodeConfiguration] {
        let defaults: [(NodeChain, String, String)] = [
            (.bitcoin,   "Blockstream",          "https://blockstream.info/api"),
            (.ethereum,  "Public Ethereum",       "https://eth.llamarpc.com"),
            (.solana,    "Solana Mainnet",        "https://api.mainnet-beta.solana.com"),
            (.litecoin,  "Litecoinspace",         "https://litecoinspace.org/api"),
            (.monero,    "Monero Public",         "http://node.moneroworld.com:18089"),
            (.bnb,       "BNB Public RPC",        "https://bsc-dataseed.binance.org"),
            (.xrp,       "XRP Public",            "https://xrplcluster.com"),
            (.polygon,   "Polygon Public",        "https://polygon-rpc.com"),
            (.arbitrum,  "Arbitrum Public",        "https://arb1.arbitrum.io/rpc"),
            (.optimism,  "Optimism Public",        "https://mainnet.optimism.io"),
            (.base,      "Base Public",            "https://mainnet.base.org"),
            (.avalanche, "Avalanche Public",       "https://api.avax.network/ext/bc/C/rpc"),
        ]

        return defaults.map { chain, label, url in
            NodeConfiguration(
                chain: chain, label: label, url: url,
                isDefault: true, isBuiltIn: true,
                health: NodeHealth(status: .disconnected)
            )
        }
    }
}

// MARK: - Errors

enum NodeTestError: Error, LocalizedError {
    case invalidURL
    case httpError
    case timeout
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .httpError: return "Server returned error"
        case .timeout: return "Connection timed out"
        case .invalidResponse: return "Invalid response format"
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let openNodeManagement = Notification.Name("hawala.openNodeManagement")
}
