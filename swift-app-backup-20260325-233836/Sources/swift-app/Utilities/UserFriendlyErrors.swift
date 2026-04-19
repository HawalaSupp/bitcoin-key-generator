import Foundation

// MARK: - User-Friendly Error Messages

/// Converts technical errors into user-friendly messages
enum UserFriendlyError {
    
    /// Convert any error to a user-friendly message
    static func message(for error: Error) -> String {
        // Check for specific error types first
        if let urlError = error as? URLError {
            return urlErrorMessage(urlError)
        }
        
        if let decodingError = error as? DecodingError {
            return decodingErrorMessage(decodingError)
        }
        
        // Check error domain for common patterns
        let nsError = error as NSError
        
        switch nsError.domain {
        case NSURLErrorDomain:
            return urlErrorMessage(from: nsError.code)
        case NSCocoaErrorDomain:
            return cocoaErrorMessage(from: nsError.code)
        default:
            // Check for known error patterns in localized description
            return categorizeError(error.localizedDescription)
        }
    }
    
    // MARK: - URL Errors
    
    private static func urlErrorMessage(_ error: URLError) -> String {
        return urlErrorMessage(from: error.code.rawValue)
    }
    
    private static func urlErrorMessage(from code: Int) -> String {
        switch code {
        case NSURLErrorNotConnectedToInternet, -1009:
            return "No internet connection. Please check your network settings and try again."
        case NSURLErrorTimedOut, -1001:
            return "Request timed out. The server may be busy. Please try again."
        case NSURLErrorCannotFindHost, -1003:
            return "Could not reach the server. Please check your internet connection."
        case NSURLErrorCannotConnectToHost, -1004:
            return "Unable to connect to the server. Please try again later."
        case NSURLErrorNetworkConnectionLost, -1005:
            return "Network connection was lost. Please try again."
        case NSURLErrorSecureConnectionFailed, -1200:
            return "Secure connection failed. Please ensure you're on a trusted network."
        case NSURLErrorCancelled, -999:
            return "Request was cancelled."
        case NSURLErrorBadServerResponse, -1011:
            return "Server returned an unexpected response. Please try again."
        case NSURLErrorUserAuthenticationRequired, -1013:
            return "Authentication required. Please check your API credentials."
        case NSURLErrorResourceUnavailable, -1022:
            return "The requested resource is not available."
        default:
            return "Network error occurred. Please check your connection and try again."
        }
    }
    
    // MARK: - Decoding Errors
    
    private static func decodingErrorMessage(_ error: DecodingError) -> String {
        switch error {
        case .dataCorrupted:
            return "Received unexpected data format from the server."
        case .keyNotFound:
            return "Server response is missing expected information."
        case .typeMismatch:
            return "Server returned data in an unexpected format."
        case .valueNotFound:
            return "Server response is incomplete."
        @unknown default:
            return "Unable to process server response."
        }
    }
    
    // MARK: - Cocoa Errors
    
    private static func cocoaErrorMessage(from code: Int) -> String {
        switch code {
        case NSFileNoSuchFileError:
            return "File not found."
        case NSFileReadNoPermissionError:
            return "Permission denied. Unable to read file."
        case NSFileWriteNoPermissionError:
            return "Permission denied. Unable to save file."
        case NSFileWriteOutOfSpaceError:
            return "Not enough storage space available."
        case NSUserCancelledError:
            return "Operation was cancelled."
        default:
            return "An error occurred while accessing files."
        }
    }
    
    // MARK: - Error Pattern Matching
    
    private static func categorizeError(_ description: String) -> String {
        let lower = description.lowercased()
        
        // Network related
        if lower.contains("network") || lower.contains("connection") || lower.contains("offline") {
            return "Network error. Please check your internet connection."
        }
        
        // Authentication related
        if lower.contains("unauthorized") || lower.contains("401") || lower.contains("forbidden") || lower.contains("403") {
            return "Authentication failed. Please check your API keys in Settings."
        }
        
        // Rate limiting
        if lower.contains("rate limit") || lower.contains("too many requests") || lower.contains("429") {
            return "Too many requests. Please wait a moment and try again."
        }
        
        // Server errors
        if lower.contains("500") || lower.contains("502") || lower.contains("503") || lower.contains("server error") {
            return "Server is temporarily unavailable. Please try again later."
        }
        
        // Invalid address
        if lower.contains("invalid address") || lower.contains("bad address") {
            return "Invalid wallet address. Please check and try again."
        }
        
        // Insufficient funds
        if lower.contains("insufficient") || lower.contains("not enough") {
            return "Insufficient balance for this transaction."
        }
        
        // Gas/fee related
        if lower.contains("gas") || lower.contains("fee") {
            return "Transaction fee estimation failed. Please try again."
        }
        
        // Timeout
        if lower.contains("timeout") || lower.contains("timed out") {
            return "Request timed out. Please try again."
        }
        
        // JSON parsing
        if lower.contains("json") || lower.contains("parse") || lower.contains("decode") {
            return "Received unexpected data from server. Please try again."
        }
        
        // Keychain
        if lower.contains("keychain") {
            return "Unable to access secure storage. Please restart the app."
        }
        
        // Default: clean up the original message
        return cleanErrorMessage(description)
    }
    
    /// Clean up technical error messages for display
    private static func cleanErrorMessage(_ message: String) -> String {
        var cleaned = message
        
        // Remove common technical prefixes
        let prefixes = ["Error: ", "error: ", "NSError: ", "Error Domain="]
        for prefix in prefixes {
            if cleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
            }
        }
        
        // Truncate very long messages
        if cleaned.count > 150 {
            cleaned = String(cleaned.prefix(147)) + "..."
        }
        
        // Capitalize first letter
        if let first = cleaned.first {
            cleaned = first.uppercased() + String(cleaned.dropFirst())
        }
        
        // Ensure ends with period
        if !cleaned.hasSuffix(".") && !cleaned.hasSuffix("!") && !cleaned.hasSuffix("?") {
            cleaned += "."
        }
        
        return cleaned
    }
}

// MARK: - Error Extension

extension Error {
    /// Get a user-friendly version of this error message
    var userFriendlyMessage: String {
        UserFriendlyError.message(for: self)
    }
}
