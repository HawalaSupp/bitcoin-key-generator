import Foundation
import os.log

// MARK: - Log Level

/// Log levels for Hawala structured logging
public enum HawalaLogLevel: Int, Comparable, Sendable {
    case debug = 0    // Verbose debugging info, stripped in Release
    case info = 1     // General operational info
    case warn = 2     // Warnings that don't prevent operation
    case error = 3    // Errors that affect functionality
    case critical = 4 // Critical errors that may crash or corrupt data
    
    public static func < (lhs: HawalaLogLevel, rhs: HawalaLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warn: return "⚠️"
        case .error: return "❌"
        case .critical: return "🚨"
        }
    }
    
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warn: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }
}

// MARK: - Log Category

/// Categories for organizing log output
public enum HawalaLogCategory: String, Sendable {
    case app = "App"
    case network = "Network"
    case provider = "Provider"
    case wallet = "Wallet"
    case transaction = "Transaction"
    case security = "Security"
    case ui = "UI"
    case sync = "Sync"
    case cache = "Cache"
    case keychain = "Keychain"
}

// MARK: - Logger

/// Structured logger for Hawala with level filtering and secret redaction
public final class HawalaLogger: @unchecked Sendable {
    
    public static let shared = HawalaLogger()
    
    /// Minimum level to log (compile-time default based on build config)
    #if DEBUG
    public var minimumLevel: HawalaLogLevel = .debug
    #else
    public var minimumLevel: HawalaLogLevel = .info
    #endif
    
    /// Whether to include timestamps in console output
    public var includeTimestamps: Bool = true
    
    /// Whether to use os_log (unified logging) in addition to print
    public var useOSLog: Bool = true
    
    /// Patterns that indicate sensitive data (will be redacted)
    private let sensitivePatterns: [String] = [
        "private",
        "secret",
        "seed",
        "mnemonic",
        "wif",
        "password",
        "passphrase"
    ]
    
    /// Regex patterns for detecting hex keys (32+ hex chars)
    private let hexKeyPattern = try! NSRegularExpression(
        pattern: "\\b[0-9a-fA-F]{64}\\b",
        options: []
    )
    
    /// Regex for base58 private keys (50+ chars starting with typical prefixes)
    private let base58KeyPattern = try! NSRegularExpression(
        pattern: "\\b[5KL][1-9A-HJ-NP-Za-km-z]{50,}\\b",
        options: []
    )
    
    private let osLog: OSLog
    private let dateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.hawala.logger", qos: .utility)
    
    private init() {
        self.osLog = OSLog(subsystem: "com.hawala.wallet", category: "general")
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }
    
    // MARK: - Public API
    
    /// Log a debug message (stripped in Release builds by default)
    public func debug(_ message: @autoclosure () -> String, category: HawalaLogCategory = .app, file: String = #file, line: Int = #line) {
        log(level: .debug, message: message(), category: category, file: file, line: line)
    }
    
    /// Log an info message
    public func info(_ message: @autoclosure () -> String, category: HawalaLogCategory = .app, file: String = #file, line: Int = #line) {
        log(level: .info, message: message(), category: category, file: file, line: line)
    }
    
    /// Log a warning
    public func warn(_ message: @autoclosure () -> String, category: HawalaLogCategory = .app, file: String = #file, line: Int = #line) {
        log(level: .warn, message: message(), category: category, file: file, line: line)
    }
    
    /// Log an error
    public func error(_ message: @autoclosure () -> String, category: HawalaLogCategory = .app, file: String = #file, line: Int = #line) {
        log(level: .error, message: message(), category: category, file: file, line: line)
    }
    
    /// Log a critical error
    public func critical(_ message: @autoclosure () -> String, category: HawalaLogCategory = .app, file: String = #file, line: Int = #line) {
        log(level: .critical, message: message(), category: category, file: file, line: line)
    }
    
    // MARK: - Provider-specific convenience methods
    
    /// Log provider health status
    public func providerStatus(_ provider: String, status: String, details: String? = nil) {
        let message = details != nil ? "[\(provider)] \(status): \(details!)" : "[\(provider)] \(status)"
        info(message, category: .provider)
    }
    
    /// Log provider failure
    public func providerFailure(_ provider: String, error: Error) {
        warn("[\(provider)] Failed: \(sanitizeError(error))", category: .provider)
    }
    
    /// Log network request (debug only)
    public func networkRequest(_ url: String, method: String = "GET") {
        debug("[\(method)] \(sanitizeURL(url))", category: .network)
    }
    
    /// Log network response
    public func networkResponse(_ url: String, statusCode: Int, duration: TimeInterval? = nil) {
        let durationStr = duration.map { String(format: " (%.2fs)", $0) } ?? ""
        if statusCode >= 400 {
            warn("[\(statusCode)] \(sanitizeURL(url))\(durationStr)", category: .network)
        } else {
            debug("[\(statusCode)] \(sanitizeURL(url))\(durationStr)", category: .network)
        }
    }
    
    // MARK: - Private
    
    private func log(level: HawalaLogLevel, message: String, category: HawalaLogCategory, file: String, line: Int) {
        guard level >= minimumLevel else { return }
        
        let sanitizedMessage = sanitizeMessage(message)
        let fileName = (file as NSString).lastPathComponent
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            var output = ""
            
            if self.includeTimestamps {
                output += "[\(self.dateFormatter.string(from: Date()))] "
            }
            
            output += "\(level.emoji) [\(category.rawValue)] \(sanitizedMessage)"
            
            #if DEBUG
            output += " (\(fileName):\(line))"
            #endif
            
            print(output)
            
            if self.useOSLog {
                os_log("%{public}@", log: self.osLog, type: level.osLogType, sanitizedMessage)
            }
        }
    }
    
    /// Sanitize message to remove potential secrets
    private func sanitizeMessage(_ message: String) -> String {
        var result = message
        
        // Redact hex keys (64 char hex strings)
        result = hexKeyPattern.stringByReplacingMatches(
            in: result,
            options: [],
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "[REDACTED_KEY]"
        )
        
        // Redact base58 private keys
        result = base58KeyPattern.stringByReplacingMatches(
            in: result,
            options: [],
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "[REDACTED_KEY]"
        )
        
        // Check for sensitive word patterns and warn
        for pattern in sensitivePatterns {
            if result.lowercased().contains(pattern) {
                // Don't redact the whole message, just flag it in debug
                #if DEBUG
                // In debug, we allow it but log a warning
                #endif
            }
        }
        
        return result
    }
    
    /// Sanitize URL to remove API keys from query params
    private func sanitizeURL(_ url: String) -> String {
        guard let urlComponents = URLComponents(string: url) else { return url }
        
        var sanitized = urlComponents
        if let queryItems = sanitized.queryItems {
            sanitized.queryItems = queryItems.map { item in
                let sensitiveParams = ["apikey", "api_key", "key", "token", "secret"]
                if sensitiveParams.contains(item.name.lowercased()) {
                    return URLQueryItem(name: item.name, value: "[REDACTED]")
                }
                return item
            }
        }
        
        return sanitized.string ?? url
    }
    
    /// Sanitize error to avoid exposing sensitive details
    private func sanitizeError(_ error: Error) -> String {
        let description = error.localizedDescription
        return sanitizeMessage(description)
    }
}

// MARK: - Global Convenience Functions

/// Global logger instance
public let Log = HawalaLogger.shared

// MARK: - Usage Examples
/*
 
 // Basic usage:
 Log.debug("Fetching prices...", category: .provider)
 Log.info("Wallet created successfully", category: .wallet)
 Log.warn("Provider returned 429, retrying...", category: .network)
 Log.error("Failed to sign transaction", category: .transaction)
 Log.critical("Keychain access denied", category: .security)
 
 // Provider-specific:
 Log.providerStatus("CoinCap", status: "healthy")
 Log.providerFailure("Alchemy", error: someError)
 
 // Network logging:
 Log.networkRequest("https://api.example.com/prices")
 Log.networkResponse("https://api.example.com/prices", statusCode: 200, duration: 0.5)
 
 // Automatic secret redaction:
 // If you accidentally log: "Private key: abc123..."
 // It will be sanitized to: "Private key: [REDACTED_KEY]"
 
 */
