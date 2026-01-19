//
//  ExternalSigner.swift
//  Hawala
//
//  External Signature Compilation for Hardware Wallets and Air-Gapped Signing
//
//  This module enables signing transactions on external devices (hardware wallets,
//  air-gapped computers) by:
//  1. Generating pre-image hashes from unsigned transactions
//  2. Accepting signatures from external signers
//  3. Compiling final broadcast-ready transactions
//

import Foundation
import RustBridge

// MARK: - Signing Algorithm

/// Algorithm used for signing
public enum SigningAlgorithm: String, Codable {
    case secp256k1Ecdsa = "Secp256k1Ecdsa"
    case secp256k1Schnorr = "Secp256k1Schnorr"
    case ed25519 = "Ed25519"
}

// MARK: - Pre-Image Hash

/// A hash that needs to be signed, with metadata
public struct PreImageHash: Codable {
    /// The hash to sign (hex-encoded with 0x prefix)
    public let hash: String
    
    /// Identifier for the signer (derivation path or address)
    public let signerId: String
    
    /// For UTXO chains: which input index this hash is for
    public let inputIndex: Int?
    
    /// Human-readable description
    public let description: String
    
    /// Algorithm to use for signing
    public let algorithm: String
    
    private enum CodingKeys: String, CodingKey {
        case hash
        case signerId = "signer_id"
        case inputIndex = "input_index"
        case description
        case algorithm
    }
    
    /// Get raw hash bytes
    public var hashBytes: Data? {
        let hex = hash.hasPrefix("0x") ? String(hash.dropFirst(2)) : hash
        return Data(fromHexString: hex)
    }
    
    /// Get signing algorithm enum
    public var signingAlgorithm: SigningAlgorithm? {
        SigningAlgorithm(rawValue: algorithm)
    }
}

// MARK: - External Signature

/// A signature produced by an external signer
public struct ExternalSignature: Codable {
    /// The signature bytes (hex-encoded)
    public let signature: Data
    
    /// Recovery ID for ECDSA (optional, needed for Ethereum)
    public let recoveryId: UInt8?
    
    /// Which input this signature is for (UTXO chains)
    public let inputIndex: Int?
    
    /// Public key that created this signature
    public let publicKey: Data
    
    private enum CodingKeys: String, CodingKey {
        case signature
        case recoveryId = "recovery_id"
        case inputIndex = "input_index"
        case publicKey = "public_key"
    }
    
    public init(signature: Data, publicKey: Data, recoveryId: UInt8? = nil, inputIndex: Int? = nil) {
        self.signature = signature
        self.publicKey = publicKey
        self.recoveryId = recoveryId
        self.inputIndex = inputIndex
    }
    
    /// Create from hex strings
    public init(signatureHex: String, publicKeyHex: String, recoveryId: UInt8? = nil, inputIndex: Int? = nil) throws {
        guard let sigData = Data(fromHexString: signatureHex) else {
            throw ExternalSignerError.invalidSignature("Invalid signature hex")
        }
        guard let pkData = Data(fromHexString: publicKeyHex) else {
            throw ExternalSignerError.invalidSignature("Invalid public key hex")
        }
        self.signature = sigData
        self.publicKey = pkData
        self.recoveryId = recoveryId
        self.inputIndex = inputIndex
    }
    
    // Custom encoding to output hex strings
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(signature.toHexString, forKey: .signature)
        try container.encodeIfPresent(recoveryId, forKey: .recoveryId)
        try container.encodeIfPresent(inputIndex, forKey: .inputIndex)
        try container.encode(publicKey.toHexString, forKey: .publicKey)
    }
    
    // Custom decoding from hex strings
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let sigHex = try container.decode(String.self, forKey: .signature)
        guard let sigData = Data(fromHexString: sigHex) else {
            throw DecodingError.dataCorruptedError(forKey: .signature, in: container, debugDescription: "Invalid hex")
        }
        self.signature = sigData
        
        let pkHex = try container.decode(String.self, forKey: .publicKey)
        guard let pkData = Data(fromHexString: pkHex) else {
            throw DecodingError.dataCorruptedError(forKey: .publicKey, in: container, debugDescription: "Invalid hex")
        }
        self.publicKey = pkData
        
        self.recoveryId = try container.decodeIfPresent(UInt8.self, forKey: .recoveryId)
        self.inputIndex = try container.decodeIfPresent(Int.self, forKey: .inputIndex)
    }
}

// MARK: - Compiled Transactions

/// Compiled Bitcoin transaction ready for broadcast
public struct CompiledBitcoinTransaction: Codable {
    /// Raw transaction hex (with 0x prefix)
    public let rawTx: String
    
    /// Transaction ID
    public let txid: String
    
    /// Witness transaction ID (for SegWit)
    public let wtxid: String?
    
    /// Virtual size in vbytes
    public let vsize: Int
    
    private enum CodingKeys: String, CodingKey {
        case rawTx = "raw_tx"
        case txid
        case wtxid
        case vsize
    }
    
    /// Get raw transaction bytes
    public var rawTxBytes: Data? {
        let hex = rawTx.hasPrefix("0x") ? String(rawTx.dropFirst(2)) : rawTx
        return Data(hexString: hex)
    }
}

/// Compiled Ethereum transaction ready for broadcast
public struct CompiledEthereumTransaction: Codable {
    /// Raw transaction hex (with 0x prefix)
    public let rawTx: String
    
    /// Transaction hash
    public let txHash: String
    
    /// Sender address
    public let from: String
    
    private enum CodingKeys: String, CodingKey {
        case rawTx = "raw_tx"
        case txHash = "tx_hash"
        case from
    }
}

/// Compiled Cosmos transaction ready for broadcast
public struct CompiledCosmosTransaction: Codable {
    /// Raw transaction hex
    public let rawTx: String
    
    /// Transaction hash
    public let txHash: String
    
    private enum CodingKeys: String, CodingKey {
        case rawTx = "raw_tx"
        case txHash = "tx_hash"
    }
}

/// Compiled Solana transaction ready for broadcast
public struct CompiledSolanaTransaction: Codable {
    /// Raw transaction hex
    public let rawTx: String
    
    /// Transaction signature (base58)
    public let signature: String
    
    private enum CodingKeys: String, CodingKey {
        case rawTx = "raw_tx"
        case signature
    }
}

// MARK: - Errors

public enum ExternalSignerError: Error {
    case invalidInput(String)
    case invalidSignature(String)
    case compilationFailed(String)
    case rustError(String)
}

// MARK: - External Signer

/// External signing support for hardware wallets and air-gapped devices
public struct ExternalSigner {
    
    // MARK: - Bitcoin
    
    /// Get signing hashes for a Bitcoin transaction
    /// - Parameters:
    ///   - transaction: Unsigned Bitcoin transaction as JSON
    ///   - sighashType: Sighash type (default: "All")
    /// - Returns: Array of PreImageHash to sign
    public static func getBitcoinSighashes(
        transaction: [String: Any],
        sighashType: String = "All"
    ) throws -> [PreImageHash] {
        let request: [String: Any] = [
            "transaction": transaction,
            "sighash_type": sighashType
        ]
        
        let result = try callRust("hawala_get_bitcoin_sighashes", request: request)
        
        guard let hashesArray = result["hashes"] as? [[String: Any]] else {
            throw ExternalSignerError.rustError("Missing hashes in response")
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: hashesArray)
        return try JSONDecoder().decode([PreImageHash].self, from: jsonData)
    }
    
    /// Compile a Bitcoin transaction with external signatures
    public static func compileBitcoinTransaction(
        transaction: [String: Any],
        signatures: [ExternalSignature]
    ) throws -> CompiledBitcoinTransaction {
        let sigsArray = try signatures.map { sig -> [String: Any] in
            var dict: [String: Any] = [
                "signature": sig.signature.toHexString,
                "public_key": sig.publicKey.toHexString
            ]
            if let rid = sig.recoveryId { dict["recovery_id"] = rid }
            if let idx = sig.inputIndex { dict["input_index"] = idx }
            return dict
        }
        
        let request: [String: Any] = [
            "transaction": transaction,
            "signatures": sigsArray
        ]
        
        let result = try callRust("hawala_compile_bitcoin_transaction", request: request)
        let jsonData = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(CompiledBitcoinTransaction.self, from: jsonData)
    }
    
    // MARK: - Ethereum
    
    /// Get signing hash for an Ethereum transaction
    public static func getEthereumSigningHash(
        transaction: [String: Any]
    ) throws -> PreImageHash {
        let request: [String: Any] = [
            "transaction": transaction
        ]
        
        let result = try callRust("hawala_get_ethereum_signing_hash", request: request)
        let jsonData = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(PreImageHash.self, from: jsonData)
    }
    
    /// Compile an Ethereum transaction with external signature
    public static func compileEthereumTransaction(
        transaction: [String: Any],
        signature: ExternalSignature
    ) throws -> CompiledEthereumTransaction {
        var sigDict: [String: Any] = [
            "signature": signature.signature.toHexString,
            "public_key": signature.publicKey.toHexString
        ]
        if let rid = signature.recoveryId { sigDict["recovery_id"] = rid }
        
        let request: [String: Any] = [
            "transaction": transaction,
            "signature": sigDict
        ]
        
        let result = try callRust("hawala_compile_ethereum_transaction", request: request)
        let jsonData = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(CompiledEthereumTransaction.self, from: jsonData)
    }
    
    // MARK: - Cosmos
    
    /// Get signing hash for a Cosmos transaction
    public static func getCosmosSignDocHash(
        transaction: [String: Any]
    ) throws -> PreImageHash {
        let request: [String: Any] = [
            "transaction": transaction
        ]
        
        let result = try callRust("hawala_get_cosmos_sign_doc_hash", request: request)
        let jsonData = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(PreImageHash.self, from: jsonData)
    }
    
    /// Compile a Cosmos transaction with external signature
    public static func compileCosmosTransaction(
        transaction: [String: Any],
        signature: ExternalSignature
    ) throws -> CompiledCosmosTransaction {
        var sigDict: [String: Any] = [
            "signature": signature.signature.toHexString,
            "public_key": signature.publicKey.toHexString
        ]
        if let rid = signature.recoveryId { sigDict["recovery_id"] = rid }
        
        let request: [String: Any] = [
            "transaction": transaction,
            "signature": sigDict
        ]
        
        let result = try callRust("hawala_compile_cosmos_transaction", request: request)
        let jsonData = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(CompiledCosmosTransaction.self, from: jsonData)
    }
    
    // MARK: - Solana
    
    /// Get signing hashes for a Solana transaction
    public static func getSolanaMessageHash(
        transaction: [String: Any]
    ) throws -> [PreImageHash] {
        let request: [String: Any] = [
            "transaction": transaction
        ]
        
        let result = try callRust("hawala_get_solana_message_hash", request: request)
        
        guard let hashesArray = result["hashes"] as? [[String: Any]] else {
            throw ExternalSignerError.rustError("Missing hashes in response")
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: hashesArray)
        return try JSONDecoder().decode([PreImageHash].self, from: jsonData)
    }
    
    /// Compile a Solana transaction with external signatures
    public static func compileSolanaTransaction(
        transaction: [String: Any],
        signatures: [ExternalSignature]
    ) throws -> CompiledSolanaTransaction {
        let sigsArray = try signatures.map { sig -> [String: Any] in
            var dict: [String: Any] = [
                "signature": sig.signature.toHexString,
                "public_key": sig.publicKey.toHexString
            ]
            if let idx = sig.inputIndex { dict["input_index"] = idx }
            return dict
        }
        
        let request: [String: Any] = [
            "transaction": transaction,
            "signatures": sigsArray
        ]
        
        let result = try callRust("hawala_compile_solana_transaction", request: request)
        let jsonData = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(CompiledSolanaTransaction.self, from: jsonData)
    }
    
    // MARK: - Private Helpers
    
    private static func callRust(_ function: String, request: [String: Any]) throws -> [String: Any] {
        let jsonData = try JSONSerialization.data(withJSONObject: request)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw ExternalSignerError.invalidInput("Failed to encode JSON")
        }
        
        let resultPtr: UnsafePointer<CChar>?
        
        switch function {
        case "hawala_get_bitcoin_sighashes":
            resultPtr = hawala_get_bitcoin_sighashes(jsonString)
        case "hawala_compile_bitcoin_transaction":
            resultPtr = hawala_compile_bitcoin_transaction(jsonString)
        case "hawala_get_ethereum_signing_hash":
            resultPtr = hawala_get_ethereum_signing_hash(jsonString)
        case "hawala_compile_ethereum_transaction":
            resultPtr = hawala_compile_ethereum_transaction(jsonString)
        case "hawala_get_cosmos_sign_doc_hash":
            resultPtr = hawala_get_cosmos_sign_doc_hash(jsonString)
        case "hawala_compile_cosmos_transaction":
            resultPtr = hawala_compile_cosmos_transaction(jsonString)
        case "hawala_get_solana_message_hash":
            resultPtr = hawala_get_solana_message_hash(jsonString)
        case "hawala_compile_solana_transaction":
            resultPtr = hawala_compile_solana_transaction(jsonString)
        default:
            throw ExternalSignerError.invalidInput("Unknown function: \(function)")
        }
        
        guard let ptr = resultPtr else {
            throw ExternalSignerError.rustError("Null response from Rust")
        }
        
        let resultString = String(cString: ptr)
        hawala_free_string(UnsafeMutablePointer(mutating: ptr))
        
        guard let resultData = resultString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: resultData) as? [String: Any] else {
            throw ExternalSignerError.rustError("Invalid JSON response")
        }
        
        guard let success = json["success"] as? Bool, success else {
            let errorMessage = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
            throw ExternalSignerError.rustError(errorMessage)
        }
        
        guard let data = json["data"] as? [String: Any] else {
            throw ExternalSignerError.rustError("Missing data in response")
        }
        
        return data
    }
}

// MARK: - Data Extension for ExternalSigner

private extension Data {
    /// Initialize from hex string (ExternalSigner internal use)
    init?(fromHexString hex: String) {
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
        
        self = data
    }
    
    /// Convert to hex string (ExternalSigner internal use)
    var toHexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
