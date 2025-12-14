import Foundation

// MARK: - User-Friendly Error Messages

/// Centralized error message handling for user-facing copy
public enum UserFacingError {
    
    // MARK: - Network Errors
    
    public enum Network {
        public static let noConnection = "No internet connection. Please check your network and try again."
        public static let timeout = "Request timed out. Please try again."
        public static let serverUnreachable = "Unable to reach server. Please try again later."
        public static let serverError = "Server is experiencing issues. Please try again later."
        public static let rateLimited = "Too many requests. Please wait a moment and try again."
        public static let cancelled = "Request was cancelled."
    }
    
    // MARK: - Provider Errors
    
    public enum Provider {
        public static let priceUnavailable = "Market data temporarily unavailable."
        public static let balanceUnavailable = "Balance information temporarily unavailable."
        public static let historyUnavailable = "Transaction history temporarily unavailable."
        public static let allOffline = "All data providers are currently unavailable."
        public static let partialData = "Some data may be outdated or unavailable."
        public static let apiKeyMissing = "API key not configured. Add it in Settings."
        public static let networkNotEnabled = "This network is not enabled. Enable it in Settings."
    }
    
    // MARK: - Transaction Errors
    
    public enum Transaction {
        public static let insufficientFunds = "Insufficient funds for this transaction."
        public static let invalidAddress = "The recipient address is invalid."
        public static let invalidAmount = "Please enter a valid amount."
        public static let feeTooLow = "Transaction fee may be too low for timely confirmation."
        public static let feeTooHigh = "Transaction fee seems unusually high. Please verify."
        public static let broadcastFailed = "Failed to broadcast transaction. Please try again."
        public static let signatureFailed = "Failed to sign transaction. Please try again."
        public static let nonceTooLow = "Transaction nonce conflict. Please wait and try again."
    }
    
    // MARK: - Wallet Errors
    
    public enum Wallet {
        public static let createFailed = "Failed to create wallet. Please try again."
        public static let importFailed = "Failed to import wallet. Please check your seed phrase."
        public static let backupFailed = "Failed to create backup. Please try again."
        public static let restoreFailed = "Failed to restore wallet. Please verify your backup."
        public static let keychainError = "Unable to access secure storage. Please restart the app."
        public static let invalidSeed = "Invalid seed phrase. Please check and try again."
        public static let invalidPassphrase = "Invalid passphrase format."
    }
    
    // MARK: - Security Errors
    
    public enum Security {
        public static let authFailed = "Authentication failed. Please try again."
        public static let biometricUnavailable = "Biometric authentication not available."
        public static let biometricFailed = "Biometric authentication failed. Please try again or use your passcode."
        public static let sessionExpired = "Your session has expired. Please authenticate again."
    }
    
    // MARK: - Generic
    
    public static let generic = "Something went wrong. Please try again."
    public static let tryAgain = "Please try again."
    public static let contactSupport = "If this problem persists, please contact support."
}

// MARK: - Error Mapper

/// Maps technical errors to user-friendly messages
public struct ErrorMessageMapper {
    
    /// Convert any Error to a user-friendly message
    public static func userMessage(for error: Error) -> String {
        let description = error.localizedDescription.lowercased()
        
        // Network errors
        if description.contains("could not be found") || 
           description.contains("dns") ||
           description.contains("no such host") {
            return UserFacingError.Network.serverUnreachable
        }
        
        if description.contains("timed out") || description.contains("timeout") {
            return UserFacingError.Network.timeout
        }
        
        if description.contains("internet") || 
           description.contains("network") ||
           description.contains("not connected") ||
           description.contains("offline") {
            return UserFacingError.Network.noConnection
        }
        
        if description.contains("cancelled") || description.contains("canceled") {
            return UserFacingError.Network.cancelled
        }
        
        // HTTP status codes
        if description.contains("401") || description.contains("unauthorized") {
            return UserFacingError.Provider.apiKeyMissing
        }
        
        if description.contains("403") {
            if description.contains("not enabled") {
                return UserFacingError.Provider.networkNotEnabled
            }
            return UserFacingError.Provider.apiKeyMissing
        }
        
        if description.contains("429") || description.contains("rate limit") {
            return UserFacingError.Network.rateLimited
        }
        
        if description.contains("500") || 
           description.contains("502") || 
           description.contains("503") ||
           description.contains("server error") {
            return UserFacingError.Network.serverError
        }
        
        // Transaction errors
        if description.contains("insufficient") {
            return UserFacingError.Transaction.insufficientFunds
        }
        
        if description.contains("invalid address") {
            return UserFacingError.Transaction.invalidAddress
        }
        
        if description.contains("nonce") {
            return UserFacingError.Transaction.nonceTooLow
        }
        
        // Keychain errors
        if description.contains("keychain") || description.contains("security") {
            return UserFacingError.Wallet.keychainError
        }
        
        // Default
        return UserFacingError.generic
    }
    
    /// Convert HTTP status code to user-friendly message
    public static func userMessage(forStatusCode code: Int) -> String {
        switch code {
        case 401:
            return UserFacingError.Provider.apiKeyMissing
        case 403:
            return UserFacingError.Provider.networkNotEnabled
        case 429:
            return UserFacingError.Network.rateLimited
        case 500...599:
            return UserFacingError.Network.serverError
        default:
            return UserFacingError.generic
        }
    }
    
    /// Get a retry suggestion based on error type
    public static func retrySuggestion(for error: Error) -> String? {
        let description = error.localizedDescription.lowercased()
        
        if description.contains("rate limit") || description.contains("429") {
            return "Wait a moment before trying again."
        }
        
        if description.contains("network") || description.contains("internet") {
            return "Check your internet connection and try again."
        }
        
        if description.contains("timeout") {
            return "The request took too long. Try again with a better connection."
        }
        
        if description.contains("403") && description.contains("not enabled") {
            return "Go to Settings to enable this network."
        }
        
        return nil
    }
}

// MARK: - Error Alert Builder

/// Builds user-friendly error alerts
public struct ErrorAlertBuilder {
    
    public struct AlertContent {
        public let title: String
        public let message: String
        public let primaryAction: String
        public let secondaryAction: String?
        public let showSettings: Bool
    }
    
    /// Build alert content for an error
    public static func alertContent(for error: Error, context: String? = nil) -> AlertContent {
        let userMessage = ErrorMessageMapper.userMessage(for: error)
        let suggestion = ErrorMessageMapper.retrySuggestion(for: error)
        
        var message = userMessage
        if let suggestion = suggestion {
            message += "\n\n\(suggestion)"
        }
        
        let description = error.localizedDescription.lowercased()
        let showSettings = description.contains("403") || 
                          description.contains("not enabled") ||
                          description.contains("api key")
        
        return AlertContent(
            title: context ?? "Error",
            message: message,
            primaryAction: "OK",
            secondaryAction: showSettings ? "Open Settings" : nil,
            showSettings: showSettings
        )
    }
    
    /// Build alert content for provider failures
    public static func providerFailureAlert(providers: [String]) -> AlertContent {
        let title = providers.count == 1 ? "Provider Unavailable" : "Providers Unavailable"
        let providerList = providers.joined(separator: ", ")
        
        return AlertContent(
            title: title,
            message: "\(providerList) \(providers.count == 1 ? "is" : "are") currently unavailable. Using cached data where possible.",
            primaryAction: "OK",
            secondaryAction: "Retry",
            showSettings: false
        )
    }
}
