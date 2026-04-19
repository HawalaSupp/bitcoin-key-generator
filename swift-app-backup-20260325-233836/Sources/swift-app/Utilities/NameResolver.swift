import Foundation

/// Resolves human-readable names (ENS, SNS) to blockchain addresses
actor NameResolver {
    static let shared = NameResolver()
    
    private init() {}
    
    // MARK: - ENS Resolution (Ethereum Name Service)
    
    /// Resolves an ENS name (e.g., "vitalik.eth") to an Ethereum address
    /// Uses the ENS public resolver via eth_call
    func resolveENS(_ name: String) async throws -> String {
        guard name.lowercased().hasSuffix(".eth") else {
            throw NameResolverError.invalidName("Not a valid ENS name")
        }
        
        // Normalize the name
        let normalizedName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Use ENS Ideas API for simple resolution
        let encodedName = normalizedName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? normalizedName
        guard let ensAPIURL = URL(string: "https://api.ensideas.com/ens/resolve/\(encodedName)") else {
            throw NameResolverError.invalidName("Could not create resolution URL")
        }
        
        var request = URLRequest(url: ensAPIURL)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NameResolverError.networkError("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw NameResolverError.nameNotFound("ENS name not found")
            }
            throw NameResolverError.networkError("HTTP \(httpResponse.statusCode)")
        }
        
        // Parse the response
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = json as? [String: Any],
              let address = dict["address"] as? String,
              !address.isEmpty,
              address != "0x0000000000000000000000000000000000000000" else {
            throw NameResolverError.nameNotFound("No address set for this ENS name")
        }
        
        return address
    }
    
    // MARK: - SNS Resolution (Solana Name Service)
    
    /// Resolves an SNS name (e.g., "example.sol") to a Solana address
    func resolveSNS(_ name: String) async throws -> String {
        guard name.lowercased().hasSuffix(".sol") else {
            throw NameResolverError.invalidName("Not a valid SNS name")
        }
        
        // Normalize the name (remove .sol suffix for API)
        let normalizedName = name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".sol", with: "")
        
        // Use SNS SDK API endpoint
        guard let url = URL(string: "https://sns-api.bonfida.com/v2/resolve/\(normalizedName)") else {
            throw NameResolverError.invalidName("Could not create resolution URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("HawalaApp/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NameResolverError.networkError("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw NameResolverError.nameNotFound("SNS name not found")
            }
            throw NameResolverError.networkError("HTTP \(httpResponse.statusCode)")
        }
        
        // Parse the response
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = json as? [String: Any],
              let result = dict["result"] as? String,
              !result.isEmpty else {
            throw NameResolverError.nameNotFound("No address set for this SNS name")
        }
        
        return result
    }
    
    // MARK: - Unified Resolution
    
    /// Resolves any supported name format to an address
    func resolve(_ name: String) async throws -> ResolvedName {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        if trimmed.hasSuffix(".eth") {
            let address = try await resolveENS(trimmed)
            return ResolvedName(originalName: name, resolvedAddress: address, service: .ens)
        } else if trimmed.hasSuffix(".sol") {
            let address = try await resolveSNS(trimmed)
            return ResolvedName(originalName: name, resolvedAddress: address, service: .sns)
        } else {
            throw NameResolverError.unsupportedFormat("Only .eth and .sol names are supported")
        }
    }
    
    /// Checks if a string looks like a resolvable name
    static func isResolvableName(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasSuffix(".eth") || trimmed.hasSuffix(".sol")
    }
    
    /// Returns the name service type for a given input
    static func nameServiceType(for input: String) -> NameService? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasSuffix(".eth") { return .ens }
        if trimmed.hasSuffix(".sol") { return .sns }
        return nil
    }
}

// MARK: - Supporting Types

struct ResolvedName {
    let originalName: String
    let resolvedAddress: String
    let service: NameService
}

enum NameService: String {
    case ens = "ENS"
    case sns = "SNS"
    
    var displayName: String {
        switch self {
        case .ens: return "Ethereum Name Service"
        case .sns: return "Solana Name Service"
        }
    }
}

enum NameResolverError: LocalizedError {
    case invalidName(String)
    case nameNotFound(String)
    case networkError(String)
    case unsupportedFormat(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidName(let msg): return "Invalid name: \(msg)"
        case .nameNotFound(let msg): return msg
        case .networkError(let msg): return "Network error: \(msg)"
        case .unsupportedFormat(let msg): return msg
        }
    }
}
