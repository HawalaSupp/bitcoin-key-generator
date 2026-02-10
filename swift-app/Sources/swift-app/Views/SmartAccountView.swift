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
        NavigationView {
            List {
                if accounts.isEmpty && !isLoading {
                    emptyStateView
                } else {
                    accountsSection
                    benefitsSection
                }
            }
            .navigationTitle("Smart Accounts")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingCreateSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                    }
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
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("No Smart Accounts")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Create an ERC-4337 smart account to enable advanced features like gasless transactions, batch operations, and social recovery.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: { showingCreateSheet = true }) {
                Label("Create Smart Account", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
        .padding()
    }
    
    private var accountsSection: some View {
        Section("Your Smart Accounts") {
            ForEach(accounts) { account in
                SmartAccountRow(account: account)
                    .onTapGesture {
                        selectedAccount = account
                    }
            }
        }
    }
    
    private var benefitsSection: some View {
        Section("Smart Account Benefits") {
            BenefitRow(
                icon: "dollarsign.circle",
                title: "Gasless Transactions",
                description: "Pay gas with stablecoins or get sponsored"
            )
            BenefitRow(
                icon: "rectangle.stack",
                title: "Batch Operations",
                description: "Execute multiple actions in one transaction"
            )
            BenefitRow(
                icon: "person.3",
                title: "Social Recovery",
                description: "Recover your account with trusted contacts"
            )
            BenefitRow(
                icon: "lock.shield",
                title: "Enhanced Security",
                description: "Spending limits, 2FA, and session keys"
            )
        }
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
        HStack {
            Image(systemName: account.accountType.icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 44, height: 44)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(account.accountType.displayName)
                    .font(.headline)
                
                Text(account.shortAddress)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(account.balance)
                    .font(.headline)
                
                statusBadge
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusBadge: some View {
        Text(account.isDeployed ? "Deployed" : "Not Deployed")
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(account.isDeployed ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
            .foregroundColor(account.isDeployed ? .green : .orange)
            .cornerRadius(4)
    }
}

struct BenefitRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.green)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
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
        NavigationView {
            Form {
                Section("Account Type") {
                    ForEach(AccountType.allCases, id: \.self) { type in
                        HStack {
                            Image(systemName: type.icon)
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading) {
                                Text(type.displayName)
                                    .font(.headline)
                                Text(type.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if accountType == type {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            accountType = type
                        }
                    }
                }
                
                Section("Network") {
                    Picker("Chain", selection: $selectedChain) {
                        ForEach(chains, id: \.self) { chain in
                            Text(chain).tag(chain)
                        }
                    }
                }
                
                Section {
                    Button(action: onCreate) {
                        if isCreating {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                Text("Creating...")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text("Create Smart Account")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isCreating)
                }
            }
            .navigationTitle("New Smart Account")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
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
