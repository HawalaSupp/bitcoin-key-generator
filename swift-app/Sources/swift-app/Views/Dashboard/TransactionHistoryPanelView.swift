import SwiftUI

/// Extracted transaction history panel – pending transactions + recent activity.
/// Displayed on the main dashboard.
struct TransactionHistoryPanelView: View {
    // MARK: - Inputs
    let pendingTransactions: [PendingTransactionManager.PendingTransaction]
    let historyEntries: [HawalaTransactionEntry]
    let historyError: String?
    let isHistoryLoading: Bool
    let cardBackgroundColor: Color

    @Binding var historySearchText: String
    @Binding var historyFilterChain: String?
    @Binding var historyFilterType: String?

    // MARK: - Callbacks
    var onRefresh: () -> Void = {}
    var onSpeedUp: (PendingTransactionManager.PendingTransaction) -> Void = { _ in }
    var onCancel: (PendingTransactionManager.PendingTransaction) -> Void = { _ in }
    var onSelectTransaction: (HawalaTransactionEntry) -> Void = { _ in }
    var onExportCSV: () -> Void = {}

    // MARK: - Services (read-only, for display names)
    @ObservedObject private var transactionHistoryService = TransactionHistoryService.shared

    // MARK: - Body
    var body: some View {
        VStack(spacing: 20) {
            pendingTransactionsSection
            transactionHistorySection
        }
    }

    // MARK: - Pending Transactions
    @ViewBuilder
    private var pendingTransactionsSection: some View {
        let pending = pendingTransactions.filter { $0.status == .pending }
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Pending Transactions", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                    Spacer()
                    Text("\(pending.count)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }

                VStack(spacing: 0) {
                    ForEach(pending) { tx in
                        PendingTransactionRow(
                            transaction: tx,
                            onSpeedUp: { onSpeedUp(tx) },
                            onCancel: { onCancel(tx) }
                        )
                        if tx.id != pending.last?.id {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(cardBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
    }

    // MARK: - Transaction History
    private var transactionHistorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header row
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent Activity")
                        .font(.headline)
                    Text("Transaction history and events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    if isHistoryLoading {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if !historyEntries.isEmpty {
                        Menu {
                            Button {
                                onExportCSV()
                            } label: {
                                Label("Export as CSV", systemImage: "tablecells")
                            }
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                                .labelStyle(.titleAndIcon)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .buttonStyle(.link)
                    }

                    Button {
                        onRefresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.link)
                    .disabled(isHistoryLoading)
                }
            }

            // Search & filter bar
            historyFilterBar

            // Content
            historyContent
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - History Content
    @ViewBuilder
    private var historyContent: some View {
        if let historyError {
            errorPlaceholder(historyError)
        } else if isHistoryLoading && historyEntries.isEmpty {
            loadingPlaceholder
        } else if historyEntries.isEmpty {
            emptyPlaceholder
        } else {
            let filtered = filteredHistoryEntries
            if filtered.isEmpty && !historyEntries.isEmpty {
                noMatchPlaceholder
            } else {
                VStack(spacing: 0) {
                    ForEach(filtered) { entry in
                        Button {
                            onSelectTransaction(entry)
                        } label: {
                            TransactionHistoryRow(entry: entry)
                        }
                        .buttonStyle(.plain)

                        if entry.id != filtered.last?.id {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Placeholders
    private func errorPlaceholder(_ msg: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange.opacity(0.6))
            Text("Unable to load history")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(msg)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") { onRefresh() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Fetching your latest transactions…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.largeTitle)
                .foregroundStyle(.secondary.opacity(0.5))
            Text("No transactions yet")
                .font(.subheadline)
                .fontWeight(.medium)
            Text("Your activity will appear here once funds move.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var noMatchPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary.opacity(0.5))
            Text("No matching transactions")
                .font(.subheadline)
                .fontWeight(.medium)
            Text("Try adjusting your search or filters")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Clear Filters") {
                historySearchText = ""
                historyFilterChain = nil
                historyFilterType = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Filter Bar
    private var historyFilterBar: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search transactions…", text: $historySearchText)
                    .textFieldStyle(.plain)
                if !historySearchText.isEmpty {
                    Button {
                        historySearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)

            HStack(spacing: 8) {
                chainFilterMenu
                typeFilterMenu
                Spacer()
                if hasActiveFilters {
                    Button {
                        historySearchText = ""
                        historyFilterChain = nil
                        historyFilterType = nil
                    } label: {
                        HStack(spacing: 4) {
                            Text("Clear")
                            Image(systemName: "xmark")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var chainFilterMenu: some View {
        Menu {
            Button("All Chains") { historyFilterChain = nil }
            Divider()
            ForEach(uniqueHistoryChains, id: \.self) { chain in
                Button(transactionHistoryService.chainDisplayName(chain)) {
                    historyFilterChain = chain
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "link")
                Text(historyFilterChain.map { transactionHistoryService.chainDisplayName($0) } ?? "All Chains")
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(historyFilterChain != nil ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
            .foregroundStyle(historyFilterChain != nil ? Color.accentColor : .primary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var typeFilterMenu: some View {
        Menu {
            Button("All Types") { historyFilterType = nil }
            Divider()
            Button("Received") { historyFilterType = "Received" }
            Button("Sent") { historyFilterType = "Sent" }
            Button("Contract") { historyFilterType = "Contract" }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.left.arrow.right")
                Text(historyFilterType ?? "All Types")
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(historyFilterType != nil ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
            .foregroundStyle(historyFilterType != nil ? Color.accentColor : .primary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filtering Logic
    private var hasActiveFilters: Bool {
        !historySearchText.isEmpty || historyFilterChain != nil || historyFilterType != nil
    }

    private var uniqueHistoryChains: [String] {
        TransactionHistoryService.uniqueChains(from: historyEntries)
    }

    private var filteredHistoryEntries: [HawalaTransactionEntry] {
        TransactionHistoryService.filteredEntries(
            historyEntries,
            chain: historyFilterChain,
            type: historyFilterType,
            searchText: historySearchText
        )
    }
}
