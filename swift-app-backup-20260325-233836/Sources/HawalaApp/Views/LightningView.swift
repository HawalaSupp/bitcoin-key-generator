import SwiftUI

// MARK: - Lightning Network Views

/// Main Lightning view with invoice parsing and payment handling
struct LightningView: View {
    @StateObject private var viewModel = LightningViewModel()
    @State private var inputText = ""
    @State private var showingScanner = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Input section
                inputSection
                
                Divider()
                
                // Content area
                ScrollView {
                    VStack(spacing: 16) {
                        if let invoice = viewModel.parsedInvoice {
                            InvoiceDetailView(invoice: invoice, onPay: viewModel.payInvoice)
                        } else if let lnurlData = viewModel.lnurlData {
                            LnUrlView(data: lnurlData, viewModel: viewModel)
                        } else if viewModel.isLoading {
                            ProgressView("Processing...")
                                .padding(40)
                        } else {
                            emptyStateView
                        }
                    }
                    .padding()
                }
                
                // Error banner
                if let error = viewModel.error {
                    errorBanner(error)
                }
            }
            .navigationTitle("Lightning")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingScanner = true }) {
                        Image(systemName: "qrcode.viewfinder")
                    }
                }
            }
            .sheet(isPresented: $showingScanner) {
                QRScannerView { result in
                    inputText = result
                    viewModel.processInput(result)
                    showingScanner = false
                }
            }
        }
    }
    
    private var inputSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.yellow)
                
                TextField("Invoice, LNURL, or Lightning Address", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .onSubmit {
                        viewModel.processInput(inputText)
                    }
                
                if !inputText.isEmpty {
                    Button(action: { inputText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color(.textBackgroundColor).opacity(0.5))
            .cornerRadius(10)
            
            // Input type indicator
            if !inputText.isEmpty {
                HStack {
                    inputTypeIndicator
                    Spacer()
                    Button("Parse") {
                        viewModel.processInput(inputText)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isLoading)
                }
            }
        }
        .padding()
    }
    
    private var inputTypeIndicator: some View {
        let type = detectInputType(inputText)
        return HStack(spacing: 4) {
            Circle()
                .fill(type.color)
                .frame(width: 8, height: 8)
            Text(type.label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.circle")
                .font(.system(size: 60))
                .foregroundColor(.yellow.opacity(0.6))
            
            Text("Lightning Network")
                .font(.title2.bold())
            
            Text("Paste a BOLT11 invoice, LNURL, or Lightning address to get started")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 8) {
                exampleRow(icon: "doc.text", label: "BOLT11 Invoice", example: "lnbc...")
                exampleRow(icon: "link", label: "LNURL", example: "lnurl1...")
                exampleRow(icon: "at", label: "Lightning Address", example: "user@domain.com")
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(12)
        }
        .padding(40)
    }
    
    private func exampleRow(icon: String, label: String, example: String) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.yellow)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(example)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func errorBanner(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(error)
                .font(.subheadline)
            Spacer()
            Button("Dismiss") {
                viewModel.error = nil
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .background(Color.red.opacity(0.1))
    }
    
    private func detectInputType(_ input: String) -> InputType {
        let lowercased = input.lowercased().trimmingCharacters(in: .whitespaces)
        if lowercased.hasPrefix("lnbc") || lowercased.hasPrefix("lntb") {
            return .bolt11
        } else if lowercased.hasPrefix("lnurl") {
            return .lnurl
        } else if input.contains("@") && input.contains(".") {
            return .lightningAddress
        } else if lowercased.hasPrefix("lightning:") {
            return .lightningUri
        }
        return .unknown
    }
    
    enum InputType {
        case bolt11, lnurl, lightningAddress, lightningUri, unknown
        
        var label: String {
            switch self {
            case .bolt11: return "BOLT11 Invoice"
            case .lnurl: return "LNURL"
            case .lightningAddress: return "Lightning Address"
            case .lightningUri: return "Lightning URI"
            case .unknown: return "Unknown format"
            }
        }
        
        var color: Color {
            switch self {
            case .bolt11: return .green
            case .lnurl: return .blue
            case .lightningAddress: return .purple
            case .lightningUri: return .orange
            case .unknown: return .gray
            }
        }
    }
}

// MARK: - Invoice Detail View

struct InvoiceDetailView: View {
    let invoice: ParsedInvoice
    let onPay: () -> Void
    
    @State private var showingTechnicalDetails = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Amount card
            amountCard
            
            // Invoice info
            infoCard
            
            // Expiry warning if needed
            if invoice.isExpiringSoon {
                expiryWarning
            }
            
            // Technical details (collapsible)
            technicalSection
            
            // Pay button
            Button(action: onPay) {
                HStack {
                    Image(systemName: "bolt.fill")
                    Text("Pay \(invoice.formattedAmount)")
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
            .disabled(invoice.isExpired)
        }
    }
    
    private var amountCard: some View {
        VStack(spacing: 8) {
            Text(invoice.formattedAmount)
                .font(.system(size: 36, weight: .bold, design: .rounded))
            
            if let fiatAmount = invoice.fiatAmount {
                Text("≈ \(fiatAmount)")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 4) {
                Image(systemName: "clock")
                Text(invoice.expiryText)
            }
            .font(.caption)
            .foregroundColor(invoice.isExpiringSoon ? .orange : .secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(16)
    }
    
    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let description = invoice.description {
                infoRow(label: "Description", value: description)
            }
            
            infoRow(label: "Network", value: invoice.network)
            
            if let payee = invoice.payee {
                infoRow(label: "Payee", value: payee, monospace: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func infoRow(label: String, value: String, monospace: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(monospace ? .system(.body, design: .monospaced) : .body)
                .lineLimit(2)
        }
    }
    
    private var expiryWarning: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("Invoice expires soon!")
                .font(.subheadline)
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var technicalSection: some View {
        DisclosureGroup("Technical Details", isExpanded: $showingTechnicalDetails) {
            VStack(alignment: .leading, spacing: 8) {
                technicalRow("Payment Hash", invoice.paymentHash)
                technicalRow("Timestamp", invoice.timestampFormatted)
                technicalRow("Min CLTV", "\(invoice.minFinalCltvExpiry)")
                if !invoice.routeHints.isEmpty {
                    technicalRow("Route Hints", "\(invoice.routeHints.count)")
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func technicalRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - LNURL View

struct LnUrlView: View {
    let data: LnUrlData
    @ObservedObject var viewModel: LightningViewModel
    
    @State private var amount: String = ""
    @State private var comment: String = ""
    
    var body: some View {
        VStack(spacing: 16) {
            // Type indicator
            typeHeader
            
            switch data.type {
            case .pay:
                payRequestView
            case .withdraw:
                withdrawRequestView
            case .auth:
                authRequestView
            case .channel:
                channelRequestView
            }
        }
    }
    
    private var typeHeader: some View {
        HStack {
            Image(systemName: data.type.icon)
                .font(.title2)
                .foregroundColor(data.type.color)
            
            VStack(alignment: .leading) {
                Text(data.type.title)
                    .font(.headline)
                Text(data.domain)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(data.type.color.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var payRequestView: some View {
        VStack(spacing: 16) {
            // Description
            if let description = data.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Amount input
            VStack(alignment: .leading, spacing: 8) {
                Text("Amount (sats)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("Enter amount", text: $amount)
                    .textFieldStyle(.roundedBorder)
                
                if let min = data.minSendable, let max = data.maxSendable {
                    Text("Min: \(formatSats(min)) • Max: \(formatSats(max))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Comment if allowed
            if data.commentAllowed > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Comment (optional)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Add a comment", text: $comment)
                        .textFieldStyle(.roundedBorder)
                    
                    Text("\(comment.count)/\(data.commentAllowed)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Pay button
            Button(action: { viewModel.executeLnUrlPay(amount: amount, comment: comment) }) {
                HStack {
                    Image(systemName: "paperplane.fill")
                    Text("Send Payment")
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isValidPayAmount)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var withdrawRequestView: some View {
        VStack(spacing: 16) {
            // Withdraw info
            VStack(spacing: 8) {
                Text("Withdraw Available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let max = data.maxWithdrawable {
                    Text(formatSats(max))
                        .font(.title.bold())
                }
            }
            
            // Withdraw button
            Button(action: { viewModel.executeLnUrlWithdraw() }) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Withdraw to Wallet")
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var authRequestView: some View {
        VStack(spacing: 16) {
            Text("Login Request")
                .font(.headline)
            
            Text("Authenticate with \(data.domain)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button(action: { viewModel.executeLnUrlAuth() }) {
                HStack {
                    Image(systemName: "person.badge.key.fill")
                    Text("Authenticate")
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var channelRequestView: some View {
        VStack(spacing: 16) {
            Text("Channel Request")
                .font(.headline)
            
            Text("Open channel with \(data.domain)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button(action: {}) {
                HStack {
                    Image(systemName: "arrow.left.arrow.right")
                    Text("Open Channel")
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var isValidPayAmount: Bool {
        guard let amountSats = Int(amount) else { return false }
        if let min = data.minSendable, amountSats < min { return false }
        if let max = data.maxSendable, amountSats > max { return false }
        return amountSats > 0
    }
    
    private func formatSats(_ sats: Int) -> String {
        if sats >= 1_000_000 {
            return String(format: "%.2fM sats", Double(sats) / 1_000_000)
        } else if sats >= 1_000 {
            return String(format: "%.1fK sats", Double(sats) / 1_000)
        }
        return "\(sats) sats"
    }
}

// MARK: - QR Scanner Placeholder

struct QRScannerView: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("QR Scanner")
                .font(.headline)
            
            // Placeholder for actual camera view
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black)
                .frame(width: 300, height: 300)
                .overlay {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 100))
                        .foregroundColor(.white.opacity(0.3))
                }
            
            Text("Point camera at QR code")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button("Cancel") {
                dismiss()
            }
        }
        .padding()
    }
}

// MARK: - View Model

@MainActor
class LightningViewModel: ObservableObject {
    @Published var parsedInvoice: ParsedInvoice?
    @Published var lnurlData: LnUrlData?
    @Published var isLoading = false
    @Published var error: String?
    
    func processInput(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        
        isLoading = true
        error = nil
        parsedInvoice = nil
        lnurlData = nil
        
        // Simulate parsing delay
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            let lowercased = trimmed.lowercased()
            
            if lowercased.hasPrefix("lnbc") || lowercased.hasPrefix("lntb") {
                // Parse BOLT11 invoice
                parsedInvoice = ParsedInvoice.mock(from: trimmed)
            } else if lowercased.hasPrefix("lnurl") {
                // Decode LNURL
                lnurlData = LnUrlData.mockPay()
            } else if trimmed.contains("@") {
                // Lightning address - fetch LNURL
                lnurlData = LnUrlData.mockFromAddress(trimmed)
            } else {
                error = "Unrecognized format. Expected BOLT11 invoice, LNURL, or Lightning address."
            }
            
            isLoading = false
        }
    }
    
    func payInvoice() {
        // Would integrate with actual Lightning node/wallet
        print("Paying invoice...")
    }
    
    func executeLnUrlPay(amount: String, comment: String) {
        print("LNUrl Pay: \(amount) sats, comment: \(comment)")
    }
    
    func executeLnUrlWithdraw() {
        print("LNUrl Withdraw")
    }
    
    func executeLnUrlAuth() {
        print("LNUrl Auth")
    }
}

// MARK: - Models

struct ParsedInvoice {
    let raw: String
    let network: String
    let amountMsat: Int?
    let paymentHash: String
    let description: String?
    let payee: String?
    let expirySeconds: Int
    let timestamp: Date
    let minFinalCltvExpiry: Int
    let routeHints: [String]
    
    var formattedAmount: String {
        guard let msat = amountMsat else { return "Any amount" }
        let sats = msat / 1000
        if sats >= 1_000_000 {
            return String(format: "%.2f M sats", Double(sats) / 1_000_000)
        } else if sats >= 1_000 {
            return String(format: "%.1f K sats", Double(sats) / 1_000)
        }
        return "\(sats) sats"
    }
    
    var fiatAmount: String? {
        guard let msat = amountMsat else { return nil }
        let btc = Double(msat) / 100_000_000_000
        let usd = btc * 45000 // Mock exchange rate
        return String(format: "$%.2f USD", usd)
    }
    
    var isExpired: Bool {
        Date() > timestamp.addingTimeInterval(TimeInterval(expirySeconds))
    }
    
    var isExpiringSoon: Bool {
        let remaining = timestamp.addingTimeInterval(TimeInterval(expirySeconds)).timeIntervalSince(Date())
        return remaining > 0 && remaining < 300 // Less than 5 minutes
    }
    
    var expiryText: String {
        let expiry = timestamp.addingTimeInterval(TimeInterval(expirySeconds))
        let remaining = expiry.timeIntervalSince(Date())
        if remaining <= 0 {
            return "Expired"
        } else if remaining < 60 {
            return "Expires in \(Int(remaining))s"
        } else if remaining < 3600 {
            return "Expires in \(Int(remaining / 60))m"
        } else {
            return "Expires in \(Int(remaining / 3600))h"
        }
    }
    
    var timestampFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    static func mock(from raw: String) -> ParsedInvoice {
        ParsedInvoice(
            raw: raw,
            network: raw.lowercased().hasPrefix("lntb") ? "Testnet" : "Mainnet",
            amountMsat: 100_000_000, // 100K sats
            paymentHash: String(raw.suffix(64)),
            description: "Payment for services",
            payee: "03abc...def",
            expirySeconds: 3600,
            timestamp: Date(),
            minFinalCltvExpiry: 18,
            routeHints: []
        )
    }
}

struct LnUrlData {
    let type: LnUrlType
    let domain: String
    let description: String?
    let minSendable: Int?
    let maxSendable: Int?
    let maxWithdrawable: Int?
    let commentAllowed: Int
    let callback: String
    
    static func mockPay() -> LnUrlData {
        LnUrlData(
            type: .pay,
            domain: "example.com",
            description: "Pay for coffee",
            minSendable: 1000,
            maxSendable: 1_000_000,
            maxWithdrawable: nil,
            commentAllowed: 140,
            callback: "https://example.com/lnurl"
        )
    }
    
    static func mockFromAddress(_ address: String) -> LnUrlData {
        let parts = address.split(separator: "@")
        let domain = parts.count > 1 ? String(parts[1]) : "unknown"
        return LnUrlData(
            type: .pay,
            domain: domain,
            description: "Send to \(address)",
            minSendable: 1,
            maxSendable: 100_000_000,
            maxWithdrawable: nil,
            commentAllowed: 280,
            callback: "https://\(domain)/.well-known/lnurlp/\(parts[0])"
        )
    }
}

enum LnUrlType {
    case pay
    case withdraw
    case auth
    case channel
    
    var title: String {
        switch self {
        case .pay: return "Pay Request"
        case .withdraw: return "Withdraw"
        case .auth: return "Login"
        case .channel: return "Channel"
        }
    }
    
    var icon: String {
        switch self {
        case .pay: return "arrow.up.circle.fill"
        case .withdraw: return "arrow.down.circle.fill"
        case .auth: return "person.badge.key.fill"
        case .channel: return "arrow.left.arrow.right"
        }
    }
    
    var color: Color {
        switch self {
        case .pay: return .blue
        case .withdraw: return .green
        case .auth: return .orange
        case .channel: return .purple
        }
    }
}

// MARK: - Previews

struct LightningView_Previews: PreviewProvider {
    static var previews: some View {
        LightningView()
            .frame(width: 500, height: 700)
    }
}
