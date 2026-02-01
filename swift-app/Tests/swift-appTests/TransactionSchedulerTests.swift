import Testing
import Foundation
@testable import swift_app

@Suite
struct TransactionSchedulerTests {
    
    // MARK: - ScheduledTransaction Model Tests
    
    @Test func testScheduledTransactionInitialization() {
        let scheduledDate = Date().addingTimeInterval(3600) // 1 hour from now
        
        let tx = ScheduledTransaction(
            chain: .ethereum,
            recipientAddress: "0x742d35Cc6634C0532925a3b844Bc9e7595f2BD2e",
            amount: Decimal(0.5),
            scheduledDate: scheduledDate,
            label: "Test Payment"
        )
        
        #expect(tx.recipientAddress == "0x742d35Cc6634C0532925a3b844Bc9e7595f2BD2e")
        #expect(tx.amount == Decimal(0.5))
        #expect(tx.chain == .ethereum)
        #expect(tx.label == "Test Payment")
        #expect(tx.status == .pending)
        #expect(!(tx.isRecurring))
    }
    
    @Test func testScheduledTransactionRecurring() {
        let tx = ScheduledTransaction(
            chain: .bitcoin,
            recipientAddress: "bc1qtest",
            amount: Decimal(0.001),
            scheduledDate: Date(),
            frequency: .weekly,
            label: "Weekly Payment"
        )
        
        #expect(tx.isRecurring)
        #expect(tx.frequency == .weekly)
    }
    
    // MARK: - SchedulableChain Tests
    
    @Test func testSchedulableChainCases() {
        let chains: [SchedulableChain] = [.bitcoin, .ethereum, .litecoin, .solana, .xrp]
        #expect(chains.count == 5)
    }
    
    @Test func testSchedulableChainDisplayName() {
        #expect(SchedulableChain.bitcoin.displayName == "Bitcoin")
        #expect(SchedulableChain.ethereum.displayName == "Ethereum")
        #expect(SchedulableChain.solana.displayName == "Solana")
    }
    
    // MARK: - Transaction Status Tests
    
    @Test func testTransactionStatusCases() {
        let statuses: [ScheduledTransactionStatus] = [.pending, .ready, .executing, .completed, .failed, .cancelled, .paused]
        #expect(statuses.count == 7)
    }
    
    @Test func testTransactionStatusTransitions() {
        var tx = ScheduledTransaction(
            chain: .ethereum,
            recipientAddress: "0xTest",
            amount: Decimal(1.0),
            scheduledDate: Date()
        )
        
        #expect(tx.status == .pending)
        
        tx.status = .executing
        #expect(tx.status == .executing)
        
        tx.status = .completed
        #expect(tx.status == .completed)
    }
    
    // MARK: - Recurrence Frequency Tests
    
    @Test func testRecurrenceFrequencyCases() {
        let frequencies: [RecurrenceFrequency] = [.once, .daily, .weekly, .biweekly, .monthly, .quarterly, .yearly]
        #expect(frequencies.count == 7)
    }
    
    @Test func testRecurrenceFrequencyValues() {
        #expect(RecurrenceFrequency.daily.componentValue == 1)
        #expect(RecurrenceFrequency.weekly.componentValue == 1)
        #expect(RecurrenceFrequency.biweekly.componentValue == 2)
        #expect(RecurrenceFrequency.monthly.componentValue == 1)
        #expect(RecurrenceFrequency.quarterly.componentValue == 3)
        #expect(RecurrenceFrequency.yearly.componentValue == 1)
    }
    
    // MARK: - Amount Validation Tests
    
    @Test func testPositiveAmount() {
        let tx = ScheduledTransaction(
            chain: .ethereum,
            recipientAddress: "0xPositive",
            amount: Decimal(0.001),
            scheduledDate: Date()
        )
        
        #expect(tx.amount > 0)
    }
    
    @Test func testDecimalPrecision() {
        let tx = ScheduledTransaction(
            chain: .bitcoin,
            recipientAddress: "0xPrecision",
            amount: Decimal(string: "0.00000001")!,
            scheduledDate: Date()
        )
        
        #expect(tx.amount == Decimal(string: "0.00000001"))
    }
    
    // MARK: - Date Scheduling Tests
    
    @Test func testFutureScheduling() {
        let futureDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        
        let tx = ScheduledTransaction(
            chain: .ethereum,
            recipientAddress: "0xFuture",
            amount: Decimal(1.0),
            scheduledDate: futureDate
        )
        
        #expect(tx.scheduledDate > Date())
    }
    
    // MARK: - Encoding Tests
    
    @Test func testScheduledTransactionEncodable() throws {
        let tx = ScheduledTransaction(
            chain: .ethereum,
            recipientAddress: "0xEncode",
            amount: Decimal(1.5),
            scheduledDate: Date(),
            label: "Test Encode"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(tx)
        #expect(data != nil)
        #expect(!(data.isEmpty))
    }
    
    // MARK: - Chain-Specific Tests
    
    @Test func testBitcoinScheduledTransaction() {
        let tx = ScheduledTransaction(
            chain: .bitcoin,
            recipientAddress: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            amount: Decimal(0.001),
            scheduledDate: Date()
        )
        
        #expect(tx.chain == .bitcoin)
        #expect(tx.recipientAddress.hasPrefix("bc1"))
    }
    
    @Test func testEthereumScheduledTransaction() {
        let tx = ScheduledTransaction(
            chain: .ethereum,
            recipientAddress: "0x742d35Cc6634C0532925a3b844Bc9e7595f2BD2e",
            amount: Decimal(0.1),
            scheduledDate: Date()
        )
        
        #expect(tx.chain == .ethereum)
        #expect(tx.recipientAddress.hasPrefix("0x"))
    }
    
    @Test func testSolanaScheduledTransaction() {
        let tx = ScheduledTransaction(
            chain: .solana,
            recipientAddress: "7KQCpknPURxD3B4i2E4qKc9d4rT5g2XyL3n9bCGcS8Uk",
            amount: Decimal(1.0),
            scheduledDate: Date()
        )
        
        #expect(tx.chain == .solana)
    }
    
    // MARK: - IsActive Tests
    
    @Test func testIsActive() {
        let tx = ScheduledTransaction(
            chain: .ethereum,
            recipientAddress: "0xActive",
            amount: Decimal(1.0),
            scheduledDate: Date()
        )
        
        #expect(tx.isActive) // pending is active
    }
    
    @Test func testIsNotActiveWhenCompleted() {
        var tx = ScheduledTransaction(
            chain: .ethereum,
            recipientAddress: "0xInactive",
            amount: Decimal(1.0),
            scheduledDate: Date()
        )
        tx.status = .completed
        
        #expect(!(tx.isActive))
    }
    
    // MARK: - Singleton Tests
    
    @MainActor
    @Test func testSchedulerSingleton() {
        let scheduler1 = TransactionScheduler.shared
        let scheduler2 = TransactionScheduler.shared
        
        #expect(scheduler1 === scheduler2)
    }
}
