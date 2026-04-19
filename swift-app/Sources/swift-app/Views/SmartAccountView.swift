// SmartAccountView.swift
// ERC-4337 Smart Account Management
// Created for Hawala - Phase 4

import SwiftUI

struct SmartAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var accounts: [SmartAccountInfo] = []
    @State private var isCreating = false
    @State private var isLoading = false
    @State private var selectedAccountType: AccountType = .simpleAccount
    @State private var showingCreateSheet = false
    @State private var selectedAccount: SmartAccountInfo?
    @State private var errorMessage: String?
    
    var body: some View {
        HawalaSheetShell(title: "Smart Accounts", width: 480, height: 580) {
            if accounts.isEmpty && !isLoading {
                emptyStateView
            } else {
                accountsSection
                benefitsSection
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateSmartAccountSheet(
                accountType: $selectedAccountType,
                isCreating: $isCreating,
                onCreate: createSmartAccount
            )
        }
        .alert("Something Went Wrong", isPresented: .constant(errorMessage != nil)) {
            Button("Dismiss") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear(perform: loadAccounts)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 48))
                .foregroundColor(Color.white.opacity(0.5))
            
            Text("No Smart Accounts")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            
            Text("Create an ERC-4337 smart account to enable advanced features like gasless transactions, batch operations, and social recovery.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
            
            HawalaActionButton(icon: "plus.circle.fill", label: "Create Smart Account", style: .primary) {
                showingCreateSheet = true
            }
        }
    }
    
    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HawalaOverlaySectionHeader(icon: "person.crop.circle", title: "Your Smart Accounts")
                Spacer()
                Button { showingCreateSheet = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            
            ForEach(accounts) { account in
                SmartAccountRow(account: account)
                    .onTapGesture { selectedAccount = account }
            }
        }
        .hawalaSectionCard()
    }
    
    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HawalaOverlaySectionHeader(icon: "sparkles", title: "Smart Account Benefits")
            BenefitRow(icon: "dollarsign.circle", title: "Gasless Transactions", description: "Pay gas with stablecoins or get sponsored")
            BenefitRow(icon: "rectangle.stack", title: "Batch Operations", description: "Execute multiple actions in one transaction")
            BenefitRow(icon: "person.3", title: "Social Recovery", description: "Recover your account with trusted contacts")
            BenefitRow(icon: "lock.shield", title: "Enhanced Security", description: "Spending limits, 2FA, and session keys")
        }
        .hawalaSectionCard()
    }
    
    private func loadAccounts() {
        isLoading = true
        // In production, this would call the Rust backend
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isLoading = false
        }
    }
    
    private func createSmartAccount() {
        isCreating = true
        // Call HawalaBridge to create smart account
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let newAccount = SmartAccountInfo(
                id: UUID().uuidString,
                address: "0x" + String(repeating: "a", count: 40),
                accountType: selectedAccountType,
                isDeployed: false,
                chainId: 1,
                balance: "0.0"
            )
            accounts.append(newAccount)
            isCreating = false
            showingCreateSheet = false
        }
    }
}

struct SmartAccountRow: View {
    let account: SmartAccountInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.accountType.icon)
                .font(.system(size: 18))
                .foregroundColor(Color.white.opacity(0.5))
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 3) {
                Text(account.accountType.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Text(account.shortAddress)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(account.balance)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                statusBadge
            }
        }
        .padding(.vertical, 4)
    }

    private var statusBadge: some View {
        Text(account.isDeployed ? "Deployed" : "Not Deployed")
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(account.isDeployed ? Color(red: 0.20, green: 0.84, blue: 0.29).opacity(0.12) : Color(red: 1, green: 0.84, blue: 0.04).opacity(0.12))
            .foregroundColor(account.isDeployed ? Color(red: 0.20, green: 0.84, blue: 0.29) : Color(red: 1, green: 0.84, blue: 0.04))
            .clipShape(Capsule())
    }
}

struct BenefitRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Color(red: 0.20, green: 0.84, blue: 0.29))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Text(description)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
    }
}

struct CreateSmartAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var accountType: AccountType
    @Binding var isCreating: Bool
    let onCreate: () -> Void
    
    @State private var selectedChain = "Ethereum"
    let chains = ["Ethereum", "Polygon", "Arbitrum", "Optimism", "Base"]
    
    var body: some View {
        HawalaSheetShell(title: "New Smart Account", width: 420, height: 500) {
            VStack(alignment: .leading, spacing: 8) {
                HawalaOverlaySectionHeader(icon: "person.crop.circle", title: "Account Type")
                ForEach(AccountType.allCases, id: \.self) { type in
                    Button {
                        accountType = type
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: type.icon)
                                .font(.system(size: 14))
                                .foregroundColor(Color.white.opacity(0.5))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(type.displayName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.85))
                                Text(type.description)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.35))
                            }
                            Spacer()
                            if accountType == type {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color.white.opacity(0.5))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .hawalaSectionCard()

            VStack(alignment: .leading, spacing: 8) {
                HawalaOverlaySectionHeader(icon: "network", title: "Network")
                Picker("Chain", selection: $selectedChain) {
                    ForEach(chains, id: \.self) { chain in
                        Text(chain).tag(chain)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.white)
            }
            .hawalaSectionCard()

            HawalaActionButton(icon: isCreating ? "hourglass" : "plus.circle.fill", label: isCreating ? "Creating..." : "Create Smart Account", style: .primary) {
                onCreate()
            }
            .disabled(isCreating)
            .opacity(isCreating ? 0.5 : 1)
        }
    }
}

// MARK: - Data Types

struct SmartAccountInfo: Identifiable {
    let id: String
    let address: String
    let accountType: AccountType
    let isDeployed: Bool
    let chainId: Int
    let balance: String
    
    var shortAddress: String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(8))...\(address.suffix(4))"
    }
}

enum AccountType: String, CaseIterable {
    case simpleAccount = "simple"
    case safe = "safe"
    case kernel = "kernel"
    case lightAccount = "light"
    
    var displayName: String {
        switch self {
        case .simpleAccount: return "Simple Account"
        case .safe: return "Safe (Gnosis)"
        case .kernel: return "Kernel (ZeroDev)"
        case .lightAccount: return "Light Account"
        }
    }
    
    var description: String {
        switch self {
        case .simpleAccount: return "Basic ERC-4337 account"
        case .safe: return "Multi-sig with modules"
        case .kernel: return "Modular & extensible"
        case .lightAccount: return "Gas-optimized"
        }
    }
    
    var icon: String {
        switch self {
        case .simpleAccount: return "person.circle"
        case .safe: return "lock.shield"
        case .kernel: return "cpu"
        case .lightAccount: return "bolt.circle"
        }
    }
}

struct SmartAccountView_Previews: PreviewProvider {
    static var previews: some View {
        SmartAccountView()
    }
}
