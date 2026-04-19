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
        HawalaSheetShell(title: "Watch-Only Wallets", width: 600, height: 560) {
            // Portfolio summary
            if !manager.wallets.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Portfolio Value")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.35))
                        Text("$\(manager.totalPortfolioValue, specifier: "%.2f")")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Addresses")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.35))
                        Text("\(manager.wallets.count)")
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .hawalaSectionCard()
            }
            
            // Search and filter
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.25))
                    TextField("Search wallets...", text: $searchText)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Picker("Chain", selection: $selectedChainFilter) {
                    Text("All Chains").tag(nil as WatchOnlyChain?)
                    ForEach(WatchOnlyChain.allCases, id: \.self) { chain in
                        Text(chain.displayName).tag(chain as WatchOnlyChain?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)

                Button {
                    Task { await manager.refreshAllBalances() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .disabled(manager.isLoading)

                Button { showAddSheet = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            
            // Wallet list
            if filteredWallets.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.15))
                    Text("No Watch-Only Wallets")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                    Text("Add addresses to track balances without importing private keys")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                    HawalaActionButton(icon: "plus.circle", label: "Add Address", style: .primary) {
                        showAddSheet = true
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredWallets) { wallet in
                            WatchOnlyWalletRow(wallet: wallet) {
                                selectedWallet = wallet
                                showEditSheet = true
                            } onRefresh: {
                                Task { await manager.refreshBalance(for: wallet.id) }
                            } onDelete: {
                                manager.removeWallet(wallet)
                            }
                        }
                    }
                }
            }
        }
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
                    .scaleEffect(1.2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.3))
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
        HStack(spacing: 10) {
            // Chain icon
            Image(systemName: wallet.chain.iconName)
                .font(.system(size: 16))
                .foregroundStyle(chainColor)
                .frame(width: 32, height: 32)
                .background(chainColor.opacity(0.1))
                .clipShape(Circle())
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(wallet.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                
                Text(truncatedAddress)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                
                if let notes = wallet.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.2))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Balance
            VStack(alignment: .trailing, spacing: 2) {
                Text(wallet.formattedBalance)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                
                if let updated = wallet.lastBalanceUpdate {
                    Text(updated, style: .relative)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.25))
                }
            }
            
            // Actions
            if isHovered {
                HStack(spacing: 6) {
                    Button { onRefresh() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    
                    Button { ClipboardHelper.copySensitive(wallet.address, timeout: 60) } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    
                    Button { onEdit() } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    
                    Button { showDeleteConfirm = true } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color.white.opacity(0.06) : Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.white.opacity(0.04), lineWidth: 1)
                )
        )
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
        case .solana: return Color(red: 0.20, green: 0.84, blue: 0.29)
        case .bnb: return Color(red: 1, green: 0.84, blue: 0.04)
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
        HawalaSheetShell(title: "Add Watch-Only Address", width: 450, height: 380) {
            VStack(alignment: .leading, spacing: 8) {
                HawalaOverlaySectionHeader(icon: "link", title: "Blockchain")
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
            }
            .hawalaSectionCard()

            VStack(alignment: .leading, spacing: 8) {
                HawalaOverlaySectionHeader(icon: "textformat", title: "Details")
                TextField("Label", text: $label, prompt: Text("e.g., Cold Storage"))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Address", text: $address, prompt: Text("Paste \(selectedChain.displayName) address"))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onChange(of: address) { new in
                            validateAddress(new)
                        }

                    if !address.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: isValidAddress ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(isValidAddress ? Color(red: 0.20, green: 0.84, blue: 0.29) : Color(red: 1, green: 0.27, blue: 0.23))
                            Text(isValidAddress ? "Valid \(selectedChain.displayName) address" : "Invalid address format")
                                .font(.system(size: 10))
                                .foregroundColor(isValidAddress ? Color(red: 0.20, green: 0.84, blue: 0.29) : Color(red: 1, green: 0.27, blue: 0.23))
                        }
                    }
                }

                TextField("Notes (optional)", text: $notes, prompt: Text("Add any notes"))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .hawalaSectionCard()

            if let error = error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23))
            }

            HawalaActionButton(icon: "plus.circle", label: "Add Address", style: .primary) {
                addWallet()
            }
        }
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
        HawalaSheetShell(title: "Edit Watch-Only Wallet", width: 450, height: 340) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Chain")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: wallet.chain.iconName)
                            .font(.system(size: 10))
                        Text(wallet.chain.displayName)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.6))
                }
                HStack {
                    Text("Address")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                    Spacer()
                    Text(wallet.address)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            .hawalaSectionCard()

            VStack(alignment: .leading, spacing: 8) {
                HawalaOverlaySectionHeader(icon: "pencil", title: "Edit")
                TextField("Label", text: $label)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                TextField("Notes", text: $notes, prompt: Text("Add any notes"), axis: .vertical)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                    .textFieldStyle(.plain)
                    .lineLimit(3...5)
                    .padding(8)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .hawalaSectionCard()

            HawalaActionButton(icon: "checkmark.circle", label: "Save", style: .primary) {
                manager.updateWalletLabel(wallet.id, newLabel: label)
                manager.updateWalletNotes(wallet.id, notes: notes.isEmpty ? nil : notes)
                dismiss()
            }
        }
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
