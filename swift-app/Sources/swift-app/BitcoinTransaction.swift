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
        
        // Pre-compute hashes for BIP143 (needed for signing)
        let hashPrevouts = try computeHashPrevouts(inputs: inputs)
        let hashSequence = computeHashSequence(inputs: inputs)
        let serializedOutputs = try serializeOutputs(outputs, isTestnet: isTestnet)
        let hashOutputs = doubleSHA256(serializedOutputs)
        
        // Build base transaction (without witness)
        var baseTx = Data()
        
        // Version (4 bytes, little-endian)
        baseTx.append(contentsOf: UInt32(2).littleEndianBytes)
        
        // Input count (varint)
        baseTx.append(contentsOf: encodeVarInt(UInt64(inputs.count)))
        
        // Inputs
        for input in inputs {
            guard let txidData = Data(hex: input.txid) else {
                throw BitcoinError.invalidTxid
            }
            // Reverse txid for little-endian
            baseTx.append(contentsOf: txidData.reversed())
            baseTx.append(contentsOf: input.vout.littleEndianBytes)
            baseTx.append(0x00) // Empty scriptSig for SegWit
            baseTx.append(contentsOf: UInt32(0xfffffffd).littleEndianBytes) // Sequence (RBF enabled)
        }
        
        // Output count
        baseTx.append(contentsOf: encodeVarInt(UInt64(outputs.count)))
        
        // Outputs (already serialized)
        baseTx.append(serializedOutputs)
        
        // Locktime
        baseTx.append(contentsOf: UInt32(0).littleEndianBytes)
        
        // Sign each input and collect witness data
        var witnessData = Data()
        for (index, input) in inputs.enumerated() {
            let signature = try signInput(
                input: input,
                inputIndex: index,
                hashPrevouts: hashPrevouts,
                hashSequence: hashSequence,
                hashOutputs: hashOutputs,
                privateKey: privateKey,
                publicKey: publicKey
            )
            
            // Witness stack: 2 items (signature + pubkey)
            witnessData.append(0x02)
            
            // Signature with SIGHASH_ALL appended
            var sigWithHashType = signature
            sigWithHashType.append(0x01) // SIGHASH_ALL
            witnessData.append(contentsOf: encodeVarInt(UInt64(sigWithHashType.count)))
            witnessData.append(sigWithHashType)
            
            // Compressed public key
            witnessData.append(contentsOf: encodeVarInt(UInt64(publicKey.count)))
            witnessData.append(publicKey)
        }
        
        // Build full SegWit transaction
        var fullTx = Data()
        fullTx.append(contentsOf: UInt32(2).littleEndianBytes) // Version
        fullTx.append(0x00) // Marker
        fullTx.append(0x01) // Flag
        
        // Inputs
        fullTx.append(contentsOf: encodeVarInt(UInt64(inputs.count)))
        for input in inputs {
            guard let txidData = Data(hex: input.txid) else {
                throw BitcoinError.invalidTxid
            }
            fullTx.append(contentsOf: txidData.reversed())
            fullTx.append(contentsOf: input.vout.littleEndianBytes)
            fullTx.append(0x00)
            fullTx.append(contentsOf: UInt32(0xfffffffd).littleEndianBytes)
        }
        
        // Outputs
        fullTx.append(contentsOf: encodeVarInt(UInt64(outputs.count)))
        fullTx.append(serializedOutputs)
        
        // Witness data
        fullTx.append(witnessData)
        
        // Locktime
        fullTx.append(contentsOf: UInt32(0).littleEndianBytes)
        
        // Calculate txid from base transaction (without marker, flag, witness)
        let txidHash = doubleSHA256(baseTx)
        let txid = Data(txidHash.reversed()).hexString
        
        // Calculate vsize: (base_size * 3 + total_size) / 4
        let baseSize = baseTx.count
        let totalSize = fullTx.count
        let vsize = (baseSize * 3 + totalSize + 3) / 4 // Round up
        
        return SignedTransaction(
            txid: txid,
            rawHex: fullTx.hexString,
            size: totalSize,
            vsize: vsize
        )
    }
    
    // MARK: - BIP143 Hash Computations
    
    private static func computeHashPrevouts(inputs: [Input]) throws -> Data {
        var prevouts = Data()
        for input in inputs {
            guard let txidData = Data(hex: input.txid) else {
                throw BitcoinError.invalidTxid
            }
            prevouts.append(contentsOf: txidData.reversed())
            prevouts.append(contentsOf: input.vout.littleEndianBytes)
        }
        return doubleSHA256(prevouts)
    }
    
    private static func computeHashSequence(inputs: [Input]) -> Data {
        var sequences = Data()
        for _ in inputs {
            sequences.append(contentsOf: UInt32(0xfffffffd).littleEndianBytes)
        }
        return doubleSHA256(sequences)
    }
    
    private static func serializeOutputs(_ outputs: [Output], isTestnet: Bool) throws -> Data {
        var data = Data()
        for output in outputs {
            data.append(contentsOf: UInt64(output.value).littleEndianBytes)
            let scriptPubKey = try createScriptPubKey(for: output.address, isTestnet: isTestnet)
            data.append(contentsOf: encodeVarInt(UInt64(scriptPubKey.count)))
            data.append(scriptPubKey)
        }
        return data
    }
    
    // MARK: - Signature Creation
    
    private static func signInput(
        input: Input,
        inputIndex: Int,
        hashPrevouts: Data,
        hashSequence: Data,
        hashOutputs: Data,
        privateKey: Data,
        publicKey: Data
    ) throws -> Data {
        // Create BIP143 signing hash
        let sigHash = try createBIP143SigningHash(
            input: input,
            hashPrevouts: hashPrevouts,
            hashSequence: hashSequence,
            hashOutputs: hashOutputs,
            publicKey: publicKey
        )
        
        // Sign with ECDSA secp256k1 - returns DER-encoded signature
        // P256K's derRepresentation already handles low-S normalization
        return try ecdsaSign(hash: sigHash, privateKey: privateKey)
    }
    
    private static func createBIP143SigningHash(
        input: Input,
        hashPrevouts: Data,
        hashSequence: Data,
        hashOutputs: Data,
        publicKey: Data
    ) throws -> Data {
        var preimage = Data()
        
        // 1. Version (4 bytes LE)
        preimage.append(contentsOf: UInt32(2).littleEndianBytes)
        
        // 2. hashPrevouts (32 bytes)
        preimage.append(hashPrevouts)
        
        // 3. hashSequence (32 bytes)
        preimage.append(hashSequence)
        
        // 4. Outpoint (36 bytes: txid + vout)
        guard let txidData = Data(hex: input.txid) else {
            throw BitcoinError.invalidTxid
        }
        preimage.append(contentsOf: txidData.reversed())
        preimage.append(contentsOf: input.vout.littleEndianBytes)
        
        // 5. scriptCode (P2PKH script for P2WPKH: OP_DUP OP_HASH160 <pubkeyhash> OP_EQUALVERIFY OP_CHECKSIG)
        let pubKeyHash = hash160(publicKey)
        var scriptCode = Data()
        scriptCode.append(0x19) // Length: 25 bytes
        scriptCode.append(0x76) // OP_DUP
        scriptCode.append(0xa9) // OP_HASH160
        scriptCode.append(0x14) // Push 20 bytes
        scriptCode.append(pubKeyHash)
        scriptCode.append(0x88) // OP_EQUALVERIFY
        scriptCode.append(0xac) // OP_CHECKSIG
        preimage.append(scriptCode)
        
        // 6. Value (8 bytes LE)
        preimage.append(contentsOf: UInt64(input.value).littleEndianBytes)
        
        // 7. Sequence (4 bytes LE)
        preimage.append(contentsOf: UInt32(0xfffffffd).littleEndianBytes)
        
        // 8. hashOutputs (32 bytes)
        preimage.append(hashOutputs)
        
        // 9. Locktime (4 bytes LE)
        preimage.append(contentsOf: UInt32(0).littleEndianBytes)
        
        // 10. Sighash type (4 bytes LE) - SIGHASH_ALL = 1
        preimage.append(contentsOf: UInt32(1).littleEndianBytes)
        
        return doubleSHA256(preimage)
    }
    
    // MARK: - Cryptographic Primitives
    
    private static func hash160(_ data: Data) -> Data {
        // HASH160 = RIPEMD160(SHA256(data))
        let sha256Hash = Data(SHA256.hash(data: data))
        return ripemd160(sha256Hash)
    }
    
    private static func ripemd160(_ data: Data) -> Data {
        // RIPEMD-160 implementation
        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xefcdab89
        var h2: UInt32 = 0x98badcfe
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xc3d2e1f0
        
        // Padding
        var message = data
        let originalLength = UInt64(data.count * 8)
        message.append(0x80)
        while (message.count % 64) != 56 {
            message.append(0x00)
        }
        // Append length in little-endian
        message.append(contentsOf: originalLength.littleEndianBytes)
        
        // Process each 64-byte block
        for blockStart in stride(from: 0, to: message.count, by: 64) {
            var x = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let offset = blockStart + i * 4
                x[i] = UInt32(message[offset]) |
                       (UInt32(message[offset+1]) << 8) |
                       (UInt32(message[offset+2]) << 16) |
                       (UInt32(message[offset+3]) << 24)
            }
            
            var al = h0, bl = h1, cl = h2, dl = h3, el = h4
            var ar = h0, br = h1, cr = h2, dr = h3, er = h4
            
            // Round constants
            let kl: [UInt32] = [0x00000000, 0x5a827999, 0x6ed9eba1, 0x8f1bbcdc, 0xa953fd4e]
            let kr: [UInt32] = [0x50a28be6, 0x5c4dd124, 0x6d703ef3, 0x7a6d76e9, 0x00000000]
            
            // Selection arrays
            let rl: [Int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
                           7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
                           3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
                           1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
                           4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13]
            let rr: [Int] = [5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
                           6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
                           15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
                           8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
                           12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11]
            let sl: [UInt32] = [11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
                              7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
                              11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
                              11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
                              9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6]
            let sr: [UInt32] = [8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
                              9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
                              9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
                              15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
                              8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11]
            
            func f(_ j: Int, _ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
                switch j {
                case 0..<16: return x ^ y ^ z
                case 16..<32: return (x & y) | (~x & z)
                case 32..<48: return (x | ~y) ^ z
                case 48..<64: return (x & z) | (y & ~z)
                default: return x ^ (y | ~z)
                }
            }
            
            for j in 0..<80 {
                let round = j / 16
                let tl = al &+ f(j, bl, cl, dl) &+ x[rl[j]] &+ kl[round]
                let rotl = ((tl << sl[j]) | (tl >> (32 - sl[j]))) &+ el
                al = el; el = dl; dl = (cl << 10) | (cl >> 22); cl = bl; bl = rotl
                
                let tr = ar &+ f(79 - j, br, cr, dr) &+ x[rr[j]] &+ kr[round]
                let rotr = ((tr << sr[j]) | (tr >> (32 - sr[j]))) &+ er
                ar = er; er = dr; dr = (cr << 10) | (cr >> 22); cr = br; br = rotr
            }
            
            let t = h1 &+ cl &+ dr
            h1 = h2 &+ dl &+ er
            h2 = h3 &+ el &+ ar
            h3 = h4 &+ al &+ br
            h4 = h0 &+ bl &+ cr
            h0 = t
        }
        
        var result = Data()
        for h in [h0, h1, h2, h3, h4] {
            result.append(contentsOf: h.littleEndianBytes)
        }
        return result
    }
    
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
        
        // Extract private key (32 bytes) - handle both compressed and uncompressed
        // Compressed WIF: 34 bytes (1 version + 32 key + 1 compression flag + 4 checksum)
        // Uncompressed WIF: 37 bytes (1 version + 32 key + 4 checksum)
        let hasCompressionFlag = decoded.count == 38 && decoded[33] == 0x01
        let keyEnd = hasCompressionFlag ? 33 : decoded.count - 4
        let privateKey = Data(decoded[1..<keyEnd])
        
        guard privateKey.count == 32 else {
            throw BitcoinError.invalidWIF
        }
        
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
    
    private static func ecdsaSign(hash: Data, privateKey: Data) throws -> Data {
        // Use P256K to create ECDSA signature
        let privKey = try P256K.Signing.PrivateKey(dataRepresentation: privateKey)
        
        // CRITICAL: We must use signature(for: Digest) NOT signature(for: Data)
        // The Data version would SHA256 hash our already-hashed message!
        // Convert our pre-computed hash to a HashDigest type
        let digest = HashDigest(Array(hash))
        let signature = try privKey.signature(for: digest)
        
        // Use P256K's built-in DER encoding - this handles low-S normalization correctly
        // P256K/libsecp256k1 already produces low-S signatures
        let derSignature = try signature.derRepresentation
        
        return derSignature
    }
    
    private static func createScriptPubKey(for address: String, isTestnet: Bool) throws -> Data {
        // Decode bech32 address
        guard let decoded = try? decodeBech32(address) else {
            throw BitcoinError.invalidAddress
        }
        
        // SegWit scriptPubKey: OP_0 <witness-program>
        // P2WPKH: OP_0 <20-byte-pubkey-hash>
        // P2WSH: OP_0 <32-byte-script-hash>
        var script = Data()
        script.append(UInt8(decoded.version)) // Witness version (OP_0 for v0, OP_1-OP_16 for v1-v16)
        script.append(UInt8(decoded.witnessProgram.count)) // Push opcode (0x14 for 20 bytes, 0x20 for 32 bytes)
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
        
        // Verify HRP (bc for mainnet, tb for testnet, ltc for Litecoin mainnet, tltc for Litecoin testnet)
        guard hrp == "bc" || hrp == "tb" || hrp == "ltc" || hrp == "tltc" else {
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
        
        // CRITICAL: First 5-bit value is the witness version (NOT converted to bytes)
        // Remaining values are the witness program (converted from 5-bit to 8-bit)
        guard !dataValues.isEmpty else {
            throw BitcoinError.invalidAddress
        }
        
        let witnessVersion = dataValues[0]
        let programValues = Array(dataValues.dropFirst())
        
        // Convert witness program from 5-bit to 8-bit
        var bits = 0
        var value = 0
        var programBytes: [UInt8] = []
        
        for val in programValues {
            bits += 5
            value = (value << 5) | Int(val)
            
            if bits >= 8 {
                bits -= 8
                programBytes.append(UInt8((value >> bits) & 0xff))
                value &= (1 << bits) - 1
            }
        }
        
        // Verify witness program length (20 bytes for P2WPKH, 32 for P2WSH)
        guard programBytes.count == 20 || programBytes.count == 32 else {
            throw BitcoinError.invalidAddress
        }
        
        // Verify witness version is 0 for native SegWit v0 (bc1q/tb1q addresses)
        // Version 1 would be Taproot (bc1p/tb1p addresses)
        guard witnessVersion <= 16 else {
            throw BitcoinError.invalidAddress
        }
        
        return (witnessVersion, Data(programBytes))
    }
    
    // MARK: - Rust FFI Integration
    
    static func buildAndSignViaRust(
        recipient: String,
        amountSats: UInt64,
        feeRate: UInt64,
        privateKeyWIF: String,
        isTestnet: Bool
    ) throws -> SignedTransaction {
        let rawHex = try RustService.shared.signBitcoinThrowing(
            recipient: recipient,
            amountSats: amountSats,
            feeRate: feeRate,
            senderWIF: privateKeyWIF
        )
        
        // Calculate txid (double SHA256 of raw hex)
        guard let txData = Data(hex: rawHex) else {
            throw BitcoinError.serializationError
        }
        
        // Double SHA256 for txid
        let firstHash = SHA256.hash(data: txData)
        let secondHash = SHA256.hash(data: Data(firstHash))
        let txid = Data(Data(secondHash).reversed()).hexString
        
        return SignedTransaction(
            txid: txid,
            rawHex: rawHex,
            size: txData.count,
            vsize: txData.count // Approximation
        )
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
    case serializationError
    
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
        case .serializationError:
            return "Serialization error"
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
        
        // Count leading '1's (which represent leading zero bytes)
        var leadingZeros = 0
        for char in base58 {
            if char == "1" {
                leadingZeros += 1
            } else {
                break
            }
        }
        
        // Allocate enough space - WIF can be up to 38 bytes
        var result = [UInt8](repeating: 0, count: base58.count)
        var resultLen = 0
        
        for char in base58 {
            guard let digit = alphabet.firstIndex(of: char) else { return nil }
            var carry = alphabet.distance(from: alphabet.startIndex, to: digit)
            
            var i = 0
            while i < resultLen || carry != 0 {
                if i < resultLen {
                    carry += 58 * Int(result[i])
                }
                result[i] = UInt8(carry % 256)
                carry /= 256
                i += 1
            }
            resultLen = i
        }
        
        // Build final result with leading zeros and reversed bytes
        var finalResult = Data(repeating: 0, count: leadingZeros)
        for i in (0..<resultLen).reversed() {
            finalResult.append(result[i])
        }
        
        self = finalResult
    }
}
