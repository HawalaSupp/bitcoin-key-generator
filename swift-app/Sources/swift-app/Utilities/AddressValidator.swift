import Foundation
import CryptoKit

enum AddressValidationResult: Equatable {
    case empty
    case valid
    case invalid(String)
}

enum BitcoinAddressNetwork {
    case bitcoinMainnet
    case bitcoinTestnet
    case litecoinMainnet

    var allowedHRPs: [String] {
        switch self {
        case .bitcoinMainnet:
            return ["bc"]
        case .bitcoinTestnet:
            return ["tb"]
        case .litecoinMainnet:
            return ["ltc"]
        }
    }

    var base58Prefixes: [UInt8] {
        switch self {
        case .bitcoinMainnet:
            return [0x00, 0x05]
        case .bitcoinTestnet:
            return [0x6f, 0xc4]
        case .litecoinMainnet:
            return [0x30, 0x32]
        }
    }

    var displayName: String {
        switch self {
        case .bitcoinMainnet:
            return "Bitcoin"
        case .bitcoinTestnet:
            return "Bitcoin Testnet"
        case .litecoinMainnet:
            return "Litecoin"
        }
    }
}

struct AddressValidator {
    static func validateBitcoinAddress(_ address: String, network: BitcoinAddressNetwork) -> AddressValidationResult {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let normalized = trimmed.lowercased()
        if network.allowedHRPs.contains(where: { normalized.hasPrefix("\($0)1") }) {
            return validateBech32Address(trimmed, allowedHRP: network.allowedHRPs, networkName: network.displayName)
        }

        return validateBase58Address(trimmed, allowedPrefixes: network.base58Prefixes, networkName: network.displayName)
    }

    static func validateEthereumAddress(_ address: String) -> AddressValidationResult {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard trimmed.hasPrefix("0x") else {
            return .invalid("Address must start with 0x")
        }
        guard trimmed.count == 42 else {
            return .invalid("Ethereum addresses must be 42 characters long")
        }

        let hexPart = trimmed.dropFirst(2)
        let hexSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard hexPart.unicodeScalars.allSatisfy({ hexSet.contains($0) }) else {
            return .invalid("Address contains invalid hex characters")
        }

        let isValid = RustService.shared.validateEthereumAddress(trimmed)
        return isValid ? .valid : .invalid("Checksum does not match expected EIP-55 casing")
    }

    static func validateBnbAddress(_ address: String) -> AddressValidationResult {
        validateEthereumAddress(address)
    }

    static func validateSolanaAddress(_ address: String) -> AddressValidationResult {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard let decoded = decodeBase58(trimmed) else {
            return .invalid("Address contains invalid Base58 characters")
        }
        guard decoded.count == 32 else {
            return .invalid("Solana addresses must decode to 32 bytes")
        }
        return .valid
    }

    static func validateXrpAddress(_ address: String) -> AddressValidationResult {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        
        // XRP classic addresses start with 'r' and are 25-35 characters
        guard trimmed.hasPrefix("r") else {
            return .invalid("XRP addresses must start with 'r'")
        }
        guard trimmed.count >= 25 && trimmed.count <= 35 else {
            return .invalid("XRP addresses must be 25-35 characters")
        }
        
        // Decode using XRP's Base58 alphabet (same as Bitcoin but different checksum)
        guard let decoded = decodeBase58(trimmed) else {
            return .invalid("Address contains invalid Base58 characters")
        }
        
        // XRP address: [1 byte version] [20 bytes payload] [4 bytes checksum]
        guard decoded.count == 25 else {
            return .invalid("Invalid XRP address length after decoding")
        }
        
        // Version byte should be 0x00 for mainnet
        guard decoded[0] == 0x00 else {
            return .invalid("Invalid XRP address version byte")
        }
        
        // Verify checksum (XRP uses double SHA256 like Bitcoin)
        let payload = Array(decoded[0..<21])
        let checksum = Array(decoded[21...])
        let computed = Array(doubleSHA256(Data(payload)).prefix(4))
        guard checksum.elementsEqual(computed) else {
            return .invalid("Invalid XRP address checksum")
        }
        
        return .valid
    }

    // MARK: - Bitcoin Helpers

    private static func validateBech32Address(_ address: String, allowedHRP: [String], networkName: String) -> AddressValidationResult {
        guard address == address.lowercased() || address == address.uppercased() else {
            return .invalid("Bech32 addresses cannot mix upper and lower case")
        }

        let normalized = address.lowercased()
        guard let separatorIndex = normalized.lastIndex(of: "1") else {
            return .invalid("Bech32 address is missing separator")
        }

        let hrp = String(normalized[..<separatorIndex])
        guard allowedHRP.contains(hrp) else {
            return .invalid("Address does not belong to the \(networkName) network")
        }

        let dataPart = normalized[normalized.index(after: separatorIndex)...]
        guard dataPart.count >= 6 else {
            return .invalid("Bech32 payload is too short")
        }

        var values: [UInt8] = []
        for char in dataPart {
            guard let digit = bech32AlphabetMap[char] else {
                return .invalid("Invalid Bech32 character")
            }
            values.append(UInt8(digit))
        }

        guard verifyBech32Checksum(hrp: hrp, data: values) else {
            return .invalid("Bech32 checksum failed")
        }

        let payload = Array(values.dropLast(6))
        guard let decoded = convertBits(data: payload, fromBits: 5, toBits: 8, pad: false) else {
            return .invalid("Unable to decode Bech32 payload")
        }
        guard let version = decoded.first else {
            return .invalid("Missing witness version")
        }
        let witnessProgram = decoded.dropFirst()
        guard version == 0 else {
            return .invalid("Unsupported witness version")
        }
        guard witnessProgram.count == 20 || witnessProgram.count == 32 else {
            return .invalid("Unexpected witness program length")
        }

        return .valid
    }

    private static func validateBase58Address(_ address: String, allowedPrefixes: [UInt8], networkName: String) -> AddressValidationResult {
        guard let decoded = base58CheckDecode(address) else {
            return .invalid("Invalid Base58 checksum")
        }

        guard allowedPrefixes.contains(decoded.version) else {
            return .invalid("Address does not belong to the \(networkName) network")
        }

        guard decoded.payload.count == 20 else {
            return .invalid("Base58 payload should be 20 bytes")
        }

        return .valid
    }

    // MARK: - Base58 Helpers

    private static let base58Alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    private static let base58AlphabetMap: [Character: Int] = {
        var map: [Character: Int] = [:]
        for (index, char) in base58Alphabet.enumerated() {
            map[char] = index
        }
        return map
    }()

    private static func decodeBase58(_ string: String) -> [UInt8]? {
        var bytes: [UInt8] = [0]

        for char in string {
            guard let value = base58AlphabetMap[char] else { return nil }
            var carry = value
            for index in 0..<bytes.count {
                let combined = Int(bytes[index]) * 58 + carry
                bytes[index] = UInt8(combined & 0xff)
                carry = combined >> 8
            }
            while carry > 0 {
                bytes.append(UInt8(carry & 0xff))
                carry >>= 8
            }
        }

        var leadingZeros = 0
        for char in string {
            if char == "1" {
                leadingZeros += 1
            } else {
                break
            }
        }
        bytes.append(contentsOf: Array(repeating: 0, count: leadingZeros))

        // Remove potential padding zero introduced by initialization
        while bytes.count > 1 && bytes.last == 0 {
            bytes.removeLast()
        }

        return bytes.reversed()
    }

    private static func base58CheckDecode(_ string: String) -> (version: UInt8, payload: [UInt8])? {
        guard let decoded = decodeBase58(string), decoded.count >= 5 else {
            return nil
        }

    let checksumStart = decoded.count - 4
    let payload = Array(decoded[..<checksumStart])
    let checksum = Array(decoded[checksumStart...])
    let computed = Array(doubleSHA256(Data(payload)).prefix(4))
    guard checksum.elementsEqual(computed) else {
            return nil
        }
        guard let version = payload.first else {
            return nil
        }
        return (version, Array(payload.dropFirst()))
    }

    private static func doubleSHA256(_ data: Data) -> Data {
        let first = Data(SHA256.hash(data: data))
        return Data(SHA256.hash(data: first))
    }

    // MARK: - Bech32

    private static let bech32Alphabet = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let bech32AlphabetMap: [Character: Int] = {
        var map: [Character: Int] = [:]
        for (index, char) in bech32Alphabet.enumerated() {
            map[char] = index
        }
        return map
    }()

    private static func verifyBech32Checksum(hrp: String, data: [UInt8]) -> Bool {
        bech32Polymod(values: bech32HRPExpand(hrp) + data) == 1
    }

    private static func bech32Polymod(values: [UInt8]) -> UInt32 {
        let generator: [UInt32] = [
            0x3b6a57b2,
            0x26508e6d,
            0x1ea119fa,
            0x3d4233dd,
            0x2a1462b3
        ]
        var checksum: UInt32 = 1
        for value in values {
            let top = checksum >> 25
            checksum = (checksum & 0x1ffffff) << 5 ^ UInt32(value)
            for i in 0..<5 {
                checksum ^= (((top >> i) & 1) == 1) ? generator[i] : 0
            }
        }
        return checksum
    }

    private static func bech32HRPExpand(_ hrp: String) -> [UInt8] {
        var result: [UInt8] = []
        for scalar in hrp.unicodeScalars {
            result.append(UInt8(scalar.value >> 5))
        }
        result.append(0)
        for scalar in hrp.unicodeScalars {
            result.append(UInt8(scalar.value & 0x1f))
        }
        return result
    }

    private static func convertBits(data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) -> [UInt8]? {
        var acc = 0
        var bits = 0
        let maxv = (1 << toBits) - 1
        var result: [UInt8] = []

        for value in data {
            guard value >> fromBits == 0 else { return nil }
            acc = (acc << fromBits) | Int(value)
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((acc >> bits) & maxv))
            }
        }

        if pad {
            if bits > 0 {
                result.append(UInt8((acc << (toBits - bits)) & maxv))
            }
        } else if bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0 {
            return nil
        }

        return result
    }
}
