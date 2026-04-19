import Foundation

// MARK: - Debug Logger
/// A simple logger that captures app events for debugging purposes

@MainActor
final class DebugLogger: ObservableObject {
    static let shared = DebugLogger()
    
    /// Maximum number of log entries to keep
    private let maxEntries = 200
    
    /// Log entries
    @Published var entries: [LogEntry] = []
    
    /// Network latency tracking
    @Published var networkLatencies: [String: TimeInterval] = [:]
    
    /// Last WebSocket connection time
    @Published var lastWebSocketConnect: Date?
    
    /// WebSocket status
    @Published var webSocketStatus: String = "Disconnected"
    
    private init() {}
    
    // MARK: - Logging
    
    func log(_ message: String, level: LogLevel = .info, category: LogCategory = .general) {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message
        )
        
        entries.append(entry)
        
        // Trim old entries
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        
        // Also print to console
        print("[\(level.rawValue.uppercased())] [\(category.rawValue)] \(message)")
    }
    
    func logNetwork(_ endpoint: String, latency: TimeInterval, success: Bool) {
        networkLatencies[endpoint] = latency
        let status = success ? "✓" : "✗"
        log("\(status) \(endpoint): \(String(format: "%.0fms", latency * 1000))", 
            level: success ? .info : .error, 
            category: .network)
    }
    
    func logWebSocket(status: String) {
        webSocketStatus = status
        if status == "Connected" {
            lastWebSocketConnect = Date()
        }
        log("WebSocket: \(status)", level: .info, category: .network)
    }
    
    func clear() {
        entries.removeAll()
        networkLatencies.removeAll()
    }
    
    // MARK: - Stats
    
    var averageLatency: TimeInterval? {
        guard !networkLatencies.isEmpty else { return nil }
        let sum = networkLatencies.values.reduce(0, +)
        return sum / Double(networkLatencies.count)
    }
    
    var latencyDescription: String {
        if let avg = averageLatency {
            return String(format: "%.0fms avg", avg * 1000)
        }
        return "No data"
    }
}

// MARK: - Log Entry

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let category: LogCategory
    let message: String
    
    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

enum LogLevel: String {
    case debug = "debug"
    case info = "info"
    case warning = "warning"
    case error = "error"
    
    var color: String {
        switch self {
        case .debug: return "gray"
        case .info: return "blue"
        case .warning: return "orange"
        case .error: return "red"
        }
    }
}

enum LogCategory: String {
    case general = "general"
    case network = "network"
    case wallet = "wallet"
    case transaction = "transaction"
    case security = "security"
}
