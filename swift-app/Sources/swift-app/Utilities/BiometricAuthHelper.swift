import Foundation
import LocalAuthentication

/// Helper for biometric authentication on sensitive actions
enum BiometricAuthHelper {
    
    /// Result of a biometric authentication attempt
    enum AuthResult {
        case success
        case cancelled
        case failed(String)
        case notAvailable
    }
    
    /// Available biometric type on this device
    enum BiometricType {
        case touchID
        case faceID
        case opticID
        case none
        
        var displayName: String {
            switch self {
            case .touchID: return "Touch ID"
            case .faceID: return "Face ID"
            case .opticID: return "Optic ID"
            case .none: return "Biometrics"
            }
        }
        
        var iconName: String {
            switch self {
            case .touchID: return "touchid"
            case .faceID: return "faceid"
            case .opticID: return "opticid"
            case .none: return "lock.shield"
            }
        }
    }
    
    /// Get the available biometric type on this device
    static var availableBiometricType: BiometricType {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        
        switch context.biometryType {
        case .touchID:
            return .touchID
        case .faceID:
            return .faceID
        case .opticID:
            return .opticID
        case .none:
            return .none
        @unknown default:
            return .none
        }
    }
    
    /// Check if biometrics are available
    static var isBiometricAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    /// Authenticate using biometrics
    /// - Parameters:
    ///   - reason: The reason shown to the user for why authentication is needed
    ///   - completion: Called with the authentication result
    static func authenticate(reason: String, completion: @escaping @Sendable (AuthResult) -> Void) {
        let context = LAContext()
        context.localizedFallbackTitle = "" // Hide "Enter Password" fallback
        context.localizedCancelTitle = "Cancel"
        
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            completion(.notAvailable)
            return
        }
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authError in
            DispatchQueue.main.async {
                if success {
                    completion(.success)
                } else if let error = authError as? LAError {
                    switch error.code {
                    case .userCancel, .appCancel, .systemCancel:
                        completion(.cancelled)
                    case .biometryNotAvailable, .biometryNotEnrolled:
                        completion(.notAvailable)
                    default:
                        completion(.failed(error.localizedDescription))
                    }
                } else {
                    completion(.failed(authError?.localizedDescription ?? "Authentication failed"))
                }
            }
        }
    }
    
    /// Authenticate using biometrics (async version)
    /// - Parameter reason: The reason shown to the user for why authentication is needed
    /// - Returns: The authentication result
    @MainActor
    static func authenticate(reason: String) async -> AuthResult {
        await withCheckedContinuation { continuation in
            authenticate(reason: reason) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Convenience method to check if user should be prompted for biometric
    /// Returns true if biometrics are available and the user hasn't disabled them
    static func shouldRequireBiometric(settingEnabled: Bool) -> Bool {
        return settingEnabled && isBiometricAvailable
    }
}
