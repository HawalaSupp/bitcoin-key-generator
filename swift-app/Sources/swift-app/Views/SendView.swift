import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

enum Chain: String, CaseIterable, Identifiable {
    case bitcoinTestnet = "bitcoin-testnet"
    case bitcoinMainnet = "bitcoin-mainnet"
    case litecoin = "litecoin"
    case ethereumSepolia = "ethereum-sepolia"
    case ethereumMainnet = "ethereum-mainnet"
    case polygon
    case bnb
    case solanaDevnet = "solana-devnet"
    case solanaMainnet = "solana-mainnet"
    case xrpTestnet = "xrp-testnet"
    case xrpMainnet = "xrp-mainnet"
    case monero
    
    var id: String { self.rawValue }
    
    var chainId: String {
        switch self {
        case .bitcoinTestnet: return "bitcoin-testnet"
        case .bitcoinMainnet: return "bitcoin-mainnet"
        case .litecoin: return "litecoin"
        case .ethereumSepolia: return "ethereum-sepolia"
        case .ethereumMainnet: return "ethereum-mainnet"
        case .polygon: return "polygon-mainnet"
        case .bnb: return "bsc-mainnet"
        case .solanaDevnet: return "solana-devnet"
        case .solanaMainnet: return "solana-mainnet"
        case .xrpTestnet: return "xrp-testnet"
        case .xrpMainnet: return "xrp-mainnet"
        case .monero: return "monero"
        }
    }
    
    var displayName: String {
        switch self {
        case .bitcoinTestnet: return "BTC Testnet"
        case .bitcoinMainnet: return "BTC Mainnet"
        case .litecoin: return "Litecoin"
        case .ethereumSepolia: return "ETH Sepolia"
        case .ethereumMainnet: return "ETH Mainnet"
        case .polygon: return "Polygon"
        case .bnb: return "BNB Chain"
        case .solanaDevnet: return "SOL Devnet"
        case .solanaMainnet: return "SOL Mainnet"
        case .xrpTestnet: return "XRP Testnet"
        case .xrpMainnet: return "XRP Mainnet"
        case .monero: return "Monero"
        }
    }
    
    var iconName: String {
        switch self {
        case .bitcoinTestnet: return "bitcoinsign"
        case .bitcoinMainnet: return "bitcoinsign.circle.fill"
        case .litecoin: return "l.circle.fill"
        case .ethereumSepolia: return "e.circle"
        case .ethereumMainnet: return "e.circle.fill"
        case .polygon: return "p.circle.fill"
        case .bnb: return "b.circle.fill"
        case .solanaDevnet: return "s.circle"
        case .solanaMainnet: return "s.circle.fill"
        case .xrpTestnet: return "x.circle"
        case .xrpMainnet: return "x.circle.fill"
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
        self == .ethereumSepolia || self == .ethereumMainnet || self == .polygon || self == .bnb
    }
    
    var isEthereum: Bool {
        self == .ethereumSepolia || self == .ethereumMainnet
    }
    
    var isSolana: Bool {
        self == .solanaDevnet || self == .solanaMainnet
    }
    
    var isXRP: Bool {
        self == .xrpTestnet || self == .xrpMainnet
    }
    
    var isTestnet: Bool {
        switch self {
        case .bitcoinTestnet, .ethereumSepolia, .solanaDevnet, .xrpTestnet:
            return true
        default:
            return false
        }
    }
    
    /// EVM chain ID for transaction signing
    var evmChainId: UInt64? {
        switch self {
        case .ethereumSepolia: return 11155111  // Sepolia testnet
        case .ethereumMainnet: return 1         // Ethereum mainnet
        case .polygon: return 137               // Polygon mainnet
        case .bnb: return 56                    // BSC mainnet
        default: return nil
        }
    }
    
    /// Native token symbol
    var nativeSymbol: String {
        switch self {
        case .bitcoinTestnet, .bitcoinMainnet: return "BTC"
        case .litecoin: return "LTC"
        case .ethereumSepolia, .ethereumMainnet: return "ETH"
        case .polygon: return "POL"
        case .bnb: return "BNB"
        case .solanaDevnet, .solanaMainnet: return "SOL"
        case .xrpTestnet, .xrpMainnet: return "XRP"
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
    @ObservedObject var balanceService = BalanceService.shared
    @StateObject private var feeEstimator = FeeEstimator.shared
    @StateObject private var feeWarningService = FeeWarningService.shared
    
    // Keys passed from parent
    let keys: AllKeys
    
    // Biometric setting for transaction confirmation
    @AppStorage("hawala.biometricForSends") private var biometricForSends = true
    
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
    @State private var nonce: String = "" // For ETH
    @State private var maxFeePerGas: String = "" // For ETH EIP-1559
    @State private var maxPriorityFeePerGas: String = "" // For ETH EIP-1559
    
    // Taproot toggle for Bitcoin - currently disabled (requires Taproot UTXOs)
    // Will be enabled once wallet supports receiving to Taproot addresses
    @State private var useTaproot: Bool = false
    
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
    
    // Security check state (P6 integration)
    @State private var showingSecurityCheck = false
    @State private var securityCheckPassed = false
    
    // Fee warnings state
    @State private var feeWarnings: [FeeWarning] = []
    
    // First-time address warning (ROADMAP-05 E5)
    @State private var showingFirstTimeWarning = false
    
    // Scam address blocking modal (ROADMAP-08 E2)
    @State private var showingScamBlockingModal = false
    @State private var scamReasons: [String] = []
    @State private var scamRiskLevel: AddressRiskLevel = .medium
    
    // Amount validation (ROADMAP-05 E8-E11)
    @State private var amountValidationError: String?
    
    // Fee estimate timestamp for expiry warning (ROADMAP-05 E16)
    @State private var feeEstimateTimestamp: Date = Date()
    @State private var showFeeExpiredWarning = false
    
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
            
            mainContent
            
            // Loading Overlay
            if isLoading {
                loadingOverlay
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: handleOnAppear)
        .onChange(of: selectedChain, perform: handleChainChange)
        .onChange(of: selectedFeePriority) { _ in updateFeeFromPriority() }
        .onChange(of: amount) { newValue in
            // ROADMAP-05 E9: Locale separator handling — convert commas to dots
            let sanitized = newValue.replacingOccurrences(of: ",", with: ".")
            if sanitized != newValue {
                amount = sanitized
                return // onChange will re-fire with sanitized value
            }
            // ROADMAP-05 E8-E11: Validate amount using AmountValidator
            validateAmount()
            updateFeeWarnings()
        }
        .onChange(of: feeRate) { _ in if selectedChain.isBitcoin { updateFeeWarnings() } }
        .sheet(isPresented: $showingQRScanner, content: qrScannerSheet)
        .sheet(isPresented: $showingReview, content: reviewSheet)
        .sheet(isPresented: $showingSuccessSheet, content: successSheet)
        .sheet(isPresented: $showingSecurityCheck, content: securityCheckSheet)
        .sheet(isPresented: $showBackupRequiredSheet, content: backupRequiredSheet)
        .sheet(isPresented: $showingFirstTimeWarning) {
            FirstTimeSendWarning(
                address: recipientAddress,
                onProceed: {
                    showingFirstTimeWarning = false
                    // Continue to security check flow
                    proceedToSecurityCheck()
                },
                onCancel: {
                    showingFirstTimeWarning = false
                }
            )
        }
        .sheet(isPresented: $showingScamBlockingModal) {
            ScamAddressBlockingModal(
                address: recipientAddress,
                riskLevel: scamRiskLevel,
                reasons: scamReasons,
                onProceedAnyway: {
                    showingScamBlockingModal = false
                    // User explicitly acknowledged — continue to first-time/security check
                    continueAfterScamCheck()
                },
                onCancel: {
                    showingScamBlockingModal = false
                }
            )
        }
    }
    
    // MARK: - Backup Required Sheet (ROADMAP-02)
    
    @ViewBuilder
    private func backupRequiredSheet() -> some View {
        VStack(spacing: 24) {
            // Warning icon
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
                .padding(.top, 32)
            
            // Title
            Text("Backup verification required")
                .font(.custom("ClashGrotesk-Bold", size: 24))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            // Explanation
            VStack(alignment: .leading, spacing: 12) {
                Text("To send more than $\(Int(BackupVerificationManager.shared.unverifiedSendLimitUSD)), you need to verify your recovery phrase backup.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                
                Text("This ensures you can recover your funds if you lose access to this device.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Buttons
            VStack(spacing: 12) {
                Button(action: {
                    showBackupRequiredSheet = false
                    // Navigate to settings -> security -> backup verification
                    // For now just dismiss - in production would navigate
                }) {
                    Text("Verify backup in Settings")
                        .font(.custom("ClashGrotesk-Semibold", size: 16))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    showBackupRequiredSheet = false
                }) {
                    Text("Send smaller amount instead")
                        .font(.custom("ClashGrotesk-Medium", size: 14))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: 450, maxHeight: 450)
        .background(Color(hex: "#1A1A1A"))
        .cornerRadius(20)
    }
    
    private func securityCheckSheet() -> some View {
        TransactionSecurityCheckView(
            walletId: "default",
            recipient: recipientAddress,
            amount: "\(amount) \(selectedChain.nativeSymbol)",
            chain: chainToHawalaChain(selectedChain),
            onApprove: {
                securityCheckPassed = true
                showingSecurityCheck = false
                // Now show the review screen
                showReviewScreen()
            },
            onReject: {
                securityCheckPassed = false
                showingSecurityCheck = false
            }
        )
    }
    
    private func chainToHawalaChain(_ chain: Chain) -> HawalaChain {
        switch chain {
        case .bitcoinTestnet: return .bitcoinTestnet
        case .bitcoinMainnet: return .bitcoin
        case .litecoin: return .litecoin
        case .ethereumSepolia: return .ethereumSepolia
        case .ethereumMainnet: return .ethereum
        case .polygon: return .polygon
        case .bnb: return .bnb
        case .solanaDevnet: return .solanaDevnet
        case .solanaMainnet: return .solana
        case .xrpTestnet: return .xrpTestnet
        case .xrpMainnet: return .xrp
        case .monero: return .ethereum // fallback, monero not supported for sending
        }
    }
    
    private func handleOnAppear() {
        withAnimation(HawalaTheme.Animation.spring) {
            appearAnimation = true
        }
        Task {
            await feeEstimator.fetchBitcoinFees(isTestnet: true)
            await feeEstimator.fetchEthereumFees()
            
            if selectedChain == .bitcoinTestnet {
                await UTXOCoinControlManager.shared.refreshUTXOs(for: keys.bitcoinTestnet.address, chain: .bitcoinTestnet)
            } else if selectedChain == .bitcoinMainnet {
                await UTXOCoinControlManager.shared.refreshUTXOs(for: keys.bitcoin.address, chain: .bitcoinMainnet)
            } else if selectedChain == .litecoin {
                await UTXOCoinControlManager.shared.refreshUTXOs(for: keys.litecoin.address, chain: .litecoin)
            } else if selectedChain.isEVM {
                // Fetch gas price for EVM chains on appear
                await fetchGasPriceForChain()
            }
        }
    }

    private func handleChainChange(_ newChain: Chain) {
        updateFeeFromPriority()
        if !recipientAddress.isEmpty {
            validateAddressAsync()
        }
        
        Task {
            if newChain == .bitcoinTestnet {
                await UTXOCoinControlManager.shared.refreshUTXOs(for: keys.bitcoinTestnet.address, chain: .bitcoinTestnet)
            } else if newChain == .bitcoinMainnet {
                await UTXOCoinControlManager.shared.refreshUTXOs(for: keys.bitcoin.address, chain: .bitcoinMainnet)
            } else if newChain == .litecoin {
                await UTXOCoinControlManager.shared.refreshUTXOs(for: keys.litecoin.address, chain: .litecoin)
            } else if newChain.isEVM {
                // Fetch current gas price for the EVM chain
                await fetchGasPriceForChain()
                // Auto-estimate gas limit if enabled and address is set
                if autoEstimateGas && !recipientAddress.isEmpty {
                    await estimateGasLimit()
                }
            }
        }
    }

    private func qrScannerSheet() -> some View {
        QRCameraScannerView(isPresented: $showingQRScanner, onScan: { code in
            showingQRScanner = false
            handleScannedQR(code)
        })
    }

    private func reviewSheet() -> some View {
        Group {
            if let data = reviewData {
                TransactionReviewView(transaction: data, onConfirm: {
                    showingReview = false
                    sendTransaction()
                }, onCancel: {
                    showingReview = false
                })
            } else {
                EmptyView()
            }
        }
    }

    private func successSheet() -> some View {
        Group {
            if let details = successTransactionDetails {
                TransactionSuccessView(
                    details: details,
                    keys: keys,
                    onDone: {
                        showingSuccessSheet = false
                        dismiss()
                        let result = TransactionBroadcastResult(
                            txid: details.txId,
                            chainId: details.chain.chainId,
                            chainName: details.chain.displayName,
                            amount: details.amount,
                            recipient: details.recipient,
                            isRBFEnabled: details.isRBFEnabled,
                            feeRate: details.feeRate,
                            nonce: details.nonce
                        )
                        onSuccess?(result)
                    },
                    onViewExplorer: {
                        openExplorer(txId: details.txId)
                    }
                )
            } else {
                EmptyView()
            }
        }
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            // Custom Header
            sendHeader
            
            // Scrollable Content
            ScrollView(showsIndicators: false) {
                scrollContent
            }
            
            // Bottom Action Button
            bottomActionBar
        }
    }
    
    private var scrollContent: some View {
        VStack(spacing: HawalaTheme.Spacing.lg) {
            // Chain Selector
            chainSelectorSection
            
            // View-Only Warning (for chains that don't support sending)
            if !selectedChain.supportsSending {
                viewOnlyWarningBanner
            }
            
            // Recipient Address
            recipientSection
            
            // Recent Recipients (ROADMAP-05 E7)
            recentRecipientsSection
            
            // Amount Input
            amountSection
            
            // Fee Settings (BTC/LTC/ETH only)
            if selectedChain.isUTXOBased || selectedChain.isEVM {
                feeSection
                
                // Fee Warnings
                if !feeWarnings.isEmpty {
                    feeWarningsSection
                }
            }
            
            // Fixed Fee Info (Solana/XRP)
            if selectedChain.isSolana || selectedChain.isXRP {
                fixedFeeInfoSection
            }
            
            // XRP Destination Tag
            if selectedChain.isXRP {
                xrpOptionsSection
            }
            
            // Estimated Arrival Time (ROADMAP-05 E12)
            if !amount.isEmpty, let amtVal = Double(amount), amtVal > 0 {
                estimatedArrivalRow
            }
            
            // Fee Expiry Warning (ROADMAP-05 E16)
            if showFeeExpiredWarning {
                feeExpiredWarningBanner
            }
            
            // Amount Validation Error (ROADMAP-05 E8-E11)
            if let validationError = amountValidationError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                    Text(validationError)
                        .font(HawalaTheme.Typography.caption)
                }
                .foregroundColor(HawalaTheme.Colors.error)
                .padding(.horizontal, HawalaTheme.Spacing.sm)
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
                    .accessibilityLabel("Recipient address")
                    .accessibilityHint("Enter wallet address or ENS domain name")
                    .accessibilityIdentifier("send_recipient_address_field")
                    .onChange(of: recipientAddress) { _ in
                        validateAddressAsync()
                        // Trigger gas estimation for all EVM chains (Ethereum, Polygon, BNB)
                        if autoEstimateGas && selectedChain.isEVM {
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
                .accessibilityLabel("Scan QR code")
                .accessibilityHint("Open camera to scan recipient address from QR code")
                .accessibilityIdentifier("send_scan_qr_button")
                
                // Paste button
                Button(action: pasteFromClipboard) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 14))
                        .foregroundColor(HawalaTheme.Colors.accent)
                }
                .buttonStyle(.plain)
                .help("Paste from clipboard")
                .accessibilityLabel("Paste address")
                .accessibilityHint("Paste wallet address from clipboard")
                .accessibilityIdentifier("send_paste_address_button")
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
            if selectedChain.isEthereum {
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
                    .accessibilityLabel("Amount to send")
                    .accessibilityHint("Enter amount in \(chainSymbol)")
                    .accessibilityIdentifier("send_amount_field")
                
                Spacer()
                
                // Send Max button
                Button(action: fillMaxAmount) {
                    Text("MAX")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(HawalaTheme.Colors.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(HawalaTheme.Colors.accent.opacity(0.15))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send maximum amount")
                .accessibilityHint("Sets the amount to your full available balance")
                .accessibilityIdentifier("send_max_button")
                
                Text(chainSymbol)
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            
            // Available balance row
            HStack {
                Text(amountHint)
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                Spacer()
                
                if let balance = availableBalanceString {
                    Text("Available: \(balance) \(chainSymbol)")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
            }
        }
        .hawalaCard()
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(HawalaTheme.Animation.spring.delay(0.1), value: appearAnimation)
    }
    
    // MARK: - Recent Recipients (ROADMAP-05 E7)
    
    @ViewBuilder
    private var recentRecipientsSection: some View {
        let recents = AddressIntelligenceManager.shared.getRecentRecipients(limit: 5)
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                Text("RECENT")
                    .font(HawalaTheme.Typography.label)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                    .tracking(1)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: HawalaTheme.Spacing.sm) {
                        ForEach(recents, id: \.address) { entry in
                            Button(action: {
                                recipientAddress = entry.address
                                validateAddressAsync()
                            }) {
                                VStack(spacing: 4) {
                                    ZStack {
                                        Circle()
                                            .fill(HawalaTheme.Colors.accent.opacity(0.15))
                                            .frame(width: 36, height: 36)
                                        Text(String(entry.address.suffix(2)).uppercased())
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(HawalaTheme.Colors.accent)
                                    }
                                    Text(truncateAddress(entry.address))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                                    Text("\(entry.count)×")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(HawalaTheme.Colors.backgroundTertiary)
                                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .opacity(appearAnimation ? 1 : 0)
            .offset(y: appearAnimation ? 0 : 20)
            .animation(HawalaTheme.Animation.spring.delay(0.07), value: appearAnimation)
        }
    }
    
    private func truncateAddress(_ addr: String) -> String {
        guard addr.count > 12 else { return addr }
        return "\(addr.prefix(6))…\(addr.suffix(4))"
    }
    
    // MARK: - Estimated Arrival (ROADMAP-05 E12)
    
    private var estimatedArrivalRow: some View {
        let (_, _, _, eta) = calculateFeeDetails()
        return HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 14))
                .foregroundColor(HawalaTheme.Colors.accent)
            Text("Estimated arrival")
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
            Spacer()
            Text("~\(eta)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(HawalaTheme.Colors.textPrimary)
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
    }
    
    // MARK: - Fee Expiry Warning (ROADMAP-05 E16)
    
    private var feeExpiredWarningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("Fee estimate may have changed.")
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(.orange)
            Spacer()
            Button(action: {
                refreshFees()
            }) {
                Text("Refresh")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(HawalaTheme.Spacing.md)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
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
                .accessibilityLabel("Refresh network fees")
                .accessibilityHint("Fetch current network fee estimates")
                .accessibilityIdentifier("send_refresh_fees_button")
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
                .accessibilityLabel("Custom fee")
                .accessibilityHint("Toggle to set a custom network fee")
                .accessibilityIdentifier("send_custom_fee_toggle")
            }
            
            // Custom Fee Input
            if useCustomFee {
                HStack {
                    TextField("", text: selectedChain.isBitcoin ? $feeRate : $gasPrice)
                        .textFieldStyle(.plain)
                        .font(HawalaTheme.Typography.mono)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                        .accessibilityLabel(selectedChain.isBitcoin ? "Fee rate in satoshis per virtual byte" : "Gas price in Gwei")
                        .accessibilityHint("Enter custom transaction fee")
                    
                    Text(selectedChain.isBitcoin ? "sat/vB" : "Gwei")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                .padding(HawalaTheme.Spacing.md)
                .background(HawalaTheme.Colors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            }
            
            // NOTE: Taproot (P2TR) toggle is hidden for now
            // Taproot requires UTXOs on a Taproot address (bc1p/tb1p)
            // Current wallet uses SegWit addresses (bc1q/tb1q) 
            // Future: Add support for receiving to Taproot and then sending with Taproot
            // For now, all transactions use SegWit (still efficient and widely supported)
            
            // Gas Limit (ETH/EVM only)
            if selectedChain.isEVM {
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
                            .accessibilityLabel("Auto-estimate gas")
                            .accessibilityHint("Automatically estimate gas limit for transaction")
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
                                .accessibilityLabel("Gas limit")
                                .accessibilityHint("Maximum gas units for this transaction")
                            
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
        case .solanaDevnet, .solanaMainnet:
            return "~0.000005 SOL"
        case .xrpTestnet, .xrpMainnet:
            return "~0.00001 XRP"
        default:
            return "N/A"
        }
    }
    
    private var fixedFeeDescription: String {
        switch selectedChain {
        case .solanaDevnet, .solanaMainnet:
            return "Fixed network fee (~$0.001) • ~1 min confirmation"
        case .xrpTestnet, .xrpMainnet:
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
            
            Button(action: initiateSecurityCheckAndReview) {
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
            .accessibilityLabel(isLoading ? "Sending transaction" : "Review transaction")
            .accessibilityHint("Review and confirm transaction details before sending")
            .accessibilityIdentifier("send_review_button")
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
                selectedChain = .ethereumSepolia
            case .solana:
                selectedChain = .solanaDevnet
            case .xrp:
                selectedChain = .xrpTestnet
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
            // ROADMAP-05 E16: Reset fee estimate timestamp
            feeEstimateTimestamp = Date()
            showFeeExpiredWarning = false
        }
    }
    
    /// Estimate gas limit for EVM transactions (Ethereum, Polygon, BNB)
    private func estimateGasLimit() async {
        // Only estimate gas for EVM chains
        guard selectedChain.isEVM else {
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
        
        // Get sender address based on chain
        // For EVM chains, we use the same Ethereum address (all EVM chains share the same key)
        let fromAddress: String
        switch selectedChain {
        case .ethereumSepolia:
            fromAddress = keys.ethereumSepolia.address
        case .ethereumMainnet, .polygon, .bnb:
            // Mainnet EVM chains share the same EVM address
            fromAddress = keys.ethereum.address
        default:
            fromAddress = keys.ethereumSepolia.address
        }
        
        // Convert amount to wei hex (Decimal-safe — ROADMAP-05 E1)
        let weiValue = safeAmountToWeiHex(amount)
        
        // Get chain ID for the selected chain
        let chainId = Int(selectedChain.evmChainId ?? 1)
        
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
    
    /// Fetch and update gas price for the selected EVM chain
    /// For post-London chains (Ethereum, Sepolia), also sets EIP-1559 parameters
    private func fetchGasPriceForChain() async {
        guard selectedChain.isEVM, !useCustomFee else { return }
        
        guard let chainId = selectedChain.evmChainId else { return }

        // Fetch actual baseFee from latest block — this determines what fee is required for inclusion.
        let baseFeeGwei = await FeeEstimationService.shared.fetchBaseFee(for: Int(chainId)) ?? 10.0
        #if DEBUG
        print("[SendView] Fetched baseFee for \(selectedChain): \(baseFeeGwei) Gwei")
        #endif

        // Priority fee (tip to validators).
        // For testnets, use generous priority; for mainnet, moderate.
        let priorityFee: Double
        switch selectedChain {
        case .ethereumSepolia:
            // Sepolia is free — use high tip for instant inclusion.
            priorityFee = max(5.0, baseFeeGwei * 0.5)
        case .ethereumMainnet:
            priorityFee = max(2.0, baseFeeGwei * 0.1)
        case .polygon:
            priorityFee = max(30.0, baseFeeGwei * 0.3)
        case .bnb:
            priorityFee = max(1.0, baseFeeGwei * 0.1)
        default:
            priorityFee = max(2.0, baseFeeGwei * 0.1)
        }

        // maxFeePerGas = 2×baseFee + priorityFee  (industry-standard safe cap)
        // This ensures the tx can tolerate up to one baseFee doubling and still be included.
        let maxFee = 2.0 * baseFeeGwei + priorityFee

        // Round up to nearest whole gwei.
        gasPrice = String(format: "%.0f", ceil(maxFee))
        maxFeePerGas = gasPrice
        maxPriorityFeePerGas = String(format: "%.0f", ceil(priorityFee))

        #if DEBUG
        print("[SendView] ✅ EIP-1559 SET for \(selectedChain): baseFee=\(baseFeeGwei) Gwei, maxFee=\(maxFeePerGas) Gwei, priorityFee=\(maxPriorityFeePerGas) Gwei")
        #endif
        #if DEBUG
        print("[SendView] Gas price for \(selectedChain): final gasPrice=\(gasPrice) Gwei")
        #endif
    }
    
    private func getEstimate(for priority: FeePriority) -> FeeEstimate? {
        if selectedChain.isBitcoin {
            return feeEstimator.getBitcoinEstimate(for: priority)
        } else {
            return feeEstimator.getEthereumEstimate(for: priority)
        }
    }
    
    // MARK: - Safe Decimal Conversion Helpers (ROADMAP-05 E1)
    
    /// Safely converts an amount string to smallest unit (sats, drops, wei) using Decimal
    /// to prevent UInt64 overflow that occurs with Double multiplication.
    private func safeAmountToSmallestUnit(_ amountString: String, multiplier: Decimal) -> UInt64 {
        guard let d = Decimal(string: amountString), d > 0 else { return 0 }
        let scaled = d * multiplier
        guard scaled >= 0, scaled <= Decimal(UInt64.max) else { return 0 }
        return NSDecimalNumber(decimal: scaled).uint64Value
    }
    
    /// Safely converts a Double gas/fee value to Wei (from Gwei) using Decimal
    private func safeGweiToWei(_ gwei: Double) -> UInt64 {
        let d = Decimal(gwei) * Decimal(1_000_000_000)
        guard d >= 0, d <= Decimal(UInt64.max) else { return 0 }
        return NSDecimalNumber(decimal: d).uint64Value
    }
    
    /// Safely converts an ETH amount string to a hex-encoded wei value for EVM gas estimation
    private func safeAmountToWeiHex(_ amountString: String) -> String {
        guard let d = Decimal(string: amountString), d > 0 else { return "0x0" }
        let wei = d * Decimal(string: "1000000000000000000")!
        guard wei >= 0, wei <= Decimal(UInt64.max) else { return "0x0" }
        return "0x" + String(NSDecimalNumber(decimal: wei).uint64Value, radix: 16)
    }
    
    // MARK: - Computed Properties
    
    private var canSend: Bool {
        guard selectedChain.supportsSending else { return false }
        guard !isLoading else { return false }
        guard !recipientAddress.isEmpty else { return false }
        guard !amount.isEmpty else { return false }
        guard let result = addressValidationResult, result.isValid else { return false }
        guard Double(amount) ?? 0 > 0 else { return false }
        // ROADMAP-05 E10/E11: Block send if amount validation fails
        guard amountValidationError == nil else { return false }
        return true
    }
    
    /// The available balance for the currently selected chain, or nil if not loaded
    private var availableBalanceString: String? {
        let chainId = selectedChain.chainId
        guard let state = balanceService.balanceStates[chainId] else { return nil }
        switch state {
        case .loaded(let value, _), .refreshing(let value, _), .stale(let value, _, _):
            // Extract just the numeric portion (balance strings may include chain symbol)
            let numericString = value.components(separatedBy: CharacterSet.decimalDigits.inverted.subtracting(CharacterSet(charactersIn: ".")))
                .joined()
            return numericString.isEmpty ? nil : numericString
        case .idle, .loading, .failed:
            return nil
        }
    }
    
    /// Fills the amount field with the maximum available balance minus estimated fees (ROADMAP-05 E6)
    private func fillMaxAmount() {
        guard let maxBalance = availableBalanceString,
              let maxDecimal = Decimal(string: maxBalance), maxDecimal > 0 else {
            return
        }
        
        // Subtract estimated fees from max balance
        let feeReserve: Decimal
        switch selectedChain {
        case .bitcoinTestnet, .bitcoinMainnet, .litecoin:
            // BTC/LTC: fee = feeRate * ~200 vbytes, in sats → convert to BTC
            let feeRateSats = Decimal(effectiveBitcoinFeeRate)
            let estimatedSats = feeRateSats * 200 + 1000 // buffer for change output
            feeReserve = estimatedSats / Decimal(100_000_000)
        case .ethereumSepolia, .ethereumMainnet, .polygon, .bnb:
            // ETH: fee = gasPrice (gwei) * gasLimit → convert to ETH
            let gasPriceVal = Decimal(string: gasPrice) ?? 20
            let gasLimitVal = Decimal(string: gasLimit) ?? 21000
            feeReserve = (gasPriceVal * gasLimitVal) / Decimal(string: "1000000000")! // gwei to ETH
        case .solanaDevnet, .solanaMainnet:
            feeReserve = Decimal(string: "0.000005")! // ~5000 lamports
        case .xrpTestnet, .xrpMainnet:
            feeReserve = Decimal(string: "10.000012")! // 10 XRP reserve + 12 drops fee
        case .monero:
            feeReserve = Decimal(string: "0.0001")! // typical monero fee
        }
        
        let spendable = maxDecimal - feeReserve
        guard spendable > 0 else {
            amount = "0"
            return
        }
        
        // Format without trailing zeros but preserve necessary precision
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8
        formatter.minimumFractionDigits = 0
        formatter.groupingSeparator = ""
        amount = formatter.string(from: NSDecimalNumber(decimal: spendable)) ?? String(describing: spendable)
    }
    
    private var amountHint: String {
        switch selectedChain {
        case .bitcoinTestnet, .bitcoinMainnet: return "Amount in BTC (e.g., 0.001)"
        case .litecoin: return "Amount in LTC (e.g., 0.1)"
        case .ethereumSepolia, .ethereumMainnet: return "Amount in ETH (e.g., 0.01)"
        case .polygon: return "Amount in MATIC (e.g., 1.0)"
        case .bnb: return "Amount in BNB (e.g., 0.01)"
        case .solanaDevnet, .solanaMainnet: return "Amount in SOL (e.g., 0.1)"
        case .xrpTestnet, .xrpMainnet: return "Amount in XRP (e.g., 10)"
        case .monero: return "Amount in XMR"
        }
    }
    
    private var chainSymbol: String {
        switch selectedChain {
        case .bitcoinTestnet, .bitcoinMainnet: return "BTC"
        case .litecoin: return "LTC"
        case .ethereumSepolia, .ethereumMainnet: return "ETH"
        case .polygon: return "MATIC"
        case .bnb: return "BNB"
        case .solanaDevnet, .solanaMainnet: return "SOL"
        case .xrpTestnet, .xrpMainnet: return "XRP"
        case .monero: return "XMR"
        }
    }
    
    private var chainDisplayName: String {
        switch selectedChain {
        case .bitcoinTestnet: return "Bitcoin Testnet"
        case .bitcoinMainnet: return "Bitcoin Mainnet"
        case .litecoin: return "Litecoin Mainnet"
        case .ethereumSepolia: return "Ethereum Sepolia"
        case .ethereumMainnet: return "Ethereum Mainnet"
        case .polygon: return "Polygon Mainnet"
        case .bnb: return "BNB Smart Chain"
        case .solanaDevnet: return "Solana Devnet"
        case .solanaMainnet: return "Solana Mainnet"
        case .xrpTestnet: return "XRP Testnet"
        case .xrpMainnet: return "XRP Mainnet"
        case .monero: return "Monero Stagenet"
        }
    }
    
    private var chainIcon: String {
        selectedChain.iconName
    }
    
    // MARK: - Amount Validation (ROADMAP-05 E8-E11)
    
    private func validateAmount() {
        let trimmed = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            amountValidationError = nil
            return
        }
        
        let result: AmountValidationResult
        switch selectedChain {
        case .bitcoinTestnet, .bitcoinMainnet, .litecoin:
            // Get available sats from balance
            let availableSats: Int64
            if let balStr = availableBalanceString, let dec = Decimal(string: balStr) {
                availableSats = NSDecimalNumber(decimal: dec * Decimal(100_000_000)).int64Value
            } else {
                availableSats = 0
            }
            let feeSats = Int64(effectiveBitcoinFeeRate) * 200 + 1000
            let balanceLoaded = availableBalanceString != nil
            result = AmountValidator.validateBitcoin(
                amountString: trimmed,
                availableSats: availableSats,
                estimatedFeeSats: feeSats,
                balanceLoaded: balanceLoaded
            )
        case .ethereumSepolia, .ethereumMainnet, .polygon, .bnb:
            let available: Decimal
            if let balStr = availableBalanceString, let d = Decimal(string: balStr) {
                available = d
            } else {
                available = 0
            }
            let gasPriceVal = Decimal(string: gasPrice) ?? 20
            let gasLimitVal = Decimal(string: gasLimit) ?? 21000
            let feeReserve = (gasPriceVal * gasLimitVal) / Decimal(string: "1000000000")!
            result = AmountValidator.validateDecimalAsset(
                amountString: trimmed,
                assetName: chainSymbol,
                available: available,
                precision: 18,
                minimum: Decimal(string: "0.000001")!,
                reserved: feeReserve
            )
        case .solanaDevnet, .solanaMainnet:
            let available: Decimal
            if let balStr = availableBalanceString, let d = Decimal(string: balStr) {
                available = d
            } else {
                available = 0
            }
            result = AmountValidator.validateDecimalAsset(
                amountString: trimmed,
                assetName: "SOL",
                available: available,
                precision: 9,
                minimum: Decimal(string: "0.000001")!,
                reserved: Decimal(string: "0.000005")!
            )
        case .xrpTestnet, .xrpMainnet:
            let available: Decimal
            if let balStr = availableBalanceString, let d = Decimal(string: balStr) {
                available = d
            } else {
                available = 0
            }
            result = AmountValidator.validateDecimalAsset(
                amountString: trimmed,
                assetName: "XRP",
                available: available,
                precision: 6,
                minimum: Decimal(string: "0.000001")!,
                reserved: Decimal(string: "10.000012")! // 10 XRP reserve + fee
            )
        case .monero:
            let available: Decimal
            if let balStr = availableBalanceString, let d = Decimal(string: balStr) {
                available = d
            } else {
                available = 0
            }
            result = AmountValidator.validateDecimalAsset(
                amountString: trimmed,
                assetName: "XMR",
                available: available,
                precision: 12,
                minimum: Decimal(string: "0.000000000001")!,
                reserved: Decimal(string: "0.0001")!
            )
        }
        
        switch result {
        case .empty:
            amountValidationError = nil
        case .valid:
            amountValidationError = nil
        case .invalid(let message):
            amountValidationError = message
        }
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
        case .ethereumSepolia: urlString = "https://sepolia.etherscan.io/tx/\(txId)"
        case .ethereumMainnet: urlString = "https://etherscan.io/tx/\(txId)"
        case .polygon: urlString = "https://polygonscan.com/tx/\(txId)"
        case .bnb: urlString = "https://bscscan.com/tx/\(txId)"
        case .solanaDevnet: urlString = "https://explorer.solana.com/tx/\(txId)?cluster=devnet"
        case .solanaMainnet: urlString = "https://explorer.solana.com/tx/\(txId)"
        case .xrpTestnet: urlString = "https://testnet.xrpl.org/transactions/\(txId)"
        case .xrpMainnet: urlString = "https://xrpscan.com/tx/\(txId)"
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
        case .ethereumSepolia, .ethereumMainnet:
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
        case .ethereumSepolia, .ethereumMainnet:
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
        // Decimal-safe ETH→Wei conversion (ROADMAP-05 E1)
        let amountDecimal = Decimal(amount) * Decimal(string: "1000000000000000000")!
        let amountWei = amountDecimal <= Decimal(UInt64.max) ? NSDecimalNumber(decimal: amountDecimal).uint64Value : UInt64.max
        
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
    
    // MARK: - Security Check (P6 Integration)
    
    /// Initiates the security check flow before showing the review screen
    private func initiateSecurityCheckAndReview() {
        // ROADMAP-05 E16: Check if fee estimate is stale (> 30s)
        if Date().timeIntervalSince(feeEstimateTimestamp) > 30 {
            showFeeExpiredWarning = true
            return
        }
        
        // ROADMAP-08 E2: Scam address screening (async)
        Task { @MainActor in
            await performScamScreening()
        }
    }
    
    /// ROADMAP-08 E1/E2: Screen address against GoPlus API + local lists before proceeding
    private func performScamScreening() async {
        let manager = AddressIntelligenceManager.shared
        
        // Quick local check first (instant)
        let quickRisk = manager.quickRiskCheck(recipientAddress)
        
        if quickRisk == .critical {
            // Sanctioned address — block immediately
            scamRiskLevel = .critical
            scamReasons = ["OFAC Sanctioned Address", "Sending to this address is prohibited by law."]
            showingScamBlockingModal = true
            return
        }
        
        if quickRisk == .high {
            // Known scam from local list
            scamRiskLevel = .high
            scamReasons = ["Previously reported scam address"]
            showingScamBlockingModal = true
            return
        }
        
        // GoPlus API screening for EVM addresses (async call)
        if recipientAddress.lowercased().hasPrefix("0x") && recipientAddress.count == 42 {
            if let goPlusResult = await manager.screenAddress(recipientAddress) {
                if goPlusResult.isBlacklisted {
                    scamRiskLevel = .high
                    scamReasons = goPlusResult.maliciousBehavior.isEmpty
                        ? ["Flagged as malicious by security screening"]
                        : goPlusResult.maliciousBehavior
                    showingScamBlockingModal = true
                    return
                }
            }
            // If GoPlus returns nil (network error), proceed with warning logged
        }
        
        // Address passed screening — continue to first-time / security check
        continueAfterScamCheck()
    }
    
    /// Continue the send flow after scam check passes or is acknowledged
    private func continueAfterScamCheck() {
        // ROADMAP-05 E5: First-time address warning
        if AddressIntelligenceManager.shared.isFirstTimeSend(to: recipientAddress) {
            showingFirstTimeWarning = true
            return
        }
        
        proceedToSecurityCheck()
    }
    
    /// Continue to security check after first-time warning (if applicable)
    private func proceedToSecurityCheck() {
        // Check if security checks are enabled (can be toggled in settings)
        let securityEnabled = UserDefaults.standard.bool(forKey: "security.threatProtection")
        
        // For mainnet transactions, always show security check
        // For testnet, only show if security is explicitly enabled
        if !selectedChain.isTestnet || securityEnabled {
            showingSecurityCheck = true
        } else {
            // Skip security check for testnet if not enabled
            showReviewScreen()
        }
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
        case .ethereumSepolia, .ethereumMainnet, .polygon, .bnb:
            let rate = Double(effectiveGasPrice)
            let limit = UInt64(gasLimit) ?? 21000
            let fee = (rate * Double(limit)) / 1_000_000_000
            let time = feeEstimator.getEthereumEstimate(for: selectedFeePriority)?.estimatedTime ?? "~2 min"
            return (fee, rate, "Gwei", time)
        case .solanaDevnet, .solanaMainnet:
            return (0.000005, 5000, "lamports", "~1 min")
        case .xrpTestnet, .xrpMainnet:
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
        
        #if DEBUG
        print("[SendView] Pre-signing transaction in background...")
        #endif
        
        Task.detached(priority: .userInitiated) {
            do {
                let signedHex: String
                
                switch await MainActor.run(body: { self.selectedChain }) {
                case .bitcoinTestnet:
                    let amountSats = await MainActor.run { self.safeAmountToSmallestUnit(self.amount, multiplier: Decimal(100_000_000)) }
                    let fee = await MainActor.run { self.effectiveBitcoinFeeRate }
                    let recipient = await MainActor.run { self.recipientAddress }
                    let wif = await MainActor.run { self.keys.bitcoinTestnet.privateWif }
                    
                    // Select UTXOs
                    let rustUTXOs = await MainActor.run {
                        let manager = UTXOCoinControlManager.shared
                        let targetAmount = amountSats + (fee * 200) + 1000
                        let selected = manager.selectUTXOs(for: targetAmount)
                        return selected.map { u in
                            RustUTXO(
                                txid: u.txid,
                                vout: UInt32(u.vout),
                                value: u.value,
                                status: RustUTXOStatus(
                                    confirmed: u.confirmations > 0,
                                    block_height: nil,
                                    block_hash: nil,
                                    block_time: nil
                                )
                            )
                        }
                    }
                    
                    // Always use SegWit signing (UTXOs are from SegWit address)
                    signedHex = try RustService.shared.signBitcoinThrowing(
                        recipient: recipient,
                        amountSats: amountSats,
                        feeRate: fee,
                        senderWIF: wif,
                        utxos: rustUTXOs
                    )
                    
                case .bitcoinMainnet:
                    let amountSats = await MainActor.run { self.safeAmountToSmallestUnit(self.amount, multiplier: Decimal(100_000_000)) }
                    let fee = await MainActor.run { self.effectiveBitcoinFeeRate }
                    let recipient = await MainActor.run { self.recipientAddress }
                    let wif = await MainActor.run { self.keys.bitcoin.privateWif }
                    
                    // Select UTXOs
                    let rustUTXOs = await MainActor.run {
                        let manager = UTXOCoinControlManager.shared
                        let targetAmount = amountSats + (fee * 200) + 1000
                        let selected = manager.selectUTXOs(for: targetAmount)
                        return selected.map { u in
                            RustUTXO(
                                txid: u.txid,
                                vout: UInt32(u.vout),
                                value: u.value,
                                status: RustUTXOStatus(
                                    confirmed: u.confirmations > 0,
                                    block_height: nil,
                                    block_hash: nil,
                                    block_time: nil
                                )
                            )
                        }
                    }
                    
                    // Always use SegWit signing (UTXOs are from SegWit address)
                    signedHex = try RustService.shared.signBitcoinThrowing(
                        recipient: recipient,
                        amountSats: amountSats,
                        feeRate: fee,
                        senderWIF: wif,
                        utxos: rustUTXOs
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
                    #if DEBUG
                    print("[SendView] Pre-signing complete! Tx ready for instant broadcast.")
                    #endif
                }
                
            } catch {
                await MainActor.run {
                    self.preSignError = error.localizedDescription
                    self.preSigningInProgress = false
                    #if DEBUG
                    print("[SendView] Pre-signing failed: \(error)")
                    #endif
                }
            }
        }
    }
    
    // MARK: - Send Transaction
    
    @State private var showBackupRequiredSheet = false
    
    private func sendTransaction() {
        #if DEBUG
        print("[SendView] sendTransaction() called")
        #endif
        #if DEBUG
        print("[SendView] Sending \(amount) \(selectedChain.displayName) to \(recipientAddress)")
        #endif
        
        // ROADMAP-02: Check backup verification before large sends
        if !BackupVerificationManager.shared.isVerified {
            // Estimate USD value (simplified - in production use real price feed)
            let estimatedUSD = estimateUSDValue()
            if estimatedUSD > BackupVerificationManager.shared.unverifiedSendLimitUSD {
                showBackupRequiredSheet = true
                return
            }
        }
        
        // Check biometric authentication if enabled
        if BiometricAuthHelper.shouldRequireBiometric(settingEnabled: biometricForSends) {
            Task { @MainActor in
                let result = await BiometricAuthHelper.authenticate(
                    reason: "Authenticate to send \(selectedChain.displayName)"
                )
                switch result {
                case .success:
                    await performSendTransaction()
                case .cancelled:
                    #if DEBUG
                    print("[SendView] Biometric cancelled by user")
                    #endif
                    return
                case .failed(let message):
                    errorMessage = "Authentication failed: \(message)"
                    return
                case .notAvailable:
                    // Biometric not available, proceed anyway
                    await performSendTransaction()
                }
            }
        } else {
            Task { @MainActor in
                await performSendTransaction()
            }
        }
    }
    
    @MainActor
    private func performSendTransaction() async {
        isLoading = true
        errorMessage = nil
        successTxId = nil
        
        do {
            #if DEBUG
            print("[SendView] Step 1: Using keys passed from parent view")
            #endif
            
            // Sign & Broadcast based on chain
            var txId: String
            var capturedFeeRate: Int? = nil
            var capturedNonce: Int? = nil
            
            switch selectedChain {
            case .bitcoinTestnet:
                (txId, capturedFeeRate) = try await sendBitcoin(isTestnet: true)
            case .bitcoinMainnet:
                (txId, capturedFeeRate) = try await sendBitcoin(isTestnet: false)
            case .litecoin:
                (txId, capturedFeeRate) = try await sendLitecoin()
            case .ethereumSepolia:
                (txId, capturedFeeRate, capturedNonce) = try await sendEthereum(chainId: 11155111, isTestnet: true)
            case .ethereumMainnet:
                (txId, capturedFeeRate, capturedNonce) = try await sendEthereum(chainId: 1, isTestnet: false)
            case .polygon:
                (txId, capturedFeeRate, capturedNonce) = try await sendEthereum(chainId: 137, isTestnet: false)
            case .bnb:
                (txId, capturedFeeRate, capturedNonce) = try await sendEthereum(chainId: 56, isTestnet: false)
            case .solanaDevnet:
                txId = try await sendSolana(isDevnet: true)
            case .solanaMainnet:
                txId = try await sendSolana(isDevnet: false)
            case .xrpTestnet:
                txId = try await sendXRP(isTestnet: true)
            case .xrpMainnet:
                txId = try await sendXRP(isTestnet: false)
            case .monero:
                throw NSError(domain: "App", code: 2, userInfo: [NSLocalizedDescriptionKey: "Monero sending not yet supported"])
            }
            
            // Success! Show confirmation sheet
            self.isLoading = false
                
            #if DEBUG
            print("[SendView] SUCCESS! Transaction completed with TxID: \(txId)")
            #endif
            
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
            
            // ROADMAP-05 E5: Record successful send for address history
            AddressIntelligenceManager.shared.recordSend(to: recipientAddress)
            
            #if DEBUG
            print("[SendView] Setting showingSuccessSheet = true")
            #endif
            
            // Show success sheet with a small delay to ensure state is set
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.showingSuccessSheet = true
                #if DEBUG
                print("[SendView] showingSuccessSheet is now: \(self.showingSuccessSheet)")
                #endif
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
            
        } catch let error as RustServiceError {
            #if DEBUG
            print("[SendView] RUST SERVICE ERROR: \(error)")
            #endif
            let errorDesc: String
            switch error {
            case .ffiError(let code, let message):
                // Parse common error patterns for more user-friendly messages
                errorDesc = parseTransactionError(code: -1, output: "[\(code)] \(message)")
            case .invalidResponse:
                errorDesc = "Unable to process the signed transaction. Please try again."
            case .invalidInput:
                errorDesc = "Invalid transaction details. Please check the recipient address and amount."
            }
            self.errorMessage = errorDesc
            self.isLoading = false
            
        } catch let error as BroadcastError {
            #if DEBUG
            print("[SendView] BROADCAST ERROR: \(error)")
            #endif
            let errorDesc: String
            switch error {
            case .invalidURL:
                errorDesc = "Unable to connect to the blockchain network. Please check your internet connection."
            case .invalidResponse:
                errorDesc = "The network returned an unexpected response. Please try again."
            case .broadcastFailed(let message):
                errorDesc = parseBroadcastError(message)
            case .allEndpointsFailed:
                errorDesc = "Unable to reach any blockchain nodes. Please check your connection and try again."
            case .unsupportedChain:
                errorDesc = "This blockchain is not yet supported for sending transactions."
            case .propagationPending:
                errorDesc = "Your transaction was accepted but is still propagating across nodes. Please wait a moment and refresh — it should appear shortly."
            }
            self.errorMessage = errorDesc
            self.isLoading = false
            
        } catch {
            #if DEBUG
            print("[SendView] ERROR: \(error)")
            #endif
            #if DEBUG
            print("[SendView] ERROR localized: \(error.localizedDescription)")
            #endif
            // Provide more user-friendly generic errors
            self.errorMessage = parseGenericError(error)
            self.isLoading = false
        }
    }
    
    // MARK: - Error Parsing Helpers
    
    /// Parse Rust execution errors into user-friendly messages
    private func parseTransactionError(code: Int, output: String) -> String {
        let lowercaseOutput = output.lowercased()
        
        // Insufficient funds
        if lowercaseOutput.contains("insufficient") || lowercaseOutput.contains("not enough") {
            return "Insufficient funds. Please check your balance and try a smaller amount."
        }
        
        // Invalid address
        if lowercaseOutput.contains("invalid address") || lowercaseOutput.contains("bad address") {
            return "The recipient address is invalid. Please double-check and try again."
        }
        
        // Nonce errors (Ethereum)
        if lowercaseOutput.contains("nonce") {
            if lowercaseOutput.contains("too low") {
                return "Transaction nonce too low. A previous transaction may be pending. Please wait and try again."
            } else if lowercaseOutput.contains("too high") {
                return "Transaction nonce too high. Please check for pending transactions."
            }
            return "Nonce error. Please refresh and try again."
        }
        
        // Gas errors
        if lowercaseOutput.contains("gas") {
            if lowercaseOutput.contains("limit") {
                return "Gas limit too low for this transaction. Please increase the gas limit."
            } else if lowercaseOutput.contains("price") {
                return "Gas price may be too low. Network congestion is high—try increasing the gas price."
            }
            return "Gas estimation failed. Please try again with adjusted settings."
        }
        
        // UTXO errors (Bitcoin/Litecoin)
        if lowercaseOutput.contains("utxo") || lowercaseOutput.contains("input") {
            return "No spendable funds available. Your coins may still be confirming from a previous transaction."
        }
        
        // Signature errors
        if lowercaseOutput.contains("signature") || lowercaseOutput.contains("sign") {
            return "Transaction signing failed. Please try again."
        }
        
        // Network/connection errors
        if lowercaseOutput.contains("timeout") || lowercaseOutput.contains("connection") {
            return "Network connection issue. Please check your internet and try again."
        }
        
        // Default: show truncated technical message
        let truncatedOutput = output.count > 150 ? String(output.prefix(150)) + "..." : output
        return "Transaction failed (code \(code)): \(truncatedOutput)"
    }
    
    /// Parse broadcast errors into user-friendly messages
    private func parseBroadcastError(_ message: String) -> String {
        let lowercaseMessage = message.lowercased()
        
        // Already broadcasted
        if lowercaseMessage.contains("already known") || lowercaseMessage.contains("already in mempool") {
            return "This transaction has already been submitted to the network."
        }
        
        // Insufficient fee
        if lowercaseMessage.contains("fee") && (lowercaseMessage.contains("low") || lowercaseMessage.contains("insufficient")) {
            return "Transaction fee too low. The network is congested—please increase the fee."
        }
        
        // Mempool full
        if lowercaseMessage.contains("mempool") && lowercaseMessage.contains("full") {
            return "Network is congested. Please try again with a higher fee."
        }
        
        // Double spend
        if lowercaseMessage.contains("double spend") || lowercaseMessage.contains("conflict") {
            return "Transaction conflicts with a pending transaction. Please wait for confirmations."
        }
        
        // Rate limiting
        if lowercaseMessage.contains("rate limit") || lowercaseMessage.contains("too many requests") {
            return "Too many requests. Please wait a moment and try again."
        }
        
        // Default
        return "Broadcast failed: \(message)"
    }
    
    /// Parse generic errors into user-friendly messages
    private func parseGenericError(_ error: Error) -> String {
        // Use centralized user-friendly error conversion
        return error.userFriendlyMessage
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
        case .ethereumSepolia, .ethereumMainnet, .polygon, .bnb:
            // Gas price in Gwei, typical 21000 gas for transfer
            let feeGwei = Double(rate) * 21000.0
            let feeETH = feeGwei / 1_000_000_000.0
            let symbol = selectedChain == .polygon ? "MATIC" : selectedChain == .bnb ? "BNB" : "ETH"
            return (String(format: "%.6f \(symbol)", feeETH), "Gwei")
        case .solanaDevnet, .solanaMainnet:
            return ("0.000005 SOL", "lamports")
        case .xrpTestnet, .xrpMainnet:
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
        case .ethereumSepolia, .ethereumMainnet, .polygon, .bnb: return keys.ethereum.address
        case .solanaDevnet, .solanaMainnet: return keys.solana.publicKeyBase58
        case .xrpTestnet, .xrpMainnet: return keys.xrp.classicAddress
        case .monero: return keys.monero.address
        }
    }
    
    // MARK: - Backup Verification (ROADMAP-02)
    
    /// Estimate the USD value of the current send amount
    /// In production, this should use real-time price feeds
    private func estimateUSDValue() -> Double {
        guard let amountValue = Double(amount), amountValue > 0 else { return 0 }
        
        // Approximate USD prices (would come from price service in production)
        let pricePerUnit: Double
        switch selectedChain {
        case .bitcoinTestnet:
            pricePerUnit = 0 // Testnet has no value
        case .bitcoinMainnet:
            pricePerUnit = 95000 // ~$95k per BTC
        case .litecoin:
            pricePerUnit = 85 // ~$85 per LTC
        case .ethereumSepolia:
            pricePerUnit = 0 // Testnet has no value
        case .ethereumMainnet:
            pricePerUnit = 3200 // ~$3.2k per ETH
        case .polygon:
            pricePerUnit = 0.45 // ~$0.45 per MATIC
        case .bnb:
            pricePerUnit = 620 // ~$620 per BNB
        case .solanaDevnet:
            pricePerUnit = 0 // Testnet has no value
        case .solanaMainnet:
            pricePerUnit = 180 // ~$180 per SOL
        case .xrpTestnet:
            pricePerUnit = 0 // Testnet has no value
        case .xrpMainnet:
            pricePerUnit = 2.50 // ~$2.50 per XRP
        case .monero:
            pricePerUnit = 200 // ~$200 per XMR
        }
        
        return amountValue * pricePerUnit
    }

    // MARK: - Loading Overlay
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                
                Text("Processing...")
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(HawalaTheme.Colors.backgroundSecondary)
            .cornerRadius(16)
        }
    }

    // MARK: - Chain-Specific Send Methods

    private func sendBitcoin(isTestnet: Bool) async throws -> (String, Int?) {
        let amountSats = safeAmountToSmallestUnit(amount, multiplier: Decimal(100_000_000))
        let fee = UInt64(effectiveBitcoinFeeRate)
        let recipient = recipientAddress
        let wif = isTestnet ? keys.bitcoinTestnet.privateWif : keys.bitcoin.privateWif
        
        // Select UTXOs from SegWit address (current implementation)
        let manager = UTXOCoinControlManager.shared
        let targetAmount = amountSats + (fee * 200) + 1000
        let selected = manager.selectUTXOs(for: targetAmount)
        
        let rustUTXOs = selected.map { u in
            RustUTXO(
                txid: u.txid,
                vout: UInt32(u.vout),
                value: u.value,
                status: RustUTXOStatus(
                    confirmed: u.confirmations > 0,
                    block_height: nil,
                    block_hash: nil,
                    block_time: nil
                )
            )
        }
        
        // NOTE: Taproot signing requires Taproot UTXOs (bc1p/tb1p addresses)
        // Current wallet uses SegWit UTXOs, so we always use SegWit signing
        // Taproot toggle will be useful once user has funded their Taproot address
        // For now, always use SegWit to ensure transactions work
        #if DEBUG
        print("[SendView] Using standard SegWit (P2WPKH) signing")
        #endif
        let signedHex = try RustService.shared.signBitcoinThrowing(
            recipient: recipient,
            amountSats: amountSats,
            feeRate: fee,
            senderWIF: wif,
            utxos: rustUTXOs.isEmpty ? nil : rustUTXOs
        )
        
        let txId = try await TransactionBroadcaster.shared.broadcastBitcoin(rawTxHex: signedHex, isTestnet: isTestnet)
        return (txId, Int(fee))
    }

    private func sendLitecoin() async throws -> (String, Int?) {
        let amountLits = safeAmountToSmallestUnit(amount, multiplier: Decimal(100_000_000))
        let fee = UInt64(effectiveBitcoinFeeRate)
        let recipient = recipientAddress
        let wif = keys.litecoin.privateWif
        let senderAddress = keys.litecoin.address
        
        // Select UTXOs
        let manager = UTXOCoinControlManager.shared
        let targetAmount = amountLits + (fee * 200) + 1000
        let selected = manager.selectUTXOs(for: targetAmount)
        
        let rustUTXOs = selected.map { u in
            RustUTXO(
                txid: u.txid,
                vout: UInt32(u.vout),
                value: u.value,
                status: RustUTXOStatus(
                    confirmed: u.confirmations > 0,
                    block_height: nil,
                    block_hash: nil,
                    block_time: nil
                )
            )
        }
        
        let signedHex = try RustService.shared.signLitecoinThrowing(
            recipient: recipient,
            amountLits: amountLits,
            feeRate: fee,
            senderWIF: wif,
            senderAddress: senderAddress,
            utxos: rustUTXOs.isEmpty ? nil : rustUTXOs
        )
        
        let txId = try await TransactionBroadcaster.shared.broadcastLitecoin(rawTxHex: signedHex)
        return (txId, Int(fee))
    }

    private func sendEthereum(chainId: UInt64, isTestnet: Bool) async throws -> (String, Int?, Int?) {
        // IMPORTANT: Avoid Double -> Int conversion for Wei.
        // Double loses precision for 1e18 scaling and Int can overflow on larger sends.
        // Use Decimal/NSDecimalNumber so we always sign the exact intended Wei amount.
        let amountWei: String = {
            let cleaned = amount.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let decimalAmount = Decimal(string: cleaned), decimalAmount > 0 else {
                return "0"
            }

            let weiPerETH = NSDecimalNumber(mantissa: 1_000_000_000_000_000_000, exponent: 0, isNegative: false)
            let eth = NSDecimalNumber(decimal: decimalAmount)
            // Round down to whole wei.
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
        let recipient = recipientAddress
        
        // Use the correct keys based on network (testnet vs mainnet)
        // For Sepolia (testnet), use ethereumSepolia keys
        // For mainnet and other EVM chains, use ethereum keys
        let senderKey: String
        let senderAddress: String
        if isTestnet {
            senderKey = keys.ethereumSepolia.privateHex
            senderAddress = keys.ethereumSepolia.address
        } else {
            senderKey = keys.ethereum.privateHex
            senderAddress = keys.ethereum.address
        }
        
        #if DEBUG
        print("[ETH TX] ========== ETHEREUM TRANSACTION DEBUG ==========")
        #endif
        #if DEBUG
        print("[ETH TX] Chain ID: \(chainId) (isTestnet: \(isTestnet))")
        #endif
        #if DEBUG
        print("[ETH TX] Sender: \(senderAddress)")
        #endif
        #if DEBUG
        print("[ETH TX] Recipient: \(recipient)")
        #endif
        #if DEBUG
        print("[ETH TX] Amount (Wei): \(amountWei)")
        #endif
        #if DEBUG
        print("[ETH TX] Sender Key (first 10): \(senderKey.prefix(10))...")
        #endif
        
        // Auto-fetch nonce from network (fallback to user input if provided)
        let nonceVal: UInt64
        if nonce.isEmpty {
            // Use our nonce manager so we don't accidentally reuse a nonce locally.
            // This also gives us a place to implement replacement logic reliably.
            let chainKey = (chainId == 11155111) ? "ethereum-sepolia" : (chainId == 1 ? "ethereum" : String(chainId))
            nonceVal = try await EVMNonceManager.shared.getNextNonce(for: senderAddress, chainId: chainKey)
            EVMNonceManager.shared.reserveNonce(nonceVal, chainId: chainKey)
            #if DEBUG
            print("[ETH TX] Fetched + reserved nonce: \(nonceVal) (chainKey=\(chainKey))")
            #endif
        } else {
            nonceVal = UInt64(nonce) ?? 0
            #if DEBUG
            print("[ETH TX] Using manual nonce: \(nonceVal)")
            #endif
        }
        
        let gasLimitVal = UInt64(gasLimit) ?? 21000
        #if DEBUG
        print("[ETH TX] Gas Limit: \(gasLimitVal)")
        #endif
        
        // IMPORTANT: Convert Gwei to Wei for Rust backend
        // UI displays/stores gas price in Gwei, but Rust expects Wei
        // 1 Gwei = 1,000,000,000 Wei
        let gasPriceWei: String?
        if !gasPrice.isEmpty, let gasPriceGwei = Double(gasPrice) {
            let weiValue = safeGweiToWei(gasPriceGwei)
            gasPriceWei = String(weiValue)
            #if DEBUG
            print("[ETH TX] Gas price: \(gasPrice) Gwei → \(weiValue) Wei")
            #endif
        } else {
            gasPriceWei = nil
            #if DEBUG
            print("[ETH TX] WARNING: No gas price set!")
            #endif
        }
        
        // For post-London chains (Sepolia, Ethereum mainnet), ensure EIP-1559 params are set
        // This is a fallback in case the async fetchGasPriceForChain didn't complete
        var effectiveMaxFeePerGas = maxFeePerGas
        var effectiveMaxPriorityFeePerGas = maxPriorityFeePerGas
        
        if chainId == 11155111 || chainId == 1 {  // Sepolia or Ethereum mainnet
            if effectiveMaxFeePerGas.isEmpty {
                // Use gasPrice as maxFeePerGas fallback
                effectiveMaxFeePerGas = gasPrice.isEmpty ? "50" : gasPrice
                #if DEBUG
                print("[ETH TX] ⚠️ maxFeePerGas was empty, using fallback: \(effectiveMaxFeePerGas) Gwei")
                #endif
            }
            if effectiveMaxPriorityFeePerGas.isEmpty {
                // Use 50% of maxFee as priority fee for Sepolia, 10% for mainnet
                if let maxFee = Double(effectiveMaxFeePerGas) {
                    let priorityMultiplier = chainId == 11155111 ? 0.5 : 0.1
                    let priorityFee = max(2.5, maxFee * priorityMultiplier)
                    effectiveMaxPriorityFeePerGas = String(format: "%.0f", ceil(priorityFee))
                } else {
                    effectiveMaxPriorityFeePerGas = chainId == 11155111 ? "25" : "3"
                }
                #if DEBUG
                print("[ETH TX] ⚠️ maxPriorityFeePerGas was empty, using fallback: \(effectiveMaxPriorityFeePerGas) Gwei")
                #endif
            }
        }
        
        // Also convert maxFeePerGas and maxPriorityFeePerGas from Gwei to Wei
        let maxFeeWei: String?
        if !effectiveMaxFeePerGas.isEmpty, let maxFeeGwei = Double(effectiveMaxFeePerGas) {
            maxFeeWei = String(safeGweiToWei(maxFeeGwei))
            #if DEBUG
            print("[ETH TX] Max Fee: \(effectiveMaxFeePerGas) Gwei → \(maxFeeWei!) Wei")
            #endif
        } else {
            maxFeeWei = nil
            #if DEBUG
            print("[ETH TX] Max Fee: NOT SET")
            #endif
        }
        
        let maxPriorityWei: String?
        if !effectiveMaxPriorityFeePerGas.isEmpty, let maxPriorityGwei = Double(effectiveMaxPriorityFeePerGas) {
            maxPriorityWei = String(safeGweiToWei(maxPriorityGwei))
            #if DEBUG
            print("[ETH TX] Max Priority: \(effectiveMaxPriorityFeePerGas) Gwei → \(maxPriorityWei!) Wei")
            #endif
        } else {
            maxPriorityWei = nil
            #if DEBUG
            print("[ETH TX] Max Priority: NOT SET")
            #endif
        }
        
        // Log transaction type
        if maxFeeWei != nil {
            #if DEBUG
            print("[ETH TX] *** USING EIP-1559 TRANSACTION ***")
            #endif
        } else {
            #if DEBUG
            print("[ETH TX] *** USING LEGACY TRANSACTION (may be deprioritized on post-London chains!) ***")
            #endif
        }
        
        let chainKeyForNonce = (chainId == 11155111) ? "ethereum-sepolia" : (chainId == 1 ? "ethereum" : String(chainId))
        do {
            #if DEBUG
            print("[ETH TX] Calling Rust FFI to sign transaction...")
            #endif
            let signedHex = try RustService.shared.signEthereumThrowing(
                recipient: recipient,
                amountWei: amountWei,
                chainId: chainId,
                senderKey: senderKey,
                nonce: nonceVal,
                gasLimit: gasLimitVal,
                gasPrice: gasPriceWei,
                maxFeePerGas: maxFeeWei,
                maxPriorityFeePerGas: maxPriorityWei
            )
            #if DEBUG
            print("[ETH TX] Signed TX hex (first 100 chars): \(signedHex.prefix(100))...")
            #endif
            #if DEBUG
            print("[ETH TX] Signed TX length: \(signedHex.count) chars")
            #endif

            #if DEBUG
            print("[ETH TX] Broadcasting transaction...")
            #endif
            let txId: String
            do {
                if chainId == 56 {
                    txId = try await TransactionBroadcaster.shared.broadcastBNB(rawTxHex: signedHex)
                } else if chainId == 1 || chainId == 11155111 {
                    txId = try await TransactionBroadcaster.shared.broadcastEthereum(rawTxHex: signedHex, isTestnet: isTestnet)
                } else {
                    txId = try await TransactionBroadcaster.shared.broadcastEthereumToChain(rawTxHex: signedHex, chainId: Int(chainId))
                }
            } catch let error as BroadcastError {
                switch error {
                case .propagationPending(let message):
                    // We don't have a tx hash from this code path when the propagation check fails.
                    // But in practice, the network often just needs a moment; treat as a user-facing
                    // "still propagating" state (same UX as pending).
                    #if DEBUG
                    print("[ETH TX] \(message)")
                    #endif
                    throw BroadcastError.broadcastFailed("Transaction broadcast is still propagating across nodes. Please wait a moment and refresh — it should appear shortly.")
                default:
                    throw error
                }
            }
        
        #if DEBUG
        print("[ETH TX] ========== TRANSACTION COMPLETE ==========")
        #endif
        #if DEBUG
        print("[ETH TX] TxID: \(txId)")
        #endif
        
    // Save the signed raw transaction for potential rebroadcast/debugging.
        // This is especially useful on testnets where some public nodes may accept
        // a tx but it can still fail to propagate widely.
        if let data = signedHex.data(using: .utf8) {
            TransactionBroadcaster.shared.cacheLastSignedRawTx(txid: txId, rawTx: data)

            // Persist to the transaction database so it survives app restarts.
            // Pro behavior: create the history record immediately, then attach raw tx.
            Task { @MainActor in
                do {
                    let walletId = try await TransactionStore.shared.ensureActiveWalletRecord()

                    let chainKey: String
                    if chainId == 1 {
                        chainKey = "ethereum"
                    } else if chainId == 11155111 {
                        chainKey = "ethereum-sepolia"
                    } else if chainId == 56 {
                        chainKey = "bnb"
                    } else {
                        chainKey = "evm-\(chainId)"
                    }

                    // Create/update the tx record.
                    let record = TransactionRecord.from(
                        walletId: walletId,
                        chainId: chainKey,
                        txHash: txId,
                        type: .send,
                        fromAddress: senderAddress,
                        toAddress: recipient,
                        amount: amountWei,
                        fee: nil,
                        asset: chainKey == "bnb" ? "BNB" : "ETH",
                        timestamp: Date(),
                        status: .pending
                    )
                    try await TransactionStore.shared.save(record)
                    try await TransactionStore.shared.attachRawData(txHash: txId, chainId: chainKey, rawData: data)
                } catch {
                    // Don't block sending if persistence fails; just log.
                    #if DEBUG
                    print("[ETH TX] ⚠️ Failed to persist tx record/raw for \(txId.prefix(12))…: \(error)")
                    #endif
                }
            }
        }

            return (txId, Int(gasPrice) ?? 0, Int(nonceVal))
        } catch {
            // If we reserved a nonce above, release it so future sends aren't forced to skip.
            if nonce.isEmpty {
                EVMNonceManager.shared.releaseNonce(nonceVal, chainId: chainKeyForNonce)
            }
            throw error
        }
    }

    private func sendSolana(isDevnet: Bool) async throws -> String {
        let amountSol = Double(amount) ?? 0
        let recipient = recipientAddress
        let senderBase58 = keys.solana.privateKeyBase58
        
        // Fetch recent blockhash from Solana network
        let recentBlockhash = try await TransactionBroadcaster.shared.getSolanaBlockhash(isDevnet: isDevnet)
        
        let signedBase64 = try RustService.shared.signSolanaThrowing(
            recipient: recipient,
            amountSol: amountSol,
            recentBlockhash: recentBlockhash,
            senderBase58: senderBase58
        )
        
        return try await TransactionBroadcaster.shared.broadcastSolana(rawTxBase64: signedBase64, isDevnet: isDevnet)
    }

    private func sendXRP(isTestnet: Bool) async throws -> String {
        let amountDrops = safeAmountToSmallestUnit(amount, multiplier: Decimal(1_000_000))
        let recipient = recipientAddress
        let senderSeed = keys.xrp.privateHex
        let senderAddress = keys.xrp.classicAddress
        let tag = destinationTag.isEmpty ? nil : UInt32(destinationTag)
        
        // Fetch sequence number from XRP Ledger
        let sequenceVal = try await TransactionBroadcaster.shared.getXRPSequence(address: senderAddress, isTestnet: isTestnet)
        
        let signedHex = try RustService.shared.signXRPThrowing(
            recipient: recipient,
            amountDrops: amountDrops,
            senderSeedHex: senderSeed,
            sequence: sequenceVal,
            destinationTag: tag
        )
        
        return try await TransactionBroadcaster.shared.broadcastXRP(rawTxHex: signedHex, isTestnet: isTestnet)
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
        case .ethereumSepolia: urlString = "https://sepolia.etherscan.io/tx/\(txId)"
        case .ethereumMainnet: urlString = "https://etherscan.io/tx/\(txId)"
        case .polygon: urlString = "https://polygonscan.com/tx/\(txId)"
        case .bnb: urlString = "https://bscscan.com/tx/\(txId)"
        case .solanaDevnet: urlString = "https://explorer.solana.com/tx/\(txId)?cluster=devnet"
        case .solanaMainnet: urlString = "https://explorer.solana.com/tx/\(txId)"
        case .xrpTestnet: urlString = "https://testnet.xrpl.org/transactions/\(txId)"
        case .xrpMainnet: urlString = "https://xrpscan.com/tx/\(txId)"
        case .monero: urlString = "https://stagenet.xmrchain.net/search?value=\(txId)"
        }
        return URL(string: urlString)
    }
    
    var explorerName: String {
        switch chain {
        case .bitcoinTestnet, .bitcoinMainnet: return "Mempool.space"
        case .litecoin: return "LitecoinSpace"
        case .ethereumSepolia, .ethereumMainnet: return "Etherscan"
        case .polygon: return "PolygonScan"
        case .bnb: return "BscScan"
        case .solanaDevnet, .solanaMainnet: return "Solana Explorer"
        case .xrpTestnet, .xrpMainnet: return "XRPL Explorer"
        case .monero: return "XMRChain"
        }
    }
    
    var currencySymbol: String {
        switch chain {
        case .bitcoinTestnet, .bitcoinMainnet: return "BTC"
        case .litecoin: return "LTC"
        case .ethereumSepolia, .ethereumMainnet: return "ETH"
        case .polygon: return "MATIC"
        case .bnb: return "BNB"
        case .solanaDevnet, .solanaMainnet: return "SOL"
        case .xrpTestnet, .xrpMainnet: return "XRP"
        case .monero: return "XMR"
        }
    }
    
    var networkName: String {
        switch chain {
        case .bitcoinTestnet: return "Bitcoin Testnet"
        case .bitcoinMainnet: return "Bitcoin Mainnet"
        case .litecoin: return "Litecoin Mainnet"
        case .ethereumSepolia: return "Ethereum Sepolia"
        case .ethereumMainnet: return "Ethereum Mainnet"
        case .polygon: return "Polygon Mainnet"
        case .bnb: return "BNB Smart Chain"
        case .solanaDevnet: return "Solana Devnet"
        case .solanaMainnet: return "Solana Mainnet"
        case .xrpTestnet: return "XRP Testnet"
        case .xrpMainnet: return "XRP Mainnet"
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
        case .ethereumSepolia, .ethereumMainnet:
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
        ClipboardHelper.copySensitive(details.txId, timeout: 60)
        
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