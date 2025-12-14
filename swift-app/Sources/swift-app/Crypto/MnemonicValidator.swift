import Foundation
import CryptoKit

// MARK: - Mnemonic Validator

/// Validates BIP39 mnemonic phrases
struct MnemonicValidator {
    
    // MARK: - Validation Result
    
    enum ValidationResult: Sendable {
        case valid
        case invalidWordCount(Int)
        case invalidWord(String, index: Int)
        case invalidChecksum
        
        var isValid: Bool {
            if case .valid = self { return true }
            return false
        }
        
        var errorMessage: String? {
            switch self {
            case .valid:
                return nil
            case .invalidWordCount(let count):
                return "Invalid word count: \(count). Must be 12, 15, 18, 21, or 24 words."
            case .invalidWord(let word, let index):
                return "Invalid word '\(word)' at position \(index + 1). Not in BIP39 wordlist."
            case .invalidChecksum:
                return "Invalid mnemonic: checksum verification failed."
            }
        }
    }
    
    // MARK: - Validation
    
    /// Validate a mnemonic phrase
    /// - Parameter phrase: Space-separated mnemonic words
    /// - Returns: Validation result
    static func validate(_ phrase: String) -> ValidationResult {
        let words = normalizePhrase(phrase)
        
        // Check word count
        let validCounts = [12, 15, 18, 21, 24]
        guard validCounts.contains(words.count) else {
            return .invalidWordCount(words.count)
        }
        
        // Check each word is in wordlist
        for (index, word) in words.enumerated() {
            guard BIP39Wordlist.english.contains(word) else {
                return .invalidWord(word, index: index)
            }
        }
        
        // Verify checksum using Rust backend for accuracy
        let joinedPhrase = words.joined(separator: " ")
        if !RustService.shared.validateMnemonic(joinedPhrase) {
            return .invalidChecksum
        }
        
        return .valid
    }
    
    /// Quick check if phrase is potentially valid (fast, no checksum)
    static func quickValidate(_ phrase: String) -> Bool {
        let words = normalizePhrase(phrase)
        let validCounts = [12, 15, 18, 21, 24]
        guard validCounts.contains(words.count) else { return false }
        return words.allSatisfy { BIP39Wordlist.english.contains($0) }
    }
    
    /// Normalize a phrase: lowercase, trim, single spaces
    static func normalizePhrase(_ phrase: String) -> [String] {
        phrase
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }
    
    /// Get word suggestions for partial input
    static func suggestions(for prefix: String, limit: Int = 5) -> [String] {
        let lowercased = prefix.lowercased()
        return BIP39Wordlist.english
            .filter { $0.hasPrefix(lowercased) }
            .prefix(limit)
            .map { $0 }
    }
}

// MARK: - Seed Deriver

/// Derives cryptographic seed from mnemonic phrase
struct SeedDeriver {
    
    /// Derive a 64-byte seed from mnemonic phrase
    /// - Parameters:
    ///   - mnemonic: BIP39 mnemonic phrase
    ///   - passphrase: Optional BIP39 passphrase (empty string if none)
    /// - Returns: 64-byte seed
    static func deriveSeed(from mnemonic: String, passphrase: String = "") -> Data? {
        // Normalize the mnemonic
        let normalizedMnemonic = MnemonicValidator.normalizePhrase(mnemonic).joined(separator: " ")
        
        // BIP39 uses PBKDF2-HMAC-SHA512 with 2048 iterations
        // Salt is "mnemonic" + passphrase
        guard let mnemonicData = normalizedMnemonic.data(using: .utf8) else { return nil }
        let salt = "mnemonic" + passphrase
        guard let saltData = salt.data(using: .utf8) else { return nil }
        
        // Use CommonCrypto for PBKDF2 (CryptoKit doesn't have it directly)
        return pbkdf2(
            password: mnemonicData,
            salt: saltData,
            iterations: 2048,
            keyLength: 64,
            algorithm: .sha512
        )
    }
    
    /// Calculate fingerprint from seed (first 8 bytes of SHA256)
    static func fingerprint(from seed: Data) -> Data {
        let hash = SHA256.hash(data: seed)
        return Data(hash.prefix(8))
    }
    
    // MARK: - PBKDF2 Implementation
    
    private enum HashAlgorithm {
        case sha512
        
        var ccAlgorithm: UInt32 {
            switch self {
            case .sha512: return UInt32(kCCPRFHmacAlgSHA512)
            }
        }
    }
    
    private static func pbkdf2(
        password: Data,
        salt: Data,
        iterations: UInt32,
        keyLength: Int,
        algorithm: HashAlgorithm
    ) -> Data? {
        var derivedKey = Data(count: keyLength)
        
        let result = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        algorithm.ccAlgorithm,
                        iterations,
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }
        
        return result == kCCSuccess ? derivedKey : nil
    }
}

// CommonCrypto import for PBKDF2
import CommonCrypto
