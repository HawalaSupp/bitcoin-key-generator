import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Payment Links View
/// Create and parse payment request links (hawala://, BIP-21, EIP-681)
struct PaymentLinksView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: PaymentTab = .create
    @State private var isLoading = false
    @State private var error: String?
    @State private var appearAnimation = false
    
    // Create link states
    @State private var recipientAddress = ""
    @State private var amount = ""
    @State private var selectedFormat: LinkFormat = .hawala
    @State private var memo = ""
    @State private var generatedLink = ""
    @State private var showCopiedToast = false
    
    // Parse link states
    @State private var inputUri = ""
    @State private var parsedLink: HawalaBridge.ParsedPaymentLink?
    
    enum PaymentTab: String, CaseIterable {
        case create = "Create Link"
        case parse = "Parse Link"
        
        var icon: String {
            switch self {
            case .create: return "link.badge.plus"
            case .parse: return "doc.text.magnifyingglass"
            }
        }
    }
    
    enum LinkFormat: String, CaseIterable {
        case hawala = "Hawala"
        case bip21 = "Bitcoin (BIP-21)"
        case eip681 = "Ethereum (EIP-681)"
        
        var description: String {
            switch self {
            case .hawala: return "Universal Hawala payment link"
            case .bip21: return "Standard Bitcoin URI"
            case .eip681: return "Standard Ethereum URI"
            }
        }
    }
    
    var body: some View {
        ZStack {
            HawalaTheme.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Tab selector
                tabSelector
                
                Divider()
                    .background(HawalaTheme.Colors.divider)
                
                // Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: HawalaTheme.Spacing.lg) {
                        switch selectedTab {
                        case .create:
                            createLinkContent
                        case .parse:
                            parseLinkContent
                        }
                    }
                    .padding(.horizontal, HawalaTheme.Spacing.lg)
                    .padding(.vertical, HawalaTheme.Spacing.md)
                }
            }
            
            // Toast
            if showCopiedToast {
                VStack {
                    Spacer()
                    copiedToast
                        .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Error
            if let error = error {
                VStack {
                    Spacer()
                    errorToast(message: error)
                        .padding(.bottom, 40)
                }
            }
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 500, idealHeight: 600)
        .onAppear {
            withAnimation(HawalaTheme.Animation.spring) {
                appearAnimation = true
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
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
            
            VStack(spacing: 2) {
                Text("Payment Links")
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("Create and share payment requests")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            // Placeholder for symmetry
            Color.clear
                .frame(width: 32, height: 32)
        }
        .padding()
    }
    
    // MARK: - Tab Selector
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(PaymentTab.allCases, id: \.rawValue) { tab in
                Button(action: {
                    withAnimation(HawalaTheme.Animation.fast) {
                        selectedTab = tab
                    }
                }) {
                    HStack(spacing: HawalaTheme.Spacing.sm) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14))
                        Text(tab.rawValue)
                            .font(HawalaTheme.Typography.captionBold)
                    }
                    .foregroundColor(selectedTab == tab ? HawalaTheme.Colors.accent : HawalaTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, HawalaTheme.Spacing.md)
                    .background(
                        selectedTab == tab
                            ? HawalaTheme.Colors.accentSubtle
                            : Color.clear
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .background(HawalaTheme.Colors.backgroundSecondary)
    }
    
    // MARK: - Create Link Content
    
    private var createLinkContent: some View {
        VStack(spacing: HawalaTheme.Spacing.lg) {
            // Format selector
            formatSelector
            
            // Input fields
            inputFieldsSection
            
            // Generate button
            Button(action: { Task { await generateLink() } }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "link.badge.plus")
                    }
                    Text("Generate Link")
                }
                .font(HawalaTheme.Typography.captionBold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(HawalaTheme.Spacing.md)
                .background(recipientAddress.isEmpty ? HawalaTheme.Colors.backgroundTertiary : HawalaTheme.Colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
            }
            .buttonStyle(.plain)
            .disabled(recipientAddress.isEmpty || isLoading)
            
            // Generated link display
            if !generatedLink.isEmpty {
                generatedLinkCard
            }
        }
    }
    
    private var formatSelector: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            Text("LINK FORMAT")
                .font(HawalaTheme.Typography.label)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            
            ForEach(LinkFormat.allCases, id: \.rawValue) { format in
                Button(action: { selectedFormat = format }) {
                    HStack {
                        Image(systemName: selectedFormat == format ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedFormat == format ? HawalaTheme.Colors.accent : HawalaTheme.Colors.textTertiary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(format.rawValue)
                                .font(HawalaTheme.Typography.body)
                                .foregroundColor(HawalaTheme.Colors.textPrimary)
                            
                            Text(format.description)
                                .font(HawalaTheme.Typography.caption)
                                .foregroundColor(HawalaTheme.Colors.textSecondary)
                        }
                        
                        Spacer()
                    }
                    .padding(HawalaTheme.Spacing.md)
                    .background(
                        selectedFormat == format
                            ? HawalaTheme.Colors.accentSubtle
                            : HawalaTheme.Colors.backgroundSecondary
                    )
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var inputFieldsSection: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            // Recipient address
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xs) {
                Text("RECIPIENT ADDRESS")
                    .font(HawalaTheme.Typography.label)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                TextField("Enter address", text: $recipientAddress)
                    .textFieldStyle(.plain)
                    .font(HawalaTheme.Typography.mono)
                    .padding(HawalaTheme.Spacing.md)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
            }
            
            // Amount (optional)
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xs) {
                Text("AMOUNT (OPTIONAL)")
                    .font(HawalaTheme.Typography.label)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                TextField("0.0", text: $amount)
                    .textFieldStyle(.plain)
                    .font(HawalaTheme.Typography.body)
                    .padding(HawalaTheme.Spacing.md)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
            }
            
            // Memo (optional)
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xs) {
                Text("MEMO (OPTIONAL)")
                    .font(HawalaTheme.Typography.label)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                TextField("Payment description", text: $memo)
                    .textFieldStyle(.plain)
                    .font(HawalaTheme.Typography.body)
                    .padding(HawalaTheme.Spacing.md)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
            }
        }
    }
    
    private var generatedLinkCard: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(HawalaTheme.Colors.success)
                
                Text("Link Generated")
                    .font(HawalaTheme.Typography.captionBold)
                    .foregroundColor(HawalaTheme.Colors.success)
                
                Spacer()
            }
            
            // Link display
            Text(generatedLink)
                .font(HawalaTheme.Typography.mono)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
                .padding(HawalaTheme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(HawalaTheme.Colors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                .textSelection(.enabled)
            
            // Action buttons
            HStack(spacing: HawalaTheme.Spacing.md) {
                Button(action: { copyToClipboard(generatedLink) }) {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                    }
                    .font(HawalaTheme.Typography.captionBold)
                    .foregroundColor(HawalaTheme.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(HawalaTheme.Spacing.md)
                    .background(HawalaTheme.Colors.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                }
                .buttonStyle(.plain)
                
                Button(action: { shareLink(generatedLink) }) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .font(HawalaTheme.Typography.captionBold)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(HawalaTheme.Spacing.md)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.success.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                .strokeBorder(HawalaTheme.Colors.success.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Parse Link Content
    
    private var parseLinkContent: some View {
        VStack(spacing: HawalaTheme.Spacing.lg) {
            // Input field
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xs) {
                Text("PAYMENT LINK OR URI")
                    .font(HawalaTheme.Typography.label)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                TextEditor(text: $inputUri)
                    .font(HawalaTheme.Typography.mono)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(HawalaTheme.Spacing.md)
                    .frame(height: 100)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                
                Text("Supports hawala://, bitcoin:, ethereum:, solana: schemes")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            
            // Parse button
            Button(action: { Task { await parseLink() } }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    Text("Parse Link")
                }
                .font(HawalaTheme.Typography.captionBold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(HawalaTheme.Spacing.md)
                .background(inputUri.isEmpty ? HawalaTheme.Colors.backgroundTertiary : HawalaTheme.Colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
            }
            .buttonStyle(.plain)
            .disabled(inputUri.isEmpty || isLoading)
            
            // Parsed result
            if let parsed = parsedLink {
                parsedResultCard(parsed: parsed)
            }
        }
    }
    
    private func parsedResultCard(parsed: HawalaBridge.ParsedPaymentLink) -> some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            // Status header
            HStack {
                Image(systemName: parsed.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(parsed.isValid ? HawalaTheme.Colors.success : HawalaTheme.Colors.error)
                
                Text(parsed.isValid ? "Valid Payment Link" : "Invalid Link")
                    .font(HawalaTheme.Typography.captionBold)
                    .foregroundColor(parsed.isValid ? HawalaTheme.Colors.success : HawalaTheme.Colors.error)
                
                Spacer()
                
                Text(parsed.scheme.uppercased())
                    .font(HawalaTheme.Typography.label)
                    .foregroundColor(HawalaTheme.Colors.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(HawalaTheme.Colors.accentSubtle)
                    .clipShape(Capsule())
            }
            
            Divider()
                .background(HawalaTheme.Colors.divider)
            
            // Details
            VStack(spacing: HawalaTheme.Spacing.sm) {
                detailRow(label: "To", value: parsed.request.to)
                
                if let amount = parsed.request.amount {
                    detailRow(label: "Amount", value: amount)
                }
                
                if let token = parsed.request.token {
                    detailRow(label: "Token", value: token)
                }
                
                if let memo = parsed.request.memo {
                    detailRow(label: "Memo", value: memo)
                }
                
                if let chainId = parsed.request.chainId {
                    detailRow(label: "Chain ID", value: String(chainId))
                }
            }
            
            // Errors if any
            if !parsed.errors.isEmpty {
                VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xs) {
                    Text("ERRORS")
                        .font(HawalaTheme.Typography.label)
                        .foregroundColor(HawalaTheme.Colors.error)
                    
                    ForEach(parsed.errors, id: \.self) { error in
                        Text("• \(error)")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.error)
                    }
                }
                .padding(HawalaTheme.Spacing.md)
                .background(HawalaTheme.Colors.error.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
            }
            
            // Use this request button
            if parsed.isValid {
                Button(action: { /* Would navigate to send view */ }) {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("Use This Request")
                    }
                    .font(HawalaTheme.Typography.captionBold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(HawalaTheme.Spacing.md)
                    .background(HawalaTheme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(HawalaTheme.Spacing.lg)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                .strokeBorder(
                    parsed.isValid ? HawalaTheme.Colors.success.opacity(0.3) : HawalaTheme.Colors.error.opacity(0.3),
                    lineWidth: 1
                )
        )
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .font(HawalaTheme.Typography.mono)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
        }
    }
    
    // MARK: - Toasts
    
    private var copiedToast: some View {
        HStack(spacing: HawalaTheme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(HawalaTheme.Colors.success)
            
            Text("Copied to clipboard")
                .font(HawalaTheme.Typography.bodySmall)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.success.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
    }
    
    private func errorToast(message: String) -> some View {
        HStack(spacing: HawalaTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(HawalaTheme.Colors.error)
            
            Text(message)
                .font(HawalaTheme.Typography.bodySmall)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.error.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
    }
    
    // MARK: - Actions
    
    private func generateLink() async {
        isLoading = true
        error = nil
        
        do {
            let request = HawalaBridge.PaymentRequest(
                to: recipientAddress,
                amount: amount.isEmpty ? nil : amount,
                memo: memo.isEmpty ? nil : memo
            )
            
            switch selectedFormat {
            case .hawala:
                generatedLink = try HawalaBridge.shared.createPaymentLink(request: request)
            case .bip21:
                generatedLink = try HawalaBridge.shared.createBip21Link(request: request)
            case .eip681:
                generatedLink = try HawalaBridge.shared.createEip681Link(request: request)
            }
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func parseLink() async {
        isLoading = true
        error = nil
        parsedLink = nil
        
        do {
            parsedLink = try HawalaBridge.shared.parsePaymentLink(uri: inputUri.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func copyToClipboard(_ text: String) {
        ClipboardHelper.copySensitive(text, timeout: 60)
        
        withAnimation {
            showCopiedToast = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedToast = false
            }
        }
    }
    
    private func shareLink(_ text: String) {
        #if os(macOS)
        let picker = NSSharingServicePicker(items: [text])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
        #endif
    }
}

// MARK: - Preview

#if DEBUG
struct PaymentLinksView_Previews: PreviewProvider {
    static var previews: some View {
        PaymentLinksView()
            .preferredColorScheme(.dark)
    }
}
#endif
