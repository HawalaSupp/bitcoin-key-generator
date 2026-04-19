//
//  LedgerSolanaApp.swift
//  Hawala
//
//  Ledger Solana App Protocol Implementation
//
//  Implements communication with the Ledger Solana app for:
//  - Public key derivation (Ed25519)
//  - Address display
//  - Transaction signing
//  - Off-chain message signing
//

import Foundation

// MARK: - Ledger Solana App

/// Ledger Solana application protocol handler
public actor LedgerSolanaApp {
    // APDU class
    private static let cla: UInt8 = 0xE0
    
    // Instructions
    private enum INS: UInt8 {
        case getAppConfiguration = 0x01
        case getPublicKey = 0x02
        case signMessage = 0x03
        case signOffchainMessage = 0x07
    }
    
    private let transport: LedgerTransportProtocol
    
    public init(transport: LedgerTransportProtocol) {
        self.transport = transport
    }
    
    // MARK: - Public Key
    
    /// Get Solana public key (Ed25519)
    /// - Parameters:
    ///   - path: BIP32 derivation path (typically m/44'/501'/0'/0')
    ///   - display: Whether to verify on device
    /// - Returns: 32-byte Ed25519 public key
    public func getPublicKey(path: DerivationPath, display: Bool = false) async throws -> PublicKeyResult {
        let pathData = serializeSolanaPath(path)
        
        let apdu = LedgerAPDUCommand.build(
            cla: Self.cla,
            ins: INS.getPublicKey.rawValue,
            p1: display ? 0x01 : 0x00,
            p2: 0x00,
            data: pathData
        )
        
        let response = try await transport.exchange(apdu)
        
        guard let parsed = LedgerAPDUCommand.parseResponse(response) else {
            throw HWError.invalidResponse("Failed to parse public key response")
        }
        
        if let error = HWError.fromStatusWord(parsed.statusWord) {
            throw error
        }
        
        // Response: 32-byte Ed25519 public key
        guard parsed.data.count >= 32 else {
            throw HWError.invalidResponse("Public key response too short")
        }
        
        let publicKey = Data(parsed.data.prefix(32))
        
        // Solana address is the base58-encoded public key
        let address = LedgerBase58.encode(publicKey)
        
        return PublicKeyResult(
            publicKey: publicKey,
            chainCode: nil,
            address: address
        )
    }
    
    // MARK: - Address
    
    /// Get Solana address (base58-encoded public key)
    public func getAddress(path: DerivationPath, display: Bool = true) async throws -> AddressResult {
        let result = try await getPublicKey(path: path, display: display)
        
        guard let address = result.address else {
            // If no address, encode the public key
            let address = LedgerBase58.encode(result.publicKey)
            return AddressResult(
                address: address,
                publicKey: result.publicKey,
                path: path
            )
        }
        
        return AddressResult(
            address: address,
            publicKey: result.publicKey,
            path: path
        )
    }
    
    // MARK: - Transaction Signing
    
    /// Sign a Solana transaction
    /// - Parameters:
    ///   - path: Derivation path for signing key
    ///   - transaction: Serialized transaction message
    /// - Returns: 64-byte Ed25519 signature
    public func signTransaction(path: DerivationPath, transaction: HardwareWalletTransaction) async throws -> SignatureResult {
        let txData = transaction.rawData
        let pathData = serializeSolanaPath(path)
        
        // Send in chunks
        var offset = 0
        var chunkIndex = 0
        let maxChunkSize = 255
        
        var finalResponse: Data?
        
        while offset < txData.count || chunkIndex == 0 {
            var chunk = Data()
            
            if chunkIndex == 0 {
                // First chunk: include path
                chunk.append(pathData)
            }
            
            // Add transaction data
            let available = maxChunkSize - chunk.count
            let remaining = txData.count - offset
            let toSend = min(available, remaining)
            
            if toSend > 0 {
                chunk.append(txData[offset..<(offset + toSend)])
                offset += toSend
            }
            
            // P1: 0x00 = first, 0x80 = more following, 0x81 = last
            let p1: UInt8
            if chunkIndex == 0 && offset >= txData.count {
                p1 = 0x01 // Single chunk (first and last)
            } else if chunkIndex == 0 {
                p1 = 0x00 // First chunk, more following
            } else if offset >= txData.count {
                p1 = 0x02 // Last chunk
            } else {
                p1 = 0x01 // Middle chunk
            }
            
            let apdu = LedgerAPDUCommand.build(
                cla: Self.cla,
                ins: INS.signMessage.rawValue,
                p1: p1,
                p2: 0x00,
                data: chunk
            )
            
            let response = try await transport.exchange(apdu)
            
            guard let parsed = LedgerAPDUCommand.parseResponse(response) else {
                throw HWError.invalidResponse("Failed to parse transaction signature response")
            }
            
            if let error = HWError.fromStatusWord(parsed.statusWord) {
                throw error
            }
            
            if offset >= txData.count {
                finalResponse = parsed.data
                break
            }
            
            chunkIndex += 1
        }
        
        guard let signatureData = finalResponse else {
            throw HWError.invalidTransaction("Failed to get signature response")
        }
        
        // Response: 64-byte Ed25519 signature
        guard signatureData.count >= 64 else {
            throw HWError.invalidResponse("Signature response too short: \(signatureData.count) bytes")
        }
        
        return SignatureResult(
            signature: Data(signatureData.prefix(64)),
            recoveryId: nil,
            ethereumV: nil
        )
    }
    
    // MARK: - Off-chain Message Signing
    
    /// Sign an off-chain message (for authentication, etc.)
    /// - Parameters:
    ///   - path: Derivation path
    ///   - message: Message to sign
    /// - Returns: 64-byte Ed25519 signature
    public func signMessage(path: DerivationPath, message: Data) async throws -> SignatureResult {
        let pathData = serializeSolanaPath(path)
        
        // Build message with header
        var data = Data()
        data.append(pathData)
        
        // Message length (4 bytes, little-endian)
        var msgLen = UInt32(message.count).littleEndian
        withUnsafeBytes(of: &msgLen) { bytes in
            data.append(contentsOf: bytes)
        }
        
        // Send in chunks
        var offset = 0
        var chunkIndex = 0
        let maxChunkSize = 255
        
        // First chunk includes path and length
        while offset < message.count || chunkIndex == 0 {
            var chunk = Data()
            
            if chunkIndex == 0 {
                chunk.append(data)
            }
            
            // Add message data
            let available = maxChunkSize - chunk.count
            let remaining = message.count - offset
            let toSend = min(available, remaining)
            
            if toSend > 0 {
                chunk.append(message[offset..<(offset + toSend)])
                offset += toSend
            }
            
            let p1: UInt8
            if chunkIndex == 0 && offset >= message.count {
                p1 = 0x01
            } else if chunkIndex == 0 {
                p1 = 0x00
            } else if offset >= message.count {
                p1 = 0x02
            } else {
                p1 = 0x01
            }
            
            let apdu = LedgerAPDUCommand.build(
                cla: Self.cla,
                ins: INS.signOffchainMessage.rawValue,
                p1: p1,
                p2: 0x00,
                data: chunk
            )
            
            let response = try await transport.exchange(apdu)
            
            guard let parsed = LedgerAPDUCommand.parseResponse(response) else {
                throw HWError.invalidResponse("Failed to parse message signature response")
            }
            
            if let error = HWError.fromStatusWord(parsed.statusWord) {
                throw error
            }
            
            if offset >= message.count {
                guard parsed.data.count >= 64 else {
                    throw HWError.invalidResponse("Signature response too short")
                }
                
                return SignatureResult(
                    signature: Data(parsed.data.prefix(64)),
                    recoveryId: nil,
                    ethereumV: nil
                )
            }
            
            chunkIndex += 1
        }
        
        throw HWError.invalidTransaction("Failed to sign message")
    }
    
    // MARK: - App Configuration
    
    /// Get Solana app configuration
    public func getAppConfiguration() async throws -> SolanaAppConfiguration {
        let apdu = LedgerAPDUCommand.build(
            cla: Self.cla,
            ins: INS.getAppConfiguration.rawValue,
            p1: 0x00,
            p2: 0x00
        )
        
        let response = try await transport.exchange(apdu)
        
        guard let parsed = LedgerAPDUCommand.parseResponse(response) else {
            throw HWError.invalidResponse("Failed to parse app configuration response")
        }
        
        if let error = HWError.fromStatusWord(parsed.statusWord) {
            throw error
        }
        
        // Response: flags (1 byte) + major (1 byte) + minor (1 byte) + patch (1 byte)
        guard parsed.data.count >= 4 else {
            throw HWError.invalidResponse("Configuration response too short")
        }
        
        let flags = parsed.data[0]
        let version = "\(parsed.data[1]).\(parsed.data[2]).\(parsed.data[3])"
        
        return SolanaAppConfiguration(
            blindSigningEnabled: (flags & 0x01) != 0,
            pubkeyDisplayMode: (flags >> 1) & 0x01,
            version: version
        )
    }
    
    // MARK: - Helpers
    
    /// Serialize derivation path for Solana app
    /// Solana uses a slightly different format than Bitcoin/Ethereum
    private func serializeSolanaPath(_ path: DerivationPath) -> Data {
        var data = Data()
        
        // Number of path components (1 byte)
        data.append(UInt8(path.components.count))
        
        // Each component as 4-byte big-endian
        for comp in path.components {
            var value = comp.value.bigEndian
            withUnsafeBytes(of: &value) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        
        return data
    }
}

// MARK: - Supporting Types

/// Solana app configuration
public struct SolanaAppConfiguration: Sendable {
    public let blindSigningEnabled: Bool
    public let pubkeyDisplayMode: UInt8
    public let version: String
}

// MARK: - Base58 Encoding

/// Simple Base58 encoder for Solana addresses (Ledger module internal)
private enum LedgerBase58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    
    static func encode(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        
        // Count leading zeros
        var zeros = 0
        for byte in data {
            if byte == 0 { zeros += 1 }
            else { break }
        }
        
        // Convert to base58
        var result = [Character]()
        var bytes = Array(data)
        
        while !bytes.isEmpty && !(bytes.count == 1 && bytes[0] == 0) {
            var remainder: Int = 0
            var newBytes = [UInt8]()
            
            for byte in bytes {
                let temp = remainder * 256 + Int(byte)
                let quotient = temp / 58
                remainder = temp % 58
                
                if !newBytes.isEmpty || quotient > 0 {
                    newBytes.append(UInt8(quotient))
                }
            }
            
            result.insert(alphabet[remainder], at: 0)
            bytes = newBytes
        }
        
        // Add leading '1's for leading zeros
        for _ in 0..<zeros {
            result.insert("1", at: 0)
        }
        
        return String(result)
    }
}
