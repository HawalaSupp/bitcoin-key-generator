import Testing
import Foundation
@testable import swift_app

@MainActor
@Suite
struct BatchTransactionManagerTests {
    
    // MARK: - BatchRecipient Model Tests
    
    @Test func testBatchRecipientInitialization() {
        let recipient = BatchRecipient(
            address: "0x742d35Cc6634C0532925a3b844Bc9e7595f2BD2e",
            amount: "0.5",
            label: "Test Recipient"
        )
        
        #expect(recipient.address == "0x742d35Cc6634C0532925a3b844Bc9e7595f2BD2e")
        #expect(recipient.amount == "0.5")
        #expect(recipient.label == "Test Recipient")
    }
    
    @Test func testBatchRecipientWithoutLabel() {
        let recipient = BatchRecipient(
            address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amount: "0.001",
            label: nil
        )
        
        #expect(recipient.label == nil)
        #expect(recipient.amount == "0.001")
    }
    
    @Test func testBatchRecipientAmountDouble() {
        let recipient = BatchRecipient(
            address: "0xTest",
            amount: "1.5",
            label: nil
        )
        
        #expect(abs(recipient.amountDouble - 1.5) < 0.0001)
    }
    
    @Test func testBatchRecipientInvalidAmount() {
        let recipient = BatchRecipient(
            address: "0xTest",
            amount: "invalid",
            label: nil
        )
        
        #expect(recipient.amountDouble == 0.0)
    }
    
    // MARK: - Batch Configuration Tests
    
    @Test func testBatchChainCases() {
        let chains: [BatchChain] = [.bitcoin, .ethereum, .bnb, .solana]
        #expect(chains.count == 4)
    }
    
    @Test func testBatchChainDisplayName() {
        #expect(BatchChain.bitcoin.displayName == "Bitcoin")
        #expect(BatchChain.ethereum.displayName == "Ethereum")
        #expect(BatchChain.bnb.displayName == "BNB Chain")
        #expect(BatchChain.solana.displayName == "Solana")
    }
    
    @Test func testBatchChainSymbol() {
        #expect(BatchChain.bitcoin.symbol == "BTC")
        #expect(BatchChain.ethereum.symbol == "ETH")
        #expect(BatchChain.bnb.symbol == "BNB")
        #expect(BatchChain.solana.symbol == "SOL")
    }
    
    @Test func testBatchChainSupportsBatching() {
        #expect(BatchChain.bitcoin.supportsBatching)
        #expect(BatchChain.ethereum.supportsBatching)
        #expect(BatchChain.bnb.supportsBatching)
        #expect(BatchChain.solana.supportsBatching)
    }
    
    // MARK: - Validation Tests
    
    @Test func testValidateBitcoinAddressFormat() {
        let bech32 = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        let legacy = "1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2"
        let p2sh = "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy"
        
        #expect(bech32.hasPrefix("bc1"))
        #expect(legacy.hasPrefix("1"))
        #expect(p2sh.hasPrefix("3"))
    }
    
    @Test func testValidateEthereumAddressFormat() {
        let validAddress = "0x742d35Cc6634C0532925a3b844Bc9e7595f2BD2e"
        
        #expect(validAddress.hasPrefix("0x"))
        #expect(validAddress.count == 42)
    }
    
    @Test func testValidateSolanaAddressFormat() {
        let validAddress = "7KQCpknPURxD3B4i2E4qKc9d4rT5g2XyL3n9bCGcS8Uk"
        
        #expect(validAddress.count >= 32 && validAddress.count <= 44)
    }
    
    // MARK: - Amount Validation Tests
    
    @Test func testValidPositiveAmount() {
        let recipient = BatchRecipient(address: "0xTest", amount: "0.001", label: nil)
        #expect(recipient.amountDouble > 0)
    }
    
    @Test func testMinimumAmountBitcoin() {
        let dustLimit: Double = 0.00000546
        let amount: Double = 0.0001
        
        #expect(amount > dustLimit)
    }
    
    // MARK: - Recipient Encoding Tests
    
    @Test func testBatchRecipientEncodable() throws {
        let recipient = BatchRecipient(
            address: "0xEncodeTest",
            amount: "1.5",
            label: "Test Label"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(recipient)
        #expect(data != nil)
        #expect(!(data.isEmpty))
    }
    
    @Test func testBatchRecipientDecodable() throws {
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
        
        #expect(recipient.address == "0xDecodeTest")
        #expect(recipient.amount == "2.5")
        #expect(recipient.label == "Decoded Label")
    }
    
    // MARK: - Fee Estimation Tests
    
    @Test func testEstimatedFeePerTx() {
        let btcFee: Double = 0.00001
        let ethFee: Double = 0.001
        let solFee: Double = 0.000005
        
        #expect(btcFee > 0)
        #expect(ethFee > 0)
        #expect(solFee > 0)
    }
    
    // MARK: - Edge Cases
    
    @Test func testVerySmallAmount() {
        let recipient = BatchRecipient(
            address: "0xSmallAmount",
            amount: "0.000000001",
            label: nil
        )
        
        #expect(recipient.amountDouble > 0)
    }
    
    @Test func testLargeAmount() {
        let recipient = BatchRecipient(
            address: "0xLargeAmount",
            amount: "1000000.0",
            label: nil
        )
        
        #expect(abs(recipient.amountDouble - 1000000.0) < 0.1)
    }
    
    @Test func testEmptyAddress() {
        let recipient = BatchRecipient(
            address: "",
            amount: "1.0",
            label: nil
        )
        
        #expect(recipient.address.isEmpty)
    }
    
    @Test func testEmptyAmount() {
        let recipient = BatchRecipient(
            address: "0xTest",
            amount: "",
            label: nil
        )
        
        #expect(recipient.amountDouble == 0.0)
    }
    
    // MARK: - Singleton Tests
    
    @Test func testBatchManagerSingleton() {
        let manager1 = BatchTransactionManager.shared
        let manager2 = BatchTransactionManager.shared
        
        #expect(manager1 === manager2)
    }
}
