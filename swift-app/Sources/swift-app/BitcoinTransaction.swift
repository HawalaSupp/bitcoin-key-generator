import Foundation
import CryptoKit

// MARK: - Bitcoin Transaction Builder & Signer

struct BitcoinTransaction {
    let inputs: [Input]
    let outputs: [Output]
    let version: UInt32
    let locktime: UInt32
    
    struct Input {
        let txid: String
        let vout: UInt32
        let scriptPubKey: Data
        let value: UInt64
        let sequence: UInt32
    }
    
    struct Output {
        let value: UInt64
        let scriptPubKey: Data
    }
    
    /// Build and sign a P2WPKH transaction
    static func buildAndSign(
        from utxos: [(txid: String, vout: UInt32, value: UInt64, scriptPubKey: String)],
        to recipient: String,
        amount: UInt64,
        feeRate: UInt64,
        changeAddress: String,
        privateKeyWIF: String
    ) throws -> String {
        
        // Parse WIF private key
        guard let privKeyData = decodeWIF(privateKeyWIF) else {
            throw TransactionError.invalidPrivateKey
        }
        
        // Decode addresses
        guard let recipientScript = try? decodeP2WPKHAddress(recipient) else {
            throw TransactionError.invalidAddress
        }
        guard let changeScript = try? decodeP2WPKHAddress(changeAddress) else {
            throw TransactionError.invalidChangeAddress
        }
        
        // Calculate total input
        let totalInput = utxos.reduce(0) { $0 + $1.value }
        
        // Estimate fee (inputs * 68 + outputs * 31 + 10)
        let estimatedSize = UInt64(utxos.count * 68 + 2 * 31 + 10)
        let fee = estimatedSize * feeRate
        
        guard totalInput >= amount + fee else {
            throw TransactionError.insufficientFunds
        }
        
        let change = totalInput - amount - fee
        
        // Build inputs
        let inputs = utxos.map { utxo in
            Input(
                txid: utxo.txid,
                vout: utxo.vout,
                scriptPubKey: Data(hex: utxo.scriptPubKey) ?? Data(),
                value: utxo.value,
                sequence: 0xfffffffd
            )
        }
        
        // Build outputs
        var outputs = [
            Output(value: amount, scriptPubKey: recipientScript)
        ]
        
        if change > 546 { // dust threshold
            outputs.append(Output(value: change, scriptPubKey: changeScript))
        }
        
        let tx = BitcoinTransaction(
            inputs: inputs,
            outputs: outputs,
            version: 2,
            locktime: 0
        )
        
        // Sign transaction
        return try tx.sign(with: privKeyData)
    }
    
    /// Sign the transaction with BIP143 (SegWit)
    private func sign(with privateKey: Data) throws -> String {
        var witnesses: [Data] = []
        
        for (inputIndex, input) in inputs.enumerated() {
            // BIP143 sighash
            let sighash = try computeBIP143Sighash(
                inputIndex: inputIndex,
                scriptCode: input.scriptPubKey,
                value: input.value
            )
            
            // Sign with secp256k1
            let signature = try signSecp256k1(hash: sighash, privateKey: privateKey)
            
            // DER encode signature + SIGHASH_ALL
            let derSig = derEncode(signature: signature) + Data([0x01])
            
            // Get public key
            let publicKey = try derivePublicKey(from: privateKey)
            
            // Build witness
            let witness = Data([UInt8(derSig.count)]) + derSig + Data([UInt8(publicKey.count)]) + publicKey
            witnesses.append(witness)
        }
        
        // Serialize transaction
        return try serialize(with: witnesses)
    }
    
    /// Compute BIP143 signature hash for SegWit
    private func computeBIP143Sighash(inputIndex: Int, scriptCode: Data, value: UInt64) throws -> Data {
        var data = Data()
        
        // 1. nVersion (4 bytes)
        data += version.littleEndianData
        
        // 2. hashPrevouts (32 bytes)
        var prevouts = Data()
        for input in inputs {
            if let txidData = Data(hex: input.txid) {
                prevouts += Data(txidData.reversed())
            }
            prevouts += input.vout.littleEndianData
        }
        let hashPrevouts = Data(SHA256.hash(data: Data(SHA256.hash(data: prevouts))))
        data += hashPrevouts
        
        // 3. hashSequence (32 bytes)
        var sequences = Data()
        for input in inputs {
            sequences += input.sequence.littleEndianData
        }
        let hashSequence = Data(SHA256.hash(data: Data(SHA256.hash(data: sequences))))
        data += hashSequence
        
        // 4. outpoint (36 bytes)
        let input = inputs[inputIndex]
        if let txidData = Data(hex: input.txid) {
            data += Data(txidData.reversed())
        }
        data += input.vout.littleEndianData
        
        // 5. scriptCode (variable)
        data += Data([UInt8(scriptCode.count)])
        data += scriptCode
        
        // 6. value (8 bytes)
        data += value.littleEndianData
        
        // 7. nSequence (4 bytes)
        data += input.sequence.littleEndianData
        
        // 8. hashOutputs (32 bytes)
        var outputsData = Data()
        for output in outputs {
            outputsData += output.value.littleEndianData
            outputsData += Data([UInt8(output.scriptPubKey.count)])
            outputsData += output.scriptPubKey
        }
        let hashOutputs = Data(SHA256.hash(data: Data(SHA256.hash(data: outputsData))))
        data += hashOutputs
        
        // 9. nLocktime (4 bytes)
        data += locktime.littleEndianData
        
        // 10. sighash type (4 bytes)
        data += UInt32(1).littleEndianData // SIGHASH_ALL
        
        // Double SHA256
        return Data(SHA256.hash(data: Data(SHA256.hash(data: data))))
    }
    
    /// Serialize the signed transaction with witnesses
    private func serialize(with witnesses: [Data]) throws -> String {
        var data = Data()
        
        // Version
        data += version.littleEndianData
        
        // Marker and flag (SegWit)
        data += Data([0x00, 0x01])
        
        // Input count
        data += Data([UInt8(inputs.count)])
        
        // Inputs
        for input in inputs {
            if let txidData = Data(hex: input.txid) {
                data += Data(txidData.reversed())
            }
            data += input.vout.littleEndianData
            data += Data([0x00]) // Empty scriptSig for SegWit
            data += input.sequence.littleEndianData
        }
        
        // Output count
        data += Data([UInt8(outputs.count)])
        
        // Outputs
        for output in outputs {
            data += output.value.littleEndianData
            data += Data([UInt8(output.scriptPubKey.count)])
            data += output.scriptPubKey
        }
        
        // Witnesses
        for witness in witnesses {
            data += Data([0x02]) // witness item count
            data += witness
        }
        
        // Locktime
        data += locktime.littleEndianData
        
        return data.hexString
    }
    
    enum TransactionError: Error {
        case invalidPrivateKey
        case invalidAddress
        case invalidChangeAddress
        case insufficientFunds
        case signingFailed
    }
}

// MARK: - Crypto Helpers

private func signSecp256k1(hash: Data, privateKey: Data) throws -> Data {
    // Use P256 as secp256k1 substitute (will need proper secp256k1 for production)
    guard privateKey.count == 32 else {
        throw BitcoinTransaction.TransactionError.invalidPrivateKey
    }
    
    let privKey = try P256.Signing.PrivateKey(rawRepresentation: privateKey)
    let signature = try privKey.signature(for: hash)
    
    // Extract r and s from signature
    return signature.rawRepresentation
}

private func derivePublicKey(from privateKey: Data) throws -> Data {
    let privKey = try P256.Signing.PrivateKey(rawRepresentation: privateKey)
    return privKey.publicKey.compressedRepresentation
}

private func derEncode(signature: Data) -> Data {
    // Simple DER encoding for ECDSA signature
    guard signature.count == 64 else { return Data() }
    
    let r = signature.prefix(32)
    let s = signature.suffix(32)
    
    var derR = r
    if derR[0] >= 0x80 {
        derR = Data([0x00]) + derR
    }
    
    var derS = s
    if derS[0] >= 0x80 {
        derS = Data([0x00]) + derS
    }
    
    var result = Data([0x30]) // SEQUENCE
    let totalLength = 2 + derR.count + 2 + derS.count
    result += Data([UInt8(totalLength)])
    
    result += Data([0x02, UInt8(derR.count)]) + derR
    result += Data([0x02, UInt8(derS.count)]) + derS
    
    return result
}

private func decodeWIF(_ wif: String) -> Data? {
    guard let decoded = base58Decode(wif) else { return nil }
    guard decoded.count == 38 else { return nil }
    
    // Extract private key (skip version byte, take 32 bytes, skip compression flag and checksum)
    return decoded.subdata(in: 1..<33)
}

private func decodeP2WPKHAddress(_ address: String) throws -> Data {
    // Decode bech32 address
    guard let decoded = try? bech32Decode(address) else {
        throw BitcoinTransaction.TransactionError.invalidAddress
    }
    
    // Build scriptPubKey: OP_0 + PUSH(20) + pubKeyHash
    return Data([0x00, 0x14]) + decoded
}

private func bech32Decode(_ address: String) throws -> Data {
    let parts = address.split(separator: "1")
    guard parts.count == 2 else { throw BitcoinTransaction.TransactionError.invalidAddress }
    
    let charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
    var values: [UInt8] = []
    
    for char in parts[1].dropLast(6) { // Remove checksum
        guard let index = charset.firstIndex(of: char) else {
            throw BitcoinTransaction.TransactionError.invalidAddress
        }
        values.append(UInt8(charset.distance(from: charset.startIndex, to: index)))
    }
    
    // Convert from base32 to base256
    return convertBits(values, fromBits: 5, toBits: 8, pad: false)
}

private func convertBits(_ data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) -> Data {
    var acc = 0
    var bits = 0
    var result: [UInt8] = []
    let maxv = (1 << toBits) - 1
    
    for value in data {
        acc = (acc << fromBits) | Int(value)
        bits += fromBits
        while bits >= toBits {
            bits -= toBits
            result.append(UInt8((acc >> bits) & maxv))
        }
    }
    
    if pad && bits > 0 {
        result.append(UInt8((acc << (toBits - bits)) & maxv))
    }
    
    return Data(result)
}

private func base58Decode(_ string: String) -> Data? {
    let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    var result: [UInt8] = [0]
    
    for char in string {
        guard let index = alphabet.firstIndex(of: char) else { return nil }
        var carry = alphabet.distance(from: alphabet.startIndex, to: index)
        
        for i in 0..<result.count {
            carry += Int(result[i]) * 58
            result[i] = UInt8(carry & 0xFF)
            carry >>= 8
        }
        
        while carry > 0 {
            result.append(UInt8(carry & 0xFF))
            carry >>= 8
        }
    }
    
    // Add leading zeros
    for char in string {
        if char == "1" {
            result.append(0)
        } else {
            break
        }
    }
    
    return Data(result.reversed())
}

// MARK: - Data Extensions

extension Data {
    init?(hex: String) {
        let hex = hex.replacingOccurrences(of: " ", with: "")
        guard hex.count % 2 == 0 else { return nil }
        
        var data = Data()
        var index = hex.startIndex
        
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            let byteString = hex[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        
        self = data
    }
    
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

extension UInt32 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}

extension UInt64 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt64>.size)
    }
}

extension SHA256.Digest {
    static func hash(data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}
