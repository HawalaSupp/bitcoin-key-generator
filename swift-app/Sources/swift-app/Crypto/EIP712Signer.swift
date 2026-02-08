//
//  EIP712Signer.swift
//  Hawala
//
//  EIP-712 Typed Data Signing Implementation
//  Reference: https://eips.ethereum.org/EIPS/eip-712
//

import Foundation
import RustBridge

// MARK: - EIP-712 Data Structures

/// A field in an EIP-712 type definition
public struct EIP712Field: Codable, Equatable {
    public let name: String
    public let type: String
    
    public init(name: String, type: String) {
        self.name = name
        self.type = type
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case type
    }
}

/// EIP-712 Domain Separator data
public struct EIP712Domain: Codable {
    public var name: String?
    public var version: String?
    public var chainId: EIP712ChainId?
    public var verifyingContract: String?
    public var salt: String?
    
    public init(
        name: String? = nil,
        version: String? = nil,
        chainId: UInt64? = nil,
        verifyingContract: String? = nil,
        salt: String? = nil
    ) {
        self.name = name
        self.version = version
        self.chainId = chainId.map { .number($0) }
        self.verifyingContract = verifyingContract
        self.salt = salt
    }
}

/// Chain ID can be a number or string
public enum EIP712ChainId: Codable, Equatable {
    case number(UInt64)
    case string(String)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(UInt64.self) {
            self = .number(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(
                EIP712ChainId.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected number or string")
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }
}

/// Complete EIP-712 typed data structure
public struct EIP712TypedData: Codable {
    public let types: [String: [EIP712Field]]
    public let primaryType: String
    public let domain: EIP712Domain
    public let message: [String: AnyCodable]
    
    public init(
        types: [String: [EIP712Field]],
        primaryType: String,
        domain: EIP712Domain,
        message: [String: AnyCodable]
    ) {
        self.types = types
        self.primaryType = primaryType
        self.domain = domain
        self.message = message
    }
    
    /// Create from JSON string
    public static func fromJSON(_ json: String) throws -> EIP712TypedData {
        guard let data = json.data(using: .utf8) else {
            throw EIP712Error.invalidJSON("Failed to convert string to data")
        }
        return try JSONDecoder().decode(EIP712TypedData.self, from: data)
    }
    
    /// Convert to JSON string
    public func toJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard let json = String(data: data, encoding: .utf8) else {
            throw EIP712Error.invalidJSON("Failed to convert data to string")
        }
        return json
    }
}

/// EIP-712 signature components
public struct EIP712Signature: Sendable {
    public let r: Data
    public let s: Data
    public let v: UInt8
    
    /// Raw 65-byte signature (r || s || v)
    public var rawSignature: Data {
        var data = Data()
        data.append(r)
        data.append(s)
        data.append(v)
        return data
    }
    
    /// Hex-encoded signature with 0x prefix
    public var hexSignature: String {
        "0x" + rawSignature.map { String(format: "%02x", $0) }.joined()
    }
    
    public init(r: Data, s: Data, v: UInt8) {
        self.r = r
        self.s = s
        self.v = v
    }
    
    /// Create from 65-byte raw signature
    public init(rawSignature: Data) throws {
        guard rawSignature.count == 65 else {
            throw EIP712Error.invalidSignature("Expected 65 bytes, got \(rawSignature.count)")
        }
        self.r = rawSignature[0..<32]
        self.s = rawSignature[32..<64]
        self.v = rawSignature[64]
    }
    
    /// Create from hex string (with or without 0x prefix)
    public init(hexSignature: String) throws {
        let hex = hexSignature.hasPrefix("0x") ? String(hexSignature.dropFirst(2)) : hexSignature
        guard let data = Data(eip712HexString: hex), data.count == 65 else {
            throw EIP712Error.invalidSignature("Invalid hex signature")
        }
        try self.init(rawSignature: data)
    }
}

/// EIP-712 hash result
public struct EIP712HashResult {
    public let hash: Data
    public let domainSeparator: Data
    public let structHash: Data
    
    /// Hex-encoded final hash
    public var hexHash: String {
        "0x" + hash.eip712HexEncodedString()
    }
}

/// EIP-712 verification result
public struct EIP712VerificationResult {
    public let valid: Bool
    public let recoveredAddress: String
}

// MARK: - EIP-712 Errors

public enum EIP712Error: Error, LocalizedError {
    case invalidJSON(String)
    case invalidType(String)
    case missingField(String)
    case invalidSignature(String)
    case signingFailed(String)
    case verificationFailed(String)
    case rustError(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let msg): return "Invalid JSON: \(msg)"
        case .invalidType(let msg): return "Invalid type: \(msg)"
        case .missingField(let msg): return "Missing field: \(msg)"
        case .invalidSignature(let msg): return "Invalid signature: \(msg)"
        case .signingFailed(let msg): return "Signing failed: \(msg)"
        case .verificationFailed(let msg): return "Verification failed: \(msg)"
        case .rustError(let msg): return "Rust error: \(msg)"
        }
    }
}

// MARK: - EIP-712 Signer

/// Main interface for EIP-712 typed data operations
public final class EIP712Signer: @unchecked Sendable {
    
    public static let shared = EIP712Signer()
    
    private init() {}
    
    // MARK: - Hashing
    
    /// Calculate the EIP-712 hash of typed data
    /// - Parameter typedData: The EIP-712 typed data structure
    /// - Returns: Hash result containing final hash, domain separator, and struct hash
    public func hashTypedData(_ typedData: EIP712TypedData) async throws -> EIP712HashResult {
        let json = try typedData.toJSON()
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cString = json.cString(using: .utf8) else {
                    continuation.resume(throwing: EIP712Error.invalidJSON("Failed to create C string"))
                    return
                }
                
                guard let resultPtr = hawala_eip712_hash(cString) else {
                    continuation.resume(throwing: EIP712Error.rustError("Null response from Rust"))
                    return
                }
                
                defer { hawala_free_string(UnsafeMutablePointer(mutating: resultPtr)) }
                
                let resultString = String(cString: resultPtr)
                
                do {
                    let result = try Self.parseHashResult(resultString)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Signing
    
    /// Sign EIP-712 typed data
    /// - Parameters:
    ///   - typedData: The EIP-712 typed data structure
    ///   - privateKey: The private key (32 bytes)
    /// - Returns: The signature
    public func signTypedData(_ typedData: EIP712TypedData, privateKey: Data) async throws -> EIP712Signature {
        guard privateKey.count == 32 else {
            throw EIP712Error.signingFailed("Private key must be 32 bytes")
        }
        
        let request = SignRequest(
            typedData: typedData,
            privateKey: "0x" + privateKey.eip712HexEncodedString()
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let requestData = try encoder.encode(request)
        guard let json = String(data: requestData, encoding: .utf8) else {
            throw EIP712Error.invalidJSON("Failed to encode request")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cString = json.cString(using: .utf8) else {
                    continuation.resume(throwing: EIP712Error.invalidJSON("Failed to create C string"))
                    return
                }
                
                guard let resultPtr = hawala_eip712_sign(cString) else {
                    continuation.resume(throwing: EIP712Error.rustError("Null response from Rust"))
                    return
                }
                
                defer { hawala_free_string(UnsafeMutablePointer(mutating: resultPtr)) }
                
                let resultString = String(cString: resultPtr)
                
                do {
                    let signature = try Self.parseSignResult(resultString)
                    continuation.resume(returning: signature)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Verification
    
    /// Verify an EIP-712 signature
    /// - Parameters:
    ///   - typedData: The EIP-712 typed data structure
    ///   - signature: The signature to verify
    ///   - address: The expected signer address
    /// - Returns: Verification result
    public func verifyTypedData(
        _ typedData: EIP712TypedData,
        signature: EIP712Signature,
        address: String
    ) async throws -> EIP712VerificationResult {
        let request = VerifyRequest(
            typedData: typedData,
            signature: signature.hexSignature,
            address: address
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let requestData = try encoder.encode(request)
        guard let json = String(data: requestData, encoding: .utf8) else {
            throw EIP712Error.invalidJSON("Failed to encode request")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cString = json.cString(using: .utf8) else {
                    continuation.resume(throwing: EIP712Error.invalidJSON("Failed to create C string"))
                    return
                }
                
                guard let resultPtr = hawala_eip712_verify(cString) else {
                    continuation.resume(throwing: EIP712Error.rustError("Null response from Rust"))
                    return
                }
                
                defer { hawala_free_string(UnsafeMutablePointer(mutating: resultPtr)) }
                
                let resultString = String(cString: resultPtr)
                
                do {
                    let result = try Self.parseVerifyResult(resultString)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Address Recovery
    
    /// Recover the signer's address from an EIP-712 signature
    /// - Parameters:
    ///   - typedData: The EIP-712 typed data structure
    ///   - signature: The signature
    /// - Returns: The recovered address
    public func recoverAddress(
        from typedData: EIP712TypedData,
        signature: EIP712Signature
    ) async throws -> String {
        let request = RecoverRequest(
            typedData: typedData,
            signature: signature.hexSignature
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let requestData = try encoder.encode(request)
        guard let json = String(data: requestData, encoding: .utf8) else {
            throw EIP712Error.invalidJSON("Failed to encode request")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cString = json.cString(using: .utf8) else {
                    continuation.resume(throwing: EIP712Error.invalidJSON("Failed to create C string"))
                    return
                }
                
                guard let resultPtr = hawala_eip712_recover(cString) else {
                    continuation.resume(throwing: EIP712Error.rustError("Null response from Rust"))
                    return
                }
                
                defer { hawala_free_string(UnsafeMutablePointer(mutating: resultPtr)) }
                
                let resultString = String(cString: resultPtr)
                
                do {
                    let address = try Self.parseRecoverResult(resultString)
                    continuation.resume(returning: address)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private struct SignRequest: Codable {
        let typedData: EIP712TypedData
        let privateKey: String
    }
    
    private struct VerifyRequest: Codable {
        let typedData: EIP712TypedData
        let signature: String
        let address: String
    }
    
    private struct RecoverRequest: Codable {
        let typedData: EIP712TypedData
        let signature: String
    }
    
    private static func parseHashResult(_ json: String) throws -> EIP712HashResult {
        guard let data = json.data(using: .utf8) else {
            throw EIP712Error.invalidJSON("Failed to parse response")
        }
        
        let response = try JSONDecoder().decode(RustResponse<HashData>.self, from: data)
        
        guard response.success, let hashData = response.data else {
            let errorMsg = response.error?.message ?? "Unknown error"
            throw EIP712Error.rustError(errorMsg)
        }
        
        guard let hash = Data(eip712HexString: hashData.hash.dropFirst(2)),
              let domainSeparator = Data(eip712HexString: hashData.domainSeparator.dropFirst(2)),
              let structHash = Data(eip712HexString: hashData.structHash.dropFirst(2)) else {
            throw EIP712Error.invalidJSON("Failed to parse hex values")
        }
        
        return EIP712HashResult(
            hash: hash,
            domainSeparator: domainSeparator,
            structHash: structHash
        )
    }
    
    private static func parseSignResult(_ json: String) throws -> EIP712Signature {
        guard let data = json.data(using: .utf8) else {
            throw EIP712Error.invalidJSON("Failed to parse response")
        }
        
        let response = try JSONDecoder().decode(RustResponse<SignData>.self, from: data)
        
        guard response.success, let signData = response.data else {
            let errorMsg = response.error?.message ?? "Unknown error"
            throw EIP712Error.signingFailed(errorMsg)
        }
        
        guard let r = Data(eip712HexString: signData.r.dropFirst(2)),
              let s = Data(eip712HexString: signData.s.dropFirst(2)) else {
            throw EIP712Error.invalidJSON("Failed to parse signature components")
        }
        
        return EIP712Signature(r: r, s: s, v: signData.v)
    }
    
    private static func parseVerifyResult(_ json: String) throws -> EIP712VerificationResult {
        guard let data = json.data(using: .utf8) else {
            throw EIP712Error.invalidJSON("Failed to parse response")
        }
        
        let response = try JSONDecoder().decode(RustResponse<VerifyData>.self, from: data)
        
        guard response.success, let verifyData = response.data else {
            let errorMsg = response.error?.message ?? "Unknown error"
            throw EIP712Error.verificationFailed(errorMsg)
        }
        
        return EIP712VerificationResult(
            valid: verifyData.valid,
            recoveredAddress: verifyData.recoveredAddress
        )
    }
    
    private static func parseRecoverResult(_ json: String) throws -> String {
        guard let data = json.data(using: .utf8) else {
            throw EIP712Error.invalidJSON("Failed to parse response")
        }
        
        let response = try JSONDecoder().decode(RustResponse<RecoverData>.self, from: data)
        
        guard response.success, let recoverData = response.data else {
            let errorMsg = response.error?.message ?? "Unknown error"
            throw EIP712Error.verificationFailed(errorMsg)
        }
        
        return recoverData.address
    }
}

// MARK: - Response Types

private struct RustResponse<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: RustError?
}

private struct RustError: Decodable {
    let code: String
    let message: String
}

private struct HashData: Decodable {
    let hash: String
    let domainSeparator: String
    let structHash: String
}

private struct SignData: Decodable {
    let signature: String
    let r: String
    let s: String
    let v: UInt8
}

private struct VerifyData: Decodable {
    let valid: Bool
    let recoveredAddress: String
}

private struct RecoverData: Decodable {
    let address: String
}

// MARK: - AnyCodable Helper

/// A type-erased Codable value for dynamic JSON handling
public struct AnyCodable: Codable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.typeMismatch(
                AnyCodable.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Unsupported type")
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let int64 as Int64:
            try container.encode(int64)
        case let uint as UInt:
            try container.encode(uint)
        case let uint64 as UInt64:
            try container.encode(uint64)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                .init(codingPath: encoder.codingPath, debugDescription: "Unsupported type")
            )
        }
    }
}

// MARK: - EIP712 Data Extensions

private extension Data {
    init?(eip712HexString hexString: String) {
        let hex = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
        let len = hex.count / 2
        var data = Data(capacity: len)
        var index = hex.startIndex
        
        for _ in 0..<len {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        
        self = data
    }
    
    init?(eip712HexString hexString: Substring) {
        self.init(eip712HexString: String(hexString))
    }
    
    func eip712HexEncodedString() -> String {
        return map { String(format: "%02x", $0) }.joined()
    }
}
