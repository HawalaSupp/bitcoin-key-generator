import SwiftUI

/// IBC Transfer view for Cosmos chain transfers
struct IBCTransferView: View {
    @StateObject private var ibcService = IBCService.shared
    @State private var amount: String = ""
    @State private var memo: String = ""
    @State private var recipientAddress: String = ""
    @State private var showSettings = false
    @State private var showActiveTransfers = false
    @State private var confirmTransfer = false
    @State private var timeoutMinutes: Int = 10
    
    // Mock sender address based on source chain
    private var senderAddress: String {
        "\(ibcService.selectedSourceChain.bech32Prefix)1hsk6jryyqjfhp5dhc55tc9jtckygx0eph6dd02"
    }
    
    // MARK: - Beta Warning Banner
    
    private var betaWarningBanner: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Preview Feature")
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.15))
            .cornerRadius(8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Warning: Preview Feature. IBC transfers are simulated.")
            
            Text("IBC transfers are in preview. Transactions are simulated and do not move real funds.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Beta warning at top
                betaWarningBanner
                
                // Header
                headerSection
                
                // Source chain
                sourceChainSection
                
                // Swap button
                swapChainsButton
                
                // Destination chain
                destinationChainSection
                
                // Recipient address
                recipientSection
                
                // Amount input
                amountSection
                
                // Memo (optional)
                memoSection
                
                // Fee estimate
                feeSection
                
                // Transfer button
                transferButton
                
                // Active transfers
                if !ibcService.activeTransfers.isEmpty && showActiveTransfers {
                    activeTransfersSection
                }
            }
            .padding()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("IBC Transfer")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItem(placement: .automatic) {
                if !ibcService.activeTransfers.isEmpty {
                    Button(action: { showActiveTransfers.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left.arrow.right")
                            Text("\(ibcService.getPendingTransfers().count)")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
        .alert("Confirm IBC Transfer", isPresented: $confirmTransfer) {
            Button("Cancel", role: .cancel) {}
            Button("Transfer") {
                Task { await executeTransfer() }
            }
        } message: {
            Text("Transfer \(formattedAmount) \(ibcService.selectedSourceChain.nativeSymbol) from \(ibcService.selectedSourceChain.displayName) to \(ibcService.selectedDestinationChain.displayName)?")
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "link.circle.fill")
                    .font(.title2)
                    .foregroundColor(.purple)
                Text("Inter-Blockchain Communication")
                    .font(.headline)
                Spacer()
            }
            
            Text("Transfer tokens between Cosmos SDK chains")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var sourceChainSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("From Chain")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                chainSelector(
                    selection: $ibcService.selectedSourceChain,
                    chains: IBCService.CosmosChain.allCases
                )
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Balance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("100.00 \(ibcService.selectedSourceChain.nativeSymbol)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
        }
    }
    
    private var swapChainsButton: some View {
        Button(action: swapChains) {
            Image(systemName: "arrow.up.arrow.down.circle.fill")
                .font(.title)
                .foregroundColor(.purple)
        }
    }
    
    private var destinationChainSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("To Chain")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            chainSelector(
                selection: $ibcService.selectedDestinationChain,
                chains: ibcService.selectedSourceChain.availableDestinations
            )
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
        }
    }
    
    private func chainSelector(
        selection: Binding<IBCService.CosmosChain>,
        chains: [IBCService.CosmosChain]
    ) -> some View {
        Menu {
            ForEach(chains) { chain in
                Button(action: { selection.wrappedValue = chain }) {
                    HStack {
                        Image(systemName: chain.icon)
                        Text(chain.displayName)
                        if selection.wrappedValue == chain {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Circle()
                    .fill(selection.wrappedValue.color)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: selection.wrappedValue.icon)
                            .font(.caption)
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading) {
                    Text(selection.wrappedValue.displayName)
                        .fontWeight(.medium)
                    Text(selection.wrappedValue.chainId)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var recipientSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recipient Address")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                TextField(
                    "\(ibcService.selectedDestinationChain.bech32Prefix)1...",
                    text: $recipientAddress
                )
                .textFieldStyle(.plain)
                
                if !recipientAddress.isEmpty {
                    Button(action: { recipientAddress = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                Button(action: pasteAddress) {
                    Image(systemName: "doc.on.clipboard")
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            
            if !recipientAddress.isEmpty && !recipientAddress.hasPrefix(ibcService.selectedDestinationChain.bech32Prefix) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Address should start with '\(ibcService.selectedDestinationChain.bech32Prefix)'")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }
    
    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Amount")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                TextField("0.0", text: $amount)
                    .textFieldStyle(.plain)
                    .font(.title2)
                
                Spacer()
                
                Text(ibcService.selectedSourceChain.nativeSymbol)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Button("MAX") {
                    amount = "100.0"
                }
                .font(.caption)
                .foregroundColor(.purple)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
        }
    }
    
    private var memoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Memo (Optional)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(memo.count)/256")
                    .font(.caption)
                    .foregroundColor(memo.count > 256 ? .red : .secondary)
            }
            
            TextField("Add a memo for this transfer", text: $memo)
                .textFieldStyle(.plain)
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
        }
    }
    
    private var feeSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Estimated Fee")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("~0.005 \(ibcService.selectedSourceChain.nativeSymbol)")
                    .font(.subheadline)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("Est. Time")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("~30 seconds")
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }
    
    private var transferButton: some View {
        Button(action: { confirmTransfer = true }) {
            HStack {
                if ibcService.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "arrow.left.arrow.right")
                    Text("Transfer via IBC")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isValidInput ? Color.purple : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(!isValidInput || ibcService.isLoading)
    }
    
    private var activeTransfersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Active Transfers")
                    .font(.headline)
                Spacer()
                Button("Clear Completed") {
                    ibcService.clearCompletedTransfers()
                }
                .font(.caption)
                .foregroundColor(.purple)
            }
            
            ForEach(ibcService.activeTransfers) { transfer in
                IBCTransferCard(transfer: transfer) {
                    Task { try? await ibcService.trackTransfer(id: transfer.id) }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(16)
    }
    
    private var settingsSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Timeout")) {
                    Picker("Timeout", selection: $timeoutMinutes) {
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                    }
                    .pickerStyle(.segmented)
                }
                
                Section(header: Text("Available Routes")) {
                    ForEach(IBCService.CosmosChain.allCases) { chain in
                        HStack {
                            Circle()
                                .fill(chain.color)
                                .frame(width: 20, height: 20)
                            Text(chain.displayName)
                            Spacer()
                            Text("\(chain.availableDestinations.count) routes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("IBC Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSettings = false }
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var isValidInput: Bool {
        !amount.isEmpty &&
        Double(amount) != nil &&
        Double(amount)! > 0 &&
        !recipientAddress.isEmpty &&
        recipientAddress.hasPrefix(ibcService.selectedDestinationChain.bech32Prefix) &&
        ibcService.selectedSourceChain != ibcService.selectedDestinationChain &&
        memo.count <= 256
    }
    
    private var formattedAmount: String {
        guard let value = Double(amount) else { return "0" }
        return String(format: "%.6f", value)
    }
    
    // MARK: - Actions
    
    private func swapChains() {
        let temp = ibcService.selectedSourceChain
        if ibcService.selectedDestinationChain.availableDestinations.contains(temp) {
            ibcService.selectedSourceChain = ibcService.selectedDestinationChain
            ibcService.selectedDestinationChain = temp
        }
    }
    
    private func pasteAddress() {
        #if os(macOS)
        if let string = NSPasteboard.general.string(forType: .string) {
            recipientAddress = string
        }
        #endif
    }
    
    private func executeTransfer() async {
        guard let amountValue = Double(amount) else { return }
        
        let amountMicro = String(Int(amountValue * 1_000_000))
        
        let request = IBCService.IBCTransferRequest(
            sourceChain: ibcService.selectedSourceChain,
            destinationChain: ibcService.selectedDestinationChain,
            denom: ibcService.selectedSourceChain.nativeDenom,
            amount: amountMicro,
            sender: senderAddress,
            receiver: recipientAddress,
            memo: memo.isEmpty ? nil : memo,
            timeoutMinutes: timeoutMinutes
        )
        
        do {
            let transfer = try await ibcService.executeTransfer(request: request)
            print("IBC Transfer initiated: \(transfer.id)")
            showActiveTransfers = true
            amount = ""
            memo = ""
            recipientAddress = ""
        } catch {
            ibcService.error = error.localizedDescription
        }
    }
}

// MARK: - IBC Transfer Card

struct IBCTransferCard: View {
    let transfer: IBCService.IBCTransfer
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(transfer.sourceChain.color)
                    .frame(width: 20, height: 20)
                Text(transfer.sourceChain.displayName)
                    .font(.subheadline)
                
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                
                Circle()
                    .fill(transfer.destinationChain.color)
                    .frame(width: 20, height: 20)
                Text(transfer.destinationChain.displayName)
                    .font(.subheadline)
                
                Spacer()
                
                IBCStatusBadge(status: transfer.status)
            }
            
            HStack {
                Text("\(transfer.formattedAmount) \(transfer.symbol)")
                    .font(.headline)
                
                Spacer()
                
                if !transfer.status.isFinal {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                }
            }
            
            if !transfer.status.isFinal {
                ProgressView(value: transferProgress)
                    .progressViewStyle(.linear)
                    .tint(.purple)
            }
            
            HStack {
                if let txHash = transfer.sourceTxHash {
                    Text(String(txHash.prefix(12)) + "...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(transfer.initiatedAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var transferProgress: Double {
        let elapsed = Date().timeIntervalSince(transfer.initiatedAt)
        let total = transfer.timeoutAt.timeIntervalSince(transfer.initiatedAt)
        return min(elapsed / total, 1.0)
    }
}

// MARK: - IBC Status Badge

struct IBCStatusBadge: View {
    let status: IBCService.IBCStatus
    
    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.2))
            .foregroundColor(status.color)
            .cornerRadius(4)
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    NavigationView {
        IBCTransferView()
    }
}
#endif
#endif
#endif
