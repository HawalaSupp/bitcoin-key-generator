import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

enum Chain: String, CaseIterable, Identifiable {
    case bitcoinTestnet = "bitcoin-testnet"
    case bitcoinMainnet = "bitcoin-mainnet"
    case litecoin = "litecoin"
    case ethereum
    case polygon
    case bnb
    case solana
    case xrp
    case monero
    
    var id: String { self.rawValue }
    
    var chainId: String {
        switch self {
        case .bitcoinTestnet: return "bitcoin-testnet"
        case .bitcoinMainnet: return "bitcoin-mainnet"
        case .litecoin: return "litecoin"
        case .ethereum: return "ethereum-sepolia"
        case .polygon: return "polygon-mainnet"
        case .bnb: return "bsc-mainnet"
        case .solana: return "solana"
        case .xrp: return "xrp"
        case .monero: return "monero"
        }
    }
    
    var displayName: String {
        switch self {
        case .bitcoinTestnet: return "BTC Testnet"
        case .bitcoinMainnet: return "BTC Mainnet"
        case .litecoin: return "Litecoin"
        case .ethereum: return "Ethereum"
        case .polygon: return "Polygon"
        case .bnb: return "BNB Chain"
        case .solana: return "Solana"
        case .xrp: return "XRP"
        case .monero: return "Monero"
        }
    }
    
    var iconName: String {
        switch self {
        case .bitcoinTestnet: return "bitcoinsign"
        case .bitcoinMainnet: return "bitcoinsign.circle.fill"
        case .litecoin: return "l.circle.fill"
        case .ethereum: return "e.circle.fill"
        case .polygon: return "p.circle.fill"
        case .bnb: return "b.circle.fill"
        case .solana: return "s.circle.fill"
        case .xrp: return "x.circle.fill"
        case .monero: return "m.circle.fill"
        }
    }
    
    var isBitcoin: Bool {
        self == .bitcoinTestnet || self == .bitcoinMainnet
    }
    
    var isLitecoin: Bool {
        self == .litecoin
    }
    
    var isUTXOBased: Bool {
        isBitcoin || isLitecoin
    }
    
    var isEVM: Bool {
        self == .ethereum || self == .polygon || self == .bnb
    }
    
    /// EVM chain ID for transaction signing
    var evmChainId: UInt64? {
        switch self {
        case .ethereum: return 11155111  // Sepolia testnet
        case .polygon: return 137        // Polygon mainnet
        case .bnb: return 56             // BSC mainnet
        default: return nil
        }
    }
    
    /// Native token symbol
    var nativeSymbol: String {
        switch self {
        case .bitcoinTestnet, .bitcoinMainnet: return "BTC"
        case .litecoin: return "LTC"
        case .ethereum: return "ETH"
        case .polygon: return "POL"
        case .bnb: return "BNB"
        case .solana: return "SOL"
        case .xrp: return "XRP"
        case .monero: return "XMR"
        }
    }
    
    /// Whether this chain supports sending in v1
    /// Monero requires ring signatures with blockchain state - view-only for v1
    var supportsSending: Bool {
        switch self {
        case .monero: return false
        default: return true
        }
    }
    
    /// Reason why sending is not supported (if applicable)
    var sendingDisabledReason: String? {
        switch self {
        case .monero: return "Monero sending requires ring signatures with blockchain sync. View-only mode in v1."
        default: return nil
        }
    }
}

struct SendView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var broadcaster = TransactionBroadcaster.shared
    @ObservedObject var addressValidator = ChainAddressValidator.shared
    @StateObject private var feeEstimator = FeeEstimator.shared
    @StateObject private var feeWarningService = FeeWarningService.shared
    
    // Keys passed from parent
    let keys: AllKeys
    
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
    
    // Success confirmation sheet
    @State private var showingSuccessSheet = false
    @State private var successTransactionDetails: TransactionSuccessDetails?
    @State private var pendingSuccessResult: TransactionBroadcastResult?
    
    // Pre-signed transaction for instant broadcast
    @State private var preSignedTxHex: String?
    @State private var preSigningInProgress = false
    @State private var preSignError: String?
    
    // Fee warnings state
    @State private var feeWarnings: [FeeWarning] = []
    
    // Gas estimation state
    @State private var gasEstimateResult: GasEstimateResult?
    @State private var isEstimatingGas = false
    @State private var autoEstimateGas = true // Auto-estimate when address changes
    
    // Animation
    @State private var appearAnimation = false
    
    var onSuccess: ((TransactionBroadcastResult) -> Void)?
    
    init(keys: AllKeys, initialChain: Chain = .bitcoinTestnet, onSuccess: ((TransactionBroadcastResult) -> Void)? = nil) {
        self.keys = keys
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
                        
                        // View-Only Warning (for chains that don't support sending)
                        if !selectedChain.supportsSending {
                            viewOnlyWarningBanner
                        }
                        
                        // Recipient Address
                        recipientSection
                        
                        // Amount Input
                        amountSection
                        
                        // Fee Settings (BTC/LTC/ETH only)
                        if selectedChain.isUTXOBased || selectedChain == .ethereum {
                            feeSection
                            
                            // Fee Warnings
                            if !feeWarnings.isEmpty {
                                feeWarningsSection
                            }
                        }
                        
                        // Fixed Fee Info (Solana/XRP)
                        if selectedChain == .solana || selectedChain == .xrp {
                            fixedFeeInfoSection
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
        .onChange(of: amount) { _ in
            updateFeeWarnings()
        }
        .onChange(of: feeRate) { _ in
            if selectedChain.isBitcoin {
                updateFeeWarnings()
            }
        }
        .onChange(of: gasPrice) { _ in
            if selectedChain == .ethereum {
                updateFeeWarnings()
            }
        }
        .onChange(of: gasLimit) { _ in
            if selectedChain == .ethereum {
                updateFeeWarnings()
            }
        }
        .sheet(isPresented: $showingReview, onDismiss: {
            // Clear pre-signed tx if user cancels
            preSignedTxHex = nil
            preSignError = nil
        }) {
            if let data = reviewData {
                TransactionReviewView(
                    transaction: data,
                    onConfirm: {
                        print("[SendView] Review confirmed! Dismissing sheet and sending transaction...")
                        showingReview = false
                        // Small delay to ensure sheet dismissal completes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            sendTransaction()
                        }
                    },
                    onCancel: {
                        print("[SendView] Review cancelled")
                        showingReview = false
                    }
                )
                .frame(minWidth: 400, minHeight: 600)
                .onAppear {
                    // Pre-sign transaction in background while user reviews
                    preSignTransaction()
                }
            }
        }
        .sheet(isPresented: $showingSuccessSheet, onDismiss: {
            print("[SendView] Success sheet dismissed")
            // Only call onSuccess when user dismisses the success sheet
            if let result = pendingSuccessResult {
                onSuccess?(result)
            }
        }) {
            if let details = successTransactionDetails {
                TransactionSuccessView(
                    details: details,
                    keys: keys,
                    onDone: {
                        print("[SendView] Done button pressed")
                        showingSuccessSheet = false
                        dismiss()
                    },
                    onViewExplorer: {
                        openExplorer(txId: details.txId)
                    }
                )
                .frame(minWidth: 420, minHeight: 600)
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
                        // Trigger gas estimation for EVM chains
                        if autoEstimateGas && selectedChain == .ethereum {
                            Task { await estimateGasLimit() }
                        }
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
                    TextField("", text: selectedChain.isBitcoin ? $feeRate : $gasPrice)
                        .textFieldStyle(.plain)
                        .font(HawalaTheme.Typography.mono)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    Text(selectedChain.isBitcoin ? "sat/vB" : "Gwei")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                .padding(HawalaTheme.Spacing.md)
                .background(HawalaTheme.Colors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            }
            
            // Gas Limit (ETH/EVM only)
            if selectedChain == .ethereum {
                VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xs) {
                    HStack {
                        Text("Gas Limit")
                            .font(HawalaTheme.Typography.bodySmall)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                        
                        Spacer()
                        
                        // Auto-estimate toggle
                        Toggle("Auto", isOn: $autoEstimateGas)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .onChange(of: autoEstimateGas) { newValue in
                                if newValue {
                                    Task { await estimateGasLimit() }
                                }
                            }
                    }
                    
                    HStack {
                        if isEstimatingGas {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Estimating...")
                                .font(HawalaTheme.Typography.caption)
                                .foregroundColor(HawalaTheme.Colors.textTertiary)
                        } else {
                            TextField("21000", text: $gasLimit)
                                .textFieldStyle(.plain)
                                .font(HawalaTheme.Typography.mono)
                                .foregroundColor(HawalaTheme.Colors.textPrimary)
                                .multilineTextAlignment(.leading)
                                .disabled(autoEstimateGas)
                            
                            Spacer()
                            
                            if let result = gasEstimateResult {
                                if result.isEstimated {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(HawalaTheme.Colors.success)
                                            .font(.caption)
                                        Text("Estimated")
                                            .font(HawalaTheme.Typography.caption)
                                            .foregroundColor(HawalaTheme.Colors.success)
                                    }
                                } else {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(HawalaTheme.Colors.warning)
                                            .font(.caption)
                                        Text("Default")
                                            .font(HawalaTheme.Typography.caption)
                                            .foregroundColor(HawalaTheme.Colors.warning)
                                    }
                                }
                            }
                        }
                    }
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
    
    // MARK: - Fee Warnings Section
    
    private var feeWarningsSection: some View {
        VStack(spacing: HawalaTheme.Spacing.sm) {
            ForEach(feeWarnings) { warning in
                FeeWarningView(warning: warning)
            }
        }
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(HawalaTheme.Animation.spring.delay(0.17), value: appearAnimation)
    }
    
    // MARK: - Fixed Fee Info Section (Solana/XRP)
    
    private var fixedFeeInfoSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            Text("NETWORK FEE")
                .font(HawalaTheme.Typography.label)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
                .tracking(1)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fixedFeeAmount)
                        .font(HawalaTheme.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    Text(fixedFeeDescription)
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(HawalaTheme.Colors.success)
            }
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
        }
        .hawalaCard()
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(HawalaTheme.Animation.spring.delay(0.15), value: appearAnimation)
    }
    
    private var fixedFeeAmount: String {
        switch selectedChain {
        case .solana:
            return "~0.000005 SOL"
        case .xrp:
            return "~0.00001 XRP"
        default:
            return "N/A"
        }
    }
    
    private var fixedFeeDescription: String {
        switch selectedChain {
        case .solana:
            return "Fixed network fee (~$0.001) • ~1 min confirmation"
        case .xrp:
            return "Fixed network fee (~$0.00001) • ~4 sec confirmation"
        default:
            return ""
        }
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
    
    // MARK: - View-Only Warning Banner
    
    private var viewOnlyWarningBanner: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            HStack(spacing: HawalaTheme.Spacing.sm) {
                Image(systemName: "eye.fill")
                    .font(.title2)
                    .foregroundColor(HawalaTheme.Colors.warning)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("View-Only Mode")
                        .font(HawalaTheme.Typography.h4)
                        .foregroundColor(HawalaTheme.Colors.warning)
                    
                    Text("Sending is not available for this chain")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
                
                Spacer()
            }
            
            if let reason = selectedChain.sendingDisabledReason {
                Text(reason)
                    .font(HawalaTheme.Typography.bodySmall)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .padding(HawalaTheme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm, style: .continuous))
            }
            
            // Show what IS supported
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xs) {
                Text("Available features:")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                HStack(spacing: HawalaTheme.Spacing.md) {
                    Label("View Address", systemImage: "qrcode")
                    Label("Copy Address", systemImage: "doc.on.doc")
                }
                .font(HawalaTheme.Typography.bodySmall)
                .foregroundColor(HawalaTheme.Colors.success)
            }
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.warning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                .strokeBorder(HawalaTheme.Colors.warning.opacity(0.3), lineWidth: 1)
        )
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
                selectedChain = .bitcoinTestnet
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
            if selectedChain.isBitcoin {
                await feeEstimator.fetchBitcoinFees(isTestnet: selectedChain == .bitcoinTestnet)
            } else {
                await feeEstimator.fetchEthereumFees()
            }
        }
    }
    
    /// Estimate gas limit for EVM transactions
    private func estimateGasLimit() async {
        guard selectedChain == .ethereum else {
            return
        }
        
        guard !recipientAddress.isEmpty,
              let validation = addressValidationResult,
              validation.isValid else {
            // Use default if no valid address
            gasLimit = "21000"
            gasEstimateResult = nil
            return
        }
        
        isEstimatingGas = true
        
        // Get sender address from Ethereum keys
        let fromAddress = keys.ethereumSepolia.address
        
        // Convert amount to wei hex
        let weiValue: String
        if let amountDouble = Double(amount), amountDouble > 0 {
            let weiAmount = UInt64(amountDouble * 1_000_000_000_000_000_000) // 1e18
            weiValue = "0x" + String(weiAmount, radix: 16)
        } else {
            weiValue = "0x0"
        }
        
        // Get chain ID (Sepolia testnet for ethereum)
        let chainId = 11155111
        
        // Estimate gas
        if let result = await FeeEstimationService.shared.estimateGasLimit(
            from: fromAddress,
            to: recipientAddress,
            value: weiValue,
            data: "0x",
            chainId: chainId
        ) {
            gasEstimateResult = result
            gasLimit = String(result.recommendedGas)
        } else {
            // Fallback to default
            gasEstimateResult = GasEstimateResult(
                estimatedGas: 21000,
                recommendedGas: 21000,
                isEstimated: false,
                errorMessage: "Could not estimate, using default"
            )
            gasLimit = "21000"
        }
        
        isEstimatingGas = false
    }
    
    private func getEstimate(for priority: FeePriority) -> FeeEstimate? {
        if selectedChain.isBitcoin {
            return feeEstimator.getBitcoinEstimate(for: priority)
        } else {
            return feeEstimator.getEthereumEstimate(for: priority)
        }
    }
    
    // MARK: - Computed Properties
    
    private var canSend: Bool {
        guard selectedChain.supportsSending else { return false }
        guard !isLoading else { return false }
        guard !recipientAddress.isEmpty else { return false }
        guard !amount.isEmpty else { return false }
        guard let result = addressValidationResult, result.isValid else { return false }
        guard Double(amount) ?? 0 > 0 else { return false }
        return true
    }
    
    private var amountHint: String {
        switch selectedChain {
        case .bitcoinTestnet, .bitcoinMainnet: return "Amount in BTC (e.g., 0.001)"
        case .litecoin: return "Amount in LTC (e.g., 0.1)"
        case .ethereum: return "Amount in ETH (e.g., 0.01)"
        case .polygon: return "Amount in MATIC (e.g., 1.0)"
        case .bnb: return "Amount in BNB (e.g., 0.01)"
        case .solana: return "Amount in SOL (e.g., 0.1)"
        case .xrp: return "Amount in XRP (e.g., 10)"
        case .monero: return "Amount in XMR"
        }
    }
    
    private var chainSymbol: String {
        switch selectedChain {
        case .bitcoinTestnet, .bitcoinMainnet: return "BTC"
        case .litecoin: return "LTC"
        case .ethereum: return "ETH"
        case .polygon: return "MATIC"
        case .bnb: return "BNB"
        case .solana: return "SOL"
        case .xrp: return "XRP"
        case .monero: return "XMR"
        }
    }
    
    private var chainDisplayName: String {
        switch selectedChain {
        case .bitcoinTestnet: return "Bitcoin Testnet"
        case .bitcoinMainnet: return "Bitcoin Mainnet"
        case .litecoin: return "Litecoin Mainnet"
        case .ethereum: return "Ethereum Sepolia"
        case .polygon: return "Polygon Mainnet"
        case .bnb: return "BNB Smart Chain"
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
        case .bitcoinTestnet: urlString = "https://mempool.space/testnet/tx/\(txId)"
        case .bitcoinMainnet: urlString = "https://mempool.space/tx/\(txId)"
        case .litecoin: urlString = "https://litecoinspace.org/tx/\(txId)"
        case .ethereum: urlString = "https://sepolia.etherscan.io/tx/\(txId)"
        case .polygon: urlString = "https://polygonscan.com/tx/\(txId)"
        case .bnb: urlString = "https://bscscan.com/tx/\(txId)"
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
        case .bitcoinTestnet, .bitcoinMainnet:
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
        
        // Update fee warnings when fee changes
        updateFeeWarnings()
    }
    
    private func updateFeeWarnings() {
        guard let amountDouble = Double(amount), amountDouble > 0 else {
            feeWarnings = []
            return
        }
        
        switch selectedChain {
        case .bitcoinTestnet, .bitcoinMainnet:
            updateBitcoinFeeWarnings(amount: amountDouble)
        case .ethereum:
            updateEthereumFeeWarnings(amount: amountDouble)
        default:
            feeWarnings = []
        }
    }
    
    private func updateBitcoinFeeWarnings(amount: Double) {
        let currentFeeRate = Int64(feeRate) ?? 5
        // Estimate tx size: P2WPKH input (68 vB) + 2 outputs (31 vB each) + overhead (11 vB) = ~141 vB
        let estimatedTxSize: Int64 = 141
        let estimatedFee = currentFeeRate * estimatedTxSize
        let amountSats = Int64(amount * 100_000_000)
        
        // Get fee estimates from FeeEstimationService if available
        var bitcoinEstimate: BitcoinFeeEstimate?
        if let fastestRate = feeEstimator.getBitcoinEstimate(for: .fast)?.feeRate,
           let mediumRate = feeEstimator.getBitcoinEstimate(for: .average)?.feeRate,
           let slowRate = feeEstimator.getBitcoinEstimate(for: .slow)?.feeRate {
            bitcoinEstimate = BitcoinFeeEstimate(
                fastest: FeeLevel(satPerByte: Int(fastestRate), estimatedMinutes: 10, label: "Fast"),
                fast: FeeLevel(satPerByte: Int(fastestRate * 0.8), estimatedMinutes: 20, label: "Fast"),
                medium: FeeLevel(satPerByte: Int(mediumRate), estimatedMinutes: 60, label: "Medium"),
                slow: FeeLevel(satPerByte: Int(slowRate), estimatedMinutes: 120, label: "Slow"),
                minimum: FeeLevel(satPerByte: 1, estimatedMinutes: 1440, label: "Min")
            )
        }
        
        feeWarnings = feeWarningService.analyzeBitcoinFee(
            amount: amountSats,
            fee: estimatedFee,
            feeRate: currentFeeRate,
            currentFeeEstimates: bitcoinEstimate
        )
    }
    
    private func updateEthereumFeeWarnings(amount: Double) {
        let currentGasPrice = UInt64(gasPrice) ?? 20
        let currentGasLimit = UInt64(gasLimit) ?? 21000
        let gasPriceWei = currentGasPrice * 1_000_000_000 // Convert gwei to wei
        let amountWei = UInt64(amount * 1_000_000_000_000_000_000) // Convert ETH to wei
        
        // Get fee estimates from FeeEstimationService if available
        var ethereumEstimate: EthereumFeeEstimate?
        if let fastRate = feeEstimator.getEthereumEstimate(for: .fast)?.feeRate,
           let mediumRate = feeEstimator.getEthereumEstimate(for: .average)?.feeRate,
           let slowRate = feeEstimator.getEthereumEstimate(for: .slow)?.feeRate {
            ethereumEstimate = EthereumFeeEstimate(
                baseFee: mediumRate * 0.5,
                fast: GasLevel(gasPrice: fastRate, maxPriorityFee: 2.0, estimatedSeconds: 15, label: "Fast"),
                medium: GasLevel(gasPrice: mediumRate, maxPriorityFee: 1.5, estimatedSeconds: 30, label: "Medium"),
                slow: GasLevel(gasPrice: slowRate, maxPriorityFee: 1.0, estimatedSeconds: 60, label: "Slow")
            )
        }
        
        feeWarnings = feeWarningService.analyzeEVMFee(
            amount: amountWei,
            gasPrice: gasPriceWei,
            gasLimit: currentGasLimit,
            chainId: selectedChain.chainId,
            currentFeeEstimates: ethereumEstimate
        )
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
        case .bitcoinTestnet, .bitcoinMainnet:
            let rate = Double(effectiveBitcoinFeeRate)
            let txSizeVBytes = 140
            let fee = (rate * Double(txSizeVBytes)) / 100_000_000
            let time = feeEstimator.getBitcoinEstimate(for: selectedFeePriority)?.estimatedTime ?? "~30 min"
            return (fee, rate, "sat/vB", time)
        case .litecoin:
            // Litecoin uses similar fee structure to Bitcoin (sat/vB)
            let rate = Double(effectiveBitcoinFeeRate)
            let txSizeVBytes = 140
            let fee = (rate * Double(txSizeVBytes)) / 100_000_000
            return (fee, rate, "lit/vB", "~2.5 min")
        case .ethereum, .polygon, .bnb:
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
    
    // MARK: - Pre-Sign Transaction (Background)
    
    private func preSignTransaction() {
        guard !preSigningInProgress else { return }
        preSigningInProgress = true
        preSignedTxHex = nil
        preSignError = nil
        
        print("[SendView] Pre-signing transaction in background...")
        
        Task.detached(priority: .userInitiated) {
            do {
                let signedHex: String
                
                switch await MainActor.run(body: { self.selectedChain }) {
                case .bitcoinTestnet:
                    let amountSats = await MainActor.run { UInt64((Double(self.amount) ?? 0) * 100_000_000) }
                    let fee = await MainActor.run { self.effectiveBitcoinFeeRate }
                    let recipient = await MainActor.run { self.recipientAddress }
                    let wif = await MainActor.run { self.keys.bitcoinTestnet.privateWif }
                    
                    signedHex = try RustCLIBridge.shared.signBitcoin(
                        recipient: recipient,
                        amountSats: amountSats,
                        feeRate: fee,
                        senderWIF: wif
                    )
                    
                case .bitcoinMainnet:
                    let amountSats = await MainActor.run { UInt64((Double(self.amount) ?? 0) * 100_000_000) }
                    let fee = await MainActor.run { self.effectiveBitcoinFeeRate }
                    let recipient = await MainActor.run { self.recipientAddress }
                    let wif = await MainActor.run { self.keys.bitcoin.privateWif }
                    
                    signedHex = try RustCLIBridge.shared.signBitcoin(
                        recipient: recipient,
                        amountSats: amountSats,
                        feeRate: fee,
                        senderWIF: wif
                    )
                    
                default:
                    // Non-Bitcoin chains don't need pre-signing (they're usually fast)
                    await MainActor.run {
                        self.preSigningInProgress = false
                    }
                    return
                }
                
                await MainActor.run {
                    self.preSignedTxHex = signedHex
                    self.preSigningInProgress = false
                    print("[SendView] Pre-signing complete! Tx ready for instant broadcast.")
                }
                
            } catch {
                await MainActor.run {
                    self.preSignError = error.localizedDescription
                    self.preSigningInProgress = false
                    print("[SendView] Pre-signing failed: \(error)")
                }
            }
        }
    }
    
    // MARK: - Send Transaction
    
    private func sendTransaction() {
        print("[SendView] sendTransaction() called")
        print("[SendView] Sending \(amount) \(selectedChain.displayName) to \(recipientAddress)")
        
        isLoading = true
        errorMessage = nil
        successTxId = nil
        
        Task { @MainActor in
            do {
                print("[SendView] Step 1: Using keys passed from parent view")
                
                // Sign & Broadcast based on chain
                var txId: String
                var capturedFeeRate: Int? = nil
                var capturedNonce: Int? = nil
                
                switch selectedChain {
                case .bitcoinTestnet:
                    // Bitcoin Testnet - use pre-signed tx if available
                    let fee = effectiveBitcoinFeeRate
                    capturedFeeRate = Int(fee)
                    
                    let signedHex: String
                    if let preSigned = preSignedTxHex {
                        print("[SendView] Using pre-signed transaction (instant!)")
                        signedHex = preSigned
                    } else {
                        print("[SendView] No pre-signed tx, signing now...")
                        let amountSats = UInt64((Double(amount) ?? 0) * 100_000_000)
                        signedHex = try RustCLIBridge.shared.signBitcoin(
                            recipient: recipientAddress,
                            amountSats: amountSats,
                            feeRate: fee,
                            senderWIF: keys.bitcoinTestnet.privateWif
                        )
                    }
                    print("[SendView] Broadcasting to Bitcoin Testnet...")
                    txId = try await broadcaster.broadcastBitcoin(rawTxHex: signedHex, isTestnet: true)
                    print("[SendView] Broadcast successful! TxID: \(txId)")
                    
                case .bitcoinMainnet:
                    // Bitcoin Mainnet - use pre-signed tx if available
                    let fee = effectiveBitcoinFeeRate
                    capturedFeeRate = Int(fee)
                    
                    let signedHex: String
                    if let preSigned = preSignedTxHex {
                        print("[SendView] Using pre-signed transaction (instant!)")
                        signedHex = preSigned
                    } else {
                        print("[SendView] No pre-signed tx, signing now...")
                        let amountSats = UInt64((Double(amount) ?? 0) * 100_000_000)
                        signedHex = try RustCLIBridge.shared.signBitcoin(
                            recipient: recipientAddress,
                            amountSats: amountSats,
                            feeRate: fee,
                            senderWIF: keys.bitcoin.privateWif
                        )
                    }
                    print("[SendView] Broadcasting to Bitcoin Mainnet...")
                    txId = try await broadcaster.broadcastBitcoin(rawTxHex: signedHex, isTestnet: false)
                    print("[SendView] Broadcast successful! TxID: \(txId)")
                    
                case .litecoin:
                    // Litecoin Mainnet - similar to Bitcoin but with LTC-specific WIF
                    let fee = effectiveBitcoinFeeRate  // Litecoin uses similar fee structure
                    capturedFeeRate = Int(fee)
                    
                    // Convert LTC amount to litoshis (1 LTC = 100,000,000 litoshis)
                    let amountLits = UInt64((Double(amount) ?? 0) * 100_000_000)
                    
                    print("[SendView] Signing Litecoin transaction...")
                    let signedHex = try RustCLIBridge.shared.signLitecoin(
                        recipient: recipientAddress,
                        amountLits: amountLits,
                        feeRate: fee,
                        senderWIF: keys.litecoin.privateWif,
                        senderAddress: keys.litecoin.address
                    )
                    
                    print("[SendView] Broadcasting to Litecoin network...")
                    txId = try await broadcaster.broadcastLitecoin(rawTxHex: signedHex)
                    print("[SendView] Broadcast successful! TxID: \(txId)")
                    
                case .ethereum:
                    // Sepolia testnet
                    let amountEth = Double(amount) ?? 0
                    let amountWei = String(format: "%.0f", amountEth * 1_000_000_000_000_000_000)
                    let gwei = effectiveGasPrice
                    let gasPriceWei = String(gwei * 1_000_000_000)
                    let limit = UInt64(gasLimit) ?? 21000
                    capturedFeeRate = Int(gwei)
                    
                    let nonce = try await broadcaster.getEthereumNonce(address: keys.ethereum.address, isTestnet: true)
                    capturedNonce = Int(nonce)
                    
                    let signedHex = try RustCLIBridge.shared.signEthereum(
                        recipient: recipientAddress,
                        amountWei: amountWei,
                        chainId: 11155111, // Sepolia
                        senderKey: keys.ethereum.privateHex,
                        nonce: nonce,
                        gasLimit: limit,
                        gasPrice: gasPriceWei
                    )
                    
                    txId = try await broadcaster.broadcastEthereum(rawTxHex: signedHex, isTestnet: true)
                    
                case .polygon:
                    // Polygon Mainnet (chainId 137)
                    let amountMatic = Double(amount) ?? 0
                    let amountWei = String(format: "%.0f", amountMatic * 1_000_000_000_000_000_000)
                    let gwei = effectiveGasPrice
                    let gasPriceWei = String(gwei * 1_000_000_000)
                    let limit = UInt64(gasLimit) ?? 21000
                    capturedFeeRate = Int(gwei)
                    
                    let nonce = try await broadcaster.getEthereumNonceForChain(address: keys.ethereum.address, chainId: 137)
                    capturedNonce = Int(nonce)
                    
                    let signedHex = try RustCLIBridge.shared.signEthereum(
                        recipient: recipientAddress,
                        amountWei: amountWei,
                        chainId: 137,
                        senderKey: keys.ethereum.privateHex,
                        nonce: nonce,
                        gasLimit: limit,
                        gasPrice: gasPriceWei
                    )
                    
                    txId = try await broadcaster.broadcastEthereumToChain(rawTxHex: signedHex, chainId: 137)
                    
                case .bnb:
                    // BNB Smart Chain (chainId 56)
                    let amountBnb = Double(amount) ?? 0
                    let amountWei = String(format: "%.0f", amountBnb * 1_000_000_000_000_000_000)
                    let gwei = effectiveGasPrice
                    let gasPriceWei = String(gwei * 1_000_000_000)
                    let limit = UInt64(gasLimit) ?? 21000
                    capturedFeeRate = Int(gwei)
                    
                    let nonce = try await broadcaster.getEthereumNonceForChain(address: keys.ethereum.address, chainId: 56)
                    capturedNonce = Int(nonce)
                    
                    let signedHex = try RustCLIBridge.shared.signEthereum(
                        recipient: recipientAddress,
                        amountWei: amountWei,
                        chainId: 56,
                        senderKey: keys.ethereum.privateHex,
                        nonce: nonce,
                        gasLimit: limit,
                        gasPrice: gasPriceWei
                    )
                    
                    txId = try await broadcaster.broadcastEthereumToChain(rawTxHex: signedHex, chainId: 56)
                    
                case .solana:
                    let amountSol = Double(amount) ?? 0
                    let blockhash = try await broadcaster.getSolanaBlockhash(isDevnet: true)
                    
                    let signedBase58 = try RustCLIBridge.shared.signSolana(
                        recipient: recipientAddress,
                        amountSol: amountSol,
                        recentBlockhash: blockhash,
                        senderBase58: keys.solana.privateKeyBase58
                    )
                    
                    txId = try await broadcaster.broadcastSolana(rawTxBase64: signedBase58, isDevnet: true)
                    
                case .xrp:
                    let amountXrp = Double(amount) ?? 0
                    let drops = UInt64(amountXrp * 1_000_000)
                    let sequence = try await broadcaster.getXRPSequence(address: keys.xrp.classicAddress, isTestnet: true)
                    
                    // Parse optional destination tag
                    let destTag: UInt32? = destinationTag.isEmpty ? nil : UInt32(destinationTag)
                    
                    let signedHex = try RustCLIBridge.shared.signXRP(
                        recipient: recipientAddress,
                        amountDrops: drops,
                        senderSeedHex: keys.xrp.privateHex,
                        sequence: sequence,
                        destinationTag: destTag
                    )
                    
                    txId = try await broadcaster.broadcastXRP(rawTxHex: signedHex, isTestnet: true)
                    
                case .monero:
                    throw NSError(domain: "App", code: 2, userInfo: [NSLocalizedDescriptionKey: "Monero sending not yet supported"])
                }
                
                // Success! Show confirmation sheet
                self.isLoading = false
                
                print("[SendView] SUCCESS! Transaction completed with TxID: \(txId)")
                
                // Calculate fee info for display
                let feeInfo = calculateFeeForDisplay(feeRate: capturedFeeRate)
                
                // Create success details
                self.successTransactionDetails = TransactionSuccessDetails(
                    txId: txId,
                    chain: selectedChain,
                    amount: amount,
                    recipient: recipientAddress,
                    feeRate: capturedFeeRate,
                    estimatedFee: feeInfo.fee,
                    feeUnit: feeInfo.unit,
                    timestamp: Date(),
                    senderAddress: getSenderAddress(),
                    nonce: capturedNonce,
                    isRBFEnabled: selectedChain.isBitcoin // Bitcoin txs are RBF by default
                )
                
                print("[SendView] Setting showingSuccessSheet = true")
                
                // Show success sheet with a small delay to ensure state is set
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.showingSuccessSheet = true
                    print("[SendView] showingSuccessSheet is now: \(self.showingSuccessSheet)")
                }
                
                // Store the result to be passed when user dismisses
                self.pendingSuccessResult = TransactionBroadcastResult(
                    txid: txId,
                    chainId: selectedChain.id,
                    chainName: selectedChain.displayName,
                    amount: amount,
                    recipient: recipientAddress,
                    isRBFEnabled: selectedChain.isBitcoin,
                    feeRate: capturedFeeRate,
                    nonce: capturedNonce
                )
                // Note: onSuccess is called when success sheet is dismissed
                
                // Start tracking confirmations for this transaction
                TransactionConfirmationTracker.shared.track(txid: txId, chainId: selectedChain.chainId)
                
            } catch let error as RustCLIError {
                print("[SendView] RUST CLI ERROR: \(error)")
                let errorDesc: String
                switch error {
                case .binaryNotFound:
                    errorDesc = "Rust binary not found. Please build the rust-app first."
                case .executionFailed(let code, let output):
                    errorDesc = "Rust execution failed (code \(code)): \(output)"
                case .outputParsingFailed:
                    errorDesc = "Failed to parse Rust output"
                case .invalidInput:
                    errorDesc = "Invalid input provided to Rust binary"
                }
                self.errorMessage = errorDesc
                self.isLoading = false
                
            } catch {
                print("[SendView] ERROR: \(error)")
                print("[SendView] ERROR localized: \(error.localizedDescription)")
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Helper Methods for Success View
    
    private func calculateFeeForDisplay(feeRate: Int?) -> (fee: String, unit: String) {
        guard let rate = feeRate else { return ("Unknown", "") }
        
        switch selectedChain {
        case .bitcoinTestnet, .bitcoinMainnet:
            // Estimate fee based on typical tx size (140 vB)
            let feeSats = rate * 140
            let feeBTC = Double(feeSats) / 100_000_000.0
            return (String(format: "%.8f BTC", feeBTC), "sat/vB")
        case .litecoin:
            // Litecoin uses similar fee structure (140 vB typical)
            let feeLits = rate * 140
            let feeLTC = Double(feeLits) / 100_000_000.0
            return (String(format: "%.8f LTC", feeLTC), "lit/vB")
        case .ethereum, .polygon, .bnb:
            // Gas price in Gwei, typical 21000 gas for transfer
            let feeGwei = Double(rate) * 21000.0
            let feeETH = feeGwei / 1_000_000_000.0
            let symbol = selectedChain == .polygon ? "MATIC" : selectedChain == .bnb ? "BNB" : "ETH"
            return (String(format: "%.6f \(symbol)", feeETH), "Gwei")
        case .solana:
            return ("0.000005 SOL", "lamports")
        case .xrp:
            return ("0.00001 XRP", "drops")
        case .monero:
            return ("~0.0001 XMR", "")
        }
    }
    
    private func getSenderAddress() -> String {
        switch selectedChain {
        case .bitcoinTestnet: return keys.bitcoinTestnet.address
        case .bitcoinMainnet: return keys.bitcoin.address
        case .litecoin: return keys.litecoin.address
        case .ethereum, .polygon, .bnb: return keys.ethereum.address
        case .solana: return keys.solana.publicKeyBase58
        case .xrp: return keys.xrp.classicAddress
        case .monero: return keys.monero.address
        }
    }
}

// MARK: - Transaction Success Details

struct TransactionSuccessDetails {
    let txId: String
    let chain: Chain
    let amount: String
    let recipient: String
    let feeRate: Int?
    let estimatedFee: String
    let feeUnit: String
    let timestamp: Date
    let senderAddress: String
    let nonce: Int? // For Ethereum tx replacement
    let isRBFEnabled: Bool // For Bitcoin RBF
    
    init(txId: String, chain: Chain, amount: String, recipient: String, feeRate: Int?, estimatedFee: String, feeUnit: String, timestamp: Date, senderAddress: String, nonce: Int? = nil, isRBFEnabled: Bool = true) {
        self.txId = txId
        self.chain = chain
        self.amount = amount
        self.recipient = recipient
        self.feeRate = feeRate
        self.estimatedFee = estimatedFee
        self.feeUnit = feeUnit
        self.timestamp = timestamp
        self.senderAddress = senderAddress
        self.nonce = nonce
        self.isRBFEnabled = isRBFEnabled
    }
    
    /// Convert to PendingTransaction for cancellation/speed-up
    func toPendingTransaction() -> PendingTransactionManager.PendingTransaction {
        PendingTransactionManager.PendingTransaction(
            id: txId,
            chainId: chain.chainId,
            chainName: networkName,
            amount: "\(amount) \(currencySymbol)",
            recipient: recipient,
            timestamp: timestamp,
            status: .pending,
            confirmations: 0,
            explorerURL: explorerURL,
            isRBFEnabled: isRBFEnabled,
            originalFeeRate: feeRate,
            nonce: nonce
        )
    }
    
    var explorerURL: URL? {
        let urlString: String
        switch chain {
        case .bitcoinTestnet: urlString = "https://mempool.space/testnet/tx/\(txId)"
        case .bitcoinMainnet: urlString = "https://mempool.space/tx/\(txId)"
        case .litecoin: urlString = "https://litecoinspace.org/tx/\(txId)"
        case .ethereum: urlString = "https://sepolia.etherscan.io/tx/\(txId)"
        case .polygon: urlString = "https://polygonscan.com/tx/\(txId)"
        case .bnb: urlString = "https://bscscan.com/tx/\(txId)"
        case .solana: urlString = "https://explorer.solana.com/tx/\(txId)?cluster=devnet"
        case .xrp: urlString = "https://testnet.xrpl.org/transactions/\(txId)"
        case .monero: urlString = "https://stagenet.xmrchain.net/search?value=\(txId)"
        }
        return URL(string: urlString)
    }
    
    var explorerName: String {
        switch chain {
        case .bitcoinTestnet, .bitcoinMainnet: return "Mempool.space"
        case .litecoin: return "LitecoinSpace"
        case .ethereum: return "Etherscan"
        case .polygon: return "PolygonScan"
        case .bnb: return "BscScan"
        case .solana: return "Solana Explorer"
        case .xrp: return "XRPL Explorer"
        case .monero: return "XMRChain"
        }
    }
    
    var currencySymbol: String {
        switch chain {
        case .bitcoinTestnet, .bitcoinMainnet: return "BTC"
        case .litecoin: return "LTC"
        case .ethereum: return "ETH"
        case .polygon: return "MATIC"
        case .bnb: return "BNB"
        case .solana: return "SOL"
        case .xrp: return "XRP"
        case .monero: return "XMR"
        }
    }
    
    var networkName: String {
        switch chain {
        case .bitcoinTestnet: return "Bitcoin Testnet"
        case .bitcoinMainnet: return "Bitcoin Mainnet"
        case .litecoin: return "Litecoin Mainnet"
        case .ethereum: return "Ethereum Sepolia"
        case .polygon: return "Polygon Mainnet"
        case .bnb: return "BNB Smart Chain"
        case .solana: return "Solana Devnet"
        case .xrp: return "XRP Testnet"
        case .monero: return "Monero Stagenet"
        }
    }
}

// MARK: - Transaction Success View

struct TransactionSuccessView: View {
    let details: TransactionSuccessDetails
    let keys: AllKeys?
    let onDone: () -> Void
    let onViewExplorer: () -> Void
    let onSpeedUp: (() -> Void)?
    let onCancel: (() -> Void)?
    
    @State private var showCheckmark = false
    @State private var showContent = false
    @State private var copiedTxId = false
    @State private var showConfetti = false
    @State private var showCancellationSheet = false
    @State private var cancellationMode: CancellationMode = .speedUp
    
    /// Whether this transaction supports RBF/speed-up
    private var canSpeedUp: Bool {
        switch details.chain {
        case .bitcoinTestnet, .bitcoinMainnet:
            return details.isRBFEnabled
        case .ethereum:
            return details.nonce != nil
        default:
            return false
        }
    }
    
    init(details: TransactionSuccessDetails, keys: AllKeys? = nil, onDone: @escaping () -> Void, onViewExplorer: @escaping () -> Void, onSpeedUp: (() -> Void)? = nil, onCancel: (() -> Void)? = nil) {
        self.details = details
        self.keys = keys
        self.onDone = onDone
        self.onViewExplorer = onViewExplorer
        self.onSpeedUp = onSpeedUp
        self.onCancel = onCancel
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Success Animation Header
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(HawalaTheme.Colors.success.opacity(0.15))
                            .frame(width: 100, height: 100)
                            .scaleEffect(showCheckmark ? 1 : 0.5)
                            .opacity(showCheckmark ? 1 : 0)
                        
                        Circle()
                            .fill(HawalaTheme.Colors.success.opacity(0.3))
                            .frame(width: 80, height: 80)
                            .scaleEffect(showCheckmark ? 1 : 0.5)
                            .opacity(showCheckmark ? 1 : 0)
                        
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(HawalaTheme.Colors.success)
                            .scaleEffect(showCheckmark ? 1 : 0)
                    }
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: showCheckmark)
                    
                    VStack(spacing: 4) {
                        Text("Transaction Sent!")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                        
                        Text("Your \(details.currencySymbol) is on its way")
                            .font(.subheadline)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                    }
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)
                }
                .padding(.top, 30)
                .padding(.bottom, 24)
            
            // Transaction Details Card
            VStack(spacing: 0) {
                // Amount
                detailRow(
                    icon: "arrow.up.circle.fill",
                    iconColor: HawalaTheme.Colors.error,
                    title: "Amount Sent",
                    value: "\(details.amount) \(details.currencySymbol)"
                )
                
                Divider()
                    .background(HawalaTheme.Colors.border)
                
                // Recipient
                detailRow(
                    icon: "person.circle.fill",
                    iconColor: HawalaTheme.Colors.accent,
                    title: "To",
                    value: truncateAddress(details.recipient),
                    isAddress: true
                )
                
                Divider()
                    .background(HawalaTheme.Colors.border)
                
                // Network
                detailRow(
                    icon: "network",
                    iconColor: HawalaTheme.Colors.warning,
                    title: "Network",
                    value: details.networkName
                )
                
                Divider()
                    .background(HawalaTheme.Colors.border)
                
                // Fee
                detailRow(
                    icon: "flame.fill",
                    iconColor: .orange,
                    title: "Network Fee",
                    value: details.estimatedFee
                )
                
                Divider()
                    .background(HawalaTheme.Colors.border)
                
                // Time
                detailRow(
                    icon: "clock.fill",
                    iconColor: HawalaTheme.Colors.textSecondary,
                    title: "Time",
                    value: formatTime(details.timestamp)
                )
            }
            .background(HawalaTheme.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 20)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)
            
            // Transaction ID Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Transaction ID")
                    .font(.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                
                HStack {
                    Text(details.txId)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                        .lineLimit(2)
                    
                    Spacer()
                    
                    Button(action: copyTxId) {
                        Image(systemName: copiedTxId ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 14))
                            .foregroundColor(copiedTxId ? HawalaTheme.Colors.success : HawalaTheme.Colors.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(HawalaTheme.Colors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .opacity(showContent ? 1 : 0)
            
            Spacer()
            
            // Action Buttons
            VStack(spacing: 12) {
                // RBF Actions Row (Speed Up / Cancel) - Like BlueWallet
                if canSpeedUp {
                    HStack(spacing: 12) {
                        // Speed Up Button
                        Button {
                            if let speedUp = onSpeedUp {
                                speedUp()
                            } else {
                                cancellationMode = .speedUp
                                showCancellationSheet = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 14))
                                Text("Speed Up")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        
                        // Cancel Button
                        Button {
                            if let cancel = onCancel {
                                cancel()
                            } else {
                                cancellationMode = .cancel
                                showCancellationSheet = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                Text("Cancel")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red.opacity(0.15))
                            .foregroundColor(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Info text about RBF
                    Text("Transaction is pending. You can speed it up or cancel before confirmation.")
                        .font(.caption)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                
                // View on Explorer
                Button(action: onViewExplorer) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.right.square.fill")
                        Text("View on \(details.explorerName)")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(HawalaTheme.Colors.accent)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                
                // Done Button
                Button(action: onDone) {
                    Text("Done")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(HawalaTheme.Colors.backgroundSecondary)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .opacity(showContent ? 1 : 0)
            }
            
            // Confetti overlay
            if showConfetti {
                ConfettiView()
                    .allowsHitTesting(false)
            }
        }
        .background(HawalaTheme.Colors.background)
        .sheet(isPresented: $showCancellationSheet) {
            if let keys = keys {
                TransactionCancellationSheet(
                    pendingTx: details.toPendingTransaction(),
                    keys: keys,
                    initialMode: cancellationMode,
                    onDismiss: {
                        showCancellationSheet = false
                    },
                    onSuccess: { newTxId in
                        showCancellationSheet = false
                        // Transaction was replaced - the done callback will refresh
                    }
                )
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                showCheckmark = true
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.2)) {
                showContent = true
            }
            // Trigger confetti
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showConfetti = true
            }
        }
    }
    
    // MARK: - Detail Row
    
    private func detailRow(
        icon: String,
        iconColor: Color,
        title: String,
        value: String,
        isAddress: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(iconColor)
                .frame(width: 24)
            
            Text(title)
                .font(.subheadline)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
            
            Spacer()
            
            Text(value)
                .font(isAddress ? .system(size: 13, design: .monospaced) : .subheadline)
                .fontWeight(.medium)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
    
    // MARK: - Helpers
    
    private func truncateAddress(_ address: String) -> String {
        guard address.count > 16 else { return address }
        let prefix = String(address.prefix(8))
        let suffix = String(address.suffix(6))
        return "\(prefix)...\(suffix)"
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter.string(from: date)
    }
    
    private func copyTxId() {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(details.txId, forType: .string)
        #endif
        
        withAnimation {
            copiedTxId = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedTxId = false
            }
        }
    }
}

struct SendChainPill: View {
    let chain: Chain
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: chain.iconName)
                    .font(.system(size: 12, weight: .semibold))
                
                Text(chain.displayName)
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
                    
                    Text(chain.isBitcoin ? "sat/vB" : "Gwei")
                        .font(.system(size: 9))
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                } else {
                    Text("--")
                        .font(HawalaTheme.Typography.monoSmall)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                
                Text(chain.isBitcoin ? priority.description : priority.ethDescription)
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

// MARK: - Confetti View

struct ConfettiView: View {
    @State private var confettiPieces: [ConfettiPiece] = []
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(confettiPieces) { piece in
                    ConfettiPieceView(piece: piece)
                }
            }
            .onAppear {
                createConfetti(in: geometry.size)
            }
        }
    }
    
    private func createConfetti(in size: CGSize) {
        let colors: [Color] = [
            .green, .yellow, .orange, .red, .pink, .purple, .blue, .cyan,
            HawalaTheme.Colors.success, HawalaTheme.Colors.accent, HawalaTheme.Colors.warning
        ]
        
        for i in 0..<80 {
            let piece = ConfettiPiece(
                id: i,
                color: colors.randomElement() ?? .green,
                startX: CGFloat.random(in: 0...size.width),
                startY: -20,
                endX: CGFloat.random(in: -50...size.width + 50),
                endY: size.height + 50,
                rotation: Double.random(in: 0...720),
                scale: CGFloat.random(in: 0.5...1.2),
                delay: Double(i) * 0.015,
                duration: Double.random(in: 2.5...4.0),
                shape: ConfettiShape.allCases.randomElement() ?? .rectangle
            )
            confettiPieces.append(piece)
        }
    }
}

struct ConfettiPiece: Identifiable {
    let id: Int
    let color: Color
    let startX: CGFloat
    let startY: CGFloat
    let endX: CGFloat
    let endY: CGFloat
    let rotation: Double
    let scale: CGFloat
    let delay: Double
    let duration: Double
    let shape: ConfettiShape
}

enum ConfettiShape: CaseIterable {
    case rectangle
    case circle
    case triangle
}

struct ConfettiPieceView: View {
    let piece: ConfettiPiece
    
    @State private var animate = false
    
    var body: some View {
        confettiShapeView
            .frame(width: 8 * piece.scale, height: 12 * piece.scale)
            .rotationEffect(.degrees(animate ? piece.rotation : 0))
            .position(
                x: animate ? piece.endX : piece.startX,
                y: animate ? piece.endY : piece.startY
            )
            .opacity(animate ? 0 : 1)
            .onAppear {
                withAnimation(
                    .easeOut(duration: piece.duration)
                    .delay(piece.delay)
                ) {
                    animate = true
                }
            }
    }
    
    @ViewBuilder
    private var confettiShapeView: some View {
        switch piece.shape {
        case .rectangle:
            RoundedRectangle(cornerRadius: 2)
                .fill(piece.color)
        case .circle:
            Circle()
                .fill(piece.color)
        case .triangle:
            Triangle()
                .fill(piece.color)
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
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