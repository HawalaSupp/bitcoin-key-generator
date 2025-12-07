import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Modern Receive View

struct ReceiveViewModern: View {
    @Environment(\.dismiss) private var dismiss
    
    let chains: [ChainInfo]
    let onCopy: (String) -> Void
    
    @State private var selectedChain: ChainInfo?
    @State private var requestAmount: String = ""
    @State private var memo: String = ""
    @State private var showCopiedToast = false
    @State private var copiedText = ""
    @State private var appearAnimation = false
    
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
                        
                        // QR Code Display
                        if let chain = selectedChain, let address = chain.receiveAddress {
                            qrCodeSection(chain: chain, address: address)
                            
                            // Address Display
                            addressSection(address: address)
                            
                            // Request Amount (Optional)
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
                            action: { selectedChain = chain }
                        )
                    }
                }
            }
        }
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
    }
    
    // MARK: - QR Code Section
    
    private func qrCodeSection(chain: ChainInfo, address: String) -> some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            // QR Code with Chain Branding
            ZStack {
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
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            
            // Chain Name Badge
            HStack(spacing: 6) {
                Circle()
                    .fill(HawalaTheme.Colors.forChain(chain.id))
                    .frame(width: 8, height: 8)
                Text(chain.title)
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(HawalaTheme.Colors.backgroundTertiary)
            .clipShape(Capsule())
        }
        .padding(.vertical, HawalaTheme.Spacing.lg)
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(HawalaTheme.Animation.spring.delay(0.05), value: appearAnimation)
    }
    
    // MARK: - Address Section
    
    private func addressSection(address: String) -> some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            Text("YOUR ADDRESS")
                .font(HawalaTheme.Typography.label)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
                .tracking(1)
            
            HStack {
                Text(address)
                    .font(HawalaTheme.Typography.mono)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                
                Spacer()
                
                Button(action: { copyAddress(address) }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundColor(HawalaTheme.Colors.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
        }
        .hawalaCard()
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(HawalaTheme.Animation.spring.delay(0.1), value: appearAnimation)
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
            }
            
            HStack(spacing: HawalaTheme.Spacing.sm) {
                Image(systemName: chain.iconName)
                    .font(.system(size: 16))
                    .foregroundColor(HawalaTheme.Colors.forChain(chain.id))
                
                TextField("", text: $requestAmount)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                    .placeholder(when: requestAmount.isEmpty) {
                        Text("0.00")
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                
                Spacer()
                
                Text(chain.symbol)
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            
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
                        Text("Memo (optional)")
                            .font(HawalaTheme.Typography.body)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
            }
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            
            Text("QR code will update with amount and memo")
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
        }
        .hawalaCard()
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 20)
        .animation(HawalaTheme.Animation.spring.delay(0.15), value: appearAnimation)
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
