import Foundation
import Combine

// MARK: - WebSocket Price Models

/// Real-time price update from WebSocket
struct LivePriceUpdate: Equatable {
    let symbol: String      // e.g., "BTCUSDT"
    let price: Double
    let priceChange24h: Double?
    let priceChangePercent24h: Double?
    let high24h: Double?
    let low24h: Double?
    let volume24h: Double?
    let timestamp: Date
    
    /// Convert to chain ID (e.g., "bitcoin", "ethereum")
    var chainId: String? {
        switch symbol.uppercased() {
        case "BTCUSDT": return "bitcoin"
        case "ETHUSDT": return "ethereum"
        case "LTCUSDT": return "litecoin"
        case "SOLUSDT": return "solana"
        case "XRPUSDT": return "xrp"
        case "BNBUSDT": return "bnb"
        case "XMRUSDT": return "monero"
        default: return nil
        }
    }
}

/// WebSocket connection state
enum WebSocketState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case failed(String)
    
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
    
    var statusText: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Live"
        case .reconnecting(let attempt): return "Reconnecting (\(attempt))..."
        case .failed(let error): return "Failed: \(error)"
        }
    }
    
    var statusIcon: String {
        switch self {
        case .disconnected: return "wifi.slash"
        case .connecting, .reconnecting: return "arrow.triangle.2.circlepath"
        case .connected: return "bolt.fill"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

// MARK: - WebSocket Price Service

/// Real-time price updates via Binance WebSocket
@MainActor
class WebSocketPriceService: NSObject, ObservableObject {
    static let shared = WebSocketPriceService()
    
    // MARK: - Published Properties
    
    @Published private(set) var connectionState: WebSocketState = .disconnected
    @Published private(set) var prices: [String: LivePriceUpdate] = [:] // keyed by chainId
    @Published private(set) var lastUpdateTime: Date?
    
    // MARK: - Price Publishers
    
    /// Publisher for specific chain price updates
    var pricePublisher: AnyPublisher<LivePriceUpdate, Never> {
        priceSubject.eraseToAnyPublisher()
    }
    
    private let priceSubject = PassthroughSubject<LivePriceUpdate, Never>()
    
    // MARK: - Private Properties
    
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private let baseReconnectDelay: TimeInterval = 2.0
    
    // Binance WebSocket streams for supported coins
    private let streams = [
        "btcusdt@ticker",
        "ethusdt@ticker", 
        "ltcusdt@ticker",
        "solusdt@ticker",
        "xrpusdt@ticker",
        "bnbusdt@ticker",
        "xmrusdt@ticker"
    ]
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    // MARK: - Public Methods
    
    /// Start the WebSocket connection
    func connect() {
        guard connectionState != .connected && connectionState != .connecting else { return }
        
        connectionState = .connecting
        reconnectAttempts = 0
        
        Task { await establishConnection() }
    }
    
    /// Disconnect the WebSocket
    func disconnect() {
        reconnectTask?.cancel()
        pingTask?.cancel()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        connectionState = .disconnected
    }
    
    /// Get current price for a chain
    func price(for chainId: String) -> LivePriceUpdate? {
        prices[chainId]
    }
    
    /// Get formatted price string
    func formattedPrice(for chainId: String, currency: String = "USD") -> String? {
        guard let update = prices[chainId] else { return nil }
        return formatPrice(update.price)
    }
    
    /// Get price change percentage
    func priceChangePercent(for chainId: String) -> Double? {
        prices[chainId]?.priceChangePercent24h
    }
    
    // MARK: - Private Methods
    
    private func establishConnection() async {
        // Binance combined streams URL
        let streamList = streams.joined(separator: "/")
        let urlString = "wss://stream.binance.com:9443/stream?streams=\(streamList)"
        
        guard let url = URL(string: urlString) else {
            await MainActor.run {
                connectionState = .failed("Invalid WebSocket URL")
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        
        webSocket = urlSession.webSocketTask(with: request)
        webSocket?.resume()
        
        // Start receiving messages
        receiveMessage()
        
        // Start ping/pong to keep connection alive
        startPingTimer()
    }
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                
                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    // Continue receiving
                    self.receiveMessage()
                    
                case .failure(let error):
                    print("WebSocket receive error: \(error.localizedDescription)")
                    self.handleDisconnection()
                }
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseTickerMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseTickerMessage(text)
            }
        @unknown default:
            break
        }
    }
    
    private func parseTickerMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        
        do {
            // Binance combined stream format: {"stream":"btcusdt@ticker","data":{...}}
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tickerData = json["data"] as? [String: Any] {
                
                guard let symbol = tickerData["s"] as? String,
                      let priceStr = tickerData["c"] as? String,
                      let price = Double(priceStr) else {
                    return
                }
                
                let update = LivePriceUpdate(
                    symbol: symbol,
                    price: price,
                    priceChange24h: (tickerData["p"] as? String).flatMap { Double($0) },
                    priceChangePercent24h: (tickerData["P"] as? String).flatMap { Double($0) },
                    high24h: (tickerData["h"] as? String).flatMap { Double($0) },
                    low24h: (tickerData["l"] as? String).flatMap { Double($0) },
                    volume24h: (tickerData["v"] as? String).flatMap { Double($0) },
                    timestamp: Date()
                )
                
                if let chainId = update.chainId {
                    prices[chainId] = update
                    lastUpdateTime = Date()
                    priceSubject.send(update)
                    
                    // Update connection state on first successful message
                    if connectionState != .connected {
                        connectionState = .connected
                        reconnectAttempts = 0
                    }
                }
            }
        } catch {
            print("Failed to parse WebSocket message: \(error)")
        }
    }
    
    private func handleDisconnection() {
        webSocket = nil
        pingTask?.cancel()
        
        if reconnectAttempts < maxReconnectAttempts {
            reconnectAttempts += 1
            connectionState = .reconnecting(attempt: reconnectAttempts)
            
            // Exponential backoff
            let delay = baseReconnectDelay * pow(2.0, Double(reconnectAttempts - 1))
            
            reconnectTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await establishConnection()
            }
        } else {
            connectionState = .failed("Max reconnection attempts reached")
        }
    }
    
    private func startPingTimer() {
        pingTask?.cancel()
        pingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                guard !Task.isCancelled else { return }
                
                webSocket?.sendPing { [weak self] error in
                    if let error = error {
                        print("WebSocket ping failed: \(error.localizedDescription)")
                        Task { @MainActor in
                            self?.handleDisconnection()
                        }
                    }
                }
            }
        }
    }
    
    private func formatPrice(_ price: Double) -> String {
        if price >= 1000 {
            return String(format: "$%.2f", price)
        } else if price >= 1 {
            return String(format: "$%.4f", price)
        } else {
            return String(format: "$%.6f", price)
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketPriceService: URLSessionWebSocketDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor in
            print("WebSocket connected")
            connectionState = .connected
        }
    }
    
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor in
            print("WebSocket closed with code: \(closeCode)")
            handleDisconnection()
        }
    }
    
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            Task { @MainActor in
                print("WebSocket task error: \(error.localizedDescription)")
                handleDisconnection()
            }
        }
    }
}

// MARK: - Price Change Formatter

extension LivePriceUpdate {
    /// Formatted price change string with sign
    var formattedPriceChange: String? {
        guard let change = priceChange24h else { return nil }
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", change))"
    }
    
    /// Formatted percentage change string
    var formattedPercentChange: String? {
        guard let percent = priceChangePercent24h else { return nil }
        let sign = percent >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", percent))%"
    }
    
    /// Whether price is up or down
    var isPositive: Bool {
        (priceChangePercent24h ?? 0) >= 0
    }
}
