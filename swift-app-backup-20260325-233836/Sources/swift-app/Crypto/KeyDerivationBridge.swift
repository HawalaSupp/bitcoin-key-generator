//
//  KeyDerivationBridge.swift
//  Hawala
//
//  HD Key Derivation (BIP-32 / SLIP-0010)
//  Supports both secp256k1 (Bitcoin) and ed25519 (Solana) derivation paths
//

import Foundation
import RustBridge
import CommonCrypto

// MARK: - Derivation Schemes

/// Key derivation curve scheme for HD wallets (used with Rust FFI)
public enum CurveScheme: String, Codable, Sendable {
    case secp256k1   // BIP-32 for Bitcoin/Ethereum
    case ed25519     // SLIP-0010 for Solana/Stellar
    
    public var displayName: String {
        switch self {
        case .secp256k1: return "BIP-32 (secp256k1)"
        case .ed25519: return "SLIP-0010 (Ed25519)"
        }
    }
    
    public var supportedChains: [String] {
        switch self {
        case .secp256k1: return ["bitcoin", "ethereum", "bnb", "litecoin", "polygon"]
        case .ed25519: return ["solana", "stellar", "cardano", "near", "aptos"]
        }
    }
}

// MARK: - Common Derivation Paths

/// Common BIP-44 derivation paths (static path strings)
public struct BIP44Paths {
    /// Bitcoin mainnet (BIP-44): m/44'/0'/0'/0/0
    public static let bitcoinMainnet = "m/44'/0'/0'/0/0"
    
    /// Bitcoin testnet: m/44'/1'/0'/0/0
    public static let bitcoinTestnet = "m/44'/1'/0'/0/0"
    
    /// Bitcoin Taproot (BIP-86): m/86'/0'/0'/0/0
    public static let bitcoinTaproot = "m/86'/0'/0'/0/0"
    
    /// Ethereum (BIP-44): m/44'/60'/0'/0/0
    public static let ethereum = "m/44'/60'/0'/0/0"
    
    /// Solana: m/44'/501'/0'/0'
    public static let solana = "m/44'/501'/0'/0'"
    
    /// Litecoin: m/44'/2'/0'/0/0
    public static let litecoin = "m/44'/2'/0'/0/0"
    
    /// Polygon (same as Ethereum): m/44'/60'/0'/0/0
    public static let polygon = "m/44'/60'/0'/0/0"
    
    /// Cardano: m/1852'/1815'/0'/0/0
    public static let cardano = "m/1852'/1815'/0'/0/0"
    
    /// Stellar: m/44'/148'/0'
    public static let stellar = "m/44'/148'/0'"
    
    /// Create account-specific path
    public static func account(_ index: Int, for chain: String) -> String {
        switch chain.lowercased() {
        case "bitcoin": return "m/44'/0'/\(index)'/0/0"
        case "ethereum", "polygon", "bnb": return "m/44'/60'/\(index)'/0/0"
        case "solana": return "m/44'/501'/\(index)'/0'"
        case "litecoin": return "m/44'/2'/\(index)'/0/0"
        default: return "m/44'/0'/\(index)'/0/0"
        }
    }
}

// MARK: - Result Types

/// Derived key result
public struct DerivedKey: Codable, Sendable {
    public let privateKey: String
    public let publicKey: String
    public let chainCode: String
    public let path: String
    public let curve: String
    
    enum CodingKeys: String, CodingKey {
        case privateKey = "private_key"
        case publicKey = "public_key"
        case chainCode = "chain_code"
        case path
        case curve
    }
    
    /// Get private key as Data
    public var privateKeyData: Data? {
        KeyDerivationBridge.hexToData(privateKey)
    }
    
    /// Get public key as Data
    public var publicKeyData: Data? {
        KeyDerivationBridge.hexToData(publicKey)
    }
}

// MARK: - FFI Response Types

private struct HDKeyFFIResponse<D: Codable>: Codable {
    let success: Bool
    let data: D?
    let error: HDKeyFFIError?
}

private struct HDKeyFFIError: Codable {
    let code: String
    let message: String
}

// MARK: - Key Derivation Bridge

/// Bridge for HD key derivation operations
public final class KeyDerivationBridge: @unchecked Sendable {
    public static let shared = KeyDerivationBridge()
    
    private init() {}
    
    // MARK: - Hex Helper
    
    static func hexToData(_ hex: String) -> Data? {
        let cleanHex = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        let len = cleanHex.count / 2
        var data = Data(capacity: len)
        var index = cleanHex.startIndex
        for _ in 0..<len {
            let nextIndex = cleanHex.index(index, offsetBy: 2)
            guard let byte = UInt8(cleanHex[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        return data
    }
    
    // MARK: - FFI Helper
    
    private func callFFI<T: Codable>(_ ffiCall: (UnsafePointer<CChar>?) -> UnsafePointer<CChar>?, input: some Encodable) throws -> T {
        let encoder = JSONEncoder()
        let inputData = try encoder.encode(input)
        guard let inputString = String(data: inputData, encoding: .utf8) else {
            throw HDKeyBridgeError.encodingFailed
        }
        
        guard let resultPtr = inputString.withCString({ ffiCall($0) }) else {
            throw HDKeyBridgeError.ffiCallFailed
        }
        defer { hawala_free_string(UnsafeMutablePointer(mutating: resultPtr)) }
        
        let resultString = String(cString: resultPtr)
        guard let resultData = resultString.data(using: .utf8) else {
            throw HDKeyBridgeError.decodingFailed
        }
        
        let decoder = JSONDecoder()
        let response = try decoder.decode(HDKeyFFIResponse<T>.self, from: resultData)
        
        if !response.success {
            throw HDKeyBridgeError.rustError(response.error?.message ?? "Unknown error")
        }
        
        guard let data = response.data else {
            throw HDKeyBridgeError.noData
        }
        
        return data
    }
    
    // MARK: - Key Derivation
    
    /// Derive a child key from a seed using BIP-32 or SLIP-0010
    /// - Parameters:
    ///   - scheme: Derivation scheme (secp256k1 or ed25519)
    ///   - seed: 64-byte seed from mnemonic (hex-encoded)
    ///   - path: Derivation path (e.g., "m/44'/0'/0'/0/0")
    /// - Returns: Derived key with chain code
    public func deriveKey(scheme: CurveScheme, seed: Data, path: String) throws -> DerivedKey {
        struct Request: Encodable {
            let curve: String
            let seed: String
            let path: String
        }
        
        let seedHex = "0x" + seed.map { String(format: "%02x", $0) }.joined()
        let request = Request(curve: scheme.rawValue, seed: seedHex, path: path)
        
        return try callFFI(hawala_derive_key, input: request)
    }
    
    /// Derive a Bitcoin key from seed
    public func deriveBitcoinKey(seed: Data, account: Int = 0) throws -> DerivedKey {
        let path = BIP44Paths.account(account, for: "bitcoin")
        return try deriveKey(scheme: .secp256k1, seed: seed, path: path)
    }
    
    /// Derive a Bitcoin Taproot key from seed
    public func deriveTaprootKey(seed: Data, account: Int = 0) throws -> DerivedKey {
        let path = "m/86'/0'/\(account)'/0/0"
        return try deriveKey(scheme: .secp256k1, seed: seed, path: path)
    }
    
    /// Derive an Ethereum key from seed
    public func deriveEthereumKey(seed: Data, account: Int = 0) throws -> DerivedKey {
        let path = BIP44Paths.account(account, for: "ethereum")
        return try deriveKey(scheme: .secp256k1, seed: seed, path: path)
    }
    
    /// Derive a Solana key from seed
    public func deriveSolanaKey(seed: Data, account: Int = 0) throws -> DerivedKey {
        let path = BIP44Paths.account(account, for: "solana")
        return try deriveKey(scheme: .ed25519, seed: seed, path: path)
    }
    
    /// Derive multiple accounts for a chain
    public func deriveAccounts(
        scheme: CurveScheme,
        seed: Data,
        chain: String,
        count: Int
    ) throws -> [DerivedKey] {
        var keys: [DerivedKey] = []
        for i in 0..<count {
            let path = BIP44Paths.account(i, for: chain)
            let key = try deriveKey(scheme: scheme, seed: seed, path: path)
            keys.append(key)
        }
        return keys
    }
    
    // MARK: - Seed Generation
    
    /// Generate seed from mnemonic using PBKDF2
    /// Note: This should be done through the wallet generation API
    public static func seedFromMnemonic(_ mnemonic: String, passphrase: String = "") throws -> Data {
        // Use PBKDF2-SHA512 as per BIP-39
        let password = mnemonic.decomposedStringWithCompatibilityMapping
        let salt = ("mnemonic" + passphrase).decomposedStringWithCompatibilityMapping
        
        guard let passwordData = password.data(using: .utf8),
              let saltData = salt.data(using: .utf8) else {
            throw HDKeyBridgeError.invalidMnemonic
        }
        
        var derivedKey = [UInt8](repeating: 0, count: 64)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            password,
            passwordData.count,
            [UInt8](saltData),
            saltData.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
            2048,
            &derivedKey,
            64
        )
        
        guard status == kCCSuccess else {
            throw HDKeyBridgeError.pbkdfFailed
        }
        
        return Data(derivedKey)
    }
}

// MARK: - Errors

/// HD key derivation errors (named differently to avoid conflicts)
public enum HDKeyBridgeError: Error, LocalizedError {
    case encodingFailed
    case decodingFailed
    case ffiCallFailed
    case noData
    case invalidPath
    case invalidSeed
    case invalidMnemonic
    case pbkdfFailed
    case rustError(String)
    
    public var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Failed to encode request"
        case .decodingFailed: return "Failed to decode response"
        case .ffiCallFailed: return "Key derivation FFI call failed"
        case .noData: return "No data in response"
        case .invalidPath: return "Invalid derivation path"
        case .invalidSeed: return "Invalid seed (must be 64 bytes)"
        case .invalidMnemonic: return "Invalid mnemonic phrase"
        case .pbkdfFailed: return "PBKDF2 derivation failed"
        case .rustError(let msg): return msg
        }
    }
}
