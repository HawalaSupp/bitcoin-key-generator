import Foundation
import CryptoKit

// MARK: - ENS & Domain Resolution Service

/// Service for resolving blockchain domain names to addresses
/// Supports ENS (.eth), Unstoppable Domains (.crypto, .nft, etc.), Solana SNS (.sol)
@MainActor
class ENSResolver: ObservableObject {
    
    // MARK: - Published State
    
    @Published var isResolving = false
    @Published var lastError: String?
    
    // MARK: - Configuration
    
    private let ethMainnetRPC = "https://eth-mainnet.g.alchemy.com/v2/demo"
    private let polygonRPC = "https://polygon-mainnet.g.alchemy.com/v2/demo"
    private let solanaRPC = "https://api.mainnet-beta.solana.com"
    
    // ENS Registry contract on Ethereum mainnet
    private let ensRegistryAddress = "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e"
    
    // Public resolver for ENS
    private let ensPublicResolver = "0x4976fb03C32e5B8cfe2b6cCB31c09Ba78EBaBa41"
    
    // Unstoppable Domains resolver on Polygon
    private let udResolverAddress = "0xa9a6A3626993D487d2Dbda3173cf58cA1a9D9e9f"
    
    // Cache for resolved addresses
    private var cache: [String: CachedResolution] = [:]
    private let cacheExpiry: TimeInterval = 3600 // 1 hour
    
    // MARK: - Supported Domain Types
    
    enum DomainType {
        case ens       // .eth
        case ud        // .crypto, .nft, .wallet, .x, .bitcoin, .dao, .888, .zil, .blockchain
        case sns       // .sol
        case unknown
        
        var supportedChains: [String] {
            switch self {
            case .ens: return ["ETH", "BTC", "LTC"]
            case .ud:  return ["ETH", "BTC", "SOL", "MATIC", "BNB", "LTC"]
            case .sns: return ["SOL"]
            case .unknown: return []
            }
        }
    }
    
    // MARK: - Resolution Methods
    
    /// Resolve a domain name to an address for a specific chain
    func resolve(domain: String, chain: String = "ETH") async -> String? {
        let normalizedDomain = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = "\(normalizedDomain):\(chain)"
        
        // Check cache first
        if let cached = cache[cacheKey], !cached.isExpired {
            return cached.address
        }
        
        await MainActor.run {
            isResolving = true
            lastError = nil
        }
        
        defer {
            Task { @MainActor in
                isResolving = false
            }
        }
        
        let domainType = detectDomainType(normalizedDomain)
        
        do {
            let address: String?
            
            switch domainType {
            case .ens:
                address = try await resolveENS(domain: normalizedDomain, chain: chain)
            case .ud:
                address = try await resolveUnstoppable(domain: normalizedDomain, chain: chain)
            case .sns:
                address = try await resolveSolana(domain: normalizedDomain)
            case .unknown:
                throw ResolverError.unsupportedDomain
            }
            
            // Cache the result
            if let addr = address {
                cache[cacheKey] = CachedResolution(address: addr, timestamp: Date())
            }
            
            return address
        } catch {
            await MainActor.run {
                lastError = error.localizedDescription
            }
            return nil
        }
    }
    
    /// Detect the type of domain from its TLD
    func detectDomainType(_ domain: String) -> DomainType {
        let lowercased = domain.lowercased()
        
        if lowercased.hasSuffix(".eth") {
            return .ens
        }
        
        // Unstoppable Domains TLDs
        let udTLDs = [".crypto", ".nft", ".wallet", ".x", ".bitcoin", ".dao", ".888", ".zil", ".blockchain"]
        for tld in udTLDs {
            if lowercased.hasSuffix(tld) {
                return .ud
            }
        }
        
        if lowercased.hasSuffix(".sol") {
            return .sns
        }
        
        return .unknown
    }
    
    /// Check if a string looks like a domain name
    func isDomainName(_ input: String) -> Bool {
        let domain = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return detectDomainType(domain) != .unknown
    }
    
    // MARK: - ENS Resolution
    
    private func resolveENS(domain: String, chain: String) async throws -> String? {
        // ENS uses namehash algorithm
        let node = namehash(domain)
        
        // First, get the resolver for this domain from ENS registry
        let resolverAddress = try await getENSResolver(node: node)
        
        guard let resolver = resolverAddress, !resolver.isEmpty else {
            throw ResolverError.noResolver
        }
        
        // Then, call the resolver to get the address
        // For multi-chain resolution, use addr(bytes32,uint256) with chain ID
        let address: String?
        
        switch chain.uppercased() {
        case "ETH":
            // Use simple addr(bytes32) for Ethereum
            address = try await getENSAddress(resolver: resolver, node: node)
        case "BTC":
            // Bitcoin uses coinType 0
            address = try await getENSAddressMulticoin(resolver: resolver, node: node, coinType: 0)
        case "LTC":
            // Litecoin uses coinType 2
            address = try await getENSAddressMulticoin(resolver: resolver, node: node, coinType: 2)
        default:
            // Try EVM address for other chains
            address = try await getENSAddress(resolver: resolver, node: node)
        }
        
        return address
    }
    
    /// Compute ENS namehash
    private func namehash(_ name: String) -> String {
        var node = Data(repeating: 0, count: 32)
        
        if name.isEmpty {
            return "0x" + node.hexString
        }
        
        let labels = name.split(separator: ".").reversed()
        
        for label in labels {
            let labelHash = SHA256.hash(data: Data(String(label).utf8))
            var combined = Data()
            combined.append(node)
            combined.append(contentsOf: labelHash)
            let hash = SHA256.hash(data: combined)
            node = Data(hash)
        }
        
        return "0x" + node.hexString
    }
    
    /// Get the resolver address for an ENS name
    private func getENSResolver(node: String) async throws -> String? {
        // resolver(bytes32) function selector: 0x0178b8bf
        let data = "0x0178b8bf" + node.dropFirst(2)
        
        let result = try await ethCall(to: ensRegistryAddress, data: String(data), rpc: ethMainnetRPC)
        
        guard result.count >= 66 else { return nil }
        
        // Extract address from result (last 40 characters of 64-char hex)
        let addressHex = String(result.suffix(40))
        
        // Check if it's a zero address
        if addressHex == String(repeating: "0", count: 40) {
            return nil
        }
        
        return "0x" + addressHex
    }
    
    /// Get the address from an ENS resolver using addr(bytes32)
    private func getENSAddress(resolver: String, node: String) async throws -> String? {
        // addr(bytes32) function selector: 0x3b3b57de
        let data = "0x3b3b57de" + node.dropFirst(2)
        
        let result = try await ethCall(to: resolver, data: String(data), rpc: ethMainnetRPC)
        
        guard result.count >= 66 else { return nil }
        
        let addressHex = String(result.suffix(40))
        
        if addressHex == String(repeating: "0", count: 40) {
            return nil
        }
        
        return "0x" + addressHex
    }
    
    /// Get address for a specific coin type using addr(bytes32, uint256)
    private func getENSAddressMulticoin(resolver: String, node: String, coinType: UInt64) async throws -> String? {
        // addr(bytes32,uint256) function selector: 0xf1cb7e06
        let coinTypeHex = String(format: "%064x", coinType)
        let data = "0xf1cb7e06" + node.dropFirst(2) + coinTypeHex
        
        let result = try await ethCall(to: resolver, data: String(data), rpc: ethMainnetRPC)
        
        // The result is ABI-encoded bytes, need to decode
        guard result.count > 130 else { return nil }
        
        // Skip function response header and decode bytes
        let addressBytes = decodeABIBytes(result)
        
        if let bytes = addressBytes, !bytes.isEmpty {
            // For Bitcoin/Litecoin, convert to base58 or bech32 address
            // For now, return hex representation
            return bytes.hexString
        }
        
        return nil
    }
    
    // MARK: - Unstoppable Domains Resolution
    
    private func resolveUnstoppable(domain: String, chain: String) async throws -> String? {
        // Unstoppable Domains uses a different approach - direct contract call
        // They have a ProxyReader contract we can query
        
        // For simplicity, use their API
        let url = URL(string: "https://resolve.unstoppabledomains.com/domains/\(domain)")!
        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ResolverError.resolutionFailed
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let records = json?["records"] as? [String: String]
        
        // Map chain to UD record key
        let recordKey: String
        switch chain.uppercased() {
        case "ETH": recordKey = "crypto.ETH.address"
        case "BTC": recordKey = "crypto.BTC.address"
        case "SOL": recordKey = "crypto.SOL.address"
        case "MATIC": recordKey = "crypto.MATIC.version.MATIC.address"
        case "BNB", "BSC": recordKey = "crypto.BNB.version.BEP20.address"
        case "LTC": recordKey = "crypto.LTC.address"
        default: recordKey = "crypto.\(chain).address"
        }
        
        return records?[recordKey]
    }
    
    // MARK: - Solana Name Service Resolution
    
    private func resolveSolana(domain: String) async throws -> String? {
        // Remove .sol suffix
        let name = domain.hasSuffix(".sol") ? String(domain.dropLast(4)) : domain
        
        // SNS uses a specific program to derive the name account
        // For simplicity, use the SNS API
        let url = URL(string: "https://sns-sdk-proxy.bonfida.workers.dev/resolve/\(name)")!
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ResolverError.resolutionFailed
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["result"] as? String
    }
    
    // MARK: - Reverse Resolution
    
    /// Reverse resolve an address to a domain name
    func reverseResolve(address: String, chain: String = "ETH") async -> String? {
        guard chain.uppercased() == "ETH" else {
            // Currently only ENS supports reverse resolution widely
            return nil
        }
        
        // ENS reverse resolution uses addr.reverse
        let reverseNode = namehash("\(address.lowercased().dropFirst(2)).addr.reverse")
        
        do {
            // Get resolver for reverse record
            guard let resolver = try await getENSResolver(node: reverseNode) else {
                return nil
            }
            
            // Call name(bytes32) to get the name
            let data = "0x691f3431" + reverseNode.dropFirst(2)
            let result = try await ethCall(to: resolver, data: String(data), rpc: ethMainnetRPC)
            
            // Decode the name from the result
            let name = decodeABIString(result)
            return name
        } catch {
            return nil
        }
    }
    
    // MARK: - Helper Methods
    
    /// Make an eth_call JSON-RPC request
    private func ethCall(to: String, data: String, rpc: String) async throws -> String {
        guard let url = URL(string: rpc) else {
            throw ResolverError.invalidRPC
        }
        
        let payload: [String: Any] = [
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
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        if let error = response?["error"] as? [String: Any] {
            throw ResolverError.rpcError(error["message"] as? String ?? "Unknown error")
        }
        
        guard let result = response?["result"] as? String else {
            throw ResolverError.invalidResponse
        }
        
        return result
    }
    
    /// Decode ABI-encoded bytes from a hex string
    private func decodeABIBytes(_ hex: String) -> Data? {
        // ABI bytes encoding: offset (32 bytes) + length (32 bytes) + data (padded to 32 bytes)
        let clean = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        
        guard clean.count >= 128 else { return nil }
        
        // Get offset (first 32 bytes = 64 hex chars)
        let offsetHex = String(clean.prefix(64))
        guard let offset = UInt64(offsetHex, radix: 16) else { return nil }
        
        // Get length from offset position
        let lengthStart = Int(offset * 2)
        guard clean.count > lengthStart + 64 else { return nil }
        
        let lengthHex = String(clean.dropFirst(lengthStart).prefix(64))
        guard let length = UInt64(lengthHex, radix: 16) else { return nil }
        
        // Get actual data
        let dataStart = lengthStart + 64
        let dataEnd = dataStart + Int(length * 2)
        guard clean.count >= dataEnd else { return nil }
        
        let dataHex = String(clean.dropFirst(dataStart).prefix(Int(length * 2)))
        return Data(hex: dataHex)
    }
    
    /// Decode ABI-encoded string from a hex string
    private func decodeABIString(_ hex: String) -> String? {
        guard let data = decodeABIBytes(hex) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Cache Structure

private struct CachedResolution {
    let address: String
    let timestamp: Date
    
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > 3600 // 1 hour
    }
}

// MARK: - Errors

enum ResolverError: LocalizedError {
    case unsupportedDomain
    case noResolver
    case resolutionFailed
    case invalidRPC
    case invalidResponse
    case rpcError(String)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedDomain: return "Unsupported domain type"
        case .noResolver: return "No resolver found for this domain"
        case .resolutionFailed: return "Failed to resolve domain"
        case .invalidRPC: return "Invalid RPC endpoint"
        case .invalidResponse: return "Invalid response from resolver"
        case .rpcError(let message): return "RPC error: \(message)"
        }
    }
}

// Note: Data.hexString extension is defined in BitcoinTransaction.swift
