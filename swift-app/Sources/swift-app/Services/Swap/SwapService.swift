import Foundation
import SwiftUI

// MARK: - Token Swap Service

/// Service for managing cross-chain token swaps between BTC, LTC, and ETH
@MainActor
final class SwapService: ObservableObject {
    static let shared = SwapService()
    
    // MARK: - Types
    
    enum SwapAsset: String, CaseIterable, Identifiable, Codable {
        case btc = "BTC"
        case ltc = "LTC"
        case eth = "ETH"
        
        var id: String { rawValue }
        
        var name: String {
            switch self {
            case .btc: return "Bitcoin"
            case .ltc: return "Litecoin"
            case .eth: return "Ethereum"
            }
        }
        
        var symbol: String { rawValue }
        
        var icon: String {
            switch self {
            case .btc: return "bitcoinsign.circle.fill"
            case .ltc: return "l.circle.fill"
            case .eth: return "diamond.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .btc: return Color(red: 247/255, green: 147/255, blue: 26/255)
            case .ltc: return Color(red: 52/255, green: 93/255, blue: 157/255)
            case .eth: return Color(red: 98/255, green: 126/255, blue: 234/255)
            }
        }
        
        var minSwapAmount: Decimal {
            switch self {
            case .btc: return 0.0001
            case .ltc: return 0.01
            case .eth: return 0.001
            }
        }
        
        var maxSwapAmount: Decimal {
            switch self {
            case .btc: return 10.0
            case .ltc: return 1000.0
            case .eth: return 100.0
            }
        }
        
        var decimals: Int {
            switch self {
            case .btc: return 8
            case .ltc: return 8
            case .eth: return 18
            }
        }
    }
    
    enum SwapStatus: String, Codable {
        case pending = "pending"
        case waitingDeposit = "waiting_deposit"
        case confirming = "confirming"
        case exchanging = "exchanging"
        case sending = "sending"
        case completed = "completed"
        case failed = "failed"
        case refunded = "refunded"
        case expired = "expired"
        
        var displayName: String {
            switch self {
            case .pending: return "Pending"
            case .waitingDeposit: return "Waiting for Deposit"
            case .confirming: return "Confirming"
            case .exchanging: return "Exchanging"
            case .sending: return "Sending"
            case .completed: return "Completed"
            case .failed: return "Failed"
            case .refunded: return "Refunded"
            case .expired: return "Expired"
            }
        }
        
        var color: Color {
            switch self {
            case .pending, .waitingDeposit: return .orange
            case .confirming, .exchanging, .sending: return .blue
            case .completed: return .green
            case .failed, .expired: return .red
            case .refunded: return .purple
            }
        }
        
        var isActive: Bool {
            switch self {
            case .pending, .waitingDeposit, .confirming, .exchanging, .sending:
                return true
            case .completed, .failed, .refunded, .expired:
                return false
            }
        }
    }
    
    enum SwapProvider: String, CaseIterable, Identifiable, Codable {
        case changelly = "changelly"
        case changenow = "changenow"
        case simpleswap = "simpleswap"
        case exolix = "exolix"
        
        var id: String { rawValue }
        
        var name: String {
            switch self {
            case .changelly: return "Changelly"
            case .changenow: return "ChangeNOW"
            case .simpleswap: return "SimpleSwap"
            case .exolix: return "Exolix"
            }
        }
        
        var feePercent: Decimal {
            switch self {
            case .changelly: return 0.25
            case .changenow: return 0.50
            case .simpleswap: return 0.50
            case .exolix: return 0.30
            }
        }
        
        var estimatedTime: String {
            switch self {
            case .changelly: return "5-30 min"
            case .changenow: return "10-30 min"
            case .simpleswap: return "10-40 min"
            case .exolix: return "5-20 min"
            }
        }
    }
    
    struct SwapQuote: Identifiable, Codable {
        let id: String
        let provider: SwapProvider
        let fromAsset: SwapAsset
        let toAsset: SwapAsset
        let fromAmount: Decimal
        let toAmount: Decimal
        let rate: Decimal
        let networkFee: Decimal
        let providerFee: Decimal
        let minAmount: Decimal
        let maxAmount: Decimal
        let validUntil: Date
        
        var isValid: Bool {
            Date() < validUntil
        }
        
        var totalFees: Decimal {
            networkFee + providerFee
        }
        
        var effectiveRate: Decimal {
            guard fromAmount > 0 else { return 0 }
            return toAmount / fromAmount
        }
    }
    
    struct SwapTransaction: Identifiable, Codable {
        let id: String
        let provider: SwapProvider
        let fromAsset: SwapAsset
        let toAsset: SwapAsset
        let fromAmount: Decimal
        let toAmount: Decimal
        let depositAddress: String
        let destinationAddress: String
        let refundAddress: String?
        let createdAt: Date
        var status: SwapStatus
        var depositTxHash: String?
        var payoutTxHash: String?
        var updatedAt: Date
        var expiresAt: Date?
        
        var isActive: Bool { status.isActive }
    }
    
    // MARK: - Published Properties
    
    @Published private(set) var quotes: [SwapQuote] = []
    @Published private(set) var activeSwaps: [SwapTransaction] = []
    @Published private(set) var swapHistory: [SwapTransaction] = []
    @Published private(set) var isLoadingQuotes = false
    @Published private(set) var isProcessingSwap = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private let userDefaults = UserDefaults.standard
    private let historyKey = "hawala.swap.history"
    private var pollingTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    private init() {
        loadHistory()
        startPollingActiveSwaps()
    }
    
    deinit {
        pollingTask?.cancel()
    }
    
    // MARK: - Public Methods
    
    /// Get quotes from all providers for a swap
    func getQuotes(
        from: SwapAsset,
        to: SwapAsset,
        amount: Decimal
    ) async {
        guard from != to else {
            errorMessage = "Cannot swap same asset"
            return
        }
        
        guard amount >= from.minSwapAmount else {
            errorMessage = "Amount below minimum (\(from.minSwapAmount) \(from.symbol))"
            return
        }
        
        guard amount <= from.maxSwapAmount else {
            errorMessage = "Amount above maximum (\(from.maxSwapAmount) \(from.symbol))"
            return
        }
        
        isLoadingQuotes = true
        errorMessage = nil
        
        // Simulate fetching quotes from multiple providers
        // In production, these would be actual API calls
        var fetchedQuotes: [SwapQuote] = []
        
        for provider in SwapProvider.allCases {
            if let quote = await fetchQuote(provider: provider, from: from, to: to, amount: amount) {
                fetchedQuotes.append(quote)
            }
        }
        
        // Sort by best rate (highest toAmount)
        quotes = fetchedQuotes.sorted { $0.toAmount > $1.toAmount }
        isLoadingQuotes = false
        
        if quotes.isEmpty {
            errorMessage = "No quotes available for this swap pair"
        }
    }
    
    /// Clear current quotes
    func clearQuotes() {
        quotes.removeAll()
    }
    
    /// Create a swap transaction
    func createSwap(
        quote: SwapQuote,
        destinationAddress: String,
        refundAddress: String?
    ) async -> SwapTransaction? {
        guard quote.isValid else {
            errorMessage = "Quote has expired"
            return nil
        }
        
        guard isValidAddress(destinationAddress, for: quote.toAsset) else {
            errorMessage = "Invalid destination address"
            return nil
        }
        
        isProcessingSwap = true
        errorMessage = nil
        
        // In production, this would create the swap via API
        let swap = await createSwapTransaction(
            quote: quote,
            destinationAddress: destinationAddress,
            refundAddress: refundAddress
        )
        
        if let swap = swap {
            activeSwaps.append(swap)
            saveSwapToHistory(swap)
        }
        
        isProcessingSwap = false
        return swap
    }
    
    /// Check status of an active swap
    func checkSwapStatus(_ swapId: String) async {
        guard let index = activeSwaps.firstIndex(where: { $0.id == swapId }) else {
            return
        }
        
        // In production, this would check via API
        if let updatedSwap = await fetchSwapStatus(swapId) {
            activeSwaps[index] = updatedSwap
            updateSwapInHistory(updatedSwap)
            
            if !updatedSwap.isActive {
                activeSwaps.remove(at: index)
            }
        }
    }
    
    /// Get exchange rate between two assets
    func getExchangeRate(from: SwapAsset, to: SwapAsset) async -> Decimal? {
        // Simulated exchange rates - in production these come from APIs
        let rates: [String: Decimal] = [
            "BTC-LTC": 300.0,
            "BTC-ETH": 15.5,
            "LTC-BTC": 0.00333,
            "LTC-ETH": 0.0517,
            "ETH-BTC": 0.0645,
            "ETH-LTC": 19.35
        ]
        
        let key = "\(from.rawValue)-\(to.rawValue)"
        return rates[key]
    }
    
    /// Cancel a pending swap (if supported by provider)
    func cancelSwap(_ swapId: String) async -> Bool {
        guard let index = activeSwaps.firstIndex(where: { $0.id == swapId }) else {
            return false
        }
        
        let swap = activeSwaps[index]
        guard swap.status == .pending || swap.status == .waitingDeposit else {
            errorMessage = "Cannot cancel swap in current state"
            return false
        }
        
        // In production, this would call the provider's cancel API
        var cancelledSwap = swap
        cancelledSwap.status = .expired
        cancelledSwap.updatedAt = Date()
        
        activeSwaps.remove(at: index)
        updateSwapInHistory(cancelledSwap)
        
        return true
    }
    
    /// Refresh all active swaps
    func refreshActiveSwaps() async {
        for swap in activeSwaps {
            await checkSwapStatus(swap.id)
        }
    }
    
    // MARK: - Private Methods
    
    private func fetchQuote(
        provider: SwapProvider,
        from: SwapAsset,
        to: SwapAsset,
        amount: Decimal
    ) async -> SwapQuote? {
        // Simulate API delay
        try? await Task.sleep(nanoseconds: UInt64.random(in: 200_000_000...500_000_000))
        
        guard let rate = await getExchangeRate(from: from, to: to) else {
            return nil
        }
        
        // Apply provider fee
        let feeMultiplier = 1 - (provider.feePercent / 100)
        let adjustedRate = rate * feeMultiplier
        let toAmount = amount * adjustedRate
        
        // Calculate network fees (simplified)
        let networkFee: Decimal = switch to {
        case .btc: 0.00005
        case .ltc: 0.001
        case .eth: 0.002
        }
        
        let providerFee = amount * (provider.feePercent / 100)
        
        return SwapQuote(
            id: UUID().uuidString,
            provider: provider,
            fromAsset: from,
            toAsset: to,
            fromAmount: amount,
            toAmount: toAmount - networkFee,
            rate: adjustedRate,
            networkFee: networkFee,
            providerFee: providerFee,
            minAmount: from.minSwapAmount,
            maxAmount: from.maxSwapAmount,
            validUntil: Date().addingTimeInterval(600) // 10 minutes
        )
    }
    
    private func createSwapTransaction(
        quote: SwapQuote,
        destinationAddress: String,
        refundAddress: String?
    ) async -> SwapTransaction? {
        // Simulate API delay
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Generate a mock deposit address based on asset type
        let depositAddress = generateMockDepositAddress(for: quote.fromAsset)
        
        return SwapTransaction(
            id: UUID().uuidString,
            provider: quote.provider,
            fromAsset: quote.fromAsset,
            toAsset: quote.toAsset,
            fromAmount: quote.fromAmount,
            toAmount: quote.toAmount,
            depositAddress: depositAddress,
            destinationAddress: destinationAddress,
            refundAddress: refundAddress,
            createdAt: Date(),
            status: .waitingDeposit,
            depositTxHash: nil,
            payoutTxHash: nil,
            updatedAt: Date(),
            expiresAt: Date().addingTimeInterval(3600) // 1 hour
        )
    }
    
    private func fetchSwapStatus(_ swapId: String) async -> SwapTransaction? {
        // In production, this would fetch from the provider's API
        guard var swap = activeSwaps.first(where: { $0.id == swapId }) else {
            return nil
        }
        
        // Simulate status progression
        let nextStatus: SwapStatus? = switch swap.status {
        case .pending: .waitingDeposit
        case .waitingDeposit: Bool.random() ? .confirming : nil
        case .confirming: .exchanging
        case .exchanging: .sending
        case .sending: .completed
        default: nil
        }
        
        if let next = nextStatus {
            swap.status = next
            swap.updatedAt = Date()
            
            if next == .confirming {
                swap.depositTxHash = generateMockTxHash()
            } else if next == .completed {
                swap.payoutTxHash = generateMockTxHash()
            }
        }
        
        return swap
    }
    
    private func generateMockDepositAddress(for asset: SwapAsset) -> String {
        switch asset {
        case .btc:
            return "bc1q" + randomHexString(length: 38)
        case .ltc:
            return "ltc1q" + randomHexString(length: 38)
        case .eth:
            return "0x" + randomHexString(length: 40)
        }
    }
    
    private func generateMockTxHash() -> String {
        randomHexString(length: 64)
    }
    
    private func randomHexString(length: Int) -> String {
        let chars = "0123456789abcdef"
        return String((0..<length).map { _ in chars.randomElement()! })
    }
    
    private func isValidAddress(_ address: String, for asset: SwapAsset) -> Bool {
        switch asset {
        case .btc:
            return address.hasPrefix("bc1") || address.hasPrefix("1") || address.hasPrefix("3")
        case .ltc:
            return address.hasPrefix("ltc1") || address.hasPrefix("L") || address.hasPrefix("M")
        case .eth:
            return address.hasPrefix("0x") && address.count == 42
        }
    }
    
    private func startPollingActiveSwaps() {
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                await refreshActiveSwaps()
            }
        }
    }
    
    // MARK: - Persistence
    
    private func loadHistory() {
        guard let data = userDefaults.data(forKey: historyKey),
              let history = try? JSONDecoder().decode([SwapTransaction].self, from: data) else {
            return
        }
        swapHistory = history
        activeSwaps = history.filter { $0.isActive }
    }
    
    private func saveSwapToHistory(_ swap: SwapTransaction) {
        swapHistory.insert(swap, at: 0)
        saveHistory()
    }
    
    private func updateSwapInHistory(_ swap: SwapTransaction) {
        if let index = swapHistory.firstIndex(where: { $0.id == swap.id }) {
            swapHistory[index] = swap
            saveHistory()
        }
    }
    
    private func saveHistory() {
        // Keep only last 100 swaps
        let historyToSave = Array(swapHistory.prefix(100))
        if let data = try? JSONEncoder().encode(historyToSave) {
            userDefaults.set(data, forKey: historyKey)
        }
    }
}

// MARK: - Swap View

struct SwapView: View {
    @StateObject private var swapService = SwapService.shared
    
    @State private var fromAsset: SwapService.SwapAsset = .btc
    @State private var toAsset: SwapService.SwapAsset = .eth
    @State private var fromAmount: String = ""
    @State private var destinationAddress: String = ""
    @State private var selectedQuote: SwapService.SwapQuote?
    @State private var showConfirmation = false
    @State private var activeSwap: SwapService.SwapTransaction?
    @State private var showSwapProgress = false
    
    private var fromAmountDecimal: Decimal? {
        Decimal(string: fromAmount)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    swapInputSection
                    
                    if !swapService.quotes.isEmpty {
                        quotesSection
                    }
                    
                    if !swapService.activeSwaps.isEmpty {
                        activeSwapsSection
                    }
                    
                    if !swapService.swapHistory.filter({ !$0.isActive }).isEmpty {
                        historySection
                    }
                }
                .padding()
            }
            .navigationTitle("swap.title".localized)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await swapService.refreshActiveSwaps()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showConfirmation) {
                if let quote = selectedQuote {
                    SwapConfirmationSheet(
                        quote: quote,
                        destinationAddress: $destinationAddress,
                        onConfirm: { address in
                            Task {
                                if let swap = await swapService.createSwap(
                                    quote: quote,
                                    destinationAddress: address,
                                    refundAddress: nil
                                ) {
                                    activeSwap = swap
                                    showSwapProgress = true
                                }
                            }
                        }
                    )
                }
            }
            .sheet(isPresented: $showSwapProgress) {
                if let swap = activeSwap {
                    SwapProgressSheet(swap: swap)
                }
            }
            .alert("Error", isPresented: .init(
                get: { swapService.errorMessage != nil },
                set: { if !$0 { swapService.errorMessage = nil } }
            )) {
                Button("OK") { }
            } message: {
                Text(swapService.errorMessage ?? "")
            }
        }
    }
    
    private var swapInputSection: some View {
        VStack(spacing: 16) {
            // From Asset
            VStack(alignment: .leading, spacing: 8) {
                Text("swap.from".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack {
                    assetPicker(selection: $fromAsset)
                    
                    TextField("0.00", text: $fromAmount)
                        .textFieldStyle(.plain)
                        .font(.title2.monospacedDigit())
                        .multilineTextAlignment(.trailing)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
            }
            
            // Swap button
            Button {
                let temp = fromAsset
                fromAsset = toAsset
                toAsset = temp
                fromAmount = ""
                swapService.clearQuotes()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            
            // To Asset
            VStack(alignment: .leading, spacing: 8) {
                Text("swap.to".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack {
                    assetPicker(selection: $toAsset)
                    
                    Text(estimatedReceiveAmount)
                        .font(.title2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
            }
            
            // Get Quotes Button
            Button {
                guard let amount = fromAmountDecimal else { return }
                Task {
                    await swapService.getQuotes(from: fromAsset, to: toAsset, amount: amount)
                }
            } label: {
                HStack {
                    if swapService.isLoadingQuotes {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Text(swapService.isLoadingQuotes ? "swap.loading_quotes".localized : "swap.get_quotes".localized)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(fromAmountDecimal == nil || fromAsset == toAsset || swapService.isLoadingQuotes)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(16)
    }
    
    private var estimatedReceiveAmount: String {
        guard fromAmountDecimal != nil,
              let bestQuote = swapService.quotes.first else {
            return "~0.00"
        }
        return "~\(formatDecimal(bestQuote.toAmount)) \(toAsset.symbol)"
    }
    
    private func assetPicker(selection: Binding<SwapService.SwapAsset>) -> some View {
        Menu {
            ForEach(SwapService.SwapAsset.allCases) { asset in
                Button {
                    selection.wrappedValue = asset
                } label: {
                    Label(asset.name, systemImage: asset.icon)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selection.wrappedValue.icon)
                    .foregroundStyle(selection.wrappedValue.color)
                Text(selection.wrappedValue.symbol)
                    .fontWeight(.semibold)
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selection.wrappedValue.color.opacity(0.15))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private var quotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("swap.available_quotes".localized)
                .font(.headline)
            
            ForEach(swapService.quotes) { quote in
                QuoteRow(quote: quote, onSelect: {
                    selectedQuote = quote
                    showConfirmation = true
                })
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(16)
    }
    
    private var activeSwapsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("swap.active_swaps".localized)
                .font(.headline)
            
            ForEach(swapService.activeSwaps) { swap in
                SwapStatusRow(swap: swap, onTap: {
                    activeSwap = swap
                    showSwapProgress = true
                })
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(16)
    }
    
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("swap.history".localized)
                .font(.headline)
            
            ForEach(swapService.swapHistory.filter { !$0.isActive }.prefix(5)) { swap in
                SwapStatusRow(swap: swap, onTap: {
                    activeSwap = swap
                    showSwapProgress = true
                })
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(16)
    }
    
    private func formatDecimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 8
        return formatter.string(from: value as NSDecimalNumber) ?? "0.00"
    }
}

// MARK: - Quote Row

struct QuoteRow: View {
    let quote: SwapService.SwapQuote
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(quote.provider.name)
                        .font(.headline)
                    Text("Fee: \(formatDecimal(quote.providerFee)) \(quote.fromAsset.symbol)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(quote.provider.estimatedTime)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(formatDecimal(quote.toAmount)) \(quote.toAsset.symbol)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Rate: 1 \(quote.fromAsset.symbol) = \(formatDecimal(quote.rate)) \(quote.toAsset.symbol)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    private func formatDecimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 8
        return formatter.string(from: value as NSDecimalNumber) ?? "0.00"
    }
}

// MARK: - Swap Status Row

struct SwapStatusRow: View {
    let swap: SwapService.SwapTransaction
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                // Asset pair icon
                HStack(spacing: -8) {
                    Image(systemName: swap.fromAsset.icon)
                        .font(.title2)
                        .foregroundStyle(swap.fromAsset.color)
                    Image(systemName: swap.toAsset.icon)
                        .font(.title2)
                        .foregroundStyle(swap.toAsset.color)
                }
                .padding(.trailing, 8)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(formatDecimal(swap.fromAmount)) \(swap.fromAsset.symbol) → \(formatDecimal(swap.toAmount)) \(swap.toAsset.symbol)")
                        .font(.subheadline)
                    Text(swap.provider.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    SwapStatusBadge(status: swap.status)
                    Text(formatDate(swap.updatedAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    private func formatDecimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 6
        return formatter.string(from: value as NSDecimalNumber) ?? "0.00"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Swap Status Badge

struct SwapStatusBadge: View {
    let status: SwapService.SwapStatus
    
    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.2))
            .foregroundStyle(status.color)
            .cornerRadius(6)
    }
}

// MARK: - Swap Confirmation Sheet

struct SwapConfirmationSheet: View {
    let quote: SwapService.SwapQuote
    @Binding var destinationAddress: String
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("swap.summary".localized) {
                    LabeledContent("swap.you_send".localized) {
                        Text("\(formatDecimal(quote.fromAmount)) \(quote.fromAsset.symbol)")
                    }
                    
                    LabeledContent("swap.you_receive".localized) {
                        Text("\(formatDecimal(quote.toAmount)) \(quote.toAsset.symbol)")
                    }
                    
                    LabeledContent("swap.provider".localized) {
                        Text(quote.provider.name)
                    }
                    
                    LabeledContent("swap.rate".localized) {
                        Text("1 \(quote.fromAsset.symbol) = \(formatDecimal(quote.rate)) \(quote.toAsset.symbol)")
                    }
                    
                    LabeledContent("swap.network_fee".localized) {
                        Text("\(formatDecimal(quote.networkFee)) \(quote.toAsset.symbol)")
                    }
                    
                    LabeledContent("swap.estimated_time".localized) {
                        Text(quote.provider.estimatedTime)
                    }
                }
                
                Section("swap.destination".localized) {
                    TextField("swap.destination_address_placeholder".localized, text: $destinationAddress)
                        .textFieldStyle(.plain)
                    
                    Text("swap.destination_warning".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("swap.confirm_swap".localized)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel".localized) { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("swap.confirm".localized) {
                        onConfirm(destinationAddress)
                        dismiss()
                    }
                    .disabled(destinationAddress.isEmpty)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 450)
    }
    
    private func formatDecimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 8
        return formatter.string(from: value as NSDecimalNumber) ?? "0.00"
    }
}

// MARK: - Swap Progress Sheet

struct SwapProgressSheet: View {
    let swap: SwapService.SwapTransaction
    @Environment(\.dismiss) private var dismiss
    @State private var copiedField: String?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Status header
                    VStack(spacing: 8) {
                        SwapStatusBadge(status: swap.status)
                            .scaleEffect(1.2)
                        
                        Text(swap.status.displayName)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        if swap.status.isActive {
                            Text("swap.status_refreshing".localized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    
                    // Progress steps
                    SwapProgressSteps(currentStatus: swap.status)
                        .padding(.horizontal)
                    
                    Divider()
                    
                    // Swap details
                    VStack(alignment: .leading, spacing: 16) {
                        detailRow(title: "swap.send".localized, value: "\(formatDecimal(swap.fromAmount)) \(swap.fromAsset.symbol)")
                        detailRow(title: "swap.receive".localized, value: "\(formatDecimal(swap.toAmount)) \(swap.toAsset.symbol)")
                        
                        if swap.status == .waitingDeposit {
                            copyableRow(title: "swap.deposit_address".localized, value: swap.depositAddress, field: "deposit")
                            
                            Text("swap.deposit_instructions".localized)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(.vertical, 8)
                        }
                        
                        copyableRow(title: "swap.destination_address".localized, value: swap.destinationAddress, field: "destination")
                        
                        if let txHash = swap.depositTxHash {
                            copyableRow(title: "swap.deposit_tx".localized, value: txHash, field: "depositTx")
                        }
                        
                        if let txHash = swap.payoutTxHash {
                            copyableRow(title: "swap.payout_tx".localized, value: txHash, field: "payoutTx")
                        }
                        
                        detailRow(title: "swap.provider".localized, value: swap.provider.name)
                        detailRow(title: "swap.created".localized, value: formatDate(swap.createdAt))
                        
                        if let expires = swap.expiresAt, swap.status.isActive {
                            detailRow(title: "swap.expires".localized, value: formatDate(expires))
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                .padding()
            }
            .navigationTitle("swap.details".localized)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done".localized) { dismiss() }
                }
            }
        }
        .frame(minWidth: 450, minHeight: 600)
    }
    
    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
    
    private func copyableRow(title: String, value: String, field: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack {
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                    copiedField = field
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if copiedField == field {
                            copiedField = nil
                        }
                    }
                } label: {
                    Image(systemName: copiedField == field ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(copiedField == field ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func formatDecimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 8
        return formatter.string(from: value as NSDecimalNumber) ?? "0.00"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Swap Progress Steps

struct SwapProgressSteps: View {
    let currentStatus: SwapService.SwapStatus
    
    private let steps: [SwapService.SwapStatus] = [
        .waitingDeposit,
        .confirming,
        .exchanging,
        .sending,
        .completed
    ]
    
    private func stepIndex(for status: SwapService.SwapStatus) -> Int {
        steps.firstIndex(of: status) ?? -1
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                let currentIndex = stepIndex(for: currentStatus)
                let isCompleted = index < currentIndex
                let isCurrent = index == currentIndex
                
                VStack(spacing: 8) {
                    Circle()
                        .fill(isCompleted ? .green : (isCurrent ? currentStatus.color : Color.gray.opacity(0.3)))
                        .frame(width: 20, height: 20)
                        .overlay {
                            if isCompleted {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                            } else if isCurrent {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    
                    Text(step.displayName)
                        .font(.caption2)
                        .foregroundStyle(isCurrent || isCompleted ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                
                if index < steps.count - 1 {
                    Rectangle()
                        .fill(index < currentIndex ? .green : Color.gray.opacity(0.3))
                        .frame(height: 2)
                        .offset(y: -12)
                }
            }
        }
    }
}
