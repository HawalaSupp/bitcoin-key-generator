import SwiftUI

// MARK: - Address Intelligence View
// Phase 5.4: Smart Transaction Features - Address Intelligence

struct AddressIntelligenceView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = AddressIntelligenceManager.shared
    
    @State private var addressInput: String = ""
    @State private var analysis: AddressAnalysis?
    @State private var isAnalyzing = false
    @State private var showLabelEditor = false
    @State private var labelText = ""
    @State private var notesText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            // Content
            ScrollView {
                VStack(spacing: 20) {
                    // Address Input
                    addressInputSection
                    
                    // Analysis Results
                    if let analysis = analysis {
                        analysisResultsSection(analysis)
                    } else if isAnalyzing {
                        loadingSection
                    } else {
                        emptyStateSection
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 550, minHeight: 650)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showLabelEditor) {
            labelEditorSheet
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Address Intelligence")
                    .font(.title2.bold())
                Text("Analyze addresses for risks and information")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Address Input
    
    private var addressInputSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Enter address to analyze...", text: $addressInput)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit {
                            analyzeAddress()
                        }
                    
                    if !addressInput.isEmpty {
                        Button(action: { addressInput = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button("Analyze") {
                        analyzeAddress()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(addressInput.isEmpty || isAnalyzing)
                }
                
                // Quick actions
                HStack(spacing: 12) {
                    Button(action: pasteFromClipboard) {
                        Label("Paste", systemImage: "doc.on.clipboard")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    
                    if let analysis = analysis {
                        Button(action: { showLabelEditor = true }) {
                            Label(analysis.savedLabel != nil ? "Edit Label" : "Add Label", systemImage: "tag")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Spacer()
                    
                    // Detected blockchain
                    if !addressInput.isEmpty {
                        let blockchain = AddressBlockchain.detect(from: addressInput)
                        HStack(spacing: 4) {
                            Image(systemName: blockchainIcon(blockchain))
                                .font(.caption)
                            Text(blockchain.rawValue)
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Analysis Results
    
    private func analysisResultsSection(_ analysis: AddressAnalysis) -> some View {
        VStack(spacing: 16) {
            // Risk Summary Card
            riskSummaryCard(analysis)
            
            // Address Details Card
            addressDetailsCard(analysis)
            
            // Risk Factors
            if !analysis.riskFactors.isEmpty {
                riskFactorsCard(analysis)
            }
            
            // Known Service Info
            if let service = analysis.knownService {
                knownServiceCard(service)
            }
            
            // User History
            userHistoryCard(analysis)
            
            // Actions
            actionsSection(analysis)
        }
    }
    
    private func riskSummaryCard(_ analysis: AddressAnalysis) -> some View {
        GroupBox {
            HStack(spacing: 16) {
                // Risk Icon
                ZStack {
                    Circle()
                        .fill(riskColor(analysis.riskLevel).opacity(0.2))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: analysis.riskLevel.icon)
                        .font(.title)
                        .foregroundColor(riskColor(analysis.riskLevel))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(analysis.riskLevel.rawValue)
                        .font(.title2.bold())
                        .foregroundColor(riskColor(analysis.riskLevel))
                    
                    Text(riskDescription(analysis.riskLevel))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Validation badges
                VStack(alignment: .trailing, spacing: 6) {
                    validationBadge(
                        "Valid Format",
                        isValid: analysis.isValid,
                        icon: "checkmark.circle"
                    )
                    
                    if let checksumValid = analysis.checksumValid {
                        validationBadge(
                            "Checksum",
                            isValid: checksumValid,
                            icon: "checkmark.seal"
                        )
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private func validationBadge(_ title: String, isValid: Bool, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: isValid ? icon + ".fill" : "xmark.circle.fill")
                .font(.caption)
            Text(title)
                .font(.caption)
        }
        .foregroundColor(isValid ? .green : .red)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(isValid ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(4)
    }
    
    private func addressDetailsCard(_ analysis: AddressAnalysis) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Address Details")
                        .font(.headline)
                    Spacer()
                    if let label = analysis.savedLabel {
                        Text(label)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                AddressDetailRow(
                    icon: "link",
                    label: "Blockchain",
                    value: analysis.blockchain.rawValue
                )
                
                AddressDetailRow(
                    icon: "doc.text",
                    label: "Address",
                    value: analysis.address,
                    isMonospaced: true,
                    canCopy: true
                )
                
                if analysis.transactionCount > 0 {
                    AddressDetailRow(
                        icon: "arrow.left.arrow.right",
                        label: "Transactions",
                        value: "\(analysis.transactionCount)"
                    )
                }
                
                if let firstSeen = analysis.firstSeen {
                    AddressDetailRow(
                        icon: "calendar",
                        label: "First Seen",
                        value: formatDate(firstSeen)
                    )
                }
                
                if analysis.isContract {
                    AddressDetailRow(
                        icon: "doc.text.fill",
                        label: "Type",
                        value: "Smart Contract"
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private func riskFactorsCard(_ analysis: AddressAnalysis) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Risk Factors")
                        .font(.headline)
                    Spacer()
                    Text("\(analysis.riskFactors.count)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(4)
                }
                
                ForEach(analysis.riskFactors) { factor in
                    RiskFactorRow(factor: factor)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private func knownServiceCard(_ service: KnownService) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: service.type.icon)
                        .foregroundColor(.blue)
                    Text("Known Service")
                        .font(.headline)
                    Spacer()
                    if service.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.blue)
                    }
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.name)
                            .font(.title3.bold())
                        
                        Text(service.type.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if let website = service.website {
                        Button(action: {
                            if let url = URL(string: "https://\(website)") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Label(website, systemImage: "arrow.up.right.square")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                if let warning = service.riskWarning {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(warning)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private func userHistoryCard(_ analysis: AddressAnalysis) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.secondary)
                    Text("Your History")
                        .font(.headline)
                    Spacer()
                }
                
                if analysis.previouslySentTo {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Previously sent to this address")
                                .font(.subheadline)
                            if analysis.previouslySentCount > 0 {
                                Text("\(analysis.previouslySentCount) transaction\(analysis.previouslySentCount == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let lastSent = analysis.lastSentDate {
                                Text("Last: \(formatDate(lastSent))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundColor(.orange)
                        Text("First time sending to this address")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private func actionsSection(_ analysis: AddressAnalysis) -> some View {
        HStack(spacing: 12) {
            Button(action: { showLabelEditor = true }) {
                Label(analysis.savedLabel != nil ? "Edit Label" : "Add Label", systemImage: "tag")
            }
            .buttonStyle(.bordered)
            
            if !analysis.isScamReported {
                Button(action: { reportAsScam(analysis.address) }) {
                    Label("Report Scam", systemImage: "exclamationmark.shield")
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
            
            Spacer()
            
            Button(action: { copyAddress(analysis.address) }) {
                Label("Copy Address", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
        }
    }
    
    // MARK: - Empty/Loading States
    
    private var loadingSection: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Analyzing address...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    private var emptyStateSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("Enter an address to analyze")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Get risk analysis, service identification, and validation")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Label Editor Sheet
    
    private var labelEditorSheet: some View {
        VStack(spacing: 20) {
            Text(analysis?.savedLabel != nil ? "Edit Address Label" : "Add Address Label")
                .font(.title2.bold())
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Label")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("e.g., My Exchange, Alice's Wallet", text: $labelText)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes (optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $notesText)
                    .frame(height: 80)
                    .border(Color.secondary.opacity(0.2))
            }
            
            HStack {
                Button("Cancel") {
                    showLabelEditor = false
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                if analysis?.savedLabel != nil {
                    Button("Remove") {
                        if let address = analysis?.address {
                            manager.removeLabel(for: address)
                            refreshAnalysis()
                        }
                        showLabelEditor = false
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
                
                Button("Save") {
                    if let address = analysis?.address {
                        manager.setLabel(
                            for: address,
                            label: labelText,
                            notes: notesText.isEmpty ? nil : notesText
                        )
                        refreshAnalysis()
                    }
                    showLabelEditor = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(labelText.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            if let analysis = analysis {
                labelText = analysis.savedLabel ?? ""
                if let labelInfo = manager.addressLabels[analysis.address.lowercased()] {
                    notesText = labelInfo.notes ?? ""
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func analyzeAddress() {
        guard !addressInput.isEmpty else { return }
        
        isAnalyzing = true
        Task {
            let result = await manager.analyzeAddress(addressInput)
            await MainActor.run {
                self.analysis = result
                self.isAnalyzing = false
            }
        }
    }
    
    private func refreshAnalysis() {
        guard let address = analysis?.address else { return }
        Task {
            let result = await manager.analyzeAddress(address)
            await MainActor.run {
                self.analysis = result
            }
        }
    }
    
    private func pasteFromClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            addressInput = string.trimmingCharacters(in: .whitespacesAndNewlines)
            analyzeAddress()
        }
    }
    
    private func copyAddress(_ address: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
        ToastManager.shared.success("Address copied!")
    }
    
    private func reportAsScam(_ address: String) {
        manager.reportScam(address)
        ToastManager.shared.success("Address reported as scam")
        refreshAnalysis()
    }
    
    private func riskColor(_ level: AddressRiskLevel) -> Color {
        switch level {
        case .safe: return .green
        case .low: return .blue
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }
    
    private func riskDescription(_ level: AddressRiskLevel) -> String {
        switch level {
        case .safe: return "This address appears safe to use"
        case .low: return "Minor concerns - proceed with caution"
        case .medium: return "Some risk factors detected"
        case .high: return "Significant risks - verify carefully"
        case .critical: return "Critical risk - do not proceed"
        }
    }
    
    private func blockchainIcon(_ blockchain: AddressBlockchain) -> String {
        switch blockchain {
        case .bitcoin: return "bitcoinsign.circle"
        case .ethereum: return "e.circle"
        case .litecoin: return "l.circle"
        case .solana: return "s.circle"
        case .xrp: return "x.circle"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Views

struct AddressDetailRow: View {
    let icon: String
    let label: String
    let value: String
    var isMonospaced: Bool = false
    var canCopy: Bool = false
    
    @State private var showCopied = false
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            if isMonospaced {
                Text(truncateAddress(value))
                    .font(.system(.caption, design: .monospaced))
            } else {
                Text(value)
                    .font(.subheadline)
            }
            
            if canCopy {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                    withAnimation {
                        showCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            showCopied = false
                        }
                    }
                }) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(showCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func truncateAddress(_ address: String) -> String {
        guard address.count > 20 else { return address }
        return "\(address.prefix(10))...\(address.suffix(8))"
    }
}

struct RiskFactorRow: View {
    let factor: RiskFactor
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: factor.level.icon)
                .foregroundColor(riskColor(factor.level))
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(factor.title)
                    .font(.subheadline.bold())
                
                Text(factor.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let recommendation = factor.recommendation {
                    Text("→ \(recommendation)")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func riskColor(_ level: AddressRiskLevel) -> Color {
        switch level {
        case .safe: return .green
        case .low: return .blue
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Send Flow Integration Component

/// Address validation badge for send flow
struct AddressValidationBadge: View {
    let address: String
    @StateObject private var manager = AddressIntelligenceManager.shared
    @State private var analysis: AddressAnalysis?
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if isLoading {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Checking...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let analysis = analysis {
                Button(action: {}) {
                    HStack(spacing: 4) {
                        Image(systemName: analysis.riskLevel.icon)
                            .font(.caption)
                        Text(analysis.savedLabel ?? analysis.knownService?.name ?? analysis.riskLevel.rawValue)
                            .font(.caption)
                    }
                    .foregroundColor(riskColor(analysis.riskLevel))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(riskColor(analysis.riskLevel).opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help(riskTooltip(analysis))
            }
        }
        .onChange(of: address) { newValue in
            checkAddress(newValue)
        }
        .onAppear {
            checkAddress(address)
        }
    }
    
    private func checkAddress(_ addr: String) {
        guard !addr.isEmpty, addr.count > 10 else {
            analysis = nil
            return
        }
        
        isLoading = true
        Task {
            let result = await manager.analyzeAddress(addr)
            await MainActor.run {
                self.analysis = result
                self.isLoading = false
            }
        }
    }
    
    private func riskColor(_ level: AddressRiskLevel) -> Color {
        switch level {
        case .safe: return .green
        case .low: return .blue
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }
    
    private func riskTooltip(_ analysis: AddressAnalysis) -> String {
        var tooltip = analysis.riskLevel.rawValue
        if analysis.previouslySentTo {
            tooltip += " • Previously used"
        }
        if let service = analysis.knownService {
            tooltip += " • \(service.name)"
        }
        if !analysis.riskFactors.isEmpty {
            tooltip += " • \(analysis.riskFactors.count) risk factor(s)"
        }
        return tooltip
    }
}

/// First-time send warning alert
struct FirstTimeSendWarning: View {
    let address: String
    let onProceed: () -> Void
    let onCancel: () -> Void
    
    @StateObject private var manager = AddressIntelligenceManager.shared
    @State private var analysis: AddressAnalysis?
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("First Time Sending")
                .font(.title2.bold())
            
            Text("You have never sent to this address before. Please verify it is correct.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            // Address preview
            GroupBox {
                VStack(spacing: 8) {
                    Text(truncateMiddle(address))
                        .font(.system(.body, design: .monospaced))
                    
                    if let analysis = analysis {
                        HStack(spacing: 4) {
                            Image(systemName: analysis.riskLevel.icon)
                            Text(analysis.riskLevel.rawValue)
                        }
                        .foregroundColor(riskColor(analysis.riskLevel))
                        .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            
            Text("Tip: Consider sending a small test amount first")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape)
                
                Button("I Verified the Address") {
                    onProceed()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            Task {
                analysis = await manager.analyzeAddress(address)
            }
        }
    }
    
    private func truncateMiddle(_ str: String) -> String {
        guard str.count > 20 else { return str }
        return "\(str.prefix(12))...\(str.suffix(10))"
    }
    
    private func riskColor(_ level: AddressRiskLevel) -> Color {
        switch level {
        case .safe: return .green
        case .low: return .blue
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Preview

#Preview {
    AddressIntelligenceView()
}
