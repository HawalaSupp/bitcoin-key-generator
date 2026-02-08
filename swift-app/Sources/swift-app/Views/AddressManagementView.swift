import SwiftUI

// MARK: - Address Management View
/// Comprehensive address management with HD wallet support, reuse warnings, and gap limit configuration

struct AddressManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var addressManager = HDAddressManager.shared
    
    @State private var selectedChain: CryptoChain = .bitcoin
    @State private var selectedFilter: AddressFilter = .all
    @State private var searchText: String = ""
    @State private var showSettings = false
    @State private var showNewAddressSheet = false
    @State private var selectedAddress: ManagedAddress?
    @State private var showReuseAlert = false
    @State private var pendingReuseAddress: ManagedAddress?
    
    enum AddressFilter: String, CaseIterable {
        case all = "All"
        case unused = "Unused"
        case used = "Used"
        case receive = "Receive"
        case change = "Change"
        case labeled = "Labeled"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Main content
            HStack(spacing: 0) {
                // Sidebar
                sidebarView
                    .frame(width: 200)
                
                Divider()
                
                // Address list
                addressListView
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .background(HawalaTheme.Colors.background)
        .sheet(isPresented: $showSettings) {
            AddressSettingsView(addressManager: addressManager)
        }
        .sheet(isPresented: $showNewAddressSheet) {
            NewAddressSheet(chain: selectedChain, addressManager: addressManager)
        }
        .sheet(item: $selectedAddress) { address in
            AddressDetailView(address: address, addressManager: addressManager)
        }
        .alert("Address Reuse Warning", isPresented: $showReuseAlert) {
            Button("Generate New Address") {
                _ = addressManager.getNextReceiveAddress(chain: selectedChain, forceNew: true)
            }
            Button("Use Anyway", role: .destructive) {
                if let address = pendingReuseAddress {
                    selectedAddress = address
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This address has been used before. Reusing addresses reduces your privacy and allows transaction linking.")
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: HawalaTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Address Management")
                    .font(HawalaTheme.Typography.h2)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("Manage your HD wallet addresses")
                    .font(HawalaTheme.Typography.bodySmall)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            // Statistics
            statisticsView
            
            Spacer()
            
            // Actions
            HStack(spacing: HawalaTheme.Spacing.md) {
                Button {
                    showNewAddressSheet = true
                } label: {
                    Label("New Address", systemImage: "plus")
                        .font(HawalaTheme.Typography.body)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!selectedChain.supportsMultipleAddresses)
                
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.bordered)
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(HawalaTheme.Spacing.lg)
    }
    
    // MARK: - Statistics
    private var statisticsView: some View {
        let stats = addressManager.getStatistics(for: selectedChain)
        
        return HStack(spacing: HawalaTheme.Spacing.xl) {
            StatBadge(title: "Total", value: "\(stats.totalAddresses)", color: HawalaTheme.Colors.textSecondary)
            StatBadge(title: "Used", value: "\(stats.usedAddresses)", color: HawalaTheme.Colors.warning)
            StatBadge(title: "Unused", value: "\(stats.unusedAddresses)", color: HawalaTheme.Colors.success)
            if stats.multiUseAddresses > 0 {
                StatBadge(title: "Multi-use", value: "\(stats.multiUseAddresses)", color: HawalaTheme.Colors.error)
            }
        }
    }
    
    // MARK: - Sidebar
    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Chain selector
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                Text("BLOCKCHAIN")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                    .padding(.horizontal, HawalaTheme.Spacing.md)
                
                ForEach(CryptoChain.allCases, id: \.self) { chain in
                    ChainRow(chain: chain, isSelected: selectedChain == chain) {
                        selectedChain = chain
                    }
                }
            }
            .padding(.vertical, HawalaTheme.Spacing.md)
            
            Divider()
            
            // Filter selector
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                Text("FILTER")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                    .padding(.horizontal, HawalaTheme.Spacing.md)
                
                ForEach(AddressFilter.allCases, id: \.self) { filter in
                    FilterRow(filter: filter, isSelected: selectedFilter == filter) {
                        selectedFilter = filter
                    }
                }
            }
            .padding(.vertical, HawalaTheme.Spacing.md)
            
            Spacer()
            
            // Gap limit indicator
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xs) {
                Text("Gap Limit: \(addressManager.gapLimit)")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                if addressManager.autoGenerateNewAddress {
                    Label("Auto-generate enabled", systemImage: "checkmark.circle.fill")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.success)
                }
            }
            .padding(HawalaTheme.Spacing.md)
        }
        .background(HawalaTheme.Colors.backgroundSecondary)
    }
    
    // MARK: - Address List
    private var addressListView: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                TextField("Search addresses or labels...", text: $searchText)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.backgroundSecondary)
            
            Divider()
            
            // Address list
            ScrollView {
                LazyVStack(spacing: HawalaTheme.Spacing.sm) {
                    ForEach(filteredAddresses) { address in
                        HDAddressRow(
                            address: address,
                            showReuseWarning: addressManager.showReuseWarnings
                        ) {
                            handleAddressSelection(address)
                        }
                    }
                    
                    if filteredAddresses.isEmpty {
                        emptyStateView
                    }
                }
                .padding(HawalaTheme.Spacing.md)
            }
        }
    }
    
    private var filteredAddresses: [ManagedAddress] {
        var addresses = addressManager.getAddresses(for: selectedChain)
        
        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .unused:
            addresses = addresses.filter { !$0.isUsed }
        case .used:
            addresses = addresses.filter { $0.isUsed }
        case .receive:
            addresses = addresses.filter { !$0.isChange }
        case .change:
            addresses = addresses.filter { $0.isChange }
        case .labeled:
            addresses = addresses.filter { !$0.label.isEmpty }
        }
        
        // Apply search
        if !searchText.isEmpty {
            addresses = addresses.filter { address in
                address.address.localizedCaseInsensitiveContains(searchText) ||
                address.label.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return addresses.sorted { $0.index > $1.index }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: HawalaTheme.Spacing.lg) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            
            Text("No addresses found")
                .font(HawalaTheme.Typography.h3)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
            
            if selectedChain.supportsMultipleAddresses {
                Button("Generate New Address") {
                    _ = addressManager.getNextReceiveAddress(chain: selectedChain, forceNew: true)
                }
                .buttonStyle(.bordered)
            } else {
                Text("\(selectedChain.name) uses a single address")
                    .font(HawalaTheme.Typography.bodySmall)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
        }
        .padding(HawalaTheme.Spacing.xxl)
    }
    
    private func handleAddressSelection(_ address: ManagedAddress) {
        if address.isUsed && addressManager.showReuseWarnings {
            pendingReuseAddress = address
            showReuseAlert = true
        } else {
            selectedAddress = address
        }
    }
}

// MARK: - Supporting Views

struct StatBadge: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
            
            Text(title)
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
        }
    }
}

struct ChainRow: View {
    let chain: CryptoChain
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: HawalaTheme.Spacing.sm) {
                Image(systemName: chain.icon)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? HawalaTheme.Colors.accent : HawalaTheme.Colors.textSecondary)
                    .frame(width: 20)
                
                Text(chain.name)
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(isSelected ? HawalaTheme.Colors.accent : HawalaTheme.Colors.textPrimary)
                
                Spacer()
                
                if !chain.supportsMultipleAddresses {
                    Text("1")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(HawalaTheme.Colors.backgroundTertiary)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, HawalaTheme.Spacing.md)
            .padding(.vertical, HawalaTheme.Spacing.sm)
            .background(isSelected ? HawalaTheme.Colors.accent.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

struct FilterRow: View {
    let filter: AddressManagementView.AddressFilter
    let isSelected: Bool
    let action: () -> Void
    
    private var icon: String {
        switch filter {
        case .all: return "list.bullet"
        case .unused: return "circle"
        case .used: return "checkmark.circle.fill"
        case .receive: return "arrow.down"
        case .change: return "arrow.left.arrow.right"
        case .labeled: return "tag"
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: HawalaTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? HawalaTheme.Colors.accent : HawalaTheme.Colors.textSecondary)
                    .frame(width: 20)
                
                Text(filter.rawValue)
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(isSelected ? HawalaTheme.Colors.accent : HawalaTheme.Colors.textPrimary)
                
                Spacer()
            }
            .padding(.horizontal, HawalaTheme.Spacing.md)
            .padding(.vertical, HawalaTheme.Spacing.sm)
            .background(isSelected ? HawalaTheme.Colors.accent.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

struct HDAddressRow: View {
    let address: ManagedAddress
    let showReuseWarning: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var isCopied = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: HawalaTheme.Spacing.md) {
                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                
                // Address info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: HawalaTheme.Spacing.sm) {
                        Text(address.displayName)
                            .font(HawalaTheme.Typography.body)
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                        
                        if address.isChange {
                            Text("CHANGE")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(HawalaTheme.Colors.textTertiary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(HawalaTheme.Colors.backgroundTertiary)
                                .clipShape(Capsule())
                        }
                        
                        if address.isUsed && address.useCount > 1 && showReuseWarning {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(HawalaTheme.Colors.warning)
                        }
                    }
                    
                    HStack(spacing: HawalaTheme.Spacing.sm) {
                        Text(address.address.isEmpty ? "Pending derivation..." : address.shortAddress)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                        
                        Text("m/\(address.index)")
                            .font(.system(size: 10))
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                            .opacity(0.7)
                    }
                }
                
                Spacer()
                
                // Use count badge
                if address.useCount > 0 {
                    Text("\(address.useCount) tx")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(HawalaTheme.Colors.backgroundTertiary)
                        .clipShape(Capsule())
                }
                
                // Copy button
                Button {
                    copyAddress()
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(isCopied ? HawalaTheme.Colors.success : HawalaTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            .padding(HawalaTheme.Spacing.md)
            .background(isHovered ? HawalaTheme.Colors.backgroundSecondary : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var statusColor: Color {
        if address.isUsed {
            return address.useCount > 1 ? HawalaTheme.Colors.warning : HawalaTheme.Colors.success
        }
        return HawalaTheme.Colors.textTertiary
    }
    
    private func copyAddress() {
        ClipboardHelper.copySensitive(address.address, timeout: 60)
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

// MARK: - Address Detail View

struct AddressDetailView: View {
    let address: ManagedAddress
    let addressManager: HDAddressManager
    
    @Environment(\.dismiss) private var dismiss
    @State private var label: String = ""
    @State private var note: String = ""
    @State private var isCopied = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Address Details")
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(HawalaTheme.Spacing.lg)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: HawalaTheme.Spacing.lg) {
                    // QR Code
                    qrCodeSection
                    
                    // Address
                    addressSection
                    
                    // Derivation info
                    derivationSection
                    
                    // Labels
                    labelSection
                    
                    // Usage history
                    if address.isUsed {
                        usageSection
                    }
                    
                    // Privacy warning
                    if address.useCount > 1 {
                        privacyWarningSection
                    }
                }
                .padding(HawalaTheme.Spacing.lg)
            }
        }
        .frame(width: 400, height: 600)
        .background(HawalaTheme.Colors.background)
        .onAppear {
            label = address.label
            note = address.note
        }
    }
    
    private var qrCodeSection: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            // QR Code would be generated here
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                .fill(Color.white)
                .frame(width: 160, height: 160)
                .overlay(
                    Text("QR")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.gray)
                )
        }
        .frame(maxWidth: .infinity)
    }
    
    private var addressSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            Text("ADDRESS")
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            
            HStack {
                Text(address.address.isEmpty ? "Pending..." : address.address)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                    .textSelection(.enabled)
                
                Spacer()
                
                Button {
                    copyAddress()
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .foregroundColor(isCopied ? HawalaTheme.Colors.success : HawalaTheme.Colors.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
        }
    }
    
    private var derivationSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            Text("DERIVATION PATH")
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            
            HStack {
                Text(address.derivationPath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Index: \(address.index)")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    
                    Text(address.isChange ? "Change" : "Receive")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(address.isChange ? HawalaTheme.Colors.warning : HawalaTheme.Colors.success)
                }
            }
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
        }
    }
    
    private var labelSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            Text("LABEL")
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            
            TextField("Add a label...", text: $label)
                .textFieldStyle(.plain)
                .padding(HawalaTheme.Spacing.md)
                .background(HawalaTheme.Colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                .onChange(of: label) { newValue in
                    addressManager.setLabel(newValue, for: address.address)
                }
            
            TextField("Add notes...", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...6)
                .padding(HawalaTheme.Spacing.md)
                .background(HawalaTheme.Colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                .onChange(of: note) { newValue in
                    addressManager.setNote(newValue, for: address.address)
                }
        }
    }
    
    private var usageSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            Text("USAGE")
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                HStack {
                    Text("Transactions:")
                    Spacer()
                    Text("\(address.useCount)")
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
                
                if let lastUsed = address.lastUsedAt {
                    HStack {
                        Text("Last used:")
                        Spacer()
                        Text(lastUsed.formatted(date: .abbreviated, time: .shortened))
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                    }
                }
                
                HStack {
                    Text("Created:")
                    Spacer()
                    Text(address.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
            }
            .font(HawalaTheme.Typography.body)
            .foregroundColor(HawalaTheme.Colors.textPrimary)
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
        }
    }
    
    private var privacyWarningSection: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundColor(HawalaTheme.Colors.warning)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Privacy Warning")
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("This address has been used \(address.useCount) times. Consider generating a new address for better privacy.")
                    .font(HawalaTheme.Typography.bodySmall)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.warning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
    }
    
    private func copyAddress() {
        ClipboardHelper.copySensitive(address.address, timeout: 60)
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

// MARK: - Settings View

struct AddressSettingsView: View {
    @ObservedObject var addressManager: HDAddressManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var gapLimitText: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Address Settings")
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(HawalaTheme.Spacing.lg)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xl) {
                    // Auto-generate toggle
                    settingRow(
                        icon: "arrow.clockwise",
                        title: "Auto-generate New Addresses",
                        description: "Automatically generate a new receive address when the current one is used"
                    ) {
                        Toggle("", isOn: $addressManager.autoGenerateNewAddress)
                            .toggleStyle(.switch)
                    }
                    
                    // Reuse warnings toggle
                    settingRow(
                        icon: "exclamationmark.triangle",
                        title: "Show Reuse Warnings",
                        description: "Display a warning when selecting an address that has been used before"
                    ) {
                        Toggle("", isOn: $addressManager.showReuseWarnings)
                            .toggleStyle(.switch)
                    }
                    
                    // Gap limit
                    settingRow(
                        icon: "number",
                        title: "Gap Limit",
                        description: "Number of consecutive unused addresses to scan when recovering wallet (BIP44 standard is 20)"
                    ) {
                        HStack(spacing: HawalaTheme.Spacing.sm) {
                            TextField("20", text: $gapLimitText)
                                .textFieldStyle(.plain)
                                .frame(width: 60)
                                .padding(HawalaTheme.Spacing.sm)
                                .background(HawalaTheme.Colors.backgroundTertiary)
                                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm))
                                .onSubmit {
                                    if let value = Int(gapLimitText) {
                                        addressManager.setGapLimit(value)
                                    }
                                    gapLimitText = "\(addressManager.gapLimit)"
                                }
                            
                            Stepper("", value: Binding(
                                get: { addressManager.gapLimit },
                                set: { addressManager.setGapLimit($0) }
                            ), in: 5...100)
                            .labelsHidden()
                        }
                    }
                    
                    Divider()
                    
                    // Info section
                    VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
                        Text("About HD Wallets")
                            .font(HawalaTheme.Typography.h4)
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                        
                        Text("Hierarchical Deterministic (HD) wallets generate multiple addresses from a single seed. This improves privacy by allowing you to use a new address for each transaction.")
                            .font(HawalaTheme.Typography.bodySmall)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                        
                        Text("Best Practices:")
                            .font(HawalaTheme.Typography.body)
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                            .padding(.top, HawalaTheme.Spacing.sm)
                        
                        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xs) {
                            bulletPoint("Use a new receive address for each transaction")
                            bulletPoint("Label addresses to track their purpose")
                            bulletPoint("Avoid reusing addresses to prevent transaction linking")
                            bulletPoint("Keep gap limit at 20 or higher for recovery")
                        }
                    }
                    .padding(HawalaTheme.Spacing.md)
                    .background(HawalaTheme.Colors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                }
                .padding(HawalaTheme.Spacing.lg)
            }
        }
        .frame(width: 450, height: 550)
        .background(HawalaTheme.Colors.background)
        .onAppear {
            gapLimitText = "\(addressManager.gapLimit)"
        }
    }
    
    private func settingRow<Content: View>(
        icon: String,
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: HawalaTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(HawalaTheme.Colors.accent)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text(description)
                    .font(HawalaTheme.Typography.bodySmall)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            content()
        }
    }
    
    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: HawalaTheme.Spacing.sm) {
            Text("•")
                .foregroundColor(HawalaTheme.Colors.accent)
            Text(text)
                .font(HawalaTheme.Typography.bodySmall)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
        }
    }
}

// MARK: - New Address Sheet

struct NewAddressSheet: View {
    let chain: CryptoChain
    let addressManager: HDAddressManager
    
    @Environment(\.dismiss) private var dismiss
    @State private var addressType: AddressType = .receive
    @State private var customLabel: String = ""
    @State private var generatedAddress: ManagedAddress?
    
    enum AddressType: String, CaseIterable {
        case receive = "Receive"
        case change = "Change"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Generate New Address")
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(HawalaTheme.Spacing.lg)
            
            Divider()
            
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.lg) {
                // Chain info
                HStack(spacing: HawalaTheme.Spacing.md) {
                    Image(systemName: chain.icon)
                        .font(.system(size: 24))
                        .foregroundColor(HawalaTheme.Colors.accent)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chain.name)
                            .font(HawalaTheme.Typography.h4)
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                        
                        Text(chain.rawValue)
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                }
                
                // Address type picker
                VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                    Text("ADDRESS TYPE")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    
                    Picker("", selection: $addressType) {
                        ForEach(AddressType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                // Optional label
                VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                    Text("LABEL (OPTIONAL)")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    
                    TextField("e.g., Savings, Exchange deposit", text: $customLabel)
                        .textFieldStyle(.plain)
                        .padding(HawalaTheme.Spacing.md)
                        .background(HawalaTheme.Colors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                }
                
                // Generated address preview
                if let address = generatedAddress {
                    VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                        Text("NEW ADDRESS")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                        
                        HStack {
                            Text(address.address.isEmpty ? "Generating..." : address.shortAddress)
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundColor(HawalaTheme.Colors.textPrimary)
                            
                            Spacer()
                            
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(HawalaTheme.Colors.success)
                        }
                        .padding(HawalaTheme.Spacing.md)
                        .background(HawalaTheme.Colors.success.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                        
                        Text(address.derivationPath)
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                }
                
                Spacer()
                
                // Action buttons
                HStack(spacing: HawalaTheme.Spacing.md) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Generate") {
                        generateAddress()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(generatedAddress != nil)
                }
            }
            .padding(HawalaTheme.Spacing.lg)
        }
        .frame(width: 400, height: 450)
        .background(HawalaTheme.Colors.background)
    }
    
    private func generateAddress() {
        let address: ManagedAddress?
        
        if addressType == .receive {
            address = addressManager.getNextReceiveAddress(chain: chain, forceNew: true)
        } else {
            address = addressManager.getNextChangeAddress(chain: chain)
        }
        
        if let address = address, !customLabel.isEmpty {
            addressManager.setLabel(customLabel, for: address.address)
        }
        
        generatedAddress = address
    }
}

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview("Address Management") {
    AddressManagementView()
}
#endif
#endif
#endif
