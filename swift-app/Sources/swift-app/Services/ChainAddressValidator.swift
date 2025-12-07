import Foundation
import CryptoKit

// MARK: - Chain Address Validator

/// Validates cryptocurrency addresses across multiple chains
/// Supports checksums, format validation, and ENS/domain resolution
@MainActor
final class ChainAddressValidator: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = ChainAddressValidator()
    
    // MARK: - Published State
    
    @Published var isResolving = false
    @Published var resolvedAddress: String?
    @Published var resolvedName: String?
    @Published var validationError: String?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public API
    
    /// Validate an address for a specific chain
    /// - Parameters:
    ///   - address: The address or domain name to validate
    ///   - chainId: The chain identifier (bitcoin, ethereum, solana, xrp, litecoin)
    /// - Returns: Validation result with normalized address
    func validate(address: String, chainId: String) async -> ChainAddressValidationResult {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            return .invalid(error: "Address cannot be empty")
        }
        
        // Check if it's a domain name that needs resolution
        if isDomainName(trimmed) {
            return await resolveDomain(trimmed, chainId: chainId)
        }
        
        // Direct address validation
        switch chainId.lowercased() {
        case "bitcoin", "bitcoin-testnet":
            return validateBitcoinAddress(trimmed, isTestnet: chainId == "bitcoin-testnet")
        case "litecoin":
            return validateLitecoinAddress(trimmed)
        case "ethereum", "ethereum-sepolia":
            return validateEthereumAddress(trimmed)
        case "solana":
            return validateSolanaAddress(trimmed)
        case "xrp":
            return validateXRPAddress(trimmed)
        default:
            return .invalid(error: "Unsupported chain: \(chainId)")
        }
    }
    
    /// Quick synchronous check if address format is valid (no network calls)
    func isValidFormat(address: String, chainId: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch chainId.lowercased() {
        case "bitcoin", "bitcoin-testnet":
            return isValidBitcoinFormat(trimmed, isTestnet: chainId == "bitcoin-testnet")
        case "litecoin":
            return isValidLitecoinFormat(trimmed)
        case "ethereum", "ethereum-sepolia":
            return isValidEthereumFormat(trimmed)
        case "solana":
            return isValidSolanaFormat(trimmed)
        case "xrp":
            return isValidXRPFormat(trimmed)
        default:
            return false
        }
    }
    
    // MARK: - Domain Resolution
    
    private func isDomainName(_ input: String) -> Bool {
        // ENS domains (.eth)
        if input.lowercased().hasSuffix(".eth") {
            return true
        }
        // Solana Name Service (.sol)
        if input.lowercased().hasSuffix(".sol") {
            return true
        }
        // Unstoppable Domains (.crypto, .nft, .x, .wallet, .blockchain, .bitcoin)
        let unstoppableTLDs = [".crypto", ".nft", ".x", ".wallet", ".blockchain", ".bitcoin", ".dao", ".888"]
        for tld in unstoppableTLDs {
            if input.lowercased().hasSuffix(tld) {
                return true
            }
        }
        return false
    }
    
    private func resolveDomain(_ domain: String, chainId: String) async -> ChainAddressValidationResult {
        isResolving = true
        defer { isResolving = false }
        
        // ENS resolution (for .eth domains)
        if domain.lowercased().hasSuffix(".eth") {
            return await resolveENS(domain, chainId: chainId)
        }
        
        // Solana Name Service resolution (for .sol domains)
        if domain.lowercased().hasSuffix(".sol") {
            return await resolveSolanaNS(domain, chainId: chainId)
        }
        
        // Unstoppable Domains resolution
        return await resolveUnstoppableDomain(domain, chainId: chainId)
    }
    
    /// Resolve ENS domain using Ethereum RPC
    private func resolveENS(_ domain: String, chainId: String) async -> ChainAddressValidationResult {
        // ENS only resolves to Ethereum addresses by default
        // For other chains, we'd need to query the chain-specific resolver
        
        guard chainId.hasPrefix("ethereum") else {
            return .invalid(error: "ENS domains only support Ethereum addresses")
        }
        
        // Use public ENS resolver
        // The resolver uses namehash to compute the node
        let node = namehash(domain)
        
        // ENS Registry address (mainnet)
        let registryAddress = "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e"
        
        // First, get the resolver address from registry
        // resolver(bytes32 node) -> address
        let resolverSelector = "0178b8bf" // keccak256("resolver(bytes32)")[:4]
        let callData = "0x" + resolverSelector + node
        
        do {
            let rpcURL = chainId == "ethereum-sepolia" 
                ? APIConfig.alchemySepoliaURL 
                : APIConfig.alchemyMainnetURL
            
            // Get resolver address
            let resolverAddress = try await ethCall(to: registryAddress, data: callData, rpcURL: rpcURL)
            
            guard resolverAddress != "0x0000000000000000000000000000000000000000000000000000000000000000" else {
                return .invalid(error: "ENS name not found: \(domain)")
            }
            
            // Extract address from padded response
            let cleanResolver = "0x" + String(resolverAddress.dropFirst(26))
            
            // Now call addr(bytes32 node) on the resolver
            let addrSelector = "3b3b57de" // keccak256("addr(bytes32)")[:4]
            let addrCallData = "0x" + addrSelector + node
            
            let addressResult = try await ethCall(to: cleanResolver, data: addrCallData, rpcURL: rpcURL)
            
            guard addressResult != "0x0000000000000000000000000000000000000000000000000000000000000000" else {
                return .invalid(error: "No address set for \(domain)")
            }
            
            // Extract the 20-byte address
            let resolvedAddr = "0x" + String(addressResult.suffix(40))
            
            resolvedAddress = resolvedAddr
            resolvedName = domain
            
            return .valid(
                normalizedAddress: resolvedAddr.lowercased(),
                displayName: domain,
                checksumAddress: toChecksumAddress(resolvedAddr)
            )
        } catch {
            return .invalid(error: "Failed to resolve ENS: \(error.localizedDescription)")
        }
    }
    
    /// Resolve Unstoppable Domains using their API
    private func resolveUnstoppableDomain(_ domain: String, chainId: String) async -> ChainAddressValidationResult {
        // Map chain to Unstoppable's ticker format
        let ticker: String
        switch chainId.lowercased() {
        case "bitcoin", "bitcoin-testnet":
            ticker = "BTC"
        case "ethereum", "ethereum-sepolia":
            ticker = "ETH"
        case "litecoin":
            ticker = "LTC"
        case "solana":
            ticker = "SOL"
        case "xrp":
            ticker = "XRP"
        default:
            ticker = "ETH"
        }
        
        // Use Unstoppable Domains resolution API
        let urlString = "https://resolve.unstoppabledomains.com/domains/\(domain)"
        
        guard let url = URL(string: urlString) else {
            return .invalid(error: "Invalid domain format")
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .invalid(error: "Invalid response")
            }
            
            if httpResponse.statusCode == 404 {
                return .invalid(error: "Domain not found: \(domain)")
            }
            
            guard httpResponse.statusCode == 200 else {
                return .invalid(error: "Failed to resolve domain (HTTP \(httpResponse.statusCode))")
            }
            
            // Parse response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let records = json["records"] as? [String: String] else {
                return .invalid(error: "Invalid domain response format")
            }
            
            // Look for the address in records
            // Keys are like "crypto.ETH.address", "crypto.BTC.address"
            let addressKey = "crypto.\(ticker).address"
            
            guard let resolvedAddr = records[addressKey], !resolvedAddr.isEmpty else {
                return .invalid(error: "No \(ticker) address set for \(domain)")
            }
            
            resolvedAddress = resolvedAddr
            resolvedName = domain
            
            // Validate the resolved address
            return await validate(address: resolvedAddr, chainId: chainId)
            
        } catch {
            return .invalid(error: "Failed to resolve domain: \(error.localizedDescription)")
        }
    }
    
    /// Resolve Solana Name Service (.sol) domains
    private func resolveSolanaNS(_ domain: String, chainId: String) async -> ChainAddressValidationResult {
        // SNS only resolves to Solana addresses
        guard chainId == "solana" else {
            return .invalid(error: "Solana domains (.sol) only support Solana addresses")
        }
        
        // Remove .sol suffix
        let name = domain.hasSuffix(".sol") ? String(domain.dropLast(4)) : domain
        
        // Use Bonfida SNS SDK proxy API
        let urlString = "https://sns-sdk-proxy.bonfida.workers.dev/resolve/\(name)"
        
        guard let url = URL(string: urlString) else {
            return .invalid(error: "Invalid domain format")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return .invalid(error: "Domain not found: \(domain)")
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? String, !result.isEmpty else {
                return .invalid(error: "No address set for \(domain)")
            }
            
            resolvedAddress = result
            resolvedName = domain
            
            return .valid(
                normalizedAddress: result,
                displayName: domain,
                checksumAddress: result // Solana addresses don't have checksums
            )
        } catch {
            return .invalid(error: "Failed to resolve Solana domain: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Bitcoin Validation
    
    private func validateBitcoinAddress(_ address: String, isTestnet: Bool) -> ChainAddressValidationResult {
        // P2PKH (Legacy): 1... (mainnet), m/n... (testnet)
        // P2SH: 3... (mainnet), 2... (testnet)
        // P2WPKH (Bech32): bc1q... (mainnet), tb1q... (testnet)
        // P2TR (Taproot): bc1p... (mainnet), tb1p... (testnet)
        
        if address.lowercased().hasPrefix("bc1") || address.lowercased().hasPrefix("tb1") {
            // Bech32/Bech32m address
            return validateBech32Address(address, isTestnet: isTestnet, expectedHRP: isTestnet ? "tb" : "bc")
        } else {
            // Base58Check address
            return validateBase58CheckAddress(address, isTestnet: isTestnet, coinType: .bitcoin)
        }
    }
    
    private func isValidBitcoinFormat(_ address: String, isTestnet: Bool) -> Bool {
        if isTestnet {
            // Testnet: tb1..., m..., n..., 2...
            return address.hasPrefix("tb1") || address.hasPrefix("m") || address.hasPrefix("n") || address.hasPrefix("2")
        } else {
            // Mainnet: bc1..., 1..., 3...
            return address.hasPrefix("bc1") || address.hasPrefix("1") || address.hasPrefix("3")
        }
    }
    
    // MARK: - Litecoin Validation
    
    private func validateLitecoinAddress(_ address: String) -> ChainAddressValidationResult {
        // P2PKH: L... 
        // P2SH: M... or 3...
        // P2WPKH (Bech32): ltc1q...
        
        if address.lowercased().hasPrefix("ltc1") {
            return validateBech32Address(address, isTestnet: false, expectedHRP: "ltc")
        } else {
            return validateBase58CheckAddress(address, isTestnet: false, coinType: .litecoin)
        }
    }
    
    private func isValidLitecoinFormat(_ address: String) -> Bool {
        return address.hasPrefix("ltc1") || address.hasPrefix("L") || address.hasPrefix("M") || address.hasPrefix("3")
    }
    
    // MARK: - Ethereum Validation
    
    private func validateEthereumAddress(_ address: String) -> ChainAddressValidationResult {
        // Must start with 0x and be 42 characters total (0x + 40 hex chars)
        guard address.hasPrefix("0x") || address.hasPrefix("0X") else {
            return .invalid(error: "Ethereum address must start with 0x")
        }
        
        guard address.count == 42 else {
            return .invalid(error: "Ethereum address must be 42 characters")
        }
        
        let hexPart = String(address.dropFirst(2))
        
        // Check if all characters are valid hex
        guard hexPart.allSatisfy({ $0.isHexDigit }) else {
            return .invalid(error: "Invalid characters in Ethereum address")
        }
        
        // EIP-55 checksum validation
        let checksummed = toChecksumAddress(address)
        
        // If original has mixed case, verify it matches checksum
        if hexPart.contains(where: { $0.isUppercase }) && hexPart.contains(where: { $0.isLowercase }) {
            if address != checksummed {
                return .invalid(error: "Invalid checksum. Did you mean: \(checksummed)?")
            }
        }
        
        return .valid(
            normalizedAddress: address.lowercased(),
            displayName: nil,
            checksumAddress: checksummed
        )
    }
    
    private func isValidEthereumFormat(_ address: String) -> Bool {
        guard address.hasPrefix("0x") || address.hasPrefix("0X") else { return false }
        guard address.count == 42 else { return false }
        let hexPart = String(address.dropFirst(2))
        return hexPart.allSatisfy { $0.isHexDigit }
    }
    
    /// EIP-55 checksum encoding
    private func toChecksumAddress(_ address: String) -> String {
        let addr = address.lowercased().replacingOccurrences(of: "0x", with: "")
        let hash = keccak256(addr.data(using: .utf8)!).map { String(format: "%02x", $0) }.joined()
        
        var result = "0x"
        for (i, char) in addr.enumerated() {
            if char.isHexDigit && char.isLetter {
                let hashChar = hash[hash.index(hash.startIndex, offsetBy: i)]
                if let hashValue = Int(String(hashChar), radix: 16), hashValue >= 8 {
                    result.append(char.uppercased())
                } else {
                    result.append(char)
                }
            } else {
                result.append(char)
            }
        }
        return result
    }
    
    // MARK: - Solana Validation
    
    private func validateSolanaAddress(_ address: String) -> ChainAddressValidationResult {
        // Solana addresses are base58 encoded, 32-44 characters
        guard address.count >= 32 && address.count <= 44 else {
            return .invalid(error: "Solana address must be 32-44 characters")
        }
        
        // Valid base58 characters (no 0, O, I, l)
        let base58Chars = CharacterSet(charactersIn: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        guard address.unicodeScalars.allSatisfy({ base58Chars.contains($0) }) else {
            return .invalid(error: "Invalid characters in Solana address")
        }
        
        // Decode and verify length (should be 32 bytes)
        guard let decoded = base58Decode(address), decoded.count == 32 else {
            return .invalid(error: "Invalid Solana address encoding")
        }
        
        return .valid(normalizedAddress: address, displayName: nil, checksumAddress: nil)
    }
    
    private func isValidSolanaFormat(_ address: String) -> Bool {
        guard address.count >= 32 && address.count <= 44 else { return false }
        let base58Chars = CharacterSet(charactersIn: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        return address.unicodeScalars.allSatisfy { base58Chars.contains($0) }
    }
    
    // MARK: - XRP Validation
    
    private func validateXRPAddress(_ address: String) -> ChainAddressValidationResult {
        // XRP addresses start with 'r' and are 25-35 characters (base58check encoded)
        guard address.hasPrefix("r") else {
            return .invalid(error: "XRP address must start with 'r'")
        }
        
        guard address.count >= 25 && address.count <= 35 else {
            return .invalid(error: "XRP address must be 25-35 characters")
        }
        
        // Valid base58 characters
        let base58Chars = CharacterSet(charactersIn: "rpshnaf39wBUDNEGHJKLM4PQRST7VWXYZ2bcdeCg65jkm8oFqi1tuvAxyz")
        guard address.unicodeScalars.allSatisfy({ base58Chars.contains($0) }) else {
            return .invalid(error: "Invalid characters in XRP address")
        }
        
        // XRP uses base58check - verify checksum
        guard let decoded = base58CheckDecode(address, alphabet: .ripple) else {
            return .invalid(error: "Invalid XRP address checksum")
        }
        
        // First byte should be 0x00 for r-addresses
        guard decoded.first == 0x00 else {
            return .invalid(error: "Invalid XRP address type")
        }
        
        return .valid(normalizedAddress: address, displayName: nil, checksumAddress: nil)
    }
    
    private func isValidXRPFormat(_ address: String) -> Bool {
        guard address.hasPrefix("r") else { return false }
        guard address.count >= 25 && address.count <= 35 else { return false }
        let base58Chars = CharacterSet(charactersIn: "rpshnaf39wBUDNEGHJKLM4PQRST7VWXYZ2bcdeCg65jkm8oFqi1tuvAxyz")
        return address.unicodeScalars.allSatisfy { base58Chars.contains($0) }
    }
    
    // MARK: - Helper Functions
    
    private func validateBech32Address(_ address: String, isTestnet: Bool, expectedHRP: String) -> ChainAddressValidationResult {
        let lower = address.lowercased()
        
        guard lower.hasPrefix(expectedHRP + "1") else {
            return .invalid(error: "Invalid address prefix")
        }
        
        // Bech32 character set
        let bech32Chars = CharacterSet(charactersIn: "qpzry9x8gf2tvdw0s3jn54khce6mua7l")
        let dataPart = String(lower.dropFirst(expectedHRP.count + 1))
        
        guard dataPart.unicodeScalars.allSatisfy({ bech32Chars.contains($0) }) else {
            return .invalid(error: "Invalid characters in address")
        }
        
        // Basic length check (minimum for P2WPKH is ~42 chars)
        guard address.count >= 42 && address.count <= 62 else {
            return .invalid(error: "Invalid address length")
        }
        
        // TODO: Full bech32/bech32m checksum verification
        
        return .valid(normalizedAddress: lower, displayName: nil, checksumAddress: nil)
    }
    
    private enum CoinType {
        case bitcoin
        case litecoin
    }
    
    private func validateBase58CheckAddress(_ address: String, isTestnet: Bool, coinType: CoinType) -> ChainAddressValidationResult {
        guard let decoded = base58CheckDecode(address, alphabet: .bitcoin) else {
            return .invalid(error: "Invalid address checksum")
        }
        
        guard decoded.count >= 21 else {
            return .invalid(error: "Address too short")
        }
        
        let version = decoded[0]
        
        // Validate version byte
        let validVersions: [UInt8]
        switch coinType {
        case .bitcoin:
            validVersions = isTestnet ? [0x6f, 0xc4] : [0x00, 0x05] // m/n, 2 for testnet; 1, 3 for mainnet
        case .litecoin:
            validVersions = [0x30, 0x32, 0x05] // L, M, 3
        }
        
        guard validVersions.contains(version) else {
            return .invalid(error: "Invalid address version for this network")
        }
        
        return .valid(normalizedAddress: address, displayName: nil, checksumAddress: nil)
    }
    
    // MARK: - Encoding Helpers
    
    private enum Base58Alphabet {
        case bitcoin
        case ripple
        
        var characters: String {
            switch self {
            case .bitcoin:
                return "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
            case .ripple:
                return "rpshnaf39wBUDNEGHJKLM4PQRST7VWXYZ2bcdeCg65jkm8oFqi1tuvAxyz"
            }
        }
    }
    
    private func base58Decode(_ string: String) -> Data? {
        let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        var result = [UInt8]()
        
        for char in string {
            guard let index = alphabet.firstIndex(of: char) else { return nil }
            var carry = alphabet.distance(from: alphabet.startIndex, to: index)
            
            for i in 0..<result.count {
                carry += 58 * Int(result[i])
                result[i] = UInt8(carry & 0xff)
                carry >>= 8
            }
            
            while carry > 0 {
                result.append(UInt8(carry & 0xff))
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
    
    private func base58CheckDecode(_ string: String, alphabet: Base58Alphabet) -> Data? {
        let chars = alphabet.characters
        var result = [UInt8]()
        
        for char in string {
            guard let index = chars.firstIndex(of: char) else { return nil }
            var carry = chars.distance(from: chars.startIndex, to: index)
            
            for i in 0..<result.count {
                carry += 58 * Int(result[i])
                result[i] = UInt8(carry & 0xff)
                carry >>= 8
            }
            
            while carry > 0 {
                result.append(UInt8(carry & 0xff))
                carry >>= 8
            }
        }
        
        // Add leading zeros based on alphabet
        let leadingChar = chars.first!
        for char in string {
            if char == leadingChar {
                result.append(0)
            } else {
                break
            }
        }
        
        let decoded = Data(result.reversed())
        
        // Verify checksum (last 4 bytes)
        guard decoded.count >= 4 else { return nil }
        
        let payload = decoded.dropLast(4)
        let checksum = decoded.suffix(4)
        
        let hash = doubleSHA256(Data(payload))
        let expectedChecksum = hash.prefix(4)
        
        guard checksum.elementsEqual(expectedChecksum) else { return nil }
        
        return Data(payload)
    }
    
    private func doubleSHA256(_ data: Data) -> Data {
        let hash1 = SHA256.hash(data: data)
        let hash2 = SHA256.hash(data: Data(hash1))
        return Data(hash2)
    }
    
    /// ENS namehash algorithm
    private func namehash(_ name: String) -> String {
        var node = Data(repeating: 0, count: 32)
        
        if !name.isEmpty {
            let labels = name.split(separator: ".").reversed()
            for label in labels {
                let labelHash = keccak256(String(label).data(using: .utf8)!)
                node = keccak256(node + labelHash)
            }
        }
        
        return node.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Keccak-256 hash (used by Ethereum)
    private func keccak256(_ data: Data) -> Data {
        // Simple Keccak-256 implementation for EIP-55 checksum
        // For production, use a proper crypto library
        var state = [UInt64](repeating: 0, count: 25)
        let rateInBytes = 136 // (1600 - 256 * 2) / 8
        
        var input = data
        input.append(0x01) // Keccak padding
        while input.count % rateInBytes != rateInBytes - 1 {
            input.append(0x00)
        }
        input.append(0x80)
        
        // Process blocks
        for blockStart in stride(from: 0, to: input.count, by: rateInBytes) {
            for i in 0..<(rateInBytes / 8) {
                let offset = blockStart + i * 8
                if offset + 8 <= input.count {
                    var value: UInt64 = 0
                    for j in 0..<8 {
                        value |= UInt64(input[offset + j]) << (j * 8)
                    }
                    state[i] ^= value
                }
            }
            keccakF1600(&state)
        }
        
        // Extract output
        var output = Data()
        for i in 0..<4 {
            var value = state[i]
            for _ in 0..<8 {
                output.append(UInt8(value & 0xff))
                value >>= 8
            }
        }
        
        return output
    }
    
    /// Keccak-f[1600] permutation
    private func keccakF1600(_ state: inout [UInt64]) {
        let roundConstants: [UInt64] = [
            0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000,
            0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
            0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
            0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003,
            0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a,
            0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008
        ]
        
        let rotations: [[Int]] = [
            [0, 36, 3, 41, 18],
            [1, 44, 10, 45, 2],
            [62, 6, 43, 15, 61],
            [28, 55, 25, 21, 56],
            [27, 20, 39, 8, 14]
        ]
        
        for round in 0..<24 {
            // θ (theta)
            var c = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 {
                c[x] = state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20]
            }
            var d = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 {
                d[x] = c[(x + 4) % 5] ^ rotateLeft(c[(x + 1) % 5], by: 1)
            }
            for x in 0..<5 {
                for y in 0..<5 {
                    state[x + y * 5] ^= d[x]
                }
            }
            
            // ρ (rho) and π (pi)
            var b = [[UInt64]](repeating: [UInt64](repeating: 0, count: 5), count: 5)
            for x in 0..<5 {
                for y in 0..<5 {
                    b[y][(2 * x + 3 * y) % 5] = rotateLeft(state[x + y * 5], by: rotations[y][x])
                }
            }
            
            // χ (chi)
            for x in 0..<5 {
                for y in 0..<5 {
                    state[x + y * 5] = b[x][y] ^ ((~b[(x + 1) % 5][y]) & b[(x + 2) % 5][y])
                }
            }
            
            // ι (iota)
            state[0] ^= roundConstants[round]
        }
    }
    
    private func rotateLeft(_ value: UInt64, by count: Int) -> UInt64 {
        return (value << count) | (value >> (64 - count))
    }
    
    /// Make an eth_call to an RPC endpoint
    private func ethCall(to: String, data: String, rpcURL: String) async throws -> String {
        guard let url = URL(string: rpcURL) else {
            throw AddressValidationError.invalidURL
        }
        
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_call",
            "params": [
                ["to": to, "data": data],
                "latest"
            ],
            "id": 1
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (responseData, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let result = json["result"] as? String else {
            throw AddressValidationError.invalidResponse
        }
        
        return result
    }
}

// MARK: - Chain Address Validation Result

/// Result type for chain address validation with ENS support
enum ChainAddressValidationResult {
    case valid(normalizedAddress: String, displayName: String?, checksumAddress: String?)
    case invalid(error: String)
    
    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
    
    var address: String? {
        if case .valid(let addr, _, _) = self { return addr }
        return nil
    }
    
    var errorMessage: String? {
        if case .invalid(let error) = self { return error }
        return nil
    }
    
    var checksummed: String? {
        if case .valid(_, _, let checksum) = self { return checksum }
        return nil
    }
}

// MARK: - Errors

enum AddressValidationError: LocalizedError {
    case invalidURL
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid RPC URL"
        case .invalidResponse: return "Invalid response from RPC"
        }
    }
}
