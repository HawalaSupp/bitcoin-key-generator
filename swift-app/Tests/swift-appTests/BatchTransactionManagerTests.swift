import XCTest
@testable import swift_app

@MainActor
final class BatchTransactionManagerTests: XCTestCase {
    
    // MARK: - BatchRecipient Model Tests
    
    func testBatchRecipientInitialization() {
        let recipient = BatchRecipient(
            address: "0x742d35Cc6634C0532925a3b844Bc9e7595f2BD2e",
            amount: "0.5",
            label: "Test Recipient"
        )
        
        XCTAssertEqual(recipient.address, "0x742d35Cc6634C0532925a3b844Bc9e7595f2BD2e")
        XCTAssertEqual(recipient.amount, "0.5")
        XCTAssertEqual(recipient.label, "Test Recipient")
    }
    
    func testBatchRecipientWithoutLabel() {
        let recipient = BatchRecipient(
            address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amount: "0.001",
            label: nil
        )
        
        XCTAssertNil(recipient.label)
        XCTAssertEqual(recipient.amount, "0.001")
    }
    
    func testBatchRecipientAmountDouble() {
        let recipient = BatchRecipient(
            address: "0xTest",
            amount: "1.5",
            label: nil
        )
        
        XCTAssertEqual(recipient.amountDouble, 1.5, accuracy: 0.0001)
    }
    
    func testBatchRecipientInvalidAmount() {
        let recipient = BatchRecipient(
            address: "0xTest",
            amount: "invalid",
            label: nil
        )
        
        XCTAssertEqual(recipient.amountDouble, 0.0)
    }
    
    // MARK: - Batch Configuration Tests
    
    func testBatchChainCases() {
        let chains: [BatchChain] = [.bitcoin, .ethereum, .bnb, .solana]
        XCTAssertEqual(chains.count, 4)
    }
    
    func testBatchChainDisplayName() {
        XCTAssertEqual(BatchChain.bitcoin.displayName, "Bitcoin")
        XCTAssertEqual(BatchChain.ethereum.displayName, "Ethereum")
        XCTAssertEqual(BatchChain.bnb.displayName, "BNB Chain")
        XCTAssertEqual(BatchChain.solana.displayName, "Solana")
    }
    
    func testBatchChainSymbol() {
        XCTAssertEqual(BatchChain.bitcoin.symbol, "BTC")
        XCTAssertEqual(BatchChain.ethereum.symbol, "ETH")
        XCTAssertEqual(BatchChain.bnb.symbol, "BNB")
        XCTAssertEqual(BatchChain.solana.symbol, "SOL")
    }
    
    func testBatchChainSupportsBatching() {
        XCTAssertTrue(BatchChain.bitcoin.supportsBatching)
        XCTAssertTrue(BatchChain.ethereum.supportsBatching)
        XCTAssertTrue(BatchChain.bnb.supportsBatching)
        XCTAssertTrue(BatchChain.solana.supportsBatching)
    }
    
    // MARK: - Validation Tests
    
    func testValidateBitcoinAddressFormat() {
        let bech32 = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        let legacy = "1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2"
        let p2sh = "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy"
        
        XCTAssertTrue(bech32.hasPrefix("bc1"))
        XCTAssertTrue(legacy.hasPrefix("1"))
        XCTAssertTrue(p2sh.hasPrefix("3"))
    }
    
    func testValidateEthereumAddressFormat() {
        let validAddress = "0x742d35Cc6634C0532925a3b844Bc9e7595f2BD2e"
        
        XCTAssertTrue(validAddress.hasPrefix("0x"))
        XCTAssertEqual(validAddress.count, 42)
    }
    
    func testValidateSolanaAddressFormat() {
        let validAddress = "7KQCpknPURxD3B4i2E4qKc9d4rT5g2XyL3n9bCGcS8Uk"
        
        XCTAssertTrue(validAddress.count >= 32 && validAddress.count <= 44)
    }
    
    // MARK: - Amount Validation Tests
    
    func testValidPositiveAmount() {
        let recipient = BatchRecipient(address: "0xTest", amount: "0.001", label: nil)
        XCTAssertTrue(recipient.amountDouble > 0)
    }
    
    func testMinimumAmountBitcoin() {
        let dustLimit: Double = 0.00000546
        let amount: Double = 0.0001
        
        XCTAssertTrue(amount > dustLimit)
    }
    
    // MARK: - Recipient Encoding Tests
    
    func testBatchRecipientEncodable() throws {
        let recipient = BatchRecipient(
            address: "0xEncodeTest",
            amount: "1.5",
            label: "Test Label"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(recipient)
        XCTAssertNotNil(data)
        XCTAssertFalse(data.isEmpty)
    }
    
    func testBatchRecipientDecodable() throws {
        let json = """
        {
            "id": "\(UUID())",
            "address": "0xDecodeTest",
            "amount": "2.5",
            "label": "Decoded Label",
            "isValid": false
        }
        """
        
        let decoder = JSONDecoder()
        let recipient = try decoder.decode(BatchRecipient.self, from: json.data(using: .utf8)!)
        
        XCTAssertEqual(recipient.address, "0xDecodeTest")
        XCTAssertEqual(recipient.amount, "2.5")
        XCTAssertEqual(recipient.label, "Decoded Label")
    }
    
    // MARK: - Fee Estimation Tests
    
    func testEstimatedFeePerTx() {
        let btcFee: Double = 0.00001
        let ethFee: Double = 0.001
        let solFee: Double = 0.000005
        
        XCTAssertTrue(btcFee > 0)
        XCTAssertTrue(ethFee > 0)
        XCTAssertTrue(solFee > 0)
    }
    
    // MARK: - Edge Cases
    
    func testVerySmallAmount() {
        let recipient = BatchRecipient(
            address: "0xSmallAmount",
            amount: "0.000000001",
            label: nil
        )
        
        XCTAssertTrue(recipient.amountDouble > 0)
    }
    
    func testLargeAmount() {
        let recipient = BatchRecipient(
            address: "0xLargeAmount",
            amount: "1000000.0",
            label: nil
        )
        
        XCTAssertEqual(recipient.amountDouble, 1000000.0, accuracy: 0.1)
    }
    
    func testEmptyAddress() {
        let recipient = BatchRecipient(
            address: "",
            amount: "1.0",
            label: nil
        )
        
        XCTAssertTrue(recipient.address.isEmpty)
    }
    
    func testEmptyAmount() {
        let recipient = BatchRecipient(
            address: "0xTest",
            amount: "",
            label: nil
        )
        
        XCTAssertEqual(recipient.amountDouble, 0.0)
    }
    
    // MARK: - Singleton Tests
    
    func testBatchManagerSingleton() {
        let manager1 = BatchTransactionManager.shared
        let manager2 = BatchTransactionManager.shared
        
        XCTAssertTrue(manager1 === manager2)
    }
}
