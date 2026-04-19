import SwiftUI

// MARK: - Stealth Address View
// Phase 4.3: UI for managing stealth addresses and payments

struct StealthAddressView: View {
    @StateObject private var manager = StealthAddressManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedChain: StealthChain = .bitcoin
    @State private var selectedTab: StealthTab = .receive
    @State private var showGenerateSheet = false
    @State private var showSendSheet = false
    @State private var showSettingsSheet = false
    @State private var showKeyPairDetail: StealthKeyPair?
    @State private var showPaymentDetail: StealthPayment?
    @State private var searchText = ""
    
    enum StealthTab: String, CaseIterable {
        case receive = "Receive"
        case send = "Send"
        case history = "History"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            HSplitView {
                // Sidebar
                sidebarView
                    .frame(minWidth: 200, maxWidth: 250)
                
                // Main Content
                VStack(spacing: 0) {
                    // Tab Bar
                    tabBarView
                    
                    Divider()
                    
                    // Content based on selected tab
                    switch selectedTab {
                    case .receive:
                        receiveTabView
                    case .send:
                        sendTabView
                    case .history:
                        historyTabView
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $showGenerateSheet) {
            GenerateStealthKeySheet(chain: selectedChain)
        }
        .sheet(isPresented: $showSendSheet) {
            SendStealthPaymentSheet(chain: selectedChain)
        }
        .sheet(isPresented: $showSettingsSheet) {
            StealthSettingsSheet()
        }
        .sheet(item: $showKeyPairDetail) { keyPair in
            KeyPairDetailSheet(keyPair: keyPair)
        }
        .sheet(item: $showPaymentDetail) { payment in
            PaymentDetailSheet(payment: payment)
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Stealth Addresses")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Enhanced privacy with one-time addresses")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Scan Status
            if manager.isScanningBlockchain {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(LoadingCopy.stealth)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Action Buttons
            Button(action: { showGenerateSheet = true }) {
                Label("New Keys", systemImage: "key.fill")
            }
            .buttonStyle(.borderedProminent)
            
            Button(action: { showSettingsSheet = true }) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.bordered)
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    // MARK: - Sidebar
    
    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Chain Selector
            VStack(alignment: .leading, spacing: 8) {
                Text("CHAINS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                
                ForEach(StealthChain.allCases) { chain in
                    ChainRowView(
                        chain: chain,
                        isSelected: selectedChain == chain,
                        stats: manager.getStatistics(for: chain)
                    )
                    .onTapGesture {
                        selectedChain = chain
                    }
                }
            }
            .padding(.vertical, 12)
            
            Divider()
            
            // Statistics
            VStack(alignment: .leading, spacing: 8) {
                Text("STATISTICS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                
                let stats = manager.getStatistics(for: selectedChain)
                StatRowView(label: "Key Pairs", value: "\(stats.keyPairCount)")
                StatRowView(label: "Received", value: "\(stats.receivedPayments)")
                StatRowView(label: "Unspent", value: "\(stats.unspentPayments)")
                StatRowView(label: "Sent", value: "\(stats.outgoingPayments)")
            }
            .padding(.vertical, 12)
            
            Divider()
            
            // Scan Progress
            if let progress = manager.scanProgress[selectedChain] {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SCAN STATUS")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        if progress.isScanning {
                            ProgressView(value: progress.progress)
                                .progressViewStyle(.linear)
                            Text(progress.progressPercentage)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Last scan: \(progress.lastScanDate?.formatted(.relative(presentation: .named)) ?? "Never")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button("Scan Now") {
                                Task {
                                    await manager.scanForPayments(chain: selectedChain)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.vertical, 12)
            }
            
            Spacer()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Tab Bar
    
    private var tabBarView: some View {
        HStack(spacing: 0) {
            ForEach(StealthTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    VStack(spacing: 4) {
                        Image(systemName: tabIcon(for: tab))
                            .font(.system(size: 16))
                        Text(tab.rawValue)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                    .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func tabIcon(for tab: StealthTab) -> String {
        switch tab {
        case .receive: return "arrow.down.circle"
        case .send: return "arrow.up.circle"
        case .history: return "clock"
        }
    }
    
    // MARK: - Receive Tab
    
    private var receiveTabView: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search key pairs...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .padding()
            
            if filteredKeyPairs.isEmpty {
                emptyKeyPairsView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredKeyPairs) { keyPair in
                            KeyPairCardView(keyPair: keyPair)
                                .onTapGesture {
                                    showKeyPairDetail = keyPair
                                }
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    private var filteredKeyPairs: [StealthKeyPair] {
        let chainKeyPairs = manager.keyPairs.filter { $0.chain == selectedChain }
        
        if searchText.isEmpty {
            return chainKeyPairs
        }
        
        return chainKeyPairs.filter {
            $0.label?.localizedCaseInsensitiveContains(searchText) == true ||
            $0.metaAddress.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var emptyKeyPairsView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "key.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Stealth Keys")
                .font(.headline)
            
            Text("Generate a stealth key pair to receive private payments on \(selectedChain.displayName)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            
            Button(action: { showGenerateSheet = true }) {
                Label("Generate Keys", systemImage: "key.fill")
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
        }
    }
    
    // MARK: - Send Tab
    
    private var sendTabView: some View {
        VStack(spacing: 0) {
            // Quick Send
            VStack(alignment: .leading, spacing: 12) {
                Text("Send to Stealth Address")
                    .font(.headline)
                
                Text("Enter a recipient's stealth meta-address to generate a one-time address for private payment.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button(action: { showSendSheet = true }) {
                    Label("New Stealth Payment", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Outgoing Payments
            if outgoingPaymentsForChain.isEmpty {
                emptyOutgoingView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(outgoingPaymentsForChain) { payment in
                            OutgoingPaymentCardView(payment: payment)
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    private var outgoingPaymentsForChain: [OutgoingStealthPayment] {
        manager.outgoingPayments
            .filter { $0.chain == selectedChain }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    private var emptyOutgoingView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "arrow.up.circle.badge.clock")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Outgoing Payments")
                .font(.headline)
            
            Text("You haven't sent any stealth payments on \(selectedChain.displayName) yet.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            
            Spacer()
        }
    }
    
    // MARK: - History Tab
    
    private var historyTabView: some View {
        VStack(spacing: 0) {
            // Filter
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search payments...", text: $searchText)
                    .textFieldStyle(.plain)
                
                Spacer()
                
                Picker("Filter", selection: .constant("All")) {
                    Text("All").tag("All")
                    Text("Unspent").tag("Unspent")
                    Text("Spent").tag("Spent")
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .padding()
            
            if receivedPaymentsForChain.isEmpty {
                emptyReceivedView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(receivedPaymentsForChain) { payment in
                            ReceivedPaymentCardView(payment: payment)
                                .onTapGesture {
                                    showPaymentDetail = payment
                                }
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    private var receivedPaymentsForChain: [StealthPayment] {
        manager.receivedPayments
            .filter { $0.chain == selectedChain }
            .sorted { $0.detectedAt > $1.detectedAt }
    }
    
    private var emptyReceivedView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Payments Found")
                .font(.headline)
            
            Text("No stealth payments have been detected for \(selectedChain.displayName). Make sure to scan the blockchain regularly.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            
            Button("Scan Blockchain") {
                Task {
                    await manager.scanForPayments(chain: selectedChain)
                }
            }
            .buttonStyle(.bordered)
            
            Spacer()
        }
    }
}

// MARK: - Supporting Views

struct ChainRowView: View {
    let chain: StealthChain
    let isSelected: Bool
    let stats: StealthStatistics
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: chain.icon)
                .font(.system(size: 20))
                .foregroundColor(chainColor)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(chain.displayName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                
                Text("\(stats.keyPairCount) key\(stats.keyPairCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if stats.unspentPayments > 0 {
                Text("\(stats.unspentPayments)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green)
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .padding(.horizontal, 8)
    }
    
    private var chainColor: Color {
        switch chain.color {
        case "orange": return .orange
        case "purple": return .purple
        case "gray": return .gray
        default: return .blue
        }
    }
}

struct StatRowView: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 12)
    }
}

struct KeyPairCardView: View {
    let keyPair: StealthKeyPair
    @State private var isCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if keyPair.isDefault {
                    Label("Default", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                if let label = keyPair.label {
                    Text(label)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                Text(keyPair.createdAt, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Meta Address
            VStack(alignment: .leading, spacing: 4) {
                Text("Stealth Meta-Address")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text(keyPair.metaAddress)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    Button(action: {
                        ClipboardHelper.copySensitive(keyPair.metaAddress, timeout: 60)
                        isCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            isCopied = false
                        }
                    }) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .foregroundColor(isCopied ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            
            // Quick Actions
            HStack {
                Button(action: {}) {
                    Label("QR Code", systemImage: "qrcode")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: {}) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct OutgoingPaymentCardView: View {
    let payment: OutgoingStealthPayment
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(payment.oneTimeAddress)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    statusBadge
                }
                
                Text(payment.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if payment.amount > 0 {
                Text(formatAmount(payment.amount, chain: payment.chain))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var statusBadge: some View {
        Text(payment.status.rawValue)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor)
            .cornerRadius(4)
    }
    
    private var statusColor: Color {
        switch payment.status {
        case .pending: return .orange
        case .broadcast: return .blue
        case .confirmed: return .green
        case .failed: return .red
        }
    }
    
    private func formatAmount(_ amount: UInt64, chain: StealthChain) -> String {
        switch chain {
        case .bitcoin, .litecoin:
            return String(format: "%.8f %@", Double(amount) / 100_000_000, chain.rawValue)
        case .ethereum:
            return String(format: "%.6f %@", Double(amount) / 1_000_000_000_000_000_000, chain.rawValue)
        }
    }
}

struct ReceivedPaymentCardView: View {
    let payment: StealthPayment
    
    var body: some View {
        HStack {
            Circle()
                .fill(payment.isSpent ? Color.gray : Color.green)
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(payment.oneTimeAddress)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                HStack {
                    Text(payment.detectedAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let note = payment.note, !note.isEmpty {
                        Text("• \(note)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatAmount(payment.amount, chain: payment.chain))
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(payment.isSpent ? "Spent" : "Unspent")
                    .font(.caption)
                    .foregroundColor(payment.isSpent ? .secondary : .green)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func formatAmount(_ amount: UInt64, chain: StealthChain) -> String {
        switch chain {
        case .bitcoin, .litecoin:
            return String(format: "%.8f %@", Double(amount) / 100_000_000, chain.rawValue)
        case .ethereum:
            return String(format: "%.6f %@", Double(amount) / 1_000_000_000_000_000_000, chain.rawValue)
        }
    }
}

// MARK: - Sheets

struct GenerateStealthKeySheet: View {
    let chain: StealthChain
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = StealthAddressManager.shared
    
    @State private var label = ""
    @State private var isGenerating = false
    @State private var generatedKeyPair: StealthKeyPair?
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Generate Stealth Keys")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Create a new key pair for \(chain.displayName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            if let keyPair = generatedKeyPair {
                // Success State
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    
                    Text("Keys Generated Successfully!")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Stealth Meta-Address:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text(keyPair.metaAddress)
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                        
                        Text("Share this address with senders. They will generate unique one-time addresses for each payment.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                // Input State
                VStack(alignment: .leading, spacing: 16) {
                    // Label Input
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Label (Optional)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        TextField("e.g., Personal, Business", text: $label)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // Info
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(icon: "key.fill", text: "Generates spending and viewing key pair")
                        InfoRow(icon: "eye.slash", text: "Viewing key allows scanning without spending access")
                        InfoRow(icon: "arrow.triangle.branch", text: "Each payment creates a unique one-time address")
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                Spacer()
                
                // Action Buttons
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button(action: generateKeys) {
                        if isGenerating {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Label("Generate Keys", systemImage: "key.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating)
                }
            }
        }
        .padding()
        .frame(width: 450, height: 400)
    }
    
    private func generateKeys() {
        isGenerating = true
        errorMessage = nil
        
        Task {
            do {
                generatedKeyPair = try await manager.generateKeyPair(
                    for: chain,
                    label: label.isEmpty ? nil : label
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }
}

struct SendStealthPaymentSheet: View {
    let chain: StealthChain
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = StealthAddressManager.shared
    
    @State private var metaAddress = ""
    @State private var amount = ""
    @State private var label = ""
    @State private var computedPayment: OutgoingStealthPayment?
    @State private var isComputing = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Send Stealth Payment")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Generate a one-time address for private payment")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            if let payment = computedPayment {
                // Computed Address
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    
                    Text("One-Time Address Generated!")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Send \(chain.rawValue) to this address:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            Text(payment.oneTimeAddress)
                                .font(.system(.caption, design: .monospaced))
                            
                            Button(action: {
                                ClipboardHelper.copySensitive(payment.oneTimeAddress, timeout: 60)
                            }) {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding()
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        
                        Text("This address can only be spent by the recipient. The ephemeral public key is embedded in the transaction for them to detect.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Button("Generate Another") {
                            computedPayment = nil
                            metaAddress = ""
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Done") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                // Input Form
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recipient's Stealth Meta-Address")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        TextField("st:\(chain.rawValue.lowercased()):...", text: $metaAddress)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Label (Optional)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        TextField("e.g., Payment to Alice", text: $label)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                Spacer()
                
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button(action: computeAddress) {
                        if isComputing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Label("Compute Address", systemImage: "arrow.right.circle.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(metaAddress.isEmpty || isComputing)
                }
            }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
    
    private func computeAddress() {
        isComputing = true
        errorMessage = nil
        
        Task {
            do {
                computedPayment = try manager.computeStealthAddress(for: metaAddress)
            } catch {
                errorMessage = error.localizedDescription
            }
            isComputing = false
        }
    }
}

struct StealthSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = StealthAddressManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Stealth Address Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            Form {
                Section("Scanning") {
                    Toggle("Auto-scan for payments", isOn: $manager.autoScanEnabled)
                    
                    if manager.autoScanEnabled {
                        Picker("Scan interval", selection: $manager.scanIntervalMinutes) {
                            Text("5 minutes").tag(5)
                            Text("15 minutes").tag(15)
                            Text("30 minutes").tag(30)
                            Text("1 hour").tag(60)
                        }
                    }
                }
                
                Section("Notifications") {
                    Toggle("Notify on new payment", isOn: $manager.notifyOnPayment)
                }
                
                Section("Privacy") {
                    Text("Stealth addresses use ECDH key exchange to derive unique one-time addresses for each payment, preventing address reuse and blockchain analysis.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
            
            Spacer()
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 400, height: 400)
    }
}

struct KeyPairDetailSheet: View {
    let keyPair: StealthKeyPair
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = StealthAddressManager.shared
    
    @State private var editedLabel = ""
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Key Pair Details")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Label
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Label")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            TextField("Enter label", text: $editedLabel)
                                .textFieldStyle(.roundedBorder)
                            
                            Button("Save") {
                                manager.updateKeyPairLabel(keyPair, label: editedLabel.isEmpty ? nil : editedLabel)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    // Meta Address
                    DetailSection(title: "Stealth Meta-Address", value: keyPair.metaAddress, isMonospace: true)
                    
                    // Public Keys
                    DetailSection(title: "Spending Public Key", value: keyPair.spendingPublicKey.hexString, isMonospace: true)
                    DetailSection(title: "Viewing Public Key", value: keyPair.viewingPublicKey.hexString, isMonospace: true)
                    
                    // Metadata
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Created")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(keyPair.createdAt, style: .date)
                                .font(.subheadline)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("Chain")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(keyPair.chain.displayName)
                                .font(.subheadline)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    
                    // Actions
                    HStack {
                        if !keyPair.isDefault {
                            Button("Set as Default") {
                                manager.setDefaultKeyPair(keyPair)
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Spacer()
                        
                        Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding()
        .frame(width: 500, height: 500)
        .onAppear {
            editedLabel = keyPair.label ?? ""
        }
        .alert("Delete Key Pair?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                do {
                    try manager.deleteKeyPair(keyPair)
                    dismiss()
                } catch {
                    // Show error
                }
            }
        } message: {
            Text("This will permanently delete this key pair. Make sure all funds have been spent.")
        }
    }
}

struct PaymentDetailSheet: View {
    let payment: StealthPayment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = StealthAddressManager.shared
    
    @State private var note = ""
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Payment Details")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Status
                    HStack {
                        Circle()
                            .fill(payment.isSpent ? Color.gray : Color.green)
                            .frame(width: 12, height: 12)
                        
                        Text(payment.isSpent ? "Spent" : "Unspent")
                            .font(.headline)
                            .foregroundColor(payment.isSpent ? .secondary : .green)
                        
                        Spacer()
                        
                        Text(formatAmount(payment.amount))
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    
                    // Address
                    DetailSection(title: "One-Time Address", value: payment.oneTimeAddress, isMonospace: true)
                    
                    // Transaction
                    if !payment.txHash.isEmpty {
                        DetailSection(title: "Transaction Hash", value: payment.txHash, isMonospace: true)
                    }
                    
                    // Note
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Note")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            TextField("Add a note...", text: $note)
                                .textFieldStyle(.roundedBorder)
                            
                            Button("Save") {
                                manager.updatePaymentNote(payment, note: note.isEmpty ? nil : note)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    // Metadata
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Detected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(payment.detectedAt, style: .date)
                                .font(.subheadline)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("Block Height")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("#\(payment.blockHeight)")
                                .font(.subheadline)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .frame(width: 500, height: 450)
        .onAppear {
            note = payment.note ?? ""
        }
    }
    
    private func formatAmount(_ amount: UInt64) -> String {
        switch payment.chain {
        case .bitcoin, .litecoin:
            return String(format: "%.8f %@", Double(amount) / 100_000_000, payment.chain.rawValue)
        case .ethereum:
            return String(format: "%.6f %@", Double(amount) / 1_000_000_000_000_000_000, payment.chain.rawValue)
        }
    }
}

struct DetailSection: View {
    let title: String
    let value: String
    var isMonospace: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack {
                Text(value)
                    .font(isMonospace ? .system(.caption, design: .monospaced) : .caption)
                    .lineLimit(2)
                    .truncationMode(.middle)
                
                Spacer()
                
                Button(action: {
                    ClipboardHelper.copySensitive(value, timeout: 60)
                }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
        }
    }
}

struct InfoRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(text)
                .font(.caption)
        }
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    StealthAddressView()
}
#endif
#endif
#endif
