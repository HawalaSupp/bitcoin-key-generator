// GaslessTxView.swift
// Gasless Transaction (Paymaster) View
// Created for Hawala - Phase 4

import SwiftUI

struct GaslessTxView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isEnabled = true
    @State private var sponsorshipAvailable = true
    @State private var sponsorships: [SponsorshipInfo] = []
    @State private var recentGasless: [GaslessTxRecord] = []
    @State private var selectedProvider = "Pimlico"
    @State private var showingProviderSettings = false
    
    let providers = ["Pimlico", "Alchemy", "Stackup", "ZeroDev"]
    
    var body: some View {
        HawalaSheetShell(title: "Gasless Transactions", width: 480, height: 600) {
            statusSection

            if isEnabled {
                sponsorshipsSection
                recentTransactionsSection
                providerSection
            }

            howItWorksSection
        }
        .sheet(isPresented: $showingProviderSettings) {
            PaymasterProviderSettings(selectedProvider: $selectedProvider)
        }
        .onAppear(perform: loadData)
    }
    
    private var statusSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(sponsorshipAvailable ? Color(red: 0.20, green: 0.84, blue: 0.29).opacity(0.1) : Color.white.opacity(0.04))
                    .frame(width: 64, height: 64)
                Image(systemName: sponsorshipAvailable ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.system(size: 32))
                    .foregroundColor(sponsorshipAvailable ? Color(red: 0.20, green: 0.84, blue: 0.29) : .white.opacity(0.3))
            }

            Text(sponsorshipAvailable ? "Sponsorship Available" : "No Sponsorship")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white.opacity(0.85))

            Text(sponsorshipAvailable ? "Your next transaction can be gasless!" : "Enable gasless transactions to get started")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)

            HawalaToggleRow(icon: "bolt.circle.fill", label: "Enable Gasless", isOn: $isEnabled)
        }
        .hawalaSectionCard()
    }
    
    private var sponsorshipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HawalaOverlaySectionHeader(icon: "gift.fill", title: "Active Sponsorships")
            if sponsorships.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "gift")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 1, green: 0.84, blue: 0.04))
                    Text("No active sponsorships")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.35))
                }
            } else {
                ForEach(sponsorships) { sponsorship in
                    SponsorshipRow(sponsorship: sponsorship)
                }
            }
        }
        .hawalaSectionCard()
    }
    
    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HawalaOverlaySectionHeader(icon: "clock.fill", title: "Recent Gasless")
            if recentGasless.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.25))
                    Text("No gasless transactions yet")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.35))
                }
            } else {
                ForEach(recentGasless) { tx in
                    GaslessTxRow(tx: tx)
                }
            }
        }
        .hawalaSectionCard()
    }
    
    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HawalaOverlaySectionHeader(icon: "server.rack", title: "Paymaster Provider")
            HStack {
                Text(selectedProvider)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Button("Change") { showingProviderSettings = true }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.5))
                    .buttonStyle(.plain)
            }
            HStack {
                Text("API Status")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Color(red: 0.20, green: 0.84, blue: 0.29)).frame(width: 6, height: 6)
                    Text("Connected")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(red: 0.20, green: 0.84, blue: 0.29))
                }
            }
        }
        .hawalaSectionCard()
    }
    
    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HawalaOverlaySectionHeader(icon: "questionmark.circle", title: "How It Works")
            StepRow(number: 1, title: "Create Transaction", description: "Build your transaction as usual")
            StepRow(number: 2, title: "Check Sponsorship", description: "We check if a paymaster will cover gas")
            StepRow(number: 3, title: "Sign & Submit", description: "Sign with your key, paymaster pays gas")
            Text("You only sign once. The paymaster covers all gas fees.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
                .padding(.top, 4)
        }
        .hawalaSectionCard()
    }
    
    private func loadData() {
        // Load sponsorships and recent gasless transactions
        sponsorships = [
            SponsorshipInfo(
                id: "1",
                name: "New User Bonus",
                description: "First 5 transactions free",
                remaining: 5,
                expiresAt: Calendar.current.date(byAdding: .day, value: 30, to: Date())!
            ),
            SponsorshipInfo(
                id: "2",
                name: "Uniswap Promo",
                description: "Gasless swaps on Uniswap",
                remaining: 3,
                expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: Date())!
            )
        ]
        
        recentGasless = [
            GaslessTxRecord(
                id: "tx1",
                action: "Swap ETH → USDC",
                chain: "Arbitrum",
                gasSaved: "$0.45",
                timestamp: Date().addingTimeInterval(-3600)
            ),
            GaslessTxRecord(
                id: "tx2",
                action: "Approve USDC",
                chain: "Base",
                gasSaved: "$0.12",
                timestamp: Date().addingTimeInterval(-86400)
            )
        ]
    }
}

struct SponsorshipRow: View {
    let sponsorship: SponsorshipInfo
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "gift.fill")
                .font(.system(size: 16))
                .foregroundColor(Color(red: 1, green: 0.84, blue: 0.04))
                .frame(width: 32, height: 32)
                .background(Color(red: 1, green: 0.84, blue: 0.04).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(sponsorship.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Text("\(sponsorship.remaining) transactions left")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("Expires")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.25))
                Text(sponsorship.expiresAt, style: .date)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.vertical, 4)
    }
}

struct GaslessTxRow: View {
    let tx: GaslessTxRecord
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(Color(red: 0.20, green: 0.84, blue: 0.29))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.action)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                HStack(spacing: 4) {
                    Text(tx.chain)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                    Text("·")
                        .foregroundColor(.white.opacity(0.2))
                    Text(tx.timestamp, style: .relative)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("Saved")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.25))
                Text(tx.gasSaved)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(red: 0.20, green: 0.84, blue: 0.29))
            }
        }
        .padding(.vertical, 4)
    }
}

struct StepRow: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(0.12)))
            
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

struct PaymasterProviderSettings: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedProvider: String
    
    let providers = [
        ("Pimlico", "Most reliable, best coverage"),
        ("Alchemy", "Integrated with Alchemy SDK"),
        ("Stackup", "Open source bundler"),
        ("ZeroDev", "Best for Kernel accounts")
    ]
    
    var body: some View {
        HawalaSheetShell(title: "Paymaster Provider", width: 400, height: 400) {
            VStack(alignment: .leading, spacing: 8) {
                HawalaOverlaySectionHeader(icon: "checkmark.circle", title: "Select Provider")
                ForEach(providers, id: \.0) { provider, description in
                    Button {
                        selectedProvider = provider
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.85))
                                Text(description)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.35))
                            }
                            Spacer()
                            if selectedProvider == provider {
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
                HawalaOverlaySectionHeader(icon: "key.fill", title: "API Key")
                HawalaSecureField(placeholder: "Enter API Key", text: .constant(""))
                Link(destination: URL(string: "https://pimlico.io")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                        Text("Get API Key")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Color.white.opacity(0.5))
                }
            }
            .hawalaSectionCard()
        }
    }
}

struct FindSponsorshipsView: View {
    var body: some View {
        HawalaSheetShell(title: "Find Sponsorships", width: 420, height: 400) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sponsorships are offered by protocols and dApps to encourage usage. Check back often for new offers!")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                    .lineSpacing(2)
            }
            .hawalaSectionCard()

            VStack(alignment: .leading, spacing: 10) {
                HawalaOverlaySectionHeader(icon: "sparkles", title: "Available Sponsorships")

                HStack(spacing: 10) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14))
                        .foregroundColor(.pink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Uniswap")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                        Text("Free swaps this week")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    Spacer()
                    Button("Claim") {}
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    Image(systemName: "circle.hexagongrid")
                        .font(.system(size: 14))
                        .foregroundColor(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Polygon")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                        Text("10 free transactions")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    Spacer()
                    Button("Claim") {}
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                }
            }
            .hawalaSectionCard()
        }
    }
}

// MARK: - Data Types

struct SponsorshipInfo: Identifiable {
    let id: String
    let name: String
    let description: String
    let remaining: Int
    let expiresAt: Date
}

struct GaslessTxRecord: Identifiable {
    let id: String
    let action: String
    let chain: String
    let gasSaved: String
    let timestamp: Date
}

struct GaslessTxView_Previews: PreviewProvider {
    static var previews: some View {
        GaslessTxView()
    }
}
