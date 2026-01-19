//
//  EIP7702.swift
//  Hawala
//
//  EIP-7702 Account Delegation - Swift integration
//  Allows EOAs to temporarily delegate to contract code during a transaction.
//

import Foundation
import RustBridge

// MARK: - EIP-7702 Authorization

/// A signed EIP-7702 authorization tuple
public struct EIP7702Authorization: Codable, Equatable {
    public let chainId: UInt64
    public let address: String  // Contract address to delegate to
    public let nonce: UInt64
    public let yParity: UInt8
    public let r: String
    public let s: String
    
    /// Create an unsigned authorization (for signing)
    public init(chainId: UInt64, address: String, nonce: UInt64) {
        self.chainId = chainId
        self.address = address
        self.nonce = nonce
        self.yParity = 0
        self.r = "0x" + String(repeating: "0", count: 64)
        self.s = "0x" + String(repeating: "0", count: 64)
    }
    
    /// Create a signed authorization
    public init(chainId: UInt64, address: String, nonce: UInt64, yParity: UInt8, r: String, s: String) {
        self.chainId = chainId
        self.address = address
        self.nonce = nonce
        self.yParity = yParity
        self.r = r
        self.s = s
    }
    
    /// Whether this authorization has been signed
    public var isSigned: Bool {
        return r != "0x" + String(repeating: "0", count: 64) ||
               s != "0x" + String(repeating: "0", count: 64)
    }
}

// MARK: - Signed EIP-7702 Transaction

/// A signed EIP-7702 transaction ready for broadcast
public struct SignedEIP7702Transaction: Codable {
    public let rawTransaction: String  // Hex-encoded serialized transaction
    public let transactionHash: String
    public let yParity: UInt8
    public let r: String
    public let s: String
}

// MARK: - EIP-7702 Error

public enum EIP7702Error: Error, LocalizedError {
    case invalidPrivateKey(String)
    case invalidAddress(String)
    case signatureFailed(String)
    case invalidInput(String)
    case rustError(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidPrivateKey(let msg): return "Invalid private key: \(msg)"
        case .invalidAddress(let msg): return "Invalid address: \(msg)"
        case .signatureFailed(let msg): return "Signature failed: \(msg)"
        case .invalidInput(let msg): return "Invalid input: \(msg)"
        case .rustError(let msg): return "Rust error: \(msg)"
        }
    }
}

// MARK: - EIP-7702 Signer

/// Swift interface for EIP-7702 account delegation operations
public struct EIP7702Signer {
    
    // MARK: - Authorization Signing
    
    /// Sign an EIP-7702 authorization
    /// - Parameters:
    ///   - chainId: Chain ID for the authorization
    ///   - contractAddress: The contract address to delegate to (hex with 0x prefix)
    ///   - nonce: The nonce of the authorizing account
    ///   - privateKey: 32-byte private key (hex with 0x prefix)
    /// - Returns: Signed authorization
    public static func signAuthorization(
        chainId: UInt64,
        contractAddress: String,
        nonce: UInt64,
        privateKey: String
    ) throws -> EIP7702Authorization {
        let request: [String: Any] = [
            "chainId": chainId,
            "address": contractAddress,
            "nonce": nonce,
            "privateKey": privateKey
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw EIP7702Error.invalidInput("Failed to encode request")
        }
        
        guard let resultPtr = hawala_eip7702_sign_authorization(jsonString) else {
            throw EIP7702Error.rustError("FFI returned null")
        }
        defer { hawala_free_string(UnsafeMutablePointer(mutating: resultPtr)) }
        
        let resultString = String(cString: resultPtr)
        guard let resultData = resultString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any] else {
            throw EIP7702Error.rustError("Failed to parse response")
        }
        
        guard let success = json["success"] as? Bool, success else {
            let errorMsg = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
            throw EIP7702Error.signatureFailed(errorMsg)
        }
        
        guard let data = json["data"] as? [String: Any],
              let chainId = data["chainId"] as? UInt64,
              let address = data["address"] as? String,
              let nonce = data["nonce"] as? UInt64,
              let yParity = data["yParity"] as? Int,
              let r = data["r"] as? String,
              let s = data["s"] as? String else {
            throw EIP7702Error.rustError("Invalid response format")
        }
        
        return EIP7702Authorization(
            chainId: chainId,
            address: address,
            nonce: nonce,
            yParity: UInt8(yParity),
            r: r,
            s: s
        )
    }
    
    // MARK: - Transaction Signing
    
    /// Sign an EIP-7702 transaction
    /// - Parameters:
    ///   - chainId: Chain ID
    ///   - nonce: Transaction nonce
    ///   - maxPriorityFeePerGas: Priority fee in wei
    ///   - maxFeePerGas: Max fee in wei
    ///   - gasLimit: Gas limit
    ///   - to: Optional recipient address
    ///   - value: Value in wei (as string to handle large numbers)
    ///   - data: Optional call data (hex)
    ///   - authorizationList: List of signed authorizations
    ///   - privateKey: Transaction signer private key
    /// - Returns: Signed transaction ready for broadcast
    public static func signTransaction(
        chainId: UInt64,
        nonce: UInt64,
        maxPriorityFeePerGas: String,
        maxFeePerGas: String,
        gasLimit: UInt64,
        to: String? = nil,
        value: String = "0",
        data: String? = nil,
        authorizationList: [EIP7702Authorization],
        privateKey: String
    ) throws -> SignedEIP7702Transaction {
        var request: [String: Any] = [
            "chainId": chainId,
            "nonce": nonce,
            "maxPriorityFeePerGas": maxPriorityFeePerGas,
            "maxFeePerGas": maxFeePerGas,
            "gasLimit": gasLimit,
            "authorizationList": authorizationList.map { auth -> [String: Any] in
                return [
                    "chainId": auth.chainId,
                    "address": auth.address,
                    "nonce": auth.nonce,
                    "yParity": auth.yParity,
                    "r": auth.r,
                    "s": auth.s
                ]
            },
            "privateKey": privateKey
        ]
        
        if let to = to { request["to"] = to }
        if let data = data { request["data"] = data }
        request["value"] = value
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw EIP7702Error.invalidInput("Failed to encode request")
        }
        
        guard let resultPtr = hawala_eip7702_sign_transaction(jsonString) else {
            throw EIP7702Error.rustError("FFI returned null")
        }
        defer { hawala_free_string(UnsafeMutablePointer(mutating: resultPtr)) }
        
        let resultString = String(cString: resultPtr)
        guard let resultData = resultString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any] else {
            throw EIP7702Error.rustError("Failed to parse response")
        }
        
        guard let success = json["success"] as? Bool, success else {
            let errorMsg = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
            throw EIP7702Error.signatureFailed(errorMsg)
        }
        
        guard let data = json["data"] as? [String: Any],
              let rawTx = data["rawTransaction"] as? String,
              let txHash = data["transactionHash"] as? String,
              let yParity = data["yParity"] as? Int,
              let r = data["r"] as? String,
              let s = data["s"] as? String else {
            throw EIP7702Error.rustError("Invalid response format")
        }
        
        return SignedEIP7702Transaction(
            rawTransaction: rawTx,
            transactionHash: txHash,
            yParity: UInt8(yParity),
            r: r,
            s: s
        )
    }
    
    // MARK: - Signer Recovery
    
    /// Recover the signer address from a signed authorization
    /// - Parameter authorization: The signed authorization
    /// - Returns: The signer's Ethereum address (hex with 0x prefix)
    public static func recoverAuthorizationSigner(
        _ authorization: EIP7702Authorization
    ) throws -> String {
        let request: [String: Any] = [
            "chainId": authorization.chainId,
            "address": authorization.address,
            "nonce": authorization.nonce,
            "yParity": authorization.yParity,
            "r": authorization.r,
            "s": authorization.s
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw EIP7702Error.invalidInput("Failed to encode request")
        }
        
        guard let resultPtr = hawala_eip7702_recover_authorization_signer(jsonString) else {
            throw EIP7702Error.rustError("FFI returned null")
        }
        defer { hawala_free_string(UnsafeMutablePointer(mutating: resultPtr)) }
        
        let resultString = String(cString: resultPtr)
        guard let resultData = resultString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any] else {
            throw EIP7702Error.rustError("Failed to parse response")
        }
        
        guard let success = json["success"] as? Bool, success else {
            let errorMsg = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
            throw EIP7702Error.signatureFailed(errorMsg)
        }
        
        guard let data = json["data"] as? [String: Any],
              let signer = data["signer"] as? String else {
            throw EIP7702Error.rustError("Invalid response format")
        }
        
        return signer
    }
}

// MARK: - Transaction Builder

/// Builder for creating EIP-7702 transactions
public class EIP7702TransactionBuilder {
    private var chainId: UInt64
    private var nonce: UInt64 = 0
    private var maxPriorityFeePerGas: String = "0"
    private var maxFeePerGas: String = "0"
    private var gasLimit: UInt64 = 21000
    private var to: String?
    private var value: String = "0"
    private var data: String?
    private var authorizations: [EIP7702Authorization] = []
    
    public init(chainId: UInt64) {
        self.chainId = chainId
    }
    
    public func setNonce(_ nonce: UInt64) -> Self {
        self.nonce = nonce
        return self
    }
    
    public func setMaxPriorityFeePerGas(_ fee: String) -> Self {
        self.maxPriorityFeePerGas = fee
        return self
    }
    
    public func setMaxFeePerGas(_ fee: String) -> Self {
        self.maxFeePerGas = fee
        return self
    }
    
    public func setGasLimit(_ limit: UInt64) -> Self {
        self.gasLimit = limit
        return self
    }
    
    public func setTo(_ address: String) -> Self {
        self.to = address
        return self
    }
    
    public func setValue(_ value: String) -> Self {
        self.value = value
        return self
    }
    
    public func setData(_ data: String) -> Self {
        self.data = data
        return self
    }
    
    public func addAuthorization(_ auth: EIP7702Authorization) -> Self {
        self.authorizations.append(auth)
        return self
    }
    
    /// Sign the transaction
    public func sign(with privateKey: String) throws -> SignedEIP7702Transaction {
        return try EIP7702Signer.signTransaction(
            chainId: chainId,
            nonce: nonce,
            maxPriorityFeePerGas: maxPriorityFeePerGas,
            maxFeePerGas: maxFeePerGas,
            gasLimit: gasLimit,
            to: to,
            value: value,
            data: data,
            authorizationList: authorizations,
            privateKey: privateKey
        )
    }
}

// MARK: - Convenience Extensions

extension EIP7702Authorization {
    /// Verify this authorization was signed by a specific address
    public func verify(signer expectedSigner: String) throws -> Bool {
        let recoveredSigner = try EIP7702Signer.recoverAuthorizationSigner(self)
        return recoveredSigner.lowercased() == expectedSigner.lowercased()
    }
}
