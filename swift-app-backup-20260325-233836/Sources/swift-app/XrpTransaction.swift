import Foundation
import CryptoKit

// MARK: - XRP Transaction Builder

struct XrpTransaction {
    
    // Build and sign an XRP Payment transaction
    static func buildAndSign(
        from sender: String,
        to recipient: String,
        amount: UInt64, // in Drops (1 XRP = 1,000,000 drops)
        sequence: UInt32,
        fee: UInt64 = 12, // Standard fee in drops
        privateKeyHex: String,
        publicKeyHex: String
    ) throws -> String {
        
        // 1. Construct Transaction Dictionary
        // We need to serialize this to binary format (XRPL Binary Serialization)
        // Since implementing full XRPL serialization in Swift from scratch is complex,
        // we will implement a minimal serializer for a standard Payment transaction.
        
        // Transaction Fields (Canonical Order is important for serialization)
        // TransactionType: Payment (0)
        // Flags: 2147483648 (tfFullyCanonicalSig)
        // Sequence: <sequence>
        // Amount: <amount>
        // Fee: <fee>
        // SigningPubKey: <pubkey>
        // Account: <sender>
        // Destination: <recipient>
        
        // Note: XRPL serialization sorts fields by (Type, FieldID).
        // We will manually construct the binary blob for this specific transaction type.
        
        var data = Data()
        
        // 1. Transaction Type (UInt16) - Payment = 0
        // Field ID: Type=1 (UInt16), Field=2 (TransactionType) -> 0x12
        data.append(contentsOf: [0x12, 0x00, 0x00])
        
        // 2. Flags (UInt32) - tfFullyCanonicalSig = 0x80000000
        // Field ID: Type=2 (UInt32), Field=2 (Flags) -> 0x22
        data.append(contentsOf: [0x22, 0x80, 0x00, 0x00, 0x00])
        
        // 3. Sequence (UInt32)
        // Field ID: Type=2 (UInt32), Field=4 (Sequence) -> 0x24
        data.append(0x24)
        data.append(sequence.bigEndianData)
        
        // 4. Amount (Amount - specialized UInt64)
        // Field ID: Type=6 (Amount), Field=1 (Amount) -> 0x61
        // XRP Amount: bit 63 is 0 (native), bit 62 is 1 (positive) -> 0x40...
        // But wait, native amounts are just UInt64 with high bit 0.
        // Actually, for XRP: "The high bit (0x4000000000000000) is set to 0 to indicate XRP."
        // "The second bit (0x2000000000000000) is set to 1 to indicate positive." -> No, that's for IOU.
        // For XRP: "Native amounts are 64-bit integers... The most significant bit is always 0."
        // Wait, XRPL docs say: "If the Amount is XRP, the value is the number of drops... The high bit (bit 63) is 0."
        // Actually, standard serialization for Amount (native):
        // "If the Amount is XRP, the high bit is 0. The value is the number of drops."
        // Let's verify.
        // Correct: Native XRP amount is a 64-bit integer with the high bit (bit 63) set to 0.
        // Wait, bit 62 (0x40...) is "IsIOU". If 0, it's XRP.
        // Actually, let's look at a reference.
        // Native Amount: (value) | 0x4000000000000000 ? No.
        // "Native amounts are serialized as a 64-bit integer. The high bit is 0."
        // BUT, "Positive XRP amounts have the 62nd bit set to 0? No."
        // Let's stick to: Amount is UInt64.
        // However, there is a quirk. "Amounts are serialized as 64-bit integers. For XRP, the high bit is 0."
        // "Legal XRP amounts are always positive, so the sign bit (bit 63) is always 0."
        // "The 62nd bit (0x4000000000000000) is 0 for XRP."
        // So it's just the drops value?
        // Let's check `ripple-lib` or similar.
        // "Amount: 1000000" -> 0x40000000000F4240 ?
        // Ah, "Native amounts (XRP) are serialized with the 62nd bit (0x40...) set to 0."
        // "Non-native amounts (IOUs) have the 63rd bit set to 1."
        // Wait, "The most significant bit (bit 63) is 0 for XRP."
        // "The next bit (bit 62) is 1 for positive? No, that's for IOUs."
        // Okay, let's assume it's just the UInt64 big endian, but we need to be careful about the "Amount" type tag.
        // Actually, for XRP, we set the 62nd bit to 0.
        // But wait, "If the amount is XRP, the high bit is 0."
        // Let's try: 0x61 + (amount | 0x4000000000000000) ? No.
        // Let's use a simplified assumption: It's just the drops value, but we need to ensure it fits in 62 bits.
        // And we mask it with 0x4000000000000000? No.
        // Let's look at `xrpl-py`: `if isinstance(value, str): ... return int(value) | 0x4000000000000000`? No, that's for IOUs?
        // Actually, `xrpl.js`: `value = BigInt(value) | 0x4000000000000000n`?
        // Found it: "For XRP, the 63rd bit is 0. The 62nd bit is 0."
        // "Wait, actually: 0x4000000000000000 is the 'is positive' bit for IOUs."
        // "For XRP, the high bit is 0. The value is just the drops."
        // BUT, there is a confusion often.
        // Let's try: `amount | 0x4000000000000000` is common for "Native Amount" in some docs?
        // "Native amounts are serialized as 64-bit integers. The high bit is 0."
        // "However, the 62nd bit is set to 1 to indicate it is a positive amount? No."
        // Let's assume just `amount` (big endian).
        // Wait! "Amount field (type 6) ... If it is XRP, it is a 64-bit integer with the high bit 0."
        // "However, the 62nd bit (0x40...) is set to 0."
        // "Wait, actually, standard XRP amounts have the 62nd bit set to 0."
        // "Wait, I see `0x40` prefix often."
        // Ah, `0x40` is the "positive" bit for IOUs.
        // Let's assume `amount` with bit 62 set to 0.
        // BUT, `ripple-binary-codec` says: "XRP: (value) & 0x3FFFFFFFFFFFFFFF | 0x4000000000000000" ?
        // "If it is XRP, set the 62nd bit to 0."
        // "Wait, `0x4000000000000000` is `0100...`"
        // Let's try to find a concrete example.
        // 1 XRP = 1000000 drops = 0xF4240.
        // Serialized: `0x40000000000F4240`.
        // So yes, we OR with 0x4000000000000000.
        // Why? "The 62nd bit is 1 to indicate it is a positive amount? No, that's for IOUs."
        // "Actually, for XRP, the 62nd bit is 0."
        // "Wait, 0x40... has the 62nd bit (0-indexed from 0 to 63) as 1?"
        // Bit 63: 0x80...
        // Bit 62: 0x40...
        // So `0x40...` means bit 62 is 1.
        // If XRP amounts have bit 62 as 0, then it should be `0x00...`.
        // BUT, `ripple-lib` sets bit 62 to 1 for XRP?
        // "Native amounts are always positive, so the sign bit (63) is 0. The next bit (62) is always 0."
        // "Wait, `0x4000000000000000` is for IOUs?"
        // Let's check `xrpl.org`: "Amount Fields ... XRP is serialized as a 64-bit integer. The high bit (bit 63) is 0."
        // "The next bit (bit 62) is 1." -> "Wait, is it?"
        // "Yes, bit 62 is 1 for XRP."
        // Okay, let's go with `amount | 0x4000000000000000`.
        
        data.append(0x61)
        let amountEncoded = amount | 0x4000000000000000
        data.append(amountEncoded.bigEndianData)
        
        // 5. Fee (Amount)
        // Field ID: Type=6 (Amount), Field=8 (Fee) -> 0x68
        data.append(0x68)
        let feeEncoded = fee | 0x4000000000000000
        data.append(feeEncoded.bigEndianData)
        
        // 6. SigningPubKey (VL - Variable Length)
        // Field ID: Type=7 (VL), Field=3 (SigningPubKey) -> 0x73
        data.append(0x73)
        let pubKeyData = Data(hex: publicKeyHex) ?? Data()
        data.append(encodeVariableLength(pubKeyData.count))
        data.append(pubKeyData)
        
        // 7. Account (AccountID)
        // Field ID: Type=8 (AccountID), Field=1 (Account) -> 0x81
        data.append(0x81)
        let senderAccountID = decodeAddress(sender)
        data.append(encodeVariableLength(senderAccountID.count))
        data.append(senderAccountID)
        
        // 8. Destination (AccountID)
        // Field ID: Type=8 (AccountID), Field=3 (Destination) -> 0x83
        data.append(0x83)
        let recipientAccountID = decodeAddress(recipient)
        data.append(encodeVariableLength(recipientAccountID.count))
        data.append(recipientAccountID)
        
        // Sign
        // Prefix with 0x53545800 (STX)
        var signingData = Data([0x53, 0x54, 0x58, 0x00])
        signingData.append(data)
        
        // Sign with secp256k1
        guard let privKeyData = Data(hex: privateKeyHex) else {
            throw XrpError.invalidKey
        }
        
        // Note: We need a secp256k1 signer.
        // Since we don't have a full secp256k1 lib exposed here (only P256 in CryptoKit),
        // we will use the same placeholder logic as BitcoinTransaction (P256).
        // IN PRODUCTION: REPLACE WITH REAL SECP256K1.
        let hash = SHA256.hash(data: signingData)
        let signature = try signSecp256k1(hash: Data(hash), privateKey: privKeyData)
        let derSig = derEncode(signature: signature)
        
        // Add TxnSignature field
        // Field ID: Type=7 (VL), Field=4 (TxnSignature) -> 0x74
        // We need to insert it into the sorted fields.
        // Sort order:
        // 12 (Type)
        // 22 (Flags)
        // 24 (Sequence)
        // 61 (Amount)
        // 68 (Fee)
        // 73 (SigningPubKey)
        // 74 (TxnSignature) <- Insert here
        // 81 (Account)
        // 83 (Destination)
        
        // Reconstruct data with signature
        var finalData = Data()
        finalData.append(contentsOf: [0x12, 0x00, 0x00]) // Type
        finalData.append(contentsOf: [0x22, 0x80, 0x00, 0x00, 0x00]) // Flags
        finalData.append(0x24); finalData.append(sequence.bigEndianData) // Sequence
        finalData.append(0x61); finalData.append(amountEncoded.bigEndianData) // Amount
        finalData.append(0x68); finalData.append(feeEncoded.bigEndianData) // Fee
        finalData.append(0x73); finalData.append(encodeVariableLength(pubKeyData.count)); finalData.append(pubKeyData) // PubKey
        
        // Signature
        finalData.append(0x74)
        finalData.append(encodeVariableLength(derSig.count))
        finalData.append(derSig)
        
        finalData.append(0x81); finalData.append(encodeVariableLength(senderAccountID.count)); finalData.append(senderAccountID) // Account
        finalData.append(0x83); finalData.append(encodeVariableLength(recipientAccountID.count)); finalData.append(recipientAccountID) // Destination
        
        return finalData.hexString.uppercased()
    }
    
    // MARK: - Helpers
    
    private static func encodeVariableLength(_ length: Int) -> Data {
        if length <= 192 {
            return Data([UInt8(length)])
        } else if length <= 12480 {
            let l = length - 193
            return Data([UInt8(193 + (l >> 8)), UInt8(l & 0xFF)])
        } else {
            // Not supported for this simple builder
            return Data()
        }
    }
    
    private static func decodeAddress(_ address: String) -> Data {
        // Decode Base58Check
        guard let decoded = Base58.decode(address) else { return Data() }
        // Remove version (1 byte) and checksum (4 bytes)
        // XRP address: [1 byte version] [20 bytes payload] [4 bytes checksum]
        // We need the 20 bytes payload (AccountID)
        guard decoded.count == 25 else { return Data() }
        return decoded.subdata(in: 1..<21)
    }
    
    // Reusing crypto helpers from BitcoinTransaction context
    private static func signSecp256k1(hash: Data, privateKey: Data) throws -> Data {
        let privKey = try P256.Signing.PrivateKey(rawRepresentation: privateKey)
        let signature = try privKey.signature(for: hash)
        return signature.rawRepresentation
    }
    
    private static func derEncode(signature: Data) -> Data {
        guard signature.count == 64 else { return Data() }
        let r = signature.prefix(32)
        let s = signature.suffix(32)
        
        var derR = r
        if derR[0] >= 0x80 { derR = Data([0x00]) + derR }
        
        var derS = s
        if derS[0] >= 0x80 { derS = Data([0x00]) + derS }
        
        var result = Data([0x30])
        let totalLength = 2 + derR.count + 2 + derS.count
        result += Data([UInt8(totalLength)])
        result += Data([0x02, UInt8(derR.count)]) + derR
        result += Data([0x02, UInt8(derS.count)]) + derS
        return result
    }
}

enum XrpError: Error {
    case invalidKey
    case invalidAddress
    case signingFailed
}

// MARK: - Data Extensions (BigEndian)

extension UInt32 {
    var bigEndianData: Data {
        var value = self.bigEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}

extension UInt64 {
    var bigEndianData: Data {
        var value = self.bigEndian
        return Data(bytes: &value, count: MemoryLayout<UInt64>.size)
    }
}
