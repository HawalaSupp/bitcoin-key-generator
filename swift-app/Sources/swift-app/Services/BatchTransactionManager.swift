import SwiftUI
import Foundation

// MARK: - Batch Transaction Models

/// A single recipient in a batch transaction
struct BatchRecipient: Identifiable, Codable, Equatable {
    let id: UUID
    var address: String
    var amount: String
    var label: String?
    var isValid: Bool
    var validationError: String?
    
    init(id: UUID = UUID(), address: String = "", amount: String = "", label: String? = nil) {
        self.id = id
        self.address = address
        self.amount = amount
        self.label = label
        self.isValid = false
        self.validationError = nil
    }
    
    var amountDouble: Double {
        Double(amount) ?? 0
    }
}

/// Supported chains for batch transactions
enum BatchChain: String, CaseIterable, Identifiable {
    case bitcoin = "bitcoin"
    case ethereum = "ethereum"
    case bnb = "bnb"
    case solana = "solana"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .bitcoin: return "Bitcoin"
        case .ethereum: return "Ethereum"
        case .bnb: return "BNB Chain"
        case .solana: return "Solana"
        }
    }
    
    var symbol: String {
        switch self {
        case .bitcoin: return "BTC"
        case .ethereum: return "ETH"
        case .bnb: return "BNB"
        case .solana: return "SOL"
        }
    }
    
    var color: Color {
        switch self {
        case .bitcoin: return HawalaTheme.Colors.bitcoin
        case .ethereum: return HawalaTheme.Colors.ethereum
        case .bnb: return HawalaTheme.Colors.bnb
        case .solana: return HawalaTheme.Colors.solana
        }
    }
    
    var icon: String {
        switch self {
        case .bitcoin: return "bitcoinsign.circle.fill"
        case .ethereum: return "diamond.fill"
        case .bnb: return "b.circle.fill"
        case .solana: return "sun.max.fill"
        }
    }
    
    var supportsBatching: Bool {
        switch self {
        case .ethereum, .bnb: return true // Native batching via smart contract or multiple txs
        case .bitcoin, .solana: return true // Can send to multiple outputs/accounts
        }
    }
}

// MARK: - Batch Transaction Manager

@MainActor
final class BatchTransactionManager: ObservableObject {
    static let shared = BatchTransactionManager()
    
    @Published var recipients: [BatchRecipient] = [BatchRecipient()]
    @Published var selectedChain: BatchChain = .ethereum
    @Published var isProcessing = false
    @Published var error: String?
    @Published var successCount = 0
    @Published var failedCount = 0
    
    private init() {}
    
    // MARK: - Recipient Management
    
    func addRecipient() {
        recipients.append(BatchRecipient())
    }
    
    func removeRecipient(_ recipient: BatchRecipient) {
        recipients.removeAll { $0.id == recipient.id }
        if recipients.isEmpty {
            recipients.append(BatchRecipient())
        }
    }
    
    func updateRecipient(_ recipient: BatchRecipient) {
        if let index = recipients.firstIndex(where: { $0.id == recipient.id }) {
            var updated = recipient
            updated.isValid = validateRecipient(updated)
            recipients[index] = updated
        }
    }
    
    func clearAll() {
        recipients = [BatchRecipient()]
        error = nil
        successCount = 0
        failedCount = 0
    }
    
    // MARK: - Validation
    
    func validateRecipient(_ recipient: BatchRecipient) -> Bool {
        guard !recipient.address.isEmpty else { return false }
        guard recipient.amountDouble > 0 else { return false }
        return validateAddress(recipient.address, chain: selectedChain)
    }
    
    func validateAddress(_ address: String, chain: BatchChain) -> Bool {
        switch chain {
        case .bitcoin:
            // Basic Bitcoin address validation
            return address.hasPrefix("1") || address.hasPrefix("3") || address.hasPrefix("bc1") || address.hasPrefix("tb1")
        case .ethereum, .bnb:
            // Ethereum/BNB address validation
            let pattern = "^0x[a-fA-F0-9]{40}$"
            return address.range(of: pattern, options: .regularExpression) != nil
        case .solana:
            // Solana address validation (base58, 32-44 chars)
            let base58Chars = CharacterSet(charactersIn: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
            return address.count >= 32 && address.count <= 44 && address.unicodeScalars.allSatisfy { base58Chars.contains($0) }
        }
    }
    
    var totalAmount: Double {
        recipients.reduce(0) { $0 + $1.amountDouble }
    }
    
    var validRecipientsCount: Int {
        recipients.filter { $0.isValid }.count
    }
    
    var canExecute: Bool {
        validRecipientsCount > 0 && !isProcessing
    }
    
    // MARK: - CSV Import
    
    func importFromCSV(_ csvContent: String) {
        let lines = csvContent.components(separatedBy: .newlines)
        var imported: [BatchRecipient] = []
        
        for line in lines {
            let parts = line.components(separatedBy: ",")
            guard parts.count >= 2 else { continue }
            
            let address = parts[0].trimmingCharacters(in: .whitespaces)
            let amount = parts[1].trimmingCharacters(in: .whitespaces)
            let label = parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespaces) : nil
            
            guard !address.isEmpty, !amount.isEmpty else { continue }
            
            var recipient = BatchRecipient(address: address, amount: amount, label: label)
            recipient.isValid = validateRecipient(recipient)
            imported.append(recipient)
        }
        
        if !imported.isEmpty {
            recipients = imported
        }
    }
    
    // MARK: - Export Template
    
    func exportTemplate() -> String {
        """
        # Batch Transaction CSV Template
        # Format: address,amount,label (optional)
        # Example:
        0x1234567890abcdef1234567890abcdef12345678,0.1,Payment 1
        0xabcdef1234567890abcdef1234567890abcdef12,0.25,Payment 2
        """
    }
    
    // MARK: - Batch Execution
    
    /// Result of a single transaction in a batch
    struct BatchTxResult: Identifiable {
        let id: UUID
        let recipient: BatchRecipient
        let success: Bool
        let txHash: String?
        let error: String?
    }
    
    @Published var results: [BatchTxResult] = []
    
    /// Execute all valid batch transactions
    /// Note: Full blockchain integration pending - uses SendView's existing send logic
    func executeBatch(keys: AllKeys, isTestnet: Bool = false) async {
        isProcessing = true
        error = nil
        successCount = 0
        failedCount = 0
        results = []
        
        let validRecipients = recipients.filter { $0.isValid }
        
        for recipient in validRecipients {
            do {
                let txHash = try await sendSingleTransaction(
                    to: recipient,
                    keys: keys,
                    isTestnet: isTestnet
                )
                
                results.append(BatchTxResult(
                    id: recipient.id,
                    recipient: recipient,
                    success: true,
                    txHash: txHash,
                    error: nil
                ))
                successCount += 1
                
                // Small delay between transactions to avoid rate limiting
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                
            } catch {
                results.append(BatchTxResult(
                    id: recipient.id,
                    recipient: recipient,
                    success: false,
                    txHash: nil,
                    error: error.localizedDescription
                ))
                failedCount += 1
            }
        }
        
        isProcessing = false
    }
    
    /// Send a single transaction within the batch
    private func sendSingleTransaction(
        to recipient: BatchRecipient,
        keys: AllKeys,
        isTestnet: Bool
    ) async throws -> String {
        switch selectedChain {
        case .bitcoin:
            return try await sendBitcoinTx(to: recipient, keys: keys, isTestnet: isTestnet)
        case .ethereum:
            return try await sendEthereumTx(to: recipient, keys: keys, isTestnet: isTestnet)
        case .bnb:
            return try await sendBnbTx(to: recipient, keys: keys)
        case .solana:
            return try await sendSolanaTx(to: recipient, keys: keys, isTestnet: isTestnet)
        }
    }
    
    private func sendBitcoinTx(to recipient: BatchRecipient, keys: AllKeys, isTestnet: Bool) async throws -> String {
        let amountSats = UInt64(recipient.amountDouble * 100_000_000)
        let wif = isTestnet ? keys.bitcoinTestnet.privateWif : keys.bitcoin.privateWif
        let feeRate: UInt64 = 10 // Default 10 sat/vB for batch
        
        // Get UTXOs
        let manager = UTXOCoinControlManager.shared
        let targetAmount = amountSats + (feeRate * 200) + 1000
        let selected = manager.selectUTXOs(for: targetAmount)
        
        let rustUTXOs = selected.map { u in
            RustCLIBridge.RustUTXO(
                txid: u.txid,
                vout: UInt32(u.vout),
                value: u.value,
                status: RustCLIBridge.RustUTXOStatus(
                    confirmed: u.confirmations > 0,
                    block_height: nil,
                    block_hash: nil,
                    block_time: nil
                )
            )
        }
        
        let signedHex = try RustCLIBridge.shared.signBitcoin(
            recipient: recipient.address,
            amountSats: amountSats,
            feeRate: feeRate,
            senderWIF: wif,
            utxos: rustUTXOs.isEmpty ? nil : rustUTXOs
        )
        
        let txId = try await TransactionBroadcaster.shared.broadcastBitcoin(rawTxHex: signedHex, isTestnet: isTestnet)
        return txId
    }
    
    private func sendEthereumTx(to recipient: BatchRecipient, keys: AllKeys, isTestnet: Bool) async throws -> String {
        let senderKey = isTestnet ? keys.ethereumSepolia.privateHex : keys.ethereum.privateHex
        let senderAddress = isTestnet ? keys.ethereumSepolia.address : keys.ethereum.address
        let chainId: UInt64 = isTestnet ? 11155111 : 1
        
        // Convert amount to Wei using Decimal for precision
        let amountWei: String = {
            guard let decimalAmount = Decimal(string: recipient.amount), decimalAmount > 0 else {
                return "0"
            }
            let weiPerETH = NSDecimalNumber(mantissa: 1_000_000_000_000_000_000, exponent: 0, isNegative: false)
            let eth = NSDecimalNumber(decimal: decimalAmount)
            let wei = eth.multiplying(by: weiPerETH)
                .rounding(accordingToBehavior: NSDecimalNumberHandler(
                    roundingMode: .down,
                    scale: 0,
                    raiseOnExactness: false,
                    raiseOnOverflow: false,
                    raiseOnUnderflow: false,
                    raiseOnDivideByZero: false
                ))
            return wei.stringValue
        }()
        
        // Get nonce
        let chainKey = isTestnet ? "ethereum-sepolia" : "ethereum"
        let nonce = try await EVMNonceManager.shared.getNextNonce(for: senderAddress, chainId: chainKey)
        EVMNonceManager.shared.reserveNonce(nonce, chainId: chainKey)
        
        // Default gas settings for simple ETH transfer
        let gasLimit: UInt64 = 21000
        let gasPriceWei = "20000000000" // 20 Gwei default
        
        let signedTx = try RustCLIBridge.shared.signEthereum(
            recipient: recipient.address,
            amountWei: amountWei,
            chainId: chainId,
            senderKey: senderKey,
            nonce: nonce,
            gasLimit: gasLimit,
            gasPrice: gasPriceWei
        )
        
        let txHash = try await TransactionBroadcaster.shared.broadcastEthereum(
            rawTxHex: signedTx,
            isTestnet: isTestnet
        )
        
        return txHash
    }
    
    private func sendBnbTx(to recipient: BatchRecipient, keys: AllKeys) async throws -> String {
        let senderKey = keys.bnb.privateHex
        let senderAddress = keys.bnb.address
        let chainId: UInt64 = 56
        
        let amountWei: String = {
            guard let decimalAmount = Decimal(string: recipient.amount), decimalAmount > 0 else {
                return "0"
            }
            let weiPerBNB = NSDecimalNumber(mantissa: 1_000_000_000_000_000_000, exponent: 0, isNegative: false)
            let bnb = NSDecimalNumber(decimal: decimalAmount)
            let wei = bnb.multiplying(by: weiPerBNB)
                .rounding(accordingToBehavior: NSDecimalNumberHandler(
                    roundingMode: .down,
                    scale: 0,
                    raiseOnExactness: false,
                    raiseOnOverflow: false,
                    raiseOnUnderflow: false,
                    raiseOnDivideByZero: false
                ))
            return wei.stringValue
        }()
        
        let nonce = try await EVMNonceManager.shared.getNextNonce(for: senderAddress, chainId: "56")
        EVMNonceManager.shared.reserveNonce(nonce, chainId: "56")
        
        let gasLimit: UInt64 = 21000
        let gasPriceWei = "5000000000" // 5 Gwei for BNB Chain
        
        let signedTx = try RustCLIBridge.shared.signEthereum(
            recipient: recipient.address,
            amountWei: amountWei,
            chainId: chainId,
            senderKey: senderKey,
            nonce: nonce,
            gasLimit: gasLimit,
            gasPrice: gasPriceWei
        )
        
        let txHash = try await TransactionBroadcaster.shared.broadcastEthereumToChain(
            rawTxHex: signedTx,
            chainId: 56
        )
        
        return txHash
    }
    
    private func sendSolanaTx(to recipient: BatchRecipient, keys: AllKeys, isTestnet: Bool) async throws -> String {
        // Solana requires a recent blockhash - fetch it first
        let rpcURL = isTestnet ? "https://api.devnet.solana.com" : "https://api.mainnet-beta.solana.com"
        
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getLatestBlockhash",
            "params": [["commitment": "finalized"]]
        ]
        
        guard let url = URL(string: rpcURL) else {
            throw NSError(domain: "BatchTx", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid RPC URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let value = result["value"] as? [String: Any],
              let blockhash = value["blockhash"] as? String else {
            throw NSError(domain: "BatchTx", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get blockhash"])
        }
        
        let amountSol = recipient.amountDouble
        let senderBase58 = keys.solana.privateKeyBase58
        
        let signedTx = try RustCLIBridge.shared.signSolana(
            recipient: recipient.address,
            amountSol: amountSol,
            recentBlockhash: blockhash,
            senderBase58: senderBase58
        )
        
        let txHash = try await TransactionBroadcaster.shared.broadcastSolana(
            rawTxBase64: signedTx,
            isDevnet: isTestnet
        )
        
        return txHash
    }
}

// MARK: - Batch Transaction View

struct BatchTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = BatchTransactionManager.shared
    @State private var showImportSheet = false
    @State private var showConfirmation = false
    @State private var showResults = false
    @State private var csvContent = ""
    @State private var useTestnet = false
    
    // Keys passed from parent
    let keys: AllKeys?
    
    init(keys: AllKeys? = nil) {
        self.keys = keys
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
                .background(HawalaTheme.Colors.border)
            
            // Chain selector
            chainSelector
                .padding(HawalaTheme.Spacing.lg)
            
            // Recipients list
            ScrollView {
                VStack(spacing: HawalaTheme.Spacing.md) {
                    ForEach(manager.recipients) { recipient in
                        RecipientRow(recipient: recipient, chain: manager.selectedChain)
                    }
                    
                    // Add recipient button
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            manager.addRecipient()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Recipient")
                        }
                        .font(HawalaTheme.Typography.body)
                        .foregroundColor(HawalaTheme.Colors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(HawalaTheme.Spacing.md)
                        .background(HawalaTheme.Colors.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                                .strokeBorder(HawalaTheme.Colors.accent.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(HawalaTheme.Spacing.lg)
            }
            
            Divider()
                .background(HawalaTheme.Colors.border)
            
            // Summary & Actions
            summary
        }
        .frame(width: 600, height: 700)
        .background(HawalaTheme.Colors.background)
        .sheet(isPresented: $showImportSheet) {
            CSVImportSheet(csvContent: $csvContent) {
                manager.importFromCSV(csvContent)
                showImportSheet = false
            }
        }
        .sheet(isPresented: $showResults) {
            BatchResultsSheet(results: manager.results, chain: manager.selectedChain)
        }
        .alert("Confirm Batch Transaction", isPresented: $showConfirmation) {
            Toggle("Use Testnet", isOn: $useTestnet)
            Button("Cancel", role: .cancel) { }
            Button("Send") {
                executeBatch()
            }
        } message: {
            Text("Send \(String(format: "%.6f", manager.totalAmount)) \(manager.selectedChain.symbol) to \(manager.validRecipientsCount) recipients?")
        }
    }
    
    @AppStorage("hawala.biometricForSends") private var biometricForSends = true
    
    private func executeBatch() {
        guard let keys = keys else {
            ToastManager.shared.error("Wallet not loaded")
            return
        }
        
        // Check biometric authentication if enabled
        if BiometricAuthHelper.shouldRequireBiometric(settingEnabled: biometricForSends) {
            Task { @MainActor in
                let result = await BiometricAuthHelper.authenticate(
                    reason: "Authenticate to send batch transaction"
                )
                switch result {
                case .success:
                    await performBatchExecution(keys: keys)
                case .cancelled:
                    #if DEBUG
                    print("[BatchTransaction] Biometric cancelled by user")
                    #endif
                    return
                case .failed(let message):
                    ToastManager.shared.error("Authentication failed: \(message)")
                    return
                case .notAvailable:
                    // Biometric not available, proceed anyway
                    await performBatchExecution(keys: keys)
                }
            }
        } else {
            Task { @MainActor in
                await performBatchExecution(keys: keys)
            }
        }
    }
    
    @MainActor
    private func performBatchExecution(keys: AllKeys) async {
        await manager.executeBatch(keys: keys, isTestnet: useTestnet)
        
        if manager.successCount > 0 {
            ToastManager.shared.success("\(manager.successCount) transactions sent successfully")
        }
        if manager.failedCount > 0 {
            ToastManager.shared.error("\(manager.failedCount) transactions failed")
        }
        showResults = true
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Batch Transaction")
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("Send to multiple addresses at once")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            
            Spacer()
            
            // Import CSV
            Button {
                showImportSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                    Text("Import CSV")
                }
                .font(HawalaTheme.Typography.caption)
                .padding(.horizontal, HawalaTheme.Spacing.md)
                .padding(.vertical, HawalaTheme.Spacing.sm)
                .background(HawalaTheme.Colors.backgroundTertiary)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
            }
            .buttonStyle(.plain)
            
            // Clear all
            Button {
                manager.clearAll()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(HawalaTheme.Colors.error)
                    .frame(width: 32, height: 32)
                    .background(HawalaTheme.Colors.error.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Clear all recipients")
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(HawalaTheme.Spacing.lg)
    }
    
    private var chainSelector: some View {
        HStack(spacing: HawalaTheme.Spacing.sm) {
            ForEach(BatchChain.allCases) { chain in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        manager.selectedChain = chain
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: chain.icon)
                            .font(.system(size: 14))
                        Text(chain.symbol)
                            .font(HawalaTheme.Typography.captionBold)
                    }
                    .padding(.horizontal, HawalaTheme.Spacing.md)
                    .padding(.vertical, HawalaTheme.Spacing.sm)
                    .background(manager.selectedChain == chain ? chain.color.opacity(0.2) : HawalaTheme.Colors.backgroundTertiary)
                    .foregroundColor(manager.selectedChain == chain ? chain.color : HawalaTheme.Colors.textSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm)
                            .strokeBorder(manager.selectedChain == chain ? chain.color : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
    }
    
    private var summary: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            // Stats
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recipients")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    Text("\(manager.validRecipientsCount) of \(manager.recipients.count)")
                        .font(HawalaTheme.Typography.h4)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total Amount")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    Text("\(String(format: "%.6f", manager.totalAmount)) \(manager.selectedChain.symbol)")
                        .font(HawalaTheme.Typography.h4)
                        .foregroundColor(manager.selectedChain.color)
                }
            }
            
            // Send button
            Button {
                showConfirmation = true
            } label: {
                HStack {
                    if manager.isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                    Text(manager.isProcessing ? "Processing..." : "Send Batch Transaction")
                }
                .font(HawalaTheme.Typography.body)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(HawalaTheme.Spacing.md)
                .background(manager.canExecute ? manager.selectedChain.color : HawalaTheme.Colors.textTertiary)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
            }
            .buttonStyle(.plain)
            .disabled(!manager.canExecute)
        }
        .padding(HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.backgroundSecondary)
    }
}

// MARK: - Recipient Row

struct RecipientRow: View {
    let recipient: BatchRecipient
    let chain: BatchChain
    @ObservedObject private var manager = BatchTransactionManager.shared
    
    @State private var address: String
    @State private var amount: String
    @State private var label: String
    @State private var isHovered = false
    
    init(recipient: BatchRecipient, chain: BatchChain) {
        self.recipient = recipient
        self.chain = chain
        _address = State(initialValue: recipient.address)
        _amount = State(initialValue: recipient.amount)
        _label = State(initialValue: recipient.label ?? "")
    }
    
    var body: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            // Validation indicator
            Circle()
                .fill(recipient.isValid ? HawalaTheme.Colors.success : HawalaTheme.Colors.error.opacity(0.5))
                .frame(width: 8, height: 8)
            
            VStack(spacing: HawalaTheme.Spacing.sm) {
                // Address field
                HStack {
                    Image(systemName: "location.fill")
                        .font(.system(size: 12))
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    
                    TextField("Recipient address", text: $address)
                        .textFieldStyle(.plain)
                        .font(HawalaTheme.Typography.mono)
                        .onChange(of: address) { newValue in
                            var updated = recipient
                            updated.address = newValue
                            manager.updateRecipient(updated)
                        }
                }
                .padding(HawalaTheme.Spacing.sm)
                .background(HawalaTheme.Colors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
                
                HStack(spacing: HawalaTheme.Spacing.sm) {
                    // Amount field
                    HStack {
                        TextField("0.0", text: $amount)
                            .textFieldStyle(.plain)
                            .font(HawalaTheme.Typography.body)
                            .onChange(of: amount) { newValue in
                                var updated = recipient
                                updated.amount = newValue
                                manager.updateRecipient(updated)
                            }
                        
                        Text(chain.symbol)
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                    .padding(HawalaTheme.Spacing.sm)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
                    .frame(width: 150)
                    
                    // Label field (optional)
                    HStack {
                        Image(systemName: "tag")
                            .font(.system(size: 10))
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                        
                        TextField("Label (optional)", text: $label)
                            .textFieldStyle(.plain)
                            .font(HawalaTheme.Typography.caption)
                            .onChange(of: label) { newValue in
                                var updated = recipient
                                updated.label = newValue.isEmpty ? nil : newValue
                                manager.updateRecipient(updated)
                            }
                    }
                    .padding(HawalaTheme.Spacing.sm)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
                }
            }
            
            // Delete button
            if isHovered && manager.recipients.count > 1 {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        manager.removeRecipient(recipient)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(HawalaTheme.Colors.error)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(HawalaTheme.Spacing.md)
        .background(isHovered ? HawalaTheme.Colors.backgroundHover : HawalaTheme.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                .strokeBorder(recipient.isValid ? Color.clear : HawalaTheme.Colors.error.opacity(0.3), lineWidth: 1)
        )
        .onHover { isHovered = $0 }
    }
}

// MARK: - CSV Import Sheet

struct CSVImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var csvContent: String
    let onImport: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Import from CSV")
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(HawalaTheme.Colors.backgroundTertiary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(HawalaTheme.Spacing.lg)
            
            Divider()
                .background(HawalaTheme.Colors.border)
            
            // Instructions
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                Text("CSV Format")
                    .font(HawalaTheme.Typography.captionBold)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                
                Text("Each line: address,amount,label (optional)")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                Text("Example:")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                    .padding(.top, 4)
                
                Text("0x1234...5678,0.1,Payment 1\n0xabcd...ef12,0.25,Payment 2")
                    .font(HawalaTheme.Typography.mono)
                    .foregroundColor(HawalaTheme.Colors.accent)
                    .padding(HawalaTheme.Spacing.sm)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HawalaTheme.Spacing.lg)
            
            // Text editor
            TextEditor(text: $csvContent)
                .font(HawalaTheme.Typography.mono)
                .padding(HawalaTheme.Spacing.sm)
                .background(HawalaTheme.Colors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                .padding(.horizontal, HawalaTheme.Spacing.lg)
                .frame(minHeight: 200)
            
            Divider()
                .background(HawalaTheme.Colors.border)
                .padding(.top, HawalaTheme.Spacing.lg)
            
            // Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                
                Spacer()
                
                Button {
                    onImport()
                } label: {
                    Text("Import")
                        .padding(.horizontal, HawalaTheme.Spacing.xl)
                }
                .buttonStyle(.borderedProminent)
                .tint(HawalaTheme.Colors.accent)
                .disabled(csvContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(HawalaTheme.Spacing.lg)
        }
        .frame(width: 450, height: 500)
        .background(HawalaTheme.Colors.background)
    }
}

// MARK: - Batch Results Sheet

struct BatchResultsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let results: [BatchTransactionManager.BatchTxResult]
    let chain: BatchChain
    
    var successCount: Int {
        results.filter { $0.success }.count
    }
    
    var failedCount: Int {
        results.filter { !$0.success }.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Batch Results")
                        .font(HawalaTheme.Typography.h3)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    Text("\(successCount) successful, \(failedCount) failed")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(failedCount > 0 ? HawalaTheme.Colors.warning : HawalaTheme.Colors.success)
                }
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(HawalaTheme.Colors.backgroundTertiary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(HawalaTheme.Spacing.lg)
            
            Divider()
                .background(HawalaTheme.Colors.border)
            
            // Results list
            ScrollView {
                VStack(spacing: HawalaTheme.Spacing.sm) {
                    ForEach(results) { result in
                        BatchResultRow(result: result, chain: chain)
                    }
                }
                .padding(HawalaTheme.Spacing.lg)
            }
            
            Divider()
                .background(HawalaTheme.Colors.border)
            
            // Footer
            HStack {
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(HawalaTheme.Colors.accent)
            }
            .padding(HawalaTheme.Spacing.lg)
        }
        .frame(width: 550, height: 500)
        .background(HawalaTheme.Colors.background)
    }
}

struct BatchResultRow: View {
    let result: BatchTransactionManager.BatchTxResult
    let chain: BatchChain
    
    var body: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            // Status icon
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(result.success ? HawalaTheme.Colors.success : HawalaTheme.Colors.error)
            
            VStack(alignment: .leading, spacing: 2) {
                // Address (truncated)
                Text(truncatedAddress(result.recipient.address))
                    .font(HawalaTheme.Typography.mono)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                // Amount and label
                HStack {
                    Text("\(result.recipient.amount) \(chain.symbol)")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(chain.color)
                    
                    if let label = result.recipient.label, !label.isEmpty {
                        Text("• \(label)")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                }
            }
            
            Spacer()
            
            // Transaction hash or error
            if result.success, let txHash = result.txHash {
                Button {
                    // Copy tx hash to clipboard
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(txHash, forType: .string)
                    ToastManager.shared.success("Transaction hash copied")
                } label: {
                    HStack(spacing: 4) {
                        Text(truncatedHash(txHash))
                            .font(HawalaTheme.Typography.mono)
                            .foregroundColor(HawalaTheme.Colors.accent)
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                }
                .buttonStyle(.plain)
            } else if let error = result.error {
                Text(error)
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.error)
                    .lineLimit(1)
                    .frame(maxWidth: 150)
            }
        }
        .padding(HawalaTheme.Spacing.md)
        .background(result.success ? HawalaTheme.Colors.success.opacity(0.05) : HawalaTheme.Colors.error.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                .strokeBorder(result.success ? HawalaTheme.Colors.success.opacity(0.2) : HawalaTheme.Colors.error.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func truncatedAddress(_ address: String) -> String {
        guard address.count > 16 else { return address }
        return "\(address.prefix(8))...\(address.suffix(6))"
    }
    
    private func truncatedHash(_ hash: String) -> String {
        guard hash.count > 12 else { return hash }
        return "\(hash.prefix(6))...\(hash.suffix(4))"
    }
}

// MARK: - Preview

#if DEBUG
struct BatchTransactionView_Previews: PreviewProvider {
    static var previews: some View {
        BatchTransactionView()
            .preferredColorScheme(.dark)
    }
}
#endif
