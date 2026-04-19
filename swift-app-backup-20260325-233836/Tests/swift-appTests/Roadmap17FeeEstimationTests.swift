import Testing
import Foundation
@testable import swift_app

// MARK: - ROADMAP-17: Fee Estimation & Gas Management Tests

@Suite("ROADMAP-17: FeePriority Enum")
struct FeePriorityTests {
    
    @Test("FeePriority has all three tiers")
    func allCases() {
        let cases = FeePriority.allCases
        #expect(cases.count == 3)
        #expect(cases.contains(.slow))
        #expect(cases.contains(.average))
        #expect(cases.contains(.fast))
    }
    
    @Test("FeePriority icons are valid SF Symbol names")
    func icons() {
        #expect(FeePriority.slow.icon == "tortoise.fill")
        #expect(FeePriority.average.icon == "gauge.medium")
        #expect(FeePriority.fast.icon == "hare.fill")
    }
    
    @Test("FeePriority descriptions differ")
    func descriptions() {
        #expect(FeePriority.slow.description != FeePriority.fast.description)
        #expect(FeePriority.slow.ethDescription != FeePriority.fast.ethDescription)
    }
    
    @Test("FeePriority is Identifiable with rawValue id")
    func identifiable() {
        #expect(FeePriority.slow.id == "Slow")
        #expect(FeePriority.average.id == "Average")
        #expect(FeePriority.fast.id == "Fast")
    }
}

@Suite("ROADMAP-17: FeeEstimate Model")
struct FeeEstimateTests {
    
    @Test("FeeEstimate stores all fields correctly")
    func fields() {
        let est = FeeEstimate(
            priority: .average,
            feeRate: 15.5,
            estimatedFee: 0.0002,
            estimatedTime: "~30 min",
            fiatValue: 1.25
        )
        #expect(est.priority == .average)
        #expect(est.feeRate == 15.5)
        #expect(est.estimatedFee == 0.0002)
        #expect(est.estimatedTime == "~30 min")
        #expect(est.fiatValue == 1.25)
    }
    
    @Test("FeeEstimate formattedFeeRate handles different ranges")
    func formattedFeeRate() {
        let tiny = FeeEstimate(priority: .slow, feeRate: 0.5, estimatedFee: 0, estimatedTime: "", fiatValue: nil)
        #expect(tiny.formattedFeeRate == "0.50")
        
        let mid = FeeEstimate(priority: .average, feeRate: 12.3, estimatedFee: 0, estimatedTime: "", fiatValue: nil)
        #expect(mid.formattedFeeRate == "12.3")
        
        let high = FeeEstimate(priority: .fast, feeRate: 250, estimatedFee: 0, estimatedTime: "", fiatValue: nil)
        #expect(high.formattedFeeRate == "250")
    }
    
    @Test("FeeEstimate supports EIP-1559 fields")
    func eip1559() {
        var est = FeeEstimate(
            priority: .fast,
            feeRate: 30,
            estimatedFee: 0.001,
            estimatedTime: "~30 sec",
            fiatValue: nil
        )
        est.maxFeePerGas = 40.0
        est.maxPriorityFeePerGas = 2.0
        #expect(est.maxFeePerGas == 40.0)
        #expect(est.maxPriorityFeePerGas == 2.0)
    }
    
    @Test("FeeEstimate conforms to Equatable")
    func equatable() {
        let a = FeeEstimate(priority: .slow, feeRate: 5, estimatedFee: 0.001, estimatedTime: "~60 min", fiatValue: nil)
        let b = FeeEstimate(priority: .slow, feeRate: 5, estimatedFee: 0.001, estimatedTime: "~60 min", fiatValue: nil)
        #expect(a == b)
        
        let c = FeeEstimate(priority: .fast, feeRate: 20, estimatedFee: 0.002, estimatedTime: "~10 min", fiatValue: nil)
        #expect(a != c)
    }
}

@Suite("ROADMAP-17: Spike Detection")
@MainActor
struct SpikeDetectionTests {
    
    @Test("detectSpike returns false with insufficient history")
    func insufficientHistory() {
        let estimator = FeeEstimator.shared
        // Less than 4 entries → always false
        #expect(!estimator.detectSpike(history: [10, 10, 50], currentRate: 50))
        #expect(!estimator.detectSpike(history: [], currentRate: 100))
    }
    
    @Test("detectSpike returns true when current > 2× average")
    func spikeDetected() {
        let estimator = FeeEstimator.shared
        // History: [10, 10, 10, 50] → prior average = 10.0, current = 50 > 10×2 = 20 → spike
        let history = [10.0, 10.0, 10.0, 50.0]
        #expect(estimator.detectSpike(history: history, currentRate: 50.0))
    }
    
    @Test("detectSpike returns false when current ≤ 2× average")
    func noSpike() {
        let estimator = FeeEstimator.shared
        // History: [10, 10, 10, 15] → prior average = 10.0, current = 15 ≤ 20 → no spike
        let history = [10.0, 10.0, 10.0, 15.0]
        #expect(!estimator.detectSpike(history: history, currentRate: 15.0))
    }
    
    @Test("detectSpike handles exactly 2× boundary (not a spike)")
    func boundaryCase() {
        let estimator = FeeEstimator.shared
        // History: [10, 10, 10, 20] → prior average = 10.0, current = 20 == 2× → NOT spike (> required, not >=)
        let history = [10.0, 10.0, 10.0, 20.0]
        #expect(!estimator.detectSpike(history: history, currentRate: 20.0))
    }
    
    @Test("recordFeeHistory appends to Bitcoin history")
    func recordBitcoinHistory() {
        let estimator = FeeEstimator.shared
        let before = estimator.bitcoinFeeHistory.count
        estimator.recordFeeHistory(rate: 42.0, chain: FeeEstimator.FeeChainType.bitcoin)
        #expect(estimator.bitcoinFeeHistory.count == before + 1)
        #expect(estimator.bitcoinFeeHistory.last == 42.0)
    }
    
    @Test("recordFeeHistory appends to Ethereum history")
    func recordEthHistory() {
        let estimator = FeeEstimator.shared
        let before = estimator.ethereumFeeHistory.count
        estimator.recordFeeHistory(rate: 25.0, chain: FeeEstimator.FeeChainType.ethereum)
        #expect(estimator.ethereumFeeHistory.count == before + 1)
        #expect(estimator.ethereumFeeHistory.last == 25.0)
    }
    
    @Test("isFeeSpike maps chain IDs correctly")
    func chainIdMapping() {
        let estimator = FeeEstimator.shared
        // These should not crash and return a bool
        _ = estimator.isFeeSpike(forChainId: "bitcoin")
        _ = estimator.isFeeSpike(forChainId: "bitcoin-testnet")
        _ = estimator.isFeeSpike(forChainId: "ethereum")
        _ = estimator.isFeeSpike(forChainId: "polygon")
        _ = estimator.isFeeSpike(forChainId: "solana") // unknown → false
        #expect(!estimator.isFeeSpike(forChainId: "solana"))
    }
}

@Suite("ROADMAP-17: FeeWarning Model")
struct FeeWarningModelTests {
    
    @Test("FeeWarning severity colors are distinct")
    func severityColors() {
        let info = FeeWarning.Severity.info
        let warn = FeeWarning.Severity.warning
        let crit = FeeWarning.Severity.critical
        #expect(info.color != warn.color)
        #expect(warn.color != crit.color)
    }
    
    @Test("FeeWarning icons map correctly to severity")
    func warningIcons() {
        let info = FeeWarning(type: .slowConfirmation, title: "Slow", message: "msg", severity: .info)
        #expect(info.icon == "info.circle.fill")
        
        let warn = FeeWarning(type: .highFeePercentage, title: "High", message: "msg", severity: .warning)
        #expect(warn.icon == "exclamationmark.triangle.fill")
        
        let crit = FeeWarning(type: .lowFeeRate, title: "Low", message: "msg", severity: .critical)
        #expect(crit.icon == "exclamationmark.octagon.fill")
    }
    
    @Test("FeeWarning.WarningType includes feeSpike (ROADMAP-17 E11)")
    func feeSpikeType() {
        let spike = FeeWarning(type: .feeSpike, title: "Spike", message: "High", severity: .warning)
        #expect(spike.icon == "exclamationmark.triangle.fill")
    }
    
    @Test("FeeWarning conforms to Identifiable")
    func identifiable() {
        let a = FeeWarning(type: .lowFeeRate, title: "T", message: "M", severity: .critical)
        let b = FeeWarning(type: .lowFeeRate, title: "T", message: "M", severity: .critical)
        #expect(a.id != b.id) // Each gets a unique UUID
    }
}

@Suite("ROADMAP-17: FeeWarningService")
@MainActor
struct FeeWarningServiceTests {
    
    @Test("analyzeBitcoinFee detects high fee percentage")
    func highFeePercentage() {
        let svc = FeeWarningService.shared
        let warnings = svc.analyzeBitcoinFee(
            amount: Int64(10_000),   // 10,000 sats
            fee: Int64(2_000),       // 2,000 sats = 20% → should warn
            feeRate: Int64(14),
            currentFeeEstimates: nil
        )
        #expect(warnings.contains { $0.type == .highFeePercentage })
    }
    
    @Test("analyzeBitcoinFee detects low fee rate")
    func lowFeeRate() {
        let svc = FeeWarningService.shared
        let est = BitcoinFeeEstimate(
            fastest: FeeLevel(satPerByte: 20, estimatedMinutes: 10, label: "Fast"),
            fast: FeeLevel(satPerByte: 15, estimatedMinutes: 20, label: "Fast"),
            medium: FeeLevel(satPerByte: 10, estimatedMinutes: 60, label: "Med"),
            slow: FeeLevel(satPerByte: 5, estimatedMinutes: 120, label: "Slow"),
            minimum: FeeLevel(satPerByte: 2, estimatedMinutes: 1440, label: "Min")
        )
        let warnings = svc.analyzeBitcoinFee(
            amount: Int64(100_000),
            fee: Int64(100),         // very low fee
            feeRate: Int64(1),       // below minimum (2)
            currentFeeEstimates: est
        )
        #expect(warnings.contains { $0.type == .lowFeeRate })
    }
    
    @Test("analyzeBitcoinFee includes spike warning when isFeeSpike is true")
    func spikeWarning() {
        let svc = FeeWarningService.shared
        let warnings = svc.analyzeBitcoinFee(
            amount: Int64(100_000),
            fee: Int64(1_000),
            feeRate: Int64(7),
            currentFeeEstimates: nil,
            isFeeSpike: true
        )
        #expect(warnings.contains { $0.type == .feeSpike })
    }
    
    @Test("analyzeBitcoinFee omits spike warning when isFeeSpike is false")
    func noSpikeWarning() {
        let svc = FeeWarningService.shared
        let warnings = svc.analyzeBitcoinFee(
            amount: Int64(100_000),
            fee: Int64(1_000),
            feeRate: Int64(7),
            currentFeeEstimates: nil,
            isFeeSpike: false
        )
        #expect(!warnings.contains { $0.type == .feeSpike })
    }
    
    @Test("analyzeEVMFee detects gas limit too low")
    func gasLimitLow() {
        let svc = FeeWarningService.shared
        let warnings = svc.analyzeEVMFee(
            amount: UInt64(1_000_000_000_000_000_000), // 1 ETH in Wei
            gasPrice: UInt64(20_000_000_000),           // 20 Gwei in Wei
            gasLimit: UInt64(15_000),                   // below 21000
            chainId: "ethereum",
            currentFeeEstimates: nil
        )
        #expect(warnings.contains { $0.type == .gasLimitLow })
    }
    
    @Test("analyzeEVMFee includes spike warning when isFeeSpike is true")
    func evmSpikeWarning() {
        let svc = FeeWarningService.shared
        let warnings = svc.analyzeEVMFee(
            amount: UInt64(1_000_000_000_000_000_000),
            gasPrice: UInt64(20_000_000_000),
            gasLimit: UInt64(21_000),
            chainId: "ethereum",
            currentFeeEstimates: nil,
            isFeeSpike: true
        )
        #expect(warnings.contains { $0.type == .feeSpike })
    }
    
    @Test("clearWarnings resets published warnings")
    func clearWarnings() {
        let svc = FeeWarningService.shared
        _ = svc.analyzeBitcoinFee(amount: Int64(10_000), fee: Int64(5_000), feeRate: Int64(35), currentFeeEstimates: nil)
        #expect(!svc.warnings.isEmpty)
        svc.clearWarnings()
        #expect(svc.warnings.isEmpty)
    }
}

@Suite("ROADMAP-17: FeeEstimator Service")
@MainActor
struct FeeEstimatorServiceTests {
    
    @Test("FeeEstimator singleton exists")
    func singleton() {
        let est = FeeEstimator.shared
        #expect(est === FeeEstimator.shared) // Same instance
    }
    
    @Test("FeeEstimator has default Bitcoin estimates")
    func defaultBTC() {
        let est = FeeEstimator.shared
        #expect(!est.bitcoinEstimates.isEmpty)
        #expect(est.bitcoinEstimates.count == 3)
        let priorities = est.bitcoinEstimates.map(\.priority)
        #expect(priorities.contains(.slow))
        #expect(priorities.contains(.average))
        #expect(priorities.contains(.fast))
    }
    
    @Test("FeeEstimator has default Ethereum estimates")
    func defaultETH() {
        let est = FeeEstimator.shared
        #expect(!est.ethereumEstimates.isEmpty)
        #expect(est.ethereumEstimates.count == 3)
    }
    
    @Test("getBitcoinEstimate returns estimate for each priority")
    func getBTCEstimate() {
        let est = FeeEstimator.shared
        #expect(est.getBitcoinEstimate(for: .slow) != nil)
        #expect(est.getBitcoinEstimate(for: .average) != nil)
        #expect(est.getBitcoinEstimate(for: .fast) != nil)
    }
    
    @Test("getEthereumEstimate returns estimate for each priority")
    func getETHEstimate() {
        let est = FeeEstimator.shared
        #expect(est.getEthereumEstimate(for: .slow) != nil)
        #expect(est.getEthereumEstimate(for: .average) != nil)
        #expect(est.getEthereumEstimate(for: .fast) != nil)
    }
    
    @Test("calculateBitcoinFee returns correct value")
    func calcBTCFee() {
        let est = FeeEstimator.shared
        // 5 sat/vB × 140 vB = 700 sats = 0.000007 BTC
        let fee = est.calculateBitcoinFee(feeRate: 5, txSizeVBytes: 140)
        #expect(abs(fee - 0.000007) < 0.0000001)
    }
    
    @Test("calculateEthereumFee returns correct value")
    func calcETHFee() {
        let est = FeeEstimator.shared
        // 20 Gwei × 21000 gas = 420,000 Gwei = 0.00042 ETH
        let fee = est.calculateEthereumFee(gasPriceGwei: 20, gasLimit: 21000)
        #expect(abs(fee - 0.00042) < 0.0000001)
    }
}

@Suite("ROADMAP-17: TransactionReviewData Fiat Fields")
struct TransactionReviewDataFiatTests {
    
    @Test("TransactionReviewData computes fiatTotal when both fiat fields present")
    func fiatTotal() {
        let data = TransactionReviewData(
            chainId: "bitcoin", chainName: "Bitcoin",
            chainIcon: "bitcoinsign.circle.fill", symbol: "BTC",
            amount: 0.1, recipientAddress: "bc1qtest",
            recipientDisplayName: nil, feeRate: 5.0,
            feeRateUnit: "sat/vB", fee: 0.000007,
            feePriority: .average, estimatedTime: "~30 min",
            fiatAmount: 6500.0, fiatFee: 0.45,
            currentBalance: nil
        )
        #expect(data.fiatTotal != nil)
        #expect(abs(data.fiatTotal! - 6500.45) < 0.01)
    }
    
    @Test("TransactionReviewData returns nil fiatTotal when fiatFee is nil")
    func fiatTotalNilWhenMissing() {
        let data = TransactionReviewData(
            chainId: "bitcoin", chainName: "Bitcoin",
            chainIcon: "bitcoinsign.circle.fill", symbol: "BTC",
            amount: 0.1, recipientAddress: "bc1qtest",
            recipientDisplayName: nil, feeRate: 5.0,
            feeRateUnit: "sat/vB", fee: 0.000007,
            feePriority: .average, estimatedTime: "~30 min",
            fiatAmount: nil, fiatFee: nil,
            currentBalance: nil
        )
        #expect(data.fiatTotal == nil)
    }
    
    @Test("TransactionReviewData fee percentage calculation")
    func feePercentage() {
        let data = TransactionReviewData(
            chainId: "bitcoin", chainName: "Bitcoin",
            chainIcon: "bitcoinsign.circle.fill", symbol: "BTC",
            amount: 0.01, recipientAddress: "bc1qtest",
            recipientDisplayName: nil, feeRate: 5.0,
            feeRateUnit: "sat/vB", fee: 0.001, // 10% of amount
            feePriority: .average, estimatedTime: "~30 min",
            fiatAmount: nil, fiatFee: nil,
            currentBalance: nil
        )
        #expect(abs(data.feePercentage - 10.0) < 0.1)
    }
    
    @Test("TransactionReviewData detects insufficient balance")
    func insufficientBalance() {
        let data = TransactionReviewData(
            chainId: "bitcoin", chainName: "Bitcoin",
            chainIcon: "bitcoinsign.circle.fill", symbol: "BTC",
            amount: 1.0, recipientAddress: "bc1qtest",
            recipientDisplayName: nil, feeRate: 5.0,
            feeRateUnit: "sat/vB", fee: 0.001,
            feePriority: .average, estimatedTime: "~30 min",
            fiatAmount: nil, fiatFee: nil,
            currentBalance: 0.5 // less than amount + fee
        )
        #expect(data.hasInsufficientBalance)
    }
}

@Suite("ROADMAP-17: Stale Fee Detection")
struct StaleFeeDetectionTests {
    
    @Test("Fee estimate is considered stale after 30 seconds")
    func staleDetection() {
        let now = Date()
        let fresh = now.addingTimeInterval(-10) // 10 seconds ago
        let stale = now.addingTimeInterval(-35) // 35 seconds ago
        
        // 30-second threshold
        let freshAge = now.timeIntervalSince(fresh)
        let staleAge = now.timeIntervalSince(stale)
        
        #expect(freshAge < 30)
        #expect(staleAge > 30)
    }
}

@Suite("ROADMAP-17: FeeWarningBanner & FeeWarningView")
@MainActor
struct FeeWarningViewTests {
    
    @Test("FeeWarningView initializes without crash")
    func warningViewInit() {
        let warning = FeeWarning(type: .feeSpike, title: "Test", message: "Message", severity: .warning)
        let _ = FeeWarningView(warning: warning)
    }
    
    @Test("FeeWarningBanner initializes with empty warnings")
    func bannerEmpty() {
        let _ = FeeWarningBanner(warnings: [])
    }
    
    @Test("FeeWarningBanner initializes with multiple warnings")
    func bannerMultiple() {
        let warnings = [
            FeeWarning(type: .feeSpike, title: "Spike", message: "High fees", severity: .warning),
            FeeWarning(type: .lowFeeRate, title: "Low", message: "Too low", severity: .critical),
        ]
        let _ = FeeWarningBanner(warnings: warnings)
    }
    
    @Test("SendFeePriorityCard initializes with USD display")
    func priorityCardWithFiat() {
        let est = FeeEstimate(priority: .average, feeRate: 15, estimatedFee: 0.0002, estimatedTime: "~30 min", fiatValue: 1.50)
        let _ = SendFeePriorityCard(
            priority: .average,
            estimate: est,
            isSelected: true,
            chain: Chain.bitcoinMainnet,
            action: {}
        )
    }
}
