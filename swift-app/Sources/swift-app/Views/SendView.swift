import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

enum Chain: String, CaseIterable, Identifiable {
    case bitcoin
    case ethereum
    case solana
    case xrp
    case monero
    
    var id: String { self.rawValue }
    
    var chainId: String {
        switch self {
        case .bitcoin: return "bitcoin-testnet"
        case .ethereum: return "ethereum-sepolia"
        case .solana: return "solana"
        case .xrp: return "xrp"
        case .monero: return "monero"
        }
    }
    
    var iconName: String {
        switch self {
        case .bitcoin: return "bitcoinsign"
        case .ethereum: return "e.circle.fill"
        case .solana: return "s.circle.fill"
        case .xrp: return "x.circle.fill"
        case .monero: return "m.circle.fill"
        }
    }
}

struct SendView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var walletRepository = WalletRepository.shared
    @ObservedObject var broadcaster = TransactionBroadcaster.shared
    @ObservedObject var addressValidator = ChainAddressValidator.shared
    @StateObject private var feeEstimator = FeeEstimator.shared
    
    @State private var selectedChain: Chain
    @State private var recipientAddress: String = ""
    @State private var amount: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successTxId: String?
    
    // Address validation state
    @State private var addressValidationResult: ChainAddressValidationResult?
    @State private var isValidatingAddress = false
    @State private var resolvedENSName: String?
    
    // Fee selection state
    @State private var selectedFeePriority: FeePriority = .average
    @State private var useCustomFee: Bool = false
    @State private var customFeeRate: String = ""
    
    // Review screen state
    @State private var showingReview = false
    @State private var reviewData: TransactionReviewData?
    
    // Chain specific fields
    @State private var feeRate: String = "5" // sat/vB for BTC
    @State private var gasPrice: String = "20" // Gwei for ETH
    @State private var gasLimit: String = "21000" // Gas limit for ETH
    @State private var destinationTag: String = "" // For XRP
    
    // QR Scanner state
    @State private var showingQRScanner = false
    @State private var scannedQRResult: ParsedQRCode?
    
    // Animation
    @State private var appearAnimation = false
    
    var onSuccess: ((TransactionBroadcastResult) -> Void)?
    
    init(initialChain: Chain = .bitcoin, onSuccess: ((TransactionBroadcastResult) -> Void)? = nil) {
        _selectedChain = State(initialValue: initialChain)
        self.onSuccess = onSuccess
    }
    
    var body: some View {
        ZStack {
            // Dark background
            HawalaTheme.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Custom Header
                sendHeader
                
                // Scrollable Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: HawalaTheme.Spacing.lg) {
                        // Chain Selector
                        chainSelectorSection
                        
                        // Recipient Address
                        recipientSection
                        
                        // Amount Input
                        amountSection
                        
                        // Fee Settings (BTC/ETH only)
                        if selectedChain == .bitcoin || selectedChain == .ethereum {
                            feeSection
                        }
                        
                        // XRP Destination Tag
                        if selectedChain == .xrp {
                            xrpOptionsSection
                        }
                        
                        // Error Message
                        if let error = errorMessage {
                            errorBanner(error)
                        }
                        
                        // Success Message
                        if let txId = successTxId {
                            successBanner(txId)
                        }
                        
                        // Bottom spacer for button
                        Color.clear.frame(height: 100)
                    }
                    .padding(.horizontal, HawalaTheme.Spacing.lg)
                    .padding(.top, HawalaTheme.Spacing.md)
                }
                
                // Bottom Action Button
                bottomActionBar
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(HawalaTheme.Animation.spring) {
                appearAnimation = true
            }
            Task {
                await feeEstimator.fetchBitcoinFees(isTestnet: true)
                await feeEstimator.fetchEthereumFees()
            }
        }
        .onChange(of: selectedChain) { _ in
            updateFeeFromPriority()
            if !recipientAddress.isEmpty {
                validateAddressAsync()
            }
        }
        .onChange(of: selectedFeePriority) { _ in
            updateFeeFromPriority()
        }
        .sheet(isPresented: $showingReview) {
            if let data = reviewData {
                TransactionReviewView(
                    transaction: data,
                    onConfirm: {
                        showingReview = false
                        sendTransaction()
                    },
                    onCancel: {
                        showingReview = false
                    }
                )
                .frame(minWidth: 400, minHeight: 600)
            }
        }
    }
    
    // MARK: - Header
    
    private var sendHeader: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text("Send")
                .font(HawalaTheme.Typography.h3)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
            
            Spacer()
            
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, HawalaTheme.Spacing.lg)
        .padding(.vertical, HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.background)
    }
    
    // MARK: - Chain Selector
    
    private var chainSelectorSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            Text("NETWORK")
                .font(HawalaTheme.Typography.label)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
                .tracking(1)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HawalaTheme.Spacing.sm) {
                    ForEach(Chain.allCases) { chain in
                        SendChainPill(
                            chain: chain,
                            isSelected: selectedChain == chain,
                            action: { selectedChain = chain }
                        )
                    }
                }
            }
        }
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
    }
    
    // MARK: - Recipient Section
    
    private var recipientSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            HStack {
                Text("RECIPIENT")
                    .font(HawalaTheme.Typography.label)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                    .tracking(1)
                
                Spacer()
                
                // Validation Status
                if isValidatingAddress {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(HawalaTheme.Colors.accent)
                } else if let result = addressValidationResult {
                    HStack(spacing: 4) {
                        Image(systemName: result.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        Text(result.isValid ? "Valid" : "Invalid")
                            .font(HawalaTheme.Typography.caption)
                    }
                    .foregroundColor(result.isValid ? HawalaTheme.Colors.success : HawalaTheme.Colors.error)
                }
            }
            
            // Address Input Field
            HStack(spacing: HawalaTheme.Spacing.sm) {
                Image(systemName: "wallet.pass")
                    .font(.system(size: 16))
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                TextField("", text: $recipientAddress)
                    .textFieldStyle(.plain)
                    .font(HawalaTheme.Typography.mono)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                    .placeholder(when: recipientAddress.isEmpty) {
                        Text("Address or ENS domain")
                            .font(HawalaTheme.Typography.body)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                    .disableAutocorrection(true)
                    .onChange(of: recipientAddress) { _ in
                        validateAddressAsync()
                    }
                
                // QR Scan button
                Button(action: scanQRCode) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 14))
                        .foregroundColor(HawalaTheme.Colors.accent)
                }
                .buttonStyle(.plain)
                .help("Scan QR code")
                
                // Paste button
                Button(action: pasteFromClipboard) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 14))
                        .foregroundColor(HawalaTheme.Colors.accent)
                }
                .buttonStyle(.plain)
                .help("Paste from clipboard")
            }
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            
            // ENS Resolution
            if let ensName = resolvedENSName {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.caption)
                    Text("Resolves to: \(ensName)")
                        .font(HawalaTheme.Typography.caption)
                }
                .foregroundColor(HawalaTheme.Colors.accent)
            }
            
            // Validation Error
            if case .invalid(let error) = addressValidationResult {
                Text(error)
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.error)
            }
            
            // ENS Hint
            if selectedChain == .ethereum {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                    Text("Supports ENS (.eth) and Unstoppable Domains")
                        .font(HawalaTheme.Typography.caption)
                }
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
        }
        .hawalaCard()
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(HawalaTheme.Animation.spring.delay(0.05), value: appearAnimation)
    }
    
    // MARK: - Amount Section
    
    private var amountSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            Text("AMOUNT")
                .font(HawalaTheme.Typography.label)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
                .tracking(1)
            
            HStack(spacing: HawalaTheme.Spacing.sm) {
                // Chain Icon
                ZStack {
                    Circle()
                        .fill(HawalaTheme.Colors.forChain(selectedChain.chainId).opacity(0.2))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: selectedChain.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(HawalaTheme.Colors.forChain(selectedChain.chainId))
                }
                
                TextField("", text: $amount)
                    .textFieldStyle(.plain)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                    .placeholder(when: amount.isEmpty) {
                        Text("0.00")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                
                Spacer()
                
                Text(chainSymbol)
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            
            Text(amountHint)
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
        }
        .hawalaCard()
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(HawalaTheme.Animation.spring.delay(0.1), value: appearAnimation)
    }
    
    // MARK: - Fee Section
    
    private var feeSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            HStack {
                Text("NETWORK FEE")
                    .font(HawalaTheme.Typography.label)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                    .tracking(1)
                
                Spacer()
                
                Button(action: refreshFees) {
                    HStack(spacing: 4) {
                        if feeEstimator.isLoadingBitcoin || feeEstimator.isLoadingEthereum {
                            ProgressView()
                                .scaleEffect(0.5)
                                .tint(HawalaTheme.Colors.accent)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                        Text("Refresh")
                            .font(HawalaTheme.Typography.caption)
                    }
                    .foregroundColor(HawalaTheme.Colors.accent)
                }
                .buttonStyle(.plain)
            }
            
            // Fee Priority Cards
            HStack(spacing: HawalaTheme.Spacing.sm) {
                ForEach(FeePriority.allCases) { priority in
                    SendFeePriorityCard(
                        priority: priority,
                        estimate: getEstimate(for: priority),
                        isSelected: selectedFeePriority == priority,
                        chain: selectedChain,
                        action: { selectedFeePriority = priority }
                    )
                }
            }
            
            // Custom Fee Toggle
            HStack {
                Toggle(isOn: $useCustomFee) {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption)
                        Text("Custom fee")
                            .font(HawalaTheme.Typography.bodySmall)
                    }
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
                .toggleStyle(SwitchToggleStyle(tint: HawalaTheme.Colors.accent))
            }
            
            // Custom Fee Input
            if useCustomFee {
                HStack {
                    TextField("", text: selectedChain == .bitcoin ? $feeRate : $gasPrice)
                        .textFieldStyle(.plain)
                        .font(HawalaTheme.Typography.mono)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    Text(selectedChain == .bitcoin ? "sat/vB" : "Gwei")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                .padding(HawalaTheme.Spacing.md)
                .background(HawalaTheme.Colors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            }
            
            // Gas Limit (ETH only)
            if selectedChain == .ethereum {
                HStack {
                    Text("Gas Limit")
                        .font(HawalaTheme.Typography.bodySmall)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    
                    Spacer()
                    
                    TextField("21000", text: $gasLimit)
                        .textFieldStyle(.plain)
                        .font(HawalaTheme.Typography.mono)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
                .padding(HawalaTheme.Spacing.md)
                .background(HawalaTheme.Colors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            }
        }
        .hawalaCard()
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(HawalaTheme.Animation.spring.delay(0.15), value: appearAnimation)
    }
    
    // MARK: - XRP Options
    
    private var xrpOptionsSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            Text("XRP OPTIONS")
                .font(HawalaTheme.Typography.label)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
                .tracking(1)
            
            HStack {
                Image(systemName: "tag")
                    .font(.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                TextField("", text: $destinationTag)
                    .textFieldStyle(.plain)
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                    .placeholder(when: destinationTag.isEmpty) {
                        Text("Destination Tag (Optional)")
                            .font(HawalaTheme.Typography.body)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
            }
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            
            Text("Some exchanges require a destination tag")
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
        }
        .hawalaCard()
    }
    
    // MARK: - Error Banner
    
    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: HawalaTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(HawalaTheme.Colors.error)
            
            Text(error)
                .font(HawalaTheme.Typography.bodySmall)
                .foregroundColor(HawalaTheme.Colors.error)
            
            Spacer()
            
            Button(action: { errorMessage = nil }) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.error.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                .strokeBorder(HawalaTheme.Colors.error.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Success Banner
    
    private func successBanner(_ txId: String) -> some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(HawalaTheme.Colors.success)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Transaction Sent!")
                        .font(HawalaTheme.Typography.h4)
                        .foregroundColor(HawalaTheme.Colors.success)
                    
                    Text("Your transaction is being processed")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Transaction ID")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                Text(txId)
                    .font(HawalaTheme.Typography.monoSmall)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            .padding(HawalaTheme.Spacing.sm)
            .background(HawalaTheme.Colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm, style: .continuous))
            
            Button(action: { openExplorer(txId: txId) }) {
                HStack {
                    Image(systemName: "arrow.up.right.square")
                    Text("View on Explorer")
                }
                .font(HawalaTheme.Typography.bodySmall)
                .foregroundColor(HawalaTheme.Colors.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.success.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                .strokeBorder(HawalaTheme.Colors.success.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Bottom Action Bar
    
    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(HawalaTheme.Colors.border)
            
            Button(action: showReviewScreen) {
                HStack(spacing: HawalaTheme.Spacing.sm) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                    Text(isLoading ? "Sending..." : "Review Transaction")
                        .font(HawalaTheme.Typography.h4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, HawalaTheme.Spacing.md)
                .background(canSend ? HawalaTheme.Colors.accent : HawalaTheme.Colors.backgroundTertiary)
                .foregroundColor(canSend ? .white : HawalaTheme.Colors.textTertiary)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSend || isLoading)
            .padding(HawalaTheme.Spacing.lg)
        }
        .background(HawalaTheme.Colors.background)
    }
    
    // MARK: - Helper Functions
    
    private func pasteFromClipboard() {
        #if canImport(AppKit)
        if let string = NSPasteboard.general.string(forType: .string) {
            recipientAddress = string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
    }
    
    private func scanQRCode() {
        // Try scanning from clipboard first (image with QR code)
        let clipboardResult = QRCodeScanner.scanFromClipboard()
        switch clipboardResult {
        case .success(let content):
            handleScannedQR(content)
            return
        case .failure:
            break
        }
        
        // Fall back to file picker
        if let content = QRCodeScanner.scanText() {
            handleScannedQR(content)
        }
    }
    
    private func handleScannedQR(_ content: String) {
        let parsed = QRCodeScanner.parseAddress(from: content)
        scannedQRResult = parsed
        
        // Set the recipient address
        recipientAddress = parsed.address
        
        // Set amount if present
        if let amountStr = parsed.amount {
            amount = amountStr
        }
        
        // Try to match chain type
        if let qrChain = parsed.chainType {
            switch qrChain {
            case .bitcoin, .bitcoinTestnet:
                selectedChain = .bitcoin
            case .ethereum, .ethereumTestnet:
                selectedChain = .ethereum
            case .solana:
                selectedChain = .solana
            case .xrp:
                selectedChain = .xrp
            default:
                break
            }
        }
        
        // Validate the address
        validateAddressAsync()
    }
    
    private func refreshFees() {
        Task {
            if selectedChain == .bitcoin {
                await feeEstimator.fetchBitcoinFees(isTestnet: true)
            } else {
                await feeEstimator.fetchEthereumFees()
            }
        }
    }
    
    private func getEstimate(for priority: FeePriority) -> FeeEstimate? {
        if selectedChain == .bitcoin {
            return feeEstimator.getBitcoinEstimate(for: priority)
        } else {
            return feeEstimator.getEthereumEstimate(for: priority)
        }
    }
    
    // MARK: - Computed Properties
    
    private var canSend: Bool {
        guard !isLoading else { return false }
        guard !recipientAddress.isEmpty else { return false }
        guard !amount.isEmpty else { return false }
        guard let result = addressValidationResult, result.isValid else { return false }
        guard Double(amount) ?? 0 > 0 else { return false }
        return true
    }
    
    private var amountHint: String {
        switch selectedChain {
        case .bitcoin: return "Amount in BTC (e.g., 0.001)"
        case .ethereum: return "Amount in ETH (e.g., 0.01)"
        case .solana: return "Amount in SOL (e.g., 0.1)"
        case .xrp: return "Amount in XRP (e.g., 10)"
        case .monero: return "Amount in XMR"
        }
    }
    
    private var chainSymbol: String {
        switch selectedChain {
        case .bitcoin: return "BTC"
        case .ethereum: return "ETH"
        case .solana: return "SOL"
        case .xrp: return "XRP"
        case .monero: return "XMR"
        }
    }
    
    private var chainDisplayName: String {
        switch selectedChain {
        case .bitcoin: return "Bitcoin Testnet"
        case .ethereum: return "Ethereum Sepolia"
        case .solana: return "Solana Devnet"
        case .xrp: return "XRP Testnet"
        case .monero: return "Monero Stagenet"
        }
    }
    
    private var chainIcon: String {
        selectedChain.iconName
    }
    
    // MARK: - Address Validation
    
    private func validateAddressAsync() {
        guard !recipientAddress.isEmpty else {
            addressValidationResult = nil
            resolvedENSName = nil
            return
        }
        
        isValidatingAddress = true
        
        Task {
            let result = await addressValidator.validate(
                address: recipientAddress,
                chainId: selectedChain.chainId
            )
            
            await MainActor.run {
                self.addressValidationResult = result
                self.isValidatingAddress = false
                
                if case .valid(_, let displayName, _) = result, let name = displayName {
                    self.resolvedENSName = name
                } else {
                    self.resolvedENSName = nil
                }
            }
        }
    }
    
    // MARK: - Explorer Links
    
    private func openExplorer(txId: String) {
        let urlString: String
        switch selectedChain {
        case .bitcoin: urlString = "https://mempool.space/testnet/tx/\(txId)"
        case .ethereum: urlString = "https://sepolia.etherscan.io/tx/\(txId)"
        case .solana: urlString = "https://explorer.solana.com/tx/\(txId)?cluster=devnet"
        case .xrp: urlString = "https://testnet.xrpl.org/transactions/\(txId)"
        case .monero: urlString = "https://stagenet.xmrchain.net/search?value=\(txId)"
        }
        
        if let url = URL(string: urlString) {
            #if canImport(AppKit)
            NSWorkspace.shared.open(url)
            #endif
        }
    }
    
    // MARK: - Fee Management
    
    private func updateFeeFromPriority() {
        guard !useCustomFee else { return }
        
        switch selectedChain {
        case .bitcoin:
            if let estimate = feeEstimator.getBitcoinEstimate(for: selectedFeePriority) {
                feeRate = String(format: "%.0f", estimate.feeRate)
            }
        case .ethereum:
            if let estimate = feeEstimator.getEthereumEstimate(for: selectedFeePriority) {
                gasPrice = String(format: "%.0f", estimate.feeRate)
            }
        default:
            break
        }
    }
    
    private var effectiveBitcoinFeeRate: UInt64 {
        if useCustomFee, let custom = UInt64(feeRate) { return custom }
        if let estimate = feeEstimator.getBitcoinEstimate(for: selectedFeePriority) {
            return UInt64(estimate.feeRate)
        }
        return 5
    }
    
    private var effectiveGasPrice: UInt64 {
        if useCustomFee, let custom = UInt64(gasPrice) { return custom }
        if let estimate = feeEstimator.getEthereumEstimate(for: selectedFeePriority) {
            return UInt64(estimate.feeRate)
        }
        return 20
    }
    
    // MARK: - Review Screen
    
    private func showReviewScreen() {
        let amountValue = Double(amount) ?? 0
        let (feeValue, feeRateValue, feeUnit, estimatedTime) = calculateFeeDetails()
        
        reviewData = TransactionReviewData(
            chainId: selectedChain.chainId,
            chainName: chainDisplayName,
            chainIcon: chainIcon,
            symbol: chainSymbol,
            amount: amountValue,
            recipientAddress: recipientAddress,
            recipientDisplayName: resolvedENSName,
            feeRate: feeRateValue,
            feeRateUnit: feeUnit,
            fee: feeValue,
            feePriority: selectedFeePriority,
            estimatedTime: estimatedTime,
            fiatAmount: nil,
            fiatFee: nil,
            currentBalance: nil
        )
        
        showingReview = true
    }
    
    private func calculateFeeDetails() -> (fee: Double, rate: Double, unit: String, time: String) {
        switch selectedChain {
        case .bitcoin:
            let rate = Double(effectiveBitcoinFeeRate)
            let txSizeVBytes = 140
            let fee = (rate * Double(txSizeVBytes)) / 100_000_000
            let time = feeEstimator.getBitcoinEstimate(for: selectedFeePriority)?.estimatedTime ?? "~30 min"
            return (fee, rate, "sat/vB", time)
        case .ethereum:
            let rate = Double(effectiveGasPrice)
            let limit = UInt64(gasLimit) ?? 21000
            let fee = (rate * Double(limit)) / 1_000_000_000
            let time = feeEstimator.getEthereumEstimate(for: selectedFeePriority)?.estimatedTime ?? "~2 min"
            return (fee, rate, "Gwei", time)
        case .solana:
            return (0.000005, 5000, "lamports", "~1 min")
        case .xrp:
            return (0.00001, 10, "drops", "~4 sec")
        case .monero:
            return (0.0001, 0, "XMR", "~20 min")
        }
    }
    
    // MARK: - Send Transaction
    
    private func sendTransaction() {
        guard let walletId = walletRepository.activeWalletId else {
            errorMessage = "No active wallet selected"
            return
        }
        
        isLoading = true
        errorMessage = nil
        successTxId = nil
        
        Task {
            do {
                // 1. Get Seed Phrase
                guard let seedPhrase = try walletRepository.getSeedPhrase(for: walletId) else {
                    throw NSError(domain: "App", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not retrieve seed phrase"])
                }
                let mnemonic = seedPhrase.joined(separator: " ")
                
                // 2. Derive Keys
                let keys = try RustCLIBridge.shared.generateKeys(mnemonic: mnemonic)
                
                // 3. Sign & Broadcast based on chain
                let txId: String
                
                switch selectedChain {
                case .bitcoin:
                    // Assuming Testnet for now as per picker
                    let amountSats = UInt64((Double(amount) ?? 0) * 100_000_000)
                    let fee = effectiveBitcoinFeeRate // Use dynamic fee from selector
                    
                    let signedHex = try RustCLIBridge.shared.signBitcoin(
                        recipient: recipientAddress,
                        amountSats: amountSats,
                        feeRate: fee,
                        senderWIF: keys.bitcoin_testnet.private_wif
                    )
                    
                    txId = try await broadcaster.broadcastBitcoin(rawTxHex: signedHex, isTestnet: true)
                    
                case .ethereum:
                    // Assuming Sepolia
                    let amountEth = Double(amount) ?? 0
                    let amountWei = String(format: "%.0f", amountEth * 1_000_000_000_000_000_000)
                    let gwei = effectiveGasPrice // Use dynamic gas price from selector
                    let gasPriceWei = String(gwei * 1_000_000_000)
                    let limit = UInt64(gasLimit) ?? 21000
                    
                    // Fetch nonce from RPC
                    let nonce = try await broadcaster.getEthereumNonce(address: keys.ethereum.address, isTestnet: true)
                    
                    let signedHex = try RustCLIBridge.shared.signEthereum(
                        recipient: recipientAddress,
                        amountWei: amountWei,
                        chainId: 11155111, // Sepolia
                        senderKey: keys.ethereum.private_hex,
                        nonce: nonce,
                        gasLimit: limit,
                        gasPrice: gasPriceWei
                    )
                    
                    txId = try await broadcaster.broadcastEthereum(rawTxHex: signedHex, isTestnet: true)
                    
                case .solana:
                    let amountSol = Double(amount) ?? 0
                    // Fetch recent blockhash
                    let blockhash = try await broadcaster.getSolanaBlockhash(isDevnet: true)
                    
                    let signedBase58 = try RustCLIBridge.shared.signSolana(
                        recipient: recipientAddress,
                        amountSol: amountSol,
                        recentBlockhash: blockhash,
                        senderBase58: keys.solana.private_key_base58
                    )
                    
                    txId = try await broadcaster.broadcastSolana(rawTxBase64: signedBase58, isDevnet: true)
                    
                case .xrp:
                    let amountXrp = Double(amount) ?? 0
                    let drops = UInt64(amountXrp * 1_000_000)
                    // Fetch sequence
                    let sequence = try await broadcaster.getXRPSequence(address: keys.xrp.classic_address, isTestnet: true)
                    
                    let signedHex = try RustCLIBridge.shared.signXRP(
                        recipient: recipientAddress,
                        amountDrops: drops,
                        senderSeedHex: keys.xrp.private_hex,
                        sequence: sequence
                    )
                    
                    txId = try await broadcaster.broadcastXRP(rawTxHex: signedHex, isTestnet: true)
                    
                case .monero:
                    throw NSError(domain: "App", code: 2, userInfo: [NSLocalizedDescriptionKey: "Monero sending not yet supported"])
                }
                
                await MainActor.run {
                    self.successTxId = txId
                    self.isLoading = false
                    
                    let result = TransactionBroadcastResult(
                        txid: txId,
                        chainId: selectedChain.id,
                        chainName: selectedChain.rawValue.capitalized,
                        amount: amount,
                        recipient: recipientAddress
                    )
                    onSuccess?(result)
                }
                
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - SendChainPill Component

struct SendChainPill: View {
    let chain: Chain
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: chain.iconName)
                    .font(.system(size: 12, weight: .semibold))
                
                Text(chain.rawValue.capitalized)
                    .font(HawalaTheme.Typography.captionBold)
            }
            .padding(.horizontal, HawalaTheme.Spacing.md)
            .padding(.vertical, HawalaTheme.Spacing.sm)
            .background(isSelected ? chainColor.opacity(0.2) : HawalaTheme.Colors.backgroundTertiary)
            .foregroundColor(isSelected ? chainColor : HawalaTheme.Colors.textSecondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? chainColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var chainColor: Color {
        HawalaTheme.Colors.forChain(chain.chainId)
    }
}

// MARK: - SendFeePriorityCard Component

struct SendFeePriorityCard: View {
    let priority: FeePriority
    let estimate: FeeEstimate?
    let isSelected: Bool
    let chain: Chain
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: priority.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isSelected ? priorityColor : HawalaTheme.Colors.textTertiary)
                
                Text(priority.rawValue)
                    .font(HawalaTheme.Typography.captionBold)
                    .foregroundColor(isSelected ? HawalaTheme.Colors.textPrimary : HawalaTheme.Colors.textSecondary)
                
                if let est = estimate {
                    Text(est.formattedFeeRate)
                        .font(HawalaTheme.Typography.monoSmall)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    
                    Text(chain == .bitcoin ? "sat/vB" : "Gwei")
                        .font(.system(size: 9))
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                } else {
                    Text("--")
                        .font(HawalaTheme.Typography.monoSmall)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                
                Text(chain == .bitcoin ? priority.description : priority.ethDescription)
                    .font(.system(size: 9))
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, HawalaTheme.Spacing.md)
            .background(isSelected ? priorityColor.opacity(0.15) : HawalaTheme.Colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? priorityColor.opacity(0.5) : HawalaTheme.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var priorityColor: Color {
        switch priority {
        case .slow: return HawalaTheme.Colors.success
        case .average: return HawalaTheme.Colors.warning
        case .fast: return HawalaTheme.Colors.error
        }
    }
}

// MARK: - Placeholder Extension

extension View {
    @ViewBuilder
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}