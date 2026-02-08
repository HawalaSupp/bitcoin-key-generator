import Testing
import Foundation
@testable import swift_app

// MARK: - ROADMAP-08 Transaction Safety Tests

@Suite("ROADMAP-08 Transaction Safety")
struct TransactionSafetyTests {
    
    // ============================================================
    // MARK: - E1: Address Screening (GoPlus API Integration)
    // ============================================================
    
    @Test("Sanctioned address returns critical risk")
    @MainActor
    func sanctionedAddressDetection() {
        let manager = AddressIntelligenceManager.shared
        // Known OFAC sanctioned Tornado Cash address
        let risk = manager.quickRiskCheck("0x722122df12d4e14e13ac3b6895a86e84145b6967")
        #expect(risk == .critical, "Sanctioned addresses should return .critical risk")
    }
    
    @Test("Previously-sent address returns safe")
    @MainActor
    func previouslySentAddressIsSafe() {
        let manager = AddressIntelligenceManager.shared
        manager.recordSend(to: "0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD")
        let risk = manager.quickRiskCheck("0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD")
        #expect(risk == .safe, "Previously sent address should return .safe risk")
    }
    
    @Test("Scam address returns high risk")
    @MainActor
    func scamAddressDetection() {
        let manager = AddressIntelligenceManager.shared
        manager.reportScam("0xdeadbeef00000000000000000000000000000001")
        let risk = manager.quickRiskCheck("0xdeadbeef00000000000000000000000000000001")
        #expect(risk == .high, "Reported scam addresses should return .high risk")
        manager.removeScamReport("0xdeadbeef00000000000000000000000000000001")
    }
    
    @Test("Unknown address returns medium risk")
    @MainActor
    func unknownAddressIsMediumRisk() {
        let manager = AddressIntelligenceManager.shared
        let risk = manager.quickRiskCheck("0x1111111111111111111111111111111111111111")
        #expect(risk == .medium, "Unknown addresses should return .medium risk")
    }
    
    @Test("Analyze address returns risk factors for sanctioned address")
    @MainActor
    func analyzeAddressReturnsRiskFactors() async {
        let manager = AddressIntelligenceManager.shared
        let analysis = await manager.analyzeAddress("0x722122df12d4e14e13ac3b6895a86e84145b6967")
        #expect(analysis.isSanctioned, "Analysis should identify sanctioned address")
        #expect(analysis.riskLevel == .critical, "Sanctioned address should have critical risk level")
        #expect(!analysis.riskFactors.isEmpty, "Should have risk factors explaining the risk")
    }
    
    @Test("screenAddress method exists and handles gracefully")
    @MainActor
    func screenAddressMethodExists() async {
        let manager = AddressIntelligenceManager.shared
        let _ = await manager.screenAddress("0x1111111111111111111111111111111111111111", chainId: "1")
        // Just verifying no crash; result may be nil (network unavailable in tests)
    }
    
    @Test("GoPlusAddressResult struct has correct fields")
    func goPlusAddressResultStructure() {
        let result = AddressIntelligenceManager.GoPlusAddressResult(
            isBlacklisted: true,
            isContract: false,
            tag: "Scammer",
            transactionCount: 5,
            maliciousBehavior: ["Phishing", "Money Laundering"]
        )
        #expect(result.isBlacklisted)
        #expect(!result.isContract)
        #expect(result.tag == "Scammer")
        #expect(result.maliciousBehavior.count == 2)
        #expect(result.maliciousBehavior.contains("Phishing"))
    }
    
    // ============================================================
    // MARK: - E2: Scam Address Blocking Modal
    // ============================================================
    
    @Test("Blocking modal detects sanctioned addresses")
    @MainActor
    func scamModalSanctionedDetection() {
        let modal = ScamAddressBlockingModal(
            address: "0x722122df12d4e14e13ac3b6895a86e84145b6967",
            riskLevel: .critical,
            reasons: ["OFAC Sanctioned", "Tornado Cash"],
            onProceedAnyway: {},
            onCancel: {}
        )
        #expect(modal.isSanctioned, "Modal with OFAC reason should detect sanctioned status")
    }
    
    @Test("Non-sanctioned scam address is not marked as sanctioned")
    @MainActor
    func scamModalNonSanctionedAllowsProceed() {
        let modal = ScamAddressBlockingModal(
            address: "0xdeadbeef00000000000000000000000000000001",
            riskLevel: .high,
            reasons: ["Reported as scam", "Phishing"],
            onProceedAnyway: {},
            onCancel: {}
        )
        #expect(!modal.isSanctioned, "Non-sanctioned scam should not be marked as sanctioned")
    }
    
    @Test("Empty reasons modal is constructable")
    @MainActor
    func scamModalEmptyReasons() {
        let modal = ScamAddressBlockingModal(
            address: "0xdeadbeef00000000000000000000000000000001",
            riskLevel: .high,
            reasons: [],
            onProceedAnyway: {},
            onCancel: {}
        )
        #expect(!modal.isSanctioned)
    }
    
    // ============================================================
    // MARK: - E3: Exact Approval Amount Default
    // ============================================================
    
    @Test("checkApproval returns exact amount, not unlimited")
    @MainActor
    func checkApprovalDefaultsToExactAmount() async throws {
        let service = DEXAggregatorService.shared
        let maxUint256 = "115792089237316195423570985008687907853269984665640564039457584007913129639935"
        
        let approval = try await service.checkApproval(
            chain: .ethereum,
            token: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
            wallet: "0x1234567890abcdef1234567890abcdef12345678",
            provider: .uniswap,
            amount: "1000000"
        )
        
        #expect(approval.requiredAllowance == "1000000",
            "checkApproval should default to exact amount, not unlimited")
        #expect(approval.requiredAllowance != maxUint256,
            "checkApproval should NOT return max uint256 (unlimited)")
        #expect(approval.needsApproval)
    }
    
    @Test("checkApproval without amount returns 0")
    @MainActor
    func checkApprovalWithoutAmountReturnsZero() async throws {
        let service = DEXAggregatorService.shared
        
        let approval = try await service.checkApproval(
            chain: .ethereum,
            token: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
            wallet: "0x1234567890abcdef1234567890abcdef12345678",
            provider: .uniswap
        )
        
        #expect(approval.requiredAllowance == "0")
    }
    
    @Test("ApprovalMode enum has exact and unlimited cases")
    func approvalModeEnum() {
        let exactMode = DEXAggregatorService.ApprovalMode.exact("500000")
        let unlimitedMode = DEXAggregatorService.ApprovalMode.unlimited
        
        switch exactMode {
        case .exact(let amount):
            #expect(amount == "500000")
        case .unlimited:
            Issue.record("Should be exact mode")
        }
        
        switch unlimitedMode {
        case .exact:
            Issue.record("Should be unlimited mode")
        case .unlimited:
            break
        }
    }
    
    @Test("TokenApproval spender resolves to valid hex address")
    @MainActor
    func tokenApprovalSpenderResolution() async throws {
        let service = DEXAggregatorService.shared
        
        let approval = try await service.checkApproval(
            chain: .ethereum,
            token: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
            wallet: "0x0000000000000000000000000000000000000000",
            provider: .uniswap,
            amount: "1000000"
        )
        
        #expect(approval.spender.hasPrefix("0x"), "Spender should be a hex address")
        #expect(approval.spender.count == 42, "Spender should be 42 chars (0x + 40 hex)")
    }
    
    // ============================================================
    // MARK: - E9: Honeypot Token Detection
    // ============================================================
    
    @Test("Confirmed honeypot is critical risk")
    func honeypotResultCriticalRisk() {
        let result = HoneypotDetector.HoneypotResult(
            tokenAddress: "0xdead", chainId: "1",
            isHoneypot: true, buyTax: 0, sellTax: 100,
            cannotSellAll: true, cannotBuy: false,
            hasProxy: false, isOpenSource: false,
            holderCount: 10, ownerAddress: nil, creatorAddress: nil,
            isAntiWhale: false, tradingCooldown: false,
            transferPausable: false, hiddenOwner: false, externalCall: false,
            warnings: ["Token is a confirmed honeypot"],
            timestamp: Date()
        )
        
        #expect(result.riskLevel == .critical, "Confirmed honeypot should be critical risk")
        #expect(result.warningMessage.contains("HONEYPOT"), "Warning should mention HONEYPOT")
    }
    
    @Test("Extreme sell tax (35%) is high risk")
    func highSellTaxIsHighRisk() {
        let result = HoneypotDetector.HoneypotResult(
            tokenAddress: "0xdead", chainId: "1",
            isHoneypot: false, buyTax: 5, sellTax: 35,
            cannotSellAll: false, cannotBuy: false,
            hasProxy: false, isOpenSource: true,
            holderCount: 1000, ownerAddress: nil, creatorAddress: nil,
            isAntiWhale: false, tradingCooldown: false,
            transferPausable: false, hiddenOwner: false, externalCall: false,
            warnings: ["High sell tax: 35.0%"],
            timestamp: Date()
        )
        
        #expect(result.riskLevel == .high, "35% sell tax should be high risk")
        #expect(result.warningMessage.contains("sell tax"), "Warning should mention sell tax")
    }
    
    @Test("Proxy contract with moderate tax is medium risk")
    func proxyContractMediumRisk() {
        let result = HoneypotDetector.HoneypotResult(
            tokenAddress: "0xdead", chainId: "1",
            isHoneypot: false, buyTax: 2, sellTax: 12,
            cannotSellAll: false, cannotBuy: false,
            hasProxy: true, isOpenSource: true,
            holderCount: 5000, ownerAddress: nil, creatorAddress: nil,
            isAntiWhale: false, tradingCooldown: false,
            transferPausable: false, hiddenOwner: false, externalCall: false,
            warnings: [],
            timestamp: Date()
        )
        
        #expect(result.riskLevel == .medium, "Proxy + moderate tax should be medium risk")
    }
    
    @Test("Clean token is safe")
    func safeTokenRiskLevel() {
        let result = HoneypotDetector.HoneypotResult(
            tokenAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", chainId: "1",
            isHoneypot: false, buyTax: 0, sellTax: 0,
            cannotSellAll: false, cannotBuy: false,
            hasProxy: false, isOpenSource: true,
            holderCount: 500000, ownerAddress: nil, creatorAddress: nil,
            isAntiWhale: false, tradingCooldown: false,
            transferPausable: false, hiddenOwner: false, externalCall: false,
            warnings: [],
            timestamp: Date()
        )
        
        #expect(result.riskLevel == .safe, "Clean token should be safe")
        #expect(result.warningMessage.isEmpty, "Safe token should have no warning message")
    }
    
    @Test("Hidden owner triggers high risk")
    func hiddenOwnerHighRisk() {
        let result = HoneypotDetector.HoneypotResult(
            tokenAddress: "0xdead", chainId: "1",
            isHoneypot: false, buyTax: 0, sellTax: 0,
            cannotSellAll: false, cannotBuy: false,
            hasProxy: false, isOpenSource: true,
            holderCount: 1000, ownerAddress: nil, creatorAddress: nil,
            isAntiWhale: false, tradingCooldown: false,
            transferPausable: false, hiddenOwner: true, externalCall: false,
            warnings: ["Hidden contract owner"],
            timestamp: Date()
        )
        
        #expect(result.riskLevel == .high, "Hidden owner should be high risk")
    }
    
    @Test("External call triggers high risk")
    func externalCallHighRisk() {
        let result = HoneypotDetector.HoneypotResult(
            tokenAddress: "0xdead", chainId: "1",
            isHoneypot: false, buyTax: 0, sellTax: 0,
            cannotSellAll: false, cannotBuy: false,
            hasProxy: false, isOpenSource: true,
            holderCount: 1000, ownerAddress: nil, creatorAddress: nil,
            isAntiWhale: false, tradingCooldown: false,
            transferPausable: false, hiddenOwner: false, externalCall: true,
            warnings: ["Makes external calls (rug pull risk)"],
            timestamp: Date()
        )
        
        #expect(result.riskLevel == .high, "External call should be high risk")
    }
    
    @Test("Cannot sell all is critical risk")
    func cannotSellAllIsCritical() {
        let result = HoneypotDetector.HoneypotResult(
            tokenAddress: "0xdead", chainId: "1",
            isHoneypot: false, buyTax: 0, sellTax: 0,
            cannotSellAll: true, cannotBuy: false,
            hasProxy: false, isOpenSource: true,
            holderCount: 1000, ownerAddress: nil, creatorAddress: nil,
            isAntiWhale: false, tradingCooldown: false,
            transferPausable: false, hiddenOwner: false, externalCall: false,
            warnings: ["Cannot sell entire holding"],
            timestamp: Date()
        )
        
        #expect(result.riskLevel == .critical, "Cannot sell all should be critical")
    }
    
    @Test("Honeypot risk level ordering is comparable")
    func riskLevelOrdering() {
        let levels: [HoneypotDetector.HoneypotRiskLevel] = [.safe, .low, .medium, .high, .critical]
        for i in 0..<levels.count - 1 {
            #expect(levels[i] < levels[i + 1], "\(levels[i]) should be less than \(levels[i+1])")
        }
    }
    
    @Test("GoPlus chain ID mapping")
    @MainActor
    func goPlusChainIdMapping() {
        #expect(HoneypotDetector.goPlusChainId(from: "ethereum") == "1")
        #expect(HoneypotDetector.goPlusChainId(from: "bsc") == "56")
        #expect(HoneypotDetector.goPlusChainId(from: "polygon") == "137")
        #expect(HoneypotDetector.goPlusChainId(from: "arbitrum") == "42161")
        #expect(HoneypotDetector.goPlusChainId(from: "optimism") == "10")
        #expect(HoneypotDetector.goPlusChainId(from: "base") == "8453")
        #expect(HoneypotDetector.goPlusChainId(from: "bitcoin") == nil, "Bitcoin should not have a GoPlus chain ID")
    }
    
    @Test("HoneypotDetector.checkToken handles invalid input gracefully")
    @MainActor
    func honeypotDetectorCheckTokenExists() async {
        let detector = HoneypotDetector.shared
        let result = await detector.checkToken("invalid", chainId: "1")
        _ = result // May be nil — just verify no crash
    }
    
    @Test("HoneypotDetector cache returns nil for unchecked tokens")
    @MainActor
    func honeypotDetectorCaching() {
        let detector = HoneypotDetector.shared
        let cached = detector.cachedResult(for: "0x0000000000000000000000000000000000000000", chainId: "999")
        #expect(cached == nil, "Should have no cached result for unchecked token")
    }
    
    // ============================================================
    // MARK: - Existing ROADMAP-08: Phishing Detection
    // ============================================================
    
    @Test("Clipboard hijack detection catches same prefix/suffix")
    @MainActor
    func clipboardHijackDetection() {
        let manager = AddressIntelligenceManager.shared
        
        let hijacked = manager.detectClipboardHijack(
            expected: "0x1234aaaa0000000000000000000000000000abcd",
            pasted:   "0x1234bbbb0000000000000000000000000000abcd"
        )
        #expect(hijacked, "Same prefix/suffix but different middle should detect hijack")
        
        let same = manager.detectClipboardHijack(
            expected: "0x1234567890abcdef1234567890abcdef12345678",
            pasted:   "0x1234567890abcdef1234567890abcdef12345678"
        )
        #expect(!same, "Same address should not trigger hijack detection")
    }
    
    @Test("Address blockchain detection")
    func addressBlockchainDetection() {
        #expect(AddressBlockchain.detect(from: "0x1234567890abcdef1234567890abcdef12345678") == .ethereum)
        #expect(AddressBlockchain.detect(from: "bc1qxyz") == .bitcoin)
        #expect(AddressBlockchain.detect(from: "ltc1qxyz") == .litecoin)
    }
    
    // ============================================================
    // MARK: - Existing ROADMAP-08: Transaction Simulator
    // ============================================================
    
    @Test("TransactionSimulator types are correctly defined")
    func transactionSimulatorTypes() {
        let request = TransactionSimulator.TransactionRequest(
            chain: "ethereum",
            fromAddress: "0xfrom",
            toAddress: "0xto",
            amount: Decimal(1.5),
            tokenSymbol: "ETH",
            isNative: true,
            contractAddress: nil,
            data: nil,
            gasLimit: 21000,
            maxFeePerGas: nil,
            maxPriorityFee: nil
        )
        
        #expect(request.chain == "ethereum")
        #expect(request.amount == Decimal(1.5))
        #expect(request.isNative)
        #expect(request.data == nil)
    }
    
    @Test("Simulation warning types are valid")
    func simulationWarningTypes() {
        let warning = TransactionSimulator.SimulationWarning(
            type: .knownScam,
            title: "Known Scam",
            message: "This address is a known scam",
            severity: .danger,
            actionable: false,
            action: nil
        )
        
        #expect(warning.title == "Known Scam")
        #expect(warning.severity == .danger)
    }
    
    @Test("Transaction simulator runs without crash")
    @MainActor
    func transactionSimulatorRuns() async throws {
        let simulator = TransactionSimulator.shared
        
        let request = TransactionSimulator.TransactionRequest(
            chain: "ethereum",
            fromAddress: "0x0000000000000000000000000000000000000001",
            toAddress: "0x0000000000000000000000000000000000000002",
            amount: Decimal(0.01),
            tokenSymbol: "ETH",
            isNative: true,
            contractAddress: nil,
            data: nil,
            gasLimit: 21000,
            maxFeePerGas: nil,
            maxPriorityFee: nil
        )
        
        let result = try await simulator.simulate(request)
        #expect(result.success, "Simple ETH transfer simulation should succeed")
        #expect(result.estimatedGas > 0, "Should estimate some gas")
    }
    
    // ============================================================
    // MARK: - Existing ROADMAP-08: Token Approval Manager
    // ============================================================
    
    @Test("TokenApprovalManager singleton exists")
    @MainActor
    func tokenApprovalManagerExists() {
        let manager = TokenApprovalManager.shared
        let _ = manager.approvals
    }
    
    @Test("TokenApproval display amounts are correct")
    func tokenApprovalDisplayAmount() {
        let unlimited = TokenApproval(
            id: "1", tokenAddress: "0xA0b8", tokenName: "USDC", tokenSymbol: "USDC",
            tokenDecimals: 6, spenderAddress: "0xRouter", spenderName: "Uniswap",
            approvalAmount: UInt64.max, isUnlimited: true, isNFT: false,
            chainId: 1, timestamp: nil, transactionHash: nil
        )
        #expect(unlimited.displayAmount == "Unlimited")
        #expect(unlimited.riskLevel == .high)
        
        let exact = TokenApproval(
            id: "2", tokenAddress: "0xA0b8", tokenName: "USDC", tokenSymbol: "USDC",
            tokenDecimals: 6, spenderAddress: "0xRouter", spenderName: "Uniswap",
            approvalAmount: 1_000_000, isUnlimited: false, isNFT: false,
            chainId: 1, timestamp: nil, transactionHash: nil
        )
        #expect(exact.displayAmount == "1.0000")
        #expect(exact.riskLevel == .low)
        
        let nft = TokenApproval(
            id: "3", tokenAddress: "0xNFT", tokenName: "Bored Apes", tokenSymbol: "BAYC",
            tokenDecimals: 0, spenderAddress: "0xOpenSea", spenderName: "OpenSea",
            approvalAmount: nil, isUnlimited: false, isNFT: true,
            chainId: 1, timestamp: nil, transactionHash: nil
        )
        #expect(nft.displayAmount == "All NFTs")
        #expect(nft.riskLevel == .medium)
    }
    
    @Test("ApprovalRiskLevel has correct colors and icons")
    func approvalRiskLevelMetadata() {
        #expect(ApprovalRiskLevel.low.color == "green")
        #expect(ApprovalRiskLevel.medium.color == "yellow")
        #expect(ApprovalRiskLevel.high.color == "red")
        
        #expect(ApprovalRiskLevel.low.icon == "checkmark.shield")
        #expect(ApprovalRiskLevel.high.icon == "exclamationmark.octagon")
    }
    
    // ============================================================
    // MARK: - Existing ROADMAP-08: Transfer Tax Detection
    // ============================================================
    
    @Test("TransferTaxDetector finds known taxed tokens by address")
    func transferTaxDetectorByAddress() {
        let sfm = TransferTaxDetector.detectTax(
            address: "0x42981d0bfbAf196529376EE702F2a9Eb9092fcB5",
            chainId: "bsc"
        )
        #expect(sfm != nil, "SafeMoon V2 should be detected")
        #expect(sfm?.taxPercentage == 10.0)
        
        let usdc = TransferTaxDetector.detectTax(
            address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
            chainId: "ethereum"
        )
        #expect(usdc == nil, "USDC should not be detected as taxed")
    }
    
    @Test("TransferTaxDetector finds tokens by symbol")
    func transferTaxDetectorBySymbol() {
        let babydoge = TransferTaxDetector.detectTaxBySymbol("BABYDOGE")
        #expect(babydoge != nil)
        #expect(babydoge?.taxPercentage == 10.0)
        
        let eth = TransferTaxDetector.detectTaxBySymbol("ETH")
        #expect(eth == nil)
    }
    
    @Test("Transfer tax warning message format")
    func transferTaxWarningMessage() {
        let token = TransferTaxDetector.TaxedToken(
            symbol: "TEST",
            name: "Test Token",
            taxPercentage: 15.0,
            addresses: [:]
        )
        let msg = TransferTaxDetector.warningMessage(for: token)
        #expect(msg.contains("15"), "Warning should include tax percentage")
        #expect(msg.contains("Test Token"), "Warning should include token name")
    }
}
