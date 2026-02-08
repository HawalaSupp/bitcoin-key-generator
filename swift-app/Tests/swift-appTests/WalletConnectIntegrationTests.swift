import Testing
import Foundation
@testable import swift_app

// MARK: - ROADMAP-09: WalletConnect & dApp Integration Tests

// =========================================================================
// MARK: - DAppAccessManager Tests
// =========================================================================

@Suite("DAppAccessManager")
struct DAppAccessManagerTests {
    
    @Test("Allowlist add and remove")
    @MainActor
    func allowlistAddRemove() {
        let manager = DAppAccessManager.shared
        let domain = "test-dapp-\(UUID().uuidString.prefix(8)).com"
        
        // Initially unknown
        let initial = manager.checkAccess(domain: domain)
        #expect(initial == .unknown, "New domain should be unknown")
        
        // Add to allowlist
        manager.addToAllowlist(domain: domain)
        let allowed = manager.checkAccess(domain: domain)
        #expect(allowed == .allowed, "Domain should be allowed after adding to allowlist")
        
        // Remove from allowlist
        manager.removeFromAllowlist(domain: domain)
        let removed = manager.checkAccess(domain: domain)
        #expect(removed == .unknown, "Domain should be unknown after removing from allowlist")
    }
    
    @Test("Blocklist add and remove")
    @MainActor
    func blocklistAddRemove() {
        let manager = DAppAccessManager.shared
        let domain = "blocked-dapp-\(UUID().uuidString.prefix(8)).com"
        
        // Add to blocklist
        manager.addToBlocklist(domain: domain)
        let blocked = manager.checkAccess(domain: domain)
        if case .blocked = blocked {
            // Expected
        } else {
            Issue.record("Domain should be blocked")
        }
        
        // Remove from blocklist
        manager.removeFromBlocklist(domain: domain)
        let removed = manager.checkAccess(domain: domain)
        #expect(removed == .unknown, "Domain should be unknown after removing from blocklist")
    }
    
    @Test("Blocklist overrides allowlist")
    @MainActor
    func blocklistOverridesAllowlist() {
        let manager = DAppAccessManager.shared
        let domain = "conflict-test-\(UUID().uuidString.prefix(8)).com"
        
        // Add to allowlist first
        manager.addToAllowlist(domain: domain)
        #expect(manager.checkAccess(domain: domain) == .allowed)
        
        // Add to blocklist — should override
        manager.addToBlocklist(domain: domain)
        if case .blocked = manager.checkAccess(domain: domain) {
            // Expected — blocklist should remove from allowlist
        } else {
            Issue.record("Blocklist should override allowlist")
        }
        
        // Clean up
        manager.removeFromBlocklist(domain: domain)
    }
    
    @Test("Built-in blocklist catches scam domains")
    @MainActor
    func builtInBlocklist() {
        let manager = DAppAccessManager.shared
        
        // Check known scam domains
        for scamDomain in DAppAccessManager.builtInBlocklist.prefix(3) {
            let decision = manager.checkAccess(domain: scamDomain)
            if case .blocked(let reason) = decision {
                #expect(reason.contains("scam"), "Built-in blocked domain should mention 'scam': \(reason)")
            } else {
                Issue.record("Built-in scam domain '\(scamDomain)' should be blocked, got: \(decision)")
            }
        }
    }
    
    @Test("Subdomain blocking propagates from parent")
    @MainActor
    func subdomainBlocking() {
        let manager = DAppAccessManager.shared
        let domain = "subdomain-test-\(UUID().uuidString.prefix(8)).com"
        
        manager.addToBlocklist(domain: domain)
        
        // Subdomain should also be blocked
        let subDecision = manager.checkAccess(domain: "app.\(domain)")
        if case .blocked = subDecision {
            // Expected
        } else {
            Issue.record("Subdomain of blocked domain should also be blocked")
        }
        
        // Clean up
        manager.removeFromBlocklist(domain: domain)
    }
    
    @Test("Domain normalization strips protocol, www, port, path")
    @MainActor
    func domainNormalization() {
        let manager = DAppAccessManager.shared
        
        // Test URL extraction
        #expect(manager.extractDomain(from: "https://app.uniswap.org/swap") == "app.uniswap.org")
        #expect(manager.extractDomain(from: "http://www.example.com:8080/path") == "example.com")
        
        // Normalize strips www, protocol, port
        #expect(manager.normalizeDomain("https://www.Example.COM:443/path") == "example.com")
        #expect(manager.normalizeDomain("WWW.Test.IO") == "test.io")
    }
    
    @Test("Peer check uses URL domain")
    @MainActor
    func peerCheck() {
        let manager = DAppAccessManager.shared
        let domain = "peer-test-\(UUID().uuidString.prefix(8)).com"
        
        let peer = WCPeer(
            publicKey: "abc123",
            name: "Test dApp",
            description: "A test",
            url: "https://\(domain)/app",
            icons: []
        )
        
        // Initially unknown
        #expect(manager.checkAccess(peer: peer) == .unknown)
        
        // Block it
        manager.addToBlocklist(domain: domain)
        if case .blocked = manager.checkAccess(peer: peer) {
            // Expected
        } else {
            Issue.record("Peer from blocked domain should be blocked")
        }
        
        // Clean up
        manager.removeFromBlocklist(domain: domain)
    }
    
    @Test("Clear operations reset lists")
    @MainActor
    func clearOperations() {
        let manager = DAppAccessManager.shared
        let d1 = "clear-test-1-\(UUID().uuidString.prefix(8)).com".lowercased()
        let d2 = "clear-test-2-\(UUID().uuidString.prefix(8)).com".lowercased()
        
        manager.addToAllowlist(domain: d1)
        manager.addToBlocklist(domain: d2)
        
        #expect(manager.allowedDomains.contains(d1))
        #expect(manager.blockedDomains.contains(d2))
        
        manager.clearAllowlist()
        #expect(!manager.allowedDomains.contains(d1), "Allowlist should be cleared")
        
        manager.clearBlocklist()
        #expect(!manager.blockedDomains.contains(d2), "Blocklist should be cleared")
    }
}

// =========================================================================
// MARK: - DAppRateLimiter Tests
// =========================================================================

@Suite("DAppRateLimiter")
struct DAppRateLimiterTests {
    
    @Test("Allows requests under limit")
    func allowsUnderLimit() async {
        let limiter = DAppRateLimiter(maxRequests: 5, windowSeconds: 60)
        let topic = "test-topic-1"
        
        // Should allow 5 requests
        for i in 1...5 {
            let allowed = await limiter.recordRequest(topic: topic)
            #expect(allowed, "Request \(i) should be allowed (under limit)")
        }
        
        // 6th should be blocked
        let blocked = await limiter.recordRequest(topic: topic)
        #expect(!blocked, "6th request should be rate limited")
    }
    
    @Test("Blocks requests over limit")
    func blocksOverLimit() async {
        let limiter = DAppRateLimiter(maxRequests: 3, windowSeconds: 60)
        let topic = "test-topic-2"
        
        // Exhaust the limit
        for _ in 1...3 {
            _ = await limiter.recordRequest(topic: topic)
        }
        
        // Should be blocked
        let shouldAllow = await limiter.shouldAllow(topic: topic)
        #expect(!shouldAllow, "Should not allow request over limit")
    }
    
    @Test("Tracks rate limits per topic independently")
    func tracksPerTopic() async {
        let limiter = DAppRateLimiter(maxRequests: 2, windowSeconds: 60)
        let topic1 = "dapp-A"
        let topic2 = "dapp-B"
        
        // Exhaust topic1
        _ = await limiter.recordRequest(topic: topic1)
        _ = await limiter.recordRequest(topic: topic1)
        let topic1Blocked = await limiter.shouldAllow(topic: topic1)
        #expect(!topic1Blocked, "Topic1 should be at limit")
        
        // Topic2 should still be allowed
        let topic2Allowed = await limiter.shouldAllow(topic: topic2)
        #expect(topic2Allowed, "Topic2 should still be allowed (separate rate limit)")
    }
    
    @Test("Request count and remaining are accurate")
    func requestCount() async {
        let limiter = DAppRateLimiter(maxRequests: 10, windowSeconds: 60)
        let topic = "count-topic"
        
        _ = await limiter.recordRequest(topic: topic)
        _ = await limiter.recordRequest(topic: topic)
        _ = await limiter.recordRequest(topic: topic)
        
        let count = await limiter.requestCount(for: topic)
        #expect(count == 3, "Should have recorded 3 requests")
        
        let remaining = await limiter.remainingRequests(for: topic)
        #expect(remaining == 7, "Should have 7 remaining requests")
    }
    
    @Test("Reset restores quota for topic")
    func reset() async {
        let limiter = DAppRateLimiter(maxRequests: 2, windowSeconds: 60)
        let topic = "reset-topic"
        
        _ = await limiter.recordRequest(topic: topic)
        _ = await limiter.recordRequest(topic: topic)
        
        #expect(!(await limiter.shouldAllow(topic: topic)))
        
        // Reset
        await limiter.reset(topic: topic)
        #expect(await limiter.shouldAllow(topic: topic), "Should allow after reset")
    }
    
    @Test("Statistics track active dApps and blocked requests")
    func statistics() async {
        let limiter = DAppRateLimiter(maxRequests: 1, windowSeconds: 60)
        
        _ = await limiter.recordRequest(topic: "t1")
        _ = await limiter.recordRequest(topic: "t1") // This should be blocked
        _ = await limiter.recordRequest(topic: "t2")
        
        let stats = await limiter.statistics
        #expect(stats.activeDApps == 2, "Should track 2 active dApps")
        #expect(stats.totalBlocked == 1, "Should have 1 blocked request")
    }
    
    @Test("Time until next slot is positive when at limit")
    func timeUntilNextSlot() async {
        let limiter = DAppRateLimiter(maxRequests: 1, windowSeconds: 60)
        let topic = "time-topic"
        
        _ = await limiter.recordRequest(topic: topic)
        
        let waitTime = await limiter.timeUntilNextSlot(for: topic)
        #expect(waitTime > 0, "Should have positive wait time when at limit")
        #expect(waitTime <= 60, "Wait time should not exceed window")
    }
    
    @Test("ResetAll clears all tracked topics")
    func resetAll() async {
        let limiter = DAppRateLimiter(maxRequests: 1, windowSeconds: 60)
        
        _ = await limiter.recordRequest(topic: "a")
        _ = await limiter.recordRequest(topic: "b")
        _ = await limiter.recordRequest(topic: "a") // blocked
        
        await limiter.resetAll()
        
        let stats = await limiter.statistics
        #expect(stats.activeDApps == 0)
        #expect(stats.totalBlocked == 0)
        
        // Should allow again
        #expect(await limiter.shouldAllow(topic: "a"))
    }
    
    @Test("Default shared config is 10 req/min")
    func defaultConfig() async {
        let limiter = DAppRateLimiter.shared
        let topic = "default-config-test"
        
        // Default is 10 req/min
        for i in 1...10 {
            let allowed = await limiter.recordRequest(topic: topic)
            #expect(allowed, "Request \(i) should be allowed within default limit")
        }
        
        let overLimit = await limiter.recordRequest(topic: topic)
        #expect(!overLimit, "11th request should exceed default 10/min limit")
        
        // Clean up
        await limiter.reset(topic: topic)
    }
}

// =========================================================================
// MARK: - DAppRegistry Tests
// =========================================================================

@Suite("DAppRegistry")
struct DAppRegistryTests {
    
    @Test("Verifies known dApps: Uniswap, OpenSea, Aave")
    @MainActor
    func verifiesKnownDApps() {
        let registry = DAppRegistry.shared
        
        // Uniswap
        let uniswap = registry.verify(url: "https://app.uniswap.org/swap")
        if case .verified(let info) = uniswap {
            #expect(info.name == "Uniswap")
            #expect(info.category == .dex)
        } else {
            Issue.record("app.uniswap.org should be verified")
        }
        
        // OpenSea
        let opensea = registry.verify(url: "https://opensea.io/assets")
        if case .verified(let info) = opensea {
            #expect(info.name == "OpenSea")
            #expect(info.category == .nftMarketplace)
        } else {
            Issue.record("opensea.io should be verified")
        }
        
        // Aave
        let aave = registry.verify(url: "https://app.aave.com")
        if case .verified(let info) = aave {
            #expect(info.name == "Aave")
            #expect(info.category == .lending)
        } else {
            Issue.record("app.aave.com should be verified")
        }
    }
    
    @Test("Detects suspicious domains (airdrop, impersonation)")
    @MainActor
    func detectsSuspiciousDomains() {
        let registry = DAppRegistry.shared
        
        let phishing = registry.verify(url: "https://uniswap-airdrop.xyz")
        if case .suspicious(let reason) = phishing {
            #expect(reason.lowercased().contains("airdrop") || reason.lowercased().contains("impersonat") || reason.lowercased().contains("uniswap"),
                    "Should detect suspicious pattern: \(reason)")
        } else {
            Issue.record("Domain with 'airdrop' should be suspicious, got: \(phishing)")
        }
        
        let fakeWallet = registry.verify(url: "https://metamask-verify.xyz")
        if case .suspicious(let reason) = fakeWallet {
            #expect(reason.lowercased().contains("metamask") || reason.lowercased().contains("impersonat"),
                    "Should detect MetaMask impersonation: \(reason)")
        } else {
            Issue.record("metamask-verify.xyz should be suspicious, got: \(fakeWallet)")
        }
    }
    
    @Test("Returns unknown for unregistered domains")
    @MainActor
    func returnsUnknownForNewDomains() {
        let registry = DAppRegistry.shared
        
        let unknown = registry.verify(url: "https://some-random-new-dapp-\(UUID().uuidString.prefix(8)).com")
        #expect(unknown == .unknown, "Unknown domain should return .unknown")
    }
    
    @Test("Subdomain verification inherits from parent")
    @MainActor
    func verifiesSubdomains() {
        let registry = DAppRegistry.shared
        
        // "v2.app.uniswap.org" should match "app.uniswap.org"
        let subdomain = registry.verify(domain: "v2.app.uniswap.org")
        if case .verified(let info) = subdomain {
            #expect(info.name == "Uniswap")
        } else {
            Issue.record("Subdomain of verified dApp should also be verified")
        }
    }
    
    @Test("Verifies peer by URL")
    @MainActor
    func verifiesPeer() {
        let registry = DAppRegistry.shared
        
        let peer = WCPeer(
            publicKey: "abc",
            name: "Uniswap",
            description: "DEX",
            url: "https://app.uniswap.org",
            icons: []
        )
        
        let result = registry.verify(peer: peer)
        if case .verified(let info) = result {
            #expect(info.name == "Uniswap")
        } else {
            Issue.record("Peer with uniswap URL should be verified")
        }
    }
    
    @Test("Category search returns correct dApp counts")
    @MainActor
    func categorySearch() {
        let registry = DAppRegistry.shared
        
        let dexes = registry.dApps(in: .dex)
        #expect(dexes.count >= 3, "Should have at least 3 DEXes in registry")
        
        let lending = registry.dApps(in: .lending)
        #expect(lending.count >= 2, "Should have at least 2 lending protocols")
    }
    
    @Test("Name search finds exact match")
    @MainActor
    func nameSearch() {
        let registry = DAppRegistry.shared
        
        let results = registry.search(query: "uniswap")
        #expect(results.count == 1, "Should find exactly 1 Uniswap")
        #expect(results.first?.name == "Uniswap")
    }
    
    @Test("All categories have icons")
    @MainActor
    func allCategoriesHaveIcons() {
        for category in DAppRegistry.DAppCategory.allCases {
            #expect(!category.icon.isEmpty, "Category \(category.rawValue) should have an icon")
        }
    }
    
    @Test("All verified dApps have valid domains and chain IDs")
    @MainActor
    func verifiedDAppsHaveValidData() {
        for dapp in DAppRegistry.verifiedDApps {
            #expect(!dapp.name.isEmpty, "dApp should have a name")
            #expect(!dapp.verifiedDomains.isEmpty, "dApp \(dapp.name) should have verified domains")
            #expect(!dapp.chainIds.isEmpty, "dApp \(dapp.name) should have chain IDs")
            
            for domain in dapp.verifiedDomains {
                #expect(!domain.isEmpty, "Domain for \(dapp.name) should not be empty")
                #expect(!domain.contains("https://"), "Domain should not contain protocol prefix")
            }
        }
    }
}

// =========================================================================
// MARK: - TransactionDecoder Tests
// =========================================================================

@Suite("TransactionDecoder")
struct TransactionDecoderTests {
    
    @Test("Decodes ERC-20 transfer with USDC contract")
    @MainActor
    func erc20Transfer() {
        let decoder = TransactionDecoder.shared
        
        // transfer(address, uint256)
        // Selector: a9059cbb
        let data = "0xa9059cbb000000000000000000000000742d35cc6634c0532925a3b844bc9e7595f2b4f600000000000000000000000000000000000000000000000000000000000f4240"
        let to = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48" // USDC
        
        let decoded = decoder.decode(data: data, to: to, value: "0")
        
        #expect(decoded.methodName == "transfer", "Should decode ERC-20 transfer")
        #expect(decoded.humanReadable.lowercased().contains("transfer"), "Human-readable should mention transfer")
        #expect(decoded.contractName == "USDC", "Should identify USDC contract")
    }
    
    @Test("Decodes unlimited ERC-20 approval with warning")
    @MainActor
    func erc20Approve() {
        let decoder = TransactionDecoder.shared
        
        // approve(address, uint256) with unlimited amount
        let data = "0x095ea7b3000000000000000000000000def1c0ded9bec7f1a1670819833240f027b25effffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
        let to = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48" // USDC
        
        let decoded = decoder.decode(data: data, to: to, value: "0")
        
        #expect(decoded.methodName == "approve", "Should decode approve")
        #expect(decoded.warnings.contains(.unlimitedApproval), "Should warn about unlimited approval")
        #expect(decoded.methodDescription == "Approve token spending")
    }
    
    @Test("Handles unknown method selector gracefully")
    @MainActor
    func unknownMethod() {
        let decoder = TransactionDecoder.shared
        
        // Random unknown selector
        let data = "0xdeadbeef0000000000000000000000000000000000000000000000000000000000000001"
        
        let decoded = decoder.decode(data: data, to: "0x1234567890123456789012345678901234567890", value: "0")
        
        #expect(decoded.methodName == "Unknown Method", "Should handle unknown selector")
    }
    
    @Test("Identifies known contracts (WETH deposit)")
    @MainActor
    func knownContracts() {
        let decoder = TransactionDecoder.shared
        
        // WETH deposit
        let decoded = decoder.decode(data: "0xd0e30db0", to: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", value: "1000000000000000000")
        
        #expect(decoded.methodName == "deposit", "Should decode WETH deposit")
        #expect(decoded.contractName == "WETH", "Should identify WETH contract")
    }
    
    @Test("Native transfer has nativeValue set")
    @MainActor
    func nativeTransfer() {
        let decoder = TransactionDecoder.shared
        
        // Simple ETH transfer (empty data), value in hex (1 ETH = 0xDE0B6B3A7640000)
        let decoded = decoder.decode(data: "0x", to: "0x742d35Cc6634C0532925a3b844Bc9e7595f2b4F6", value: "0xDE0B6B3A7640000")
        
        #expect(decoded.nativeValue != nil, "Should have native value for ETH transfer")
    }
    
    @Test("Unlimited approval is medium+ risk")
    @MainActor
    func riskLevels() {
        let decoder = TransactionDecoder.shared
        
        // Unlimited approval = at least medium risk
        let data = "0x095ea7b3000000000000000000000000def1c0ded9bec7f1a1670819833240f027b25effffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
        let decoded = decoder.decode(data: data, to: "0x1234567890123456789012345678901234567890", value: "0")
        
        let risk: TxRiskLevel = decoded.riskLevel
        #expect(risk == .medium || risk == .high || risk == .critical,
                "Unlimited approval should be medium+ risk, got: \(risk)")
    }
}

// =========================================================================
// MARK: - EIP-712 Type Parsing Tests
// =========================================================================

@Suite("EIP-712 Parsing")
struct EIP712ParsingTests {
    
    @Test("Parses typed data JSON with domain, types, message")
    func typedDataFromJSON() throws {
        let json = """
        {
            "types": {
                "EIP712Domain": [
                    {"name": "name", "type": "string"},
                    {"name": "version", "type": "string"},
                    {"name": "chainId", "type": "uint256"},
                    {"name": "verifyingContract", "type": "address"}
                ],
                "Person": [
                    {"name": "name", "type": "string"},
                    {"name": "wallet", "type": "address"}
                ]
            },
            "primaryType": "Person",
            "domain": {
                "name": "Test",
                "version": "1",
                "chainId": 1,
                "verifyingContract": "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC"
            },
            "message": {
                "name": "Bob",
                "wallet": "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB"
            }
        }
        """
        
        let typedData = try EIP712TypedData.fromJSON(json)
        
        #expect(typedData.primaryType == "Person")
        #expect(typedData.domain.name == "Test")
        #expect(typedData.domain.version == "1")
        
        if case .number(let chainId) = typedData.domain.chainId {
            #expect(chainId == 1)
        } else {
            Issue.record("Chain ID should be number 1")
        }
        
        #expect(typedData.domain.verifyingContract == "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC")
        #expect(typedData.types.count == 2, "Should have EIP712Domain and Person types")
        #expect(typedData.message.count == 2, "Should have name and wallet in message")
    }
    
    @Test("Round-trip encode/decode preserves data")
    func roundTrip() throws {
        let json = """
        {
            "types": {
                "EIP712Domain": [
                    {"name": "name", "type": "string"}
                ],
                "Mail": [
                    {"name": "from", "type": "string"},
                    {"name": "to", "type": "string"},
                    {"name": "contents", "type": "string"}
                ]
            },
            "primaryType": "Mail",
            "domain": {"name": "Test"},
            "message": {"from": "Alice", "to": "Bob", "contents": "Hello"}
        }
        """
        
        let typedData = try EIP712TypedData.fromJSON(json)
        let reEncoded = try typedData.toJSON()
        let reparsed = try EIP712TypedData.fromJSON(reEncoded)
        
        #expect(typedData.primaryType == reparsed.primaryType)
        #expect(typedData.domain.name == reparsed.domain.name)
        #expect(typedData.types.count == reparsed.types.count)
    }
    
    @Test("Decodes numeric and string chain IDs")
    func chainIdDecoding() throws {
        // Number chain ID
        let json1 = """
        {"types":{"EIP712Domain":[{"name":"chainId","type":"uint256"}]},"primaryType":"EIP712Domain","domain":{"chainId":137},"message":{}}
        """
        let data1 = try EIP712TypedData.fromJSON(json1)
        if case .number(let n) = data1.domain.chainId {
            #expect(n == 137)
        } else {
            Issue.record("Should decode numeric chainId")
        }
        
        // String chain ID
        let json2 = """
        {"types":{"EIP712Domain":[{"name":"chainId","type":"uint256"}]},"primaryType":"EIP712Domain","domain":{"chainId":"0x89"},"message":{}}
        """
        let data2 = try EIP712TypedData.fromJSON(json2)
        if case .string(let s) = data2.domain.chainId {
            #expect(s == "0x89")
        } else {
            Issue.record("Should decode string chainId")
        }
    }
    
    @Test("EIP712Signature from valid 65-byte hex")
    func signatureFromHex() throws {
        // Create a valid 65-byte hex signature
        let r = String(repeating: "ab", count: 32)
        let s = String(repeating: "cd", count: 32)
        let v = "1b" // 27
        let hexSig = "0x" + r + s + v
        
        let sig = try EIP712Signature(hexSignature: hexSig)
        #expect(sig.r.count == 32, "r should be 32 bytes")
        #expect(sig.s.count == 32, "s should be 32 bytes")
        #expect(sig.v == 27, "v should be 27")
        #expect(sig.rawSignature.count == 65, "Raw signature should be 65 bytes")
    }
    
    @Test("Invalid hex length throws EIP712Error")
    func signatureInvalidLength() {
        #expect(throws: EIP712Error.self) {
            try EIP712Signature(hexSignature: "0xabcdef")
        }
    }
    
    @Test("Invalid JSON throws decoding error")
    func invalidJSON() {
        #expect(throws: (any Error).self) {
            try EIP712TypedData.fromJSON("not json")
        }
    }
}

// =========================================================================
// MARK: - WalletConnectSigningService Tests
// =========================================================================

@Suite("WalletConnectSigningService")
struct WalletConnectSigningServiceTests {
    
    @Test("Personal sign request routes to signing")
    @MainActor
    func personalSign() async throws {
        let service = WalletConnectSigningService.shared
        
        // personal_sign expects [address, message]
        let message = "0x48656c6c6f" // "Hello" in hex
        let request = WCSessionRequest(
            id: 1,
            topic: "test",
            chainId: "eip155:1",
            method: "personal_sign",
            params: ["0x742d35Cc6634C0532925a3b844Bc9e7595f2b4F6", message]
        )
        
        // This will fail without real keys, but should at least not crash
        do {
            let _ = try await service.handleSign(request, keys: makeTestKeys())
            // If keys are empty, should throw
        } catch {
            // Expected — empty keys
            #expect(error is WCError, "Should throw WCError for empty keys")
        }
    }
    
    @Test("Typed data request routes through EIP-712")
    @MainActor
    func typedDataRouting() async throws {
        let service = WalletConnectSigningService.shared
        
        let typedDataJSON = """
        {"types":{"EIP712Domain":[{"name":"name","type":"string"}],"Test":[{"name":"value","type":"uint256"}]},"primaryType":"Test","domain":{"name":"Test"},"message":{"value":"42"}}
        """
        
        let request = WCSessionRequest(
            id: 2,
            topic: "test",
            chainId: "eip155:1",
            method: "eth_signTypedData_v4",
            params: ["0x742d35Cc6634C0532925a3b844Bc9e7595f2b4F6", typedDataJSON]
        )
        
        do {
            let _ = try await service.handleSign(request, keys: makeTestKeys())
        } catch {
            // Expected — empty keys, but should route correctly
            #expect(error is WCError || error is EIP712Error,
                    "Should throw WCError or EIP712Error, got \(type(of: error))")
        }
    }
    
    @Test("Transaction signing rejects with userRejected")
    @MainActor
    func transactionRejects() async throws {
        let service = WalletConnectSigningService.shared
        
        let request = WCSessionRequest(
            id: 3,
            topic: "test",
            chainId: "eip155:1",
            method: "eth_sendTransaction",
            params: [["from": "0x123", "to": "0x456", "value": "0x0"]]
        )
        
        do {
            let _ = try await service.handleSign(request, keys: makeTestKeys())
            Issue.record("Transaction signing should throw")
        } catch let error as WCError {
            #expect(error == .userRejected, "Transaction signing should reject")
        }
    }
    
    @Test("Unknown method rejects with userRejected")
    @MainActor
    func unknownMethodRejects() async throws {
        let service = WalletConnectSigningService.shared
        
        let request = WCSessionRequest(
            id: 4,
            topic: "test",
            chainId: "eip155:1",
            method: "unknown_method",
            params: nil
        )
        
        do {
            let _ = try await service.handleSign(request, keys: makeTestKeys())
            Issue.record("Unknown method should throw")
        } catch let error as WCError {
            #expect(error == .userRejected)
        }
    }
    
    @Test("EVM accounts generated in CAIP-10 format")
    @MainActor
    func evmAccounts() {
        let service = WalletConnectSigningService.shared
        let keys = makeTestKeysWithAddress("0xABCDEF1234567890abcdef1234567890ABCDEF12")
        
        let accounts = service.evmAccounts(from: keys)
        
        // Should have Ethereum + Sepolia + BNB + Polygon + Arbitrum + Optimism + Avalanche
        #expect(accounts.count >= 5, "Should generate accounts for multiple EVM chains")
        
        // Check CAIP-10 format
        for account in accounts {
            #expect(account.hasPrefix("eip155:"), "Account should be in CAIP-10 format: \(account)")
            let parts = account.split(separator: ":")
            #expect(parts.count == 3, "CAIP-10 should have 3 parts: \(account)")
        }
    }
}

// =========================================================================
// MARK: - WalletConnect Model Tests
// =========================================================================

@Suite("WalletConnect Models")
struct WalletConnectModelTests {
    
    @Test("Method display names are human-readable")
    func methodDisplay() {
        let sendTx = WCSessionRequest(id: 1, topic: "t", chainId: "eip155:1", method: "eth_sendTransaction", params: nil)
        #expect(sendTx.methodDisplay == "Send Transaction")
        
        let signTx = WCSessionRequest(id: 2, topic: "t", chainId: "eip155:1", method: "eth_signTransaction", params: nil)
        #expect(signTx.methodDisplay == "Sign Transaction")
        
        let personalSign = WCSessionRequest(id: 3, topic: "t", chainId: "eip155:1", method: "personal_sign", params: nil)
        #expect(personalSign.methodDisplay == "Sign Message")
        
        let typedV4 = WCSessionRequest(id: 4, topic: "t", chainId: "eip155:1", method: "eth_signTypedData_v4", params: nil)
        #expect(typedV4.methodDisplay == "Sign Typed Data")
    }
    
    @Test("WCSession encodes and decodes via JSON")
    func sessionCodable() throws {
        let session = WCSession(
            topic: "test-topic-123",
            pairingTopic: "pairing-456",
            peer: WCPeer(publicKey: "pk", name: "Test dApp", description: "Test", url: "https://test.com", icons: ["https://test.com/icon.png"]),
            namespaces: ["eip155": WCSessionNamespace(accounts: ["eip155:1:0xABC"], methods: ["personal_sign"], events: ["accountsChanged"], chains: ["eip155:1"])],
            expiry: Date().addingTimeInterval(86400),
            acknowledged: true
        )
        
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(WCSession.self, from: data)
        
        #expect(decoded.topic == session.topic)
        #expect(decoded.peer.name == "Test dApp")
        #expect(decoded.peer.url == "https://test.com")
        #expect(decoded.namespaces.count == 1)
    }
    
    @Test("WCPeer iconURL returns first icon")
    func peerIconURL() {
        let peer = WCPeer(
            publicKey: "pk",
            name: "Test",
            description: "Test",
            url: "https://test.com",
            icons: ["https://test.com/icon.png", "https://test.com/icon2.png"]
        )
        
        #expect(peer.iconURL == URL(string: "https://test.com/icon.png"))
        
        let noIcons = WCPeer(publicKey: "pk", name: "Test", description: "Test", url: "https://test.com", icons: [])
        #expect(noIcons.iconURL == nil)
    }
    
    @Test("WCSession chains and accounts extracted from namespaces")
    func sessionChains() {
        let session = WCSession(
            topic: "t",
            pairingTopic: "p",
            peer: WCPeer(publicKey: "", name: "", description: "", url: "", icons: []),
            namespaces: [
                "eip155": WCSessionNamespace(
                    accounts: ["eip155:1:0xABC", "eip155:137:0xABC"],
                    methods: [],
                    events: [],
                    chains: ["eip155:1", "eip155:137"]
                )
            ],
            expiry: Date(),
            acknowledged: true
        )
        
        #expect(session.chains.contains("eip155:1"))
        #expect(session.chains.contains("eip155:137"))
        #expect(session.accounts.contains("eip155:1:0xABC"))
    }
    
    @Test("WCError has descriptions for all cases")
    func errorDescriptions() {
        let errors: [WCError] = [.invalidURI, .invalidRelayURL, .connectionFailed, .sessionNotFound, .noAccountsProvided, .requestTimeout, .userRejected]
        
        for error in errors {
            #expect(error.errorDescription != nil, "WCError.\(error) should have a description")
            #expect(!error.errorDescription!.isEmpty)
        }
    }
    
    @Test("Supported chains include major EVM networks")
    @MainActor
    func supportedChains() {
        #expect(WalletConnectService.supportedChains.count >= 7)
        
        let chainIds = WalletConnectService.supportedChains.map { $0.id }
        #expect(chainIds.contains("eip155:1"), "Should support Ethereum mainnet")
        #expect(chainIds.contains("eip155:11155111"), "Should support Sepolia")
        #expect(chainIds.contains("eip155:56"), "Should support BSC")
    }
    
    @Test("Supported methods include signing operations")
    @MainActor
    func supportedMethods() {
        #expect(WalletConnectService.supportedMethods.contains("eth_sendTransaction"))
        #expect(WalletConnectService.supportedMethods.contains("personal_sign"))
        #expect(WalletConnectService.supportedMethods.contains("eth_signTypedData_v4"))
    }
}

// =========================================================================
// MARK: - EIP-712 Error Tests
// =========================================================================

@Suite("EIP-712 Errors")
struct EIP712ErrorTests {
    
    @Test("All error cases include descriptive messages")
    func errorDescriptions() {
        let errors: [EIP712Error] = [
            .invalidJSON("test"),
            .invalidType("test"),
            .missingField("test"),
            .invalidSignature("test"),
            .signingFailed("test"),
            .verificationFailed("test"),
            .rustError("test"),
        ]
        
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(error.errorDescription!.contains("test"))
        }
    }
}

// =========================================================================
// MARK: - AnyCodable Tests
// =========================================================================

@Suite("AnyCodable")
struct AnyCodableTests {
    
    @Test("Encodes and decodes basic types")
    func encodeDecode() throws {
        let dict: [String: AnyCodable] = [
            "string": AnyCodable("hello"),
            "int": AnyCodable(42),
            "bool": AnyCodable(true),
            "double": AnyCodable(3.14),
        ]
        
        let data = try JSONEncoder().encode(dict)
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: data)
        
        #expect(decoded["string"]?.value as? String == "hello")
        #expect(decoded["int"]?.value as? Int == 42)
        #expect(decoded["bool"]?.value as? Bool == true)
    }
    
    @Test("Handles nested arrays and dictionaries")
    func nestedStructures() throws {
        let json = """
        {"array": [1, 2, 3], "nested": {"key": "value"}}
        """.data(using: .utf8)!
        
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: json)
        
        if let array = decoded["array"]?.value as? [Any] {
            #expect(array.count == 3)
        } else {
            Issue.record("Should decode array")
        }
        
        if let nested = decoded["nested"]?.value as? [String: Any] {
            #expect(nested["key"] as? String == "value")
        } else {
            Issue.record("Should decode nested dict")
        }
    }
}

// =========================================================================
// MARK: - Integration: Access + Registry + Rate Limiting
// =========================================================================

@Suite("ROADMAP-09 Integration")
struct Roadmap09IntegrationTests {
    
    @Test("Access manager + registry work together")
    @MainActor
    func accessAndRegistryIntegration() {
        let accessManager = DAppAccessManager.shared
        let registry = DAppRegistry.shared
        
        // Verified dApp should be verifiable
        let uniswapVerification = registry.verify(url: "https://app.uniswap.org")
        if case .verified = uniswapVerification {
            // Can add to allowlist
            accessManager.addToAllowlist(domain: "app.uniswap.org")
            #expect(accessManager.checkAccess(domain: "app.uniswap.org") == .allowed)
        }
        
        // Clean up
        accessManager.removeFromAllowlist(domain: "app.uniswap.org")
    }
    
    @Test("Rate limiter handles multiple dApps independently")
    func rateLimiterMultiDApp() async {
        let limiter = DAppRateLimiter(maxRequests: 3, windowSeconds: 60)
        
        // Simulate requests from 3 different dApps
        for i in 1...3 {
            let topic = "dapp-\(i)"
            for _ in 1...3 {
                let allowed = await limiter.recordRequest(topic: topic)
                #expect(allowed)
            }
            // 4th request from each should be blocked
            let blocked = await limiter.recordRequest(topic: topic)
            #expect(!blocked, "4th request from dapp-\(i) should be blocked")
        }
        
        let stats = await limiter.statistics
        #expect(stats.activeDApps == 3)
        #expect(stats.totalBlocked == 3) // One blocked per dApp
    }
}

// =========================================================================
// MARK: - Test Helpers
// =========================================================================

private func makeTestKeys() -> AllKeys {
    return makeTestKeysWithAddress("")
}

private func makeTestKeysWithAddress(_ ethAddress: String) -> AllKeys {
    // AllKeys has many nested types with custom CodingKeys — construct from JSON
    let json = """
    {
        "bitcoin": {"private_hex":"","private_wif":"","public_compressed_hex":"","address":"","taproot_address":null,"x_only_pubkey":null},
        "bitcoin_testnet": {"private_hex":"","private_wif":"","public_compressed_hex":"","address":"","taproot_address":null,"x_only_pubkey":null},
        "litecoin": {"private_hex":"","private_wif":"","public_compressed_hex":"","address":""},
        "monero": {"private_spend_hex":"","private_view_hex":"","public_spend_hex":"","public_view_hex":"","address":""},
        "solana": {"private_seed_hex":"","private_key_base58":"","public_key_base58":""},
        "ethereum": {"private_hex":"","public_uncompressed_hex":"","address":"\(ethAddress)"},
        "ethereum_sepolia": {"private_hex":"","public_uncompressed_hex":"","address":""},
        "bnb": {"private_hex":"","public_uncompressed_hex":"","address":""},
        "xrp": {"private_hex":"","public_compressed_hex":"","classic_address":""},
        "ton": {"private_hex":"","public_hex":"","address":""},
        "aptos": {"private_hex":"","public_hex":"","address":""},
        "sui": {"private_hex":"","public_hex":"","address":""},
        "polkadot": {"private_hex":"","public_hex":"","address":"","kusama_address":""},
        "dogecoin": {"private_hex":"","private_wif":"","public_compressed_hex":"","address":""},
        "bitcoin_cash": {"private_hex":"","private_wif":"","public_compressed_hex":"","legacy_address":"","cash_address":""},
        "cosmos": {"private_hex":"","public_hex":"","cosmos_address":"","osmosis_address":"","celestia_address":"","dydx_address":"","injective_address":"","sei_address":"","akash_address":"","kujira_address":"","stride_address":"","secret_address":"","stargaze_address":"","juno_address":"","terra_address":"","neutron_address":"","noble_address":"","axelar_address":"","fetch_address":"","persistence_address":"","sommelier_address":""},
        "cardano": {"private_hex":"","public_hex":"","address":""},
        "tron": {"private_hex":"","public_hex":"","address":""},
        "algorand": {"private_hex":"","public_hex":"","address":""},
        "stellar": {"private_hex":"","secret_key":"","public_hex":"","address":""},
        "near": {"private_hex":"","public_hex":"","implicit_address":""},
        "tezos": {"private_hex":"","secret_key":"","public_hex":"","public_key":"","address":""},
        "hedera": {"private_hex":"","public_hex":"","public_key_der":""},
        "zcash": {"private_hex":"","private_wif":"","public_compressed_hex":"","transparent_address":""},
        "dash": {"private_hex":"","private_wif":"","public_compressed_hex":"","address":""},
        "ravencoin": {"private_hex":"","private_wif":"","public_compressed_hex":"","address":""},
        "vechain": {"private_hex":"","public_hex":"","address":""},
        "filecoin": {"private_hex":"","public_hex":"","address":""},
        "harmony": {"private_hex":"","public_hex":"","address":"","bech32_address":""},
        "oasis": {"private_hex":"","public_hex":"","address":""},
        "internet_computer": {"private_hex":"","public_hex":"","principal_id":"","account_id":""},
        "waves": {"private_hex":"","public_hex":"","address":""},
        "multiversx": {"private_hex":"","public_hex":"","address":""},
        "flow": {"private_hex":"","public_hex":"","address":""},
        "mina": {"private_hex":"","public_hex":"","address":""},
        "zilliqa": {"private_hex":"","public_hex":"","address":"","bech32_address":""},
        "eos": {"private_hex":"","public_hex":"","public_key":""},
        "neo": {"private_hex":"","public_hex":"","address":""},
        "nervos": {"private_hex":"","public_hex":"","address":""}
    }
    """
    return try! JSONDecoder().decode(AllKeys.self, from: json.data(using: .utf8)!)
}
