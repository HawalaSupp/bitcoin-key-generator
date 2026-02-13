import SwiftUI

// MARK: - Sidebar Wallet Switcher (ROADMAP-21 E5)
/// Compact wallet switcher displayed at the top of the NavigationSplitView sidebar.
/// Shows the active wallet with a dropdown to switch or manage wallets.

struct SidebarWalletSwitcher: View {
    @ObservedObject var walletManager: MultiWalletManager
    let onSwitchWallet: (UUID) -> Void
    let onAddWallet: () -> Void
    let onManageWallets: () -> Void
    
    @State private var isExpanded = false
    @State private var hoveredWalletId: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            // Active wallet header (tap to expand)
            activeWalletButton
            
            // Expanded wallet list
            if isExpanded {
                expandedWalletList
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
    }
    
    // MARK: - Active Wallet Button
    
    private var activeWalletButton: some View {
        Button {
            withAnimation {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                // Emoji avatar
                ZStack {
                    Circle()
                        .fill((walletManager.activeWallet?.color ?? HawalaTheme.Colors.accent).opacity(0.2))
                        .frame(width: 28, height: 28)
                    
                    Text(walletManager.activeWallet?.emoji ?? "💰")
                        .font(.system(size: 14))
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(walletManager.activeWallet?.name ?? "Main Wallet")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                        .lineLimit(1)
                    
                    if walletManager.walletCount > 1 {
                        Text("\(walletManager.walletCount) wallets")
                            .font(.system(size: 10))
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(HawalaTheme.Colors.backgroundSecondary)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
    
    // MARK: - Expanded Wallet List
    
    private var expandedWalletList: some View {
        VStack(spacing: 2) {
            // Aggregate view toggle
            if walletManager.walletCount > 1 {
                Button {
                    walletManager.toggleAggregateView()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 12))
                            .foregroundColor(walletManager.showAggregateView ? HawalaTheme.Colors.accent : HawalaTheme.Colors.textSecondary)
                            .frame(width: 28)
                        
                        Text("All Wallets")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(walletManager.showAggregateView ? HawalaTheme.Colors.accent : HawalaTheme.Colors.textPrimary)
                        
                        Spacer()
                        
                        if walletManager.showAggregateView {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(HawalaTheme.Colors.accent)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(walletManager.showAggregateView ? HawalaTheme.Colors.accent.opacity(0.1) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                
                Divider()
                    .background(HawalaTheme.Colors.divider)
                    .padding(.vertical, 4)
            }
            
            // Individual wallets
            ForEach(walletManager.sortedWallets) { wallet in
                walletRow(wallet)
            }
            
            Divider()
                .background(HawalaTheme.Colors.divider)
                .padding(.vertical, 4)
            
            // Action buttons
            HStack(spacing: 8) {
                Button {
                    onAddWallet()
                    isExpanded = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 11))
                        Text("Add")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(HawalaTheme.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(HawalaTheme.Colors.accent.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!walletManager.canAddWallet)
                
                Button {
                    onManageWallets()
                    isExpanded = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11))
                        Text("Manage")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(HawalaTheme.Colors.backgroundTertiary)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
    
    // MARK: - Wallet Row
    
    private func walletRow(_ wallet: HawalaWalletProfile) -> some View {
        let isActive = wallet.id == walletManager.activeWalletId && !walletManager.showAggregateView
        let isHovered = hoveredWalletId == wallet.id
        
        return Button {
            walletManager.showAggregateView = false
            onSwitchWallet(wallet.id)
            isExpanded = false
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(wallet.color.opacity(0.2))
                        .frame(width: 24, height: 24)
                    
                    Text(wallet.emoji)
                        .font(.system(size: 12))
                }
                
                Text(wallet.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? HawalaTheme.Colors.textPrimary : HawalaTheme.Colors.textSecondary)
                    .lineLimit(1)
                
                if wallet.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.yellow)
                }
                
                Spacer()
                
                if isActive {
                    Circle()
                        .fill(HawalaTheme.Colors.success)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? wallet.color.opacity(0.1) : (isHovered ? HawalaTheme.Colors.backgroundHover : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredWalletId = hovering ? wallet.id : nil
        }
    }
}

// MARK: - Delete Wallet Confirmation Sheet (ROADMAP-21 E9/E10)

struct DeleteWalletConfirmationView: View {
    let walletId: UUID
    let walletName: String
    let onConfirmDelete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var backupAcknowledged = false
    @State private var typedConfirmation = ""
    
    private var canDelete: Bool {
        backupAcknowledged && typedConfirmation.lowercased() == "delete"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(HawalaTheme.Colors.error)
                
                Text("Delete Wallet")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("You are about to permanently delete **\(walletName)**. This action cannot be undone.")
                    .font(.system(size: 14))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)
            
            Divider().background(HawalaTheme.Colors.divider)
            
            // Safeguards
            VStack(alignment: .leading, spacing: 16) {
                // Backup acknowledgment checkbox
                Toggle(isOn: $backupAcknowledged) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("I have backed up this wallet")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                        
                        Text("I understand that without a backup, all funds in this wallet will be permanently lost.")
                            .font(.system(size: 12))
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                    }
                }
                .toggleStyle(.checkbox)
                
                // Type "delete" confirmation
                VStack(alignment: .leading, spacing: 6) {
                    Text("Type \"delete\" to confirm")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    
                    TextField("delete", text: $typedConfirmation)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(HawalaTheme.Colors.backgroundTertiary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    typedConfirmation.lowercased() == "delete" ? HawalaTheme.Colors.error.opacity(0.5) : HawalaTheme.Colors.border,
                                    lineWidth: 1
                                )
                        )
                }
            }
            .padding(20)
            
            Divider().background(HawalaTheme.Colors.divider)
            
            // Actions
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(HawalaTheme.Colors.backgroundTertiary)
                )
                
                Button {
                    onConfirmDelete()
                    dismiss()
                } label: {
                    Text("Delete Wallet")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(canDelete ? HawalaTheme.Colors.error : HawalaTheme.Colors.error.opacity(0.3))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canDelete)
            }
            .padding(20)
        }
        .frame(width: 420)
        .background(HawalaTheme.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .preferredColorScheme(.dark)
    }
}

// MARK: - Add Wallet Sheet (ROADMAP-21 E7)

struct AddWalletSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var walletManager: MultiWalletManager
    
    @State private var walletName = ""
    @State private var selectedEmoji = "💰"
    @State private var selectedColor: String = HawalaWalletProfile.colors[0]
    @State private var importMode = false
    
    let onCreateNew: (String, String, String) -> Void  // name, emoji, color
    let onImport: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundColor(HawalaTheme.Colors.accent)
                
                Spacer()
                
                Text("Add Wallet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Spacer()
                
                Button("Create") {
                    let name = walletName.isEmpty ? "Wallet \(walletManager.walletCount + 1)" : walletName
                    onCreateNew(name, selectedEmoji, selectedColor)
                    dismiss()
                }
                .foregroundColor(HawalaTheme.Colors.accent)
                .disabled(walletName.isEmpty && walletManager.walletCount == 0)
            }
            .padding(16)
            
            Divider().background(HawalaTheme.Colors.divider)
            
            ScrollView {
                VStack(spacing: 24) {
                    // Preview
                    ZStack {
                        Circle()
                            .fill(Color(hex: selectedColor).opacity(0.2))
                            .frame(width: 80, height: 80)
                        Text(selectedEmoji)
                            .font(.system(size: 36))
                    }
                    .padding(.top, 24)
                    
                    // Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Wallet Name")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                        
                        TextField("e.g. Savings, Trading, DeFi", text: $walletName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(HawalaTheme.Colors.backgroundTertiary)
                            )
                    }
                    
                    // Emoji picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Emoji")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                            ForEach(HawalaWalletProfile.emojis, id: \.self) { emoji in
                                Button {
                                    selectedEmoji = emoji
                                } label: {
                                    Text(emoji)
                                        .font(.system(size: 24))
                                        .frame(width: 44, height: 44)
                                        .background(
                                            Circle()
                                                .fill(selectedEmoji == emoji ? HawalaTheme.Colors.accent.opacity(0.2) : Color.clear)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // Color picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Color")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                            ForEach(HawalaWalletProfile.colors, id: \.self) { colorHex in
                                Button {
                                    selectedColor = colorHex
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: colorHex))
                                            .frame(width: 44, height: 44)
                                        if selectedColor == colorHex {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    Divider().background(HawalaTheme.Colors.divider)
                    
                    // Import option
                    Button {
                        onImport()
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 16))
                            Text("Import Existing Wallet")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundColor(HawalaTheme.Colors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(HawalaTheme.Colors.accent.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(24)
            }
        }
        .frame(minWidth: 420, minHeight: 550)
        .background(HawalaTheme.Colors.background)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Sidebar Navigation Button (Themed)
/// A custom sidebar navigation button that matches HawalaTheme instead of default macOS List style.
struct SidebarNavButton: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? HawalaTheme.Colors.textPrimary : HawalaTheme.Colors.textSecondary)
                    .frame(width: 20)
                
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? HawalaTheme.Colors.textPrimary : HawalaTheme.Colors.textSecondary)
                
                Spacer()
                
                if isSelected {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white)
                        .frame(width: 3, height: 16)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.white.opacity(0.08)
                            : (isHovered ? Color.white.opacity(0.04) : Color.clear)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
