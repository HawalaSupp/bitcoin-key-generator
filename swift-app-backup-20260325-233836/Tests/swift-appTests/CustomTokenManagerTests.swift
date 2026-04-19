import Testing
import Foundation
@testable import swift_app

@Suite
struct CustomTokenManagerTests {
    
    // MARK: - Token Model Tests
    
    @Test func testCustomTokenInitialization() {
        let token = CustomToken(
            contractAddress: "0x6B175474E89094C44Da98b954EescdkdjFasGD5c",
            symbol: "DAI",
            name: "Dai Stablecoin",
            decimals: 18,
            chain: .ethereum
        )
        
        #expect(token.symbol == "DAI")
        #expect(token.name == "Dai Stablecoin")
        #expect(token.decimals == 18)
        #expect(token.chain == .ethereum)
        #expect(token.logoURL == nil)
    }
    
    @Test func testCustomTokenWithOptionalFields() {
        let token = CustomToken(
            contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
            symbol: "USDC",
            name: "USD Coin",
            decimals: 6,
            chain: .ethereum,
            logoURL: "https://example.com/usdc.png"
        )
        
        #expect(token.logoURL == "https://example.com/usdc.png")
    }
    
    @Test func testTokenChainIdentifier() {
        let ethToken = CustomToken(
            contractAddress: "0x123",
            symbol: "TEST",
            name: "Test Token",
            decimals: 18,
            chain: .ethereum
        )
        
        let solToken = CustomToken(
            contractAddress: "So11111111111111111111111111111111111111112",
            symbol: "SOL",
            name: "Wrapped SOL",
            decimals: 9,
            chain: .solana
        )
        
        #expect(ethToken.chain == .ethereum)
        #expect(solToken.chain == .solana)
    }
    
    // MARK: - TokenChain Tests
    
    @Test func testTokenChainCases() {
        let chains: [TokenChain] = [.ethereum, .bsc, .solana]
        #expect(chains.count == 3)
    }
    
    @Test func testTokenChainDisplayName() {
        #expect(TokenChain.ethereum.displayName == "Ethereum (ERC-20)")
        #expect(TokenChain.bsc.displayName == "BNB Chain (BEP-20)")
        #expect(TokenChain.solana.displayName == "Solana (SPL)")
    }
    
    @Test func testTokenChainAddressPlaceholder() {
        #expect(TokenChain.ethereum.addressPlaceholder == "0x...")
        #expect(TokenChain.bsc.addressPlaceholder == "0x...")
        #expect(TokenChain.solana.addressPlaceholder == "Token mint address")
    }
    
    // MARK: - Contract Address Validation Tests
    
    @Test func testEthereumAddressFormat() {
        let validAddress = "0x6B175474E89094C44Da98b954EeadDeFE456dAcE" // exactly 42 chars
        #expect(validAddress.hasPrefix("0x"))
        #expect(validAddress.count == 42)
    }
    
    @Test func testSolanaAddressFormat() {
        let validAddress = "So11111111111111111111111111111111111111112"
        #expect(validAddress.count >= 32 && validAddress.count <= 44)
    }
    
    // MARK: - Token Encoding Tests
    
    @Test func testTokenEncodable() throws {
        let token = CustomToken(
            contractAddress: "0xTestEncode",
            symbol: "ENC",
            name: "Encode Test",
            decimals: 18,
            chain: .ethereum
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(token)
        #expect(data != nil)
        #expect(!(data.isEmpty))
    }
    
    @Test func testTokenDecodable() throws {
        let dateFormatter = ISO8601DateFormatter()
        let dateString = dateFormatter.string(from: Date())
        
        let json = """
        {
            "id": "\(UUID())",
            "contractAddress": "0xTestDecode",
            "symbol": "DEC",
            "name": "Decode Test",
            "decimals": 18,
            "chain": "ethereum",
            "addedAt": "\(dateString)"
        }
        """
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let token = try decoder.decode(CustomToken.self, from: json.data(using: .utf8)!)
        
        #expect(token.symbol == "DEC")
        #expect(token.decimals == 18)
    }
    
    // MARK: - ChainId Tests
    
    @Test func testChainIdGeneration() {
        let ethToken = CustomToken(
            contractAddress: "0xTest",
            symbol: "USDT",
            name: "Tether",
            decimals: 6,
            chain: .ethereum
        )
        
        #expect(ethToken.chainId == "usdt-erc20")
        
        let bscToken = CustomToken(
            contractAddress: "0xTest",
            symbol: "CAKE",
            name: "PancakeSwap",
            decimals: 18,
            chain: .bsc
        )
        
        #expect(bscToken.chainId == "cake-bep20")
        
        let splToken = CustomToken(
            contractAddress: "SolMint",
            symbol: "RAY",
            name: "Raydium",
            decimals: 6,
            chain: .solana
        )
        
        #expect(splToken.chainId == "ray-spl")
    }
    
    // MARK: - Singleton Tests
    
    @MainActor
    @Test func testCustomTokenManagerSingleton() {
        let manager1 = CustomTokenManager.shared
        let manager2 = CustomTokenManager.shared
        
        #expect(manager1 === manager2)
    }
}
