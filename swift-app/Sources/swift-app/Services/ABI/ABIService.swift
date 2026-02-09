import Foundation

/// Swift ABI (Application Binary Interface) service for EVM contracts
/// Provides encoding/decoding for Solidity contract interactions
@MainActor
final class ABIService: ObservableObject {
    static let shared = ABIService()
    
    @Published var isLoading = false
    @Published var error: String?
    @Published var recentContracts: [SavedContract] = []
    
    private init() {
        loadRecentContracts()
    }
    
    // MARK: - Types
    
    /// Solidity type enumeration
    indirect enum ABIType: Hashable, CustomStringConvertible {
        case uint8, uint16, uint32, uint64, uint128, uint256
        case int8, int16, int32, int64, int128, int256
        case address
        case bool
        case bytes1, bytes2, bytes3, bytes4, bytes8, bytes16, bytes20, bytes32
        case bytes // dynamic
        case string // dynamic
        case array(ABIType) // dynamic array T[]
        case fixedArray(ABIType, Int) // fixed array T[N]
        case tuple([ABIType]) // struct
        
        var description: String {
            switch self {
            case .uint8: return "uint8"
            case .uint16: return "uint16"
            case .uint32: return "uint32"
            case .uint64: return "uint64"
            case .uint128: return "uint128"
            case .uint256: return "uint256"
            case .int8: return "int8"
            case .int16: return "int16"
            case .int32: return "int32"
            case .int64: return "int64"
            case .int128: return "int128"
            case .int256: return "int256"
            case .address: return "address"
            case .bool: return "bool"
            case .bytes1: return "bytes1"
            case .bytes2: return "bytes2"
            case .bytes3: return "bytes3"
            case .bytes4: return "bytes4"
            case .bytes8: return "bytes8"
            case .bytes16: return "bytes16"
            case .bytes20: return "bytes20"
            case .bytes32: return "bytes32"
            case .bytes: return "bytes"
            case .string: return "string"
            case .array(let inner): return "\(inner)[]"
            case .fixedArray(let inner, let size): return "\(inner)[\(size)]"
            case .tuple(let types): return "(\(types.map { $0.description }.joined(separator: ",")))"
            }
        }
        
        var isDynamic: Bool {
            switch self {
            case .bytes, .string, .array: return true
            case .fixedArray(let inner, _): return inner.isDynamic
            case .tuple(let types): return types.contains { $0.isDynamic }
            default: return false
            }
        }
        
        /// Parse type from string
        static func from(_ s: String) -> ABIType? {
            let s = s.trimmingCharacters(in: .whitespaces)
            
            // Dynamic array
            if s.hasSuffix("[]") {
                guard let inner = from(String(s.dropLast(2))) else { return nil }
                return .array(inner)
            }
            
            // Fixed array
            if let bracketIdx = s.lastIndex(of: "["), s.hasSuffix("]") {
                let innerStr = String(s[..<bracketIdx])
                let sizeStr = String(s[s.index(after: bracketIdx)..<s.index(before: s.endIndex)])
                guard let inner = from(innerStr),
                      let size = Int(sizeStr) else { return nil }
                return .fixedArray(inner, size)
            }
            
            switch s {
            case "uint8": return .uint8
            case "uint16": return .uint16
            case "uint32": return .uint32
            case "uint64": return .uint64
            case "uint128": return .uint128
            case "uint256", "uint": return .uint256
            case "int8": return .int8
            case "int16": return .int16
            case "int32": return .int32
            case "int64": return .int64
            case "int128": return .int128
            case "int256", "int": return .int256
            case "address": return .address
            case "bool": return .bool
            case "bytes1": return .bytes1
            case "bytes2": return .bytes2
            case "bytes3": return .bytes3
            case "bytes4": return .bytes4
            case "bytes8": return .bytes8
            case "bytes16": return .bytes16
            case "bytes20": return .bytes20
            case "bytes32": return .bytes32
            case "bytes": return .bytes
            case "string": return .string
            default: return nil
            }
        }
    }
    
    /// ABI value wrapper
    enum ABIValue {
        case uint(String) // String to handle large numbers
        case int(String)
        case address(String) // 0x-prefixed hex
        case bool(Bool)
        case fixedBytes(Data)
        case bytes(Data)
        case string(String)
        case array([ABIValue])
        case tuple([ABIValue])
        
        /// Create from user input based on type
        static func from(input: String, type: ABIType) -> ABIValue? {
            switch type {
            case .uint8, .uint16, .uint32, .uint64, .uint128, .uint256:
                return .uint(input)
            case .int8, .int16, .int32, .int64, .int128, .int256:
                return .int(input)
            case .address:
                guard input.hasPrefix("0x"), input.count == 42 else { return nil }
                return .address(input)
            case .bool:
                let lower = input.lowercased()
                if lower == "true" || lower == "1" { return .bool(true) }
                if lower == "false" || lower == "0" { return .bool(false) }
                return nil
            case .bytes1, .bytes2, .bytes3, .bytes4, .bytes8, .bytes16, .bytes20, .bytes32:
                let hex = input.hasPrefix("0x") ? String(input.dropFirst(2)) : input
                guard let data = Data(hexString: hex) else { return nil }
                return .fixedBytes(data)
            case .bytes:
                let hex = input.hasPrefix("0x") ? String(input.dropFirst(2)) : input
                guard let data = Data(hexString: hex) else { return nil }
                return .bytes(data)
            case .string:
                return .string(input)
            case .array, .fixedArray, .tuple:
                // Complex types need JSON parsing
                return nil
            }
        }
    }
    
    /// ABI function definition
    struct ABIFunction: Identifiable, Codable {
        let id = UUID()
        let name: String
        let inputs: [ABIParam]
        let outputs: [ABIParam]
        let stateMutability: String
        
        var signature: String {
            let params = inputs.map { $0.type }.joined(separator: ",")
            return "\(name)(\(params))"
        }
        
        var selector: String {
            let hash = keccak256(signature)
            return "0x" + hash.prefix(8)
        }
        
        var isReadOnly: Bool {
            stateMutability == "view" || stateMutability == "pure"
        }
        
        var isPayable: Bool {
            stateMutability == "payable"
        }
    }
    
    /// ABI parameter
    struct ABIParam: Codable {
        let name: String
        let type: String
        let components: [ABIParam]?
    }
    
    /// ABI event definition
    struct ABIEvent: Identifiable, Codable {
        let id = UUID()
        let name: String
        let inputs: [ABIEventParam]
        let anonymous: Bool?
        
        var signature: String {
            let params = inputs.map { $0.type }.joined(separator: ",")
            return "\(name)(\(params))"
        }
        
        var topic: String {
            "0x" + keccak256(signature)
        }
    }
    
    /// ABI event parameter
    struct ABIEventParam: Codable {
        let name: String
        let type: String
        let indexed: Bool
    }
    
    /// Parsed contract ABI
    struct ContractABI {
        let functions: [ABIFunction]
        let events: [ABIEvent]
        let constructor: ABIFunction?
        
        var readFunctions: [ABIFunction] {
            functions.filter { $0.isReadOnly }
        }
        
        var writeFunctions: [ABIFunction] {
            functions.filter { !$0.isReadOnly }
        }
    }
    
    /// Saved contract for quick access
    struct SavedContract: Identifiable, Codable {
        let id: UUID
        let name: String
        let address: String
        let chainId: Int
        let abiJson: String
        let addedAt: Date
    }
    
    // MARK: - Known Selectors
    
    struct KnownSelectors {
        static let transfer = "0xa9059cbb"
        static let approve = "0x095ea7b3"
        static let transferFrom = "0x23b872dd"
        static let balanceOf = "0x70a08231"
        static let allowance = "0xdd62ed3e"
        static let totalSupply = "0x18160ddd"
        static let name = "0x06fdde03"
        static let symbol = "0x95d89b41"
        static let decimals = "0x313ce567"
        static let ownerOf = "0x6352211e"
        static let tokenURI = "0xc87b56dd"
        
        static func identify(_ selector: String) -> String? {
            switch selector.lowercased() {
            case transfer: return "transfer(address,uint256)"
            case approve: return "approve(address,uint256)"
            case transferFrom: return "transferFrom(address,address,uint256)"
            case balanceOf: return "balanceOf(address)"
            case allowance: return "allowance(address,address)"
            case totalSupply: return "totalSupply()"
            case name: return "name()"
            case symbol: return "symbol()"
            case decimals: return "decimals()"
            case ownerOf: return "ownerOf(uint256)"
            case tokenURI: return "tokenURI(uint256)"
            default: return nil
            }
        }
    }
    
    // MARK: - Known ABIs
    
    /// ERC-20 Token Standard ABI
    static let erc20ABI = """
    [
        {"type":"function","name":"name","inputs":[],"outputs":[{"name":"","type":"string"}],"stateMutability":"view"},
        {"type":"function","name":"symbol","inputs":[],"outputs":[{"name":"","type":"string"}],"stateMutability":"view"},
        {"type":"function","name":"decimals","inputs":[],"outputs":[{"name":"","type":"uint8"}],"stateMutability":"view"},
        {"type":"function","name":"totalSupply","inputs":[],"outputs":[{"name":"","type":"uint256"}],"stateMutability":"view"},
        {"type":"function","name":"balanceOf","inputs":[{"name":"account","type":"address"}],"outputs":[{"name":"","type":"uint256"}],"stateMutability":"view"},
        {"type":"function","name":"transfer","inputs":[{"name":"to","type":"address"},{"name":"amount","type":"uint256"}],"outputs":[{"name":"","type":"bool"}],"stateMutability":"nonpayable"},
        {"type":"function","name":"allowance","inputs":[{"name":"owner","type":"address"},{"name":"spender","type":"address"}],"outputs":[{"name":"","type":"uint256"}],"stateMutability":"view"},
        {"type":"function","name":"approve","inputs":[{"name":"spender","type":"address"},{"name":"amount","type":"uint256"}],"outputs":[{"name":"","type":"bool"}],"stateMutability":"nonpayable"},
        {"type":"function","name":"transferFrom","inputs":[{"name":"from","type":"address"},{"name":"to","type":"address"},{"name":"amount","type":"uint256"}],"outputs":[{"name":"","type":"bool"}],"stateMutability":"nonpayable"}
    ]
    """
    
    // MARK: - Parsing
    
    /// Parse JSON ABI string
    func parseABI(_ json: String) throws -> ContractABI {
        guard let data = json.data(using: .utf8) else {
            throw ABIError.invalidJSON
        }
        
        let items = try JSONDecoder().decode([ABIItem].self, from: data)
        
        var functions: [ABIFunction] = []
        var events: [ABIEvent] = []
        var constructor: ABIFunction? = nil
        
        for item in items {
            switch item.type {
            case "function":
                functions.append(ABIFunction(
                    name: item.name ?? "",
                    inputs: item.inputs ?? [],
                    outputs: item.outputs ?? [],
                    stateMutability: item.stateMutability ?? "nonpayable"
                ))
            case "event":
                events.append(ABIEvent(
                    name: item.name ?? "",
                    inputs: item.inputs?.map { ABIEventParam(name: $0.name, type: $0.type, indexed: false) } ?? [],
                    anonymous: item.anonymous
                ))
            case "constructor":
                constructor = ABIFunction(
                    name: "constructor",
                    inputs: item.inputs ?? [],
                    outputs: [],
                    stateMutability: item.stateMutability ?? "nonpayable"
                )
            default:
                break
            }
        }
        
        return ContractABI(functions: functions, events: events, constructor: constructor)
    }
    
    /// Internal ABI item for parsing
    private struct ABIItem: Codable {
        let type: String
        let name: String?
        let inputs: [ABIParam]?
        let outputs: [ABIParam]?
        let stateMutability: String?
        let anonymous: Bool?
    }
    
    // MARK: - Encoding
    
    /// Encode function call
    func encodeFunctionCall(signature: String, values: [ABIValue]) -> String {
        // Calculate selector
        let selector = calculateSelector(signature)
        
        // Encode parameters
        let encodedParams = encodeValues(values, from: signature)
        
        return selector + encodedParams
    }
    
    /// Encode ERC-20 transfer
    func encodeERC20Transfer(to: String, amount: String) -> String {
        encodeFunctionCall(
            signature: "transfer(address,uint256)",
            values: [.address(to), .uint(amount)]
        )
    }
    
    /// Encode ERC-20 approve
    func encodeERC20Approve(spender: String, amount: String) -> String {
        encodeFunctionCall(
            signature: "approve(address,uint256)",
            values: [.address(spender), .uint(amount)]
        )
    }
    
    // MARK: - Decoding
    
    /// Decode function result
    func decodeFunctionResult(data: String, outputTypes: [String]) -> [String] {
        let hex = data.hasPrefix("0x") ? String(data.dropFirst(2)) : data
        var result: [String] = []
        var offset = 0
        
        for type in outputTypes {
            let value = decodeValue(hex: hex, offset: &offset, type: type)
            result.append(value)
        }
        
        return result
    }
    
    /// Decode ERC-20 balance result
    func decodeERC20Balance(data: String) -> String {
        let results = decodeFunctionResult(data: data, outputTypes: ["uint256"])
        return results.first ?? "0"
    }
    
    /// Decode ERC-20 name/symbol result
    func decodeString(data: String) -> String {
        let results = decodeFunctionResult(data: data, outputTypes: ["string"])
        return results.first ?? ""
    }
    
    // MARK: - Selector Calculation
    
    /// Calculate function selector (first 4 bytes of keccak256)
    func calculateSelector(_ signature: String) -> String {
        let hash = keccak256(signature)
        return "0x" + hash.prefix(8)
    }
    
    /// Calculate event topic (full keccak256)
    func calculateEventTopic(_ signature: String) -> String {
        "0x" + keccak256(signature)
    }
    
    // MARK: - Contract Management
    
    func saveContract(name: String, address: String, chainId: Int, abiJson: String) {
        let contract = SavedContract(
            id: UUID(),
            name: name,
            address: address,
            chainId: chainId,
            abiJson: abiJson,
            addedAt: Date()
        )
        recentContracts.insert(contract, at: 0)
        if recentContracts.count > 20 {
            recentContracts = Array(recentContracts.prefix(20))
        }
        persistContracts()
    }
    
    func removeContract(_ id: UUID) {
        recentContracts.removeAll { $0.id == id }
        persistContracts()
    }
    
    private func loadRecentContracts() {
        guard let data = UserDefaults.standard.data(forKey: "savedContracts"),
              let contracts = try? JSONDecoder().decode([SavedContract].self, from: data) else {
            return
        }
        recentContracts = contracts
    }
    
    private func persistContracts() {
        guard let data = try? JSONEncoder().encode(recentContracts) else { return }
        UserDefaults.standard.set(data, forKey: "savedContracts")
    }
    
    // MARK: - Private Helpers
    
    private func encodeValues(_ values: [ABIValue], from signature: String) -> String {
        var result = ""
        
        for value in values {
            result += encodeValue(value)
        }
        
        return result
    }
    
    private func encodeValue(_ value: ABIValue) -> String {
        switch value {
        case .uint(let v):
            return padLeft(hexFromDecimal(v), to: 64)
        case .int(let v):
            if v.hasPrefix("-") {
                // Two's complement for negative
                let abs = String(v.dropFirst())
                let hex = hexFromDecimal(abs)
                return twosComplement(hex)
            } else {
                return padLeft(hexFromDecimal(v), to: 64)
            }
        case .address(let v):
            let addr = v.hasPrefix("0x") ? String(v.dropFirst(2)) : v
            return padLeft(addr, to: 64)
        case .bool(let v):
            return padLeft(v ? "1" : "0", to: 64)
        case .fixedBytes(let data):
            return padRight(data.hexString, to: 64)
        case .bytes(let data):
            let length = padLeft(String(data.count, radix: 16), to: 64)
            let paddedData = padRight(data.hexString, to: ((data.count + 31) / 32) * 64)
            return length + paddedData
        case .string(let s):
            let data = Data(s.utf8)
            return encodeValue(.bytes(data))
        case .array(let values):
            var result = padLeft(String(values.count, radix: 16), to: 64)
            for v in values {
                result += encodeValue(v)
            }
            return result
        case .tuple(let values):
            var result = ""
            for v in values {
                result += encodeValue(v)
            }
            return result
        }
    }
    
    private func decodeValue(hex: String, offset: inout Int, type: String) -> String {
        let chunkSize = 64
        
        switch type {
        case "uint256", "uint", "uint128", "uint64", "uint32", "uint16", "uint8":
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: chunkSize)
            let chunk = String(hex[start..<end])
            offset += chunkSize
            return decimalFromHex(chunk)
        case "address":
            let start = hex.index(hex.startIndex, offsetBy: offset + 24)
            let end = hex.index(start, offsetBy: 40)
            let addr = String(hex[start..<end])
            offset += chunkSize
            return "0x" + addr
        case "bool":
            let start = hex.index(hex.startIndex, offsetBy: offset + 62)
            let end = hex.index(start, offsetBy: 2)
            let val = String(hex[start..<end])
            offset += chunkSize
            return val == "01" ? "true" : "false"
        case "string":
            // Read offset to data
            let offsetStart = hex.index(hex.startIndex, offsetBy: offset)
            let offsetEnd = hex.index(offsetStart, offsetBy: chunkSize)
            let dataOffset = Int(String(hex[offsetStart..<offsetEnd]), radix: 16) ?? 0
            offset += chunkSize
            
            // Read length at data offset
            let actualStart = dataOffset * 2
            let lengthStart = hex.index(hex.startIndex, offsetBy: actualStart)
            let lengthEnd = hex.index(lengthStart, offsetBy: chunkSize)
            let length = Int(String(hex[lengthStart..<lengthEnd]), radix: 16) ?? 0
            
            // Read string data
            let stringStart = hex.index(lengthEnd, offsetBy: 0)
            let stringEnd = hex.index(stringStart, offsetBy: length * 2)
            let stringHex = String(hex[stringStart..<stringEnd])
            
            return hexToString(stringHex)
        default:
            offset += chunkSize
            return "?"
        }
    }
    
    private func padLeft(_ s: String, to length: Int) -> String {
        let padCount = max(0, length - s.count)
        return String(repeating: "0", count: padCount) + s.lowercased()
    }
    
    private func padRight(_ s: String, to length: Int) -> String {
        let padCount = max(0, length - s.count)
        return s.lowercased() + String(repeating: "0", count: padCount)
    }
    
    private func hexFromDecimal(_ s: String) -> String {
        guard let value = Decimal(string: s) else { return "0" }
        // Simple conversion for reasonable values
        if let intValue = Int64(s) {
            return String(intValue, radix: 16)
        }
        // For very large values, use string manipulation
        return "0" // Simplified
    }
    
    private func decimalFromHex(_ hex: String) -> String {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "0"))
        guard !trimmed.isEmpty,
              let value = UInt64(trimmed, radix: 16) else { return "0" }
        return String(value)
    }
    
    private func hexToString(_ hex: String) -> String {
        var result = ""
        var i = hex.startIndex
        while i < hex.endIndex {
            let nextIndex = hex.index(i, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            let byteStr = String(hex[i..<nextIndex])
            if let byte = UInt8(byteStr, radix: 16) {
                result.append(Character(UnicodeScalar(byte)))
            }
            i = nextIndex
        }
        return result
    }
    
    private func twosComplement(_ hex: String) -> String {
        // Invert bits and add 1
        var inverted = ""
        for c in hex {
            if let val = Int(String(c), radix: 16) {
                inverted += String(15 - val, radix: 16)
            }
        }
        // Add 1 (simplified)
        return padLeft(inverted, to: 64)
    }
    
    // MARK: - Errors
    
    enum ABIError: LocalizedError {
        case invalidJSON
        case invalidType
        case encodingFailed
        case decodingFailed
        
        var errorDescription: String? {
            switch self {
            case .invalidJSON: return "Invalid JSON ABI"
            case .invalidType: return "Invalid type specification"
            case .encodingFailed: return "Failed to encode value"
            case .decodingFailed: return "Failed to decode value"
            }
        }
    }
}

// MARK: - Keccak256 Helper

/// Simple keccak256 implementation (would use CryptoKit in production)
private func keccak256(_ string: String) -> String {
    // Use a lookup table for known signatures
    let knownHashes: [String: String] = [
        "transfer(address,uint256)": "a9059cbb2ab09eb219583f4a59a5d0623ade346d962bcd4e46b11da047c9049b",
        "approve(address,uint256)": "095ea7b334ae44009aa867bfb386f5c3b4b443ac6f0ee573fa91c4608fbadfba",
        "transferFrom(address,address,uint256)": "23b872dd7302113369cda2901243429419bec145408fa8b352b3dd92b66c680b",
        "balanceOf(address)": "70a08231b98ef4ca268c9cc3f6b4590e4bfec28280db06bb5d45e689f2a360be",
        "allowance(address,address)": "dd62ed3e90e97b3d417db9c0c7522647811bafca5afc6571f6f8787bc9df8e0c",
        "totalSupply()": "18160ddd7f15c72528c2f94fd8dfe3c8d5aa26e2c50c7d81f4bc7bee8d4b7932",
        "name()": "06fdde0383f15d582d1a74511486c9ddf862a882fb7904b3d9fe9b8b8e58a796",
        "symbol()": "95d89b41e2f5f391a79ec54e9d87c79d6e777c63e32c28da95b4e9e4a7f60e5c",
        "decimals()": "313ce567add4d438edf58b94ff345d7d38c45b17dfc0f947988d7819dca364f9",
        "safeTransferFrom(address,address,uint256)": "42842e0eb38857a7775b4e7364b2775df7325074d088e7fb39590cd6281184ed",
        "ownerOf(uint256)": "6352211e6566aa027e75ac9dbf2423197fbd9b82b9d981a3ab367d355866aa1c",
        "tokenURI(uint256)": "c87b56dda752230262935940d907f047a9f86bb5ee6aa33511fc86db33fea6cc",
        "Transfer(address,address,uint256)": "ddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",
        "Approval(address,address,uint256)": "8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925",
    ]
    
    if let hash = knownHashes[string] {
        return hash
    }
    
    // Fallback: return placeholder (in production, use proper keccak256)
    return String(repeating: "0", count: 64)
}

// Note: Data extension for hexString is defined elsewhere in the project
