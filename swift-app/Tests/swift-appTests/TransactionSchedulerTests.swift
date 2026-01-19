import XCTest
@testable import swift_app

final class TransactionSchedulerTests: XCTestCase {
    
    // MARK: - ScheduledTransaction Model Tests
    
    func testScheduledTransactionInitialization() {
        let scheduledDate = Date().addingTimeInterval(3600) // 1 hour from now
        
        let tx = ScheduledTransaction(
            chain: .ethereum,
            recipientAddress: "0x742d35Cc6634C0532925a3b844Bc9e7595f2BD2e",
            amount: Decimal(0.5),
            scheduledDate: scheduledDate,
            label: "Test Payment"
        )
        
        XCTAssertEqual(tx.recipientAddress, "0x742d35Cc6634C0532925a3b844Bc9e7595f2BD2e")
        XCTAssertEqual(tx.amount, Decimal(0.5))
        XCTAssertEqual(tx.chain, .ethereum)
        XCTAssertEqual(tx.label, "Test Payment")
        XCTAssertEqual(tx.status, .pending)
        XCTAssertFalse(tx.isRecurring)
    }
    
    func testScheduledTransactionRecurring() {
        let tx = ScheduledTransaction(
            chain: .bitcoin,
            recipientAddress: "bc1qtest",
            amount: Decimal(0.001),
            scheduledDate: Date(),
            frequency: .weekly,
            label: "Weekly Payment"
        )
        
        XCTAssertTrue(tx.isRecurring)
        XCTAssertEqual(tx.frequency, .weekly)
    }
    
    // MARK: - SchedulableChain Tests
    
    func testSchedulableChainCases() {
        let chains: [SchedulableChain] = [.bitcoin, .ethereum, .litecoin, .solana, .xrp]
        XCTAssertEqual(chains.count, 5)
    }
    
    func testSchedulableChainDisplayName() {
        XCTAssertEqual(SchedulableChain.bitcoin.displayName, "Bitcoin")
        XCTAssertEqual(SchedulableChain.ethereum.displayName, "Ethereum")
        XCTAssertEqual(SchedulableChain.solana.displayName, "Solana")
    }
    
    // MARK: - Transaction Status Tests
    
    func testTransactionStatusCases() {
        let statuses: [ScheduledTransactionStatus] = [.pending, .ready, .executing, .completed, .failed, .cancelled, .paused]
        XCTAssertEqual(statuses.count, 7)
    }
    
    func testTransactionStatusTransitions() {
        var tx = ScheduledTransaction(
            chain: .ethereum,
            recipientAddress: "0xTest",
            amount: Decimal(1.0),
            scheduledDate: Date()
        )
        
        XCTAssertEqual(tx.status, .pending)
        
        tx.status = .executing
        XCTAssertEqual(tx.status, .executing)
        
        tx.status = .completed
        XCTAssertEqual(tx.status, .completed)
    }
    
    // MARK: - Recurrence Frequency Tests
    
    func testRecurrenceFrequencyCases() {
        let frequencies: [RecurrenceFrequency] = [.once, .daily, .weekly, .biweekly, .monthly, .quarterly, .yearly]
        XCTAssertEqual(frequencies.count, 7)
    }
    
    func testRecurrenceFrequencyValues() {
        XCTAssertEqual(RecurrenceFrequency.daily.componentValue, 1)
        XCTAssertEqual(RecurrenceFrequency.weekly.componentValue, 1)
        XCTAssertEqual(RecurrenceFrequency.biweekly.componentValue, 2)
        XCTAssertEqual(RecurrenceFrequency.monthly.componentValue, 1)
        XCTAssertEqual(RecurrenceFrequency.quarterly.componentValue, 3)
        XCTAssertEqual(RecurrenceFrequency.yearly.componentValue, 1)
    }
    
    // MARK: - Amount Validation Tests
    
    func testPositiveAmount() {
        let tx = ScheduledTransaction(
            chain: .ethereum,
            recipientAddress: "0xPositive",
            amount: Decimal(0.001),
            scheduledDate: Date()
        )
        
        XCTAssertTrue(tx.amount > 0)
    }
    
    func testDecimalPrecision() {
        let tx = ScheduledTransaction(
            chain: .bitcoin,
            recipientAddress: "0xPrecision",
            amount: Decimal(string: "0.00000001")!,
            scheduledDate: Date()
        )
        
        XCTAssertEqual(tx.amount, Decimal(string: "0.00000001"))
    }
    
    // MARK: - Date Scheduling Tests
    
    func testFutureScheduling() {
        let futureDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        
        let tx = ScheduledTransaction(
            chain: .ethereum,
            recipientAddress: "0xFuture",
            amount: Decimal(1.0),
            scheduledDate: futureDate
        )
        
        XCTAssertTrue(tx.scheduledDate > Date())
    }
    
    // MARK: - Encoding Tests
    
    func testScheduledTransactionEncodable() throws {
        let tx = ScheduledTransaction(
            chain: .ethereum,
            recipientAddress: "0xEncode",
            amount: Decimal(1.5),
            scheduledDate: Date(),
            label: "Test Encode"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(tx)
        XCTAssertNotNil(data)
        XCTAssertFalse(data.isEmpty)
    }
    
    // MARK: - Chain-Specific Tests
    
    func testBitcoinScheduledTransaction() {
        let tx = ScheduledTransaction(
            chain: .bitcoin,
            recipientAddress: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amount: Decimal(0.001),
            scheduledDate: Date()
        )
        
        XCTAssertEqual(tx.chain, .bitcoin)
        XCTAssertTrue(tx.recipientAddress.hasPrefix("bc1"))
    }
    
    func testEthereumScheduledTransaction() {
        let tx = ScheduledTransaction(
            chain: .ethereum,
            recipientAddress: "0x742d35Cc6634C0532925a3b844Bc9e7595f2BD2e",
            amount: Decimal(0.1),
            scheduledDate: Date()
        )
        
        XCTAssertEqual(tx.chain, .ethereum)
        XCTAssertTrue(tx.recipientAddress.hasPrefix("0x"))
    }
    
    func testSolanaScheduledTransaction() {
        let tx = ScheduledTransaction(
            chain: .solana,
            recipientAddress: "7KQCpknPURxD3B4i2E4qKc9d4rT5g2XyL3n9bCGcS8Uk",
            amount: Decimal(1.0),
            scheduledDate: Date()
        )
        
        XCTAssertEqual(tx.chain, .solana)
    }
    
    // MARK: - IsActive Tests
    
    func testIsActive() {
        let tx = ScheduledTransaction(
            chain: .ethereum,
            recipientAddress: "0xActive",
            amount: Decimal(1.0),
            scheduledDate: Date()
        )
        
        XCTAssertTrue(tx.isActive) // pending is active
    }
    
    func testIsNotActiveWhenCompleted() {
        var tx = ScheduledTransaction(
            chain: .ethereum,
            recipientAddress: "0xInactive",
            amount: Decimal(1.0),
            scheduledDate: Date()
        )
        tx.status = .completed
        
        XCTAssertFalse(tx.isActive)
    }
    
    // MARK: - Singleton Tests
    
    @MainActor
    func testSchedulerSingleton() {
        let scheduler1 = TransactionScheduler.shared
        let scheduler2 = TransactionScheduler.shared
        
        XCTAssertTrue(scheduler1 === scheduler2)
    }
}
