import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
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
    @Environment(\.dismiss) private var dismiss
    
    let chains: [ChainInfo]
    let onCopy: (String) -> Void
    
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
    
    init(chains: [ChainInfo], onCopy: @escaping (String) -> Void) {
        self.chains = chains
        self.onCopy = onCopy
        // Default to first chain with an address
        _selectedChain = State(initialValue: chains.first(where: { $0.receiveAddress != nil }))
    }
    
    var body: some View {
        ZStack {
            // Background
            HawalaTheme.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                receiveHeader
                
                // Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: HawalaTheme.Spacing.lg) {
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
                    .padding(.horizontal, HawalaTheme.Spacing.lg)
                    .padding(.top, HawalaTheme.Spacing.md)
                    .padding(.bottom, HawalaTheme.Spacing.xxl)
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
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(HawalaTheme.Animation.spring) {
                appearAnimation = true
            }
        }
    }
    
    // MARK: - Header
    
    private var receiveHeader: some View {
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
            
            Text("Receive")
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
                    ForEach(chains.filter { $0.receiveAddress != nil }) { chain in
                        ReceiveChainPill(
                            chain: chain,
                            isSelected: selectedChain?.id == chain.id,
                            action: { 
                                withAnimation(HawalaTheme.Animation.spring) {
                                    selectedChain = chain
                                    // Reset amount when switching chains
                                    requestAmount = ""
                                    requestAmountUSD = ""
                                }
                                // Animate QR code
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
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            Text("ADDRESS FORMAT")
                .font(HawalaTheme.Typography.label)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
                .tracking(1)
            
            HStack(spacing: HawalaTheme.Spacing.sm) {
                ForEach(BitcoinAddressFormat.allCases) { format in
                    AddressFormatPill(
                        format: format,
                        isSelected: selectedAddressFormat == format,
                        action: {
                            withAnimation(HawalaTheme.Animation.spring) {
                                selectedAddressFormat = format
                            }
                        }
                    )
                }
            }
            
            // Info text
            HStack(spacing: HawalaTheme.Spacing.xs) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                Text(selectedAddressFormat.description)
                    .font(HawalaTheme.Typography.caption)
            }
            .foregroundColor(HawalaTheme.Colors.textTertiary)
        }
        .hawalaCard()
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(HawalaTheme.Animation.spring.delay(0.05), value: appearAnimation)
    }
    
    // MARK: - QR Code Section
    
    private func qrCodeSection(chain: ChainInfo, address: String) -> some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            // QR Code with Chain Branding
            ZStack {
                // Glow effect behind QR
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg + 8, style: .continuous)
                    .fill(HawalaTheme.Colors.forChain(chain.id).opacity(0.1))
                    .frame(width: 240, height: 240)
                    .blur(radius: 20)
                
                // White background for QR
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                    .fill(.white)
                    .frame(width: 220, height: 220)
                
                // QR Code
                QRCodeView(content: generatePaymentURI(chain: chain, address: address), size: 200)
                
                // Chain Icon Overlay
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 44, height: 44)
                    
                    Circle()
                        .fill(HawalaTheme.Colors.forChain(chain.id))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: chain.iconName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .scaleEffect(qrAnimationScale)
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            
            // Chain Name Badge with Amount
            HStack(spacing: 6) {
                Circle()
                    .fill(HawalaTheme.Colors.forChain(chain.id))
                    .frame(width: 8, height: 8)
                Text(chain.title)
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                
                if !requestAmount.isEmpty {
                    Text("•")
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    Text("\(requestAmount) \(chain.symbol)")
                        .font(HawalaTheme.Typography.captionBold)
                        .foregroundColor(HawalaTheme.Colors.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(HawalaTheme.Colors.backgroundTertiary)
            .clipShape(Capsule())
            
            // Verify Address Button
            Button(action: { startVerification() }) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Verify on Device")
                        .font(HawalaTheme.Typography.caption)
                }
                .foregroundColor(HawalaTheme.Colors.success)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, HawalaTheme.Spacing.lg)
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(HawalaTheme.Animation.spring.delay(0.05), value: appearAnimation)
    }
    
    // MARK: - Address Section
    
    private func addressSection(address: String) -> some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            HStack {
                Text("YOUR ADDRESS")
                    .font(HawalaTheme.Typography.label)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                    .tracking(1)
                
                Spacer()
                
                // Copy button with feedback
                Button(action: { copyAddress(address) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                        Text("Copy")
                            .font(HawalaTheme.Typography.label)
                    }
                    .foregroundColor(HawalaTheme.Colors.accent)
                }
                .buttonStyle(.plain)
            }
            
            // Address display - tappable to copy
            Button(action: { copyAddress(address) }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        // Split address for better readability
                        Text(formatAddress(address).prefix)
                            .font(HawalaTheme.Typography.mono)
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                        
                        Text(formatAddress(address).suffix)
                            .font(HawalaTheme.Typography.mono)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                    }
                    .textSelection(.enabled)
                    
                    Spacer()
                    
                    // Visual tap hint
                    Image(systemName: "hand.tap")
                        .font(.system(size: 14))
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                .padding(HawalaTheme.Spacing.md)
                .background(HawalaTheme.Colors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            
            // Warning text
            HStack(spacing: HawalaTheme.Spacing.xs) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                Text("Only send \(selectedChain?.symbol ?? "") to this address")
                    .font(HawalaTheme.Typography.caption)
            }
            .foregroundColor(HawalaTheme.Colors.warning)
        }
        .hawalaCard()
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(HawalaTheme.Animation.spring.delay(0.1), value: appearAnimation)
    }
    
    // Helper to format address for display
    private func formatAddress(_ address: String) -> (prefix: String, suffix: String) {
        let midpoint = address.count / 2
        let prefixEnd = address.index(address.startIndex, offsetBy: midpoint)
        return (String(address[..<prefixEnd]), String(address[prefixEnd...]))
    }
    
    // MARK: - Request Amount Section
    
    private func requestAmountSection(chain: ChainInfo) -> some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            HStack {
                Text("REQUEST AMOUNT")
                    .font(HawalaTheme.Typography.label)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                    .tracking(1)
                
                Text("(Optional)")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                Spacer()
                
                // USD/Crypto toggle
                Button(action: { 
                    withAnimation(HawalaTheme.Animation.fast) {
                        isAmountInUSD.toggle()
                        // Convert amounts when toggling
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
                            .font(HawalaTheme.Typography.captionBold)
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(HawalaTheme.Colors.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(HawalaTheme.Colors.accentSubtle)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            
            // Amount input
            HStack(spacing: HawalaTheme.Spacing.sm) {
                Image(systemName: isAmountInUSD ? "dollarsign" : chain.iconName)
                    .font(.system(size: 16))
                    .foregroundColor(isAmountInUSD ? HawalaTheme.Colors.success : HawalaTheme.Colors.forChain(chain.id))
                    .frame(width: 24)
                
                TextField("", text: isAmountInUSD ? $requestAmountUSD : $requestAmount)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                    .placeholder(when: (isAmountInUSD ? requestAmountUSD : requestAmount).isEmpty) {
                        Text("0.00")
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
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
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            
            // Conversion preview
            if !requestAmount.isEmpty, let amount = Double(requestAmount), amount > 0 {
                HStack {
                    Text("≈")
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    if isAmountInUSD {
                        Text("\(requestAmount) \(chain.symbol)")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                    } else {
                        Text("$\(String(format: "%.2f", amount * priceForChain(chain))) USD")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, HawalaTheme.Spacing.sm)
            }
            
            // Memo field
            HStack(spacing: HawalaTheme.Spacing.sm) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 14))
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                TextField("", text: $memo)
                    .textFieldStyle(.plain)
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                    .placeholder(when: memo.isEmpty) {
                        Text("Memo / Note (optional)")
                            .font(HawalaTheme.Typography.body)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
            }
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            
            // Info text
            HStack(spacing: HawalaTheme.Spacing.xs) {
                Image(systemName: "qrcode")
                    .font(.system(size: 10))
                Text("QR code updates automatically with amount")
                    .font(HawalaTheme.Typography.caption)
            }
            .foregroundColor(HawalaTheme.Colors.textTertiary)
        }
        .hawalaCard()
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(HawalaTheme.Animation.spring.delay(0.15), value: appearAnimation)
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
        VStack(spacing: HawalaTheme.Spacing.sm) {
            // Copy Address Button
            Button(action: { copyAddress(address) }) {
                HStack(spacing: HawalaTheme.Spacing.sm) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy Address")
                        .font(HawalaTheme.Typography.h4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, HawalaTheme.Spacing.md)
                .background(HawalaTheme.Colors.accent)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            
            HStack(spacing: HawalaTheme.Spacing.sm) {
                // Copy Payment Link
                Button(action: { copyPaymentLink(chain: chain, address: address) }) {
                    HStack(spacing: HawalaTheme.Spacing.xs) {
                        Image(systemName: "link")
                        Text("Copy Link")
                            .font(HawalaTheme.Typography.body)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, HawalaTheme.Spacing.md)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                            .strokeBorder(HawalaTheme.Colors.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                // Share Button
                Button(action: { shareAddress(chain: chain, address: address) }) {
                    HStack(spacing: HawalaTheme.Spacing.xs) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                            .font(HawalaTheme.Typography.body)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, HawalaTheme.Spacing.md)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                            .strokeBorder(HawalaTheme.Colors.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                // Save QR Button
                Button(action: { saveQRCode(chain: chain, address: address) }) {
                    HStack(spacing: HawalaTheme.Spacing.xs) {
                        Image(systemName: "arrow.down.circle")
                        Text("Save QR")
                            .font(HawalaTheme.Typography.body)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, HawalaTheme.Spacing.md)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                            .strokeBorder(HawalaTheme.Colors.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(HawalaTheme.Animation.spring.delay(0.2), value: appearAnimation)
    }
    
    // MARK: - Toast View
    
    private var copiedToastView: some View {
        HStack(spacing: HawalaTheme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(HawalaTheme.Colors.success)
            
            Text(copiedText)
                .font(HawalaTheme.Typography.body)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
        }
        .padding(.horizontal, HawalaTheme.Spacing.lg)
        .padding(.vertical, HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .clipShape(Capsule())
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
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
        #endif
        onCopy(address)
        showToast("Address copied!")
    }
    
    private func copyPaymentLink(chain: ChainInfo, address: String) {
        let uri = generatePaymentURI(chain: chain, address: address)
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(uri, forType: .string)
        #endif
        showToast("Payment link copied!")
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
            // Blur background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(HawalaTheme.Animation.spring) {
                        showAddressVerification = false
                    }
                }
            
            // Verification card
            VStack(spacing: HawalaTheme.Spacing.xl) {
                // Icon
                ZStack {
                    Circle()
                        .fill(verificationStep == 3 ? HawalaTheme.Colors.success.opacity(0.2) : HawalaTheme.Colors.accent.opacity(0.2))
                        .frame(width: 80, height: 80)
                    
                    if verificationStep < 3 {
                        // Loading indicator
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(HawalaTheme.Colors.accent, lineWidth: 3)
                            .frame(width: 60, height: 60)
                            .rotationEffect(.degrees(verificationStep > 0 ? 360 : 0))
                            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: verificationStep)
                        
                        Image(systemName: "shield")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(HawalaTheme.Colors.accent)
                    } else {
                        // Success checkmark
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundColor(HawalaTheme.Colors.success)
                    }
                }
                
                // Status text
                VStack(spacing: HawalaTheme.Spacing.sm) {
                    Text(verificationStatusTitle)
                        .font(HawalaTheme.Typography.h3)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    Text(verificationStatusSubtitle)
                        .font(HawalaTheme.Typography.body)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                
                // Progress steps
                HStack(spacing: HawalaTheme.Spacing.md) {
                    ForEach(0..<3) { step in
                        Circle()
                            .fill(step <= verificationStep ? HawalaTheme.Colors.accent : HawalaTheme.Colors.backgroundTertiary)
                            .frame(width: 8, height: 8)
                    }
                }
                
                // Dismiss button (only when complete)
                if verificationStep == 3 {
                    Button(action: {
                        withAnimation(HawalaTheme.Animation.spring) {
                            showAddressVerification = false
                        }
                    }) {
                        Text("Done")
                            .font(HawalaTheme.Typography.h4)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, HawalaTheme.Spacing.md)
                            .background(HawalaTheme.Colors.success)
                            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, HawalaTheme.Spacing.md)
                }
            }
            .padding(HawalaTheme.Spacing.xl)
            .frame(maxWidth: 300)
            .background(HawalaTheme.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.xl, style: .continuous)
                    .strokeBorder(HawalaTheme.Colors.border, lineWidth: 1)
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
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: format.icon)
                    .font(.system(size: 14, weight: .semibold))
                
                Text(format.rawValue)
                    .font(HawalaTheme.Typography.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, HawalaTheme.Spacing.sm)
            .background(isSelected ? HawalaTheme.Colors.accent.opacity(0.2) : HawalaTheme.Colors.backgroundTertiary)
            .foregroundColor(isSelected ? HawalaTheme.Colors.accent : HawalaTheme.Colors.textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? HawalaTheme.Colors.accent.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Receive Chain Pill

struct ReceiveChainPill: View {
    let chain: ChainInfo
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: chain.iconName)
                    .font(.system(size: 12, weight: .semibold))
                
                Text(chain.symbol)
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
        HawalaTheme.Colors.forChain(chain.id)
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
        default: return id.uppercased()
        }
    }
}
