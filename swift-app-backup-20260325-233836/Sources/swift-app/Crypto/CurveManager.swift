//
//  CurveManager.swift
//  Hawala
//
//  Multi-Curve Cryptography Support
//  Supports: secp256k1, ed25519, sr25519, secp256r1
//

import Foundation
import RustBridge

// MARK: - Curve Types

/// Supported elliptic curve types
public enum CurveType: String, Codable, CaseIterable, Sendable {
    case secp256k1 = "secp256k1"
    case ed25519 = "ed25519"
    case sr25519 = "sr25519"
    case secp256r1 = "secp256r1"
    
    public var displayName: String {
        switch self {
        case .secp256k1: return "secp256k1 (Bitcoin/Ethereum)"
        case .ed25519: return "Ed25519 (Solana/Stellar)"
        case .sr25519: return "Sr25519 (Polkadot)"
        case .secp256r1: return "P-256/NIST (NEO)"
        }
    }
    
    public var supportedChains: [String] {
        switch self {
        case .secp256k1: return ["bitcoin", "ethereum", "bnb", "litecoin", "dogecoin", "tron"]
        case .ed25519: return ["solana", "stellar", "cardano", "ton", "near", "aptos", "sui", "algorand"]
        case .sr25519: return ["polkadot", "kusama"]
        case .secp256r1: return ["neo"]
        }
    }
}

// MARK: - Result Types

/// Generated keypair result
public struct CurveKeypair: Codable, Sendable {
    public let privateKey: String
    public let publicKey: String
    public let curve: String
    
    enum CodingKeys: String, CodingKey {
        case privateKey = "private_key"
        case publicKey = "public_key"
        case curve
    }
}

/// Signature result
public struct CurveSignature: Codable, Sendable {
    public let signature: String
    public let publicKey: String
    public let curve: String
    
    enum CodingKeys: String, CodingKey {
        case signature
        case publicKey = "public_key"
        case curve
    }
}

/// Verification result
public struct CurveVerification: Codable, Sendable {
    public let valid: Bool
    public let curve: String
}

/// Curve information
public struct CurveInfo: Codable, Sendable {
    public let name: String
    public let privateKeySize: Int
    public let publicKeySize: Int
    public let signatureSize: Int
    public let chains: [String]
    
    enum CodingKeys: String, CodingKey {
        case name
        case privateKeySize = "private_key_size"
        case publicKeySize = "public_key_size"
        case signatureSize = "signature_size"
        case chains
    }
}

// MARK: - FFI Response Types

private struct CurveFFIResponse<D: Codable>: Codable {
    let success: Bool
    let data: D?
    let error: CurveFFIError?
}

private struct CurveFFIError: Codable {
    let code: String
    let message: String
}

// MARK: - Curve Manager

/// Manager for multi-curve cryptographic operations
public final class CurveManager: @unchecked Sendable {
    public static let shared = CurveManager()
    
    private init() {}
    
    // MARK: - FFI Helpers
    
    private func callFFI<T: Codable>(_ ffiCall: (UnsafePointer<CChar>?) -> UnsafePointer<CChar>?, input: some Encodable) throws -> T {
        let encoder = JSONEncoder()
        let inputData = try encoder.encode(input)
        guard let inputString = String(data: inputData, encoding: .utf8) else {
            throw CurveError.encodingFailed
        }
        
        guard let resultPtr = inputString.withCString({ ffiCall($0) }) else {
            throw CurveError.ffiCallFailed
        }
        defer { hawala_free_string(UnsafeMutablePointer(mutating: resultPtr)) }
        
        let resultString = String(cString: resultPtr)
        guard let resultData = resultString.data(using: .utf8) else {
            throw CurveError.decodingFailed
        }
        
        let decoder = JSONDecoder()
        let response = try decoder.decode(CurveFFIResponse<T>.self, from: resultData)
        
        if !response.success {
            throw CurveError.rustError(response.error?.message ?? "Unknown error")
        }
        
        guard let data = response.data else {
            throw CurveError.noData
        }
        
        return data
    }
    
    // MARK: - Key Generation
    
    /// Generate a keypair for the specified curve
    /// - Parameters:
    ///   - curve: The elliptic curve to use
    ///   - seed: 32-byte seed (hex-encoded with 0x prefix)
    /// - Returns: Generated keypair
    public func generateKeypair(curve: CurveType, seed: Data) throws -> CurveKeypair {
        struct Request: Encodable {
            let curve: String
            let seed: String
        }
        
        let request = Request(
            curve: curve.rawValue,
            seed: "0x" + seed.map { String(format: "%02x", $0) }.joined()
        )
        
        return try callFFI(hawala_curve_generate_keypair, input: request)
    }
    
    /// Derive public key from private key
    /// - Parameters:
    ///   - curve: The elliptic curve
    ///   - privateKey: Hex-encoded private key (with or without 0x prefix)
    /// - Returns: Hex-encoded public key
    public func publicKey(curve: CurveType, privateKey: String) throws -> String {
        struct Request: Encodable {
            let curve: String
            let private_key: String
        }
        
        struct Response: Codable {
            let public_key: String
            let curve: String
        }
        
        let pk = privateKey.hasPrefix("0x") ? privateKey : "0x" + privateKey
        let request = Request(curve: curve.rawValue, private_key: pk)
        
        let response: Response = try callFFI(hawala_curve_public_key, input: request)
        return response.public_key
    }
    
    // MARK: - Signing
    
    /// Sign a message using the specified curve
    /// - Parameters:
    ///   - curve: The elliptic curve to use
    ///   - privateKey: Hex-encoded private key
    ///   - message: Message data to sign
    /// - Returns: Signature with public key
    public func sign(curve: CurveType, privateKey: String, message: Data) throws -> CurveSignature {
        struct Request: Encodable {
            let curve: String
            let private_key: String
            let message: String
        }
        
        let pk = privateKey.hasPrefix("0x") ? privateKey : "0x" + privateKey
        let msg = "0x" + message.map { String(format: "%02x", $0) }.joined()
        
        let request = Request(curve: curve.rawValue, private_key: pk, message: msg)
        
        return try callFFI(hawala_curve_sign, input: request)
    }
    
    /// Sign a hex-encoded message
    public func signHex(curve: CurveType, privateKey: String, messageHex: String) throws -> CurveSignature {
        struct Request: Encodable {
            let curve: String
            let private_key: String
            let message: String
        }
        
        let pk = privateKey.hasPrefix("0x") ? privateKey : "0x" + privateKey
        let msg = messageHex.hasPrefix("0x") ? messageHex : "0x" + messageHex
        
        let request = Request(curve: curve.rawValue, private_key: pk, message: msg)
        
        return try callFFI(hawala_curve_sign, input: request)
    }
    
    // MARK: - Verification
    
    /// Verify a signature
    /// - Parameters:
    ///   - curve: The elliptic curve
    ///   - publicKey: Hex-encoded public key
    ///   - message: Original message data
    ///   - signature: Hex-encoded signature
    /// - Returns: Whether the signature is valid
    public func verify(curve: CurveType, publicKey: String, message: Data, signature: String) throws -> Bool {
        struct Request: Encodable {
            let curve: String
            let public_key: String
            let message: String
            let signature: String
        }
        
        let pk = publicKey.hasPrefix("0x") ? publicKey : "0x" + publicKey
        let msg = "0x" + message.map { String(format: "%02x", $0) }.joined()
        let sig = signature.hasPrefix("0x") ? signature : "0x" + signature
        
        let request = Request(curve: curve.rawValue, public_key: pk, message: msg, signature: sig)
        
        let result: CurveVerification = try callFFI(hawala_curve_verify, input: request)
        return result.valid
    }
    
    // MARK: - Curve Information
    
    /// Get information about a curve type
    public func curveInfo(_ curve: CurveType) throws -> CurveInfo {
        struct Request: Encodable {
            let curve: String
        }
        
        return try callFFI(hawala_curve_info, input: Request(curve: curve.rawValue))
    }
    
    /// Get all supported curves
    public var supportedCurves: [CurveType] {
        CurveType.allCases
    }
}

// MARK: - Errors

public enum CurveError: Error, LocalizedError {
    case encodingFailed
    case decodingFailed
    case ffiCallFailed
    case noData
    case rustError(String)
    case invalidPrivateKey
    case invalidPublicKey
    case invalidSignature
    case unsupportedCurve
    
    public var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Failed to encode request"
        case .decodingFailed: return "Failed to decode response"
        case .ffiCallFailed: return "FFI call returned null"
        case .noData: return "No data in response"
        case .rustError(let msg): return msg
        case .invalidPrivateKey: return "Invalid private key format"
        case .invalidPublicKey: return "Invalid public key format"
        case .invalidSignature: return "Invalid signature format"
        case .unsupportedCurve: return "Unsupported curve type"
        }
    }
}

// MARK: - Convenience Extensions

extension Data {
    /// Create random seed data for key generation
    public static func randomSeed(bytes: Int = 32) -> Data {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, bytes, ptr.baseAddress!)
        }
        return data
    }
}
