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
        HawalaSheetShell(title: "Gas Account", width: 480, height: 620) {
            balanceCard
            
            if !chainBalances.isEmpty {
                chainBreakdownSection
            }
            
            settingsSection
            
            howItWorksSection
        }
        .sheet(isPresented: $showingDepositSheet) {
            GasDepositSheet(onDeposit: handleDeposit)
        }
        .sheet(isPresented: $showingWithdrawSheet) {
            GasWithdrawSheet(maxAmount: totalBalanceUSD, onWithdraw: handleWithdraw)
        }
        .onAppear(perform: loadGasAccount)
    }
    
    private var balanceCard: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "fuelpump.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color(red: 1, green: 0.84, blue: 0.04))
                Text("Gas Balance")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                if isRefreshing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.4)))
                        .scaleEffect(0.7)
                } else {
                    Button(action: refreshBalances) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Text("$\(totalBalanceUSD, specifier: "%.2f")")
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
            
            if totalBalanceUSD < lowBalanceAlert {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 1, green: 0.84, blue: 0.04))
                    Text("Low balance — consider topping up")
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 1, green: 0.84, blue: 0.04).opacity(0.8))
                }
            }
            
            HStack(spacing: 10) {
                HawalaActionButton(icon: "arrow.down.circle.fill", label: "Deposit", style: .primary) {
                    showingDepositSheet = true
                }
                HawalaActionButton(icon: "arrow.up.circle.fill", label: "Withdraw", style: .secondary) {
                    showingWithdrawSheet = true
                }
            }
        }
        .hawalaSectionCard()
    }
    
    private var chainBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HawalaOverlaySectionHeader(icon: "chart.bar.fill", title: "Balance by Chain")
            ForEach(chainBalances) { balance in
                ChainGasRow(balance: balance)
            }
        }
        .hawalaSectionCard()
    }
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HawalaOverlaySectionHeader(icon: "gearshape.fill", title: "Settings")
            HawalaToggleRow(icon: "arrow.triangle.2.circlepath", label: "Auto-Refill", isOn: $autoRefillEnabled)
            
            if autoRefillEnabled {
                HStack {
                    Text("Refill when below")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    Text("$\(lowBalanceAlert, specifier: "%.0f")")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.5))
                }
                Slider(value: $lowBalanceAlert, in: 1...50, step: 1)
                    .tint(Color.white)
            }
            
            Rectangle().fill(.white.opacity(0.04)).frame(height: 1)
            
            HawalaToggleRow(icon: "bell.badge", label: "Low Balance Alerts", isOn: .constant(true))
        }
        .hawalaSectionCard()
    }
    
    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HawalaOverlaySectionHeader(icon: "questionmark.circle", title: "How It Works")
            GasFeatureRow(icon: "1.circle.fill", title: "Deposit Once", description: "Add funds to your gas account on any chain")
            GasFeatureRow(icon: "2.circle.fill", title: "Use Everywhere", description: "Pay for gas on any supported network")
            GasFeatureRow(icon: "3.circle.fill", title: "No ETH Needed", description: "We handle the cross-chain bridging for you")
            Text("Supported: Ethereum, Polygon, Arbitrum, Optimism, Base, Avalanche, BNB Chain")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.25))
                .padding(.top, 2)
        }
        .hawalaSectionCard()
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
        HStack(spacing: 10) {
            chainIcon
            
            VStack(alignment: .leading, spacing: 2) {
                Text(balance.chain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Text("\(balance.amount) \(balance.symbol)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }
            
            Spacer()
            
            Text("$\(balance.usdValue, specifier: "%.2f")")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
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
                    .foregroundColor(.white.opacity(0.2))
            }
        }
        .font(.system(size: 16))
        .frame(width: 24)
    }
}

struct GasDepositSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onDeposit: (String, Double) -> Void
    
    @State private var selectedChain = "Ethereum"
    @State private var depositAmount = ""
    
    let chains = ["Ethereum", "Polygon", "Arbitrum", "Base"]
    
    var body: some View {
        HawalaSheetShell(title: "Deposit to Gas Account", width: 420, height: 380) {
            VStack(alignment: .leading, spacing: 8) {
                HawalaOverlaySectionHeader(icon: "link", title: "Select Chain")
                HStack(spacing: 6) {
                    ForEach(chains, id: \.self) { chain in
                        Button {
                            selectedChain = chain
                        } label: {
                            Text(chain)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(selectedChain == chain ? .white : .white.opacity(0.4))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    selectedChain == chain
                                        ? Color.white.opacity(0.3)
                                        : Color.white.opacity(0.04)
                                )
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().strokeBorder(
                                        selectedChain == chain
                                            ? Color.white.opacity(0.5)
                                            : .clear,
                                        lineWidth: 1
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .hawalaSectionCard()

            VStack(alignment: .leading, spacing: 8) {
                HawalaOverlaySectionHeader(icon: "dollarsign.circle", title: "Amount")
                HStack(spacing: 4) {
                    Text("$")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.35))
                    TextField("0.00", text: $depositAmount)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 6) {
                    ForEach(["10", "25", "50", "100"], id: \.self) { amount in
                        Button("$\(amount)") { depositAmount = amount }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.04))
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                    }
                }
            }
            .hawalaSectionCard()

            HawalaActionButton(icon: "arrow.down.circle.fill", label: "Deposit", style: .primary) {
                if let amount = Double(depositAmount) {
                    onDeposit(selectedChain, amount)
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
        HawalaSheetShell(title: "Withdraw from Gas Account", width: 420, height: 440) {
            VStack(alignment: .leading, spacing: 8) {
                HawalaOverlaySectionHeader(icon: "arrow.right.circle", title: "Withdraw To")
                TextField("0x...", text: $withdrawAddress)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .hawalaSectionCard()

            VStack(alignment: .leading, spacing: 8) {
                HawalaOverlaySectionHeader(icon: "link", title: "Select Chain")
                Picker("Chain", selection: $selectedChain) {
                    ForEach(chains, id: \.self) { chain in
                        Text(chain).tag(chain)
                    }
                }
                .pickerStyle(.segmented)
            }
            .hawalaSectionCard()

            VStack(alignment: .leading, spacing: 8) {
                HawalaOverlaySectionHeader(icon: "dollarsign.circle", title: "Amount")
                HStack(spacing: 4) {
                    Text("$")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.35))
                    TextField("0.00", text: $withdrawAmount)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    Text("Available: $\(maxAmount, specifier: "%.2f")")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                    Spacer()
                    Button("Max") { withdrawAmount = String(format: "%.2f", maxAmount) }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.5))
                        .buttonStyle(.plain)
                }
            }
            .hawalaSectionCard()

            HawalaActionButton(icon: "arrow.up.circle.fill", label: "Withdraw", style: .primary) {
                if let amount = Double(withdrawAmount) {
                    onWithdraw(selectedChain, amount)
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Color.white.opacity(0.5))
                .frame(width: 24)
            
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

struct GasAccountView_Previews: PreviewProvider {
    static var previews: some View {
        GasAccountView()
    }
}
