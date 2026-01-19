//
//  SchnorrSigner.swift
//  Hawala
//
//  BIP-340 Schnorr Signature Implementation for Bitcoin Taproot
//  Reference: https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki
//

import Foundation
import RustBridge

// MARK: - Schnorr Types

/// 32-byte x-only public key (BIP-340)
public struct XOnlyPublicKey: Equatable, Codable {
    public let data: Data
    
    public init(data: Data) throws {
        guard data.count == 32 else {
            throw SchnorrError.invalidPublicKey("Expected 32 bytes, got \(data.count)")
        }
        self.data = data
    }
    
    public init(hex: String) throws {
        let hexString = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard let data = Data(hexString: hexString), data.count == 32 else {
            throw SchnorrError.invalidPublicKey("Invalid hex string or wrong length")
        }
        self.data = data
    }
    
    public var hex: String {
        "0x" + data.hexEncodedString()
    }
}

/// 64-byte Schnorr signature (BIP-340)
public struct SchnorrSignature: Equatable, Codable {
    public let data: Data
    
    public init(data: Data) throws {
        guard data.count == 64 else {
            throw SchnorrError.invalidSignature("Expected 64 bytes, got \(data.count)")
        }
        self.data = data
    }
    
    public init(hex: String) throws {
        let hexString = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard let data = Data(hexString: hexString), data.count == 64 else {
            throw SchnorrError.invalidSignature("Invalid hex string or wrong length")
        }
        self.data = data
    }
    
    /// The R component (first 32 bytes)
    public var r: Data {
        data.prefix(32)
    }
    
    /// The s component (last 32 bytes)
    public var s: Data {
        data.suffix(32)
    }
    
    public var hex: String {
        "0x" + data.hexEncodedString()
    }
}

// MARK: - Taproot Types

/// Taproot output key (tweaked public key)
public struct TaprootOutputKey: Equatable, Codable {
    /// The x-only output public key
    public let outputKey: XOnlyPublicKey
    /// Parity of the output key (needed for script-path spending)
    public let parity: Bool
}

/// TapLeaf hash (32 bytes)
public struct TapLeafHash: Equatable, Codable {
    public let data: Data
    
    public init(data: Data) throws {
        guard data.count == 32 else {
            throw SchnorrError.invalidHash("Expected 32 bytes, got \(data.count)")
        }
        self.data = data
    }
    
    public init(hex: String) throws {
        let hexString = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard let data = Data(hexString: hexString), data.count == 32 else {
            throw SchnorrError.invalidHash("Invalid hex string or wrong length")
        }
        self.data = data
    }
    
    public var hex: String {
        "0x" + data.hexEncodedString()
    }
}

/// Merkle root for Taproot script trees
public struct TapMerkleRoot: Equatable, Codable {
    public let data: Data
    
    public init(data: Data) throws {
        guard data.count == 32 else {
            throw SchnorrError.invalidMerkleRoot("Expected 32 bytes, got \(data.count)")
        }
        self.data = data
    }
    
    public init(hex: String) throws {
        let hexString = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard let data = Data(hexString: hexString), data.count == 32 else {
            throw SchnorrError.invalidMerkleRoot("Invalid hex string or wrong length")
        }
        self.data = data
    }
    
    public var hex: String {
        "0x" + data.hexEncodedString()
    }
    
    /// Create an empty merkle root (key-path only spend)
    public static var empty: TapMerkleRoot {
        try! TapMerkleRoot(data: Data(count: 32))
    }
    
    public var isEmpty: Bool {
        data.allSatisfy { $0 == 0 }
    }
}

// MARK: - Errors

public enum SchnorrError: LocalizedError {
    case invalidPrivateKey(String)
    case invalidPublicKey(String)
    case invalidSignature(String)
    case invalidHash(String)
    case invalidMerkleRoot(String)
    case signingFailed(String)
    case verificationFailed(String)
    case tweakFailed(String)
    case rustError(String)
    case invalidJSON(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidPrivateKey(let msg): return "Invalid private key: \(msg)"
        case .invalidPublicKey(let msg): return "Invalid public key: \(msg)"
        case .invalidSignature(let msg): return "Invalid signature: \(msg)"
        case .invalidHash(let msg): return "Invalid hash: \(msg)"
        case .invalidMerkleRoot(let msg): return "Invalid merkle root: \(msg)"
        case .signingFailed(let msg): return "Signing failed: \(msg)"
        case .verificationFailed(let msg): return "Verification failed: \(msg)"
        case .tweakFailed(let msg): return "Tweak failed: \(msg)"
        case .rustError(let msg): return "Rust error: \(msg)"
        case .invalidJSON(let msg): return "Invalid JSON: \(msg)"
        }
    }
}

// MARK: - Schnorr Signer

/// BIP-340 Schnorr signature implementation
public final class SchnorrSigner: Sendable {
    public static let shared = SchnorrSigner()
    
    public init() {}
    
    // MARK: - Signing
    
    /// Sign a message using BIP-340 Schnorr signature scheme
    /// - Parameters:
    ///   - message: 32-byte message hash to sign
    ///   - privateKey: 32-byte private key
    ///   - auxRand: Optional 32-byte auxiliary randomness (recommended for security)
    /// - Returns: Tuple of (signature, publicKey)
    public func sign(message: Data, privateKey: Data, auxRand: Data? = nil) async throws -> (signature: SchnorrSignature, publicKey: XOnlyPublicKey) {
        guard message.count == 32 else {
            throw SchnorrError.invalidHash("Message must be 32 bytes")
        }
        guard privateKey.count == 32 else {
            throw SchnorrError.invalidPrivateKey("Private key must be 32 bytes")
        }
        if let aux = auxRand, aux.count != 32 {
            throw SchnorrError.invalidHash("Auxiliary randomness must be 32 bytes")
        }
        
        var request: [String: Any] = [
            "message": "0x" + message.hexEncodedString(),
            "private_key": "0x" + privateKey.hexEncodedString()
        ]
        if let aux = auxRand {
            request["aux_rand"] = "0x" + aux.hexEncodedString()
        }
        
        let result = try await callRust(request)
        
        guard let sigHex = result["signature"] as? String,
              let pubKeyHex = result["public_key"] as? String else {
            throw SchnorrError.rustError("Missing signature or public_key in response")
        }
        
        let signature = try SchnorrSignature(hex: sigHex)
        let publicKey = try XOnlyPublicKey(hex: pubKeyHex)
        
        return (signature, publicKey)
    }
    
    /// Verify a BIP-340 Schnorr signature
    /// - Parameters:
    ///   - message: 32-byte message hash
    ///   - signature: 64-byte Schnorr signature
    ///   - publicKey: 32-byte x-only public key
    /// - Returns: True if signature is valid
    public func verify(message: Data, signature: SchnorrSignature, publicKey: XOnlyPublicKey) async throws -> Bool {
        guard message.count == 32 else {
            throw SchnorrError.invalidHash("Message must be 32 bytes")
        }
        
        let request: [String: Any] = [
            "message": "0x" + message.hexEncodedString(),
            "signature": signature.hex,
            "public_key": publicKey.hex
        ]
        
        let result = try await callRustVerify(request)
        
        guard let valid = result["valid"] as? Bool else {
            throw SchnorrError.rustError("Missing valid field in response")
        }
        
        return valid
    }
    
    // MARK: - Private Helpers
    
    private func callRust(_ request: [String: Any]) async throws -> [String: Any] {
        let jsonData = try JSONSerialization.data(withJSONObject: request)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw SchnorrError.invalidJSON("Failed to create JSON string")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cString = jsonString.cString(using: .utf8) else {
                    continuation.resume(throwing: SchnorrError.invalidJSON("Failed to create C string"))
                    return
                }
                
                guard let resultPtr = hawala_schnorr_sign(cString) else {
                    continuation.resume(throwing: SchnorrError.rustError("Null response from Rust"))
                    return
                }
                
                defer { hawala_free_string(UnsafeMutablePointer(mutating: resultPtr)) }
                
                let resultString = String(cString: resultPtr)
                
                do {
                    let result = try Self.parseResponse(resultString)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func callRustVerify(_ request: [String: Any]) async throws -> [String: Any] {
        let jsonData = try JSONSerialization.data(withJSONObject: request)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw SchnorrError.invalidJSON("Failed to create JSON string")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cString = jsonString.cString(using: .utf8) else {
                    continuation.resume(throwing: SchnorrError.invalidJSON("Failed to create C string"))
                    return
                }
                
                guard let resultPtr = hawala_schnorr_verify(cString) else {
                    continuation.resume(throwing: SchnorrError.rustError("Null response from Rust"))
                    return
                }
                
                defer { hawala_free_string(UnsafeMutablePointer(mutating: resultPtr)) }
                
                let resultString = String(cString: resultPtr)
                
                do {
                    let result = try Self.parseResponse(resultString)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private static func parseResponse(_ jsonString: String) throws -> [String: Any] {
        guard let data = jsonString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SchnorrError.invalidJSON("Failed to parse response JSON")
        }
        
        guard let success = json["success"] as? Bool else {
            throw SchnorrError.rustError("Missing success field in response")
        }
        
        if !success {
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw SchnorrError.rustError(message)
            }
            throw SchnorrError.rustError("Unknown error")
        }
        
        guard let result = json["data"] as? [String: Any] else {
            throw SchnorrError.rustError("Missing data field in response")
        }
        
        return result
    }
}

// MARK: - Taproot Signer

/// Taproot key tweaking and signing
public final class TaprootSigner: Sendable {
    public static let shared = TaprootSigner()
    
    public init() {}
    
    // MARK: - Key Tweaking
    
    /// Tweak an internal public key to create the Taproot output key
    /// - Parameters:
    ///   - internalKey: 32-byte x-only internal public key
    ///   - merkleRoot: Optional 32-byte merkle root of script tree
    /// - Returns: Tweaked output key with parity
    public func tweakPublicKey(internalKey: XOnlyPublicKey, merkleRoot: TapMerkleRoot? = nil) async throws -> TaprootOutputKey {
        var request: [String: Any] = [
            "internal_key": internalKey.hex
        ]
        if let root = merkleRoot, !root.isEmpty {
            request["merkle_root"] = root.hex
        }
        
        let result = try await callRust("hawala_taproot_tweak_pubkey", request: request)
        
        guard let outputKeyHex = result["output_key"] as? String,
              let parity = result["parity"] as? Bool else {
            throw SchnorrError.rustError("Missing output_key or parity in response")
        }
        
        let outputKey = try XOnlyPublicKey(hex: outputKeyHex)
        
        return TaprootOutputKey(outputKey: outputKey, parity: parity)
    }
    
    /// Sign for Taproot key-path spending
    /// - Parameters:
    ///   - sighash: 32-byte sighash to sign
    ///   - privateKey: 32-byte private key
    ///   - merkleRoot: Optional 32-byte merkle root of script tree
    /// - Returns: Tuple of (signature, outputKey)
    public func signKeyPath(sighash: Data, privateKey: Data, merkleRoot: TapMerkleRoot? = nil) async throws -> (signature: SchnorrSignature, outputKey: XOnlyPublicKey) {
        guard sighash.count == 32 else {
            throw SchnorrError.invalidHash("Sighash must be 32 bytes")
        }
        guard privateKey.count == 32 else {
            throw SchnorrError.invalidPrivateKey("Private key must be 32 bytes")
        }
        
        var request: [String: Any] = [
            "sighash": "0x" + sighash.hexEncodedString(),
            "private_key": "0x" + privateKey.hexEncodedString()
        ]
        if let root = merkleRoot, !root.isEmpty {
            request["merkle_root"] = root.hex
        }
        
        let result = try await callRust("hawala_taproot_sign_key_path", request: request)
        
        guard let sigHex = result["signature"] as? String,
              let outputKeyHex = result["output_key"] as? String else {
            throw SchnorrError.rustError("Missing signature or output_key in response")
        }
        
        let signature = try SchnorrSignature(hex: sigHex)
        let outputKey = try XOnlyPublicKey(hex: outputKeyHex)
        
        return (signature, outputKey)
    }
    
    // MARK: - Script Tree Operations
    
    /// Calculate the TapLeaf hash for a script
    /// - Parameters:
    ///   - script: Script bytes
    ///   - version: Leaf version (default: 0xc0 for TapScript)
    /// - Returns: TapLeaf hash
    public func leafHash(script: Data, version: UInt8 = 0xc0) async throws -> TapLeafHash {
        let request: [String: Any] = [
            "script": "0x" + script.hexEncodedString(),
            "version": version
        ]
        
        let result = try await callRust("hawala_taproot_leaf_hash", request: request)
        
        guard let hashHex = result["leaf_hash"] as? String else {
            throw SchnorrError.rustError("Missing leaf_hash in response")
        }
        
        return try TapLeafHash(hex: hashHex)
    }
    
    /// Build a Merkle root from a list of scripts
    /// - Parameters:
    ///   - scripts: Array of script bytes
    ///   - versions: Optional array of leaf versions (default: 0xc0 for all)
    /// - Returns: Merkle root
    public func buildMerkleRoot(scripts: [Data], versions: [UInt8]? = nil) async throws -> TapMerkleRoot {
        let scriptHexes = scripts.map { "0x" + $0.hexEncodedString() }
        
        var request: [String: Any] = [
            "scripts": scriptHexes
        ]
        if let versions = versions {
            request["versions"] = versions
        }
        
        let result = try await callRust("hawala_taproot_merkle_root", request: request)
        
        guard let rootHex = result["merkle_root"] as? String else {
            throw SchnorrError.rustError("Missing merkle_root in response")
        }
        
        return try TapMerkleRoot(hex: rootHex)
    }
    
    // MARK: - Private Helpers
    
    private func callRust(_ function: String, request: [String: Any]) async throws -> [String: Any] {
        let jsonData = try JSONSerialization.data(withJSONObject: request)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw SchnorrError.invalidJSON("Failed to create JSON string")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cString = jsonString.cString(using: .utf8) else {
                    continuation.resume(throwing: SchnorrError.invalidJSON("Failed to create C string"))
                    return
                }
                
                let resultPtr: UnsafePointer<CChar>?
                switch function {
                case "hawala_taproot_tweak_pubkey":
                    resultPtr = hawala_taproot_tweak_pubkey(cString)
                case "hawala_taproot_sign_key_path":
                    resultPtr = hawala_taproot_sign_key_path(cString)
                case "hawala_taproot_leaf_hash":
                    resultPtr = hawala_taproot_leaf_hash(cString)
                case "hawala_taproot_merkle_root":
                    resultPtr = hawala_taproot_merkle_root(cString)
                default:
                    continuation.resume(throwing: SchnorrError.rustError("Unknown function: \(function)"))
                    return
                }
                
                guard let ptr = resultPtr else {
                    continuation.resume(throwing: SchnorrError.rustError("Null response from Rust"))
                    return
                }
                
                defer { hawala_free_string(UnsafeMutablePointer(mutating: ptr)) }
                
                let resultString = String(cString: ptr)
                
                do {
                    let result = try Self.parseResponse(resultString)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private static func parseResponse(_ jsonString: String) throws -> [String: Any] {
        guard let data = jsonString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SchnorrError.invalidJSON("Failed to parse response JSON")
        }
        
        guard let success = json["success"] as? Bool else {
            throw SchnorrError.rustError("Missing success field in response")
        }
        
        if !success {
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw SchnorrError.rustError(message)
            }
            throw SchnorrError.rustError("Unknown error")
        }
        
        guard let result = json["data"] as? [String: Any] else {
            throw SchnorrError.rustError("Missing data field in response")
        }
        
        return result
    }
}

// Note: Data hex extensions are defined in EIP712Signer.swift to avoid duplication
