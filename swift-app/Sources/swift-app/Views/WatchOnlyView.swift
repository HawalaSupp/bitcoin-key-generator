import SwiftUI

struct WatchOnlyView: View {
    @StateObject private var manager = WatchOnlyManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var showAddSheet = false
    @State private var searchText = ""
    @State private var selectedChainFilter: WatchOnlyChain?
    @State private var selectedWallet: WatchOnlyWallet?
    @State private var showEditSheet = false
    
    var filteredWallets: [WatchOnlyWallet] {
        var result = manager.searchWallets(query: searchText)
        if let chain = selectedChainFilter {
            result = result.filter { $0.chain == chain }
        }
        return result.sorted { $0.dateAdded > $1.dateAdded }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Watch-Only Wallets")
                        .font(.title2.bold())
                    Text("Track addresses without private keys")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    Task {
                        await manager.refreshAllBalances()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(manager.isLoading)
                
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Portfolio summary
            if !manager.wallets.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Portfolio Value")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("$\(manager.totalPortfolioValue, specifier: "%.2f")")
                            .font(.title.bold())
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Addresses")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(manager.wallets.count)")
                            .font(.title2.bold())
                    }
                }
                .padding()
                .background(Color.accentColor.opacity(0.1))
            }
            
            // Search and filter
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search wallets...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(8)
                
                Picker("Chain", selection: $selectedChainFilter) {
                    Text("All Chains").tag(nil as WatchOnlyChain?)
                    ForEach(WatchOnlyChain.allCases, id: \.self) { chain in
                        Text(chain.displayName).tag(chain as WatchOnlyChain?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
            .padding()
            
            // Wallet list
            if filteredWallets.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No Watch-Only Wallets")
                        .font(.headline)
                    Text("Add addresses to track balances without importing private keys")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Add Address") {
                        showAddSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredWallets) { wallet in
                            WatchOnlyWalletRow(wallet: wallet) {
                                selectedWallet = wallet
                                showEditSheet = true
                            } onRefresh: {
                                Task {
                                    await manager.refreshBalance(for: wallet.id)
                                }
                            } onDelete: {
                                manager.removeWallet(wallet)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .sheet(isPresented: $showAddSheet) {
            AddWatchOnlyView()
        }
        .sheet(isPresented: $showEditSheet) {
            if let wallet = selectedWallet {
                EditWatchOnlyView(wallet: wallet)
            }
        }
        .overlay {
            if manager.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.2))
            }
        }
    }
}

// MARK: - Wallet Row

struct WatchOnlyWalletRow: View {
    let wallet: WatchOnlyWallet
    let onEdit: () -> Void
    let onRefresh: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    @State private var showDeleteConfirm = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Chain icon
            Image(systemName: wallet.chain.iconName)
                .font(.title)
                .foregroundStyle(chainColor)
                .frame(width: 40, height: 40)
                .background(chainColor.opacity(0.15))
                .clipShape(Circle())
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(wallet.label)
                    .font(.headline)
                
                Text(truncatedAddress)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                
                if let notes = wallet.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Balance
            VStack(alignment: .trailing, spacing: 4) {
                Text(wallet.formattedBalance)
                    .font(.headline.monospaced())
                
                if let updated = wallet.lastBalanceUpdate {
                    Text(updated, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Actions
            if isHovered {
                HStack(spacing: 8) {
                    Button {
                        onRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(wallet.address, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .cornerRadius(12)
        .onHover { isHovered = $0 }
        .alert("Remove Wallet?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("This will stop tracking \(wallet.label). No funds will be affected.")
        }
    }
    
    private var truncatedAddress: String {
        let address = wallet.address
        if address.count > 20 {
            return "\(address.prefix(10))...\(address.suffix(8))"
        }
        return address
    }
    
    private var chainColor: Color {
        switch wallet.chain {
        case .bitcoin: return .orange
        case .ethereum: return .purple
        case .litecoin: return .gray
        case .solana: return .green
        case .bnb: return .yellow
        case .xrp: return .blue
        case .monero: return .orange
        }
    }
}

// MARK: - Add Watch-Only View

struct AddWatchOnlyView: View {
    @StateObject private var manager = WatchOnlyManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var label = ""
    @State private var address = ""
    @State private var selectedChain: WatchOnlyChain = .bitcoin
    @State private var notes = ""
    @State private var error: String?
    @State private var isValidAddress = false
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Add Watch-Only Address")
                    .font(.title2.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Form {
                Picker("Blockchain", selection: $selectedChain) {
                    ForEach(WatchOnlyChain.allCases, id: \.self) { chain in
                        HStack {
                            Image(systemName: chain.iconName)
                            Text(chain.displayName)
                        }
                        .tag(chain)
                    }
                }
                .pickerStyle(.menu)
                
                TextField("Label", text: $label, prompt: Text("e.g., Cold Storage"))
                
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Address", text: $address, prompt: Text("Paste \(selectedChain.displayName) address"))
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: address) { new in
                            validateAddress(new)
                        }
                    
                    if !address.isEmpty {
                        HStack {
                            Image(systemName: isValidAddress ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(isValidAddress ? .green : .red)
                            Text(isValidAddress ? "Valid \(selectedChain.displayName) address" : "Invalid address format")
                                .font(.caption)
                                .foregroundStyle(isValidAddress ? .green : .red)
                        }
                    }
                }
                
                TextField("Notes (optional)", text: $notes, prompt: Text("Add any notes"))
            }
            .formStyle(.grouped)
            
            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Add Address") {
                    addWallet()
                }
                .buttonStyle(.borderedProminent)
                .disabled(label.isEmpty || !isValidAddress)
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 450, height: 350)
        .onChange(of: selectedChain) { _ in
            validateAddress(address)
        }
    }
    
    private func validateAddress(_ address: String) {
        isValidAddress = selectedChain.validateAddress(address)
    }
    
    private func addWallet() {
        do {
            try manager.addWallet(
                label: label,
                address: address,
                chain: selectedChain,
                notes: notes.isEmpty ? nil : notes
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Edit Watch-Only View

struct EditWatchOnlyView: View {
    let wallet: WatchOnlyWallet
    @StateObject private var manager = WatchOnlyManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var label: String
    @State private var notes: String
    
    init(wallet: WatchOnlyWallet) {
        self.wallet = wallet
        _label = State(initialValue: wallet.label)
        _notes = State(initialValue: wallet.notes ?? "")
    }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Edit Watch-Only Wallet")
                    .font(.title2.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Form {
                LabeledContent("Chain") {
                    HStack {
                        Image(systemName: wallet.chain.iconName)
                        Text(wallet.chain.displayName)
                    }
                }
                
                LabeledContent("Address") {
                    Text(wallet.address)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                
                TextField("Label", text: $label)
                
                TextField("Notes", text: $notes, prompt: Text("Add any notes"), axis: .vertical)
                    .lineLimit(3...5)
            }
            .formStyle(.grouped)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Save") {
                    manager.updateWalletLabel(wallet.id, newLabel: label)
                    manager.updateWalletNotes(wallet.id, notes: notes.isEmpty ? nil : notes)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(label.isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 450, height: 320)
    }
}

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    WatchOnlyView()
}
#endif
#endif
#endif
