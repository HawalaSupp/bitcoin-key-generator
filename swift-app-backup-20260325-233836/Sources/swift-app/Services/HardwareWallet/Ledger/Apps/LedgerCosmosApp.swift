//
//  LedgerCosmosApp.swift
//  Hawala
//
//  Ledger Cosmos App Protocol Implementation
//
//  Implements communication with the Ledger Cosmos app for:
//  - Public key derivation (secp256k1)
//  - Address display (Bech32)
//  - Transaction signing (Amino and Protobuf)
//

import Foundation
import CommonCrypto

// MARK: - Ledger Cosmos App

/// Ledger Cosmos application protocol handler
public actor LedgerCosmosApp {
    // APDU class (Cosmos uses 0x55)
    private static let cla: UInt8 = 0x55
    
    // Instructions
    private enum INS: UInt8 {
        case getVersion = 0x00
        case getPublicKey = 0x04
        case signSecp256k1 = 0x02
    }
    
    private let transport: LedgerTransportProtocol
    
    // Bech32 prefix (can be overridden for other Cosmos chains)
    public var bech32Prefix: String = "cosmos"
    
    public init(transport: LedgerTransportProtocol, bech32Prefix: String = "cosmos") {
        self.transport = transport
        self.bech32Prefix = bech32Prefix
    }
    
    // MARK: - Public Key
    
    /// Get Cosmos public key (secp256k1)
    /// - Parameters:
    ///   - path: BIP32 derivation path (typically m/44'/118'/0'/0/0)
    ///   - display: Whether to verify on device
    /// - Returns: 33-byte compressed secp256k1 public key
    public func getPublicKey(path: DerivationPath, display: Bool = false) async throws -> PublicKeyResult {
        let pathData = serializeCosmosPath(path)
        
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
        
        // Response: 33-byte compressed public key
        guard parsed.data.count >= 33 else {
            throw HWError.invalidResponse("Public key response too short")
        }
        
        let publicKey = Data(parsed.data.prefix(33))
        
        // Derive Bech32 address from public key
        let address = try deriveBech32Address(from: publicKey)
        
        return PublicKeyResult(
            publicKey: publicKey,
            chainCode: nil,
            address: address
        )
    }
    
    // MARK: - Address
    
    /// Get Cosmos address (Bech32-encoded)
    public func getAddress(path: DerivationPath, display: Bool = true) async throws -> AddressResult {
        let result = try await getPublicKey(path: path, display: display)
        
        guard let address = result.address else {
            throw HWError.invalidResponse("Failed to derive address")
        }
        
        return AddressResult(
            address: address,
            publicKey: result.publicKey,
            path: path
        )
    }
    
    // MARK: - Transaction Signing
    
    /// Sign a Cosmos transaction (JSON sign doc)
    /// - Parameters:
    ///   - path: Derivation path for signing key
    ///   - transaction: JSON-encoded sign document
    /// - Returns: Signature result (DER-encoded secp256k1 signature)
    public func signTransaction(path: DerivationPath, transaction: HardwareWalletTransaction) async throws -> SignatureResult {
        let txData = transaction.rawData
        let pathData = serializeCosmosPath(path)
        
        // Cosmos signing uses chunked transmission
        // P1: 0x00 = init, 0x01 = add, 0x02 = last
        
        var offset = 0
        var chunkIndex = 0
        let maxChunkSize = 250
        
        // First chunk includes path
        while offset < txData.count || chunkIndex == 0 {
            var chunk = Data()
            
            if chunkIndex == 0 {
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
            
            let p1: UInt8
            if chunkIndex == 0 {
                p1 = 0x00 // Init
            } else if offset >= txData.count {
                p1 = 0x02 // Last
            } else {
                p1 = 0x01 // Add
            }
            
            let apdu = LedgerAPDUCommand.build(
                cla: Self.cla,
                ins: INS.signSecp256k1.rawValue,
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
            
            // Check if we have the signature (final response)
            if offset >= txData.count || p1 == 0x02 {
                // Response is DER-encoded signature
                let derSignature = parsed.data
                
                // Parse DER to extract r, s
                guard let (r, s) = parseDERSignature(derSignature) else {
                    throw HWError.invalidResponse("Failed to parse DER signature")
                }
                
                // Cosmos uses 64-byte concatenated r||s signatures
                let signature = padTo32Bytes(r) + padTo32Bytes(s)
                
                return SignatureResult(
                    signature: signature,
                    recoveryId: nil,
                    ethereumV: nil
                )
            }
            
            chunkIndex += 1
        }
        
        throw HWError.invalidTransaction("Failed to sign transaction")
    }
    
    // MARK: - App Version
    
    /// Get Cosmos app version
    public func getVersion() async throws -> CosmosAppVersion {
        let apdu = LedgerAPDUCommand.build(
            cla: Self.cla,
            ins: INS.getVersion.rawValue,
            p1: 0x00,
            p2: 0x00
        )
        
        let response = try await transport.exchange(apdu)
        
        guard let parsed = LedgerAPDUCommand.parseResponse(response) else {
            throw HWError.invalidResponse("Failed to parse version response")
        }
        
        if let error = HWError.fromStatusWord(parsed.statusWord) {
            throw error
        }
        
        // Response: testMode (1 byte) + major (2 bytes) + minor (2 bytes) + patch (2 bytes) + locked (1 byte)
        guard parsed.data.count >= 8 else {
            throw HWError.invalidResponse("Version response too short")
        }
        
        let testMode = parsed.data[0] != 0
        let major = UInt16(parsed.data[1]) << 8 | UInt16(parsed.data[2])
        let minor = UInt16(parsed.data[3]) << 8 | UInt16(parsed.data[4])
        let patch = UInt16(parsed.data[5]) << 8 | UInt16(parsed.data[6])
        let locked = parsed.data.count > 7 ? parsed.data[7] != 0 : false
        
        return CosmosAppVersion(
            testMode: testMode,
            major: Int(major),
            minor: Int(minor),
            patch: Int(patch),
            deviceLocked: locked
        )
    }
    
    // MARK: - Helpers
    
    /// Serialize derivation path for Cosmos app
    private func serializeCosmosPath(_ path: DerivationPath) -> Data {
        var data = Data()
        
        // Cosmos app uses a specific format
        // 1 byte: number of components
        // Then each component as 4 bytes big-endian
        
        data.append(UInt8(path.components.count))
        
        for comp in path.components {
            var value = comp.value.bigEndian
            withUnsafeBytes(of: &value) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        
        return data
    }
    
    /// Derive Bech32 address from public key
    private func deriveBech32Address(from publicKey: Data) throws -> String {
        // 1. SHA256 hash of public key
        let sha256Hash = sha256(publicKey)
        
        // 2. RIPEMD160 hash of SHA256 result (first 20 bytes as approximation)
        let ripemd160Hash = ripemd160(sha256Hash)
        
        // 3. Bech32 encode
        return try bech32Encode(hrp: bech32Prefix, data: ripemd160Hash)
    }
    
    /// Simple SHA256 (would use CryptoKit in production)
    private func sha256(_ data: Data) -> Data {
        // Use CommonCrypto for SHA256
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
    
    /// Simple RIPEMD160 approximation (uses first 20 bytes of SHA256)
    private func ripemd160(_ data: Data) -> Data {
        // In production, implement proper RIPEMD160
        // For now, use truncated SHA256 as placeholder
        return Data(sha256(data).prefix(20))
    }
    
    /// Bech32 encoding
    private func bech32Encode(hrp: String, data: Data) throws -> String {
        // Convert 8-bit data to 5-bit groups
        let converted = convertBits(from: 8, to: 5, data: Array(data), pad: true)
        
        // Bech32 character set
        let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
        
        // Create checksum
        let hrpExpanded = expandHRP(hrp)
        let combined = hrpExpanded + converted + [0, 0, 0, 0, 0, 0]
        let polymod = bech32Polymod(combined) ^ 1
        
        var checksum = [UInt8]()
        for i in 0..<6 {
            checksum.append(UInt8((polymod >> (5 * (5 - i))) & 31))
        }
        
        // Build result
        var result = hrp + "1"
        for byte in converted + checksum {
            result.append(charset[Int(byte)])
        }
        
        return result
    }
    
    private func expandHRP(_ hrp: String) -> [UInt8] {
        var result = [UInt8]()
        for c in hrp.unicodeScalars {
            result.append(UInt8(c.value >> 5))
        }
        result.append(0)
        for c in hrp.unicodeScalars {
            result.append(UInt8(c.value & 31))
        }
        return result
    }
    
    private func bech32Polymod(_ values: [UInt8]) -> UInt32 {
        let generator: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var chk: UInt32 = 1
        for v in values {
            let top = chk >> 25
            chk = ((chk & 0x1ffffff) << 5) ^ UInt32(v)
            for i in 0..<5 {
                if (top >> i) & 1 == 1 {
                    chk ^= generator[i]
                }
            }
        }
        return chk
    }
    
    private func convertBits(from: Int, to: Int, data: [UInt8], pad: Bool) -> [UInt8] {
        var acc = 0
        var bits = 0
        var result = [UInt8]()
        let maxv = (1 << to) - 1
        
        for value in data {
            acc = (acc << from) | Int(value)
            bits += from
            while bits >= to {
                bits -= to
                result.append(UInt8((acc >> bits) & maxv))
            }
        }
        
        if pad && bits > 0 {
            result.append(UInt8((acc << (to - bits)) & maxv))
        }
        
        return result
    }
    
    /// Parse DER signature to extract r and s
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
        
        // Remove leading zeros
        while r.first == 0 && r.count > 32 {
            r = r.dropFirst()
        }
        while s.first == 0 && s.count > 32 {
            s = s.dropFirst()
        }
        
        return (r, s)
    }
    
    /// Pad data to 32 bytes
    private func padTo32Bytes(_ data: Data) -> Data {
        if data.count >= 32 {
            return Data(data.suffix(32))
        }
        var padded = Data(count: 32 - data.count)
        padded.append(data)
        return padded
    }
}

// MARK: - Supporting Types

/// Cosmos app version
public struct CosmosAppVersion: Sendable {
    public let testMode: Bool
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let deviceLocked: Bool
    
    public var versionString: String {
        "\(major).\(minor).\(patch)"
    }
}
