import SwiftUI

// MARK: - UTXO Coin Control View
/// Visual UTXO explorer with labeling, freezing, and selection

struct UTXOCoinControlView: View {
    @StateObject private var manager = UTXOCoinControlManager.shared
    @Environment(\.dismiss) private var dismiss
    
    let address: String
    let chain: Chain
    var onSelectionComplete: (([ManagedUTXO]) -> Void)?
    
    @State private var selectedUTXOs: Set<ManagedUTXO> = []
    @State private var selectionMode = false
    @State private var searchText = ""
    @State private var sortStrategy: UTXOSelectionStrategy = .optimal
    @State private var showFrozenOnly = false
    @State private var selectedUTXOForEdit: ManagedUTXO?
    @State private var showSourcePicker = false
    @State private var filterSource: UTXOSource?
    
    private var filteredUTXOs: [ManagedUTXO] {
        var utxos = manager.utxos
        
        // Filter by frozen status
        if showFrozenOnly {
            utxos = utxos.filter { $0.metadata.isFrozen }
        }
        
        // Filter by source
        if let source = filterSource {
            utxos = utxos.filter { $0.metadata.source == source }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            utxos = utxos.filter {
                $0.txid.localizedCaseInsensitiveContains(searchText) ||
                $0.metadata.label.localizedCaseInsensitiveContains(searchText) ||
                $0.metadata.note.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Sort
        return utxos.sorted { compareUTXOs($0, $1) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Stats bar
            statsBar
            
            // Toolbar
            toolbar
            
            // Content
            if manager.isLoading {
                loadingView
            } else if manager.utxos.isEmpty {
                emptyState
            } else {
                utxoList
            }
            
            // Selection footer
            if selectionMode && !selectedUTXOs.isEmpty {
                selectionFooter
            }
        }
        .frame(minWidth: 700, minHeight: 600)
        .task {
            await manager.refreshUTXOs(for: address, chain: chain)
        }
        .sheet(item: $selectedUTXOForEdit) { utxo in
            UTXODetailSheet(utxo: utxo, manager: manager)
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("UTXO Coin Control")
                    .font(.title2.bold())
                
                Text(address.prefix(8) + "..." + address.suffix(8))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if selectionMode {
                Button("Done Selecting") {
                    if let callback = onSelectionComplete {
                        callback(Array(selectedUTXOs))
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            
            Button(action: {
                Task {
                    await manager.refreshUTXOs(for: address, chain: chain)
                }
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(manager.isLoading)
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    // MARK: - Stats Bar
    
    private var statsBar: some View {
        HStack(spacing: 24) {
            StatItem(
                title: "Total",
                value: formatBTC(manager.totalBalance),
                icon: "bitcoinsign.circle",
                color: .orange
            )
            
            StatItem(
                title: "Spendable",
                value: formatBTC(manager.spendableBalance),
                icon: "checkmark.circle",
                color: .green
            )
            
            StatItem(
                title: "Frozen",
                value: formatBTC(manager.frozenBalance),
                icon: "snowflake",
                color: .blue
            )
            
            StatItem(
                title: "Privacy Score",
                value: String(format: "%.0f%%", manager.averagePrivacyScore),
                icon: "eye.slash",
                color: privacyScoreColor
            )
            
            StatItem(
                title: "UTXOs",
                value: "\(manager.utxos.count)",
                icon: "square.stack.3d.up",
                color: .purple
            )
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
    }
    
    private var privacyScoreColor: Color {
        let score = manager.averagePrivacyScore
        if score >= 80 { return .green }
        if score >= 60 { return .yellow }
        if score >= 40 { return .orange }
        return .red
    }
    
    // MARK: - Toolbar
    
    private var toolbar: some View {
        HStack(spacing: 12) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search txid, label, or note...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            .frame(maxWidth: 300)
            
            // Sort picker
            Picker("Sort", selection: $sortStrategy) {
                ForEach(UTXOSelectionStrategy.allCases, id: \.self) { strategy in
                    Text(strategy.rawValue).tag(strategy)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)
            
            // Source filter
            Picker("Source", selection: $filterSource) {
                Text("All Sources").tag(nil as UTXOSource?)
                Divider()
                ForEach(UTXOSource.allCases, id: \.self) { source in
                    Label(source.rawValue, systemImage: source.icon)
                        .tag(source as UTXOSource?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)
            
            Spacer()
            
            // Frozen filter toggle
            Toggle("Frozen Only", isOn: $showFrozenOnly)
                .toggleStyle(.checkbox)
            
            // Selection mode toggle
            Toggle("Select Mode", isOn: $selectionMode)
                .toggleStyle(.checkbox)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    // MARK: - UTXO List
    
    private var utxoList: some View {
        List(selection: selectionMode ? $selectedUTXOs : .constant(Set<ManagedUTXO>())) {
            ForEach(filteredUTXOs) { utxo in
                UTXORow(
                    utxo: utxo,
                    isSelected: selectedUTXOs.contains(utxo),
                    onTap: {
                        if selectionMode {
                            if selectedUTXOs.contains(utxo) {
                                selectedUTXOs.remove(utxo)
                            } else if !utxo.metadata.isFrozen {
                                selectedUTXOs.insert(utxo)
                            }
                        } else {
                            selectedUTXOForEdit = utxo
                        }
                    },
                    onFreeze: {
                        manager.setFrozen(!utxo.metadata.isFrozen, for: utxo)
                    }
                )
                .tag(utxo)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }
    
    // MARK: - Selection Footer
    
    private var selectionFooter: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(selectedUTXOs.count) UTXOs selected")
                    .font(.headline)
                
                let totalSelected = selectedUTXOs.reduce(0) { $0 + $1.value }
                Text(formatBTC(totalSelected))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Clear Selection") {
                selectedUTXOs.removeAll()
            }
            .buttonStyle(.bordered)
            
            Button("Use Selected") {
                if let callback = onSelectionComplete {
                    callback(Array(selectedUTXOs))
                }
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.accentColor.opacity(0.1))
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bitcoinsign.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No UTXOs Found")
                .font(.headline)
            
            Text("This address has no unspent outputs")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading UTXOs...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helpers
    
    private func formatBTC(_ sats: UInt64) -> String {
        let btc = Double(sats) / 100_000_000
        if btc >= 0.0001 {
            return String(format: "%.8f BTC", btc)
        } else {
            return "\(sats) sats"
        }
    }
    
    private func compareUTXOs(_ a: ManagedUTXO, _ b: ManagedUTXO) -> Bool {
        switch sortStrategy {
        case .largestFirst: return a.value > b.value
        case .smallestFirst: return a.value < b.value
        case .oldestFirst: return a.confirmations > b.confirmations
        case .newestFirst: return a.confirmations < b.confirmations
        case .privacyOptimized: return a.privacyScore > b.privacyScore
        case .optimal:
            let aScore = Double(a.value) / 100_000 + Double(a.privacyScore)
            let bScore = Double(b.value) / 100_000 + Double(b.privacyScore)
            return aScore > bScore
        }
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(value)
                    .font(.headline)
            }
            .foregroundColor(color)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - UTXO Row

struct UTXORow: View {
    let utxo: ManagedUTXO
    let isSelected: Bool
    let onTap: () -> Void
    let onFreeze: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection indicator
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
            
            // Value
            VStack(alignment: .leading, spacing: 2) {
                Text(utxo.formattedValue)
                    .font(.headline)
                    .foregroundColor(utxo.metadata.isFrozen ? .secondary : .primary)
                
                if !utxo.metadata.label.isEmpty {
                    Text(utxo.metadata.label)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
            .frame(width: 140, alignment: .leading)
            
            Divider().frame(height: 30)
            
            // TXID
            VStack(alignment: .leading, spacing: 2) {
                Text(utxo.shortTxid)
                    .font(.system(.caption, design: .monospaced))
                
                Text("Output #\(utxo.vout)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 150, alignment: .leading)
            
            Divider().frame(height: 30)
            
            // Source
            Label(utxo.metadata.source.rawValue, systemImage: utxo.metadata.source.icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Divider().frame(height: 30)
            
            // Confirmations
            VStack(alignment: .leading, spacing: 2) {
                Text("\(utxo.confirmations)")
                    .font(.subheadline)
                Text("confirms")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 70, alignment: .leading)
            
            Divider().frame(height: 30)
            
            // Privacy Score
            PrivacyScoreBadge(score: utxo.privacyScore)
                .frame(width: 60)
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                Button(action: onFreeze) {
                    Image(systemName: utxo.metadata.isFrozen ? "lock.fill" : "lock.open")
                        .foregroundColor(utxo.metadata.isFrozen ? .blue : .secondary)
                }
                .buttonStyle(.borderless)
                .help(utxo.metadata.isFrozen ? "Unfreeze" : "Freeze")
                
                Button(action: onTap) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("View details")
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .opacity(utxo.metadata.isFrozen ? 0.7 : 1)
    }
}

// MARK: - Privacy Score Badge

struct PrivacyScoreBadge: View {
    let score: Int
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.slash")
                .font(.caption2)
            Text("\(score)")
                .font(.caption.bold())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(scoreColor.opacity(0.2))
        .foregroundColor(scoreColor)
        .cornerRadius(6)
    }
    
    private var scoreColor: Color {
        if score >= 80 { return .green }
        if score >= 60 { return .yellow }
        if score >= 40 { return .orange }
        return .red
    }
}

// MARK: - UTXO Detail Sheet

struct UTXODetailSheet: View {
    let utxo: ManagedUTXO
    let manager: UTXOCoinControlManager
    
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var note: String
    @State private var source: UTXOSource
    
    init(utxo: ManagedUTXO, manager: UTXOCoinControlManager) {
        self.utxo = utxo
        self.manager = manager
        _label = State(initialValue: utxo.metadata.label)
        _note = State(initialValue: utxo.metadata.note)
        _source = State(initialValue: utxo.metadata.source)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("UTXO Details")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    saveChanges()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Value section
                    GroupBox("Value") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(utxo.formattedValue)
                                    .font(.title2.bold())
                                Spacer()
                                PrivacyScoreBadge(score: utxo.privacyScore)
                            }
                            
                            Text("\(utxo.confirmations) confirmations")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Transaction info
                    GroupBox("Transaction") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("TXID") {
                                Text(utxo.txid)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            
                            LabeledContent("Output Index") {
                                Text("\(utxo.vout)")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Metadata
                    GroupBox("Metadata") {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Label (e.g., 'Coinbase payout')", text: $label)
                                .textFieldStyle(.roundedBorder)
                            
                            Picker("Source", selection: $source) {
                                ForEach(UTXOSource.allCases, id: \.self) { src in
                                    Label(src.rawValue, systemImage: src.icon).tag(src)
                                }
                            }
                            .pickerStyle(.menu)
                            
                            Text(source.privacyImpact)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("Notes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TextEditor(text: $note)
                                .frame(height: 80)
                                .font(.body)
                                .padding(4)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    
                    // Actions
                    GroupBox("Actions") {
                        HStack {
                            Button(action: {
                                manager.setFrozen(!utxo.metadata.isFrozen, for: utxo)
                            }) {
                                Label(
                                    utxo.metadata.isFrozen ? "Unfreeze UTXO" : "Freeze UTXO",
                                    systemImage: utxo.metadata.isFrozen ? "lock.open" : "lock"
                                )
                            }
                            .buttonStyle(.bordered)
                            
                            Spacer()
                            
                            Link(destination: URL(string: "https://mempool.space/tx/\(utxo.txid)")!) {
                                Label("View on Explorer", systemImage: "arrow.up.right.square")
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 550)
    }
    
    private func saveChanges() {
        if label != utxo.metadata.label {
            manager.setLabel(label, for: utxo)
        }
        if note != utxo.metadata.note {
            manager.setNote(note, for: utxo)
        }
        if source != utxo.metadata.source {
            manager.setSource(source, for: utxo)
        }
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    UTXOCoinControlView(
        address: "tb1qv629dc9dm623hywx0wrfq3ezfm64yylhh87ty3",
        chain: .bitcoinTestnet
    )
}
#endif
#endif
#endif
