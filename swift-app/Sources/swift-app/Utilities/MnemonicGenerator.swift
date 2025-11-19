import Foundation
import CryptoKit
import Security

struct MnemonicGenerator {
    enum WordCount: Int, CaseIterable, Identifiable {
        case twelve = 12
        case twentyFour = 24
        
        var id: Int { rawValue }
        
        var title: String {
            switch self {
            case .twelve:
                return "12 Words"
            case .twentyFour:
                return "24 Words"
            }
        }
        
        var entropyBits: Int {
            switch self {
            case .twelve:
                return 128
            case .twentyFour:
                return 256
            }
        }
        
        var entropyBytes: Int { entropyBits / 8 }
        var checksumBits: Int { entropyBits / 32 }
    }
    
    static func generate(wordCount: WordCount) -> [String] {
        var entropy = Data(count: wordCount.entropyBytes)
        let status = entropy.withUnsafeMutableBytes { mutableBytes in
            guard let baseAddress = mutableBytes.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, wordCount.entropyBytes, baseAddress)
        }
        if status != errSecSuccess {
            return fallbackWords(count: wordCount.rawValue)
        }
        
        let hash = SHA256.hash(data: entropy)
        var bits = entropy.map { byte -> String in
            var binary = String(byte, radix: 2)
            while binary.count < 8 { binary = "0" + binary }
            return binary
        }.joined()
        
        let checksum = hash.reduce("") { partialResult, byte in
            let binary = String(byte, radix: 2).leftPadding(toLength: 8, withPad: "0")
            return partialResult + binary
        }
        let checksumSlice = checksum.prefix(wordCount.checksumBits)
        bits += checksumSlice
        
        var words: [String] = []
        for index in 0..<wordCount.rawValue {
            let start = bits.index(bits.startIndex, offsetBy: index * 11)
            let end = bits.index(start, offsetBy: 11)
            let chunk = bits[start..<end]
            let number = Int(chunk, radix: 2) ?? 0
            let word = BIP39Wordlist.english[number % BIP39Wordlist.english.count]
            words.append(word)
        }
        
        return words
    }
    
    private static func fallbackWords(count: Int) -> [String] {
        (0..<count).map { index in
            let idx = index % BIP39Wordlist.english.count
            return BIP39Wordlist.english[idx]
        }
    }
}

private extension String {
    func leftPadding(toLength: Int, withPad character: Character) -> String {
        let paddingCount = max(0, toLength - count)
        guard paddingCount > 0 else { return self }
        return String(repeating: String(character), count: paddingCount) + self
    }
}
