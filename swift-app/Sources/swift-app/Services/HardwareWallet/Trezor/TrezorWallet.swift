//
//  TrezorWallet.swift
//  Hawala
//
//  Trezor Hardware Wallet Implementation
//
//  Implements the HardwareWallet protocol for Trezor devices,
//  handling device communication, PIN/passphrase entry, and signing.
//

import Foundation
import CommonCrypto

// MARK: - Trezor Wallet

/// Main Trezor hardware wallet implementation
public actor TrezorWallet: HardwareWallet {
    // Device info
    private let deviceInfo: DiscoveredDevice
    private let transport: TrezorTransportProtocol
    
    // State
    private var _isConnected = false
    private var _features: TrezorFeatures?
    private var _deviceStatus: HardwareDeviceStatus = .disconnected
    
    // Callbacks for user interaction
    public var pinCallback: (@Sendable () async -> String?)?
    public var passphraseCallback: (@Sendable () async -> String?)?
    public var buttonCallback: (@Sendable (String) async -> Void)?
    
    // MARK: - HardwareWallet Protocol
    
    public nonisolated var name: String {
        deviceInfo.name ?? deviceInfo.deviceType.displayName
    }
    
    public nonisolated var deviceType: HardwareDeviceType {
        deviceInfo.deviceType
    }
    
    public var connectionStatus: HardwareDeviceStatus {
        _deviceStatus
    }
    
    public var isConnected: Bool {
        _isConnected
    }
    
    public var supportedChains: [SupportedChain] {
        [.bitcoin, .ethereum, .solana, .cosmos, .polygon, .arbitrum, .optimism, .bsc]
    }
    
    public var firmwareVersion: String? {
        guard let f = _features else { return nil }
        return "\(f.majorVersion ?? 0).\(f.minorVersion ?? 0).\(f.patchVersion ?? 0)"
    }
    
    // MARK: - Initialization
    
    public init(deviceInfo: DiscoveredDevice) {
        self.deviceInfo = deviceInfo
        self.transport = TrezorTransportFactory.create(for: deviceInfo)
    }
    
    // MARK: - Connection
    
    public func connect() async throws {
        _deviceStatus = .connecting
        
        do {
            try await transport.open()
            _isConnected = true
            
            // Initialize device and get features
            let features = try await initialize()
            _features = features
            
            // Check device state
            if features.pinProtection == true && features.unlocked != true {
                _deviceStatus = .requiresPinEntry
            } else if features.passphraseProtection == true {
                _deviceStatus = .requiresPassphrase
            } else {
                _deviceStatus = .ready
            }
        } catch {
            _deviceStatus = .error(.connectionFailed(error.localizedDescription))
            throw error
        }
    }
    
    public func disconnect() async throws {
        try await transport.close()
        _isConnected = false
        _features = nil
        _deviceStatus = .disconnected
    }
    
    // MARK: - Public Key
    
    public func getPublicKey(path: DerivationPath, curve: EllipticCurveType) async throws -> PublicKeyResult {
        let addressN = path.components.map { $0.value }
        
        let request = TrezorGetPublicKey(
            addressN: addressN,
            ecdsaCurveName: curve.trezorCurveName,
            showDisplay: false
        )
        
        let response = try await call(request)
        
        guard let publicKey = try TrezorPublicKey.decode(from: response.data).node?.publicKey else {
            throw HWError.invalidResponse("No public key in response")
        }
        
        let chainCode = try TrezorPublicKey.decode(from: response.data).node?.chainCode
        
        return PublicKeyResult(
            publicKey: publicKey,
            chainCode: chainCode,
            address: nil
        )
    }
    
    // MARK: - Address
    
    public func getAddress(path: DerivationPath, chain: SupportedChain, display: Bool) async throws -> AddressResult {
        // Get public key and derive address
        let pubKeyResult = try await getPublicKey(path: path, curve: chain.curve)
        
        // Address derivation would depend on chain
        // For simplicity, return the public key hex as placeholder
        let address: String
        switch chain {
        case .ethereum, .polygon, .arbitrum, .optimism, .bsc:
            address = try deriveEthereumAddress(from: pubKeyResult.publicKey)
        case .bitcoin:
            address = try deriveBitcoinAddress(from: pubKeyResult.publicKey, path: path)
        default:
            address = pubKeyResult.publicKey.hexEncodedString()
        }
        
        if display {
            // Request address verification on device
            await buttonCallback?("Verify address on your Trezor")
        }
        
        return AddressResult(
            address: address,
            publicKey: pubKeyResult.publicKey,
            path: path
        )
    }
    
    // MARK: - Transaction Signing
    
    public func signTransaction(path: DerivationPath, transaction: HardwareWalletTransaction, chain: SupportedChain) async throws -> SignatureResult {
        // Transaction signing varies by chain
        // This is a simplified implementation
        
        switch chain {
        case .ethereum, .polygon, .arbitrum, .optimism, .bsc:
            return try await signEthereumTransaction(path: path, transaction: transaction, chainId: chain.getChainId())
        case .bitcoin:
            throw HWError.notImplemented("Bitcoin transaction signing requires multi-step protocol")
        case .solana:
            return try await signSolanaTransaction(path: path, transaction: transaction)
        default:
            throw HWError.unsupportedChain(chain.rawValue)
        }
    }
    
    // MARK: - Message Signing
    
    public func signMessage(path: DerivationPath, message: Data, chain: SupportedChain) async throws -> SignatureResult {
        let addressN = path.components.map { $0.value }
        
        let coinName: String
        switch chain {
        case .bitcoin: coinName = "Bitcoin"
        case .ethereum: coinName = "Ethereum" // Trezor uses this for personal_sign
        default: coinName = "Bitcoin"
        }
        
        let request = TrezorSignMessage(
            addressN: addressN,
            message: message,
            coinName: coinName
        )
        
        let response = try await call(request)
        
        let decoded = try TrezorMessageSignature.decode(from: response.data)
        
        guard let signature = decoded.signature else {
            throw HWError.invalidResponse("No signature in response")
        }
        
        return SignatureResult(
            signature: signature,
            recoveryId: nil,
            ethereumV: nil
        )
    }
    
    // MARK: - EIP-712 Typed Data
    
    public func signTypedData(path: DerivationPath, domainHash: Data, messageHash: Data) async throws -> SignatureResult {
        // Trezor uses EthereumSignTypedHash for pre-hashed EIP-712 data
        throw HWError.notImplemented("EIP-712 signing requires full typed data, not just hashes")
    }
    
    // MARK: - Device Communication
    
    /// Initialize device and get features
    private func initialize() async throws -> TrezorFeatures {
        let request = TrezorInitialize()
        let response = try await call(request)
        
        guard response.messageType == TrezorMessageType.features.rawValue else {
            throw HWError.invalidResponse("Expected Features, got \(response.messageType)")
        }
        
        return try TrezorFeatures.decode(from: response.data)
    }
    
    /// Call a Trezor message and handle interactive responses
    private func call<T: TrezorMessage>(_ message: T) async throws -> (messageType: UInt16, data: Data) {
        var response = try await transport.exchange(
            messageType: T.messageType.rawValue,
            data: message.encode()
        )
        
        // Handle interactive responses
        while true {
            switch TrezorMessageType(rawValue: response.messageType) {
            case .buttonRequest:
                // User needs to confirm on device
                await buttonCallback?("Please confirm on your Trezor")
                
                let ack = TrezorButtonAck()
                response = try await transport.exchange(
                    messageType: TrezorMessageType.buttonAck.rawValue,
                    data: ack.encode()
                )
                
            case .pinMatrixRequest:
                // PIN entry required
                guard let pin = await pinCallback?() else {
                    throw HWError.userRejected
                }
                
                let ack = TrezorPinMatrixAck(pin: pin)
                response = try await transport.exchange(
                    messageType: TrezorMessageType.pinMatrixAck.rawValue,
                    data: ack.encode()
                )
                
            case .passphraseRequest:
                // Passphrase entry required
                guard let passphrase = await passphraseCallback?() else {
                    throw HWError.userRejected
                }
                
                let ack = TrezorPassphraseAck(passphrase: passphrase)
                response = try await transport.exchange(
                    messageType: TrezorMessageType.passphraseAck.rawValue,
                    data: ack.encode()
                )
                
            case .failure:
                let failure = try TrezorFailure.decode(from: response.data)
                throw HWError.unknown(failure.message ?? "Unknown Trezor error")
                
            default:
                // Final response
                return response
            }
        }
    }
    
    // MARK: - Ethereum Transaction Signing
    
    private func signEthereumTransaction(path: DerivationPath, transaction: HardwareWalletTransaction, chainId: UInt64) async throws -> SignatureResult {
        // EthereumSignTx message would need full implementation
        // This is a placeholder showing the structure
        
        let addressN = path.components.map { $0.value }
        
        // Build EthereumSignTx protobuf message
        var data = Data()
        
        // Field 1: address_n (repeated uint32)
        for n in addressN {
            data.append(contentsOf: encodeVarintField(fieldNumber: 1, value: UInt64(n)))
        }
        
        // Field 2: nonce (bytes)
        // Field 3: gas_price (bytes)
        // Field 4: gas_limit (bytes)
        // Field 5: to (bytes, 20 bytes)
        // Field 6: value (bytes)
        // Field 7: data_initial_chunk (bytes)
        // Field 8: data_length (uint32)
        // Field 9: chain_id (uint64)
        
        // For EIP-1559:
        // Field 15: max_fee_per_gas (bytes)
        // Field 16: max_priority_fee_per_gas (bytes)
        
        // Add chain_id
        data.append(contentsOf: encodeVarintField(fieldNumber: 9, value: chainId))
        
        // Add transaction data
        data.append(contentsOf: encodeBytes(fieldNumber: 7, value: transaction.rawData))
        
        // This would continue with more fields...
        throw HWError.notImplemented("Full Ethereum transaction signing requires complete EthereumSignTx implementation")
    }
    
    // MARK: - Solana Transaction Signing
    
    private func signSolanaTransaction(path: DerivationPath, transaction: HardwareWalletTransaction) async throws -> SignatureResult {
        let addressN = path.components.map { $0.value }
        
        // SolanaSignTx message
        var data = Data()
        
        for n in addressN {
            data.append(contentsOf: encodeVarintField(fieldNumber: 1, value: UInt64(n)))
        }
        
        data.append(contentsOf: encodeBytes(fieldNumber: 2, value: transaction.rawData))
        
        let response = try await transport.exchange(
            messageType: TrezorMessageType.solanaSignTx.rawValue,
            data: data
        )
        
        // Parse SolanaSignedTx response
        var offset = 0
        var signature: Data?
        
        while offset < response.data.count {
            let (fieldNumber, wireType, newOffset) = decodeTag(data: response.data, offset: offset)
            offset = newOffset
            
            if fieldNumber == 1 && wireType == 2 {
                let (sig, nextOffset) = try decodeBytes(data: response.data, offset: offset)
                signature = sig
                offset = nextOffset
            } else {
                offset = skipField(data: response.data, offset: offset, wireType: wireType)
            }
        }
        
        guard let sig = signature else {
            throw HWError.invalidResponse("No signature in response")
        }
        
        return SignatureResult(
            signature: sig,
            recoveryId: nil,
            ethereumV: nil
        )
    }
    
    // MARK: - Address Derivation Helpers
    
    private func deriveEthereumAddress(from publicKey: Data) throws -> String {
        // Ethereum address: last 20 bytes of Keccak256(uncompressed public key without prefix)
        // In production, use proper Keccak256 implementation
        
        var keyData = publicKey
        if keyData.first == 0x04 {
            keyData = keyData.dropFirst() // Remove uncompressed prefix
        }
        
        // Placeholder - in production, use Keccak256
        let hash = sha256(keyData) // Using SHA256 as placeholder
        let address = "0x" + hash.suffix(20).hexEncodedString()
        
        return address
    }
    
    private func deriveBitcoinAddress(from publicKey: Data, path: DerivationPath) throws -> String {
        // Would derive proper Bitcoin address based on path (P2PKH, P2WPKH, etc.)
        return "bc1..." // Placeholder
    }
    
    private func sha256(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
}

// MARK: - Curve Extension

extension EllipticCurveType {
    var trezorCurveName: String? {
        switch self {
        case .secp256k1: return "secp256k1"
        case .ed25519: return "ed25519"
        case .nist256p1: return "nist256p1"
        case .sr25519: return nil // Not supported by Trezor
        }
    }
}

// MARK: - Protobuf Helpers (duplicated for module isolation)

private func encodeVarint(_ value: UInt64) -> Data {
    var data = Data()
    var v = value
    while v > 0x7F {
        data.append(UInt8((v & 0x7F) | 0x80))
        v >>= 7
    }
    data.append(UInt8(v))
    return data
}

private func encodeTag(fieldNumber: Int, wireType: Int) -> Data {
    let tag = (fieldNumber << 3) | wireType
    return encodeVarint(UInt64(tag))
}

private func encodeVarintField(fieldNumber: Int, value: UInt64) -> Data {
    var data = encodeTag(fieldNumber: fieldNumber, wireType: 0)
    data.append(contentsOf: encodeVarint(value))
    return data
}

private func encodeBytes(fieldNumber: Int, value: Data) -> Data {
    var data = encodeTag(fieldNumber: fieldNumber, wireType: 2)
    data.append(contentsOf: encodeVarint(UInt64(value.count)))
    data.append(value)
    return data
}

private func decodeTag(data: Data, offset: Int) -> (fieldNumber: Int, wireType: Int, newOffset: Int) {
    let (tag, newOffset) = decodeVarint(data: data, offset: offset)
    return (Int(tag >> 3), Int(tag & 0x07), newOffset)
}

private func decodeVarint(data: Data, offset: Int) -> (value: UInt64, newOffset: Int) {
    var result: UInt64 = 0
    var shift = 0
    var pos = offset
    
    while pos < data.count {
        let byte = data[pos]
        result |= UInt64(byte & 0x7F) << shift
        pos += 1
        if byte & 0x80 == 0 { break }
        shift += 7
    }
    
    return (result, pos)
}

private func decodeBytes(data: Data, offset: Int) throws -> (value: Data, newOffset: Int) {
    let (length, nextOffset) = decodeVarint(data: data, offset: offset)
    let end = nextOffset + Int(length)
    guard end <= data.count else {
        throw HWError.invalidResponse("Bytes extend beyond data")
    }
    return (Data(data[nextOffset..<end]), end)
}

private func skipField(data: Data, offset: Int, wireType: Int) -> Int {
    switch wireType {
    case 0:
        let (_, newOffset) = decodeVarint(data: data, offset: offset)
        return newOffset
    case 1: return offset + 8
    case 2:
        let (length, nextOffset) = decodeVarint(data: data, offset: offset)
        return nextOffset + Int(length)
    case 5: return offset + 4
    default: return offset + 1
    }
}

// Note: Data.hexEncodedString() is defined elsewhere in the codebase
