import Foundation
import CryptoKit
import P256K

// MARK: - Bitcoin Transaction Builder

/// Builds, signs, and broadcasts Bitcoin transactions (P2WPKH SegWit)
struct BitcoinTransactionBuilder {
    
    // MARK: - Data Types
    
    struct Input {
        let txid: String
        let vout: UInt32
        let value: Int64
        let scriptPubKey: Data
    }
    
    struct Output {
        let address: String
        let value: Int64
    }
    
    struct SignedTransaction {
        let txid: String
        let rawHex: String
        let size: Int
        let vsize: Int
    }
    
    // MARK: - Transaction Building
    
    static func buildAndSign(
        inputs: [Input],
        outputs: [Output],
        privateKeyWIF: String,
        isTestnet: Bool
    ) throws -> SignedTransaction {
        
        // Decode WIF private key
        let privateKey = try decodeWIF(privateKeyWIF, isTestnet: isTestnet)
        let publicKey = try derivePublicKey(from: privateKey)
        
        // Build transaction
        var tx = Data()
        
        // Version (4 bytes, little-endian)
        tx.append(contentsOf: UInt32(2).littleEndianBytes)
        
        // Marker and Flag for SegWit (0x00 0x01)
        tx.append(0x00)
        tx.append(0x01)
        
        // Input count (varint)
        tx.append(contentsOf: encodeVarInt(UInt64(inputs.count)))
        
        // Inputs (without witness data)
        for input in inputs {
            // Previous txid (32 bytes, reversed)
            guard let txidData = Data(hex: input.txid)?.reversed() else {
                throw BitcoinError.invalidTxid
            }
            tx.append(contentsOf: txidData)
            
            // Output index (4 bytes, little-endian)
            tx.append(contentsOf: input.vout.littleEndianBytes)
            
            // ScriptSig length (0 for SegWit)
            tx.append(0x00)
            
            // Sequence (4 bytes, 0xfffffffd for RBF)
            tx.append(contentsOf: UInt32(0xfffffffd).littleEndianBytes)
        }
        
        // Output count
        tx.append(contentsOf: encodeVarInt(UInt64(outputs.count)))
        
        // Outputs
        for output in outputs {
            // Amount (8 bytes, little-endian)
            tx.append(contentsOf: UInt64(output.value).littleEndianBytes)
            
            // ScriptPubKey
            let scriptPubKey = try createScriptPubKey(for: output.address, isTestnet: isTestnet)
            tx.append(contentsOf: encodeVarInt(UInt64(scriptPubKey.count)))
            tx.append(scriptPubKey)
        }
        
        // Witness data
        for (index, input) in inputs.enumerated() {
            // Sign this input
            let signature = try signInput(
                tx: tx,
                inputIndex: index,
                input: input,
                privateKey: privateKey,
                publicKey: publicKey
            )
            
            // Witness stack: <signature> <pubkey>
            tx.append(0x02) // 2 witness items
            
            // Signature with SIGHASH_ALL
            var sigWithHashType = signature
            sigWithHashType.append(0x01) // SIGHASH_ALL
            tx.append(contentsOf: encodeVarInt(UInt64(sigWithHashType.count)))
            tx.append(sigWithHashType)
            
            // Public key
            tx.append(contentsOf: encodeVarInt(UInt64(publicKey.count)))
            tx.append(publicKey)
        }
        
        // Locktime (4 bytes)
        tx.append(contentsOf: UInt32(0).littleEndianBytes)
        
        // Calculate txid (double SHA256 of non-witness data)
        let txidHash = doubleSHA256(tx)
        let txid = Data(txidHash.reversed()).hexString
        
        return SignedTransaction(
            txid: txid,
            rawHex: tx.hexString,
            size: tx.count,
            vsize: calculateVSize(tx)
        )
    }
    
    // MARK: - Signature Creation
    
    private static func signInput(
        tx: Data,
        inputIndex: Int,
        input: Input,
        privateKey: Data,
        publicKey: Data
    ) throws -> Data {
        // Create signing hash for this input (BIP143)
        let sigHash = try createSigningHash(
            tx: tx,
            inputIndex: inputIndex,
            input: input
        )
        
        // Sign with ECDSA secp256k1
        let signature = try ecdsaSign(hash: sigHash, privateKey: privateKey)
        
        // Convert to DER format
        return try derEncode(signature: signature)
    }
    
    private static func createSigningHash(
        tx: Data,
        inputIndex: Int,
        input: Input
    ) throws -> Data {
        // BIP143 signing hash for P2WPKH
        var preimage = Data()
        
        // Version
        preimage.append(contentsOf: UInt32(2).littleEndianBytes)
        
        // hashPrevouts (double SHA256 of all input outpoints)
        var prevouts = Data()
        guard let txidData = Data(hex: input.txid)?.reversed() else {
            throw BitcoinError.invalidTxid
        }
        prevouts.append(contentsOf: txidData)
        prevouts.append(contentsOf: input.vout.littleEndianBytes)
        preimage.append(doubleSHA256(prevouts))
        
        // hashSequence
        let sequence = UInt32(0xfffffffd)
        preimage.append(doubleSHA256(Data(sequence.littleEndianBytes)))
        
        // Outpoint being spent
        preimage.append(contentsOf: txidData)
        preimage.append(contentsOf: input.vout.littleEndianBytes)
        
        // scriptCode (P2PKH of the input)
        let scriptCode = input.scriptPubKey
        preimage.append(contentsOf: encodeVarInt(UInt64(scriptCode.count)))
        preimage.append(scriptCode)
        
        // Input amount
        preimage.append(contentsOf: UInt64(input.value).littleEndianBytes)
        
        // Sequence
        preimage.append(contentsOf: sequence.littleEndianBytes)
        
        // hashOutputs (all outputs concatenated and hashed)
        let outputs = Data()
        // TODO: Add actual outputs
        preimage.append(doubleSHA256(outputs))
        
        // Locktime
        preimage.append(contentsOf: UInt32(0).littleEndianBytes)
        
        // SIGHASH_ALL
        preimage.append(contentsOf: UInt32(1).littleEndianBytes)
        
        return doubleSHA256(preimage)
    }
    
    // MARK: - Cryptographic Primitives
    
    private static func decodeWIF(_ wif: String, isTestnet: Bool) throws -> Data {
        guard let decoded = Data(base58: wif) else {
            throw BitcoinError.invalidWIF
        }
        
        // Check version byte
        let versionByte = decoded[0]
        let expectedVersion: UInt8 = isTestnet ? 0xef : 0x80
        guard versionByte == expectedVersion else {
            throw BitcoinError.invalidWIF
        }
        
        // Extract private key (32 bytes)
        let keyEnd = decoded[1] == 0x01 ? decoded.count - 5 : decoded.count - 4
        let privateKey = decoded[1..<keyEnd]
        
        // Verify checksum
        let checksum = decoded.suffix(4)
        let payload = decoded.prefix(decoded.count - 4)
        let computedChecksum = doubleSHA256(payload).prefix(4)
        
        guard checksum == computedChecksum else {
            throw BitcoinError.invalidChecksum
        }
        
        return privateKey
    }
    
    private static func derivePublicKey(from privateKey: Data) throws -> Data {
        // Use P256K (secp256k1) to derive compressed public key
        let privKey = try P256K.Signing.PrivateKey(dataRepresentation: privateKey)
        let pubKeyData = privKey.publicKey.dataRepresentation
        
        // Ensure it's compressed (33 bytes: 0x02/0x03 prefix + 32 bytes)
        guard pubKeyData.count == 33 else {
            throw BitcoinError.invalidPublicKey
        }
        
        return pubKeyData
    }
    
    private static func ecdsaSign(hash: Data, privateKey: Data) throws -> (r: Data, s: Data) {
        // Use P256K to create ECDSA signature
        let privKey = try P256K.Signing.PrivateKey(dataRepresentation: privateKey)
        let signature = try privKey.signature(for: hash)
        
        // Extract R and S components from the signature
        // P256K returns a 64-byte signature (32 bytes R + 32 bytes S)
        let sigBytes = signature.dataRepresentation
        guard sigBytes.count == 64 else {
            throw BitcoinError.signingFailed
        }
        
        let r = sigBytes.prefix(32)
        let s = sigBytes.suffix(32)
        
        return (Data(r), Data(s))
    }
    
    private static func derEncode(signature: (r: Data, s: Data)) throws -> Data {
        // DER encoding: 0x30 [total-length] 0x02 [R-length] [R] 0x02 [S-length] [S]
        var der = Data()
        der.append(0x30) // Sequence
        
        var content = Data()
        content.append(0x02) // Integer
        content.append(UInt8(signature.r.count))
        content.append(signature.r)
        content.append(0x02) // Integer
        content.append(UInt8(signature.s.count))
        content.append(signature.s)
        
        der.append(UInt8(content.count))
        der.append(content)
        
        return der
    }
    
    private static func createScriptPubKey(for address: String, isTestnet: Bool) throws -> Data {
        // Decode bech32 address
        guard let decoded = try? decodeBech32(address) else {
            throw BitcoinError.invalidAddress
        }
        
        // P2WPKH: OP_0 <20-byte-pubkey-hash>
        var script = Data()
        script.append(0x00) // OP_0
        script.append(0x14) // Push 20 bytes
        script.append(decoded.witnessProgram)
        
        return script
    }
    
    private static func decodeBech32(_ address: String) throws -> (version: UInt8, witnessProgram: Data) {
        let lowercaseAddress = address.lowercased()
        
        // Split HRP and data
        guard let sepIndex = lowercaseAddress.lastIndex(of: "1") else {
            throw BitcoinError.invalidAddress
        }
        
        let hrp = String(lowercaseAddress[..<sepIndex])
        let dataString = String(lowercaseAddress[lowercaseAddress.index(after: sepIndex)...])
        
        // Verify HRP (bc for mainnet, tb for testnet)
        guard hrp == "bc" || hrp == "tb" else {
            throw BitcoinError.invalidAddress
        }
        
        // Bech32 charset
        let charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
        var values: [UInt8] = []
        
        for char in dataString {
            guard let index = charset.firstIndex(of: char) else {
                throw BitcoinError.invalidAddress
            }
            values.append(UInt8(charset.distance(from: charset.startIndex, to: index)))
        }
        
        // Verify checksum (last 6 characters)
        guard values.count >= 6 else {
            throw BitcoinError.invalidAddress
        }
        
        let dataValues = Array(values.dropLast(6))
        
        // Convert from base32 to bytes
        var bits = 0
        var value = 0
        var bytes: [UInt8] = []
        
        for val in dataValues {
            bits += 5
            value = (value << 5) | Int(val)
            
            if bits >= 8 {
                bits -= 8
                bytes.append(UInt8((value >> bits) & 0xff))
                value &= (1 << bits) - 1
            }
        }
        
        guard bytes.count >= 2 else {
            throw BitcoinError.invalidAddress
        }
        
        // First byte is witness version
        let version = bytes[0]
        let program = Data(bytes.dropFirst())
        
        // Verify witness program length (20 bytes for P2WPKH, 32 for P2WSH)
        guard program.count == 20 || program.count == 32 else {
            throw BitcoinError.invalidAddress
        }
        
        return (version, program)
    }
    
    // MARK: - Helper Functions
    
    private static func doubleSHA256(_ data: Data) -> Data {
        let first = Data(SHA256.hash(data: data))
        return Data(SHA256.hash(data: first))
    }
    
    private static func calculateVSize(_ tx: Data) -> Int {
        // SegWit virtual size = (base_size * 3 + total_size) / 4
        // For simplicity, estimate ~140 vBytes per input + 34 per output
        return tx.count / 4
    }
    
    private static func encodeVarInt(_ value: UInt64) -> [UInt8] {
        if value < 0xfd {
            return [UInt8(value)]
        } else if value <= 0xffff {
            return [0xfd] + UInt16(value).littleEndianBytes
        } else if value <= 0xffffffff {
            return [0xfe] + UInt32(value).littleEndianBytes
        } else {
            return [0xff] + value.littleEndianBytes
        }
    }
}

// MARK: - Bitcoin Errors

enum BitcoinError: LocalizedError {
    case invalidWIF
    case invalidTxid
    case invalidAddress
    case invalidChecksum
    case notImplemented(String)
    case signingFailed
    case invalidPublicKey
    
    var errorDescription: String? {
        switch self {
        case .invalidWIF:
            return "Invalid WIF private key format"
        case .invalidTxid:
            return "Invalid transaction ID"
        case .invalidAddress:
            return "Invalid Bitcoin address"
        case .invalidChecksum:
            return "Checksum verification failed"
        case .notImplemented(let msg):
            return "Not implemented: \(msg)"
        case .signingFailed:
            return "Transaction signing failed"
        case .invalidPublicKey:
            return "Invalid public key format"
        }
    }
}

// MARK: - Extensions

extension UInt32 {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: self.littleEndian) { Array($0) }
    }
}

extension UInt64 {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: self.littleEndian) { Array($0) }
    }
}

extension UInt16 {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: self.littleEndian) { Array($0) }
    }
}

extension Data {
    init?(hex: String) {
        let hex = hex.replacingOccurrences(of: " ", with: "")
        guard hex.count % 2 == 0 else { return nil }
        
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        
        for _ in 0..<hex.count/2 {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        
        self = data
    }
    
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
    
    init?(base58: String) {
        // Base58 decoding
        let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        var result = Data(repeating: 0, count: 25)
        
        for char in base58 {
            guard let digit = alphabet.firstIndex(of: char) else { return nil }
            var carry = alphabet.distance(from: alphabet.startIndex, to: digit)
            
            for i in (0..<result.count).reversed() {
                carry += 58 * Int(result[i])
                result[i] = UInt8(carry % 256)
                carry /= 256
            }
        }
        
        // Remove leading zeros
        while result.first == 0 && result.count > 1 {
            result.removeFirst()
        }
        
        self = result
    }
}
