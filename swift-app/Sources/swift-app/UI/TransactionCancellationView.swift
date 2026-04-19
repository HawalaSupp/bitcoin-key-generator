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
    
    // State - use safe defaults to prevent Slider crash before async load completes
    @State private var mode: CancellationMode = .cancel
    @State private var newFeeRate: Double = 10
    @State private var minFeeRate: Double = 1
    @State private var maxFeeRate: Double = 100  // Safe default > minFeeRate
    @State private var recommendedFeeRate: Double = 20
    @State private var isLoading = true  // Start as loading
    @State private var errorMessage: String?
    @State private var mempoolInfo: TransactionCancellationManager.MempoolInfo?
    @State private var estimatedCost: String = "—"
    @State private var estimatedTime: String = "—"
    
    private var isBitcoinLike: Bool {
        ["bitcoin", "bitcoin-mainnet", "bitcoin-testnet", "litecoin"].contains(pendingTx.chainId)
    }
    
    private var isEthereumLike: Bool {
        [
            "ethereum", "ethereum-mainnet", "ethereum-sepolia",
            "bnb", "bsc-mainnet",
            "polygon", "polygon-mainnet",
            "arbitrum", "arbitrum-mainnet",
            "optimism", "optimism-mainnet",
            "base", "base-mainnet",
            "avalanche", "avalanche-mainnet",
            "fantom", "fantom-mainnet",
            "gnosis", "gnosis-mainnet",
            "scroll", "scroll-mainnet"
        ].contains(pendingTx.chainId)
    }
    
    private var feeUnit: String {
        isBitcoinLike ? "sat/vB" : "gwei"
    }
    
    private var chainColor: Color {
        switch pendingTx.chainId {
        case "bitcoin", "bitcoin-mainnet", "bitcoin-testnet": return .orange
        case "litecoin": return .gray
        case "ethereum", "ethereum-mainnet", "ethereum-sepolia",
             "arbitrum", "arbitrum-mainnet",
             "optimism", "optimism-mainnet",
             "base", "base-mainnet",
             "scroll", "scroll-mainnet": return .blue
        case "bnb", "bsc-mainnet": return .yellow
        case "polygon", "polygon-mainnet": return .purple
        case "avalanche", "avalanche-mainnet": return .red
        case "fantom", "fantom-mainnet": return .cyan
        case "gnosis", "gnosis-mainnet": return .green
        default: return .purple
        }
    }
    
    var body: some View {
        HawalaSheetShell(title: mode == .cancel ? "Cancel Transaction" : "Speed Up Transaction", width: 480, height: 680) {
            transactionCard
            modeSelector

            if let info = mempoolInfo {
                mempoolStatusCard(info)
            }

            feeSection
            estimatesSection
            warningSection

            if let error = errorMessage {
                errorBanner(error)
            }

            actionButton
        }
        .task {
            mode = initialMode
            await loadFeeData()
        }
    }
    
    // MARK: - Transaction Card
    
    private var transactionCard: some View {
        VStack(spacing: 0) {
            HStack {
                Circle()
                    .fill(chainColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: chainIcon)
                            .font(.system(size: 18))
                            .foregroundColor(chainColor)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(pendingTx.chainName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                    Text(pendingTx.amount)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(red: 1, green: 0.84, blue: 0.04))
                        .frame(width: 6, height: 6)
                    Text("Pending")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(red: 1, green: 0.84, blue: 0.04))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(red: 1, green: 0.84, blue: 0.04).opacity(0.1))
                .clipShape(Capsule())
            }
            .padding(14)

            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(height: 1)

            VStack(spacing: 10) {
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
            .padding(14)
        }
        .hawalaSectionCard()
    }
    
    private var chainIcon: String {
        switch pendingTx.chainId {
        case "bitcoin", "bitcoin-mainnet", "bitcoin-testnet": return "bitcoinsign.circle.fill"
        case "litecoin": return "l.circle.fill"
        case "ethereum", "ethereum-mainnet", "ethereum-sepolia",
             "arbitrum", "arbitrum-mainnet",
             "optimism", "optimism-mainnet",
             "base", "base-mainnet",
             "scroll", "scroll-mainnet": return "diamond.fill"
        case "bnb", "bsc-mainnet": return "b.circle.fill"
        case "polygon", "polygon-mainnet": return "p.circle.fill"
        case "avalanche", "avalanche-mainnet": return "a.circle.fill"
        case "fantom", "fantom-mainnet": return "f.circle.fill"
        case "gnosis", "gnosis-mainnet": return "g.circle.fill"
        default: return "circle.fill"
        }
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - Mode Selector

    private var modeSelector: some View {
        HStack(spacing: 10) {
            ForEach(CancellationMode.allCases, id: \.self) { m in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        mode = m
                        updateEstimates()
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: m.icon)
                            .font(.system(size: 18))
                        Text(m.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                        Text(m.description)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.35))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundColor(mode == m ? m.color : .white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(mode == m ? m.color.opacity(0.1) : Color.white.opacity(0.02))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(mode == m ? m.color.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Mempool Status
    
    private func mempoolStatusCard(_ info: TransactionCancellationManager.MempoolInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.5))
                Text("Network Status")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                if info.isStale {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 9))
                        Text("Stale")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(Color(red: 1, green: 0.84, blue: 0.04))
                }
            }

            HStack(spacing: 16) {
                feeIndicator(label: "Fast", value: info.fastestFee, color: Color(red: 0.20, green: 0.84, blue: 0.29))
                feeIndicator(label: "Normal", value: info.halfHourFee, color: Color.white.opacity(0.5))
                feeIndicator(label: "Slow", value: info.hourFee, color: Color(red: 1, green: 0.84, blue: 0.04))
            }

            if let size = info.mempoolSize {
                HStack {
                    Text("Mempool:")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                    Text("\(size.formatted()) unconfirmed txs")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .hawalaSectionCard()
    }

    private func feeIndicator(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Fee Section
    
    /// Safe slider range - ensures maxFeeRate > minFeeRate to prevent SwiftUI crash
    private var safeSliderRange: ClosedRange<Double> {
        let safeMin = max(1, minFeeRate)
        let safeMax = max(safeMin + 1, maxFeeRate)
        return safeMin...safeMax
    }
    
    private var feeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("New Fee Rate")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("\(Int(newFeeRate)) \(feeUnit)")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(mode.color)
            }

            Slider(value: $newFeeRate, in: safeSliderRange, step: 1)
                .tint(mode.color)
                .disabled(maxFeeRate <= minFeeRate)
                .onChange(of: newFeeRate) { _ in
                    updateEstimates()
                }

            HStack {
                Text("Min: \(Int(minFeeRate))")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
                Spacer()
                Button("Recommended") {
                    withAnimation { newFeeRate = recommendedFeeRate }
                }
                .font(.system(size: 10))
                .foregroundColor(mode.color)
                .buttonStyle(.plain)
                Spacer()
                Text("Max: \(Int(maxFeeRate))")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
            }

            HStack(spacing: 8) {
                feePresetButton("1.1x", multiplier: 1.1)
                feePresetButton("1.5x", multiplier: 1.5)
                feePresetButton("2x", multiplier: 2.0)
                feePresetButton("3x", multiplier: 3.0)
            }
        }
        .hawalaSectionCard()
    }

    private func feePresetButton(_ label: String, multiplier: Double) -> some View {
        Button {
            withAnimation {
                newFeeRate = min(maxFeeRate, max(minFeeRate, Double(pendingTx.originalFeeRate ?? Int(minFeeRate)) * multiplier))
            }
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.04))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Estimates Section

    private var estimatesSection: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Additional Cost")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
                Text(estimatedCost)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(mode.color.opacity(0.08))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(mode.color.opacity(0.12), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text("Est. Confirmation")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
                Text(estimatedTime)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(red: 0.20, green: 0.84, blue: 0.29).opacity(0.08))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(red: 0.20, green: 0.84, blue: 0.29).opacity(0.12), lineWidth: 1))
        }
    }

    // MARK: - Warning Section

    private var warningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 1, green: 0.84, blue: 0.04))
                Text("Important")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }

            if mode == .cancel {
                Text("This will send all funds from the original transaction back to your wallet. The original recipient will NOT receive any funds.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            } else {
                Text("This will replace the original transaction with a higher fee. The recipient and amount remain the same.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }

            if isBitcoinLike {
                Text("RBF replacement may take a few minutes to propagate through the network.")
                    .font(.system(size: 10))
                    .foregroundColor(Color(red: 1, green: 0.84, blue: 0.04).opacity(0.7))
            }
        }
        .padding(12)
        .background(Color(red: 1, green: 0.84, blue: 0.04).opacity(0.06))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(red: 1, green: 0.84, blue: 0.04).opacity(0.1), lineWidth: 1))
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23))
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
        }
        .padding(12)
        .background(Color(red: 1, green: 0.27, blue: 0.23).opacity(0.08))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(red: 1, green: 0.27, blue: 0.23).opacity(0.12), lineWidth: 1))
    }

    // MARK: - Action Button

    private var actionButton: some View {
        HawalaActionButton(
            icon: isLoading ? "hourglass" : (mode == .cancel ? "xmark.circle.fill" : "bolt.fill"),
            label: mode == .cancel ? "Cancel Transaction" : "Speed Up Transaction",
            style: .primary
        ) {
            Task { await executeAction() }
        }
        .disabled(isLoading || newFeeRate <= minFeeRate)
        .opacity(isLoading || newFeeRate <= minFeeRate ? 0.5 : 1)
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
                case "bitcoin", "bitcoin-mainnet":
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
                let useSepoliaKeys = pendingTx.chainId == "ethereum-sepolia"
                let privateKey = useSepoliaKeys ? keys.ethereumSepolia.privateHex : keys.ethereum.privateHex
                let senderAddress = useSepoliaKeys ? keys.ethereumSepolia.address : keys.ethereum.address
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
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pending Transactions")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                    Text("\(pendingCount) transaction\(pendingCount == 1 ? "" : "s") waiting for confirmation")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.35))
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
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.04))
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(height: 1)

            if pendingTransactions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
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
                    .padding(16)
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
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(Color(red: 0.20, green: 0.84, blue: 0.29))
            Text("All Clear!")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            Text("No pending transactions")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.35))
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
        case "bitcoin", "bitcoin-mainnet", "bitcoin-testnet": return .orange
        case "litecoin": return .gray
        case "ethereum", "ethereum-mainnet", "ethereum-sepolia",
             "arbitrum", "arbitrum-mainnet",
             "optimism", "optimism-mainnet",
             "base", "base-mainnet",
             "scroll", "scroll-mainnet": return Color.white.opacity(0.5)
        case "bnb", "bsc-mainnet": return .yellow
        case "polygon", "polygon-mainnet": return .purple
        case "avalanche", "avalanche-mainnet": return Color(red: 1, green: 0.27, blue: 0.23)
        case "fantom", "fantom-mainnet": return .cyan
        case "gnosis", "gnosis-mainnet": return Color(red: 0.20, green: 0.84, blue: 0.29)
        default: return .purple
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(chainColor.opacity(0.12))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: chainIcon)
                        .font(.system(size: 16))
                        .foregroundColor(chainColor)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(transaction.amount)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))

                    if transaction.confirmations > 0 {
                        Text("\(transaction.confirmations) conf")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Color(red: 0.20, green: 0.84, blue: 0.29))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.20, green: 0.84, blue: 0.29).opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                Text("To: \(truncate(transaction.recipient))")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))

                HStack(spacing: 6) {
                    if let fee = transaction.originalFeeRate {
                        Text("\(fee) \(feeUnit)")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.2))
                    }
                    Circle()
                        .fill(.white.opacity(0.15))
                        .frame(width: 2, height: 2)
                    Text(timeAgo)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.2))
                }
            }

            Spacer()

            if isHovered && transaction.canSpeedUp {
                HStack(spacing: 6) {
                    Button {
                        onSpeedUp()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9))
                            Text("Speed Up")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(Color(red: 1, green: 0.84, blue: 0.04))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(red: 1, green: 0.84, blue: 0.04).opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onCancel()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                            Text("Cancel")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(red: 1, green: 0.27, blue: 0.23).opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.white.opacity(isHovered ? 0.04 : 0.02))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .onHover { isHovered = $0 }
    }
    
    private var chainIcon: String {
        switch transaction.chainId {
        case "bitcoin", "bitcoin-mainnet", "bitcoin-testnet": return "bitcoinsign.circle.fill"
        case "litecoin": return "l.circle.fill"
        case "ethereum", "ethereum-mainnet", "ethereum-sepolia",
             "arbitrum", "arbitrum-mainnet",
             "optimism", "optimism-mainnet",
             "base", "base-mainnet",
             "scroll", "scroll-mainnet": return "diamond.fill"
        case "bnb", "bsc-mainnet": return "b.circle.fill"
        case "polygon", "polygon-mainnet": return "p.circle.fill"
        case "avalanche", "avalanche-mainnet": return "a.circle.fill"
        case "fantom", "fantom-mainnet": return "f.circle.fill"
        case "gnosis", "gnosis-mainnet": return "g.circle.fill"
        default: return "circle.fill"
        }
    }
    
    private var feeUnit: String {
        ["bitcoin", "bitcoin-mainnet", "bitcoin-testnet", "litecoin"].contains(transaction.chainId) ? "sat/vB" : "gwei"
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
