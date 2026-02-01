import SwiftUI

/// Main multisig wallet management view
struct MultisigView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var multisigManager = MultisigManager.shared
    @State private var showCreateWallet = false
    @State private var selectedWallet: MultisigConfig?
    @State private var showAddKey = false
    @State private var showCreatePSBT = false
    @State private var showImportPSBT = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            if multisigManager.wallets.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Wallets
                        walletsSection
                        
                        // Pending PSBTs
                        if !multisigManager.pendingPSBTs.isEmpty {
                            pendingPSBTsSection
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 600, idealWidth: 650, minHeight: 500, idealHeight: 550)
        .sheet(isPresented: $showCreateWallet) {
            CreateMultisigSheet { name, m, n, testnet in
                let _ = multisigManager.createWallet(
                    name: name,
                    requiredSignatures: m,
                    totalSigners: n,
                    isTestnet: testnet
                )
                showCreateWallet = false
            } onCancel: {
                showCreateWallet = false
            }
        }
        .sheet(isPresented: $showAddKey) {
            if let wallet = selectedWallet {
                AddPublicKeySheet(wallet: wallet) { pubKey in
                    do {
                        try multisigManager.addPublicKey(pubKey, to: wallet.id)
                        showAddKey = false
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                } onCancel: {
                    showAddKey = false
                }
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
    
    private var headerView: some View {
        HStack {
            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            
            Spacer()
            
            Text("Multisig Wallets")
                .font(.headline)
            
            Spacer()
            
            Button {
                showCreateWallet = true
            } label: {
                Label("New Wallet", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            
            Text("No Multisig Wallets")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Create a multisig wallet to require multiple signatures for transactions. Great for shared funds or extra security.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                showCreateWallet = true
            } label: {
                Label("Create Multisig Wallet", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var walletsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Wallets")
                .font(.headline)
            
            ForEach(multisigManager.wallets) { wallet in
                MultisigWalletCard(wallet: wallet) {
                    selectedWallet = wallet
                    showAddKey = true
                } onDelete: {
                    multisigManager.deleteWallet(wallet)
                }
            }
        }
    }
    
    private var pendingPSBTsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pending Transactions")
                .font(.headline)
            
            ForEach(multisigManager.pendingPSBTs) { psbt in
                PSBTCard(psbt: psbt) {
                    // Sign action
                } onExport: {
                    // Export action
                    let exported = multisigManager.exportPSBT(psbt)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(exported, forType: .string)
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct MultisigWalletCard: View {
    let wallet: MultisigConfig
    let onAddKey: () -> Void
    let onDelete: () -> Void
    
    @State private var showDeleteConfirm = false
    @State private var expanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(wallet.name)
                            .font(.headline)
                        
                        Text(wallet.description)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                        
                        if wallet.isTestnet {
                            Text("Testnet")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                    
                    if let address = wallet.address {
                        Text(address)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                
                Spacer()
                
                // Status
                if wallet.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("\(wallet.publicKeys.count)/\(wallet.totalSigners) keys")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                
                Button {
                    withAnimation { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
            }
            
            // Expanded content
            if expanded {
                Divider()
                
                // Public keys
                VStack(alignment: .leading, spacing: 8) {
                    Text("Signers (\(wallet.publicKeys.count)/\(wallet.totalSigners))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ForEach(Array(wallet.publicKeys.enumerated()), id: \.offset) { index, pubKey in
                        HStack {
                            Text("Signer \(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Text(pubKey.prefix(16) + "..." + pubKey.suffix(8))
                                .font(.system(.caption, design: .monospaced))
                            
                            Spacer()
                            
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(pubKey, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Add key button
                    if !wallet.isComplete {
                        Button {
                            onAddKey()
                        } label: {
                            Label("Add Signer Key", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                
                Divider()
                
                // Actions
                HStack {
                    if wallet.isComplete {
                        Button {
                            if let address = wallet.address {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(address, forType: .string)
                            }
                        } label: {
                            Label("Copy Address", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Spacer()
                    
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
        .confirmationDialog("Delete Wallet?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete the multisig wallet configuration. Make sure you have backups of all public keys.")
        }
    }
}

struct PSBTCard: View {
    let psbt: PSBT
    let onSign: () -> Void
    let onExport: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Transaction")
                        .font(.headline)
                    
                    PSBTStatusBadge(status: psbt.status)
                }
                
                Text("\(psbt.amount) sats to \(psbt.recipient.prefix(16))...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("\(psbt.signatureCount) signature(s)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button("Sign") { onSign() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(psbt.status == .readyToBroadcast)
                
                Button("Export") { onExport() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(10)
    }
}

struct PSBTStatusBadge: View {
    let status: PSBT.PSBTStatus
    
    var body: some View {
        Text(statusText)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }
    
    private var statusText: String {
        switch status {
        case .pending: return "Pending"
        case .partiallySign: return "Partial"
        case .readyToBroadcast: return "Ready"
        case .broadcast: return "Broadcast"
        case .failed: return "Failed"
        }
    }
    
    private var backgroundColor: Color {
        switch status {
        case .pending: return .gray.opacity(0.15)
        case .partiallySign: return .orange.opacity(0.15)
        case .readyToBroadcast: return .green.opacity(0.15)
        case .broadcast: return .blue.opacity(0.15)
        case .failed: return .red.opacity(0.15)
        }
    }
    
    private var foregroundColor: Color {
        switch status {
        case .pending: return .gray
        case .partiallySign: return .orange
        case .readyToBroadcast: return .green
        case .broadcast: return .blue
        case .failed: return .red
        }
    }
}

struct CreateMultisigSheet: View {
    let onCreate: (String, Int, Int, Bool) -> Void
    let onCancel: () -> Void
    
    @State private var name = ""
    @State private var requiredSigs = 2
    @State private var totalSigners = 3
    @State private var isTestnet = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                
                Spacer()
                
                Text("Create Multisig Wallet")
                    .font(.headline)
                
                Spacer()
                
                Button("Create") {
                    onCreate(name, requiredSigs, totalSigners, isTestnet)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || requiredSigs > totalSigners)
            }
            .padding()
            
            Divider()
            
            Form {
                Section("Wallet Name") {
                    TextField("e.g., Family Savings", text: $name)
                }
                
                Section("Signature Scheme") {
                    Stepper("Required Signatures: \(requiredSigs)", value: $requiredSigs, in: 1...totalSigners)
                    Stepper("Total Signers: \(totalSigners)", value: $totalSigners, in: 2...15)
                    
                    Text("\(requiredSigs)-of-\(totalSigners): Requires \(requiredSigs) out of \(totalSigners) people to sign")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section("Network") {
                    Toggle("Testnet (for testing)", isOn: $isTestnet)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 400, height: 400)
    }
}

struct AddPublicKeySheet: View {
    let wallet: MultisigConfig
    let onAdd: (String) -> Void
    let onCancel: () -> Void
    
    @State private var publicKey = ""
    @State private var signerName = ""
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                
                Spacer()
                
                Text("Add Signer Key")
                    .font(.headline)
                
                Spacer()
                
                Button("Add") {
                    onAdd(publicKey.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .buttonStyle(.borderedProminent)
                .disabled(publicKey.isEmpty)
            }
            .padding()
            
            Divider()
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Adding signer \(wallet.publicKeys.count + 1) of \(wallet.totalSigners)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Public Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextEditor(text: $publicKey)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3))
                        )
                    
                    Text("Enter a 33-byte compressed public key (66 hex characters starting with 02 or 03)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                Button {
                    if let clipboard = NSPasteboard.general.string(forType: .string) {
                        publicKey = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            Spacer()
        }
        .frame(width: 450, height: 350)
    }
}

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    MultisigView()
}
#endif
#endif
#endif
