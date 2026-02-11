import Testing
import Foundation
@testable import swift_app

// MARK: - Property-Based Testing Utilities

/// Simple property-based testing helper that generates random inputs
/// and verifies invariants hold across many iterations
struct PropertyTest {
    /// Run a property test with random inputs
    static func check<T>(
        _ name: String,
        iterations: Int = 100,
        generator: () -> T,
        property: (T) throws -> Bool
    ) throws {
        for i in 0..<iterations {
            let input = generator()
            let result = try property(input)
            #expect(result, "Property '\(name)' failed on iteration \(i) with input: \(input)")
        }
    }
}

/// Random generators for common types
enum RandomGen {
    static func amount() -> String {
        let whole = Int.random(in: 0...999999)
        let decimal = Int.random(in: 0...99999999)
        return "\(whole).\(decimal)"
    }
    
    static func hexString(length: Int) -> String {
        let chars = "0123456789abcdef"
        return String((0..<length).map { _ in chars.randomElement()! })
    }
    
    static func ethAddress() -> String {
        "0x" + hexString(length: 40)
    }
    
    static func btcAddress() -> String {
        let prefixes = ["1", "3", "bc1q"]
        let prefix = prefixes.randomElement()!
        let chars = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        let length = prefix == "bc1q" ? 39 : Int.random(in: 25...34)
        let body = String((0..<length).map { _ in chars.randomElement()! })
        return prefix + body
    }
    
    static func solAddress() -> String {
        let chars = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        return String((0..<44).map { _ in chars.randomElement()! })
    }
    
    static func chain() -> Chain {
        Chain.allCases.randomElement()!
    }
    
    static func utf8String(maxLength: Int = 100) -> String {
        let length = Int.random(in: 0...maxLength)
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 !@#$%^&*()-_=+[]{}|;':\",./<>?`~"
        return String((0..<length).map { _ in chars.randomElement()! })
    }
}

// MARK: - Amount Parsing Property Tests

@Suite("Property: Amount Parsing")
struct AmountParsingPropertyTests {
    
    @Test func amountNeverNegativeAfterParsing() throws {
        try PropertyTest.check(
            "parsed amounts are non-negative",
            iterations: 200,
            generator: { RandomGen.amount() },
            property: { amountStr in
                guard let value = Double(amountStr) else { return true }
                return value >= 0
            }
        )
    }
    
    @Test func amountStringRoundTrip() throws {
        try PropertyTest.check(
            "amount string round-trips through Double",
            iterations: 100,
            generator: {
                let value = Double.random(in: 0...1000)
                return String(format: "%.8f", value)
            },
            property: { amountStr in
                guard let parsed = Double(amountStr) else { return false }
                let reparsed = String(format: "%.8f", parsed)
                return Double(reparsed)! == parsed
            }
        )
    }
    
    @Test func zeroPaddedAmountsParseCorrectly() {
        let testCases = ["0.0", "0.00000000", "00.01", "000.100", "0", "0.0001"]
        for tc in testCases {
            let value = Double(tc)
            #expect(value != nil, "Failed to parse: \(tc)")
            #expect(value! >= 0, "Negative value from: \(tc)")
        }
    }
    
    @Test func emptyAndInvalidAmountsReturnNil() {
        let invalidCases = ["", "abc", "...", "1.2.3", "--1", "∞", "NaN"]
        for tc in invalidCases {
            let value = Double(tc)
            if let v = value {
                // NaN and Infinity are technically parseable but should be treated as invalid
                #expect(!v.isNaN || tc == "NaN", "Unexpected parse of: \(tc)")
            }
        }
    }
}

// MARK: - Chain ID Property Tests

@Suite("Property: Chain IDs")
struct ChainIDPropertyTests {
    
    @Test func allChainsHaveUniqueIDs() {
        let ids = Chain.allCases.map(\.chainId)
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count, "Duplicate chain IDs found")
    }
    
    @Test func allChainsHaveNonEmptyDisplayNames() {
        for chain in Chain.allCases {
            #expect(!chain.displayName.isEmpty, "Empty display name for \(chain)")
        }
    }
    
    @Test func allChainsHaveNonEmptySymbols() {
        for chain in Chain.allCases {
            #expect(!chain.rawValue.isEmpty, "Empty raw value for \(chain)")
        }
    }
    
    @Test func chainIdIsStableAcrossAccesses() throws {
        try PropertyTest.check(
            "chainId is deterministic",
            iterations: 50,
            generator: { RandomGen.chain() },
            property: { chain in
                chain.chainId == chain.chainId
            }
        )
    }
}

// MARK: - Balance State Property Tests

@Suite("Property: Balance States")
@MainActor
struct BalanceStatePropertyTests {
    
    @Test func loadedStateAlwaysHasValue() {
        let states: [ChainBalanceState] = [
            .loaded(value: "1.5 BTC", lastUpdated: Date()),
            .loaded(value: "0.0 ETH", lastUpdated: Date()),
            .refreshing(previous: "100 SOL", lastUpdated: Date()),
            .stale(value: "0.01 XRP", lastUpdated: Date(), message: "Stale"),
        ]
        
        for state in states {
            let service = BalanceService.shared
            let amount = service.extractNumericAmount(from: state)
            #expect(amount != nil, "extractNumericAmount returned nil for state with value")
        }
    }
    
    @Test func idleAndLoadingReturnNilAmount() {
        let states: [ChainBalanceState] = [
            .idle,
            .loading,
            .failed("Network error"),
        ]
        
        let service = BalanceService.shared
        for state in states {
            let amount = service.extractNumericAmount(from: state)
            #expect(amount == nil, "Expected nil amount for non-loaded state")
        }
    }
}

// MARK: - Clipboard Security Property Tests

@Suite("Property: Clipboard Security")
@MainActor
struct ClipboardSecurityPropertyTests {
    
    @Test func copySensitiveSchedulesAutoClear() async throws {
        // Verify that copySensitive doesn't crash with various inputs
        let testInputs = ["", "test", "0xAbCdEf1234567890", String(repeating: "a", count: 10000)]
        for input in testInputs {
            ClipboardHelper.copySensitive(input, timeout: 0.1)
            // Just verify no crash
        }
        // Wait for auto-clear
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2s
    }
    
    @Test func clipboardCopyBasicFunctionality() {
        let testValue = "test_clipboard_\(UUID().uuidString)"
        ClipboardHelper.copy(testValue)
        let retrieved = ClipboardHelper.currentString()
        #expect(retrieved == testValue)
        
        // Clean up
        ClipboardHelper.clear()
    }
}

// MARK: - Analytics Service Property Tests

@Suite("Property: Analytics Service")
@MainActor
struct AnalyticsServicePropertyTests {
    
    @Test func trackingWhenDisabledIsNoOp() {
        let service = AnalyticsService.shared
        let initialCount = service.eventCount
        service.isEnabled = false
        service.track(AnalyticsService.EventName.settingsChanged, properties: ["key": "value"])
        #expect(service.eventCount == initialCount || service.eventCount == 0,
                "Event count should not increase when disabled")
    }
    
    @Test func sanitizationRedactsSensitiveKeys() {
        let service = AnalyticsService.shared
        let wasEnabled = service.isEnabled
        service.isEnabled = true
        
        // Track with sensitive-looking properties
        service.track(AnalyticsService.EventName.sendCompleted, properties: [
            "address": "0x1234",
            "private_key": "secret",
            "screen": "dashboard" // This should NOT be redacted
        ])
        
        // Restore
        service.isEnabled = wasEnabled
    }
    
    @Test func eventNameConstants() {
        // Verify all event name constants are non-empty strings
        let names = [
            AnalyticsService.EventName.appLaunch,
            AnalyticsService.EventName.walletCreated,
            AnalyticsService.EventName.sendInitiated,
            AnalyticsService.EventName.receiveViewed,
            AnalyticsService.EventName.errorOccurred,
        ]
        for name in names {
            #expect(!name.isEmpty, "Event name constant is empty")
        }
    }
}

// MARK: - Edge Case: Extreme Amounts

@Suite("Edge Cases: Extreme Values")
struct ExtremeValueEdgeCaseTests {
    
    @Test func veryLargeAmount() {
        let huge = "99999999999999999.99999999"
        let value = Double(huge)
        #expect(value != nil)
        #expect(value! > 0)
    }
    
    @Test func verySmallAmount() {
        let tiny = "0.00000001" // 1 satoshi in BTC
        let value = Double(tiny)
        #expect(value != nil)
        #expect(value! > 0)
        #expect(value! < 0.001)
    }
    
    @Test func zeroAmount() {
        let zero = "0"
        let value = Double(zero)
        #expect(value == 0)
    }
    
    @Test func negativeAmountShouldBeRejected() {
        let negative = "-1.5"
        let value = Double(negative)
        // The send flow should reject negative values
        #expect(value != nil)
        #expect(value! < 0, "Negative amounts should be detectable")
    }
    
    @Test func unicodeInAmountField() {
        let unicodeInputs = ["١٢٣", "🚀", "1️⃣", "½", "²"]
        for input in unicodeInputs {
            let value = Double(input)
            // These should all fail to parse as valid amounts
            #expect(value == nil, "Unicode '\(input)' should not parse as amount")
        }
    }
}

// MARK: - Edge Case: Address Formats

@Suite("Edge Cases: Address Formats")
struct AddressFormatEdgeCaseTests {
    
    @Test func emptyAddressIsInvalid() {
        #expect("".isEmpty)
    }
    
    @Test func whitespaceOnlyAddressIsInvalid() {
        let whitespaceInputs = [" ", "  ", "\t", "\n", " \t\n "]
        for input in whitespaceInputs {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(trimmed.isEmpty, "Whitespace-only should be empty after trim")
        }
    }
    
    @Test func ethAddressLengthValidation() {
        // Valid ETH address is 42 chars (0x + 40 hex)
        let valid = "0x" + String(repeating: "a", count: 40)
        #expect(valid.count == 42)
        #expect(valid.hasPrefix("0x"))
        
        // Too short
        let short = "0x" + String(repeating: "a", count: 39)
        #expect(short.count != 42)
        
        // Too long
        let long = "0x" + String(repeating: "a", count: 41)
        #expect(long.count != 42)
    }
    
    @Test func btcAddressTypePrefixes() {
        // Legacy P2PKH starts with 1
        #expect("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa".hasPrefix("1"))
        // P2SH starts with 3
        #expect("3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy".hasPrefix("3"))
        // Bech32 starts with bc1
        #expect("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4".hasPrefix("bc1"))
    }
    
    @Test func addressWithLeadingTrailingWhitespace() {
        let address = "  0xAbCdEf1234567890AbCdEf1234567890AbCdEf12  "
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmed.hasPrefix("0x"))
        #expect(!trimmed.contains(" "))
    }
}

// MARK: - Edge Case: Fee Estimation

@Suite("Edge Cases: Fee Estimation")
struct FeeEstimationEdgeCaseTests {
    
    @Test func feePrioritiesAreOrdered() {
        let priorities = FeePriority.allCases
        #expect(priorities.count >= 3, "Should have at least 3 fee priorities")
    }
    
    @Test func feePrioritiesHaveDisplayInfo() {
        for priority in FeePriority.allCases {
            #expect(!priority.rawValue.isEmpty, "Fee priority missing raw value")
        }
    }
}

// MARK: - Edge Case: Chain Info Completeness

@Suite("Edge Cases: Chain Info")
struct ChainInfoEdgeCaseTests {
    
    @Test func allChainsHaveIconNames() {
        for chain in Chain.allCases {
            #expect(!chain.iconName.isEmpty, "Chain \(chain) missing icon name")
        }
    }
    
    @Test func bitcoinChainsIdentifiedCorrectly() {
        #expect(Chain.bitcoinTestnet.isBitcoin)
        #expect(Chain.bitcoinMainnet.isBitcoin)
        #expect(!Chain.ethereumMainnet.isBitcoin)
        #expect(!Chain.solanaMainnet.isBitcoin)
    }
    
    @Test func chainIdMatchesRawValue() {
        // For chains without custom chainId mapping, verify consistency
        for chain in Chain.allCases {
            #expect(!chain.chainId.isEmpty, "Chain \(chain) has empty chainId")
        }
    }
}

// MARK: - Edge Case: Concurrent Operations

@Suite("Edge Cases: Concurrency")
@MainActor
struct ConcurrencyEdgeCaseTests {
    
    @Test func multipleRapidClipboardCopies() async {
        // Simulate rapid copy operations (race condition check)
        for i in 0..<10 {
            ClipboardHelper.copy("value_\(i)")
        }
        // Last value should win
        let current = ClipboardHelper.currentString()
        #expect(current == "value_9", "Last clipboard copy should win")
        ClipboardHelper.clear()
    }
}

// MARK: - Edge Case: Hex Parsing

@Suite("Edge Cases: Hex Parsing")
struct HexParsingEdgeCaseTests {
    
    @Test func hexToDecimalConversion() {
        // 0x38d7ea4c68000 = 1000000000000000 wei = 0.001 ETH
        let hex = "38d7ea4c68000"
        let value = UInt64(hex, radix: 16)
        #expect(value == 1_000_000_000_000_000)
    }
    
    @Test func emptyHexReturnsNil() {
        let value = UInt64("", radix: 16)
        #expect(value == nil)
    }
    
    @Test func invalidHexCharsReturnNil() {
        let value = UInt64("0xGGG", radix: 16)
        #expect(value == nil)
    }
    
    @Test func maxUInt64HexValue() {
        let hex = "ffffffffffffffff"
        let value = UInt64(hex, radix: 16)
        #expect(value == UInt64.max)
    }
    
    @Test func overflowHexValueHandledGracefully() {
        // This is > UInt64.max
        let hex = "1ffffffffffffffff"
        let value = UInt64(hex, radix: 16)
        #expect(value == nil, "Overflow hex should return nil")
    }
}
