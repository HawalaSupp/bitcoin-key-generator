import SwiftUI

/// Sheet for speeding up (RBF) a stuck transaction
struct SpeedUpTransactionSheet: View {
    let pendingTx: PendingTransactionManager.PendingTransaction
    let keys: AllKeys
    let onDismiss: () -> Void
    let onSuccess: (String) -> Void // New txid
    
    @Environment(\.dismiss) private var dismiss
    @State private var newFeeRate: Double = 0
    @State private var minFeeRate: Double = 0
    @State private var maxFeeRate: Double = 0
    @State private var recommendedFeeRate: Double = 0
    @State private var estimatedCost: String = "—"
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var feeEstimates: BitcoinFeeEstimates?
    
    private var isBitcoinLike: Bool {
        ["bitcoin", "bitcoin-testnet", "litecoin"].contains(pendingTx.chainId)
    }
    
    private var isEthereumLike: Bool {
        ["ethereum", "ethereum-sepolia", "bnb"].contains(pendingTx.chainId)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Transaction info
                transactionInfoCard
                
                // Fee slider
                feeSliderSection
                
                // Cost estimate
                costEstimateSection
                
                Spacer()
                
                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Speed up button
                Button {
                    Task { await speedUpTransaction() }
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Speed Up Transaction")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(isLoading || newFeeRate <= minFeeRate)
            }
            .padding(24)
            .navigationTitle("Speed Up Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 420, height: 500)
        .task {
            await loadFeeEstimates()
        }
    }
    
    private var transactionInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pendingTx.chainName)
                        .font(.headline)
                    Text(pendingTx.amount)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Stuck")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                    if let rate = pendingTx.originalFeeRate {
                        Text("\(rate) \(isBitcoinLike ? "sat/vB" : "gwei")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Divider()
            
            HStack {
                Text("To:")
                    .foregroundStyle(.secondary)
                Text(truncateAddress(pendingTx.recipient))
                    .font(.system(.caption, design: .monospaced))
            }
            
            HStack {
                Text("TX:")
                    .foregroundStyle(.secondary)
                Text(truncateAddress(pendingTx.id))
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.05))
        )
    }
    
    private var feeSliderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("New Fee Rate")
                    .font(.headline)
                Spacer()
                Text("\(Int(newFeeRate)) \(isBitcoinLike ? "sat/vB" : "gwei")")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
            }
            
            Slider(value: $newFeeRate, in: minFeeRate...maxFeeRate, step: 1)
                .tint(.orange)
            
            HStack {
                Text("Min: \(Int(minFeeRate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Recommended") {
                    newFeeRate = recommendedFeeRate
                }
                .font(.caption)
                .buttonStyle(.link)
                Spacer()
                Text("Max: \(Int(maxFeeRate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Fee tier indicators
            HStack(spacing: 8) {
                feeButton(label: "Economy", multiplier: 1.1)
                feeButton(label: "Normal", multiplier: 1.5)
                feeButton(label: "Fast", multiplier: 2.0)
                feeButton(label: "Urgent", multiplier: 3.0)
            }
        }
    }
    
    private func feeButton(label: String, multiplier: Double) -> some View {
        Button {
            newFeeRate = min(maxFeeRate, minFeeRate * multiplier)
        } label: {
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
    
    private var costEstimateSection: some View {
        HStack {
            Text("Estimated Additional Cost")
                .foregroundStyle(.secondary)
            Spacer()
            Text(estimatedCost)
                .fontWeight(.semibold)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
        )
    }
    
    private func truncateAddress(_ address: String) -> String {
        guard address.count > 16 else { return address }
        return "\(address.prefix(8))...\(address.suffix(6))"
    }
    
    private func loadFeeEstimates() async {
        isLoading = true
        
        do {
            if isBitcoinLike {
                let estimates = try await fetchBitcoinFeeEstimates()
                feeEstimates = estimates
                
                // Set min to original + 1 (RBF requires higher fee)
                let originalRate = Double(pendingTx.originalFeeRate ?? estimates.hourFee)
                minFeeRate = originalRate + 1
                maxFeeRate = Double(estimates.fastestFee * 3)
                recommendedFeeRate = Double(estimates.halfHourFee)
                newFeeRate = max(minFeeRate, Double(estimates.halfHourFee))
            } else if isEthereumLike {
                let gasPrice = try await fetchCurrentGasPrice()
                let originalGas = Double(pendingTx.originalFeeRate ?? Int(gasPrice))
                minFeeRate = originalGas * 1.1 // 10% higher minimum
                maxFeeRate = gasPrice * 5
                recommendedFeeRate = gasPrice * 1.5
                newFeeRate = max(minFeeRate, gasPrice * 1.25)
            }
            
            updateCostEstimate()
        } catch {
            errorMessage = "Failed to load fee estimates: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func updateCostEstimate() {
        if isBitcoinLike {
            // Estimate ~200 vBytes for typical tx
            let additionalSats = Int((newFeeRate - minFeeRate + 1) * 200)
            let btc = Double(additionalSats) / 100_000_000
            estimatedCost = String(format: "+%.8f BTC", btc)
        } else if isEthereumLike {
            // 21000 gas for simple transfer
            let additionalGwei = (newFeeRate - minFeeRate / 1.1) * 21000
            let eth = additionalGwei / 1_000_000_000
            estimatedCost = String(format: "+%.6f ETH", eth)
        }
    }
    
    private func fetchBitcoinFeeEstimates() async throws -> BitcoinFeeEstimates {
        let baseURL = pendingTx.chainId == "bitcoin-testnet"
            ? "https://mempool.space/testnet/api"
            : pendingTx.chainId == "litecoin"
                ? "https://litecoinspace.org/api"
                : "https://mempool.space/api"
        
        guard let url = URL(string: "\(baseURL)/v1/fees/recommended") else {
            throw SpeedUpError.networkError
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(BitcoinFeeEstimates.self, from: data)
    }
    
    private func fetchCurrentGasPrice() async throws -> Double {
        let rpcURL: String
        switch pendingTx.chainId {
        case "ethereum": rpcURL = "https://eth.llamarpc.com"
        case "ethereum-sepolia": rpcURL = "https://rpc.sepolia.org"
        case "bnb": rpcURL = "https://bsc-dataseed.binance.org/"
        default: throw SpeedUpError.unsupportedChain
        }
        
        guard let url = URL(string: rpcURL) else {
            throw SpeedUpError.networkError
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_gasPrice",
            "params": [],
            "id": 1
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let result = json?["result"] as? String,
              let weiValue = UInt64(result.dropFirst(2), radix: 16) else {
            throw SpeedUpError.networkError
        }
        
        return Double(weiValue) / 1_000_000_000 // Convert to gwei
    }
    
    private func speedUpTransaction() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let newTxid: String
            
            if isBitcoinLike {
                newTxid = try await speedUpBitcoinTransaction()
            } else if isEthereumLike {
                newTxid = try await speedUpEthereumTransaction()
            } else {
                throw SpeedUpError.unsupportedChain
            }
            
            // Mark original as replaced
            await PendingTransactionManager.shared.markReplaced(pendingTx.id, replacedBy: newTxid)
            
            // Add new transaction
            await PendingTransactionManager.shared.add(
                txid: newTxid,
                chainId: pendingTx.chainId,
                chainName: pendingTx.chainName,
                amount: pendingTx.amount,
                recipient: pendingTx.recipient,
                isRBFEnabled: true,
                feeRate: Int(newFeeRate),
                nonce: pendingTx.nonce
            )
            
            await MainActor.run {
                onSuccess(newTxid)
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    private func speedUpBitcoinTransaction() async throws -> String {
        // Use TransactionCancellationManager for Bitcoin RBF
        let cancellationManager = TransactionCancellationManager.shared
        
        // Get the private key WIF for the appropriate chain
        let privateWIF: String
        switch pendingTx.chainId {
        case "litecoin":
            privateWIF = keys.litecoin.privateWif
        case "bitcoin-testnet":
            privateWIF = keys.bitcoinTestnet.privateWif
        default: // "bitcoin"
            privateWIF = keys.bitcoin.privateWif
        }
        
        // Call the speed-up method
        let result = try await cancellationManager.speedUpBitcoinTransaction(
            pendingTx: pendingTx,
            privateKeyWIF: privateWIF,
            newFeeRate: Int(newFeeRate)
        )
        
        guard result.success, let newTxid = result.replacementTxid else {
            throw SpeedUpError.broadcastFailed(result.message)
        }
        
        return newTxid
    }
    
    private func speedUpEthereumTransaction() async throws -> String {
        guard let nonce = pendingTx.nonce else {
            throw SpeedUpError.missingNonce
        }
        
        // For Ethereum, we send a new transaction with same nonce but higher gas
        let rpcURL: String
        let chainId: Int
        
        switch pendingTx.chainId {
        case "ethereum":
            rpcURL = "https://eth.llamarpc.com"
            chainId = 1
        case "ethereum-sepolia":
            rpcURL = "https://rpc.sepolia.org"
            chainId = 11155111
        case "bnb":
            rpcURL = "https://bsc-dataseed.binance.org/"
            chainId = 56
        default:
            throw SpeedUpError.unsupportedChain
        }
        
        // Get the private key
        let privateKey = keys.ethereum.privateHex
        
        // Build replacement transaction with same nonce, higher gas
        let gasPriceWei = UInt64(newFeeRate * 1_000_000_000)
        
        // Parse amount from transaction
        let amountString = pendingTx.amount.components(separatedBy: " ").first ?? "0"
        guard let amountDouble = Double(amountString) else {
            throw SpeedUpError.invalidAmount
        }
        let weiAmount = UInt64(amountDouble * 1e18)
        
        let signedTx = try EthereumTransaction.buildAndSign(
            to: pendingTx.recipient,
            value: String(weiAmount),
            gasLimit: 21000,
            gasPrice: String(gasPriceWei),
            nonce: nonce,
            chainId: chainId,
            privateKeyHex: privateKey
        )
        
        // Broadcast
        guard let url = URL(string: rpcURL) else {
            throw SpeedUpError.networkError
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_sendRawTransaction",
            "params": [signedTx],
            "id": 1
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        if let error = json?["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw SpeedUpError.broadcastFailed(message)
        }
        
        guard let txid = json?["result"] as? String else {
            throw SpeedUpError.broadcastFailed("No transaction ID returned")
        }
        
        return txid
    }
}

// MARK: - Errors

enum SpeedUpError: LocalizedError {
    case networkError
    case unsupportedChain
    case missingNonce
    case invalidAmount
    case broadcastFailed(String)
    case featureInProgress(String)
    
    var errorDescription: String? {
        switch self {
        case .networkError: return "Network error. Please try again."
        case .unsupportedChain: return "Speed-up not supported for this chain."
        case .missingNonce: return "Missing transaction nonce. Cannot speed up."
        case .invalidAmount: return "Invalid transaction amount."
        case .broadcastFailed(let msg): return "Broadcast failed: \(msg)"
        case .featureInProgress(let msg): return msg
        }
    }
}
