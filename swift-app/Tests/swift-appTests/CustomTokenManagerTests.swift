import XCTest
@testable import swift_app

final class CustomTokenManagerTests: XCTestCase {
    
    // MARK: - Token Model Tests
    
    func testCustomTokenInitialization() {
        let token = CustomToken(
            contractAddress: "0x6B175474E89094C44Da98b954EescdkdjFasGD5c",
            symbol: "DAI",
            name: "Dai Stablecoin",
            decimals: 18,
            chain: .ethereum
        )
        
        XCTAssertEqual(token.symbol, "DAI")
        XCTAssertEqual(token.name, "Dai Stablecoin")
        XCTAssertEqual(token.decimals, 18)
        XCTAssertEqual(token.chain, .ethereum)
        XCTAssertNil(token.logoURL)
    }
    
    func testCustomTokenWithOptionalFields() {
        let token = CustomToken(
            contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
            symbol: "USDC",
            name: "USD Coin",
            decimals: 6,
            chain: .ethereum,
            logoURL: "https://example.com/usdc.png"
        )
        
        XCTAssertEqual(token.logoURL, "https://example.com/usdc.png")
    }
    
    func testTokenChainIdentifier() {
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
        
        XCTAssertEqual(ethToken.chain, .ethereum)
        XCTAssertEqual(solToken.chain, .solana)
    }
    
    // MARK: - TokenChain Tests
    
    func testTokenChainCases() {
        let chains: [TokenChain] = [.ethereum, .bsc, .solana]
        XCTAssertEqual(chains.count, 3)
    }
    
    func testTokenChainDisplayName() {
        XCTAssertEqual(TokenChain.ethereum.displayName, "Ethereum (ERC-20)")
        XCTAssertEqual(TokenChain.bsc.displayName, "BNB Chain (BEP-20)")
        XCTAssertEqual(TokenChain.solana.displayName, "Solana (SPL)")
    }
    
    func testTokenChainAddressPlaceholder() {
        XCTAssertEqual(TokenChain.ethereum.addressPlaceholder, "0x...")
        XCTAssertEqual(TokenChain.bsc.addressPlaceholder, "0x...")
        XCTAssertEqual(TokenChain.solana.addressPlaceholder, "Token mint address")
    }
    
    // MARK: - Contract Address Validation Tests
    
    func testEthereumAddressFormat() {
        let validAddress = "0x6B175474E89094C44Da98b954EeadDeFE456dAcE" // exactly 42 chars
        XCTAssertTrue(validAddress.hasPrefix("0x"))
        XCTAssertEqual(validAddress.count, 42)
    }
    
    func testSolanaAddressFormat() {
        let validAddress = "So11111111111111111111111111111111111111112"
        XCTAssertTrue(validAddress.count >= 32 && validAddress.count <= 44)
    }
    
    // MARK: - Token Encoding Tests
    
    func testTokenEncodable() throws {
        let token = CustomToken(
            contractAddress: "0xTestEncode",
            symbol: "ENC",
            name: "Encode Test",
            decimals: 18,
            chain: .ethereum
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(token)
        XCTAssertNotNil(data)
        XCTAssertFalse(data.isEmpty)
    }
    
    func testTokenDecodable() throws {
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
        
        XCTAssertEqual(token.symbol, "DEC")
        XCTAssertEqual(token.decimals, 18)
    }
    
    // MARK: - ChainId Tests
    
    func testChainIdGeneration() {
        let ethToken = CustomToken(
            contractAddress: "0xTest",
            symbol: "USDT",
            name: "Tether",
            decimals: 6,
            chain: .ethereum
        )
        
        XCTAssertEqual(ethToken.chainId, "usdt-erc20")
        
        let bscToken = CustomToken(
            contractAddress: "0xTest",
            symbol: "CAKE",
            name: "PancakeSwap",
            decimals: 18,
            chain: .bsc
        )
        
        XCTAssertEqual(bscToken.chainId, "cake-bep20")
        
        let splToken = CustomToken(
            contractAddress: "SolMint",
            symbol: "RAY",
            name: "Raydium",
            decimals: 6,
            chain: .solana
        )
        
        XCTAssertEqual(splToken.chainId, "ray-spl")
    }
    
    // MARK: - Singleton Tests
    
    @MainActor
    func testCustomTokenManagerSingleton() {
        let manager1 = CustomTokenManager.shared
        let manager2 = CustomTokenManager.shared
        
        XCTAssertTrue(manager1 === manager2)
    }
}
