import SwiftUI

// MARK: - Time-Locked Vaults View

/// Main view for managing time-locked vaults
struct TimeLockedVaultsView: View {
    @StateObject private var manager = TimeLockedVaultManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var showCreateVault = false
    @State private var selectedVault: TimeLockedVault?
    @State private var showUnlockConfirmation = false
    @State private var vaultToUnlock: TimeLockedVault?
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            if manager.vaults.isEmpty {
                emptyState
            } else {
                vaultList
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showCreateVault) {
            CreateVaultSheet()
        }
        .sheet(item: $selectedVault) { vault in
            VaultDetailSheet(vault: vault)
        }
        .alert("Vault Error", isPresented: .constant(errorMessage != nil)) {
            Button("Dismiss") { errorMessage = nil }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .alert("Unlock Vault", isPresented: $showUnlockConfirmation) {
            Button("Cancel", role: .cancel) { vaultToUnlock = nil }
            Button("Unlock", role: .destructive) {
                if let vault = vaultToUnlock {
                    Task {
                        let result = await manager.unlockVault(vault.id)
                        if case .failure(let error) = result {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                vaultToUnlock = nil
            }
        } message: {
            if let vault = vaultToUnlock {
                Text("Are you sure you want to unlock '\(vault.name)'? This will transfer \(vault.amount) \(vault.tokenSymbol) back to your wallet.")
            }
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Time-Locked Vaults")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("\(manager.vaults.count) vault\(manager.vaults.count == 1 ? "" : "s") • \(formattedTotalLocked) locked")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { showCreateVault = true }) {
                Label("New Vault", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var formattedTotalLocked: String {
        let btc = manager.totalLockedValue(for: .bitcoin)
        let eth = manager.totalLockedValue(for: .ethereum)
        
        var parts: [String] = []
        if btc > 0 { parts.append(String(format: "%.4f BTC", btc)) }
        if eth > 0 { parts.append(String(format: "%.4f ETH", eth)) }
        
        return parts.isEmpty ? "0" : parts.joined(separator: ", ")
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "lock.doc.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            VStack(spacing: 8) {
                Text("No Vaults Yet")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Create a time-locked vault to lock your crypto until a specific date.\nPerfect for forced HODLing, savings goals, or scheduled payments.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            
            Button(action: { showCreateVault = true }) {
                Label("Create Your First Vault", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            // Feature highlights
            HStack(spacing: 40) {
                VaultFeatureItem(icon: "lock.fill", title: "Blockchain Enforced", subtitle: "Cannot be bypassed")
                VaultFeatureItem(icon: "calendar", title: "Custom Duration", subtitle: "1 month to 10+ years")
                VaultFeatureItem(icon: "chart.pie.fill", title: "Partial Unlocks", subtitle: "Scheduled releases")
            }
            .padding(.top, 20)
            
            Spacer()
        }
        .padding(40)
    }
    
    // MARK: - Vault List
    
    private var vaultList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Stats header
                statsHeader
                
                // Locked vaults
                let lockedVaults = manager.vaults.filter { $0.status == .locked || $0.status == .partiallyUnlocked }
                if !lockedVaults.isEmpty {
                    VaultSection(title: "Locked", vaults: lockedVaults) { vault in
                        selectedVault = vault
                    }
                }
                
                // Ready to unlock
                let readyVaults = manager.vaults.filter { $0.status == .ready }
                if !readyVaults.isEmpty {
                    VaultSection(title: "Ready to Unlock", vaults: readyVaults) { vault in
                        vaultToUnlock = vault
                        showUnlockConfirmation = true
                    }
                }
                
                // Unlocked (history)
                let unlockedVaults = manager.vaults.filter { $0.status == .unlocked }
                if !unlockedVaults.isEmpty {
                    VaultSection(title: "History", vaults: unlockedVaults, isHistory: true) { vault in
                        selectedVault = vault
                    }
                }
            }
            .padding(24)
        }
    }
    
    private var statsHeader: some View {
        HStack(spacing: 20) {
            VaultStatCard(
                title: "Total Locked",
                value: formattedTotalLocked,
                icon: "lock.fill",
                color: .orange
            )
            
            VaultStatCard(
                title: "Active Vaults",
                value: "\(manager.vaults.filter { $0.status == .locked }.count)",
                icon: "tray.full.fill",
                color: .blue
            )
            
            VaultStatCard(
                title: "Ready to Unlock",
                value: "\(manager.vaults.filter { $0.status == .ready }.count)",
                icon: "lock.open.fill",
                color: .green
            )
        }
    }
}

// MARK: - Vault Section

private struct VaultSection: View {
    let title: String
    let vaults: [TimeLockedVault]
    var isHistory: Bool = false
    let onSelect: (TimeLockedVault) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(isHistory ? .secondary : .primary)
            
            ForEach(vaults) { vault in
                VaultCard(vault: vault, isHistory: isHistory)
                    .onTapGesture {
                        onSelect(vault)
                    }
            }
        }
    }
}

// MARK: - Vault Card

private struct VaultCard: View {
    let vault: TimeLockedVault
    var isHistory: Bool = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Chain icon
            Image(systemName: vault.chain.icon)
                .font(.title)
                .foregroundColor(vault.chain.color)
                .frame(width: 50, height: 50)
                .background(vault.chain.color.opacity(0.1))
                .cornerRadius(12)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(vault.name)
                        .font(.headline)
                    
                    if vault.status == .ready {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                
                Text("\(String(format: "%.6f", vault.amount)) \(vault.tokenSymbol)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if !isHistory {
                    Text(vault.formattedTimeRemaining)
                        .font(.caption)
                        .foregroundColor(vault.status == .ready ? .green : .orange)
                }
            }
            
            Spacer()
            
            // Progress/Status
            VStack(alignment: .trailing, spacing: 4) {
                Text(vault.status.displayName)
                    .font(.caption)
                    .foregroundColor(vault.status.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(vault.status.color.opacity(0.1))
                    .cornerRadius(6)
                
                if !isHistory && vault.status == .locked {
                    CircularProgress(progress: vault.progress)
                        .frame(width: 40, height: 40)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(vault.status == .ready ? Color.green.opacity(0.3) : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Circular Progress

private struct CircularProgress: View {
    let progress: Double
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 4)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            
            Text("\(Int(progress * 100))%")
                .font(.system(size: 10, weight: .medium))
        }
    }
}

// MARK: - Create Vault Sheet

private struct CreateVaultSheet: View {
    @StateObject private var manager = TimeLockedVaultManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var config = VaultConfig()
    @State private var useSchedule = false
    @State private var scheduleItems: [UnlockScheduleItem] = []
    @State private var isCreating = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create Time-Locked Vault")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Basic info
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Vault Details")
                            .font(.headline)
                        
                        TextField("Vault Name", text: $config.name)
                            .textFieldStyle(.roundedBorder)
                        
                        Picker("Blockchain", selection: $config.chain) {
                            ForEach(BlockchainChain.allCases) { chain in
                                Label(chain.displayName, systemImage: chain.icon)
                                    .tag(chain)
                            }
                        }
                        .onChange(of: config.chain) { newChain in
                            config.tokenSymbol = newChain.symbol
                        }
                        
                        HStack {
                            TextField("Amount", value: $config.amount, format: .number)
                                .textFieldStyle(.roundedBorder)
                            Text(config.tokenSymbol)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Divider()
                    
                    // Lock duration
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Lock Duration")
                            .font(.headline)
                        
                        // Presets
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                            ForEach(VaultConfig.presetDurations, id: \.months) { preset in
                                Button(action: {
                                    config.unlockDate = Calendar.current.date(byAdding: .month, value: preset.months, to: Date())!
                                }) {
                                    Text(preset.label)
                                        .font(.subheadline)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(isPresetSelected(preset.months) ? Color.blue : Color.gray.opacity(0.1))
                                        .foregroundColor(isPresetSelected(preset.months) ? .white : .primary)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        // Custom date
                        DatePicker("Unlock Date", selection: $config.unlockDate, in: Date()..., displayedComponents: [.date])
                        
                        Text("Funds will be locked until \(config.unlockDate, style: .date)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // Unlock schedule
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Use Partial Unlock Schedule", isOn: $useSchedule)
                        
                        if useSchedule {
                            Text("Release portions of the vault over time")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            // Schedule items
                            ForEach(Array(scheduleItems.enumerated()), id: \.element.id) { index, item in
                                HStack {
                                    Text("Release \(item.percentage)%")
                                    Spacer()
                                    Text(item.unlockDate, style: .date)
                                        .foregroundColor(.secondary)
                                    Button(action: { scheduleItems.remove(at: index) }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding()
                                .background(Color.gray.opacity(0.05))
                                .cornerRadius(8)
                            }
                            
                            Button(action: addScheduleItem) {
                                Label("Add Release Date", systemImage: "plus.circle")
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Purpose
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Purpose")
                            .font(.headline)
                        
                        Picker("Purpose", selection: $config.purpose) {
                            ForEach(VaultPurpose.allCases, id: \.self) { purpose in
                                Label(purpose.displayName, systemImage: purpose.icon)
                                    .tag(purpose)
                            }
                        }
                        .pickerStyle(.menu)
                        
                        TextField("Notes (optional)", text: Binding(
                            get: { config.notes ?? "" },
                            set: { config.notes = $0.isEmpty ? nil : $0 }
                        ), axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                    }
                    
                    // Warning
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Important")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Time-locked vaults are enforced by the blockchain. You will NOT be able to access these funds until the unlock date.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                    
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                .padding(24)
            }
            
            // Footer
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create Vault") {
                    createVault()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate || isCreating)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 500, height: 700)
    }
    
    private var canCreate: Bool {
        !config.name.isEmpty && config.amount > 0 && config.unlockDate > Date()
    }
    
    private func isPresetSelected(_ months: Int) -> Bool {
        let targetDate = Calendar.current.date(byAdding: .month, value: months, to: Date())!
        let diff = abs(config.unlockDate.timeIntervalSince(targetDate))
        return diff < 86400 // Within 1 day
    }
    
    private func addScheduleItem() {
        let remainingPercentage = 100 - scheduleItems.reduce(0) { $0 + $1.percentage }
        guard remainingPercentage > 0 else { return }
        
        let newDate = scheduleItems.last?.unlockDate ?? config.unlockDate
        let item = UnlockScheduleItem(
            unlockDate: Calendar.current.date(byAdding: .month, value: 1, to: newDate)!,
            amount: config.amount * Double(min(25, remainingPercentage)) / 100.0,
            percentage: min(25, remainingPercentage)
        )
        scheduleItems.append(item)
    }
    
    private func createVault() {
        isCreating = true
        
        if useSchedule && !scheduleItems.isEmpty {
            config.unlockSchedule = scheduleItems
        }
        
        Task {
            let result = await manager.createVault(config)
            isCreating = false
            
            switch result {
            case .success:
                dismiss()
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Vault Detail Sheet

private struct VaultDetailSheet: View {
    let vault: TimeLockedVault
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: vault.chain.icon)
                    .font(.title)
                    .foregroundColor(vault.chain.color)
                
                VStack(alignment: .leading) {
                    Text(vault.name)
                        .font(.headline)
                    Text(vault.chain.displayName)
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
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            ScrollView {
                VStack(spacing: 24) {
                    // Status card
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                            
                            Circle()
                                .trim(from: 0, to: vault.progress)
                                .stroke(vault.status.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            
                            VStack(spacing: 4) {
                                Image(systemName: vault.status.icon)
                                    .font(.title)
                                    .foregroundColor(vault.status.color)
                                Text(vault.status.displayName)
                                    .font(.caption)
                            }
                        }
                        .frame(width: 120, height: 120)
                        
                        Text(vault.formattedTimeRemaining)
                            .font(.headline)
                            .foregroundColor(vault.status == .ready ? .green : .primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(16)
                    
                    // Details
                    VStack(spacing: 16) {
                        VaultDetailRow(label: "Amount", value: "\(String(format: "%.8f", vault.amount)) \(vault.tokenSymbol)")
                        VaultDetailRow(label: "Created", value: vault.createdAt.formatted(date: .abbreviated, time: .shortened))
                        VaultDetailRow(label: "Unlocks", value: vault.unlockDate.formatted(date: .abbreviated, time: .shortened))
                        VaultDetailRow(label: "Purpose", value: vault.purpose.displayName)
                        
                        if let notes = vault.notes {
                            VaultDetailRow(label: "Notes", value: notes)
                        }
                        
                        if let scriptAddress = vault.scriptAddress {
                            VaultDetailRow(label: "Script Address", value: scriptAddress)
                        }
                        
                        if let txHash = vault.lockTxHash {
                            VaultDetailRow(label: "Lock TX", value: String(txHash.prefix(16)) + "...")
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(12)
                    
                    // Unlock schedule if present
                    if let schedule = vault.unlockSchedule {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Unlock Schedule")
                                .font(.headline)
                            
                            ForEach(schedule) { item in
                                HStack {
                                    Image(systemName: item.isUnlocked ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(item.isUnlocked ? .green : .gray)
                                    
                                    Text("\(item.percentage)%")
                                        .fontWeight(.medium)
                                    
                                    Spacer()
                                    
                                    Text(item.unlockDate, style: .date)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(item.isUnlocked ? Color.green.opacity(0.1) : Color.gray.opacity(0.05))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding(24)
            }
            
            // Action button
            if vault.status == .ready {
                HStack {
                    Spacer()
                    Button("Unlock Vault") {
                        // Trigger unlock
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .frame(width: 450, height: 600)
    }
}

private struct VaultDetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .fontWeight(.medium)
            Spacer()
        }
    }
}

// MARK: - Helper Views

private struct VaultFeatureItem: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
            
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct VaultStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.headline)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    TimeLockedVaultsView()
}
#endif
#endif
#endif
