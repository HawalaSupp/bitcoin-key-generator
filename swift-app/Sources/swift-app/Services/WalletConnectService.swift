import Foundation
import CryptoKit

// MARK: - WalletConnect v2 Service

/// WalletConnect v2 integration for dApp connectivity
/// Implements the WalletConnect protocol for Ethereum and EVM-compatible chains
@MainActor
class WalletConnectService: ObservableObject {
    
    // MARK: - Published State
    
    @Published var sessions: [WCSession] = []
    @Published var pendingProposal: WCSessionProposal?
    @Published var pendingRequest: WCSessionRequest?
    @Published var isConnecting = false
    @Published var connectionError: String?
    
    // MARK: - Configuration
    
    private let projectId: String
    private let metadata: WCAppMetadata
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession
    private var reconnectTimer: Timer?
    private let maxReconnectAttempts = 5
    private var reconnectAttempts = 0
    
    // Relay URL for WalletConnect v2
    private let relayURL = "wss://relay.walletconnect.com"
    
    // MARK: - Supported Chains
    
    static let supportedChains: [WCChain] = [
        WCChain(id: "eip155:1", name: "Ethereum", symbol: "ETH"),
        WCChain(id: "eip155:11155111", name: "Ethereum Sepolia", symbol: "ETH"),
        WCChain(id: "eip155:56", name: "BNB Chain", symbol: "BNB"),
        WCChain(id: "eip155:137", name: "Polygon", symbol: "MATIC"),
        WCChain(id: "eip155:42161", name: "Arbitrum One", symbol: "ETH"),
        WCChain(id: "eip155:10", name: "Optimism", symbol: "ETH"),
        WCChain(id: "eip155:43114", name: "Avalanche C-Chain", symbol: "AVAX"),
    ]
    
    // MARK: - Supported Methods
    
    static let supportedMethods: [String] = [
        "eth_sendTransaction",
        "eth_signTransaction",
        "eth_sign",
        "personal_sign",
        "eth_signTypedData",
        "eth_signTypedData_v3",
        "eth_signTypedData_v4",
        "wallet_switchEthereumChain",
        "wallet_addEthereumChain",
    ]
    
    static let supportedEvents: [String] = [
        "chainChanged",
        "accountsChanged",
    ]
    
    // MARK: - Initialization
    
    init(projectId: String = "") {
        self.projectId = projectId.isEmpty ? APIConfig.walletConnectProjectId : projectId
        self.metadata = WCAppMetadata(
            name: "Hawala Wallet",
            description: "Secure self-custody crypto wallet",
            url: "https://hawala.app",
            icons: ["https://hawala.app/icon.png"]
        )
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.urlSession = URLSession(configuration: config)
        
        loadSavedSessions()
        
        // ROADMAP-09 E14: Auto-cleanup stale sessions on launch
        cleanupStaleSessions()
        
        if self.projectId.isEmpty {
            print("⚠️ WalletConnect: No project ID configured. Get one at https://cloud.walletconnect.com/")
        } else {
            print("🔗 WalletConnect: Initialized with project ID: \(self.projectId.prefix(8))...")
        }
    }
    
    // Default project ID (should be configured in production)
    private static var defaultProjectId: String {
        // In production, this should come from secure configuration
        return ProcessInfo.processInfo.environment["WALLETCONNECT_PROJECT_ID"] ?? ""
    }
    
    // MARK: - Session Management
    
    /// Parse a WalletConnect URI and initiate pairing
    func pair(uri: String) async throws {
        guard !uri.isEmpty else {
            throw WCError.invalidURI
        }
        
        // Parse WC URI: wc:topic@version?relay-protocol=irn&symKey=key
        guard let parsed = parseWCUri(uri) else {
            throw WCError.invalidURI
        }
        
        isConnecting = true
        connectionError = nil
        
        do {
            // Connect to relay
            try await connectToRelay(topic: parsed.topic, symKey: parsed.symKey)
            print("🔗 WalletConnect: Paired with topic \(parsed.topic.prefix(8))...")
        } catch {
            isConnecting = false
            connectionError = error.localizedDescription
            throw error
        }
    }
    
    /// Approve a session proposal
    func approveSession(proposal: WCSessionProposal, accounts: [String]) async throws {
        guard !accounts.isEmpty else {
            throw WCError.noAccountsProvided
        }
        
        // Build session namespaces
        let namespaces = buildNamespaces(from: proposal, accounts: accounts)
        
        let session = WCSession(
            topic: generateTopic(),
            pairingTopic: proposal.pairingTopic,
            peer: proposal.proposer,
            namespaces: namespaces,
            expiry: Date().addingTimeInterval(7 * 24 * 60 * 60), // 7 days
            acknowledged: true
        )
        
        sessions.append(session)
        saveSessions()
        pendingProposal = nil
        
        // Send approval response
        try await sendSessionApproval(proposal: proposal, session: session)
        
        print("✅ WalletConnect: Session approved for \(proposal.proposer.name)")
    }
    
    /// Reject a session proposal
    func rejectSession(proposal: WCSessionProposal, reason: String = "User rejected") async throws {
        // Send rejection response
        try await sendSessionRejection(proposal: proposal, reason: reason)
        pendingProposal = nil
        
        print("❌ WalletConnect: Session rejected for \(proposal.proposer.name)")
    }
    
    /// Disconnect a session
    func disconnect(session: WCSession) async throws {
        // Send disconnect message
        try await sendSessionDisconnect(session: session)
        
        sessions.removeAll { $0.topic == session.topic }
        saveSessions()
        
        print("🔌 WalletConnect: Disconnected from \(session.peer.name)")
    }
    
    /// Disconnect all sessions
    func disconnectAll() async {
        for session in sessions {
            try? await disconnect(session: session)
        }
        sessions = []
        saveSessions()
    }
    
    // MARK: - ROADMAP-09 E14: Stale Session Cleanup
    
    /// Remove sessions that have been idle for more than 7 days
    func cleanupStaleSessions() {
        let staleSessions = sessions.filter { $0.isStale }
        guard !staleSessions.isEmpty else { return }
        
        for stale in staleSessions {
            sessions.removeAll { $0.topic == stale.topic }
            print("🧹 WalletConnect: Auto-disconnected stale session with \(stale.peer.name) (idle since \(stale.lastActivityAt))")
        }
        saveSessions()
    }
    
    /// Update the last activity timestamp for a session (call on every request)
    func touchSession(topic: String) {
        if let index = sessions.firstIndex(where: { $0.topic == topic }) {
            sessions[index].lastActivityAt = Date()
            saveSessions()
        }
    }
    
    // MARK: - Request Handling
    
    /// Approve a session request (transaction/signing)
    func approveRequest(request: WCSessionRequest, result: String) async throws {
        try await sendRequestResponse(request: request, result: result)
        pendingRequest = nil
        
        print("✅ WalletConnect: Request approved - \(request.method)")
    }
    
    /// Reject a session request
    func rejectRequest(request: WCSessionRequest, reason: String = "User rejected") async throws {
        try await sendRequestRejection(request: request, reason: reason)
        pendingRequest = nil
        
        print("❌ WalletConnect: Request rejected - \(request.method)")
    }
    
    // MARK: - URI Parsing
    
    private struct ParsedURI {
        let topic: String
        let version: Int
        let symKey: String
        let relayProtocol: String
    }
    
    private func parseWCUri(_ uri: String) -> ParsedURI? {
        // Format: wc:topic@version?relay-protocol=irn&symKey=key
        guard uri.hasPrefix("wc:") else { return nil }
        
        let withoutPrefix = String(uri.dropFirst(3))
        let parts = withoutPrefix.split(separator: "@")
        guard parts.count == 2 else { return nil }
        
        let topic = String(parts[0])
        
        let versionAndParams = parts[1].split(separator: "?")
        guard versionAndParams.count == 2,
              let version = Int(versionAndParams[0]) else { return nil }
        
        var symKey = ""
        var relayProtocol = "irn"
        
        let params = versionAndParams[1].split(separator: "&")
        for param in params {
            let keyValue = param.split(separator: "=")
            guard keyValue.count == 2 else { continue }
            
            let key = String(keyValue[0])
            let value = String(keyValue[1])
            
            switch key {
            case "symKey":
                symKey = value
            case "relay-protocol":
                relayProtocol = value
            default:
                break
            }
        }
        
        guard !symKey.isEmpty else { return nil }
        
        return ParsedURI(
            topic: topic,
            version: version,
            symKey: symKey,
            relayProtocol: relayProtocol
        )
    }
    
    // MARK: - WebSocket Connection
    
    private func connectToRelay(topic: String, symKey: String) async throws {
        let urlString = "\(relayURL)?projectId=\(projectId)"
        guard let url = URL(string: urlString) else {
            throw WCError.invalidRelayURL
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        
        webSocket = urlSession.webSocketTask(with: request)
        webSocket?.resume()
        
        // Subscribe to topic
        try await subscribe(to: topic)
        
        // Start receiving messages
        receiveMessages()
    }
    
    private func subscribe(to topic: String) async throws {
        let subscribeMessage: [String: Any] = [
            "id": Int64(Date().timeIntervalSince1970 * 1000),
            "jsonrpc": "2.0",
            "method": "irn_subscribe",
            "params": [
                "topic": topic
            ]
        ]
        
        let data = try JSONSerialization.data(withJSONObject: subscribeMessage)
        let message = URLSessionWebSocketTask.Message.data(data)
        try await webSocket?.send(message)
    }
    
    private func receiveMessages() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                Task { @MainActor in
                    self.handleMessage(message)
                    self.receiveMessages() // Continue receiving
                }
            case .failure(let error):
                print("⚠️ WalletConnect WebSocket error: \(error.localizedDescription)")
                Task { @MainActor in
                    self.handleDisconnect()
                }
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseIncomingMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseIncomingMessage(text)
            }
        @unknown default:
            break
        }
    }
    
    private func parseIncomingMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        // Handle different message types
        if let method = json["method"] as? String {
            switch method {
            case "wc_sessionPropose":
                handleSessionProposal(json)
            case "wc_sessionRequest":
                handleSessionRequest(json)
            case "wc_sessionDelete":
                handleSessionDelete(json)
            default:
                print("📨 WalletConnect: Unknown method \(method)")
            }
        }
    }
    
    private func handleSessionProposal(_ json: [String: Any]) {
        guard let params = json["params"] as? [String: Any],
              let proposer = params["proposer"] as? [String: Any],
              let metadata = proposer["metadata"] as? [String: Any] else {
            return
        }
        
        let proposal = WCSessionProposal(
            id: json["id"] as? Int64 ?? 0,
            pairingTopic: params["pairingTopic"] as? String ?? "",
            proposer: WCPeer(
                publicKey: proposer["publicKey"] as? String ?? "",
                name: metadata["name"] as? String ?? "Unknown dApp",
                description: metadata["description"] as? String ?? "",
                url: metadata["url"] as? String ?? "",
                icons: metadata["icons"] as? [String] ?? []
            ),
            requiredNamespaces: parseNamespaces(params["requiredNamespaces"]),
            optionalNamespaces: parseNamespaces(params["optionalNamespaces"])
        )
        
        // Check dApp access (allowlist / blocklist)
        let accessDecision = DAppAccessManager.shared.checkAccess(peer: proposal.proposer)
        switch accessDecision {
        case .blocked(let reason):
            print("🚫 WalletConnect: Blocked proposal from \(proposal.proposer.name) — \(reason)")
            Task {
                try? await sendSessionRejection(proposal: proposal, reason: "dApp is blocked: \(reason)")
            }
            return
        case .allowed:
            print("✅ WalletConnect: Allowed dApp \(proposal.proposer.name)")
        case .unknown:
            print("⚠️ WalletConnect: Unknown dApp \(proposal.proposer.name) — showing proposal for review")
        }
        
        // Check dApp verification
        let verification = DAppRegistry.shared.verify(peer: proposal.proposer)
        switch verification {
        case .verified(let info):
            print("✅ WalletConnect: Verified dApp — \(info.name) (\(info.category.rawValue))")
        case .suspicious(let reason):
            print("⚠️ WalletConnect: Suspicious dApp — \(reason)")
        case .unknown:
            print("ℹ️ WalletConnect: Unverified dApp — \(proposal.proposer.url)")
        }
        
        pendingProposal = proposal
        print("📥 WalletConnect: Session proposal from \(proposal.proposer.name)")
    }
    
    private func handleSessionRequest(_ json: [String: Any]) {
        guard let params = json["params"] as? [String: Any],
              let request = params["request"] as? [String: Any] else {
            return
        }
        
        let sessionRequest = WCSessionRequest(
            id: json["id"] as? Int64 ?? 0,
            topic: params["topic"] as? String ?? "",
            chainId: params["chainId"] as? String ?? "",
            method: request["method"] as? String ?? "",
            params: request["params"]
        )
        
        // Rate limit check (10 req/min per dApp topic)
        Task {
            let allowed = await DAppRateLimiter.shared.recordRequest(topic: sessionRequest.topic)
            if !allowed {
                let waitTime = await DAppRateLimiter.shared.timeUntilNextSlot(for: sessionRequest.topic)
                print("🚦 WalletConnect: Rate limited request from topic \(sessionRequest.topic.prefix(8))... (wait \(Int(waitTime))s)")
                try? await sendRequestRejection(
                    request: sessionRequest,
                    reason: "Rate limited — too many requests. Try again in \(Int(waitTime)) seconds."
                )
                return
            }
            
            // Check dApp access for the session's peer
            if let session = sessions.first(where: { $0.topic == sessionRequest.topic }) {
                let accessDecision = DAppAccessManager.shared.checkAccess(peer: session.peer)
                if case .blocked(let reason) = accessDecision {
                    print("🚫 WalletConnect: Blocked request from \(session.peer.name) — \(reason)")
                    try? await sendRequestRejection(request: sessionRequest, reason: "dApp is blocked")
                    return
                }
            }
            
            pendingRequest = sessionRequest
            print("📥 WalletConnect: Request - \(sessionRequest.method)")
        }
    }
    
    private func handleSessionDelete(_ json: [String: Any]) {
        guard let params = json["params"] as? [String: Any],
              let topic = params["topic"] as? String else {
            return
        }
        
        sessions.removeAll { $0.topic == topic }
        saveSessions()
        print("🗑️ WalletConnect: Session deleted")
    }
    
    private func handleDisconnect() {
        isConnecting = false
        
        // Attempt reconnection
        if reconnectAttempts < maxReconnectAttempts {
            reconnectAttempts += 1
            reconnectTimer = Timer.scheduledTimer(withTimeInterval: Double(reconnectAttempts * 2), repeats: false) { [weak self] _ in
                Task {
                    // Reconnect logic
                }
            }
        }
    }
    
    // MARK: - Response Sending
    
    private func sendSessionApproval(proposal: WCSessionProposal, session: WCSession) async throws {
        let response: [String: Any] = [
            "id": proposal.id,
            "jsonrpc": "2.0",
            "result": [
                "relay": [
                    "protocol": "irn"
                ],
                "namespaces": encodeNamespaces(session.namespaces),
                "controller": [
                    "publicKey": generatePublicKey(),
                    "metadata": [
                        "name": metadata.name,
                        "description": metadata.description,
                        "url": metadata.url,
                        "icons": metadata.icons
                    ]
                ],
                "expiry": Int(session.expiry.timeIntervalSince1970)
            ]
        ]
        
        try await sendWebSocketMessage(response)
        isConnecting = false
        print("✅ WalletConnect: Session approval sent")
    }
    
    private func sendSessionRejection(proposal: WCSessionProposal, reason: String) async throws {
        let response: [String: Any] = [
            "id": proposal.id,
            "jsonrpc": "2.0",
            "error": [
                "code": 5000,
                "message": reason
            ]
        ]
        
        try await sendWebSocketMessage(response)
        isConnecting = false
        print("❌ WalletConnect: Session rejection sent - \(reason)")
    }
    
    private func sendSessionDisconnect(session: WCSession) async throws {
        let message: [String: Any] = [
            "id": Int64(Date().timeIntervalSince1970 * 1000),
            "jsonrpc": "2.0",
            "method": "wc_sessionDelete",
            "params": [
                "topic": session.topic,
                "reason": [
                    "code": 6000,
                    "message": "User disconnected"
                ]
            ]
        ]
        
        try await sendWebSocketMessage(message)
        print("🔌 WalletConnect: Disconnect message sent")
    }
    
    private func sendRequestResponse(request: WCSessionRequest, result: String) async throws {
        let response: [String: Any] = [
            "id": request.id,
            "jsonrpc": "2.0",
            "result": result
        ]
        
        try await sendWebSocketMessage(response)
        print("✅ WalletConnect: Request response sent for \(request.method)")
    }
    
    private func sendRequestRejection(request: WCSessionRequest, reason: String) async throws {
        let response: [String: Any] = [
            "id": request.id,
            "jsonrpc": "2.0",
            "error": [
                "code": 4001,
                "message": reason
            ]
        ]
        
        try await sendWebSocketMessage(response)
        print("❌ WalletConnect: Request rejection sent - \(reason)")
    }
    
    private func sendWebSocketMessage(_ message: [String: Any]) async throws {
        guard let webSocket = webSocket else {
            throw WCError.connectionFailed
        }
        
        let data = try JSONSerialization.data(withJSONObject: message)
        let wsMessage = URLSessionWebSocketTask.Message.data(data)
        try await webSocket.send(wsMessage)
    }
    
    private func encodeNamespaces(_ namespaces: [String: WCSessionNamespace]) -> [String: [String: Any]] {
        var result: [String: [String: Any]] = [:]
        for (key, ns) in namespaces {
            result[key] = [
                "accounts": ns.accounts,
                "methods": ns.methods,
                "events": ns.events,
                "chains": ns.chains
            ]
        }
        return result
    }
    
    private func generatePublicKey() -> String {
        // Generate a random 32-byte public key for session
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Helpers
    
    private func parseNamespaces(_ value: Any?) -> [String: WCNamespace] {
        guard let dict = value as? [String: [String: Any]] else { return [:] }
        
        var result: [String: WCNamespace] = [:]
        for (key, data) in dict {
            result[key] = WCNamespace(
                chains: data["chains"] as? [String] ?? [],
                methods: data["methods"] as? [String] ?? [],
                events: data["events"] as? [String] ?? []
            )
        }
        return result
    }
    
    private func buildNamespaces(from proposal: WCSessionProposal, accounts: [String]) -> [String: WCSessionNamespace] {
        var namespaces: [String: WCSessionNamespace] = [:]
        
        // Build EIP-155 namespace
        let chains = proposal.requiredNamespaces["eip155"]?.chains ?? Self.supportedChains.map { $0.id }
        let methods = proposal.requiredNamespaces["eip155"]?.methods ?? Self.supportedMethods
        let events = proposal.requiredNamespaces["eip155"]?.events ?? Self.supportedEvents
        
        // Format accounts as "eip155:chainId:address"
        var formattedAccounts: [String] = []
        for chain in chains {
            for account in accounts {
                formattedAccounts.append("\(chain):\(account)")
            }
        }
        
        namespaces["eip155"] = WCSessionNamespace(
            accounts: formattedAccounts,
            methods: methods,
            events: events,
            chains: chains
        )
        
        return namespaces
    }
    
    private func generateTopic() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Persistence
    
    private func saveSessions() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: "walletconnect_sessions")
        }
    }
    
    private func loadSavedSessions() {
        if let data = UserDefaults.standard.data(forKey: "walletconnect_sessions"),
           let saved = try? JSONDecoder().decode([WCSession].self, from: data) {
            sessions = saved.filter { $0.expiry > Date() }
        }
    }
}

// MARK: - Data Models

struct WCChain: Identifiable, Codable {
    let id: String
    let name: String
    let symbol: String
}

struct WCAppMetadata: Codable {
    let name: String
    let description: String
    let url: String
    let icons: [String]
}

struct WCPeer: Codable, Identifiable {
    var id: String { publicKey }
    let publicKey: String
    let name: String
    let description: String
    let url: String
    let icons: [String]
    
    var iconURL: URL? {
        icons.first.flatMap { URL(string: $0) }
    }
}

struct WCNamespace: Codable {
    let chains: [String]
    let methods: [String]
    let events: [String]
}

struct WCSessionNamespace: Codable {
    let accounts: [String]
    let methods: [String]
    let events: [String]
    let chains: [String]
}

struct WCSessionProposal: Identifiable, Equatable {
    let id: Int64
    let pairingTopic: String
    let proposer: WCPeer
    let requiredNamespaces: [String: WCNamespace]
    let optionalNamespaces: [String: WCNamespace]
    
    static func == (lhs: WCSessionProposal, rhs: WCSessionProposal) -> Bool {
        lhs.id == rhs.id
    }
}

struct WCSessionRequest: Identifiable, Equatable {
    let id: Int64
    let topic: String
    let chainId: String
    let method: String
    let params: Any?
    
    static func == (lhs: WCSessionRequest, rhs: WCSessionRequest) -> Bool {
        lhs.id == rhs.id
    }
    
    var methodDisplay: String {
        switch method {
        case "eth_sendTransaction": return "Send Transaction"
        case "eth_signTransaction": return "Sign Transaction"
        case "eth_sign": return "Sign Message"
        case "personal_sign": return "Sign Message"
        case "eth_signTypedData", "eth_signTypedData_v3", "eth_signTypedData_v4":
            return "Sign Typed Data"
        case "wallet_switchEthereumChain": return "Switch Network"
        case "wallet_addEthereumChain": return "Add Network"
        default: return method
        }
    }
}

struct WCSession: Identifiable, Codable {
    let topic: String
    let pairingTopic: String
    let peer: WCPeer
    let namespaces: [String: WCSessionNamespace]
    let expiry: Date
    let acknowledged: Bool
    /// ROADMAP-09 E14: Track last activity for stale session cleanup
    var lastActivityAt: Date
    
    var id: String { topic }
    
    var accounts: [String] {
        namespaces.values.flatMap { $0.accounts }
    }
    
    var chains: [String] {
        namespaces.values.flatMap { $0.chains }
    }
    
    /// ROADMAP-09 E14: Session is stale if idle for 7+ days
    var isStale: Bool {
        let staleDays: TimeInterval = 7 * 24 * 60 * 60 // 7 days
        return Date().timeIntervalSince(lastActivityAt) > staleDays
    }
    
    init(topic: String, pairingTopic: String, peer: WCPeer, namespaces: [String: WCSessionNamespace], expiry: Date, acknowledged: Bool, lastActivityAt: Date = Date()) {
        self.topic = topic
        self.pairingTopic = pairingTopic
        self.peer = peer
        self.namespaces = namespaces
        self.expiry = expiry
        self.acknowledged = acknowledged
        self.lastActivityAt = lastActivityAt
    }
}

// MARK: - Errors

enum WCError: LocalizedError, Equatable {
    case invalidURI
    case invalidRelayURL
    case connectionFailed
    case sessionNotFound
    case noAccountsProvided
    case requestTimeout
    case userRejected
    
    var errorDescription: String? {
        switch self {
        case .invalidURI: return "Invalid WalletConnect URI"
        case .invalidRelayURL: return "Invalid relay URL"
        case .connectionFailed: return "Failed to connect to relay"
        case .sessionNotFound: return "Session not found"
        case .noAccountsProvided: return "No accounts provided"
        case .requestTimeout: return "Request timed out"
        case .userRejected: return "User rejected the request"
        }
    }
}
