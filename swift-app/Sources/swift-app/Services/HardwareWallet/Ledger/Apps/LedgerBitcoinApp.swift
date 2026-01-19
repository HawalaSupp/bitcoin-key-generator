//
//  LedgerBitcoinApp.swift
//  Hawala
//
//  Ledger Bitcoin App Protocol Implementation
//
//  Implements communication with the Ledger Bitcoin app for:
//  - Public key derivation (BIP32/44/49/84/86)
//  - Address generation (P2PKH, P2SH-P2WPKH, P2WPKH, P2TR)
//  - Transaction signing (Legacy, SegWit, Taproot)
//  - Message signing
//

import Foundation

// MARK: - Ledger Bitcoin App

/// Ledger Bitcoin application protocol handler
public actor LedgerBitcoinApp {
    // APDU class and instructions
    private static let cla: UInt8 = 0xE0
    
    // Instructions
    private enum INS: UInt8 {
        case getWalletPublicKey = 0x40
        case getTrustedInput = 0x42
        case hashInputStart = 0x44
        case hashInputFinalize = 0x46
        case hashSign = 0x48
        case hashInputFinalizeFull = 0x4A
        case getInternalChainIndex = 0x4C
        case signMessage = 0x4E
        case getWalletExtendedPublicKey = 0xE1
    }
    
    // Address types for P2
    public enum AddressType: UInt8 {
        case legacy = 0x00       // P2PKH
        case p2shP2wpkh = 0x01   // P2SH-P2WPKH (nested SegWit)
        case bech32 = 0x02       // P2WPKH (native SegWit)
        case bech32m = 0x03      // P2TR (Taproot)
    }
    
    private let transport: LedgerTransportProtocol
    
    public init(transport: LedgerTransportProtocol) {
        self.transport = transport
    }
    
    // MARK: - Public Key
    
    /// Get public key for derivation path
    /// - Parameters:
    ///   - path: BIP32 derivation path
    ///   - display: Whether to display on device
    /// - Returns: Public key result with chain code
    public func getPublicKey(path: DerivationPath, display: Bool = false) async throws -> PublicKeyResult {
        let pathData = path.serialize()
        
        let apdu = LedgerAPDUCommand.build(
            cla: Self.cla,
            ins: INS.getWalletPublicKey.rawValue,
            p1: display ? 0x01 : 0x00,
            p2: AddressType.bech32.rawValue,
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
        // - public key (33 or 65 bytes, compressed or uncompressed)
        // - address string length (1 byte)
        // - address string (variable)
        // - chain code (32 bytes)
        
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
        guard data.count >= addressDataOffset + addressLength + 32 else {
            throw HWError.invalidResponse("Response too short for chain code")
        }
        
        let addressData = data[addressDataOffset..<(addressDataOffset + addressLength)]
        let address = String(data: addressData, encoding: .ascii)
        
        let chainCodeOffset = addressDataOffset + addressLength
        let chainCode = Data(data[chainCodeOffset..<(chainCodeOffset + 32)])
        
        return PublicKeyResult(
            publicKey: publicKey,
            chainCode: chainCode,
            address: address
        )
    }
    
    // MARK: - Address
    
    /// Get Bitcoin address for derivation path
    /// - Parameters:
    ///   - path: BIP32 derivation path
    ///   - display: Whether to verify on device
    ///   - type: Address type (defaults based on path)
    /// - Returns: Address result
    public func getAddress(path: DerivationPath, display: Bool = true, type: AddressType? = nil) async throws -> AddressResult {
        // Determine address type from path if not specified
        let addressType: AddressType
        if let type = type {
            addressType = type
        } else {
            addressType = try determineAddressType(from: path)
        }
        
        let pathData = path.serialize()
        
        let apdu = LedgerAPDUCommand.build(
            cla: Self.cla,
            ins: INS.getWalletPublicKey.rawValue,
            p1: display ? 0x01 : 0x00,
            p2: addressType.rawValue,
            data: pathData
        )
        
        let response = try await transport.exchange(apdu)
        
        guard let parsed = LedgerAPDUCommand.parseResponse(response) else {
            throw HWError.invalidResponse("Failed to parse address response")
        }
        
        if let error = HWError.fromStatusWord(parsed.statusWord) {
            throw error
        }
        
        // Parse response
        let data = parsed.data
        guard data.count >= 2 else {
            throw HWError.invalidResponse("Response too short")
        }
        
        let pubKeyLength = Int(data[0])
        guard data.count >= 1 + pubKeyLength + 1 else {
            throw HWError.invalidResponse("Invalid response format")
        }
        
        let publicKey = Data(data[1..<(1 + pubKeyLength)])
        
        let addressLengthOffset = 1 + pubKeyLength
        let addressLength = Int(data[addressLengthOffset])
        
        let addressDataOffset = addressLengthOffset + 1
        guard data.count >= addressDataOffset + addressLength else {
            throw HWError.invalidResponse("Invalid address length")
        }
        
        let addressData = data[addressDataOffset..<(addressDataOffset + addressLength)]
        guard let address = String(data: addressData, encoding: .ascii) else {
            throw HWError.invalidResponse("Failed to decode address")
        }
        
        return AddressResult(
            address: address,
            publicKey: publicKey,
            path: path
        )
    }
    
    // MARK: - Transaction Signing
    
    /// Sign a Bitcoin transaction
    /// - Parameters:
    ///   - path: Derivation path for signing key
    ///   - transaction: Transaction to sign
    /// - Returns: Signature result
    public func signTransaction(path: DerivationPath, transaction: HardwareWalletTransaction) async throws -> SignatureResult {
        // The Ledger Bitcoin signing flow is complex and involves multiple steps:
        // 1. Get trusted inputs for each input (hash previous outputs)
        // 2. Start input hashing with first input
        // 3. Continue with remaining inputs
        // 4. Finalize with outputs
        // 5. Sign each input
        
        // For now, we'll implement a simplified version that works with pre-hashed transactions
        // Full implementation would need PSBT parsing
        
        guard let preImageHashes = transaction.preImageHashes, !preImageHashes.isEmpty else {
            throw HWError.invalidTransaction("Transaction must include pre-image hashes")
        }
        
        // Sign the first hash (for simple single-input transactions)
        let hashToSign = preImageHashes[0]
        
        return try await signHash(path: path, hash: hashToSign, lockTime: 0, sigHashType: 0x01)
    }
    
    /// Sign a pre-computed hash
    private func signHash(path: DerivationPath, hash: Data, lockTime: UInt32, sigHashType: UInt8) async throws -> SignatureResult {
        // Prepare signing data
        var data = Data()
        
        // Derivation path
        data.append(path.serialize())
        
        // User validation code (skip)
        data.append(0x00)
        
        // Lock time (4 bytes, little-endian)
        var lt = lockTime.littleEndian
        withUnsafeBytes(of: &lt) { bytes in
            data.append(contentsOf: bytes)
        }
        
        // SigHash type
        data.append(sigHashType)
        
        let apdu = LedgerAPDUCommand.build(
            cla: Self.cla,
            ins: INS.hashSign.rawValue,
            p1: 0x00,
            p2: 0x00,
            data: data
        )
        
        let response = try await transport.exchange(apdu)
        
        guard let parsed = LedgerAPDUCommand.parseResponse(response) else {
            throw HWError.invalidResponse("Failed to parse signature response")
        }
        
        if let error = HWError.fromStatusWord(parsed.statusWord) {
            throw error
        }
        
        // Response is DER-encoded signature
        // The first byte is 0x30 followed by the DER structure
        var signature = parsed.data
        
        // Remove leading 0x30 if present (Ledger includes it)
        if signature.first == 0x30 {
            // Parse DER to extract r and s
            if let (r, s) = parseDERSignature(signature) {
                // Convert to 64-byte raw signature
                signature = padTo32Bytes(r) + padTo32Bytes(s)
            }
        }
        
        return SignatureResult(
            signature: signature,
            recoveryId: nil,
            ethereumV: nil
        )
    }
    
    // MARK: - Message Signing
    
    /// Sign a message (Bitcoin Message Signing format)
    /// - Parameters:
    ///   - path: Derivation path
    ///   - message: Message to sign
    /// - Returns: Signature result
    public func signMessage(path: DerivationPath, message: Data) async throws -> SignatureResult {
        // Message signing with Ledger uses INS 0x4E
        // P1 = 0x00 for first chunk, 0x80 for continuation
        // P2 = 0x00
        
        // Prepare first chunk: path + message length + message start
        var data = Data()
        data.append(path.serialize())
        
        // Message length (variable length encoding)
        let msgLen = message.count
        if msgLen < 0xFD {
            data.append(UInt8(msgLen))
        } else if msgLen <= 0xFFFF {
            data.append(0xFD)
            data.append(UInt8(msgLen & 0xFF))
            data.append(UInt8((msgLen >> 8) & 0xFF))
        } else {
            throw HWError.invalidTransaction("Message too long")
        }
        
        // Send in chunks
        var offset = 0
        let chunkSize = 230 // Leave room for header
        var p1: UInt8 = 0x00
        
        // First chunk with path
        let firstDataSize = min(message.count, chunkSize - data.count)
        data.append(message[0..<firstDataSize])
        offset = firstDataSize
        
        var apdu = LedgerAPDUCommand.build(
            cla: Self.cla,
            ins: INS.signMessage.rawValue,
            p1: p1,
            p2: 0x00,
            data: data
        )
        
        var response = try await transport.exchange(apdu)
        
        // Continue with remaining chunks
        while offset < message.count {
            let remaining = message.count - offset
            let chunkLen = min(remaining, chunkSize)
            let chunk = message[offset..<(offset + chunkLen)]
            
            apdu = LedgerAPDUCommand.build(
                cla: Self.cla,
                ins: INS.signMessage.rawValue,
                p1: 0x80, // Continuation
                p2: 0x00,
                data: Data(chunk)
            )
            
            response = try await transport.exchange(apdu)
            offset += chunkLen
        }
        
        guard let parsed = LedgerAPDUCommand.parseResponse(response) else {
            throw HWError.invalidResponse("Failed to parse message signature response")
        }
        
        if let error = HWError.fromStatusWord(parsed.statusWord) {
            throw error
        }
        
        // Response format: header (1 byte) + r (32 bytes) + s (32 bytes)
        guard parsed.data.count >= 65 else {
            throw HWError.invalidResponse("Signature response too short")
        }
        
        let header = parsed.data[0]
        let recoveryId = ((header - 27) & 0x03)
        let signature = Data(parsed.data[1..<65])
        
        return SignatureResult(
            signature: signature,
            recoveryId: recoveryId,
            ethereumV: nil
        )
    }
    
    // MARK: - Helpers
    
    /// Determine address type from BIP path
    private func determineAddressType(from path: DerivationPath) throws -> AddressType {
        guard let purpose = path.components.first else {
            throw HWError.invalidPath("Empty path")
        }
        
        switch purpose.index {
        case 44: return .legacy        // BIP44 -> P2PKH
        case 49: return .p2shP2wpkh    // BIP49 -> P2SH-P2WPKH
        case 84: return .bech32        // BIP84 -> P2WPKH
        case 86: return .bech32m       // BIP86 -> P2TR
        default: return .bech32        // Default to native SegWit
        }
    }
    
    /// Parse DER signature to extract r and s components
    private func parseDERSignature(_ der: Data) -> (r: Data, s: Data)? {
        guard der.count >= 8 else { return nil }
        guard der[0] == 0x30 else { return nil }
        
        var offset = 2 // Skip 0x30 and length byte
        
        // Parse r
        guard der[offset] == 0x02 else { return nil }
        offset += 1
        
        let rLen = Int(der[offset])
        offset += 1
        
        guard offset + rLen < der.count else { return nil }
        var r = Data(der[offset..<(offset + rLen)])
        offset += rLen
        
        // Parse s
        guard der[offset] == 0x02 else { return nil }
        offset += 1
        
        let sLen = Int(der[offset])
        offset += 1
        
        guard offset + sLen <= der.count else { return nil }
        var s = Data(der[offset..<(offset + sLen)])
        
        // Remove leading zeros if present
        while r.first == 0 && r.count > 32 {
            r = r.dropFirst()
        }
        while s.first == 0 && s.count > 32 {
            s = s.dropFirst()
        }
        
        return (r, s)
    }
    
    /// Pad data to 32 bytes (left-pad with zeros)
    private func padTo32Bytes(_ data: Data) -> Data {
        if data.count >= 32 {
            return Data(data.suffix(32))
        }
        var padded = Data(count: 32 - data.count)
        padded.append(data)
        return padded
    }
}
