//
//  HardwareWalletAccountSelector.swift
//  Hawala
//
//  A picker component for selecting hardware wallet accounts
//  to use for signing transactions.
//

import SwiftUI

// MARK: - Account Selector View

/// Dropdown/picker for selecting a hardware wallet account for signing
struct HardwareWalletAccountSelector: View {
    @Binding var selectedAccount: HardwareWalletAccount?
    @ObservedObject var manager: HardwareWalletManagerV2
    
    let chain: SupportedChain
    let onAddAccount: () -> Void
    
    @State private var isExpanded = false
    
    init(
        selectedAccount: Binding<HardwareWalletAccount?>,
        chain: SupportedChain,
        manager: HardwareWalletManagerV2 = .shared,
        onAddAccount: @escaping () -> Void
    ) {
        self._selectedAccount = selectedAccount
        self.chain = chain
        self.manager = manager
        self.onAddAccount = onAddAccount
    }
    
    var availableAccounts: [HardwareWalletAccount] {
        manager.savedAccounts.filter { $0.chain == chain }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sign with Hardware Wallet")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Menu {
                if availableAccounts.isEmpty {
                    Text("No hardware wallet accounts")
                } else {
                    ForEach(availableAccounts) { account in
                        Button {
                            selectedAccount = account
                        } label: {
                            HStack {
                                Image(systemName: account.deviceType.iconName)
                                Text(account.label ?? account.deviceType.displayName)
                                if selectedAccount?.id == account.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                
                Divider()
                
                Button {
                    onAddAccount()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Add Hardware Wallet")
                    }
                }
            } label: {
                HStack {
                    if let account = selectedAccount {
                        Image(systemName: account.deviceType.iconName)
                            .foregroundColor(account.deviceType.brandColor)
                        Text(account.label ?? account.deviceType.displayName)
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(account.truncatedAddress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.secondary)
                        Text("Select Hardware Wallet")
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray).opacity(0.1))
                .cornerRadius(10)
            }
        }
    }
}

// MARK: - Signing Mode Toggle

/// Toggle between software and hardware wallet signing
struct SigningModeToggle: View {
    @Binding var useHardwareWallet: Bool
    @Binding var selectedHardwareAccount: HardwareWalletAccount?
    
    let chain: SupportedChain
    let hasHardwareAccounts: Bool
    let onSetupHardwareWallet: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Toggle
            HStack {
                Text("Signing Method")
                    .font(.headline)
                
                Spacer()
                
                Picker("Signing", selection: $useHardwareWallet) {
                    Text("Software").tag(false)
                    Text("Hardware").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            
            // Hardware wallet selector when enabled
            if useHardwareWallet {
                if hasHardwareAccounts {
                    HardwareWalletAccountSelector(
                        selectedAccount: $selectedHardwareAccount,
                        chain: chain,
                        onAddAccount: onSetupHardwareWallet
                    )
                } else {
                    setupPrompt
                }
            }
        }
        .padding()
        .background(Color(.systemGray).opacity(0.05))
        .cornerRadius(12)
    }
    
    private var setupPrompt: some View {
        Button(action: onSetupHardwareWallet) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect Hardware Wallet")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("Use Ledger or Trezor for secure signing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Device Status Indicator

/// Shows connection status of a hardware wallet device
struct HardwareWalletStatusIndicator: View {
    let account: HardwareWalletAccount
    @ObservedObject var manager: HardwareWalletManagerV2
    
    var isConnected: Bool {
        manager.discoveredDevices.contains { $0.deviceType == account.deviceType }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            Text(isConnected ? "Connected" : "Disconnected")
                .font(.caption)
                .foregroundColor(isConnected ? .green : .red)
        }
    }
}

// MARK: - Hardware Account Extension

extension HardwareWalletAccount {
    var truncatedAddress: String {
        guard address.count > 12 else { return address }
        let prefix = String(address.prefix(6))
        let suffix = String(address.suffix(4))
        return "\(prefix)...\(suffix)"
    }
}

// MARK: - Send View Hardware Wallet Section

/// Section to add to SendView for hardware wallet signing option
struct SendHardwareWalletSection: View {
    @Binding var isEnabled: Bool
    @Binding var selectedAccount: HardwareWalletAccount?
    
    let chain: SupportedChain
    @State private var showSetupSheet = false
    @ObservedObject private var manager = HardwareWalletManagerV2.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Image(systemName: "lock.shield")
                    .foregroundColor(.accentColor)
                Text("Hardware Wallet")
                    .font(.headline)
                
                Spacer()
                
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
            }
            
            if isEnabled {
                if manager.savedAccounts.isEmpty {
                    // No accounts - show setup prompt
                    noAccountsView
                } else {
                    // Show account selector
                    accountSelector
                }
            }
        }
        .padding()
        .background(Color(.systemGray).opacity(0.05))
        .cornerRadius(12)
        .sheet(isPresented: $showSetupSheet) {
            HardwareWalletSetupSheet(chain: chain) { account in
                selectedAccount = account
            }
        }
    }
    
    private var noAccountsView: some View {
        Button {
            showSetupSheet = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect Hardware Wallet")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("Sign transactions with Ledger or Trezor")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundColor(.accentColor)
            }
            .padding()
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private var accountSelector: some View {
        VStack(spacing: 8) {
            ForEach(manager.savedAccounts.filter { $0.chain == chain }) { account in
                accountRow(account)
            }
            
            // Add new account button
            Button {
                showSetupSheet = true
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("Add Device")
                }
                .font(.subheadline)
                .foregroundColor(.accentColor)
            }
        }
    }
    
    private func accountRow(_ account: HardwareWalletAccount) -> some View {
        Button {
            selectedAccount = account
        } label: {
            HStack {
                // Device icon
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(account.deviceType.brandColor.opacity(0.2))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: account.deviceType.iconName)
                        .foregroundColor(account.deviceType.brandColor)
                }
                
                // Account info
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.label ?? account.deviceType.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(account.truncatedAddress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Selection indicator
                if selectedAccount?.id == account.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                } else {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                selectedAccount?.id == account.id
                    ? Color.accentColor.opacity(0.1)
                    : Color.clear
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
struct HardwareWalletAccountSelector_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            HardwareWalletAccountSelector(
                selectedAccount: .constant(nil),
                chain: .ethereum,
                onAddAccount: {}
            )
            
            SigningModeToggle(
                useHardwareWallet: .constant(true),
                selectedHardwareAccount: .constant(nil),
                chain: .ethereum,
                hasHardwareAccounts: false,
                onSetupHardwareWallet: {}
            )
            
            SendHardwareWalletSection(
                isEnabled: .constant(true),
                selectedAccount: .constant(nil),
                chain: .ethereum
            )
        }
        .padding()
    }
}
#endif
