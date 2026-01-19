//
//  MessageSigner.swift
//  Hawala
//
//  Multi-chain Message Signing Implementation
//  Supports: Ethereum (EIP-191), Solana, Cosmos (ADR-036), Tezos
//

import Foundation
import RustBridge

// MARK: - Message Signature Types

/// Unified message signature result
public struct MessageSignature: Codable, Equatable {
    /// Full signature as hex string (with 0x prefix)
    public let signature: String
    
    /// R component (ECDSA only)
    public let r: String?
    
    /// S component (ECDSA only)
    public let s: String?
    
    /// Recovery ID / V value (ECDSA only)
    public let v: Int?
    
    /// Public key of signer (for chains that need it)
    public let publicKey: String?
    
    /// Base58 encoded signature (Tezos)
    public let signatureBase58: String?
    
    public init(signature: String, r: String? = nil, s: String? = nil, v: Int? = nil, publicKey: String? = nil, signatureBase58: String? = nil) {
        self.signature = signature
        self.r = r
        self.s = s
        self.v = v
        self.publicKey = publicKey
        self.signatureBase58 = signatureBase58
    }
}

/// Verification result
public struct VerificationResult: Codable {
    public let valid: Bool
    public let address: String?
    public let publicKey: String?
}

/// Message encoding type
public enum MessageEncoding: String, Codable {
    case utf8 = "utf8"
    case hex = "hex"
}

// MARK: - Message Signer Errors

public enum MessageSignerError: Error, LocalizedError {
    case invalidPrivateKey(String)
    case invalidSignature(String)
    case invalidMessage(String)
    case invalidAddress(String)
    case signingFailed(String)
    case verificationFailed(String)
    case recoveryFailed(String)
    case rustBridgeError(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidPrivateKey(let msg): return "Invalid private key: \(msg)"
        case .invalidSignature(let msg): return "Invalid signature: \(msg)"
        case .invalidMessage(let msg): return "Invalid message: \(msg)"
        case .invalidAddress(let msg): return "Invalid address: \(msg)"
        case .signingFailed(let msg): return "Signing failed: \(msg)"
        case .verificationFailed(let msg): return "Verification failed: \(msg)"
        case .recoveryFailed(let msg): return "Recovery failed: \(msg)"
        case .rustBridgeError(let msg): return "Rust bridge error: \(msg)"
        }
    }
}

// MARK: - Message Signer Protocol

public protocol MessageSignerProtocol {
    func signMessage(_ message: Data, privateKey: Data) async throws -> MessageSignature
    func verifyMessage(_ message: Data, signature: Data, address: String) async throws -> Bool
}

// MARK: - Ethereum Message Signer

/// Ethereum personal_sign (EIP-191) implementation
public final class EthereumMessageSigner: @unchecked Sendable {
    public static let shared = EthereumMessageSigner()
    
    private init() {}
    
    /// Sign a message using personal_sign (EIP-191)
    /// - Parameters:
    ///   - message: The message to sign (UTF-8 or hex encoded)
    ///   - privateKey: The 32-byte private key
    ///   - encoding: Message encoding (default: UTF-8)
    /// - Returns: The signature with r, s, v components
    public func signMessage(
        _ message: String,
        privateKey: Data,
        encoding: MessageEncoding = .utf8
    ) async throws -> MessageSignature {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request: [String: Any] = [
                        "message": message,
                        "privateKey": "0x" + privateKey.map { String(format: "%02x", $0) }.joined(),
                        "encoding": encoding.rawValue
                    ]
                    
                    guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
                          let jsonString = String(data: jsonData, encoding: .utf8) else {
                        continuation.resume(throwing: MessageSignerError.invalidMessage("Failed to serialize request"))
                        return
                    }
                    
                    guard let resultPtr = hawala_personal_sign(jsonString) else {
                        continuation.resume(throwing: MessageSignerError.rustBridgeError("Null response from Rust"))
                        return
                    }
                    
                    let resultString = String(cString: resultPtr)
                    hawala_free_string(UnsafeMutablePointer(mutating: resultPtr))
                    
                    guard let resultData = resultString.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any] else {
                        continuation.resume(throwing: MessageSignerError.rustBridgeError("Failed to parse response"))
                        return
                    }
                    
                    if let success = json["success"] as? Bool, success,
                       let data = json["data"] as? [String: Any] {
                        let signature = MessageSignature(
                            signature: data["signature"] as? String ?? "",
                            r: data["r"] as? String,
                            s: data["s"] as? String,
                            v: data["v"] as? Int
                        )
                        continuation.resume(returning: signature)
                    } else if let error = json["error"] as? [String: Any] {
                        let message = error["message"] as? String ?? "Unknown error"
                        continuation.resume(throwing: MessageSignerError.signingFailed(message))
                    } else {
                        continuation.resume(throwing: MessageSignerError.rustBridgeError("Invalid response format"))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Verify a personal_sign signature
    public func verifyMessage(
        _ message: String,
        signature: String,
        address: String,
        encoding: MessageEncoding = .utf8
    ) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request: [String: Any] = [
                    "message": message,
                    "signature": signature,
                    "address": address,
                    "encoding": encoding.rawValue
                ]
                
                guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
                      let jsonString = String(data: jsonData, encoding: .utf8) else {
                    continuation.resume(throwing: MessageSignerError.invalidMessage("Failed to serialize request"))
                    return
                }
                
                guard let resultPtr = hawala_personal_verify(jsonString) else {
                    continuation.resume(throwing: MessageSignerError.rustBridgeError("Null response from Rust"))
                    return
                }
                
                let resultString = String(cString: resultPtr)
                hawala_free_string(UnsafeMutablePointer(mutating: resultPtr))
                
                guard let resultData = resultString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any] else {
                    continuation.resume(throwing: MessageSignerError.rustBridgeError("Failed to parse response"))
                    return
                }
                
                if let success = json["success"] as? Bool, success,
                   let data = json["data"] as? [String: Any],
                   let valid = data["valid"] as? Bool {
                    continuation.resume(returning: valid)
                } else if let error = json["error"] as? [String: Any] {
                    let message = error["message"] as? String ?? "Unknown error"
                    continuation.resume(throwing: MessageSignerError.verificationFailed(message))
                } else {
                    continuation.resume(throwing: MessageSignerError.rustBridgeError("Invalid response format"))
                }
            }
        }
    }
    
    /// Recover the signer's address from a signature
    public func recoverAddress(
        from message: String,
        signature: String,
        encoding: MessageEncoding = .utf8
    ) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request: [String: Any] = [
                    "message": message,
                    "signature": signature,
                    "encoding": encoding.rawValue
                ]
                
                guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
                      let jsonString = String(data: jsonData, encoding: .utf8) else {
                    continuation.resume(throwing: MessageSignerError.invalidMessage("Failed to serialize request"))
                    return
                }
                
                guard let resultPtr = hawala_personal_recover(jsonString) else {
                    continuation.resume(throwing: MessageSignerError.rustBridgeError("Null response from Rust"))
                    return
                }
                
                let resultString = String(cString: resultPtr)
                hawala_free_string(UnsafeMutablePointer(mutating: resultPtr))
                
                guard let resultData = resultString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any] else {
                    continuation.resume(throwing: MessageSignerError.rustBridgeError("Failed to parse response"))
                    return
                }
                
                if let success = json["success"] as? Bool, success,
                   let data = json["data"] as? [String: Any],
                   let address = data["address"] as? String {
                    continuation.resume(returning: address)
                } else if let error = json["error"] as? [String: Any] {
                    let message = error["message"] as? String ?? "Unknown error"
                    continuation.resume(throwing: MessageSignerError.recoveryFailed(message))
                } else {
                    continuation.resume(throwing: MessageSignerError.rustBridgeError("Invalid response format"))
                }
            }
        }
    }
}

// MARK: - Solana Message Signer

/// Solana off-chain message signing (Ed25519)
public final class SolanaMessageSigner: @unchecked Sendable {
    public static let shared = SolanaMessageSigner()
    
    private init() {}
    
    /// Sign a message for Solana
    public func signMessage(
        _ message: String,
        privateKey: Data,
        encoding: MessageEncoding = .utf8
    ) async throws -> MessageSignature {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request: [String: Any] = [
                    "message": message,
                    "privateKey": "0x" + privateKey.map { String(format: "%02x", $0) }.joined(),
                    "encoding": encoding.rawValue
                ]
                
                guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
                      let jsonString = String(data: jsonData, encoding: .utf8) else {
                    continuation.resume(throwing: MessageSignerError.invalidMessage("Failed to serialize request"))
                    return
                }
                
                guard let resultPtr = hawala_solana_sign_message(jsonString) else {
                    continuation.resume(throwing: MessageSignerError.rustBridgeError("Null response from Rust"))
                    return
                }
                
                let resultString = String(cString: resultPtr)
                hawala_free_string(UnsafeMutablePointer(mutating: resultPtr))
                
                guard let resultData = resultString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any] else {
                    continuation.resume(throwing: MessageSignerError.rustBridgeError("Failed to parse response"))
                    return
                }
                
                if let success = json["success"] as? Bool, success,
                   let data = json["data"] as? [String: Any] {
                    let signature = MessageSignature(
                        signature: data["signature"] as? String ?? "",
                        publicKey: data["publicKey"] as? String
                    )
                    continuation.resume(returning: signature)
                } else if let error = json["error"] as? [String: Any] {
                    let message = error["message"] as? String ?? "Unknown error"
                    continuation.resume(throwing: MessageSignerError.signingFailed(message))
                } else {
                    continuation.resume(throwing: MessageSignerError.rustBridgeError("Invalid response format"))
                }
            }
        }
    }
    
    /// Verify a Solana message signature
    public func verifyMessage(
        _ message: String,
        signature: String,
        publicKey: String,
        encoding: MessageEncoding = .utf8
    ) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request: [String: Any] = [
                    "message": message,
                    "signature": signature,
                    "publicKey": publicKey,
                    "encoding": encoding.rawValue
                ]
                
                guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
                      let jsonString = String(data: jsonData, encoding: .utf8) else {
                    continuation.resume(throwing: MessageSignerError.invalidMessage("Failed to serialize request"))
                    return
                }
                
                guard let resultPtr = hawala_solana_verify_message(jsonString) else {
                    continuation.resume(throwing: MessageSignerError.rustBridgeError("Null response from Rust"))
                    return
                }
                
                let resultString = String(cString: resultPtr)
                hawala_free_string(UnsafeMutablePointer(mutating: resultPtr))
                
                guard let resultData = resultString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any] else {
                    continuation.resume(throwing: MessageSignerError.rustBridgeError("Failed to parse response"))
                    return
                }
                
                if let success = json["success"] as? Bool, success,
                   let data = json["data"] as? [String: Any],
                   let valid = data["valid"] as? Bool {
                    continuation.resume(returning: valid)
                } else if let error = json["error"] as? [String: Any] {
                    let message = error["message"] as? String ?? "Unknown error"
                    continuation.resume(throwing: MessageSignerError.verificationFailed(message))
                } else {
                    continuation.resume(throwing: MessageSignerError.rustBridgeError("Invalid response format"))
                }
            }
        }
    }
}

// MARK: - Cosmos Message Signer

/// Cosmos ADR-036 arbitrary message signing
public final class CosmosMessageSigner: @unchecked Sendable {
    public static let shared = CosmosMessageSigner()
    
    private init() {}
    
    /// Sign an arbitrary message for Cosmos (ADR-036)
    public func signArbitrary(
        _ message: String,
        signer: String,
        privateKey: Data,
        chainId: String? = nil
    ) async throws -> MessageSignature {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var request: [String: Any] = [
                    "message": message,
                    "signer": signer,
                    "privateKey": "0x" + privateKey.map { String(format: "%02x", $0) }.joined()
                ]
                
                if let chainId = chainId {
                    request["chainId"] = chainId
                }
                
                guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
                      let jsonString = String(data: jsonData, encoding: .utf8) else {
                    continuation.resume(throwing: MessageSignerError.invalidMessage("Failed to serialize request"))
                    return
                }
                
                guard let resultPtr = hawala_cosmos_sign_arbitrary(jsonString) else {
                    continuation.resume(throwing: MessageSignerError.rustBridgeError("Null response from Rust"))
                    return
                }
                
                let resultString = String(cString: resultPtr)
                hawala_free_string(UnsafeMutablePointer(mutating: resultPtr))
                
                guard let resultData = resultString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any] else {
                    continuation.resume(throwing: MessageSignerError.rustBridgeError("Failed to parse response"))
                    return
                }
                
                if let success = json["success"] as? Bool, success,
                   let data = json["data"] as? [String: Any] {
                    let signature = MessageSignature(
                        signature: data["signature"] as? String ?? "",
                        r: data["r"] as? String,
                        s: data["s"] as? String,
                        publicKey: data["publicKey"] as? String
                    )
                    continuation.resume(returning: signature)
                } else if let error = json["error"] as? [String: Any] {
                    let message = error["message"] as? String ?? "Unknown error"
                    continuation.resume(throwing: MessageSignerError.signingFailed(message))
                } else {
                    continuation.resume(throwing: MessageSignerError.rustBridgeError("Invalid response format"))
                }
            }
        }
    }
}

// MARK: - Tezos Message Signer

/// Tezos off-chain message signing
public final class TezosMessageSigner: @unchecked Sendable {
    public static let shared = TezosMessageSigner()
    
    private init() {}
    
    /// Sign a message for Tezos
    public func signMessage(
        _ message: String,
        dappUrl: String,
        privateKey: Data
    ) async throws -> MessageSignature {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request: [String: Any] = [
                    "message": message,
                    "dappUrl": dappUrl,
                    "privateKey": "0x" + privateKey.map { String(format: "%02x", $0) }.joined()
                ]
                
                guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
                      let jsonString = String(data: jsonData, encoding: .utf8) else {
                    continuation.resume(throwing: MessageSignerError.invalidMessage("Failed to serialize request"))
                    return
                }
                
                guard let resultPtr = hawala_tezos_sign_message(jsonString) else {
                    continuation.resume(throwing: MessageSignerError.rustBridgeError("Null response from Rust"))
                    return
                }
                
                let resultString = String(cString: resultPtr)
                hawala_free_string(UnsafeMutablePointer(mutating: resultPtr))
                
                guard let resultData = resultString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any] else {
                    continuation.resume(throwing: MessageSignerError.rustBridgeError("Failed to parse response"))
                    return
                }
                
                if let success = json["success"] as? Bool, success,
                   let data = json["data"] as? [String: Any] {
                    let signature = MessageSignature(
                        signature: data["signature"] as? String ?? "",
                        signatureBase58: data["signatureBase58"] as? String
                    )
                    continuation.resume(returning: signature)
                } else if let error = json["error"] as? [String: Any] {
                    let message = error["message"] as? String ?? "Unknown error"
                    continuation.resume(throwing: MessageSignerError.signingFailed(message))
                } else {
                    continuation.resume(throwing: MessageSignerError.rustBridgeError("Invalid response format"))
                }
            }
        }
    }
}

// MARK: - Unified Message Signer

/// Unified interface for multi-chain message signing
public final class UnifiedMessageSigner: @unchecked Sendable {
    public static let shared = UnifiedMessageSigner()
    
    public enum Chain {
        case ethereum
        case solana
        case cosmos(chainId: String?)
        case tezos(dappUrl: String)
    }
    
    private init() {}
    
    /// Sign a message for any supported chain
    public func signMessage(
        _ message: String,
        privateKey: Data,
        chain: Chain,
        signer: String? = nil
    ) async throws -> MessageSignature {
        switch chain {
        case .ethereum:
            return try await EthereumMessageSigner.shared.signMessage(message, privateKey: privateKey)
            
        case .solana:
            return try await SolanaMessageSigner.shared.signMessage(message, privateKey: privateKey)
            
        case .cosmos(let chainId):
            guard let signer = signer else {
                throw MessageSignerError.invalidAddress("Signer address required for Cosmos")
            }
            return try await CosmosMessageSigner.shared.signArbitrary(message, signer: signer, privateKey: privateKey, chainId: chainId)
            
        case .tezos(let dappUrl):
            return try await TezosMessageSigner.shared.signMessage(message, dappUrl: dappUrl, privateKey: privateKey)
        }
    }
}
