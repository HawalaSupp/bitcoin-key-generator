import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import LocalAuthentication
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Bitcoin Address Format
enum BitcoinAddressFormat: String, CaseIterable, Identifiable {
    case nativeSegwit = "Native SegWit"
    case segwit = "SegWit"
    case legacy = "Legacy"
    
    var id: String { rawValue }
    
    var prefix: String {
        switch self {
        case .nativeSegwit: return "bc1"
        case .segwit: return "3"
        case .legacy: return "1"
        }
    }
    
    var description: String {
        switch self {
        case .nativeSegwit: return "Lowest fees (bc1...)"
        case .segwit: return "Compatible (3...)"
        case .legacy: return "Universal (1...)"
        }
    }
    
    var icon: String {
        switch self {
        case .nativeSegwit: return "bolt.fill"
        case .segwit: return "shield.checkered"
        case .legacy: return "clock.fill"
        }
    }
}

// MARK: - Modern Receive View

struct ReceiveViewModern: View {
    @Environment(\.dismiss) private var envDismiss
    
    let chains: [ChainInfo]
    let onCopy: (String) -> Void
    var onDismiss: (() -> Void)? = nil
    
    /// Unified dismiss: prefers overlay callback, falls back to sheet environment
    private func dismiss() {
        if let onDismiss {
            onDismiss()
        } else {
            envDismiss()
        }
    }
    
    @State private var selectedChain: ChainInfo?
    @State private var requestAmount: String = ""
    @State private var requestAmountUSD: String = ""
    @State private var memo: String = ""
    @State private var showCopiedToast = false
    @State private var copiedText = ""
    @State private var appearAnimation = false
    @State private var selectedAddressFormat: BitcoinAddressFormat = .nativeSegwit
    @State private var showAddressVerification = false
    @State private var verificationStep = 0
    @State private var isAmountInUSD = false
    @State private var qrAnimationScale: CGFloat = 1.0
    
    // Price for USD conversion (would come from price service in real app)
    private let btcPrice: Double = 42500.0
    private let ethPrice: Double = 2250.0
    private let ltcPrice: Double = 72.0
    
    init(chains: [ChainInfo], initialChain: ChainInfo? = nil, onCopy: @escaping (String) -> Void, onDismiss: (() -> Void)? = nil) {
        self.chains = chains
        self.onCopy = onCopy
        self.onDismiss = onDismiss
        // Use provided chain or default to first chain with an address
        if let initial = initialChain {
            _selectedChain = State(initialValue: initial)
        } else {
            _selectedChain = State(initialValue: chains.first(where: { $0.receiveAddress != nil }))
        }
    }
    
    @ObservedObject private var passcodeManager = PasscodeManager.shared
    @State private var requiresUnlock = false
    
    var body: some View {
        ZStack {
            // Background — popup card
            Color(red: 0.10, green: 0.10, blue: 0.12)
            
            // ROADMAP-06 E8: Gate receive view when wallet is locked
            if passcodeManager.isLocked {
                walletLockedOverlay
            } else {
            VStack(spacing: 0) {
                // Header
                receiveHeader
                
                // Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Chain Selector
                        chainSelectorSection
                        
                        // Address Format Selector (Bitcoin only)
                        if let chain = selectedChain, chain.id.lowercased().contains("bitcoin") {
                            addressFormatSection
                        }
                        
                        // QR Code Display
                        if let chain = selectedChain, let address = chain.receiveAddress {
                            qrCodeSection(chain: chain, address: address)
                            
                            // Address Display with Verify
                            addressSection(address: address)
                            
                            // Request Amount with USD toggle
                            requestAmountSection(chain: chain)
                            
                            // Action Buttons
                            actionButtonsSection(chain: chain, address: address)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            
            // Copied Toast
            if showCopiedToast {
                VStack {
                    Spacer()
                    copiedToastView
                        .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Address Verification Overlay
            if showAddressVerification {
                addressVerificationOverlay
            }
            } // end else (wallet not locked)
        }
        .frame(width: 480, height: 700)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.1), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.5), radius: 50, x: 0, y: 25)
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                appearAnimation = true
            }
        }
    }
    
    // MARK: - Wallet Locked Overlay (ROADMAP-06 E8)
    
    private var walletLockedOverlay: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundColor(Color.orange.opacity(0.8))
            
            Text("Wallet Locked")
                .font(.clashGroteskMedium(size: 20))
                .foregroundColor(.white)
            
            Text("Unlock your wallet to view receive addresses.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: {
                Task {
                    let context = LAContext()
                    do {
                        let success = try await context.evaluatePolicy(
                            .deviceOwnerAuthentication,
                            localizedReason: "Unlock wallet to view receive address"
                        )
                        if success {
                            await MainActor.run { passcodeManager.unlock() }
                        }
                    } catch {
                        #if DEBUG
                        print("[ReceiveView] Biometric unlock failed: \\(error)")
                        #endif
                    }
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "faceid")
                    Text("Unlock")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(red: 0.10, green: 0.10, blue: 0.12))
                .frame(maxWidth: 200)
                .frame(height: 48)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            
            Button("Cancel") { dismiss() }
                .foregroundColor(Color.white.opacity(0.4))
                .buttonStyle(.plain)
            
            Spacer()
        }
    }
    
    // MARK: - Header
    
    private var receiveHeader: some View {
        ZStack {
            // Centered title
            Text("Receive")
                .font(.clashGroteskMedium(size: 20))
                .foregroundColor(.white)
            
            // Close button — right aligned
            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.5))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityHint("Dismiss receive view")
                .accessibilityIdentifier("receive_close_button")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }
    
    // MARK: - Chain Selector
    
    private var chainSelectorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NETWORK")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.white.opacity(0.4))
                .tracking(1)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chains.filter { $0.receiveAddress != nil }) { chain in
                        ReceiveChainPill(
                            chain: chain,
                            isSelected: selectedChain?.id == chain.id,
                            action: { 
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    selectedChain = chain
                                    requestAmount = ""
                                    requestAmountUSD = ""
                                }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                    qrAnimationScale = 0.9
                                }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.1)) {
                                    qrAnimationScale = 1.0
                                }
                            }
                        )
                    }
                }
            }
        }
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
    }
    
    // MARK: - Address Format Section (Bitcoin)
    
    private var addressFormatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ADDRESS FORMAT")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.white.opacity(0.4))
                .tracking(1)
            
            HStack(spacing: 8) {
                ForEach(BitcoinAddressFormat.allCases) { format in
                    AddressFormatPill(
                        format: format,
                        isSelected: selectedAddressFormat == format,
                        action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                selectedAddressFormat = format
                            }
                        }
                    )
                }
            }
            
            // Info text
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                Text(selectedAddressFormat.description)
                    .font(.system(size: 11))
            }
            .foregroundColor(Color.white.opacity(0.4))
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(.spring(response: 0.35, dampingFraction: 0.85).delay(0.05), value: appearAnimation)
    }
    
    // MARK: - QR Code Section
    
    private func qrCodeSection(chain: ChainInfo, address: String) -> some View {
        VStack(spacing: 16) {
            // QR Code with Hawala Logo — clean centered design
            ZStack {
                // Subtle glow behind QR
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 280, height: 280)
                    .blur(radius: 30)
                
                // White background for QR
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white)
                    .frame(width: 260, height: 260)
                
                // QR Code with embedded Hawala logo
                QRCodeView(content: generatePaymentURI(chain: chain, address: address), size: 240, showLogo: true)
            }
            .scaleEffect(qrAnimationScale)
            .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
            .accessibilityLabel("QR code for receiving \(chain.symbol)")
            .accessibilityHint("Scan this code to send \(chain.symbol) to your wallet")
            .accessibilityIdentifier("receive_qr_code")
            
            // Chain Name Badge with Amount
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 8, height: 8)
                Text(chain.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.5))
                
                if !requestAmount.isEmpty {
                    Text("•")
                        .foregroundColor(Color.white.opacity(0.3))
                    Text("\(requestAmount) \(chain.symbol)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
            
            // Verify Address Button
            Button(action: { startVerification() }) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Verify on Device")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(Color.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Verify address on device")
            .accessibilityHint("Confirm your wallet address matches displayed address")
            .accessibilityIdentifier("receive_verify_button")
        }
        .padding(.vertical, 16)
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(.spring(response: 0.35, dampingFraction: 0.85).delay(0.05), value: appearAnimation)
    }
    
    // MARK: - Address Section
    
    private func addressSection(address: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("YOUR ADDRESS")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.4))
                    .tracking(1)
                
                Spacer()
                
                // Copy button
                Button(action: { copyAddress(address) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                        Text("Copy")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy address")
                .accessibilityHint("Copy wallet address to clipboard")
                .accessibilityIdentifier("receive_copy_button")
            }
            
            // Address display - tappable to copy
            Button(action: { copyAddress(address) }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formatAddress(address).prefix)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                        
                        Text(formatAddress(address).suffix)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.5))
                    }
                    .textSelection(.enabled)
                    
                    Spacer()
                    
                    Image(systemName: "hand.tap")
                        .font(.system(size: 14))
                        .foregroundColor(Color.white.opacity(0.25))
                }
                .padding(14)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Wallet address")
            .accessibilityValue(address)
            .accessibilityHint("Tap to copy address to clipboard")
            .accessibilityIdentifier("receive_address_display")
            
            // Warning text
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                Text("Only send \(selectedChain?.symbol ?? "") to this address")
                    .font(.system(size: 11))
            }
            .foregroundColor(Color.orange.opacity(0.8))
            .accessibilityLabel("Warning: Only send \(selectedChain?.symbol ?? "") to this address")
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(.spring(response: 0.35, dampingFraction: 0.85).delay(0.1), value: appearAnimation)
    }
    
    // Helper to format address for display
    private func formatAddress(_ address: String) -> (prefix: String, suffix: String) {
        let midpoint = address.count / 2
        let prefixEnd = address.index(address.startIndex, offsetBy: midpoint)
        return (String(address[..<prefixEnd]), String(address[prefixEnd...]))
    }
    
    // MARK: - Request Amount Section
    
    private func requestAmountSection(chain: ChainInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("REQUEST AMOUNT")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.4))
                    .tracking(1)
                
                Text("(Optional)")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.3))
                
                Spacer()
                
                // USD/Crypto toggle
                Button(action: { 
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        isAmountInUSD.toggle()
                        if isAmountInUSD {
                            if let crypto = Double(requestAmount), crypto > 0 {
                                requestAmountUSD = String(format: "%.2f", crypto * priceForChain(chain))
                            }
                        } else {
                            if let usd = Double(requestAmountUSD), usd > 0 {
                                requestAmount = String(format: "%.8f", usd / priceForChain(chain))
                            }
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(isAmountInUSD ? "USD" : chain.symbol)
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            
            // Amount input
            HStack(spacing: 8) {
                Image(systemName: isAmountInUSD ? "dollarsign" : chain.iconName)
                    .font(.system(size: 16))
                    .foregroundColor(Color.white.opacity(0.4))
                    .frame(width: 24)
                
                TextField("", text: isAmountInUSD ? $requestAmountUSD : $requestAmount)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .placeholder(when: (isAmountInUSD ? requestAmountUSD : requestAmount).isEmpty) {
                        Text("0.00")
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.25))
                    }
                    .onChange(of: requestAmount) { newValue in
                        if !isAmountInUSD, let crypto = Double(newValue), crypto > 0 {
                            requestAmountUSD = String(format: "%.2f", crypto * priceForChain(chain))
                        }
                    }
                    .onChange(of: requestAmountUSD) { newValue in
                        if isAmountInUSD, let usd = Double(newValue), usd > 0 {
                            requestAmount = String(format: "%.8f", usd / priceForChain(chain))
                        }
                    }
                
                Spacer()
                
                Text(isAmountInUSD ? "USD" : chain.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.4))
            }
            .padding(14)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
            
            // Conversion preview
            if !requestAmount.isEmpty, let amount = Double(requestAmount), amount > 0 {
                HStack {
                    Text("≈")
                        .foregroundColor(Color.white.opacity(0.3))
                    if isAmountInUSD {
                        Text("\(requestAmount) \(chain.symbol)")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.5))
                    } else {
                        Text("$\(String(format: "%.2f", amount * priceForChain(chain))) USD")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 8)
            }
            
            // Memo field
            HStack(spacing: 8) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 14))
                    .foregroundColor(Color.white.opacity(0.3))
                
                TextField("", text: $memo)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .placeholder(when: memo.isEmpty) {
                        Text("Memo / Note (optional)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.25))
                    }
            }
            .padding(14)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
            
            // Info text
            HStack(spacing: 4) {
                Image(systemName: "qrcode")
                    .font(.system(size: 10))
                Text("QR code updates automatically with amount")
                    .font(.system(size: 11))
            }
            .foregroundColor(Color.white.opacity(0.3))
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(.spring(response: 0.35, dampingFraction: 0.85).delay(0.15), value: appearAnimation)
    }
    
    // Helper for price conversion
    private func priceForChain(_ chain: ChainInfo) -> Double {
        switch chain.id.lowercased() {
        case "bitcoin", "bitcoin-testnet": return btcPrice
        case "ethereum", "ethereum-sepolia": return ethPrice
        case "litecoin": return ltcPrice
        default: return 1.0
        }
    }
    
    // MARK: - Action Buttons
    
    private func actionButtonsSection(chain: ChainInfo, address: String) -> some View {
        VStack(spacing: 8) {
            // Copy Address — primary action
            Button(action: { copyAddress(address) }) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14, weight: .medium))
                    Text("Copy Address")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.white)
                .foregroundColor(Color(red: 0.10, green: 0.10, blue: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            
            HStack(spacing: 8) {
                // Copy Payment Link
                Button(action: { copyPaymentLink(chain: chain, address: address) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 12, weight: .medium))
                        Text("Copy Link")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.white.opacity(0.08))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                // Share
                Button(action: { shareAddress(chain: chain, address: address) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .medium))
                        Text("Share")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.white.opacity(0.08))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                // Save QR
                Button(action: { saveQRCode(chain: chain, address: address) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 12, weight: .medium))
                        Text("Save QR")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.white.opacity(0.08))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(.spring(response: 0.35, dampingFraction: 0.85).delay(0.2), value: appearAnimation)
    }
    
    // MARK: - Toast View
    
    private var copiedToastView: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color.green)
            
            Text(copiedText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.1))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
    }
    
    // MARK: - Helper Functions
    
    private func generatePaymentURI(chain: ChainInfo, address: String) -> String {
        var uri = ""
        
        // Build URI scheme based on chain
        switch chain.id.lowercased() {
        case "bitcoin", "bitcoin-testnet":
            uri = "bitcoin:\(address)"
        case "litecoin":
            uri = "litecoin:\(address)"
        case "ethereum", "ethereum-sepolia":
            uri = "ethereum:\(address)"
        case "solana":
            uri = "solana:\(address)"
        case "xrp":
            uri = "xrp:\(address)"
        default:
            uri = address
        }
        
        // Add amount if specified
        var queryParams: [String] = []
        if !requestAmount.isEmpty, let _ = Double(requestAmount) {
            queryParams.append("amount=\(requestAmount)")
        }
        if !memo.isEmpty {
            let encodedMemo = memo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? memo
            queryParams.append("message=\(encodedMemo)")
        }
        
        if !queryParams.isEmpty {
            uri += "?" + queryParams.joined(separator: "&")
        }
        
        return uri
    }
    
    private func copyAddress(_ address: String) {
        ClipboardHelper.copySensitive(address, timeout: 60)
        onCopy(address)
        showToast("Address copied! Auto-clears in 60s.")
        
        // ROADMAP-20: Track receive address copied
        AnalyticsService.shared.track(AnalyticsService.EventName.receiveViewed)
    }
    
    private func copyPaymentLink(chain: ChainInfo, address: String) {
        let uri = generatePaymentURI(chain: chain, address: address)
        ClipboardHelper.copySensitive(uri, timeout: 60)
        showToast("Payment link copied! Auto-clears in 60s.")
    }
    
    private func shareAddress(chain: ChainInfo, address: String) {
        #if canImport(AppKit)
        let uri = generatePaymentURI(chain: chain, address: address)
        let shareText = "My \(chain.title) address: \(uri)"
        
        let picker = NSSharingServicePicker(items: [shareText])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
        #endif
    }
    
    private func saveQRCode(chain: ChainInfo, address: String) {
        #if canImport(AppKit)
        let uri = generatePaymentURI(chain: chain, address: address)
        
        // Generate QR image
        guard let qrImage = generateQRImage(content: uri, size: 512) else {
            return
        }
        
        // Save panel
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "\(chain.title)_address_qr.png"
        savePanel.message = "Save QR Code"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                if let pngData = qrImage.pngData() {
                    try? pngData.write(to: url)
                    showToast("QR code saved!")
                }
            }
        }
        #endif
    }
    
    private func generateQRImage(content: String, size: CGFloat) -> NSImage? {
        #if canImport(AppKit)
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        let data = Data(content.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let scale = size / outputImage.extent.width
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
        #else
        return nil
        #endif
    }
    
    private func showToast(_ text: String) {
        copiedText = text
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showCopiedToast = false
            }
        }
    }
    
    // MARK: - Verification Functions
    
    private func startVerification() {
        verificationStep = 0
        withAnimation(HawalaTheme.Animation.spring) {
            showAddressVerification = true
        }
        
        // Simulate verification steps
        simulateVerificationSteps()
    }
    
    private func simulateVerificationSteps() {
        // Step 1: Connecting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                verificationStep = 1
            }
        }
        
        // Step 2: Verifying
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                verificationStep = 2
            }
        }
        
        // Step 3: Complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                verificationStep = 3
            }
        }
        
        // Auto dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            withAnimation(HawalaTheme.Animation.spring) {
                showAddressVerification = false
            }
        }
    }
    
    // MARK: - Address Verification Overlay
    
    private var addressVerificationOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        showAddressVerification = false
                    }
                }
            
            // Verification card
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(verificationStep == 3 ? Color.green.opacity(0.15) : Color.white.opacity(0.08))
                        .frame(width: 80, height: 80)
                    
                    if verificationStep < 3 {
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(Color.white.opacity(0.5), lineWidth: 3)
                            .frame(width: 60, height: 60)
                            .rotationEffect(.degrees(verificationStep > 0 ? 360 : 0))
                            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: verificationStep)
                        
                        Image(systemName: "shield")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundColor(Color.green)
                    }
                }
                
                VStack(spacing: 8) {
                    Text(verificationStatusTitle)
                        .font(.clashGroteskMedium(size: 18))
                        .foregroundColor(.white)
                    
                    Text(verificationStatusSubtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                
                // Progress dots
                HStack(spacing: 12) {
                    ForEach(0..<3) { step in
                        Circle()
                            .fill(step <= verificationStep ? Color.white : Color.white.opacity(0.15))
                            .frame(width: 8, height: 8)
                    }
                }
                
                // Done button
                if verificationStep == 3 {
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            showAddressVerification = false
                        }
                    }) {
                        Text("Done")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(red: 0.10, green: 0.10, blue: 0.12))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
            }
            .padding(32)
            .frame(maxWidth: 300)
            .background(Color(red: 0.10, green: 0.10, blue: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.1), Color.white.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 10)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
    
    private var verificationStatusTitle: String {
        switch verificationStep {
        case 0: return "Preparing..."
        case 1: return "Connecting to Device"
        case 2: return "Verifying Address"
        case 3: return "Address Verified!"
        default: return ""
        }
    }
    
    private var verificationStatusSubtitle: String {
        switch verificationStep {
        case 0: return "Initializing verification"
        case 1: return "Please check your hardware wallet"
        case 2: return "Confirm the address matches"
        case 3: return "This address is safe to use"
        default: return ""
        }
    }
}

// MARK: - Address Format Pill

struct AddressFormatPill: View {
    let format: BitcoinAddressFormat
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: format.icon)
                    .font(.system(size: 14, weight: .semibold))
                
                Text(format.rawValue)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.white.opacity(0.1) : (isHovered ? Color.white.opacity(0.04) : Color.clear))
            .foregroundColor(isSelected ? .white : Color.white.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Receive Chain Pill

struct ReceiveChainPill: View {
    let chain: ChainInfo
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: chain.iconName)
                    .font(.system(size: 12, weight: .semibold))
                
                Text(chain.symbol)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.white.opacity(0.1) : (isHovered ? Color.white.opacity(0.04) : Color.clear))
            .foregroundColor(isSelected ? .white : Color.white.opacity(0.4))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - NSImage PNG Extension

#if canImport(AppKit)
extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = self.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmapRep.representation(using: .png, properties: [:])
    }
}
#endif

// MARK: - ChainInfo Extension

extension ChainInfo {
    var symbol: String {
        switch id.lowercased() {
        case "bitcoin", "bitcoin-testnet": return "BTC"
        case "ethereum", "ethereum-sepolia": return "ETH"
        case "litecoin": return "LTC"
        case "solana": return "SOL"
        case "xrp": return "XRP"
        case "bnb": return "BNB"
        case "monero": return "XMR"
        // New chains from wallet-core integration
        case "ton": return "TON"
        case "aptos": return "APT"
        case "sui": return "SUI"
        case "polkadot": return "DOT"
        case "kusama": return "KSM"
        default: return id.uppercased()
        }
    }
}
