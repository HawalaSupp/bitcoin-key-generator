//
//  QRCodeBridge.swift
//  Hawala
//
//  QR Code Encoding/Decoding for Air-Gapped Signing
//  Supports UR (Uniform Resource) format for animated QR codes
//

import Foundation
import RustBridge

// MARK: - UR Types

/// Uniform Resource types for QR encoding
public enum URType: String, Codable, CaseIterable, Sendable {
    case bytes = "bytes"
    case cryptoPsbt = "crypto-psbt"
    case cryptoAccount = "crypto-account"
    case cryptoHdkey = "crypto-hdkey"
    case cryptoOutput = "crypto-output"
    case cryptoSeed = "crypto-seed"
    case ethSignRequest = "eth-sign-request"
    case ethSignature = "eth-signature"
    case solSignRequest = "sol-sign-request"
    case solSignature = "sol-signature"
    
    public var displayName: String {
        switch self {
        case .bytes: return "Raw Bytes"
        case .cryptoPsbt: return "Bitcoin PSBT"
        case .cryptoAccount: return "Crypto Account"
        case .cryptoHdkey: return "HD Key"
        case .cryptoOutput: return "Output Descriptor"
        case .cryptoSeed: return "Seed"
        case .ethSignRequest: return "Ethereum Sign Request"
        case .ethSignature: return "Ethereum Signature"
        case .solSignRequest: return "Solana Sign Request"
        case .solSignature: return "Solana Signature"
        }
    }
    
    public var description: String {
        switch self {
        case .bytes: return "Raw byte data"
        case .cryptoPsbt: return "Partially Signed Bitcoin Transaction (BIP-174)"
        case .cryptoAccount: return "Cryptocurrency account descriptor"
        case .cryptoHdkey: return "HD wallet key (BIP-32)"
        case .cryptoOutput: return "Bitcoin output descriptor"
        case .cryptoSeed: return "Cryptographic seed"
        case .ethSignRequest: return "Ethereum signing request"
        case .ethSignature: return "Ethereum signature response"
        case .solSignRequest: return "Solana signing request"
        case .solSignature: return "Solana signature response"
        }
    }
}

// MARK: - Result Types

/// Encoded UR frames for animated QR display
public struct UREncodedFrames: Codable, Sendable {
    public let frames: [String]
    public let frameCount: Int
    public let type: String
    
    enum CodingKeys: String, CodingKey {
        case frames
        case frameCount = "frame_count"
        case type
    }
}

/// Simple QR payload
public struct SimpleQRPayload: Codable, Sendable {
    public let payload: String
    public let size: Int
    public let canFitSingleQR: Bool
    
    enum CodingKeys: String, CodingKey {
        case payload
        case size
        case canFitSingleQR = "can_fit_single_qr"
    }
}

/// Decoded UR result
public struct URDecodeResult: Codable, Sendable {
    public let type: String?
    public let data: String?
    public let complete: Bool
    public let progress: Float?
    public let message: String?
}

/// Supported UR types info
public struct URSupportedTypes: Codable, Sendable {
    public let types: [URTypeInfo]
    public let maxSingleQRSizeBytes: Int
    public let recommendedFragmentSize: Int
    
    enum CodingKeys: String, CodingKey {
        case types
        case maxSingleQRSizeBytes = "max_single_qr_size_bytes"
        case recommendedFragmentSize = "recommended_fragment_size"
    }
}

public struct URTypeInfo: Codable, Sendable {
    public let name: String
    public let description: String
}

// MARK: - FFI Response Types

private struct QRFFIResponse<D: Codable>: Codable {
    let success: Bool
    let data: D?
    let error: QRFFIError?
}

private struct QRFFIError: Codable {
    let code: String
    let message: String
}

// MARK: - QR Code Bridge

/// Bridge for QR code encoding/decoding operations
public final class QRCodeBridge: @unchecked Sendable {
    public static let shared = QRCodeBridge()
    
    /// Default fragment size for animated QR codes
    public static let defaultFragmentSize = 100
    
    /// Maximum bytes for a single QR code
    public static let maxSingleQRBytes = 2331
    
    private init() {}
    
    // MARK: - FFI Helpers
    
    private func callFFI<T: Codable>(_ ffiCall: (UnsafePointer<CChar>?) -> UnsafePointer<CChar>?, input: some Encodable) throws -> T {
        let encoder = JSONEncoder()
        let inputData = try encoder.encode(input)
        guard let inputString = String(data: inputData, encoding: .utf8) else {
            throw QRBridgeError.encodingFailed
        }
        
        guard let resultPtr = inputString.withCString({ ffiCall($0) }) else {
            throw QRBridgeError.ffiCallFailed
        }
        defer { hawala_free_string(UnsafeMutablePointer(mutating: resultPtr)) }
        
        let resultString = String(cString: resultPtr)
        guard let resultData = resultString.data(using: .utf8) else {
            throw QRBridgeError.decodingFailed
        }
        
        let decoder = JSONDecoder()
        let response = try decoder.decode(QRFFIResponse<T>.self, from: resultData)
        
        if !response.success {
            throw QRBridgeError.rustError(response.error?.message ?? "Unknown error")
        }
        
        guard let data = response.data else {
            throw QRBridgeError.noData
        }
        
        return data
    }
    
    private func callFFINoInput<T: Codable>(_ ffiCall: () -> UnsafePointer<CChar>?) throws -> T {
        guard let resultPtr = ffiCall() else {
            throw QRBridgeError.ffiCallFailed
        }
        defer { hawala_free_string(UnsafeMutablePointer(mutating: resultPtr)) }
        
        let resultString = String(cString: resultPtr)
        guard let resultData = resultString.data(using: .utf8) else {
            throw QRBridgeError.decodingFailed
        }
        
        let decoder = JSONDecoder()
        let response = try decoder.decode(QRFFIResponse<T>.self, from: resultData)
        
        if !response.success {
            throw QRBridgeError.rustError(response.error?.message ?? "Unknown error")
        }
        
        guard let data = response.data else {
            throw QRBridgeError.noData
        }
        
        return data
    }
    
    // MARK: - Encoding
    
    /// Encode data as UR frames for animated QR display
    /// - Parameters:
    ///   - type: The UR type
    ///   - data: Data to encode
    ///   - maxFragmentSize: Maximum fragment size (default 100)
    /// - Returns: Array of UR frame strings
    public func encodeUR(type: URType, data: Data, maxFragmentSize: Int = defaultFragmentSize) throws -> UREncodedFrames {
        struct Request: Encodable {
            let type: String
            let data: String
            let max_fragment_size: Int
        }
        
        let dataHex = "0x" + data.map { String(format: "%02x", $0) }.joined()
        let request = Request(type: type.rawValue, data: dataHex, max_fragment_size: maxFragmentSize)
        
        return try callFFI(hawala_qr_encode_ur, input: request)
    }
    
    /// Encode a PSBT for air-gapped signing
    public func encodePSBT(_ psbtData: Data, maxFragmentSize: Int = defaultFragmentSize) throws -> [String] {
        let result = try encodeUR(type: .cryptoPsbt, data: psbtData, maxFragmentSize: maxFragmentSize)
        return result.frames
    }
    
    /// Encode data as a simple QR payload
    /// - Parameters:
    ///   - data: Data to encode
    ///   - format: Output format ("hex", "base64", or "raw")
    /// - Returns: Simple QR payload
    public func encodeSimple(data: Data, format: String = "hex") throws -> SimpleQRPayload {
        struct Request: Encodable {
            let data: String
            let format: String
        }
        
        let dataHex = "0x" + data.map { String(format: "%02x", $0) }.joined()
        let request = Request(data: dataHex, format: format)
        
        return try callFFI(hawala_qr_encode_simple, input: request)
    }
    
    /// Check if data can fit in a single QR code
    public func canFitSingleQR(_ data: Data) -> Bool {
        data.count <= Self.maxSingleQRBytes
    }
    
    // MARK: - Decoding
    
    /// Decode a UR string
    /// - Parameter ur: UR string (e.g., "ur:crypto-psbt/...")
    /// - Returns: Decoded result
    public func decodeUR(_ ur: String) throws -> URDecodeResult {
        struct Request: Encodable {
            let ur: String
        }
        
        return try callFFI(hawala_qr_decode_ur, input: Request(ur: ur))
    }
    
    /// Decode UR data to bytes
    /// - Parameter ur: UR string
    /// - Returns: Decoded data and type
    public func decodeURToData(_ ur: String) throws -> (type: URType, data: Data) {
        let result = try decodeUR(ur)
        
        guard result.complete else {
            throw QRBridgeError.incompleteData
        }
        
        guard let typeStr = result.type,
              let type = URType(rawValue: typeStr) else {
            throw QRBridgeError.unknownURType
        }
        
        guard let dataHex = result.data else {
            throw QRBridgeError.noData
        }
        
        let hex = dataHex.hasPrefix("0x") ? String(dataHex.dropFirst(2)) : dataHex
        guard let data = Data(hexString: hex) else {
            throw QRBridgeError.decodingFailed
        }
        
        return (type, data)
    }
    
    // MARK: - Information
    
    /// Get supported UR types and QR limits
    public func supportedTypes() throws -> URSupportedTypes {
        return try callFFINoInput(hawala_qr_supported_types)
    }
    
    /// Get all supported UR types
    public var allURTypes: [URType] {
        URType.allCases
    }
}

// MARK: - Errors

public enum QRBridgeError: Error, LocalizedError {
    case encodingFailed
    case decodingFailed
    case ffiCallFailed
    case noData
    case incompleteData
    case unknownURType
    case payloadTooLarge
    case rustError(String)
    
    public var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Failed to encode request"
        case .decodingFailed: return "Failed to decode QR data"
        case .ffiCallFailed: return "QR FFI call failed"
        case .noData: return "No data in response"
        case .incompleteData: return "Incomplete multi-part QR data"
        case .unknownURType: return "Unknown UR type"
        case .payloadTooLarge: return "Payload too large for QR code"
        case .rustError(let msg): return msg
        }
    }
}
