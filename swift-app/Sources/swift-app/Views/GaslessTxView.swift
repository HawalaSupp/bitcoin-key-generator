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
        NavigationView {
            List {
                statusSection
                
                if isEnabled {
                    sponsorshipsSection
                    recentTransactionsSection
                    providerSection
                }
                
                howItWorksSection
            }
            .navigationTitle("Gasless Transactions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingProviderSettings) {
                PaymasterProviderSettings(selectedProvider: $selectedProvider)
            }
            .onAppear(perform: loadData)
        }
    }
    
    private var statusSection: some View {
        Section {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(sponsorshipAvailable ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: sponsorshipAvailable ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .font(.system(size: 40))
                        .foregroundColor(sponsorshipAvailable ? .green : .gray)
                }
                
                Text(sponsorshipAvailable ? "Sponsorship Available" : "No Sponsorship")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(sponsorshipAvailable 
                    ? "Your next transaction can be gasless!"
                    : "Enable gasless transactions to get started")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Toggle("Enable Gasless Transactions", isOn: $isEnabled)
                    .padding(.top)
            }
            .padding()
        }
    }
    
    private var sponsorshipsSection: some View {
        Section("Active Sponsorships") {
            if sponsorships.isEmpty {
                HStack {
                    Image(systemName: "gift")
                        .foregroundColor(.orange)
                    Text("No active sponsorships")
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(sponsorships) { sponsorship in
                    SponsorshipRow(sponsorship: sponsorship)
                }
            }
            
            NavigationLink(destination: FindSponsorshipsView()) {
                Label("Find Sponsorships", systemImage: "magnifyingglass")
            }
        }
    }
    
    private var recentTransactionsSection: some View {
        Section("Recent Gasless Transactions") {
            if recentGasless.isEmpty {
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    Text("No gasless transactions yet")
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(recentGasless) { tx in
                    GaslessTxRow(tx: tx)
                }
            }
        }
    }
    
    private var providerSection: some View {
        Section("Paymaster Provider") {
            HStack {
                Image(systemName: "server.rack")
                    .foregroundColor(.blue)
                Text(selectedProvider)
                Spacer()
                Button("Change") {
                    showingProviderSettings = true
                }
            }
            
            HStack {
                Text("API Status")
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Connected")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
        }
    }
    
    private var howItWorksSection: some View {
        Section("How Gasless Transactions Work") {
            VStack(alignment: .leading, spacing: 16) {
                StepRow(
                    number: 1,
                    title: "Create Transaction",
                    description: "Build your transaction as usual"
                )
                
                StepRow(
                    number: 2,
                    title: "Check Sponsorship",
                    description: "We check if a paymaster will cover gas"
                )
                
                StepRow(
                    number: 3,
                    title: "Sign & Submit",
                    description: "Sign with your key, paymaster pays gas"
                )
                
                Text("You only sign once. The paymaster covers all gas fees.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            .padding(.vertical, 8)
        }
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
        HStack {
            Image(systemName: "gift.fill")
                .font(.title2)
                .foregroundColor(.orange)
                .frame(width: 44, height: 44)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(sponsorship.name)
                    .font(.headline)
                
                Text("\(sponsorship.remaining) transactions left")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("Expires")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text(sponsorship.expiresAt, style: .date)
                    .font(.caption)
            }
        }
    }
}

struct GaslessTxRow: View {
    let tx: GaslessTxRecord
    
    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.action)
                    .font(.subheadline)
                
                HStack {
                    Text(tx.chain)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(tx.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text("Saved")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text(tx.gasSaved)
                    .font(.subheadline)
                    .foregroundColor(.green)
            }
        }
    }
}

struct StepRow: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.blue))
            
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
        NavigationView {
            List {
                Section("Select Provider") {
                    ForEach(providers, id: \.0) { provider, description in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(provider)
                                    .font(.headline)
                                Text(description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if selectedProvider == provider {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedProvider = provider
                        }
                    }
                }
                
                Section("API Key") {
                    SecureField("Enter API Key", text: .constant(""))
                    
                    Link(destination: URL(string: "https://pimlico.io")!) {
                        Label("Get API Key", systemImage: "arrow.up.right.square")
                    }
                }
            }
            .navigationTitle("Paymaster Provider")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct FindSponsorshipsView: View {
    var body: some View {
        List {
            Section {
                Text("Sponsorships are offered by protocols and dApps to encourage usage. Check back often for new offers!")
                    .foregroundColor(.secondary)
            }
            
            Section("Available Sponsorships") {
                HStack {
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundColor(.pink)
                    VStack(alignment: .leading) {
                        Text("Uniswap")
                        Text("Free swaps this week")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Claim") {}
                        .buttonStyle(.borderedProminent)
                }
                
                HStack {
                    Image(systemName: "circle.hexagongrid")
                        .foregroundColor(.purple)
                    VStack(alignment: .leading) {
                        Text("Polygon")
                        Text("10 free transactions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Claim") {}
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Find Sponsorships")
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
