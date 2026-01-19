//
//  LedgerEthereumApp.swift
//  Hawala
//
//  Ledger Ethereum App Protocol Implementation
//
//  Implements communication with the Ledger Ethereum app for:
//  - Public key and address derivation
//  - Transaction signing (Legacy, EIP-2930, EIP-1559)
//  - Personal message signing (EIP-191)
//  - Typed data signing (EIP-712)
//

import Foundation

// MARK: - Ledger Ethereum App

/// Ledger Ethereum application protocol handler
public actor LedgerEthereumApp {
    // APDU class
    private static let cla: UInt8 = 0xE0
    
    // Instructions
    private enum INS: UInt8 {
        case getPublicKey = 0x02
        case signTransaction = 0x04
        case getAppConfiguration = 0x06
        case signPersonalMessage = 0x08
        case provideERC20TokenInformation = 0x0A
        case signEIP712Message = 0x0C
        case getEthV2PublicKey = 0x10
        case setExternalPlugin = 0x12
        case provideNFTInformation = 0x14
        case setPlugin = 0x16
        case performPrivacyOperation = 0x18
        case signEIP712MessageV2 = 0x1C
    }
    
    private let transport: LedgerTransportProtocol
    
    public init(transport: LedgerTransportProtocol) {
        self.transport = transport
    }
    
    // MARK: - Public Key
    
    /// Get Ethereum public key and address
    /// - Parameters:
    ///   - path: BIP32 derivation path
    ///   - display: Whether to verify on device
    ///   - chainCode: Whether to return chain code
    /// - Returns: Public key result
    public func getPublicKey(path: DerivationPath, display: Bool = false, chainCode: Bool = true) async throws -> PublicKeyResult {
        let pathData = path.serialize()
        
        let apdu = LedgerAPDUCommand.build(
            cla: Self.cla,
            ins: INS.getPublicKey.rawValue,
            p1: display ? 0x01 : 0x00,
            p2: chainCode ? 0x01 : 0x00,
            data: pathData
        )
        
        let response = try await transport.exchange(apdu)
        
        guard let parsed = LedgerAPDUCommand.parseResponse(response) else {
            throw HWError.invalidResponse("Failed to parse public key response")
        }
        
        if let error = HWError.fromStatusWord(parsed.statusWord) {
            throw error
        }
        
        // Response format:
        // - public key length (1 byte)
        // - public key (65 bytes, uncompressed)
        // - address length (1 byte)
        // - address (40 chars, no 0x prefix)
        // - chain code (32 bytes, if requested)
        
        let data = parsed.data
        guard data.count >= 2 else {
            throw HWError.invalidResponse("Response too short")
        }
        
        let pubKeyLength = Int(data[0])
        guard data.count >= 1 + pubKeyLength + 1 else {
            throw HWError.invalidResponse("Invalid public key length")
        }
        
        let publicKey = Data(data[1..<(1 + pubKeyLength)])
        
        let addressLengthOffset = 1 + pubKeyLength
        let addressLength = Int(data[addressLengthOffset])
        
        let addressDataOffset = addressLengthOffset + 1
        guard data.count >= addressDataOffset + addressLength else {
            throw HWError.invalidResponse("Invalid address length")
        }
        
        let addressData = data[addressDataOffset..<(addressDataOffset + addressLength)]
        let address = "0x" + (String(data: addressData, encoding: .ascii) ?? "")
        
        var chainCodeData: Data?
        if chainCode && data.count >= addressDataOffset + addressLength + 32 {
            let chainCodeOffset = addressDataOffset + addressLength
            chainCodeData = Data(data[chainCodeOffset..<(chainCodeOffset + 32)])
        }
        
        return PublicKeyResult(
            publicKey: publicKey,
            chainCode: chainCodeData,
            address: address
        )
    }
    
    // MARK: - Address
    
    /// Get Ethereum address for derivation path
    public func getAddress(path: DerivationPath, display: Bool = true) async throws -> AddressResult {
        let result = try await getPublicKey(path: path, display: display, chainCode: false)
        
        guard let address = result.address else {
            throw HWError.invalidResponse("No address returned")
        }
        
        return AddressResult(
            address: address,
            publicKey: result.publicKey,
            path: path
        )
    }
    
    // MARK: - Transaction Signing
    
    /// Sign an Ethereum transaction
    /// - Parameters:
    ///   - path: Derivation path for signing key
    ///   - transaction: RLP-encoded unsigned transaction
    ///   - chainId: EIP-155 chain ID
    /// - Returns: Signature result with v, r, s
    public func signTransaction(path: DerivationPath, transaction: HardwareWalletTransaction, chainId: UInt64 = 1) async throws -> SignatureResult {
        // Transaction data is RLP-encoded
        let txData = transaction.rawData
        
        // Send in chunks
        let pathData = path.serialize()
        
        var offset = 0
        var chunkIndex = 0
        let maxChunkSize = 150 // Conservative chunk size
        
        while offset < txData.count || chunkIndex == 0 {
            var chunk = Data()
            
            if chunkIndex == 0 {
                // First chunk includes path
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
            
            let p1: UInt8 = chunkIndex == 0 ? 0x00 : 0x80
            
            let apdu = LedgerAPDUCommand.build(
                cla: Self.cla,
                ins: INS.signTransaction.rawValue,
                p1: p1,
                p2: 0x00,
                data: chunk
            )
            
            let response = try await transport.exchange(apdu)
            
            guard let parsed = LedgerAPDUCommand.parseResponse(response) else {
                throw HWError.invalidResponse("Failed to parse transaction signature response")
            }
            
            // Check for need-more-data response
            if parsed.statusWord == 0x9000 && offset < txData.count {
                chunkIndex += 1
                continue
            }
            
            if let error = HWError.fromStatusWord(parsed.statusWord) {
                throw error
            }
            
            // Final response: v (1 byte) + r (32 bytes) + s (32 bytes)
            guard parsed.data.count >= 65 else {
                throw HWError.invalidResponse("Signature response too short")
            }
            
            let v = parsed.data[0]
            let r = Data(parsed.data[1..<33])
            let s = Data(parsed.data[33..<65])
            
            // Calculate EIP-155 v value
            let ethereumV = calculateEIP155V(v: v, chainId: chainId)
            
            return SignatureResult(
                signature: r + s,
                recoveryId: v < 27 ? v : (v - 27) % 2,
                ethereumV: ethereumV
            )
        }
        
        throw HWError.invalidTransaction("Failed to sign transaction")
    }
    
    // MARK: - Personal Message Signing
    
    /// Sign a personal message (EIP-191)
    /// - Parameters:
    ///   - path: Derivation path
    ///   - message: Message to sign (will be prefixed with Ethereum Signed Message)
    /// - Returns: Signature result
    public func signMessage(path: DerivationPath, message: Data) async throws -> SignatureResult {
        // Message length is encoded as variable length
        var lengthData = Data()
        let msgLen = message.count
        if msgLen < 0xFD {
            lengthData.append(UInt8(msgLen))
        } else if msgLen <= 0xFFFF {
            lengthData.append(0xFD)
            lengthData.append(UInt8(msgLen & 0xFF))
            lengthData.append(UInt8((msgLen >> 8) & 0xFF))
        } else if msgLen <= 0xFFFFFFFF {
            lengthData.append(0xFE)
            lengthData.append(contentsOf: withUnsafeBytes(of: UInt32(msgLen).littleEndian) { Array($0) })
        } else {
            throw HWError.invalidTransaction("Message too long")
        }
        
        // First chunk: path + length + message start
        let pathData = path.serialize()
        
        var offset = 0
        var chunkIndex = 0
        let maxChunkSize = 150
        
        while offset < message.count || chunkIndex == 0 {
            var chunk = Data()
            
            if chunkIndex == 0 {
                chunk.append(pathData)
                chunk.append(lengthData)
            }
            
            // Add message data
            let available = maxChunkSize - chunk.count
            let remaining = message.count - offset
            let toSend = min(available, remaining)
            
            if toSend > 0 {
                chunk.append(message[offset..<(offset + toSend)])
                offset += toSend
            }
            
            let p1: UInt8 = chunkIndex == 0 ? 0x00 : 0x80
            
            let apdu = LedgerAPDUCommand.build(
                cla: Self.cla,
                ins: INS.signPersonalMessage.rawValue,
                p1: p1,
                p2: 0x00,
                data: chunk
            )
            
            let response = try await transport.exchange(apdu)
            
            guard let parsed = LedgerAPDUCommand.parseResponse(response) else {
                throw HWError.invalidResponse("Failed to parse message signature response")
            }
            
            // Continue if more data needed
            if parsed.statusWord == 0x9000 && offset < message.count {
                chunkIndex += 1
                continue
            }
            
            if let error = HWError.fromStatusWord(parsed.statusWord) {
                throw error
            }
            
            // Response: v (1 byte) + r (32 bytes) + s (32 bytes)
            guard parsed.data.count >= 65 else {
                throw HWError.invalidResponse("Signature response too short")
            }
            
            let v = parsed.data[0]
            let r = Data(parsed.data[1..<33])
            let s = Data(parsed.data[33..<65])
            
            return SignatureResult(
                signature: r + s,
                recoveryId: v < 27 ? v : (v - 27) % 2,
                ethereumV: UInt64(v)
            )
        }
        
        throw HWError.invalidTransaction("Failed to sign message")
    }
    
    // MARK: - EIP-712 Typed Data Signing
    
    /// Sign EIP-712 typed data
    /// - Parameters:
    ///   - path: Derivation path
    ///   - domainHash: 32-byte domain separator hash
    ///   - messageHash: 32-byte message hash
    /// - Returns: Signature result
    public func signTypedData(path: DerivationPath, domainHash: Data, messageHash: Data) async throws -> SignatureResult {
        guard domainHash.count == 32, messageHash.count == 32 else {
            throw HWError.invalidTransaction("Domain and message hashes must be 32 bytes")
        }
        
        let pathData = path.serialize()
        
        var data = Data()
        data.append(pathData)
        data.append(domainHash)
        data.append(messageHash)
        
        let apdu = LedgerAPDUCommand.build(
            cla: Self.cla,
            ins: INS.signEIP712Message.rawValue,
            p1: 0x00,
            p2: 0x00,
            data: data
        )
        
        let response = try await transport.exchange(apdu)
        
        guard let parsed = LedgerAPDUCommand.parseResponse(response) else {
            throw HWError.invalidResponse("Failed to parse EIP-712 signature response")
        }
        
        if let error = HWError.fromStatusWord(parsed.statusWord) {
            throw error
        }
        
        // Response: v (1 byte) + r (32 bytes) + s (32 bytes)
        guard parsed.data.count >= 65 else {
            throw HWError.invalidResponse("Signature response too short")
        }
        
        let v = parsed.data[0]
        let r = Data(parsed.data[1..<33])
        let s = Data(parsed.data[33..<65])
        
        return SignatureResult(
            signature: r + s,
            recoveryId: v < 27 ? v : (v - 27) % 2,
            ethereumV: UInt64(v)
        )
    }
    
    // MARK: - App Configuration
    
    /// Get Ethereum app configuration
    public func getAppConfiguration() async throws -> EthereumAppConfiguration {
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
        
        return EthereumAppConfiguration(
            arbitraryDataEnabled: (flags & 0x01) != 0,
            erc20ProvisioningEnabled: (flags & 0x02) != 0,
            starkEnabled: (flags & 0x04) != 0,
            starkV2Enabled: (flags & 0x08) != 0,
            version: version
        )
    }
    
    // MARK: - ERC-20 Token Information
    
    /// Provide ERC-20 token information for clear signing
    public func provideERC20TokenInformation(
        ticker: String,
        address: Data,
        decimals: UInt8,
        chainId: UInt32,
        signature: Data
    ) async throws {
        var data = Data()
        
        // Ticker length + ticker
        let tickerData = ticker.data(using: .utf8) ?? Data()
        data.append(UInt8(tickerData.count))
        data.append(tickerData)
        
        // Contract address (20 bytes)
        data.append(address)
        
        // Decimals
        data.append(contentsOf: withUnsafeBytes(of: UInt32(decimals).bigEndian) { Array($0) })
        
        // Chain ID
        data.append(contentsOf: withUnsafeBytes(of: chainId.bigEndian) { Array($0) })
        
        // Signature
        data.append(signature)
        
        let apdu = LedgerAPDUCommand.build(
            cla: Self.cla,
            ins: INS.provideERC20TokenInformation.rawValue,
            p1: 0x00,
            p2: 0x00,
            data: data
        )
        
        let response = try await transport.exchange(apdu)
        
        guard let parsed = LedgerAPDUCommand.parseResponse(response) else {
            throw HWError.invalidResponse("Failed to parse ERC-20 info response")
        }
        
        if let error = HWError.fromStatusWord(parsed.statusWord) {
            throw error
        }
    }
    
    // MARK: - Helpers
    
    /// Calculate EIP-155 v value
    private func calculateEIP155V(v: UInt8, chainId: UInt64) -> UInt64 {
        if v >= 35 {
            // Already EIP-155 encoded
            return UInt64(v)
        }
        
        // Legacy v value (27 or 28)
        if v == 27 || v == 28 {
            return UInt64(v)
        }
        
        // Calculate EIP-155: v = chain_id * 2 + 35 + recovery_id
        let recoveryId = v % 2
        return chainId * 2 + 35 + UInt64(recoveryId)
    }
}

// MARK: - Supporting Types

/// Ethereum app configuration
public struct EthereumAppConfiguration: Sendable {
    public let arbitraryDataEnabled: Bool
    public let erc20ProvisioningEnabled: Bool
    public let starkEnabled: Bool
    public let starkV2Enabled: Bool
    public let version: String
}
