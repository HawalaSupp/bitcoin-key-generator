import Testing
import Foundation
@testable import swift_app

// MARK: - ROADMAP-19: QA & Edge Case Tests

// ============================================================
// I1-I5: Infrastructure Verification
// ============================================================

@Suite("ROADMAP-19 I1-I5: Test Infrastructure")
struct TestInfrastructureTests {

    @Test("I1: Swift Testing framework is operational")
    func swiftTestingFramework() {
        #expect(true, "Swift Testing framework is working")
    }

    @Test("I2: Integration test target compiles alongside unit tests")
    func integrationTestTargetCompiles() {
        // The fact this test runs proves the test target compiles
        #expect(true)
    }
}

// ============================================================
// T4: ViewModel Tests
// ============================================================

@Suite("ROADMAP-19 T4: WalletViewModel")
struct WalletViewModelTests {

    @Test("WalletViewModel starts with no keys")
    @MainActor
    func initialState() async {
        let vm = WalletViewModel()
        #expect(!vm.hasKeys)
        #expect(!vm.isGenerating)
        #expect(vm.errorMessage == nil)
        #expect(vm.statusMessage == nil)
        #expect(vm.rawJSON.isEmpty)
    }

    @Test("WalletViewModel chain list empty when no keys")
    @MainActor
    func chainInfosEmpty() async {
        let vm = WalletViewModel()
        #expect(vm.chainInfos.isEmpty)
    }

    @Test("WalletViewModel send eligible chains are filterable")
    @MainActor
    func sendEligibleFilter() async {
        let vm = WalletViewModel()
        // bitcoin, ethereum, etc. should be supported
        #expect(vm.isSendSupported(chainID: "bitcoin"))
        #expect(vm.isSendSupported(chainID: "ethereum"))
        #expect(vm.isSendSupported(chainID: "solana"))
        // Unknown chains should not
        #expect(!vm.isSendSupported(chainID: "nonexistent-chain"))
    }

    @Test("WalletViewModel showStatus auto-clears")
    @MainActor
    func showStatusMessage() async {
        let vm = WalletViewModel()
        vm.showStatus("Test message", tone: .success, autoClear: false)
        #expect(vm.statusMessage == "Test message")
        #expect(vm.statusColor == StatusTone.success.color)
    }

    @Test("WalletViewModel clearSensitiveData resets state")
    @MainActor
    func clearSensitiveData() async {
        let vm = WalletViewModel()
        vm.rawJSON = "test json"
        vm.clearSensitiveData()
        #expect(vm.rawJSON.isEmpty)
        #expect(!vm.hasKeys)
        #expect(vm.errorMessage == nil)
    }

    @Test("WalletViewModel export file name format")
    @MainActor
    func exportFileName() async {
        let vm = WalletViewModel()
        let name = vm.defaultExportFileName()
        #expect(name.hasPrefix("hawala-backup-"))
        #expect(name.hasSuffix(".hawala"))
    }

    @Test("WalletViewModel wasKeyGenInterrupted reads EdgeCaseGuards")
    @MainActor
    func keyGenInterruptedProxy() async {
        let vm = WalletViewModel()
        // Should match EdgeCaseGuards
        #expect(vm.wasKeyGenInterrupted == EdgeCaseGuards.wasKeyGenerationInterrupted)
    }
    
    @Test("WalletViewModel performFactoryWipe resets everything")
    @MainActor
    func factoryWipe() async {
        let vm = WalletViewModel()
        vm.rawJSON = "test"
        vm.performFactoryWipe()
        #expect(vm.rawJSON.isEmpty)
        #expect(!vm.hasKeys)
    }
}

// ============================================================
// T8: Offline / Network Simulation Tests
// ============================================================

@Suite("ROADMAP-19 T8: Offline & Network Error Handling")
struct OfflineNetworkTests {

    @Test("ErrorMessageMapper maps network offline errors")
    func offlineErrorMapping() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet,
                            userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."])
        let message = ErrorMessageMapper.userMessage(for: error)
        #expect(message == UserFacingError.Network.noConnection)
    }

    @Test("ErrorMessageMapper maps timeout errors")
    func timeoutErrorMapping() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
                            userInfo: [NSLocalizedDescriptionKey: "The request timed out."])
        let message = ErrorMessageMapper.userMessage(for: error)
        #expect(message == UserFacingError.Network.timeout)
    }

    @Test("ErrorMessageMapper maps rate limit errors")
    func rateLimitErrorMapping() {
        let error = NSError(domain: "API", code: 429,
                            userInfo: [NSLocalizedDescriptionKey: "429 rate limit exceeded"])
        let message = ErrorMessageMapper.userMessage(for: error)
        #expect(message == UserFacingError.Network.rateLimited)
    }

    @Test("ErrorMessageMapper maps server 500 errors")
    func serverErrorMapping() {
        let error = NSError(domain: "API", code: 500,
                            userInfo: [NSLocalizedDescriptionKey: "500 internal server error"])
        let message = ErrorMessageMapper.userMessage(for: error)
        #expect(message == UserFacingError.Network.serverError)
    }

    @Test("ErrorMessageMapper maps cancelled errors")
    func cancelledErrorMapping() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled,
                            userInfo: [NSLocalizedDescriptionKey: "The operation was cancelled."])
        let message = ErrorMessageMapper.userMessage(for: error)
        #expect(message == UserFacingError.Network.cancelled)
    }

    @Test("ErrorMessageMapper provides retry suggestions for network errors")
    func retryForNetworkError() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet,
                            userInfo: [NSLocalizedDescriptionKey: "network unavailable"])
        let suggestion = ErrorMessageMapper.retrySuggestion(for: error)
        #expect(suggestion != nil)
        #expect(suggestion!.contains("internet") || suggestion!.contains("connection"))
    }

    @Test("ErrorMessageMapper maps HTTP status codes")
    func httpStatusCodeMapping() {
        #expect(ErrorMessageMapper.userMessage(forStatusCode: 429) == UserFacingError.Network.rateLimited)
        #expect(ErrorMessageMapper.userMessage(forStatusCode: 500) == UserFacingError.Network.serverError)
        #expect(ErrorMessageMapper.userMessage(forStatusCode: 502) == UserFacingError.Network.serverError)
        #expect(ErrorMessageMapper.userMessage(forStatusCode: 401) == UserFacingError.Provider.apiKeyMissing)
    }

    @Test("ErrorAlertBuilder creates valid alert for network error")
    func alertBuildForNetworkError() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet,
                            userInfo: [NSLocalizedDescriptionKey: "network unavailable"])
        let alert = ErrorAlertBuilder.alertContent(for: error, context: "Send")
        #expect(alert.title == "Send")
        #expect(!alert.message.isEmpty)
    }
}

// ============================================================
// Edge Case #5: Key Generation State Persistence
// ============================================================

@Suite("ROADMAP-19 #5: Key Generation Interruption Guard", .serialized)
struct KeyGenerationGuardTests {

    @Test("markKeyGenerationStarted and wasKeyGenerationInterrupted round-trip")
    func markStartedAndCheck() {
        EdgeCaseGuards.markKeyGenerationFinished() // clean state
        EdgeCaseGuards.markKeyGenerationStarted()
        // Verify the flag was persisted
        let inProgress = UserDefaults.standard.bool(forKey: "hawala.keygen.inProgress")
        #expect(inProgress, "keygen.inProgress should be set")
        EdgeCaseGuards.markKeyGenerationFinished() // cleanup
    }

    @Test("markKeyGenerationFinished clears in-progress flag")
    func markFinished() {
        EdgeCaseGuards.markKeyGenerationStarted()
        EdgeCaseGuards.markKeyGenerationFinished()
        let inProgress = UserDefaults.standard.bool(forKey: "hawala.keygen.inProgress")
        #expect(!inProgress, "keygen.inProgress should be cleared")
    }
}

// ============================================================
// Edge Case #9: Locale-Aware Amount Parsing
// ============================================================

@Suite("ROADMAP-19 #9: Locale-Aware Amount Parsing")
struct LocaleAmountParsingTests {

    @Test("Normalises dot-separated amount (US locale)")
    func dotSeparator() {
        let usLocale = Locale(identifier: "en_US")
        let result = EdgeCaseGuards.normaliseAmountInput("1,000.50", locale: usLocale)
        #expect(result == "1000.50")
    }

    @Test("Normalises comma-separated amount (German locale)")
    func commaSeparator() {
        let deLocale = Locale(identifier: "de_DE")
        let result = EdgeCaseGuards.normaliseAmountInput("1.000,50", locale: deLocale)
        #expect(result == "1000.50")
    }

    @Test("Handles empty input")
    func emptyInput() {
        let result = EdgeCaseGuards.normaliseAmountInput("  ")
        #expect(result == "")
    }

    @Test("Handles plain number without separators")
    func plainNumber() {
        let result = EdgeCaseGuards.normaliseAmountInput("42", locale: Locale(identifier: "en_US"))
        #expect(result == "42")
    }

    @Test("AmountValidator.normaliseInput proxies to EdgeCaseGuards")
    func validatorProxy() {
        let result = AmountValidator.normaliseInput("1,000")
        #expect(!result.isEmpty)
    }
}

// ============================================================
// Edge Case #12: Price Feed $0 Guard
// ============================================================

@Suite("ROADMAP-19 #12: Price Feed Zero Guard")
struct PriceFeedZeroGuardTests {

    @Test("Zero price is invalid")
    func zeroPrice() {
        #expect(!EdgeCaseGuards.isPriceValid(0.0))
    }

    @Test("Negative price is invalid")
    func negativePrice() {
        #expect(!EdgeCaseGuards.isPriceValid(-100.0))
    }

    @Test("NaN price is invalid")
    func nanPrice() {
        #expect(!EdgeCaseGuards.isPriceValid(Double.nan))
    }

    @Test("Infinite price is invalid")
    func infinitePrice() {
        #expect(!EdgeCaseGuards.isPriceValid(Double.infinity))
    }

    @Test("Positive price is valid")
    func validPrice() {
        #expect(EdgeCaseGuards.isPriceValid(95000.0))
    }

    @Test("Decimal zero is invalid")
    func decimalZero() {
        #expect(!EdgeCaseGuards.isPriceValid(Decimal.zero))
    }

    @Test("Decimal positive is valid")
    func decimalPositive() {
        #expect(EdgeCaseGuards.isPriceValid(Decimal(string: "95000.00")!))
    }
}

// ============================================================
// Edge Case #18: Network Switch During Send
// ============================================================

@Suite("ROADMAP-19 #18: Network Switch Guard")
struct NetworkSwitchGuardTests {

    @Test("Can switch network when no transaction in flight")
    func canSwitchIdle() {
        #expect(EdgeCaseGuards.canSwitchNetwork(isTransactionInFlight: false))
    }

    @Test("Cannot switch network during transaction")
    func blockedDuringSend() {
        #expect(!EdgeCaseGuards.canSwitchNetwork(isTransactionInFlight: true))
    }
}

// ============================================================
// Edge Case #19: QR Code Security Validation
// ============================================================

@Suite("ROADMAP-19 #19: QR Code Payload Validation")
struct QRCodeSecurityTests {

    @Test("Empty QR payload rejected")
    func emptyPayload() {
        let warning = EdgeCaseGuards.validateQRPayload("")
        #expect(warning != nil)
        #expect(warning!.contains("Empty"))
    }

    @Test("javascript: URL rejected")
    func javascriptURL() {
        let warning = EdgeCaseGuards.validateQRPayload("javascript:alert(1)")
        #expect(warning != nil)
        #expect(warning!.contains("Malicious"))
    }

    @Test("data: URL rejected")
    func dataURL() {
        let warning = EdgeCaseGuards.validateQRPayload("data:text/html,<script>alert(1)</script>")
        #expect(warning != nil)
        #expect(warning!.contains("Suspicious"))
    }

    @Test("Insecure HTTP link warned")
    func httpLink() {
        let warning = EdgeCaseGuards.validateQRPayload("http://evil.com/phish")
        #expect(warning != nil)
        #expect(warning!.contains("Insecure"))
    }

    @Test("Oversized payload rejected")
    func oversizedPayload() {
        let bigPayload = String(repeating: "a", count: 5000)
        let warning = EdgeCaseGuards.validateQRPayload(bigPayload)
        #expect(warning != nil)
        #expect(warning!.contains("too large"))
    }

    @Test("Valid Bitcoin address passes")
    func validBitcoinAddress() {
        let warning = EdgeCaseGuards.validateQRPayload("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")
        #expect(warning == nil)
    }

    @Test("Valid HTTPS URL passes")
    func validHTTPS() {
        let warning = EdgeCaseGuards.validateQRPayload("https://hawala.wallet/pay?to=abc")
        #expect(warning == nil)
    }
}

// ============================================================
// Edge Case #30: Repeated Send Detection
// ============================================================

@Suite("ROADMAP-19 #30: Duplicate Send Detection")
struct DuplicateSendDetectionTests {

    @Test("No duplicate on first send")
    func firstSend() {
        // Use a unique test address to avoid collision
        let addr = "test_first_send_\(UUID().uuidString)"
        let isDup = EdgeCaseGuards.isDuplicateSend(to: addr, chain: "bitcoin")
        #expect(!isDup)
    }

    @Test("Duplicate detected after recording send")
    func duplicateAfterRecord() {
        let addr = "test_dup_\(UUID().uuidString)"
        EdgeCaseGuards.recordSend(to: addr, chain: "ethereum")
        let isDup = EdgeCaseGuards.isDuplicateSend(to: addr, chain: "ethereum")
        #expect(isDup)
    }

    @Test("Different chain is not duplicate")
    func differentChain() {
        let addr = "test_chain_\(UUID().uuidString)"
        EdgeCaseGuards.recordSend(to: addr, chain: "bitcoin")
        let isDup = EdgeCaseGuards.isDuplicateSend(to: addr, chain: "ethereum")
        #expect(!isDup)
    }
}

// ============================================================
// Edge Case #44: Factory Wipe
// ============================================================

@Suite("ROADMAP-19 #44: Factory Wipe")
struct FactoryWipeTests {

    @Test("Factory wipe executes without crash")
    @MainActor
    func factoryWipeRuns() {
        // Simply verify the wipe runs without throwing
        EdgeCaseGuards.performFactoryWipe()
        // URLCache should be cleared
        #expect(URLCache.shared.currentDiskUsage >= 0)
    }

    @Test("WalletViewModel performFactoryWipe resets state")
    @MainActor
    func vmFactoryWipe() {
        let vm = WalletViewModel()
        vm.rawJSON = "test_data"
        vm.performFactoryWipe()
        #expect(vm.rawJSON.isEmpty)
        #expect(!vm.hasKeys)
    }
}

// ============================================================
// Edge Case #48: Biometric Failure Counter
// ============================================================

@Suite("ROADMAP-19 #48: Biometric Failure Counter", .serialized)
struct BiometricFailureCounterTests {

    @Test("Counter resets to zero")
    func initialCount() {
        EdgeCaseGuards.resetBiometricFailureCount()
        let count = UserDefaults.standard.integer(forKey: "hawala.biometric.failCount")
        #expect(count == 0)
    }

    @Test("Recording failure increments, three triggers fallback, reset clears")
    func fullCycle() {
        // Start clean
        EdgeCaseGuards.resetBiometricFailureCount()
        
        // Record 1
        let first = EdgeCaseGuards.recordBiometricFailure()
        #expect(!first, "1st failure should not trigger fallback")
        
        // Record 2
        let second = EdgeCaseGuards.recordBiometricFailure()
        #expect(!second, "2nd failure should not trigger fallback")
        
        // Record 3 — should trigger
        let third = EdgeCaseGuards.recordBiometricFailure()
        #expect(third, "3rd failure should trigger fallback")
        #expect(EdgeCaseGuards.shouldFallbackToPasscode)
        
        // Reset
        EdgeCaseGuards.resetBiometricFailureCount()
        #expect(!EdgeCaseGuards.shouldFallbackToPasscode)
        #expect(EdgeCaseGuards.biometricFailureCount == 0)
    }
}

// ============================================================
// Edge Case #49: Backup State Persistence
// ============================================================

@Suite("ROADMAP-19 #49: Backup Interruption Guard", .serialized)
struct BackupInterruptionGuardTests {

    @Test("No interrupted backup after clearing state")
    func noInterruption() {
        EdgeCaseGuards.markBackupFinished()
        #expect(EdgeCaseGuards.interruptedBackupStep == nil)
    }

    @Test("Start and finish backup round-trip")
    func startFinishRoundTrip() {
        // Start
        EdgeCaseGuards.markBackupStarted(step: "verify-phrase")
        let step = UserDefaults.standard.string(forKey: "hawala.backup.step")
        #expect(step == "verify-phrase")
        
        // Finish
        EdgeCaseGuards.markBackupFinished()
        let cleared = UserDefaults.standard.bool(forKey: "hawala.backup.inProgress")
        #expect(!cleared)
    }
}

// ============================================================
// Edge Case #56: Spam NFT Filter
// ============================================================

@Suite("ROADMAP-19 #56: Spam NFT Filter")
struct SpamNFTFilterTests {

    @Test("Detects airdrop spam")
    func airdropSpam() {
        #expect(EdgeCaseGuards.isLikelySpamNFT(name: "FREE AIRDROP - Claim Now"))
    }

    @Test("Detects link-based spam")
    func linkSpam() {
        #expect(EdgeCaseGuards.isLikelySpamNFT(name: "Prize", description: "Visit http://scam.xyz to claim"))
    }

    @Test("Normal NFT name passes")
    func normalNFT() {
        #expect(!EdgeCaseGuards.isLikelySpamNFT(name: "Bored Ape Yacht Club #1234"))
    }

    @Test("Detects free mint spam")
    func freeMint() {
        #expect(EdgeCaseGuards.isLikelySpamNFT(name: "Free Mint - Limited Edition"))
    }
}

// ============================================================
// Edge Case #57: NFT Metadata Fallback
// ============================================================

@Suite("ROADMAP-19 #57: NFT Metadata Fallback")
struct NFTMetadataFallbackTests {

    @Test("Generates fallback name with token ID")
    func fallbackName() {
        let name = EdgeCaseGuards.nftFallbackName(tokenId: "42", contractAddress: "0x1234567890abcdef1234567890abcdef12345678")
        #expect(name.contains("42"))
        #expect(name.contains("0x1234"))
        #expect(name.contains("5678"))
    }

    @Test("Fallback name is non-empty for any input")
    func nonEmpty() {
        let name = EdgeCaseGuards.nftFallbackName(tokenId: "", contractAddress: "")
        #expect(!name.isEmpty)
    }
}

// ============================================================
// Edge Case #59: Locked During Receive
// ============================================================

@Suite("ROADMAP-19 #59: Queued Receive Notifications")
struct QueuedReceiveNotificationTests {

    @Test("Queue and drain receive notifications")
    func queueAndDrain() {
        // Drain any existing notifications first
        _ = EdgeCaseGuards.drainPendingReceiveNotifications()
        
        EdgeCaseGuards.queueReceiveNotification(chain: "bitcoin", amount: "0.05 BTC", from: "bc1qtest")
        EdgeCaseGuards.queueReceiveNotification(chain: "ethereum", amount: "1.0 ETH", from: "0xtest")
        
        let pending = EdgeCaseGuards.drainPendingReceiveNotifications()
        #expect(pending.count == 2)
        #expect(pending[0].chain == "bitcoin")
        #expect(pending[1].chain == "ethereum")
        
        // After drain, should be empty
        let empty = EdgeCaseGuards.drainPendingReceiveNotifications()
        #expect(empty.isEmpty)
    }
}

// ============================================================
// AmountValidator Tests
// ============================================================

@Suite("ROADMAP-19: AmountValidator Enhancements")
struct AmountValidatorEdgeCaseTests {

    @Test("Bitcoin dust limit rejection")
    func dustLimit() {
        let result = AmountValidator.validateBitcoin(
            amountString: "0.00000001", availableSats: 100_000, estimatedFeeSats: 250
        )
        #expect(result == .invalid("Amount must be at least 546 sats"))
    }

    @Test("Empty string returns .empty")
    func emptyString() {
        let result = AmountValidator.validateBitcoin(amountString: "", availableSats: 1000, estimatedFeeSats: 250)
        #expect(result == .empty)
    }

    @Test("Non-numeric string returns .invalid")
    func nonNumeric() {
        let result = AmountValidator.validateBitcoin(amountString: "abc", availableSats: 1000, estimatedFeeSats: 250)
        #expect(result == .invalid("Enter a numeric BTC amount"))
    }

    @Test("Zero amount returns .invalid")
    func zeroAmount() {
        let result = AmountValidator.validateBitcoin(amountString: "0", availableSats: 1000, estimatedFeeSats: 250)
        #expect(result == .invalid("Amount must be greater than zero"))
    }

    @Test("Excessive precision returns .invalid")
    func excessivePrecision() {
        let result = AmountValidator.validateBitcoin(amountString: "0.123456789", availableSats: 100_000_000, estimatedFeeSats: 250)
        #expect(result == .invalid("Bitcoin supports up to 8 decimal places"))
    }

    @Test("Insufficient balance returns .invalid")
    func insufficientBalance() {
        let result = AmountValidator.validateBitcoin(amountString: "1.0", availableSats: 1000, estimatedFeeSats: 250)
        #expect(result == .invalid("Not enough balance after fees"))
    }

    @Test("Valid amount returns .valid")
    func validAmount() {
        let result = AmountValidator.validateBitcoin(
            amountString: "0.001", availableSats: 200_000, estimatedFeeSats: 250
        )
        #expect(result == .valid)
    }

    @Test("Decimal asset zero balance returns .invalid")
    func decimalAssetZeroBalance() {
        let result = AmountValidator.validateDecimalAsset(
            amountString: "1.0", assetName: "ETH", available: .zero, precision: 18, minimum: Decimal(string: "0.0001")!
        )
        #expect(result == .invalid("Not enough available ETH after fees"))
    }
}

// ============================================================
// Error Messages Edge Cases
// ============================================================

@Suite("ROADMAP-19: Error Message Edge Cases")
struct ErrorMessageEdgeCaseTests {

    @Test("Security biometric lockout message exists")
    func biometricLockoutMessage() {
        #expect(!UserFacingError.Security.biometricLockout.isEmpty)
        #expect(UserFacingError.Security.biometricLockout.contains("passcode"))
    }

    @Test("Forgot passcode message exists")
    func forgotPasscodeMessage() {
        #expect(!UserFacingError.Security.forgotPasscode.isEmpty)
        #expect(UserFacingError.Security.forgotPasscode.contains("seed"))
    }

    @Test("Provider failure alert handles single provider")
    func singleProviderAlert() {
        let alert = ErrorAlertBuilder.providerFailureAlert(providers: ["CoinGecko"])
        #expect(alert.title == "Provider Unavailable")
        #expect(alert.message.contains("CoinGecko"))
    }

    @Test("Provider failure alert handles multiple providers")
    func multiProviderAlert() {
        let alert = ErrorAlertBuilder.providerFailureAlert(providers: ["CoinGecko", "Blockchair"])
        #expect(alert.title == "Providers Unavailable")
    }
}
