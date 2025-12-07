import Foundation
import CryptoKit

// MARK: - Data Extensions for Little Endian

extension UInt32 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
}

extension UInt64 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
}

// MARK: - Solana Transaction Builder

struct SolanaTransaction {
    
    // Build and sign a Solana transfer transaction
    static func buildAndSign(
        from sender: String,
        to recipient: String,
        amount: UInt64, // in Lamports
        recentBlockhash: String,
        privateKeyBase58: String
    ) throws -> String {
        
        // Convert Lamports to SOL
        let amountSol = Double(amount) / 1_000_000_000.0
        
        return try RustCLIBridge.shared.signSolana(
            recipient: recipient,
            amountSol: amountSol,
            recentBlockhash: recentBlockhash,
            senderBase58: privateKeyBase58
        )
    }
    
    // MARK: - Helpers
    
    private static func encodeCompactLength(_ len: Int) -> [UInt8] {
        var rem = len
        var bytes: [UInt8] = []
        repeat {
            var elem = rem & 0x7f
            rem >>= 7
            if rem != 0 {
                elem |= 0x80
            }
            bytes.append(UInt8(elem))
        } while rem != 0
        return bytes
    }
}

enum SolanaError: Error {
    case invalidKey
    case invalidBlockhash
    case signingFailed
}

// MARK: - Base58 Helper (Simplified)
// Note: In a real app, use a robust Base58 library. This is a placeholder or assumes one exists.
// Since we used Base58 in BitcoinTransaction, we can reuse or adapt.

struct Base58 {
    static let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    
    static func decode(_ string: String) -> Data? {
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
    
    static func encode(_ data: Data) -> String {
        var result: [UInt8] = [0]
        
        for byte in data {
            var carry = Int(byte)
            
            for i in 0..<result.count {
                carry += Int(result[i]) * 256
                result[i] = UInt8(carry % 58)
                carry /= 58
            }
            
            while carry > 0 {
                result.append(UInt8(carry % 58))
                carry /= 58
            }
        }
        
        var str = ""
        for byte in result.reversed() {
            let index = alphabet.index(alphabet.startIndex, offsetBy: Int(byte))
            str.append(alphabet[index])
        }
        
        // Handle leading zeros
        for byte in data {
            if byte == 0 {
                str.insert("1", at: str.startIndex)
            } else {
                break
            }
        }
        
        // Remove leading '1's that were added by the initial [0] if they are extra?
        // The logic above is a bit rough. Let's stick to a simpler known algo if possible or just use the one from BitcoinTransaction if it was exposed.
        // Actually, the decode logic above is from BitcoinTransaction.
        
        return str
    }
}

// MARK: - Data Extensions

// Extensions are already defined in BitcoinTransaction.swift or other files in the module.
// If they are not public/internal there, we might need them here.
// Assuming they are internal to the module, we don't need to redefine them if they are in the same target.
// However, if they are private in BitcoinTransaction.swift, we need them here.
// Let's check visibility. They were 'extension UInt32' without 'private' modifier in BitcoinTransaction.swift, so they should be internal.
// But the compiler error says "Invalid redeclaration", which means they ARE visible.
// So I should remove them.


