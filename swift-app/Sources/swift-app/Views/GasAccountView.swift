// GasAccountView.swift
// Multi-Chain Gas Management
// Created for Hawala - Phase 4

import SwiftUI

struct GasAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var totalBalanceUSD: Double = 0.0
    @State private var chainBalances: [ChainGasBalance] = []
    @State private var isRefreshing = false
    @State private var showingDepositSheet = false
    @State private var showingWithdrawSheet = false
    @State private var autoRefillEnabled = false
    @State private var lowBalanceAlert: Double = 5.0
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    balanceCard
                    
                    if !chainBalances.isEmpty {
                        chainBreakdownSection
                    }
                    
                    settingsSection
                    
                    howItWorksSection
                }
                .padding()
            }
            .navigationTitle("Gas Account")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: refreshBalances) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isRefreshing)
                }
            }
            .sheet(isPresented: $showingDepositSheet) {
                GasDepositSheet(onDeposit: handleDeposit)
            }
            .sheet(isPresented: $showingWithdrawSheet) {
                GasWithdrawSheet(maxAmount: totalBalanceUSD, onWithdraw: handleWithdraw)
            }
            .onAppear(perform: loadGasAccount)
        }
    }
    
    private var balanceCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "fuelpump.circle.fill")
                    .font(.title)
                    .foregroundColor(.orange)
                
                Text("Gas Balance")
                    .font(.headline)
                
                Spacer()
                
                if isRefreshing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
            
            Text("$\(totalBalanceUSD, specifier: "%.2f")")
                .font(.system(size: 48, weight: .bold, design: .rounded))
            
            if totalBalanceUSD < lowBalanceAlert {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Low balance - consider topping up")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            HStack(spacing: 12) {
                Button(action: { showingDepositSheet = true }) {
                    Label("Deposit", systemImage: "arrow.down.circle.fill")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
                Button(action: { showingWithdrawSheet = true }) {
                    Label("Withdraw", systemImage: "arrow.up.circle.fill")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(totalBalanceUSD <= 0)
            }
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.orange.opacity(0.2), Color.red.opacity(0.1)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
    }
    
    private var chainBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Balance by Chain")
                .font(.headline)
            
            ForEach(chainBalances) { balance in
                ChainGasRow(balance: balance)
            }
        }
        .padding()
        .background(Color.white.opacity(0.8))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 8)
    }
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)
            
            Toggle("Auto-Refill", isOn: $autoRefillEnabled)
            
            if autoRefillEnabled {
                HStack {
                    Text("Refill when below")
                    Spacer()
                    Text("$\(lowBalanceAlert, specifier: "%.0f")")
                        .foregroundColor(.secondary)
                }
                
                Slider(value: $lowBalanceAlert, in: 1...50, step: 1)
            }
            
            Divider()
            
            HStack {
                Image(systemName: "bell.badge")
                    .foregroundColor(.blue)
                Text("Low Balance Alerts")
                Spacer()
                Toggle("", isOn: .constant(true))
                    .labelsHidden()
            }
        }
        .padding()
        .background(Color.white.opacity(0.8))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 8)
    }
    
    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How It Works")
                .font(.headline)
            
            GasFeatureRow(
                icon: "1.circle.fill",
                title: "Deposit Once",
                description: "Add funds to your gas account on any chain"
            )
            
            GasFeatureRow(
                icon: "2.circle.fill",
                title: "Use Everywhere",
                description: "Pay for gas on any supported network"
            )
            
            GasFeatureRow(
                icon: "3.circle.fill",
                title: "No ETH Needed",
                description: "We handle the cross-chain bridging for you"
            )
            
            Text("Supported: Ethereum, Polygon, Arbitrum, Optimism, Base, Avalanche, BNB Chain")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.white.opacity(0.8))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 8)
    }
    
    private func loadGasAccount() {
        isRefreshing = true
        // Call HawalaBridge to get gas account info
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Demo data
            chainBalances = [
                ChainGasBalance(id: "1", chain: "Ethereum", symbol: "ETH", amount: "0.005", usdValue: 12.50),
                ChainGasBalance(id: "137", chain: "Polygon", symbol: "MATIC", amount: "10.0", usdValue: 8.50),
                ChainGasBalance(id: "8453", chain: "Base", symbol: "ETH", amount: "0.002", usdValue: 5.00),
            ]
            totalBalanceUSD = chainBalances.reduce(0) { $0 + $1.usdValue }
            isRefreshing = false
        }
    }
    
    private func refreshBalances() {
        loadGasAccount()
    }
    
    private func handleDeposit(chain: String, amount: Double) {
        // Handle deposit
        showingDepositSheet = false
        loadGasAccount()
    }
    
    private func handleWithdraw(chain: String, amount: Double) {
        // Handle withdrawal
        showingWithdrawSheet = false
        loadGasAccount()
    }
}

struct ChainGasRow: View {
    let balance: ChainGasBalance
    
    var body: some View {
        HStack {
            chainIcon
            
            VStack(alignment: .leading, spacing: 2) {
                Text(balance.chain)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(balance.amount) \(balance.symbol)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("$\(balance.usdValue, specifier: "%.2f")")
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding(.vertical, 4)
    }
    
    private var chainIcon: some View {
        Group {
            switch balance.chain.lowercased() {
            case "ethereum":
                Image(systemName: "diamond.fill")
                    .foregroundColor(.blue)
            case "polygon":
                Image(systemName: "hexagon.fill")
                    .foregroundColor(.purple)
            case "arbitrum":
                Image(systemName: "a.circle.fill")
                    .foregroundColor(.blue)
            case "base":
                Image(systemName: "b.circle.fill")
                    .foregroundColor(.blue)
            default:
                Image(systemName: "circle.fill")
                    .foregroundColor(.gray)
            }
        }
        .font(.title2)
        .frame(width: 32)
    }
}

struct GasDepositSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onDeposit: (String, Double) -> Void
    
    @State private var selectedChain = "Ethereum"
    @State private var depositAmount = ""
    
    let chains = ["Ethereum", "Polygon", "Arbitrum", "Base"]
    
    var body: some View {
        NavigationView {
            Form {
                Section("Select Chain") {
                    Picker("Chain", selection: $selectedChain) {
                        ForEach(chains, id: \.self) { chain in
                            Text(chain).tag(chain)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section("Amount") {
                    HStack {
                        Text("$")
                        TextField("0.00", text: $depositAmount)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    
                    HStack(spacing: 12) {
                        ForEach(["10", "25", "50", "100"], id: \.self) { amount in
                            Button("$\(amount)") {
                                depositAmount = amount
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                
                Section {
                    Button("Deposit") {
                        if let amount = Double(depositAmount) {
                            onDeposit(selectedChain, amount)
                        }
                    }
                    .disabled(depositAmount.isEmpty)
                }
            }
            .navigationTitle("Deposit to Gas Account")
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

struct GasWithdrawSheet: View {
    @Environment(\.dismiss) private var dismiss
    let maxAmount: Double
    let onWithdraw: (String, Double) -> Void
    
    @State private var selectedChain = "Ethereum"
    @State private var withdrawAmount = ""
    @State private var withdrawAddress = ""
    
    let chains = ["Ethereum", "Polygon", "Arbitrum", "Base"]
    
    var body: some View {
        NavigationView {
            Form {
                Section("Withdraw To") {
                    TextField("0x...", text: $withdrawAddress)
                        .font(.system(.body, design: .monospaced))
                }
                
                Section("Select Chain") {
                    Picker("Chain", selection: $selectedChain) {
                        ForEach(chains, id: \.self) { chain in
                            Text(chain).tag(chain)
                        }
                    }
                }
                
                Section("Amount") {
                    HStack {
                        Text("$")
                        TextField("0.00", text: $withdrawAmount)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    
                    Text("Available: $\(maxAmount, specifier: "%.2f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Max") {
                        withdrawAmount = String(format: "%.2f", maxAmount)
                    }
                }
                
                Section {
                    Button("Withdraw") {
                        if let amount = Double(withdrawAmount) {
                            onWithdraw(selectedChain, amount)
                        }
                    }
                    .disabled(withdrawAmount.isEmpty || withdrawAddress.isEmpty)
                }
            }
            .navigationTitle("Withdraw from Gas Account")
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

struct ChainGasBalance: Identifiable {
    let id: String
    let chain: String
    let symbol: String
    let amount: String
    let usdValue: Double
}

// Local FeatureRow for GasAccountView (different from SettingsView's FeatureRow)
private struct GasFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct GasAccountView_Previews: PreviewProvider {
    static var previews: some View {
        GasAccountView()
    }
}
