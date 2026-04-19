import Testing
import Foundation
@testable import swift_app

// MARK: - ROADMAP-18: Transaction History & Activity Tests

// MARK: - E1: Transaction Models

@Suite("ROADMAP-18: HawalaTransactionEntry Model")
struct HawalaTransactionEntryTests {

    @Test("HawalaTransactionEntry stores all fields")
    func allFields() {
        let entry = HawalaTransactionEntry(
            id: "tx-1",
            type: "Send",
            asset: "Bitcoin",
            amountDisplay: "-0.005 BTC",
            status: "Confirmed",
            timestamp: "Jan 15, 2026",
            sortTimestamp: 1_768_500_000,
            txHash: "abc123",
            chainId: "bitcoin",
            confirmations: 6,
            fee: "0.00001 BTC",
            blockNumber: 900_000,
            counterparty: "bc1qtest"
        )
        #expect(entry.id == "tx-1")
        #expect(entry.type == "Send")
        #expect(entry.asset == "Bitcoin")
        #expect(entry.amountDisplay == "-0.005 BTC")
        #expect(entry.status == "Confirmed")
        #expect(entry.txHash == "abc123")
        #expect(entry.chainId == "bitcoin")
        #expect(entry.confirmations == 6)
        #expect(entry.fee == "0.00001 BTC")
        #expect(entry.blockNumber == 900_000)
        #expect(entry.counterparty == "bc1qtest")
    }

    @Test("confirmationsDisplay formats correctly")
    func confirmationsDisplay() {
        let none = HawalaTransactionEntry(id: "1", type: "Send", asset: "BTC", amountDisplay: "-1", status: "Pending", timestamp: "", sortTimestamp: nil)
        #expect(none.confirmationsDisplay == nil)

        var one = HawalaTransactionEntry(id: "2", type: "Send", asset: "BTC", amountDisplay: "-1", status: "Confirmed", timestamp: "", sortTimestamp: nil)
        one.confirmations = 1
        #expect(one.confirmationsDisplay == "1 confirmation")

        var three = HawalaTransactionEntry(id: "3", type: "Send", asset: "BTC", amountDisplay: "-1", status: "Confirmed", timestamp: "", sortTimestamp: nil)
        three.confirmations = 3
        #expect(three.confirmationsDisplay == "3 confirmations")

        var many = HawalaTransactionEntry(id: "4", type: "Send", asset: "BTC", amountDisplay: "-1", status: "Confirmed", timestamp: "", sortTimestamp: nil)
        many.confirmations = 10
        #expect(many.confirmationsDisplay == "6+ confirmations")
    }

    @Test("explorerURL generates correct URLs per chain")
    func explorerURL() {
        let btc = HawalaTransactionEntry(id: "1", type: "Send", asset: "BTC", amountDisplay: "-1", status: "Confirmed", timestamp: "", sortTimestamp: nil, txHash: "txhash", chainId: "bitcoin")
        #expect(btc.explorerURL?.absoluteString == "https://mempool.space/tx/txhash")

        let eth = HawalaTransactionEntry(id: "2", type: "Send", asset: "ETH", amountDisplay: "-1", status: "Confirmed", timestamp: "", sortTimestamp: nil, txHash: "txhash", chainId: "ethereum")
        #expect(eth.explorerURL?.absoluteString == "https://etherscan.io/tx/txhash")

        let sol = HawalaTransactionEntry(id: "3", type: "Send", asset: "SOL", amountDisplay: "-1", status: "Confirmed", timestamp: "", sortTimestamp: nil, txHash: "txhash", chainId: "solana")
        #expect(sol.explorerURL?.absoluteString == "https://solscan.io/tx/txhash")

        let noChain = HawalaTransactionEntry(id: "4", type: "Send", asset: "BTC", amountDisplay: "-1", status: "Confirmed", timestamp: "", sortTimestamp: nil, txHash: "txhash")
        #expect(noChain.explorerURL == nil)
    }

    @Test("typeColor maps correctly")
    func typeColor() {
        let receive = HawalaTransactionEntry(id: "1", type: "Receive", asset: "BTC", amountDisplay: "+1", status: "Confirmed", timestamp: "", sortTimestamp: nil)
        #expect(receive.typeColor == .receive)

        let send = HawalaTransactionEntry(id: "2", type: "Send", asset: "BTC", amountDisplay: "-1", status: "Confirmed", timestamp: "", sortTimestamp: nil)
        #expect(send.typeColor == .send)

        let swap = HawalaTransactionEntry(id: "3", type: "Swap", asset: "BTC", amountDisplay: "1", status: "Confirmed", timestamp: "", sortTimestamp: nil)
        #expect(swap.typeColor == .swap)
    }

    @Test("statusColor maps correctly")
    func statusColor() {
        let confirmed = HawalaTransactionEntry(id: "1", type: "Send", asset: "BTC", amountDisplay: "-1", status: "Confirmed", timestamp: "", sortTimestamp: nil)
        #expect(confirmed.statusColor == .confirmed)

        let pending = HawalaTransactionEntry(id: "2", type: "Send", asset: "BTC", amountDisplay: "-1", status: "Pending", timestamp: "", sortTimestamp: nil)
        #expect(pending.statusColor == .pending)

        let failed = HawalaTransactionEntry(id: "3", type: "Send", asset: "BTC", amountDisplay: "-1", status: "Failed", timestamp: "", sortTimestamp: nil)
        #expect(failed.statusColor == .failed)
    }

    @Test("HawalaTransactionEntry conforms to Equatable")
    func equatable() {
        let a = HawalaTransactionEntry(id: "1", type: "Send", asset: "BTC", amountDisplay: "-1", status: "Confirmed", timestamp: "Jan 1", sortTimestamp: nil)
        let b = HawalaTransactionEntry(id: "1", type: "Send", asset: "BTC", amountDisplay: "-1", status: "Confirmed", timestamp: "Jan 1", sortTimestamp: nil)
        #expect(a == b)
    }
}

// MARK: - E4: Type Filtering

@Suite("ROADMAP-18: Transaction Type Filtering")
@MainActor
struct TransactionTypeFilterTests {
    static let sampleEntries: [HawalaTransactionEntry] = [
        HawalaTransactionEntry(id: "1", type: "Send", asset: "Bitcoin", amountDisplay: "-0.01 BTC", status: "Confirmed", timestamp: "Jan 1", sortTimestamp: nil, chainId: "bitcoin"),
        HawalaTransactionEntry(id: "2", type: "Received", asset: "Ethereum", amountDisplay: "+1.5 ETH", status: "Confirmed", timestamp: "Jan 2", sortTimestamp: nil, chainId: "ethereum"),
        HawalaTransactionEntry(id: "3", type: "Swap", asset: "Bitcoin", amountDisplay: "0.5 BTC → ETH", status: "Confirmed", timestamp: "Jan 3", sortTimestamp: nil, chainId: "ethereum"),
        HawalaTransactionEntry(id: "4", type: "Approve", asset: "Ethereum", amountDisplay: "Approve USDC", status: "Confirmed", timestamp: "Jan 4", sortTimestamp: nil, chainId: "ethereum"),
        HawalaTransactionEntry(id: "5", type: "Contract", asset: "Ethereum", amountDisplay: "0 ETH", status: "Confirmed", timestamp: "Jan 5", sortTimestamp: nil, chainId: "ethereum"),
    ]

    @Test("Filter by Send returns only sends")
    func filterSend() {
        let result = TransactionHistoryService.filteredEntries(Self.sampleEntries, chain: nil, type: "Send", searchText: "")
        #expect(result.count == 1)
        #expect(result.first?.type == "Send")
    }

    @Test("Filter by Swap returns only swaps")
    func filterSwap() {
        let result = TransactionHistoryService.filteredEntries(Self.sampleEntries, chain: nil, type: "Swap", searchText: "")
        #expect(result.count == 1)
        #expect(result.first?.type == "Swap")
    }

    @Test("Filter by Approve returns only approvals")
    func filterApprove() {
        let result = TransactionHistoryService.filteredEntries(Self.sampleEntries, chain: nil, type: "Approve", searchText: "")
        #expect(result.count == 1)
        #expect(result.first?.type == "Approve")
    }

    @Test("Filter All Types returns all entries")
    func filterAll() {
        let result = TransactionHistoryService.filteredEntries(Self.sampleEntries, chain: nil, type: nil, searchText: "")
        #expect(result.count == 5)
    }
}

// MARK: - E5: Token Filtering

@Suite("ROADMAP-18: Token Filtering")
@MainActor
struct TokenFilterTests {
    static let sampleEntries: [HawalaTransactionEntry] = [
        HawalaTransactionEntry(id: "1", type: "Send", asset: "Bitcoin", amountDisplay: "-0.01 BTC", status: "Confirmed", timestamp: "Jan 1", sortTimestamp: nil, chainId: "bitcoin"),
        HawalaTransactionEntry(id: "2", type: "Received", asset: "Ethereum", amountDisplay: "+1 ETH", status: "Confirmed", timestamp: "Jan 2", sortTimestamp: nil, chainId: "ethereum"),
        HawalaTransactionEntry(id: "3", type: "Send", asset: "Bitcoin", amountDisplay: "-0.5 BTC", status: "Confirmed", timestamp: "Jan 3", sortTimestamp: nil, chainId: "bitcoin"),
        HawalaTransactionEntry(id: "4", type: "Received", asset: "USDC", amountDisplay: "+100 USDC", status: "Confirmed", timestamp: "Jan 4", sortTimestamp: nil, chainId: "ethereum"),
    ]

    @Test("uniqueTokens returns sorted unique asset names")
    func uniqueTokens() {
        let tokens = TransactionHistoryService.uniqueTokens(from: Self.sampleEntries)
        #expect(tokens == ["Bitcoin", "Ethereum", "USDC"])
    }

    @Test("Filter by token returns only matching asset")
    func filterByToken() {
        let result = TransactionHistoryService.filteredEntries(Self.sampleEntries, chain: nil, type: nil, token: "Bitcoin", searchText: "")
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.asset == "Bitcoin" })
    }

    @Test("Filter by token nil returns all entries")
    func filterByTokenNil() {
        let result = TransactionHistoryService.filteredEntries(Self.sampleEntries, chain: nil, type: nil, token: nil, searchText: "")
        #expect(result.count == 4)
    }

    @Test("Combined chain + token filter")
    func combinedFilter() {
        let result = TransactionHistoryService.filteredEntries(Self.sampleEntries, chain: "ethereum", type: nil, token: "USDC", searchText: "")
        #expect(result.count == 1)
        #expect(result.first?.asset == "USDC")
    }
}

// MARK: - E6: Date Range Filtering

@Suite("ROADMAP-18: Date Range Filter")
@MainActor
struct DateRangeFilterTests {

    @Test("TransactionDateRange has all expected cases")
    func allCases() {
        let cases = TransactionDateRange.allCases
        #expect(cases.count == 6)
        #expect(cases.contains(.all))
        #expect(cases.contains(.today))
        #expect(cases.contains(.week))
        #expect(cases.contains(.month))
        #expect(cases.contains(.quarter))
        #expect(cases.contains(.year))
    }

    @Test("cutoffDate is nil for .all")
    func cutoffAll() {
        #expect(TransactionDateRange.all.cutoffDate == nil)
    }

    @Test("cutoffDate is non-nil for other ranges")
    func cutoffNonNil() {
        #expect(TransactionDateRange.today.cutoffDate != nil)
        #expect(TransactionDateRange.week.cutoffDate != nil)
        #expect(TransactionDateRange.month.cutoffDate != nil)
        #expect(TransactionDateRange.quarter.cutoffDate != nil)
        #expect(TransactionDateRange.year.cutoffDate != nil)
    }

    @Test("cutoffDate ordering: today > week > month > quarter > year")
    func cutoffOrdering() {
        let today = TransactionDateRange.today.cutoffDate!
        let week = TransactionDateRange.week.cutoffDate!
        let month = TransactionDateRange.month.cutoffDate!
        let quarter = TransactionDateRange.quarter.cutoffDate!
        let year = TransactionDateRange.year.cutoffDate!
        #expect(today > week)
        #expect(week > month)
        #expect(month > quarter)
        #expect(quarter > year)
    }

    @Test("Date filter excludes old transactions")
    func dateFilterExcludes() {
        let now = Date().timeIntervalSince1970
        let oldTimestamp = Date().addingTimeInterval(-365 * 24 * 3600).timeIntervalSince1970 // 1 year ago
        let entries: [HawalaTransactionEntry] = [
            HawalaTransactionEntry(id: "recent", type: "Send", asset: "BTC", amountDisplay: "-1", status: "Confirmed", timestamp: "Today", sortTimestamp: now),
            HawalaTransactionEntry(id: "old", type: "Send", asset: "BTC", amountDisplay: "-1", status: "Confirmed", timestamp: "Last Year", sortTimestamp: oldTimestamp),
        ]

        let weekResult = TransactionHistoryService.filteredEntries(entries, chain: nil, type: nil, token: nil, dateRange: .week, searchText: "")
        #expect(weekResult.count == 1)
        #expect(weekResult.first?.id == "recent")
    }

    @Test("Date filter .all returns everything")
    func dateFilterAll() {
        let entries: [HawalaTransactionEntry] = [
            HawalaTransactionEntry(id: "1", type: "Send", asset: "BTC", amountDisplay: "-1", status: "Confirmed", timestamp: "Today", sortTimestamp: Date().timeIntervalSince1970),
            HawalaTransactionEntry(id: "2", type: "Send", asset: "BTC", amountDisplay: "-1", status: "Confirmed", timestamp: "Old", sortTimestamp: 1_000_000_000),
        ]

        let result = TransactionHistoryService.filteredEntries(entries, chain: nil, type: nil, token: nil, dateRange: .all, searchText: "")
        #expect(result.count == 2)
    }

    @Test("TransactionDateRange labels are non-empty")
    func labels() {
        for range in TransactionDateRange.allCases {
            #expect(!range.label.isEmpty)
        }
    }

    @Test("TransactionDateRange is Identifiable")
    func identifiable() {
        for range in TransactionDateRange.allCases {
            #expect(!range.id.isEmpty)
        }
    }
}

// MARK: - E7+E8: Pending Grouping & Status

@Suite("ROADMAP-18: Transaction Status Colors")
struct TransactionStatusTests {

    @Test("TransactionTypeColor has all expected cases")
    func typeColors() {
        let _ = TransactionTypeColor.receive
        let _ = TransactionTypeColor.send
        let _ = TransactionTypeColor.swap
        let _ = TransactionTypeColor.neutral
    }

    @Test("TransactionStatusColor has all expected cases")
    func statusColors() {
        let _ = TransactionStatusColor.confirmed
        let _ = TransactionStatusColor.pending
        let _ = TransactionStatusColor.failed
        let _ = TransactionStatusColor.neutral
    }
}

// MARK: - E10: Failed Transaction Explanation

@Suite("ROADMAP-18: Failed Transaction Explanation")
struct FailedTransactionExplanationTests {

    @Test("explanation returns nil for confirmed transactions")
    func confirmedReturnsNil() {
        let result = TransactionFailureReason.explanation(status: "Confirmed", chainId: "ethereum", fee: nil)
        #expect(result == nil)
    }

    @Test("explanation returns nil for pending transactions")
    func pendingReturnsNil() {
        let result = TransactionFailureReason.explanation(status: "Pending", chainId: "bitcoin", fee: nil)
        #expect(result == nil)
    }

    @Test("explanation returns result for failed EVM transaction")
    func failedEVM() {
        let result = TransactionFailureReason.explanation(status: "Failed", chainId: "ethereum", fee: nil)
        #expect(result != nil)
        #expect(result!.reason.contains("Failed"))
        #expect(result!.explanation.contains("reverted") || result!.explanation.contains("gas"))
        #expect(!result!.suggestion.isEmpty)
        #expect(!result!.icon.isEmpty)
    }

    @Test("explanation returns gas-specific message when fee mentions out of gas")
    func outOfGas() {
        let result = TransactionFailureReason.explanation(status: "Failed", chainId: "ethereum", fee: "Out of gas")
        #expect(result != nil)
        #expect(result!.reason.contains("gas"))
        #expect(result!.explanation.contains("gas"))
    }

    @Test("explanation returns generic for non-EVM chains")
    func failedNonEVM() {
        let result = TransactionFailureReason.explanation(status: "Failed", chainId: "bitcoin", fee: nil)
        #expect(result != nil)
        #expect(result!.reason.contains("Failed"))
        #expect(!result!.suggestion.isEmpty)
    }

    @Test("explanation handles case-insensitive status")
    func caseInsensitive() {
        let result = TransactionFailureReason.explanation(status: "failed", chainId: "ethereum", fee: nil)
        #expect(result != nil)
    }

    @Test("TransactionFailureExplanation has all required fields")
    func structFields() {
        let explanation = TransactionFailureExplanation(
            reason: "Test Reason",
            explanation: "Test Explanation",
            suggestion: "Test Suggestion",
            icon: "xmark.circle"
        )
        #expect(explanation.reason == "Test Reason")
        #expect(explanation.explanation == "Test Explanation")
        #expect(explanation.suggestion == "Test Suggestion")
        #expect(explanation.icon == "xmark.circle")
    }
}

// MARK: - E11: Retry Failed Transaction

@Suite("ROADMAP-18: Retry Failed Transaction")
@MainActor
struct RetryTransactionTests {

    @Test("TransactionDetailSheet initializes with nil retry callback")
    func detailSheetNoRetry() {
        let entry = HawalaTransactionEntry(id: "1", type: "Send", asset: "BTC", amountDisplay: "-1", status: "Failed", timestamp: "", sortTimestamp: nil)
        let _ = TransactionDetailSheet(transaction: entry)
    }

    @Test("TransactionDetailSheet accepts retry callback")
    func detailSheetWithRetry() {
        let entry = HawalaTransactionEntry(id: "1", type: "Send", asset: "BTC", amountDisplay: "-1", status: "Failed", timestamp: "", sortTimestamp: nil)
        var retried = false
        let _ = TransactionDetailSheet(transaction: entry, onRetryTransaction: { _ in retried = true })
        // Callback was set (not invoked yet)
        #expect(!retried)
    }
}

// MARK: - E12+E13+E14: Transaction Detail, Copy, Explorer

@Suite("ROADMAP-18: Transaction Detail Features")
@MainActor
struct TransactionDetailFeatureTests {

    @Test("TransactionDetailViewModern initializes correctly")
    func detailViewInit() {
        let item = TransactionDisplayItem(
            id: "1", txHash: "abc", chainId: "bitcoin", chainName: "Bitcoin",
            type: .send, status: .confirmed, amount: 0.5, symbol: "BTC",
            fromAddress: "addr1", toAddress: "addr2", fee: 0.0001,
            timestamp: Date(), confirmations: 6, blockHeight: 900000
        )
        let _ = TransactionDetailViewModern(transaction: item)
    }

    @Test("TransactionDetailSheet displays explorer link for known chains")
    func explorerLink() {
        let entry = HawalaTransactionEntry(
            id: "1", type: "Send", asset: "Bitcoin", amountDisplay: "-0.5 BTC",
            status: "Confirmed", timestamp: "Jan 1", sortTimestamp: nil,
            txHash: "abc123", chainId: "bitcoin"
        )
        #expect(entry.explorerURL != nil)
        #expect(entry.explorerURL!.absoluteString.contains("mempool.space"))
    }

    @Test("explorerURL for Ethereum Sepolia")
    func explorerSepolia() {
        let entry = HawalaTransactionEntry(
            id: "1", type: "Send", asset: "ETH", amountDisplay: "-0.1 ETH",
            status: "Confirmed", timestamp: "Jan 1", sortTimestamp: nil,
            txHash: "0xabc", chainId: "ethereum-sepolia"
        )
        #expect(entry.explorerURL?.absoluteString.contains("sepolia.etherscan.io") == true)
    }
}

// MARK: - E15+E16: CSV Export

@Suite("ROADMAP-18: CSV Export")
@MainActor
struct CSVExportTests {

    @Test("buildCSV generates header row")
    func csvHeader() {
        let service = TransactionHistoryService.shared
        let csv = service.buildCSV(from: [])
        #expect(csv.contains("Date,Type,Asset,Amount,Status,Fee,Confirmations,TX Hash,Chain"))
    }

    @Test("buildCSV includes transaction data")
    func csvData() {
        let service = TransactionHistoryService.shared
        let entries = [
            HawalaTransactionEntry(
                id: "1", type: "Send", asset: "Bitcoin", amountDisplay: "-0.5 BTC",
                status: "Confirmed", timestamp: "Jan 15, 2026",
                sortTimestamp: nil, txHash: "abc123", chainId: "bitcoin",
                confirmations: 6, fee: "0.00001 BTC"
            )
        ]
        let csv = service.buildCSV(from: entries)
        #expect(csv.contains("Send"))
        #expect(csv.contains("Bitcoin"))
        #expect(csv.contains("abc123"))
        #expect(csv.contains("Confirmed"))
    }

    @Test("buildCSV handles multiple entries")
    func csvMultiple() {
        let service = TransactionHistoryService.shared
        let entries = [
            HawalaTransactionEntry(id: "1", type: "Send", asset: "BTC", amountDisplay: "-1", status: "Confirmed", timestamp: "Jan 1", sortTimestamp: nil),
            HawalaTransactionEntry(id: "2", type: "Receive", asset: "ETH", amountDisplay: "+2", status: "Pending", timestamp: "Jan 2", sortTimestamp: nil),
        ]
        let csv = service.buildCSV(from: entries)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 3) // header + 2 rows
    }

    @Test("buildCSV escapes commas in fields")
    func csvEscaping() {
        let service = TransactionHistoryService.shared
        let entries = [
            HawalaTransactionEntry(id: "1", type: "Send", asset: "Bitcoin", amountDisplay: "1,000 BTC", status: "Confirmed", timestamp: "Jan 15, 2026", sortTimestamp: nil)
        ]
        let csv = service.buildCSV(from: entries)
        // Fields should be quoted
        #expect(csv.contains("\""))
    }
}

// MARK: - Combined Filter Tests

@Suite("ROADMAP-18: Combined Filtering")
@MainActor
struct CombinedFilterTests {
    static let entries: [HawalaTransactionEntry] = [
        HawalaTransactionEntry(id: "1", type: "Send", asset: "Bitcoin", amountDisplay: "-0.01 BTC", status: "Confirmed", timestamp: "Jan 1", sortTimestamp: Date().timeIntervalSince1970, chainId: "bitcoin"),
        HawalaTransactionEntry(id: "2", type: "Received", asset: "Ethereum", amountDisplay: "+1 ETH", status: "Confirmed", timestamp: "Jan 2", sortTimestamp: Date().timeIntervalSince1970, chainId: "ethereum"),
        HawalaTransactionEntry(id: "3", type: "Swap", asset: "USDC", amountDisplay: "100 USDC", status: "Confirmed", timestamp: "Jan 3", sortTimestamp: Date().timeIntervalSince1970, chainId: "ethereum"),
        HawalaTransactionEntry(id: "4", type: "Send", asset: "Ethereum", amountDisplay: "-0.5 ETH", status: "Failed", timestamp: "Jan 4", sortTimestamp: Date().addingTimeInterval(-365 * 86400).timeIntervalSince1970, chainId: "ethereum"),
    ]

    @Test("Chain + type filter")
    func chainAndType() {
        let result = TransactionHistoryService.filteredEntries(Self.entries, chain: "ethereum", type: "Received", searchText: "")
        #expect(result.count == 1)
        #expect(result.first?.id == "2")
    }

    @Test("Chain + token filter")
    func chainAndToken() {
        let result = TransactionHistoryService.filteredEntries(Self.entries, chain: "ethereum", type: nil, token: "USDC", searchText: "")
        #expect(result.count == 1)
        #expect(result.first?.id == "3")
    }

    @Test("Token + date filter")
    func tokenAndDate() {
        let result = TransactionHistoryService.filteredEntries(Self.entries, chain: nil, type: nil, token: "Ethereum", dateRange: .month, searchText: "")
        // Only the recent Ethereum entry (id 2) should match, not old one (id 4)
        #expect(result.count == 1)
        #expect(result.first?.id == "2")
    }

    @Test("Search text filter")
    func searchText() {
        let result = TransactionHistoryService.filteredEntries(Self.entries, chain: nil, type: nil, searchText: "USDC")
        #expect(result.count == 1)
        #expect(result.first?.id == "3")
    }

    @Test("All filters combined")
    func allCombined() {
        let result = TransactionHistoryService.filteredEntries(
            Self.entries,
            chain: "ethereum",
            type: "Received",
            token: "Ethereum",
            dateRange: .all,
            searchText: "ETH"
        )
        #expect(result.count == 1)
        #expect(result.first?.id == "2")
    }

    @Test("No results when filters are too restrictive")
    func noResults() {
        let result = TransactionHistoryService.filteredEntries(Self.entries, chain: "bitcoin", type: "Swap", searchText: "")
        #expect(result.isEmpty)
    }
}

// MARK: - UI Component Tests

@Suite("ROADMAP-18: UI Components")
@MainActor
struct TransactionUITests {

    @Test("TransactionFilter has expected cases")
    func filterCases() {
        let all = TransactionFilter.allCases
        #expect(all.count == 5)
        #expect(all.contains(.all))
        #expect(all.contains(.pending))
        #expect(all.contains(.sent))
        #expect(all.contains(.received))
        #expect(all.contains(.spam))
    }

    @Test("TransactionFilter icons are valid")
    func filterIcons() {
        for filter in TransactionFilter.allCases {
            #expect(!filter.icon.isEmpty)
        }
    }

    @Test("FilterPill initializes without crash")
    func filterPillInit() {
        let _ = FilterPill(filter: .sent, count: 5, isSelected: true, action: {})
    }

    @Test("TransactionDisplayItem.TransactionStatus has all cases")
    func displayItemStatus() {
        let _ = TransactionDisplayItem.TransactionStatus.pending
        let _ = TransactionDisplayItem.TransactionStatus.confirmed
        let _ = TransactionDisplayItem.TransactionStatus.failed
        let _ = TransactionDisplayItem.TransactionStatus.replaced
        let _ = TransactionDisplayItem.TransactionStatus.cancelled
    }

    @Test("TransactionDisplayItem.TransactionType has all cases")
    func displayItemType() {
        let _ = TransactionDisplayItem.TransactionType.send
        let _ = TransactionDisplayItem.TransactionType.receive
        let _ = TransactionDisplayItem.TransactionType.unknown
    }

    @Test("TransactionDisplayItem formattedAmount formats correctly")
    func formattedAmount() {
        let item = TransactionDisplayItem(
            id: "1", txHash: "abc", chainId: "bitcoin", chainName: "Bitcoin",
            type: .send, status: .confirmed, amount: 0.00005, symbol: "BTC"
        )
        #expect(item.formattedAmount.contains("0.00005"))
    }

    @Test("TransactionDisplayItem title includes address")
    func title() {
        let item = TransactionDisplayItem(
            id: "1", txHash: "abc", chainId: "bitcoin", chainName: "Bitcoin",
            type: .send, status: .confirmed, amount: 0.5, symbol: "BTC",
            toAddress: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"
        )
        #expect(item.title.contains("Sent to"))
    }
}

// MARK: - Unique Chains

@Suite("ROADMAP-18: Unique Chains")
@MainActor
struct UniqueChainsTests {

    @Test("uniqueChains returns sorted unique chain IDs")
    func uniqueChains() {
        let entries = [
            HawalaTransactionEntry(id: "1", type: "Send", asset: "BTC", amountDisplay: "-1", status: "Confirmed", timestamp: "", sortTimestamp: nil, chainId: "bitcoin"),
            HawalaTransactionEntry(id: "2", type: "Send", asset: "ETH", amountDisplay: "-1", status: "Confirmed", timestamp: "", sortTimestamp: nil, chainId: "ethereum"),
            HawalaTransactionEntry(id: "3", type: "Send", asset: "BTC", amountDisplay: "-1", status: "Confirmed", timestamp: "", sortTimestamp: nil, chainId: "bitcoin"),
        ]
        let chains = TransactionHistoryService.uniqueChains(from: entries)
        #expect(chains == ["bitcoin", "ethereum"])
    }

    @Test("uniqueChains skips nil chainIds")
    func skipNilChains() {
        let entries = [
            HawalaTransactionEntry(id: "1", type: "Send", asset: "BTC", amountDisplay: "-1", status: "Confirmed", timestamp: "", sortTimestamp: nil),
        ]
        let chains = TransactionHistoryService.uniqueChains(from: entries)
        #expect(chains.isEmpty)
    }
}
