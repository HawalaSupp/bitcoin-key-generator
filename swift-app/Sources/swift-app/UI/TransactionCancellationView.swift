import SwiftUI

// MARK: - Cancellation Mode Enum

/// Mode for transaction cancellation/speed-up operations
enum CancellationMode: String, CaseIterable {
    case cancel = "Cancel"
    case speedUp = "Speed Up"
    
    var description: String {
        switch self {
        case .cancel: return "Send funds back to yourself"
        case .speedUp: return "Increase fee to confirm faster"
        }
    }
    
    var icon: String {
        switch self {
        case .cancel: return "xmark.circle.fill"
        case .speedUp: return "bolt.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .cancel: return .red
        case .speedUp: return .orange
        }
    }
}

// MARK: - Transaction Cancellation Sheet
/// UI for cancelling or speeding up stuck transactions

struct TransactionCancellationSheet: View {
    let pendingTx: PendingTransactionManager.PendingTransaction
    let keys: AllKeys
    let initialMode: CancellationMode
    let onDismiss: () -> Void
    let onSuccess: (String) -> Void
    
    init(pendingTx: PendingTransactionManager.PendingTransaction, keys: AllKeys, initialMode: CancellationMode = .cancel, onDismiss: @escaping () -> Void, onSuccess: @escaping (String) -> Void) {
        self.pendingTx = pendingTx
        self.keys = keys
        self.initialMode = initialMode
        self.onDismiss = onDismiss
        self.onSuccess = onSuccess
    }
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cancellationManager = TransactionCancellationManager.shared
    
    // State
    @State private var mode: CancellationMode = .cancel
    @State private var newFeeRate: Double = 0
    @State private var minFeeRate: Double = 0
    @State private var maxFeeRate: Double = 0
    @State private var recommendedFeeRate: Double = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var mempoolInfo: TransactionCancellationManager.MempoolInfo?
    @State private var estimatedCost: String = "—"
    @State private var estimatedTime: String = "—"
    
    private var isBitcoinLike: Bool {
        ["bitcoin", "bitcoin-testnet", "litecoin"].contains(pendingTx.chainId)
    }
    
    private var isEthereumLike: Bool {
        ["ethereum", "ethereum-sepolia", "bnb"].contains(pendingTx.chainId)
    }
    
    private var feeUnit: String {
        isBitcoinLike ? "sat/vB" : "gwei"
    }
    
    private var chainColor: Color {
        switch pendingTx.chainId {
        case "bitcoin", "bitcoin-testnet": return .orange
        case "litecoin": return .gray
        case "ethereum", "ethereum-sepolia": return .blue
        case "bnb": return .yellow
        default: return .purple
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Transaction Info Card
                    transactionCard
                    
                    // Mode Selector
                    modeSelector
                    
                    // Mempool Status
                    if let info = mempoolInfo {
                        mempoolStatusCard(info)
                    }
                    
                    // Fee Slider
                    feeSection
                    
                    // Cost & Time Estimate
                    estimatesSection
                    
                    // Warning
                    warningSection
                    
                    // Error
                    if let error = errorMessage {
                        errorBanner(error)
                    }
                    
                    Spacer(minLength: 20)
                    
                    // Action Button
                    actionButton
                }
                .padding(24)
            }
            .navigationTitle(mode == .cancel ? "Cancel Transaction" : "Speed Up Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 480, height: 680)
        .task {
            mode = initialMode
            await loadFeeData()
        }
    }
    
    // MARK: - Transaction Card
    
    private var transactionCard: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                // Chain icon
                Circle()
                    .fill(chainColor.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: chainIcon)
                            .font(.system(size: 20))
                            .foregroundStyle(chainColor)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(pendingTx.chainName)
                        .font(.headline)
                    Text(pendingTx.amount)
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                // Status badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 8, height: 8)
                    Text("Pending")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.15))
                .clipShape(Capsule())
            }
            .padding()
            
            Divider()
            
            // Details
            VStack(spacing: 12) {
                detailRow(label: "To", value: truncate(pendingTx.recipient))
                detailRow(label: "Transaction", value: truncate(pendingTx.id))
                
                if let feeRate = pendingTx.originalFeeRate {
                    detailRow(label: "Current Fee", value: "\(feeRate) \(feeUnit)")
                }
                
                if let nonce = pendingTx.nonce {
                    detailRow(label: "Nonce", value: "\(nonce)")
                }
                
                detailRow(label: "Sent", value: formatTimestamp(pendingTx.timestamp))
            }
            .padding()
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.primary.opacity(0.03))
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            }
        )
    }
    
    private var chainIcon: String {
        switch pendingTx.chainId {
        case "bitcoin", "bitcoin-testnet": return "bitcoinsign.circle.fill"
        case "litecoin": return "l.circle.fill"
        case "ethereum", "ethereum-sepolia": return "diamond.fill"
        case "bnb": return "b.circle.fill"
        default: return "circle.fill"
        }
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
        }
    }
    
    // MARK: - Mode Selector
    
    private var modeSelector: some View {
        HStack(spacing: 12) {
            ForEach(CancellationMode.allCases, id: \.self) { m in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        mode = m
                        updateEstimates()
                    }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: m.icon)
                            .font(.title2)
                        Text(m.rawValue)
                            .font(.headline)
                        Text(m.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(mode == m ? m.color.opacity(0.15) : Color.primary.opacity(0.03))
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(mode == m ? m.color : Color.clear, lineWidth: 2)
                        }
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(mode == m ? m.color : .primary)
            }
        }
    }
    
    // MARK: - Mempool Status
    
    private func mempoolStatusCard(_ info: TransactionCancellationManager.MempoolInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.blue)
                Text("Network Status")
                    .font(.headline)
                Spacer()
                if info.isStale {
                    Label("Stale", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            
            HStack(spacing: 16) {
                feeIndicator(label: "Fast", value: info.fastestFee, color: .green)
                feeIndicator(label: "Normal", value: info.halfHourFee, color: .blue)
                feeIndicator(label: "Slow", value: info.hourFee, color: .orange)
            }
            
            if let size = info.mempoolSize {
                HStack {
                    Text("Mempool:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(size.formatted()) unconfirmed txs")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.05))
        )
    }
    
    private func feeIndicator(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Fee Section
    
    private var feeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("New Fee Rate")
                    .font(.headline)
                Spacer()
                Text("\(Int(newFeeRate)) \(feeUnit)")
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(mode.color)
            }
            
            // Slider
            Slider(value: $newFeeRate, in: minFeeRate...maxFeeRate, step: 1)
                .tint(mode.color)
                .onChange(of: newFeeRate) { _ in
                    updateEstimates()
                }
            
            // Labels
            HStack {
                Text("Min: \(Int(minFeeRate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Recommended") {
                    withAnimation {
                        newFeeRate = recommendedFeeRate
                    }
                }
                .font(.caption)
                .foregroundStyle(mode.color)
                Spacer()
                Text("Max: \(Int(maxFeeRate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Quick select buttons
            HStack(spacing: 8) {
                feePresetButton("1.1x", multiplier: 1.1)
                feePresetButton("1.5x", multiplier: 1.5)
                feePresetButton("2x", multiplier: 2.0)
                feePresetButton("3x", multiplier: 3.0)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.03))
        )
    }
    
    private func feePresetButton(_ label: String, multiplier: Double) -> some View {
        Button {
            withAnimation {
                newFeeRate = min(maxFeeRate, max(minFeeRate, Double(pendingTx.originalFeeRate ?? Int(minFeeRate)) * multiplier))
            }
        } label: {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Estimates Section
    
    private var estimatesSection: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Additional Cost")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(estimatedCost)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(mode.color.opacity(0.1))
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Est. Confirmation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(estimatedTime)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.green.opacity(0.1))
            )
        }
    }
    
    // MARK: - Warning Section
    
    private var warningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Important")
                    .font(.headline)
            }
            
            if mode == .cancel {
                Text("This will send all funds from the original transaction back to your wallet. The original recipient will NOT receive any funds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("This will replace the original transaction with a higher fee. The recipient and amount remain the same.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if isBitcoinLike {
                Text("⚠️ RBF replacement may take a few minutes to propagate through the network.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.1))
        )
    }
    
    // MARK: - Error Banner
    
    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red.opacity(0.1))
        )
    }
    
    // MARK: - Action Button
    
    private var actionButton: some View {
        Button {
            Task { await executeAction() }
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: mode == .cancel ? "xmark.circle.fill" : "bolt.fill")
                }
                Text(mode == .cancel ? "Cancel Transaction" : "Speed Up Transaction")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .tint(mode.color)
        .disabled(isLoading || newFeeRate <= minFeeRate)
    }
    
    // MARK: - Actions
    
    private func loadFeeData() async {
        isLoading = true
        
        do {
            let info = try await cancellationManager.fetchMempoolInfo(chainId: pendingTx.chainId)
            
            await MainActor.run {
                mempoolInfo = info
                
                let originalRate = Double(pendingTx.originalFeeRate ?? info.hourFee)
                minFeeRate = originalRate + 1
                maxFeeRate = Double(info.fastestFee * 5)
                recommendedFeeRate = Double(info.halfHourFee)
                newFeeRate = max(minFeeRate, Double(info.halfHourFee))
                
                updateEstimates()
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                
                // Set defaults
                let originalRate = Double(pendingTx.originalFeeRate ?? 10)
                minFeeRate = originalRate + 1
                maxFeeRate = originalRate * 10
                recommendedFeeRate = originalRate * 2
                newFeeRate = originalRate * 1.5
                
                isLoading = false
            }
        }
    }
    
    private func updateEstimates() {
        if isBitcoinLike {
            // Estimate ~150 vBytes for cancellation, ~200 for speed-up
            let vsize = mode == .cancel ? 150 : 200
            let additionalSats = Int((newFeeRate - minFeeRate + 1) * Double(vsize))
            let btc = Double(additionalSats) / 100_000_000
            estimatedCost = String(format: "+%.8f BTC", btc)
        } else {
            let additionalGwei = (newFeeRate - minFeeRate / 1.1) * 21000
            let eth = additionalGwei / 1_000_000_000
            estimatedCost = String(format: "+%.6f ETH", eth)
        }
        
        // Estimate time based on fee rate
        if let info = mempoolInfo {
            if Int(newFeeRate) >= info.fastestFee {
                estimatedTime = "~10 minutes"
            } else if Int(newFeeRate) >= info.halfHourFee {
                estimatedTime = "~30 minutes"
            } else if Int(newFeeRate) >= info.hourFee {
                estimatedTime = "~1 hour"
            } else {
                estimatedTime = ">1 hour"
            }
        } else {
            estimatedTime = "Unknown"
        }
    }
    
    private func executeAction() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let result: TransactionCancellationManager.CancellationResult
            
            if isBitcoinLike {
                // Get the appropriate private key based on chain
                let wif: String
                let returnAddress: String
                
                switch pendingTx.chainId {
                case "bitcoin":
                    wif = keys.bitcoin.privateWif
                    returnAddress = keys.bitcoin.address
                case "bitcoin-testnet":
                    wif = keys.bitcoinTestnet.privateWif
                    returnAddress = keys.bitcoinTestnet.address
                case "litecoin":
                    wif = keys.litecoin.privateWif
                    returnAddress = keys.litecoin.address
                default:
                    throw TransactionCancelError.unsupportedChain(pendingTx.chainId)
                }
                
                if mode == .cancel {
                    result = try await cancellationManager.cancelBitcoinTransactionWithFetch(
                        pendingTx: pendingTx,
                        privateKeyWIF: wif,
                        returnAddress: returnAddress,
                        newFeeRate: Int(newFeeRate)
                    )
                } else {
                    result = try await cancellationManager.speedUpBitcoinTransactionWithFetch(
                        pendingTx: pendingTx,
                        privateKeyWIF: wif,
                        newFeeRate: Int(newFeeRate)
                    )
                }
            } else {
                let privateKey = keys.ethereum.privateHex
                let senderAddress = keys.ethereum.address
                let gasWei = UInt64(newFeeRate * 1_000_000_000)
                
                if mode == .cancel {
                    result = try await cancellationManager.cancelEthereumTransaction(
                        pendingTx: pendingTx,
                        privateKeyHex: privateKey,
                        senderAddress: senderAddress,
                        newGasPrice: gasWei
                    )
                } else {
                    result = try await cancellationManager.speedUpEthereumTransaction(
                        pendingTx: pendingTx,
                        privateKeyHex: privateKey,
                        newGasPrice: gasWei
                    )
                }
            }
            
            await MainActor.run {
                if result.success, let newTxid = result.replacementTxid {
                    onSuccess(newTxid)
                    dismiss()
                } else {
                    errorMessage = result.message
                    isLoading = false
                }
            }
            
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    // MARK: - Helpers
    
    private func truncate(_ text: String) -> String {
        guard text.count > 18 else { return text }
        return "\(text.prefix(10))...\(text.suffix(6))"
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Pending Transactions Dashboard

struct PendingTransactionsDashboard: View {
    @Binding var pendingTransactions: [PendingTransactionManager.PendingTransaction]
    let keys: AllKeys
    let onRefresh: () async -> Void
    
    @State private var selectedTx: PendingTransactionManager.PendingTransaction?
    @State private var showCancellationSheet = false
    @State private var isRefreshing = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pending Transactions")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("\(pendingCount) transaction\(pendingCount == 1 ? "" : "s") waiting for confirmation")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    Task {
                        isRefreshing = true
                        await onRefresh()
                        isRefreshing = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            Divider()
            
            if pendingTransactions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(pendingTransactions.filter { $0.status == .pending }) { tx in
                            PendingTxCard(
                                transaction: tx,
                                onCancel: {
                                    selectedTx = tx
                                    showCancellationSheet = true
                                },
                                onSpeedUp: {
                                    selectedTx = tx
                                    showCancellationSheet = true
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showCancellationSheet) {
            if let tx = selectedTx {
                TransactionCancellationSheet(
                    pendingTx: tx,
                    keys: keys,
                    onDismiss: {
                        showCancellationSheet = false
                        selectedTx = nil
                    },
                    onSuccess: { _ in
                        showCancellationSheet = false
                        selectedTx = nil
                        Task { await onRefresh() }
                    }
                )
            }
        }
    }
    
    private var pendingCount: Int {
        pendingTransactions.filter { $0.status == .pending }.count
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("All Clear!")
                .font(.title3)
                .fontWeight(.semibold)
            Text("No pending transactions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Pending Transaction Card

struct PendingTxCard: View {
    let transaction: PendingTransactionManager.PendingTransaction
    let onCancel: () -> Void
    let onSpeedUp: () -> Void
    
    @State private var isHovered = false
    
    private var chainColor: Color {
        switch transaction.chainId {
        case "bitcoin", "bitcoin-testnet": return .orange
        case "litecoin": return .gray
        case "ethereum", "ethereum-sepolia": return .blue
        case "bnb": return .yellow
        default: return .purple
        }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Chain indicator
            Circle()
                .fill(chainColor.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: chainIcon)
                        .font(.system(size: 18))
                        .foregroundStyle(chainColor)
                )
            
            // Transaction info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(transaction.amount)
                        .font(.headline)
                    
                    if transaction.confirmations > 0 {
                        Text("\(transaction.confirmations) conf")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                
                Text("To: \(truncate(transaction.recipient))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    if let fee = transaction.originalFeeRate {
                        Text("\(fee) \(feeUnit)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    
                    Text("•")
                        .foregroundStyle(.tertiary)
                    
                    Text(timeAgo)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            // Actions
            if isHovered && transaction.canSpeedUp {
                HStack(spacing: 8) {
                    Button {
                        onSpeedUp()
                    } label: {
                        Label("Speed Up", systemImage: "bolt.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    
                    Button {
                        onCancel()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            } else {
                // Spinning indicator
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(isHovered ? 0.06 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .onHover { isHovered = $0 }
    }
    
    private var chainIcon: String {
        switch transaction.chainId {
        case "bitcoin", "bitcoin-testnet": return "bitcoinsign.circle.fill"
        case "litecoin": return "l.circle.fill"
        case "ethereum", "ethereum-sepolia": return "diamond.fill"
        case "bnb": return "b.circle.fill"
        default: return "circle.fill"
        }
    }
    
    private var feeUnit: String {
        ["bitcoin", "bitcoin-testnet", "litecoin"].contains(transaction.chainId) ? "sat/vB" : "gwei"
    }
    
    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: transaction.timestamp, relativeTo: Date())
    }
    
    private func truncate(_ text: String) -> String {
        guard text.count > 18 else { return text }
        return "\(text.prefix(10))...\(text.suffix(6))"
    }
}

// MARK: - Preview

#if DEBUG
struct TransactionCancellationSheet_Previews: PreviewProvider {
    static var previews: some View {
        Text("Preview not available - requires AllKeys")
            .padding()
    }
}
#endif
